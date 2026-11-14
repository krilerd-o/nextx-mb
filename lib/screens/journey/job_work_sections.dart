import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/activity_guests.dart' show activityTypeLabel;
import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/journey_rules.dart';
import '../../core/status_labels.dart';
import '../../core/thai_time.dart';
import '../../core/entity_display.dart' show userDisplayName;
import '../../services/api_client.dart' show EntityListPage;
import '../../widgets/nx_icons.dart';
import 'journey_widgets.dart';

String _s(Object? v) {
  final t = '${v ?? ''}'.trim();
  return t == 'null' ? '' : t;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _dt(DateTime d) => '${d.day}/${d.month}/${uiYear(d.year)} ${_two(d.hour)}:${_two(d.minute)}';
String _hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Duration as "1 ชม. 15 นาที" / "45 นาที".
String jobDurationText(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return tr('ไม่ถึง 1 นาที');
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return tr('$r นาที');
  return r == 0 ? tr('$h ชม.') : tr('$h ชม. $r นาที');
}

/// Priority tone: urgent red, high amber, low slate, normal neutral.
Color jobPriorityColor(BuildContext context, Object? v) {
  final cs = Theme.of(context).colorScheme;
  return switch (_s(v).toLowerCase()) {
    'urgent' => const Color(0xFFDC2626),
    'high' => const Color(0xFFD97706),
    'low' => const Color(0xFF64748B),
    _ => cs.onSurfaceVariant,
  };
}

/// SLA chip from `GET /api/field-service/jobs/:id/sla`
/// (`{policy, response_due, resolve_due, breached_response, breached_resolve}`).
/// Null when the job has no SLA policy (no empty bar).
({String label, Color color, IconData icon})? jobSlaChip(Map<String, dynamic> sla, Map<String, dynamic> row, {DateTime? now}) {
  final policy = sla['policy'];
  if (policy is! Map) return null;
  final status = canonicalJobStatus(row['job_status']);
  if (status == 'Cancelled') return null;
  final name = _s(policy['name']);
  final resolve = parseThai(sla['resolve_due']);
  final response = parseThai(sla['response_due']);
  final accepted = _s(row['accepted_at']).isNotEmpty || status == 'In Progress' || status == 'Completed';
  if (status == 'Completed') return (label: 'SLA ${name.isEmpty ? '' : '$name · '}${tr('ปิดงานแล้ว')}'.trim(), color: const Color(0xFF16A34A), icon: NxI.checkCircle);
  if (sla['breached_resolve'] == true) {
    return (label: tr('SLA เกินกำหนดแก้ไข${resolve == null ? '' : ' (${_dt(resolve)})'}'), color: const Color(0xFFDC2626), icon: NxI.warning);
  }
  if (sla['breached_response'] == true && !accepted) {
    return (label: tr('SLA เกินเวลาตอบรับ${response == null ? '' : ' (${_dt(response)})'}'), color: const Color(0xFFDC2626), icon: NxI.warning);
  }
  final due = accepted ? resolve : (response ?? resolve);
  if (due == null) return (label: 'SLA${name.isEmpty ? '' : ' · $name'}', color: const Color(0xFF2563EB), icon: NxI.timer);
  final left = due.difference(now ?? thaiNow());
  final soon = left.inMinutes <= 120;
  final what = accepted || response == null ? tr('แก้ไขภายใน') : tr('ตอบรับภายใน');
  return (
    label: '$what ${_dt(due)} · ${tr('เหลือ')} ${jobDurationText(left)}',
    color: soon ? const Color(0xFFD97706) : const Color(0xFF2563EB),
    icon: NxI.timer,
  );
}

/// "ข้อมูลหน้างาน": what a technician needs to do the job — priority / type /
/// SLA, customer and contact (call, e-mail), site (navigate), asset, schedule
/// and due date, sales contact, PO, description. Only filled rows show.
class JobWorkInfoCard extends StatefulWidget {
  const JobWorkInfoCard({super.key, required this.row, required this.onOpen, this.picklists = const {}});
  final Map<String, dynamic> row;
  final void Function(String module, String id) onOpen;
  final Map<String, List<Map<String, dynamic>>> picklists;

  @override
  State<JobWorkInfoCard> createState() => _JobWorkInfoCardState();
}

class _JobWorkInfoCardState extends State<JobWorkInfoCard> {
  Map<String, dynamic> _sla = const {};
  Map<String, dynamic> _asset = const {};
  bool _more = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(JobWorkInfoCard old) {
    super.didUpdateWidget(old);
    if (_s(old.row['related_asset_id']) != _s(widget.row['related_asset_id']) || _s(old.row['job_status']) != _s(widget.row['job_status'])) _load();
  }

  Future<void> _load() async {
    final config = context.read<AppConfig>();
    if (!config.isLoggedIn) return;
    final api = config.apiClient;
    final id = _s(widget.row['id']);
    if (id.isEmpty) return;
    final asset = _s(widget.row['related_asset_id']);
    // SLA and the linked asset side by side (they were asked one after the other).
    final results = await Future.wait<Map<String, dynamic>?>([
      api.getJobSla(id).then<Map<String, dynamic>?>((v) => v, onError: (Object _) => null),
      asset.isEmpty
          ? Future<Map<String, dynamic>?>.value()
          : api.getEntity('asset', asset).then<Map<String, dynamic>?>((v) => v, onError: (Object _) => null),
    ]);
    if (!mounted) return;
    setState(() {
      if (results[0] != null) _sla = results[0]!;
      if (results[1] != null) _asset = results[1]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = widget.row;
    final priority = jobPriorityLabel(r['job_priority'], options: widget.picklists['job_priority'] ?? const []);
    final type = jobPickLabel(r['job_type'], options: widget.picklists['job_type'] ?? const []);
    final category = _s(r['job_category']) == 'other' && _s(r['job_category_other']).isNotEmpty
        ? _s(r['job_category_other'])
        : jobPickLabel(r['job_category'], options: widget.picklists['job_category'] ?? const []);
    final sla = jobSlaChip(_sla, r);
    final customer = _s(r['customer_name']).isNotEmpty ? _s(r['customer_name']) : _s(r['account_name']);
    final contact = [_s(r['customer_contact_name']), _s(r['customer_department'])].where((e) => e.isNotEmpty).join(' · ');
    final phone = _s(r['customer_mobile']).replaceAll(RegExp(r'[^0-9+]'), '');
    final email = _s(r['customer_email']);
    final place = _s(r['location_name_snapshot']);
    final address = _s(r['site_address_snapshot']);
    final planStart = parseThai(r['plan_start']);
    final planEnd = parseThai(r['plan_end']);
    final due = parseWall(r['due_datetime']);
    final overdue = due != null && due.isBefore(thaiNow()) && !const {'Completed', 'Cancelled'}.contains(canonicalJobStatus(r['job_status']));
    final assetName = _s(_asset['asset_name']).isNotEmpty ? _s(_asset['asset_name']) : _s(_asset['asset_no']);
    final serial = _s(_asset['serial_no']);
    final warrantyEnd = _s(_asset['warranty_end']);
    final sales = _s(r['salesperson_name']);
    final salesPhone = _s(r['salesperson_phone']).replaceAll(RegExp(r'[^0-9+]'), '');
    final po = _s(r['contract_po_no']);
    final desc = _s(r['description']);

    final pills = <Widget>[
      if (priority.isNotEmpty) _Pill(key: const ValueKey('job-priority-pill'), icon: NxI.flag, label: priority, color: jobPriorityColor(context, r['job_priority'])),
      if (type.isNotEmpty) _Pill(icon: NxI.wrench, label: type, color: cs.onSurfaceVariant),
      if (category.isNotEmpty) _Pill(icon: NxI.tag, label: category, color: cs.onSurfaceVariant),
      if (sla != null) _Pill(key: const ValueKey('job-sla-chip'), icon: sla.icon, label: sla.label, color: sla.color, strong: true),
    ];
    final rows = <Widget>[
      if (customer.isNotEmpty)
        _InfoRow(
          icon: NxI.buildings,
          label: tr('ลูกค้า'),
          value: customer,
          onTap: _s(r['related_account_id']).isNotEmpty ? () => widget.onOpen('account', _s(r['related_account_id'])) : null,
        ),
      if (contact.isNotEmpty || phone.isNotEmpty || email.isNotEmpty)
        _InfoRow(
          key: const ValueKey('job-info-contact'),
          icon: NxI.user,
          label: tr('ผู้ติดต่อหน้างาน'),
          value: [contact, if (phone.isNotEmpty) _s(r['customer_mobile'])].where((e) => e.isNotEmpty).join('\n'),
          actions: [
            if (phone.isNotEmpty) _RoundAction(key: const ValueKey('job-info-call'), icon: NxI.phoneCall, tooltip: tr('โทร'), onTap: () => launchUrl(Uri(scheme: 'tel', path: phone))),
            if (email.isNotEmpty) _RoundAction(key: const ValueKey('job-info-email'), icon: NxI.envelope, tooltip: tr('อีเมล'), onTap: () => launchUrl(Uri(scheme: 'mailto', path: email))),
          ],
        ),
      if (place.isNotEmpty || address.isNotEmpty)
        _InfoRow(
          key: const ValueKey('job-info-site'),
          icon: NxI.mapPin,
          label: tr('สถานที่หน้างาน'),
          value: [place, address].where((e) => e.isNotEmpty).join('\n'),
          onTap: _s(r['related_location_id']).isNotEmpty ? () => widget.onOpen('location', _s(r['related_location_id'])) : null,
          actions: [
            _RoundAction(
              key: const ValueKey('job-info-map'),
              icon: NxI.navigationArrow,
              tooltip: tr('นำทาง'),
              onTap: () => launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address.isNotEmpty ? address : place}), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
      if (_s(r['related_asset_id']).isNotEmpty)
        _InfoRow(
          key: const ValueKey('job-info-asset'),
          icon: NxI.package,
          label: tr('อุปกรณ์ / ทรัพย์สิน'),
          value: [
            assetName.isEmpty ? '#${_s(r['related_asset_id'])}' : assetName,
            if (serial.isNotEmpty) 'S/N $serial',
            if (warrantyEnd.isNotEmpty) '${tr('ประกันถึง')} ${thaiDate(warrantyEnd, year: uiYear)}',
          ].join('\n'),
          onTap: () => widget.onOpen('asset', _s(r['related_asset_id'])),
        ),
      if (planStart != null)
        _InfoRow(
          icon: NxI.calendarClock,
          label: tr('นัดเข้างาน'),
          value: planEnd == null ? _dt(planStart) : '${_dt(planStart)} – ${planEnd.day == planStart.day && planEnd.month == planStart.month ? _hm(planEnd) : _dt(planEnd)}',
        ),
      if (due != null)
        _InfoRow(
          key: const ValueKey('job-info-due'),
          icon: NxI.clockCountdown,
          label: tr('กำหนดเสร็จ'),
          value: _dt(due) + (overdue ? ' · ${tr('เลยกำหนด')}' : ''),
          valueColor: overdue ? cs.error : null,
        ),
      if (_s(r['related_case_id']).isNotEmpty)
        _InfoRow(icon: NxI.headset, label: tr('เคสต้นทาง'), value: '#${_s(r['related_case_id'])}', onTap: () => widget.onOpen('case', _s(r['related_case_id']))),
      if (sales.isNotEmpty)
        _InfoRow(
          icon: NxI.userCircle,
          label: tr('ผู้ประสานงานขาย'),
          value: sales,
          actions: [if (salesPhone.isNotEmpty) _RoundAction(icon: NxI.phoneCall, tooltip: tr('โทร'), onTap: () => launchUrl(Uri(scheme: 'tel', path: salesPhone)))],
        ),
      if (po.isNotEmpty) _InfoRow(icon: NxI.receipt, label: tr('เลขที่ PO / สัญญา'), value: po),
    ];
    if (pills.isEmpty && rows.isEmpty && desc.isEmpty) return const SizedBox.shrink();
    return JourneySection(
      key: const ValueKey('job-work-info'),
      title: tr('ข้อมูลหน้างาน'),
      icon: NxI.mapPinned,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pills.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: pills),
          if (pills.isNotEmpty && rows.isNotEmpty) const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)), rows[i]],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                onTap: () => setState(() => _more = !_more),
                child: Text(desc, key: const ValueKey('job-info-desc'), maxLines: _more ? null : 4, overflow: _more ? null : TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.icon, required this.label, required this.color, this.strong = false});
  final IconData icon;
  final String label;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: strong ? (dark ? 0.22 : 0.12) : (dark ? 0.14 : 0.07)),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: strong ? 0.45 : 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({super.key, required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: cs.primary.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, size: 18, color: cs.primary), visualDensity: VisualDensity.compact),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({super.key, required this.icon, required this.label, required this.value, this.actions = const [], this.onTap, this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: valueColor, height: 1.35)),
            ]),
          ),
          ...actions,
          if (onTap != null && actions.isEmpty) Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------- Activities

