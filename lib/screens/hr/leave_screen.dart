import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_shake.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, this.initialTab = 0});

  /// 0 = balance, 1 = request form, 2 = mine, 3 = approve.
  final int initialTab;

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
                  _LeaveMineTab(revision: _mineRevision),
                  if (canApprove) const _LeaveApprovalTab(),
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
            for (final b in list) _BalanceCard(row: b),
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
  int? _typeId;
  final _typeShake = GlobalKey<NxShakeState>();
  final _rangeShake = GlobalKey<NxShakeState>();
  final _reason = TextEditingController();
  DateTimeRange? _range;
  List<({List<int> bytes, String name})> _files = [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await context.read<AppConfig>().apiClient.getLeaveTypes();
      if (mounted) {
        setState(() {
          _types = types;
          _typeId = types.isNotEmpty ? int.tryParse(types.first['id']?.toString() ?? '') : null;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
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
      initialDateRange: _range ?? DateTimeRange(start: now, end: now.add(const Duration(days: 1))),
    );
    if (r != null) setState(() => _range = r);
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
        setState(() => _files = []);
        widget.onSubmitted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const NxSkeletonForm(fields: 5);
    if (_error != null && _types.isEmpty) {
      return NxErrorRetry(error: _error!, onRetry: _loadTypes);
    }
    return ListView(
      padding: NxBreakpoint.of(context).scrollPadding(context),
      children: [
        NxSurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            children: [
              NxShake(
                key: _typeShake,
                child: DropdownButtonFormField<int>(
        icon: const Icon(NxI.caretDown, size: 18),
                value: _typeId,
                decoration: InputDecoration(label: nxRequiredLabel(context, tr('ประเภท'))),
                items: _types
                    .map(
                      (e) => DropdownMenuItem(
                        value: int.tryParse(e['id']?.toString() ?? ''),
                        child: Text(tr(e['name']?.toString() ?? '')),
                      ),
                    )
                    .where((e) => e.value != null)
                    .toList(),
                onChanged: (v) => setState(() => _typeId = v),
              ),
              ),
              const SizedBox(height: 12),
              NxShake(
                key: _rangeShake,
                child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: nxRequiredLabel(context, tr('ช่วงวันที่')),
                subtitle: Text(
                  tr(_range == null
                      ? 'แตะเพื่อเลือก'
                      : '${_range!.start.day}/${_range!.start.month} – ${_range!.end.day}/${_range!.end.month}'),
                ),
                trailing: const Icon(NxI.calendarBlank),
                onTap: _pickRange,
              ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                decoration: InputDecoration(labelText: tr('เหตุผล')),
                maxLines: 3,
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
                    label: Text(tr('แนบไฟล์ (เช่น ใบรับรองแพทย์)')),
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
              const SizedBox(height: 16),
              NxHeroCta(
                label: 'ส่งคำขอ',
                busy: _saving,
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeaveMineTab extends StatefulWidget {
  const _LeaveMineTab({required this.revision});
  final int revision;

  @override
  State<_LeaveMineTab> createState() => _LeaveMineTabState();
}

class _LeaveMineTabState extends State<_LeaveMineTab> {
  NxListQuery _lq = const NxListQuery();

  var _local = 0;

  Future<void> _cancel(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ยกเลิกคำขอลา?')),
        content: Text(tr('${p['leave_type_name'] ?? 'ลา'} ${p['start_date'] ?? ''} – ${p['end_date'] ?? ''}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ไม่'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ยกเลิกคำขอ'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.cancelLeave(p['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ยกเลิกคำขอลาแล้ว'))));
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
        final list = nxApplyLocalQuery<Map<String, dynamic>>(
          all,
          _lq,
          text: (p) => '${p['leave_type_name'] ?? ''} ${p['reason'] ?? ''}',
          filters: {
            'status': (p, v) => v.contains('${p['status'] ?? ''}'),
            'month': (p, v) {
              final m = '${p['start_date'] ?? ''}'.length >= 7 ? '${p['start_date']}'.substring(0, 7) : '';
              return (v.contains('this') && m == thisMonth) ||
                  (v.contains('last') && m == lastMonth) ||
                  (v.contains('year') && m.startsWith('${now.year}'));
            },
          },
          sorts: {
            'new': (a, b) => '${b['start_date'] ?? ''}'.compareTo('${a['start_date'] ?? ''}'),
            'old': (a, b) => '${a['start_date'] ?? ''}'.compareTo('${b['start_date'] ?? ''}'),
          },
        );
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
  const _LeaveRequestCard({required this.row, this.onCancel, this.trailing, this.editableFiles = false});
  final Map<String, dynamic> row;

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
    String d(dynamic v) => (v?.toString() ?? '').split('T').first;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
    final used = num.tryParse(row['used_days']?.toString() ?? '') ?? 0;
    final total = num.tryParse(row['total_days']?.toString() ?? '') ?? 0;
    final left = total - used;
    final ratio = total <= 0 ? 0.0 : (used / total).clamp(0, 1).toDouble();
    String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(tr(row['leave_type_name']?.toString() ?? ''), style: theme.textTheme.titleSmall)),
                Text(tr('คงเหลือ ${n(left < 0 ? 0 : left)} วัน'), style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ratio, minHeight: 8),
            ),
            const SizedBox(height: 4),
            Text(tr('ใช้ไป ${n(used)} จาก ${n(total)} วัน'), style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _LeaveApprovalTab extends StatefulWidget {
  const _LeaveApprovalTab();

  @override
  State<_LeaveApprovalTab> createState() => _LeaveApprovalTabState();
}

class _LeaveApprovalTabState extends State<_LeaveApprovalTab> {
  var _revision = 0;

  Future<void> _act(String id, bool approve) async {
    String? reason;
    if (!approve) {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('เหตุผลที่ไม่อนุมัติ')),
          content: TextField(controller: ctrl, autofocus: true, maxLines: 3, decoration: InputDecoration(hintText: tr('ไม่บังคับ'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('ไม่อนุมัติ'))),
          ],
        ),
      );
      ctrl.dispose();
      if (reason == null || !mounted) return;
    }
    try {
      await context.read<AppConfig>().apiClient.approveLeave(id, approve: approve, reason: reason);
      if (mounted) setState(() => _revision++);
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
            for (final p in pending)
              _LeaveRequestCard(
                row: p,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(NxI.checkCircle, color: Colors.green),
                      onPressed: () => _act(p['id'].toString(), true),
                    ),
                    IconButton(
                      icon: const Icon(NxI.xCircle, color: Colors.red),
                      onPressed: () => _act(p['id'].toString(), false),
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
