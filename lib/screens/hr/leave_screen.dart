import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/menu_access.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../core/thai_time.dart';
import '../../core/leave_suggest.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_shake.dart';

/// Tab index of `/hr/leave?tab=` (`balance` | `request` | `mine` | `approve`).
int leaveTabIndex(String? tab) {
  switch (tab) {
    case 'request':
      return 1;
    case 'mine':
      return 2;
    case 'approve':
      return 3;
    default:
      return 0;
  }
}

/// Moves the request [focusId] to the top of [rows] (opened from a notification).
List<Map<String, dynamic>> leaveFocusFirst(List<Map<String, dynamic>> rows, String? focusId) {
  if (focusId == null || focusId.isEmpty) return rows;
  final i = rows.indexWhere((r) => '${r['id']}' == focusId);
  if (i <= 0) return rows;
  return [rows[i], ...rows.sublist(0, i), ...rows.sublist(i + 1)];
}

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, this.initialTab = 0, this.focusId});

  /// 0 = balance, 1 = request form, 2 = mine, 3 = approve.
  final int initialTab;

  /// Leave request a notification is about: shown first and outlined.
  final String? focusId;

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  var _mineRevision = 0;

  @override
  Widget build(BuildContext context) {
    final canApprove = MenuAccess.allow(
      context.select((AppConfig c) => c.session),
      MenuAccess.leaveManagement,
    );
    final tabCount = canApprove ? 4 : 3;
    return DefaultTabController(
      length: tabCount,
      initialIndex: widget.initialTab.clamp(0, tabCount - 1),
      child: NxScrollScaffold(
        header: const NxAppHeader(title: 'การลา'),
        body: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelPadding: const EdgeInsets.symmetric(horizontal: 20),
              tabs: [
                const Tab(text: 'คงเหลือ'),
                const Tab(text: 'ยื่นคำขอ'),
                const Tab(text: 'ของฉัน'),
                if (canApprove) const Tab(text: 'อนุมัติ'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _LeaveBalanceTab(),
                  _LeaveRequestTab(onSubmitted: () => setState(() => _mineRevision++)),
                  _LeaveMineTab(revision: _mineRevision, focusId: widget.focusId),
                  if (canApprove) _LeaveApprovalTab(focusId: widget.focusId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaveBalanceTab extends StatelessWidget {
  const _LeaveBalanceTab();

  @override
  Widget build(BuildContext context) {
    return NxCachedFuture<List<Map<String, dynamic>>>(
      load: () => context.read<AppConfig>().apiClient.getLeaveBalance(),
      skeleton: const NxSkeletonList(rows: 4),
      isEmpty: (list) => list.isEmpty,
      empty: Center(child: Text(tr('ไม่มีข้อมูลสิทธิ์ลา'))),
      builder: (context, list) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: NxBreakpoint.of(context).scrollPadding(context),
          children: [
            LayoutBuilder(builder: (context, c) {
              const gap = 10.0;
              final cols = c.maxWidth >= 640 ? 3 : 2;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(spacing: gap, runSpacing: gap, children: [
                for (final b in list) SizedBox(width: w, child: _BalanceCard(row: b)),
              ]);
            }),
          ],
        );
      },
    );
  }
}

class _LeaveRequestTab extends StatefulWidget {
  const _LeaveRequestTab({required this.onSubmitted});
  final VoidCallback onSubmitted;

  @override
  State<_LeaveRequestTab> createState() => _LeaveRequestTabState();
}

class _LeaveRequestTabState extends State<_LeaveRequestTab> {
  List<Map<String, dynamic>> _types = [];
  Map<int, num> _remaining = {};
  List<Map<String, dynamic>> _mine = [];
  int? _typeId;
  int? _suggestedTypeId;
  final _typeShake = GlobalKey<NxShakeState>();
  final _rangeShake = GlobalKey<NxShakeState>();
  final _reason = TextEditingController();
  DateTimeRange? _range;
  bool _rangeTouched = false;
  List<({List<int> bytes, String name})> _files = [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final types = await api.getLeaveTypes();
      // Balance + my requests only sharpen the suggestion; the form works without them.
      final extra = await Future.wait<List<Map<String, dynamic>>>([
        api.getLeaveBalance().catchError((_) => <Map<String, dynamic>>[]),
        api.getLeaveRequests().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      final remaining = leaveRemainingByType(extra[0]);
      final suggested = suggestLeaveTypeId(types, remaining, extra[1]);
      setState(() {
        _types = types;
        _remaining = remaining;
        _mine = extra[1];
        _suggestedTypeId = suggested;
        _typeId = suggested;
        _range = defaultLeaveRange(leaveKindOf(_typeById(suggested)));
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  Map<String, dynamic>? _typeById(int? id) {
    for (final t in _types) {
      if (int.tryParse(t['id']?.toString() ?? '') == id) return t;
    }
    return null;
  }

  LeaveKind get _kind => leaveKindOf(_typeById(_typeId));

  void _pickType(int id) {
    setState(() {
      _typeId = id;
      // Untouched dates follow the type (sick = today, others = next working day).
      if (!_rangeTouched) _range = defaultLeaveRange(leaveKindOf(_typeById(id)));
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final now = thaiNow();
    final r = await showDateRangePicker(
      switchToInputEntryModeIcon: const Icon(NxI.pencilSimple),
      switchToCalendarEntryModeIcon: const Icon(NxI.calendarBlank),
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range ?? defaultLeaveRange(_kind),
    );
    if (r != null) {
      setState(() {
        _range = r;
        _rangeTouched = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_typeId == null || _range == null) {
      // Point at what's missing: scroll there, shake it, short vibration.
      nxShakeField(_typeId == null ? _typeShake : _rangeShake);
      if (_typeId == null && _range == null) _rangeShake.currentState?.shake(haptic: false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เลือกประเภทลาและวันที่'))));
      return;
    }
    setState(() => _saving = true);
    final api = context.read<AppConfig>().apiClient;
    try {
      final created = await api.postLeaveRequest(
            leaveTypeId: _typeId!,
            startDate: _ymd(_range!.start),
            endDate: _ymd(_range!.end),
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
      var note = 'ส่งคำขอลาแล้ว';
      final id = (asStringKeyedMap(created['request'])?['id'] ?? created['id'])?.toString();
      if (_files.isNotEmpty && id != null) {
        try {
          await api.uploadLeaveAttachments(id, _files);
        } catch (e) {
          note = 'ส่งคำขอลาแล้ว แต่แนบไฟล์ไม่สำเร็จ (${formatApiError(e)}) — แนบเพิ่มได้ที่แท็บ "ของฉัน"';
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(note))));
        _reason.clear();
        setState(() {
          _files = [];
          _rangeTouched = false;
        });
        widget.onSubmitted();
        _loadTypes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _section(BuildContext context, String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Expanded(child: nxRequiredLabel(context, tr(title))),
          ?trailing,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const NxSkeletonForm(fields: 5);
    if (_error != null && _types.isEmpty) {
      return NxErrorRetry(error: _error!, onRetry: _loadTypes);
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kind = _kind;
    final range = _range;
    final days = range == null ? 0 : leaveDays(range);
    final left = _typeId == null ? null : _remaining[_typeId!];
    final after = left == null ? null : left - days;
    final overlap = range == null ? null : overlappingLeave(range, _mine);
    final presets = leaveDatePresets();
    String dShort(DateTime d) => thaiDate(d, year: uiYear);
    return ListView(
      key: const ValueKey('leave-request-form'),
      padding: NxBreakpoint.of(context).scrollPadding(context),
      children: [
        // ── Leave type: cards with days left, suggested one marked.
        NxShake(
          key: _typeShake,
          child: _section(context, 'ประเภทการลา'),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _types)
              if (int.tryParse(t['id']?.toString() ?? '') case final int id)
                _LeaveTypeChip(
                  key: ValueKey('leave-type-$id'),
                  label: t['name']?.toString() ?? '',
                  kind: leaveKindOf(t),
                  remaining: _remaining[id],
                  selected: id == _typeId,
                  suggested: id == _suggestedTypeId,
                  onTap: () => _pickType(id),
                ),
          ],
        ),
        const SizedBox(height: 18),
        // ── Dates: quick picks + the chosen range.
        NxShake(key: _rangeShake, child: _section(context, 'วันที่ลา')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: ValueKey('leave-date-${p.id}'),
                  label: Text(tr(p.label)),
                  selected: range != null && leaveDays(range) == leaveDays(p.range) && DateUtils.isSameDay(range.start, p.range.start),
                  onSelected: (_) => setState(() {
                    _range = p.range;
                    _rangeTouched = true;
                  }),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        NxSurfaceCard(
          key: const ValueKey('leave-range-card'),
          onTap: _pickRange,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            _DateBlock(date: range?.start, label: 'เริ่ม'),
            Expanded(
              child: Column(children: [
                Text(tr(days > 0 ? '$days วัน' : '—'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                Icon(NxI.arrowRight, size: 16, color: cs.onSurfaceVariant),
              ]),
            ),
            _DateBlock(date: range?.end, label: 'ถึง'),
            const SizedBox(width: 8),
            Icon(NxI.calendarBlank, color: cs.onSurfaceVariant),
          ]),
        ),
        const SizedBox(height: 18),
        // ── Reason with suggestions for this kind.
        Text(tr('เหตุผล'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in leaveReasonSuggestions(kind))
              ActionChip(
                key: ValueKey('leave-reason-$r'),
                avatar: const Icon(NxI.sparkle, size: 14),
                label: Text(tr(r)),
                onPressed: () {
                  _reason.text = r;
                  _reason.selection = TextSelection.collapsed(offset: r.length);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          decoration: InputDecoration(hintText: tr('เพิ่มรายละเอียด (ไม่บังคับ)')),
          minLines: 2,
          maxLines: 4,
        ),
        if (context.select((AppConfig c) => c.serverInfo)?.has('leave_attachments') ?? false) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving || _files.length >= 5
                  ? null
                  : () async {
                      final picked = await pickLeaveFiles(max: 5 - _files.length);
                      if (picked.isNotEmpty && mounted) setState(() => _files = [..._files, ...picked]);
                    },
              icon: const Icon(NxI.paperclip, size: 18),
              label: Text(tr(kind == LeaveKind.sick ? 'แนบใบรับรองแพทย์' : 'แนบไฟล์')),
            ),
          ),
          if (_files.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in _files)
                  InputChip(
                    deleteIcon: const Icon(NxI.x, size: 16),
                    label: Text(tr(f.name), overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _files = _files.where((x) => !identical(x, f)).toList()),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 14),
        // ── Summary before sending.
        if (range != null && _typeId != null)
          _LeaveSummary(
            key: const ValueKey('leave-summary'),
            typeName: _typeById(_typeId)?['name']?.toString() ?? '',
            rangeText: days == 1 ? dShort(range.start) : '${dShort(range.start)} – ${dShort(range.end)}',
            days: days,
            leftAfter: after == null ? null : _n(after),
            overBalance: after != null && after < 0,
            overlap: overlap == null
                ? null
                : 'ซ้อนกับคำขอ${overlap['leave_type_name'] ?? 'ลา'} ${thaiDate(overlap['start_date'], year: uiYear)} (${leaveStatusStyle(overlap['status']?.toString(), cs).$1})',
            certificateHint: leaveNeedsCertificateHint(kind, days) && _files.isEmpty,
          ),
        const SizedBox(height: 16),
        NxHeroCta(
          label: 'ส่งคำขอ',
          busy: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

IconData _leaveKindIcon(LeaveKind k) => switch (k) {
      LeaveKind.sick => NxI.heartbeat,
      LeaveKind.personal => NxI.briefcase,
      LeaveKind.vacation => NxI.sun,
      LeaveKind.maternity => NxI.baby,
      LeaveKind.ordination => NxI.flower,
      LeaveKind.military => NxI.shield,
      LeaveKind.other => NxI.calendarCheck,
    };

Color _leaveKindColor(LeaveKind k) => switch (k) {
      LeaveKind.sick => const Color(0xFFEF4444),
      LeaveKind.personal => const Color(0xFF6366F1),
      LeaveKind.vacation => const Color(0xFFF59E0B),
      LeaveKind.maternity => const Color(0xFFEC4899),
      LeaveKind.ordination => const Color(0xFFF97316),
      LeaveKind.military => const Color(0xFF16A34A),
      LeaveKind.other => const Color(0xFF0EA5E9),
    };

class _LeaveTypeChip extends StatelessWidget {
  const _LeaveTypeChip({
    super.key,
    required this.label,
    required this.kind,
    required this.remaining,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });
  final String label;
  final LeaveKind kind;
  final num? remaining;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _leaveKindColor(kind);
    String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    final none = remaining != null && remaining! <= 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.12) : cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? color : cs.outlineVariant, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 14, backgroundColor: color.withValues(alpha: 0.16), child: Icon(_leaveKindIcon(kind), size: 15, color: color)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr(label), style: theme.textTheme.labelLarge?.copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                if (suggested) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(6)),
                    child: Text(tr('แนะนำ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onPrimary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              if (remaining != null)
                Text(
                  tr(none ? 'สิทธิ์หมดแล้ว' : 'เหลือ ${n(remaining!)} วัน'),
                  style: theme.textTheme.labelSmall?.copyWith(color: none ? cs.error : cs.onSurfaceVariant),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.date, required this.label});
  final DateTime? date;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const th = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
    final d = date;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(label), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      Text(d == null ? '—' : '${d.day}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.1)),
      Text(
        d == null ? '' : tr('${th[d.weekday - 1]} ${thaiDate(d, year: uiYear).replaceFirst(RegExp(r'^\d+\s*'), '')}'),
        style: theme.textTheme.labelSmall,
      ),
    ]);
  }
}

class _LeaveSummary extends StatelessWidget {
  const _LeaveSummary({
    super.key,
    required this.typeName,
    required this.rangeText,
    required this.days,
    required this.leftAfter,
    required this.overBalance,
    required this.overlap,
    required this.certificateHint,
  });
  final String typeName;
  final String rangeText;
  final int days;
  final String? leftAfter;
  final bool overBalance;
  final String? overlap;
  final bool certificateHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget note(IconData icon, String text, Color color) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(tr(text), style: theme.textTheme.bodySmall?.copyWith(color: color))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('สรุปคำขอ'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(tr('$typeName · $days วัน'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        Text(tr(rangeText), style: theme.textTheme.bodySmall),
        if (leftAfter != null)
          note(overBalance ? NxI.warning : NxI.checkCircle, overBalance ? 'เกินสิทธิ์คงเหลือ (คงเหลือหลังลา $leftAfter วัน)' : 'คงเหลือหลังลา $leftAfter วัน',
              overBalance ? cs.error : const Color(0xFF16A34A)),
        if (overlap != null) note(NxI.warning, overlap!, const Color(0xFFF59E0B)),
        if (certificateHint) note(NxI.paperclip, 'ลาป่วยตั้งแต่ 3 วันขึ้นไป ควรแนบใบรับรองแพทย์', cs.onSurfaceVariant),
      ]),
    );
  }
}

class _LeaveMineTab extends StatefulWidget {
  const _LeaveMineTab({required this.revision, this.focusId});
  final int revision;
  final String? focusId;

  @override
  State<_LeaveMineTab> createState() => _LeaveMineTabState();
}

class _LeaveMineTabState extends State<_LeaveMineTab> {
  NxListQuery _lq = const NxListQuery();

  var _local = 0;

  Future<void> _cancel(Map<String, dynamic> p) async {
    final cs = Theme.of(context).colorScheme;
    final st = '${p['status'] ?? ''}';
    final (stLabel, stColor) = leaveStatusStyle(st, cs);
    final ok = await showStatusChangeConfirm(
      context,
      title: 'ยกเลิกคำขอลา?',
      recordTitle: tr('${p['leave_type_name'] ?? 'ลา'} ${thaiDate(p['start_date'], year: uiYear)} – ${thaiDate(p['end_date'], year: uiYear)}'),
      from: st.isEmpty ? null : stLabel,
      fromColor: stColor,
      to: 'ยกเลิก',
      toColor: kNxDangerRed,
      impact: 'วันลาที่ขอไว้จะคืนกลับเข้าสิทธิ์',
      confirmLabel: 'ยกเลิกคำขอ',
    );
    if (ok == null || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.cancelLeave(p['id'].toString());
      if (!mounted) return;
      showNxStatusChangedSnack(ScaffoldMessenger.of(context), label: 'ยกเลิกคำขอลาแล้ว');
      setState(() => _local++);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NxCachedFuture<List<Map<String, dynamic>>>(
      revision: widget.revision + _local,
      load: () => context.read<AppConfig>().apiClient.getLeaveRequests(),
      skeleton: const NxSkeletonList(rows: 4),
      isEmpty: (list) => list.isEmpty,
      empty: Center(child: Text(tr('ยังไม่มีคำขอลา'))),
      builder: (context, all) {
        final now = thaiNow();
        String ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
        final thisMonth = ym(now);
        final lastMonth = ym(DateTime(now.year, now.month - 1));
        final list = leaveFocusFirst(nxApplyLocalQuery<Map<String, dynamic>>(
          all,
          _lq,
          text: (p) => '${p['leave_type_name'] ?? ''} ${p['reason'] ?? ''}',
          filters: {
            'status': (p, v) => v.contains('${p['status'] ?? ''}'),
            'month': (p, v) {
              final sd = parseThaiDate(p['start_date']);
              final m = sd == null ? '' : '${sd.year}-${sd.month.toString().padLeft(2, '0')}';
              return (v.contains('this') && m == thisMonth) ||
                  (v.contains('last') && m == lastMonth) ||
                  (v.contains('year') && m.startsWith('${now.year}'));
            },
          },
          sorts: {
            'new': (a, b) => '${b['start_date'] ?? ''}'.compareTo('${a['start_date'] ?? ''}'),
            'old': (a, b) => '${a['start_date'] ?? ''}'.compareTo('${b['start_date'] ?? ''}'),
          },
        ), widget.focusId);
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: NxBreakpoint.of(context).scrollPadding(context),
          children: [
            NxListToolbar(
              query: _lq,
              liveSearch: true,
              showSearch: all.length > 5,
              padding: const EdgeInsets.only(bottom: 8),
              searchHint: 'ค้นหาประเภท / เหตุผล',
              quickGroup: 'status',
              resultCount: list.length,
              groups: const [
                NxFilterGroup(key: 'status', label: 'สถานะ', options: [
                  NxFilterOption('Pending', 'รออนุมัติ'),
                  NxFilterOption('Approved', 'อนุมัติแล้ว'),
                  NxFilterOption('Rejected', 'ไม่อนุมัติ'),
                  NxFilterOption('Cancelled', 'ยกเลิกแล้ว'),
                ]),
                NxFilterGroup(key: 'month', label: 'ช่วงเดือน', multi: false, options: [
                  NxFilterOption('this', 'เดือนนี้'),
                  NxFilterOption('last', 'เดือนที่แล้ว'),
                  NxFilterOption('year', 'ปีนี้'),
                ]),
              ],
              sorts: const [NxSortOption('new', 'วันที่ลาล่าสุด'), NxSortOption('old', 'วันที่ลาเก่าสุด')],
              onChanged: (q) => setState(() => _lq = q),
            ),
            for (final p in list)
              _LeaveRequestCard(
                row: p,
                focused: widget.focusId != null && '${p['id']}' == widget.focusId,
                onCancel: p['status']?.toString() == 'Pending' ? () => _cancel(p) : null,
                editableFiles: p['status']?.toString() == 'Pending',
              ),
          ],
        );
      },
    );
  }
}

/// Thai label + color for a NEXTX leave status.
(String, Color) leaveStatusStyle(String? status, ColorScheme cs) {
  switch (status) {
    case 'Approved':
      return ('อนุมัติแล้ว', const Color(0xFF16A34A));
    case 'Rejected':
      return ('ไม่อนุมัติ', cs.error);
    case 'Cancelled':
      return ('ยกเลิกแล้ว', cs.outline);
    case 'Pending':
      return ('รออนุมัติ', const Color(0xFFF59E0B));
    default:
      return (status ?? '—', cs.outline);
  }
}

class _LeaveRequestCard extends StatelessWidget {
  const _LeaveRequestCard({required this.row, this.onCancel, this.trailing, this.editableFiles = false, this.focused = false});
  final Map<String, dynamic> row;

  /// The request a tapped notification is about.
  final bool focused;

  /// The requester's own Pending request: may add / remove files.
  final bool editableFiles;
  final VoidCallback? onCancel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = leaveStatusStyle(row['status']?.toString(), theme.colorScheme);
    final who = row['user_name']?.toString();
    final reason = row['reason']?.toString() ?? '';
    final reject = row['reject_reason']?.toString() ?? '';
    String d(dynamic v) => thaiDate(v, year: uiYear);
    final start = parseThaiDate(row['start_date']);
    const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
    return Card(
      key: ValueKey('leave-card-${row['id']}${focused ? '-focused' : ''}'),
      margin: const EdgeInsets.only(bottom: 10),
      shape: focused
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius), side: BorderSide(color: theme.colorScheme.primary, width: 1.6))
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date badge (start day) tinted by status.
            Container(
              width: 46,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text(start == null ? '—' : '${start.day}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color, height: 1.1)),
                Text(start == null ? '' : tr(months[start.month - 1]), style: theme.textTheme.labelSmall?.copyWith(color: color)),
              ]),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tr(who != null && who.isNotEmpty ? who : (row['leave_type_name']?.toString() ?? 'ลา')),
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                        child: Text(tr(label), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr([
                      if (who != null && who.isNotEmpty) row['leave_type_name']?.toString() ?? '',
                      '${d(row['start_date'])} – ${d(row['end_date'])}',
                      if (row['days'] != null) '${row['days']} วัน',
                    ].where((e) => e.isNotEmpty).join(' · ')),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (reason.isNotEmpty) Text(tr('เหตุผล: $reason'), style: theme.textTheme.bodySmall),
                  if (reject.isNotEmpty)
                    Text(tr('เหตุผลที่ไม่อนุมัติ: $reject'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  LeaveAttachments(row: row, editable: editableFiles),
                ],
              ),
            ),
            if (onCancel != null) TextButton(onPressed: onCancel, child: Text(tr('ยกเลิก'))),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final used = num.tryParse(row['used_days']?.toString() ?? '') ?? 0;
    final total = num.tryParse(row['total_days']?.toString() ?? '') ?? 0;
    final left = (total - used) < 0 ? 0 : total - used;
    final ratio = total <= 0 ? 0.0 : (left / total).clamp(0, 1).toDouble();
    final kind = leaveKindOf(row);
    final color = _leaveKindColor(kind);
    String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return NxSurfaceCard(
      key: ValueKey('leave-balance-${row['leave_type_id']}'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_leaveKindIcon(kind), size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(tr(row['leave_type_name']?.toString() ?? ''), style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.14),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(n(left), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1)),
                Text(tr('วันคงเหลือ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: Text(tr('ใช้ไป ${n(used)} จาก ${n(total)} วัน'), style: theme.textTheme.bodySmall)),
      ]),
    );
  }
}

class _LeaveApprovalTab extends StatefulWidget {
  const _LeaveApprovalTab({this.focusId});
  final String? focusId;

  @override
  State<_LeaveApprovalTab> createState() => _LeaveApprovalTabState();
}

class _LeaveApprovalTabState extends State<_LeaveApprovalTab> {
  var _revision = 0;

  Future<void> _act(Map<String, dynamic> p, bool approve) async {
    final id = p['id'].toString();
    // Ask first; rejecting needs a reason (the server keeps it).
    final ok = await showStatusChangeConfirm(
      context,
      recordTitle: '${p['user_name'] ?? p['employee_name'] ?? ''} · ${tr('${p['leave_type_name'] ?? 'ลา'}')} ${thaiDate(p['start_date'], year: uiYear)} – ${thaiDate(p['end_date'], year: uiYear)}',
      from: 'รออนุมัติ',
      fromColor: const Color(0xFFF59E0B),
      to: approve ? 'อนุมัติ' : 'ไม่อนุมัติ',
      toColor: approve ? const Color(0xFF16A34A) : kNxDangerRed,
      impact: approve ? 'หักวันลาจากสิทธิ์ และแจ้งผู้ขอ' : 'ผู้ขอจะได้รับแจ้งว่าไม่อนุมัติ',
      requireReason: !approve,
      reasons: approve ? const [] : const ['ช่วงนี้งานเร่งด่วน', 'คนในทีมลาพร้อมกันหลายคน', 'สิทธิ์ลาไม่พอ', 'ขอเอกสารเพิ่มเติม'],
      confirmLabel: approve ? 'อนุมัติ' : 'ไม่อนุมัติ',
    );
    if (ok == null || !mounted) return;
    final reason = approve ? null : ok.note;
    try {
      await context.read<AppConfig>().apiClient.approveLeave(id, approve: approve, reason: reason);
      if (!mounted) return;
      showNxStatusChangedSnack(ScaffoldMessenger.of(context), label: approve ? 'อนุมัติแล้ว' : 'ไม่อนุมัติแล้ว');
      setState(() => _revision++);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NxCachedFuture<List<Map<String, dynamic>>>(
      revision: _revision,
      load: () => context.read<AppConfig>().apiClient.getLeaveRequests(all: true, status: 'Pending'),
      skeleton: const NxSkeletonList(rows: 4),
      isEmpty: (list) => list.isEmpty,
      empty: Center(child: Text(tr('ไม่มีคำขอรออนุมัติ'))),
      builder: (context, pending) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: NxBreakpoint.of(context).scrollPadding(context),
          children: [
            for (final p in leaveFocusFirst(pending, widget.focusId))
              _LeaveRequestCard(
                row: p,
                focused: widget.focusId != null && '${p['id']}' == widget.focusId,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(NxI.checkCircle, color: Colors.green),
                      onPressed: () => _act(p, true),
                    ),
                    IconButton(
                      icon: const Icon(NxI.xCircle, color: Colors.red),
                      onPressed: () => _act(p, false),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Images / PDF for a leave request (≤ 10 MB each — the server checks too).
Future<List<({List<int> bytes, String name})>> pickLeaveFiles({int max = 5}) async {
  final picked = await FilePicker.platform.pickFiles(
    withData: true,
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'heic', 'webp', 'pdf'],
  );
  return [
    for (final f in (picked?.files ?? const <PlatformFile>[]).take(max))
      if (f.bytes != null) (bytes: f.bytes!, name: f.name),
  ];
}

/// Files attached to a leave request; opened through the API (permission-checked, not public).
class LeaveAttachments extends StatefulWidget {
  const LeaveAttachments({super.key, required this.row, this.editable = false});

  final Map<String, dynamic> row;
  final bool editable;

  @override
  State<LeaveAttachments> createState() => _LeaveAttachmentsState();
}

class _LeaveAttachmentsState extends State<LeaveAttachments> {
  late List<Map<String, dynamic>> _files = extractMapList(widget.row['attachments']);
  bool _busy = false;

  String get _id => widget.row['id']?.toString() ?? '';

  Future<void> _run(Future<List<Map<String, dynamic>>> Function() f) async {
    setState(() => _busy = true);
    try {
      final next = await f();
      if (mounted) setState(() => _files = next);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> f) async {
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await api.downloadLeaveAttachment(f['url'].toString());
      await openFileBytes(bytes, f['name']?.toString() ?? 'file');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final canAdd = widget.editable && _files.length < 5 && (context.select((AppConfig c) => c.serverInfo)?.has('leave_attachments') ?? false);
    if (_files.isEmpty && !canAdd) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final f in _files)
            InputChip(
        deleteIcon: const Icon(NxI.x, size: 16),
              avatar: Icon((f['mime']?.toString() ?? '').startsWith('image/') ? NxI.image : NxI.file, size: 16),
              label: Text(tr(f['name']?.toString() ?? 'ไฟล์'), overflow: TextOverflow.ellipsis),
              onPressed: _busy ? null : () => _open(f),
              onDeleted: widget.editable && !_busy ? () => _run(() => api.removeLeaveAttachment(_id, f['id'].toString())) : null,
              deleteButtonTooltipMessage: 'เอาไฟล์ออก',
            ),
          if (canAdd)
            ActionChip(
              avatar: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.paperclip, size: 16),
              label: Text(tr('แนบไฟล์')),
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await pickLeaveFiles(max: 5 - _files.length);
                      if (picked.isNotEmpty) await _run(() => api.uploadLeaveAttachments(_id, picked));
                    },
            ),
        ],
      ),
    );
  }
}