/// Activity type → icon.
IconData jobActivityTypeIcon(Object? type) => switch (_s(type)) {
      'Visit' => NxI.mapPin,
      'Call' => NxI.phoneCall,
      'Meeting' => NxI.users,
      'Task' => NxI.listChecks,
      'Education' => NxI.bookOpen,
      _ => NxI.calendarBlank,
    };

/// Activity status → tone (planned slate, in progress blue, done green,
/// cancelled red, waiting approval amber).
Color jobActivityStatusColor(BuildContext context, Object? status) {
  final cs = Theme.of(context).colorScheme;
  return switch (_s(status).toLowerCase()) {
    'in progress' => const Color(0xFF2563EB),
    'completed' || 'held' => const Color(0xFF16A34A),
    'cancelled' || 'not held' => const Color(0xFFDC2626),
    'pending approval' => const Color(0xFFD97706),
    _ => cs.onSurfaceVariant,
  };
}

/// Thai / English activity status (shared `statusValueLabel`; empty = planned).
String jobActivityStatusText(Object? status) => statusValueLabel(_s(status).isEmpty ? 'Planned' : _s(status), module: 'activity');

/// "ปฏิบัติงาน": the job's activities — type icon, subject, Thai status chip,
/// date/time, assignee, check-in / out and time on site. Tap = open.
class JobActivitiesList extends StatefulWidget {
  const JobActivitiesList({
    super.key,
    required this.jobId,
    required this.linked,
    required this.onOpen,
    this.users = const [],
    this.canEdit = false,
    this.onGenerate,
    this.onCreate,
    this.onSaveTemplate,
    this.reloadToken,
    this.initialShown = 5,
  });

  final String jobId;

  /// Rows of `GET /api/links/job/:id` (`activities`) — the authoritative list.
  final List<Map<String, dynamic>> linked;
  final void Function(String id) onOpen;
  final List<Map<String, dynamic>> users;
  final bool canEdit;
  final VoidCallback? onGenerate;
  final VoidCallback? onCreate;
  final VoidCallback? onSaveTemplate;

  /// Change it to reload the details (e.g. the record's modifiedtime).
  final Object? reloadToken;
  final int initialShown;

  @override
  State<JobActivitiesList> createState() => _JobActivitiesListState();
}

class _JobActivitiesListState extends State<JobActivitiesList> {
  final Map<String, Map<String, dynamic>> _details = {};
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(JobActivitiesList old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken || old.linked.length != widget.linked.length) _load();
  }

  /// Full activity rows (owner, check-in / out): activities linked by
  /// `related_job_id` or by `related_module=job` + `related_id`.
  Future<void> _load() async {
    final config = context.read<AppConfig>();
    if (!config.isLoggedIn) return;
    final api = config.apiClient;
    // Both link styles side by side, only the columns the tiles show; one setState.
    final pages = await Future.wait([
      for (final extra in [
        {'filter[related_job_id]': widget.jobId},
        {'filter[related_module]': 'job', 'filter[related_id]': widget.jobId},
      ])
        api
            .getEntityList('activity', limit: 100, extra: {...extra, 'sort': 'date_start', 'order': 'desc', 'cols': _activityCols})
            .then<EntityListPage?>((p) => p, onError: (Object _) => null),
    ]);
    if (!mounted) return;
    setState(() {
      for (final page in pages) {
        for (final a in page?.items ?? const <Map<String, dynamic>>[]) {
          final id = _s(a['id']);
          if (id.isNotEmpty) _details[id] = a;
        }
      }
    });
  }

  /// What [JobActivityTile] and the owner line read (the server ignores unknown names).
  static const _activityCols =
      'id,subject,title,activitytype,status,date_start,date_end,all_day,checkindate,checkoutdate,photos,smownerid,owner_name,smownerid_name,assigned_user_name';

  List<Map<String, dynamic>> get _rows {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final l in widget.linked) {
      final id = _s(l['id']);
      if (id.isEmpty || !seen.add(id)) continue;
      out.add({...l, ...?_details[id]});
    }
    // Rows the links API did not return (older servers).
    for (final e in _details.entries) {
      if (seen.add(e.key)) out.add(e.value);
    }
    DateTime? at(Map<String, dynamic> a) => parseWall(a['date_start']);
    out.sort((a, b) {
      final x = at(a), y = at(b);
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return out;
  }

  String _owner(Map<String, dynamic> a) {
    for (final k in const ['owner_name', 'smownerid_name', 'assigned_user_name']) {
      if (_s(a[k]).isNotEmpty) return _s(a[k]);
    }
    final id = _s(a['smownerid']);
    if (id.isEmpty) return '';
    for (final u in widget.users) {
      if (_s(u['user_id'] ?? u['id']) == id) return userDisplayName(u);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = _rows;
    final open = rows.where((a) => const {'planned', 'in progress', 'pending approval', ''}.contains(_s(a['status']).toLowerCase())).length;
    final shown = _all ? rows : rows.take(widget.initialShown).toList();
    return JourneySection(
      key: const ValueKey('job-activities'),
      title: rows.isEmpty ? tr('ปฏิบัติงาน') : tr('ปฏิบัติงาน (${rows.length})'),
      icon: NxI.calendarCheck,
      trailing: widget.canEdit
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.onGenerate != null)
                TextButton.icon(
                  key: const ValueKey('job-gen-activities'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: widget.onGenerate,
                  icon: const Icon(NxI.calendarPlus, size: 16),
                  label: Text(tr('สร้าง')),
                ),
              if (widget.onCreate != null || widget.onSaveTemplate != null)
                PopupMenuButton<String>(
                  key: const ValueKey('job-activities-more'),
                  icon: const Icon(NxI.dotsThreeVertical, size: 18),
                  tooltip: tr('เพิ่มเติม'),
                  onSelected: (v) => v == 'create' ? widget.onCreate?.call() : widget.onSaveTemplate?.call(),
                  itemBuilder: (_) => [
                    if (widget.onCreate != null) PopupMenuItem(value: 'create', child: Text(tr('สร้างนัดผูกกับงานนี้'))),
                    if (widget.onSaveTemplate != null && rows.isNotEmpty)
                      PopupMenuItem(key: const ValueKey('job-save-activity-template'), value: 'template', child: Text(tr('บันทึกกิจกรรมของงานนี้เป็นเทมเพลต'))),
                  ],
                ),
            ])
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Container(
              key: const ValueKey('job-activities-empty'),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)),
              child: Text(
                tr(widget.canEdit ? 'ยังไม่มีกิจกรรม — กด "สร้าง" เพื่อแบ่งงานเข้าหน้างาน' : 'ยังไม่มีกิจกรรม'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            if (open > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(tr('ยังไม่เสร็จ $open รายการ'), style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFF2563EB), fontWeight: FontWeight.w700)),
              ),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              JobActivityTile(row: shown[i], owner: _owner(shown[i]), onTap: () => widget.onOpen(_s(shown[i]['id']))),
            ],
            if (rows.length > widget.initialShown)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('job-activities-all'),
                  onPressed: () => setState(() => _all = !_all),
                  icon: Icon(_all ? NxI.caretUp : NxI.caretDown, size: 16),
                  label: Text(tr(_all ? 'ย่อ' : 'ดูทั้งหมด (${rows.length})')),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One activity of a job.
class JobActivityTile extends StatelessWidget {
  const JobActivityTile({super.key, required this.row, required this.onTap, this.owner = ''});
  final Map<String, dynamic> row;
  final String owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final a = row;
    final id = _s(a['id']);
    final type = _s(a['activitytype']);
    final status = _s(a['status']);
    final tone = jobActivityStatusColor(context, status);
    final start = parseWall(a['date_start']);
    final end = parseWall(a['date_end']);
    final inAt = parseWall(a['checkindate']);
    final outAt = parseWall(a['checkoutdate']);
    final when = start == null
        ? tr('ยังไม่กำหนดเวลา')
        : (a['all_day'] == true ? '${start.day}/${start.month}/${uiYear(start.year)} · ${tr('ทั้งวัน')}' : '${_dt(start)}${end != null && end.isAfter(start) ? '–${_hm(end)}' : ''}');
    final photos = a['photos'] is List ? (a['photos'] as List).length : 0;
    final visit = <String>[
      if (inAt != null) '${tr('เข้า')} ${_hm(inAt)}',
      if (outAt != null) '${tr('ออก')} ${_hm(outAt)}',
      if (inAt != null && outAt != null && outAt.isAfter(inAt)) jobDurationText(outAt.difference(inAt)),
      if (inAt != null && outAt == null) tr('อยู่หน้างาน'),
    ];
    return Material(
      key: ValueKey('job-act-$id'),
      color: cs.surfaceContainerHighest.withValues(alpha: dark ? 0.35 : 0.4),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tone.withValues(alpha: dark ? 0.22 : 0.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(jobActivityTypeIcon(type), size: 18, color: tone == cs.onSurfaceVariant ? cs.primary : tone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _s(a['subject']).isNotEmpty ? _s(a['subject']) : (_s(a['title']).isNotEmpty ? _s(a['title']) : tr('กิจกรรม')),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // The chip may shrink (large text / narrow), the title keeps 60%.
                  Flexible(
                    flex: 2,
                    child: Container(
                      key: ValueKey('job-act-status-$id'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: tone.withValues(alpha: dark ? 0.24 : 0.13), borderRadius: BorderRadius.circular(99)),
                      child: Text(jobActivityStatusText(status), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: tone, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  [if (type.isNotEmpty) tr(activityTypeLabel(type)), when, if (owner.isNotEmpty) owner].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (visit.isNotEmpty || photos > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (visit.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(NxI.signIn, size: 13, color: Color(0xFF16A34A)),
                          const SizedBox(width: 4),
                          Flexible(child: Text(visit.join(' · '), key: ValueKey('job-act-visit-$id'), style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
                        ]),
                      if (photos > 0)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(NxI.images, size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text('$photos', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                        ]),
                    ]),
                  ),
              ]),
            ),
            Padding(padding: const EdgeInsets.only(top: 8, left: 2), child: Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
