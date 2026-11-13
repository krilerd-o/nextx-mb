import 'package:flutter/material.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_split_view.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/activity_guests.dart' show activityTypeLabel;
import '../../core/approval_queue.dart';
import '../../core/journey_rules.dart' show jobPriorityLabel;
import '../../core/entity_display.dart';
import '../../core/menu_access.dart';
import '../../core/service_journey.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../deep_link_loaders.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_refresh.dart';

/// Everything waiting for the current user's decision, gathered from the
/// NEXTX endpoints that already exist (quotation approval chain, HR leave,
/// business join requests).
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _Section {
  _Section(this.title, this.icon, this.load);
  final String title;
  final IconData icon;
  final Future<List<Map<String, dynamic>>> Function() load;
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  /// Two-pane: the record open on the right.
  (String, String)? _open;
  var _revision = 0;

  /// Service Journey inbox (`/api/approvals/inbox`): quotations + activities + jobs sent to me.
  bool _journey = false;
  Future<Map<String, dynamic>>? _inbox;

  Future<Map<String, dynamic>> _loadInbox() {
    if (_inbox != null) return _inbox!;
    return _inbox = context.read<AppConfig>().apiClient.getApprovalInbox();
  }

  Future<List<Map<String, dynamic>>> _inboxList(String key) async {
    final d = await _loadInbox();
    final v = d[key];
    return v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];
  }
  NxListQuery _query = const NxListQuery();
  late final NxListPrefs _prefs = NxListPrefs('approvals_${context.read<AppConfig>().businessScope}');

  @override
  void initState() {
    super.initState();
    ServiceJourney.supported(context.read<AppConfig>().apiClient).then((ok) {
      if (ok && mounted) setState(() => _journey = true);
    });
    _prefs.loadQuery().then((q) {
      if (q != null && mounted) setState(() => _query = q);
    });
  }

  void _onQuery(NxListQuery q) {
    setState(() => _query = q);
    _prefs.saveQuery(q.copyWith(q: ''));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      showNxStatusChangedSnack(ScaffoldMessenger.of(context), label: done);
      final config = context.read<AppConfig>();
      PendingApprovals.instance.refresh(config.apiClient, userId: config.session.userId);
      setState(() {
        _revision++;
        _inbox = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  Future<void> _decide(String kind, Map<String, dynamic> row, bool approve, [String title = '']) async {
    final api = context.read<AppConfig>().apiClient;
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    if (!approve && kind == 'job') {
      // "ไม่อนุมัติ" a job = open it to forward / cancel there (its own windows).
      context.push(AppRoutes.crmRecord('job', id));
      return;
    }
    // Ask first: รออนุมัติ → อนุมัติ / ไม่อนุมัติ. A reason is required to
    // reject where the server keeps one (quotation, leave, activity).
    final takesReason = !approve && kind != 'join';
    final ok = await showStatusChangeConfirm(
      context,
      recordTitle: title,
      from: kind == 'job' ? 'รอการตอบรับ' : 'รออนุมัติ',
      fromColor: const Color(0xFFF59E0B),
      to: approve ? (kind == 'job' ? 'กำลังดำเนินการ' : 'อนุมัติ') : 'ไม่อนุมัติ',
      toColor: approve ? const Color(0xFF16A34A) : kNxDangerRed,
      impact: approve ? (kind == 'join' ? 'ผู้ขอจะเข้าใช้งานธุรกิจนี้ได้ทันที' : 'ผู้ขอจะได้รับแจ้งผลการอนุมัติ') : 'ผู้ขอจะได้รับแจ้งว่าไม่อนุมัติ',
      requireReason: takesReason,
      reasons: takesReason ? kNxRejectReasons : const [],
      confirmLabel: approve ? (kind == 'job' ? 'รับงาน' : 'อนุมัติ') : 'ไม่อนุมัติ',
      destructive: !approve,
    );
    if (ok == null || !mounted) return;
    final reason = takesReason ? ok.note : null;
    final label = approve ? 'อนุมัติแล้ว' : 'ไม่อนุมัติแล้ว';
    switch (kind) {
      case 'quotation':
        await _run(
          () async => approve ? await api.approveQuotation(id) : await api.rejectQuotation(id, reason: reason),
          label,
        );
      case 'leave':
        await _run(() async => api.approveLeave(id, approve: approve, reason: reason), label);
      case 'join':
        await _run(() => api.decideJoinRequest(id, approve: approve), label);
      case 'activity':
        await _run(() async => approve ? await api.approveActivity(id) : await api.rejectActivity(id, note: reason), label);
      case 'job':
        // "อนุมัติ" = รับงาน ("ไม่อนุมัติ" opened the job above).
        // No customer e-mail unless asked (same default as the รับงาน sheet).
        await _run(() async => api.jobWorkflowAction(id, 'accept', skipEmail: true), 'รับงานแล้ว');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final api = config.apiClient;
    final session = config.session;
    final sections = <String, _Section>{
      if (MenuAccess.allow(session, MenuAccess.quotation))
        'quotation': _Section('ใบเสนอราคา', NxI.receipt, () async {
          if (_journey) return _inboxList('quotations');
          final rows = await api.getPendingQuotationApprovals();
          return rows.where((r) => isAwaitingMyApproval(r, session.userId)).toList();
        }),
      if (_journey) 'activity': _Section('กิจกรรม', NxI.calendarCheck, () => _inboxList('activities')),
      if (_journey && MenuAccess.allow(session, MenuAccess.job)) 'job': _Section('งานที่ส่งถึงฉัน', NxI.wrench, () => _inboxList('jobs')),
      if (MenuAccess.allow(session, MenuAccess.leaveManagement))
        'leave': _Section('การลา', NxI.calendarCheck, () => api.getLeaveRequests(all: true, status: 'Pending')),
      if (MenuAccess.allow(session, MenuAccess.pendingApprovals))
        'join': _Section('คำขอเข้าร่วมธุรกิจ', NxI.userPlus, api.getJoinRequests),
    };

    final open = _open;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'รออนุมัติ',
      ),
      body: NxSplitView(
        onClose: () => setState(() => _open = null),
        detail: open == null
            ? null
            : NxPaneHost(
                key: ValueKey('approval-pane-${open.$1}-${open.$2}'),
                onPopRoot: () => setState(() => _open = null),
                child: open.$1 == 'activity' ? ActivityByIdLoader(id: open.$2) : EntityByIdLoader(module: open.$1, id: open.$2),
              ),
        list: sections.isEmpty
          ? Center(child: Text(tr('ไม่มีสิทธิ์อนุมัติรายการใด')))
          : NxRefresh(
              onRefresh: () async => setState(() {
                _revision++;
                _inbox = null;
              }),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: NxBreakpoint.of(context).scrollPadding(context),
                children: [
                  NxListToolbar(
                    query: _query,
                    prefs: _prefs,
                    liveSearch: true,
                    padding: const EdgeInsets.only(bottom: 4),
                    searchHint: 'ค้นหาชื่อผู้ขอ / เลขเอกสาร',
                    quickGroup: 'type',
                    groups: [
                      NxFilterGroup(
                        key: 'type',
                        label: 'ประเภท',
                        options: [for (final e in sections.entries) NxFilterOption(e.key, e.value.title)],
                      ),
                    ],
                    sorts: const [NxSortOption('new', 'ใหม่ → เก่า'), NxSortOption('old', 'เก่า → ใหม่')],
                    onChanged: _onQuery,
                  ),
                  for (final e in sections.entries)
                    if (_query.values('type').isEmpty || _query.has('type', e.key))
                      _ApprovalSection(
                        key: ValueKey('${e.key}-$_revision-$_journey'),
                        kind: e.key,
                        section: e.value,
                        query: _query,
                        onDecide: _decide,
                        onOpen: (k, id) => setState(() => _open = (k, id)),
                      ),
                ],
              ),
            ),
      ),
    );
  }
}

class _ApprovalSection extends StatefulWidget {
  const _ApprovalSection({
    super.key,
    required this.kind,
    required this.section,
    required this.onDecide,
    this.onOpen,
    this.query = const NxListQuery(),
  });

  final String kind;
  final NxListQuery query;
  final _Section section;
  final Future<void> Function(String kind, Map<String, dynamic> row, bool approve, String title) onDecide;
  final void Function(String kind, String id)? onOpen;

  @override
  State<_ApprovalSection> createState() => _ApprovalSectionState();
}

class _ApprovalSectionState extends State<_ApprovalSection> {
  late final Future<List<Map<String, dynamic>>> _future = widget.section.load();
  final Set<String> _busy = {};

  (String, String) _describe(Map<String, dynamic> r) {
    switch (widget.kind) {
      case 'quotation':
        final title = entityTitle(r, module: 'quotation');
        final amount = r['grand_total'] ?? r['total_amount'] ?? r['total'];
        final level = r['approval_level'];
        return (
          title,
          [
            if (amount != null) 'ยอด $amount',
            if (level != null) 'ขั้นที่ $level',
          ].join(' · '),
        );
      case 'activity':
        return (
          (r['subject'] ?? r['title'] ?? 'กิจกรรม').toString(),
          [
            r['owner_name'],
            if ('${r['activitytype'] ?? ''}'.isNotEmpty) tr(activityTypeLabel('${r['activitytype']}')),
            if (r['date_start'] != null) formatThaiField(r['date_start'], 'date_start', module: 'activity', year: uiYear),
          ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
        );
      case 'job':
        return (
          '${r['job_no'] ?? ''} ${r['job_name'] ?? ''}'.trim(),
          // Priority in Thai like the web (Normal → ปกติ).
          [r['customer_name'], jobPriorityLabel(r['job_priority']), if (r['plan_start'] != null) thaiDate(r['plan_start'], year: uiYear)].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
        );
      case 'leave':
        return (
          r['user_name']?.toString() ?? r['leave_type_name']?.toString() ?? 'คำขอลา',
          '${thaiDate(r['start_date'], year: uiYear)} – ${thaiDate(r['end_date'], year: uiYear)} · ${r['leave_type_name'] ?? ''}'
              '${(r['reason']?.toString() ?? '').isEmpty ? '' : ' · ${r['reason']}'}',
        );
      default:
        final name = [r['first_name'], r['last_name']].where((e) => e != null).join(' ').trim();
        return (
          name.isEmpty ? (r['email1']?.toString() ?? 'ผู้ใช้') : name,
          [r['email1'], r['business_name']].where((e) => e != null).join(' · '),
        );
    }
  }

  /// Request time for sorting (created / submitted / start date).
  String _when(Map<String, dynamic> r) =>
      '${r['created_at'] ?? r['createdtime'] ?? r['requested_at'] ?? r['start_date'] ?? r['id'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Icon(widget.section.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(tr(widget.section.title), style: theme.textTheme.titleSmall),
              if (snap.hasData) ...[
                const SizedBox(width: 8),
                Text('(${snap.data!.length})', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        );
        final rows = snap.hasData
            ? nxApplyLocalQuery<Map<String, dynamic>>(
                snap.data!,
                widget.query.copyWith(filters: const {}),
                text: (r) {
                  final (t, sub) = _describe(r);
                  return '$t $sub ${r['quotation_no'] ?? ''} ${r['user_name'] ?? ''}';
                },
                sorts: {
                  'new': (a, b) => _when(b).compareTo(_when(a)),
                  'old': (a, b) => _when(a).compareTo(_when(b)),
                },
              )
            : const <Map<String, dynamic>>[];
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const NxSkeletonList(rows: 2);
        } else if (snap.hasError) {
          body = Text(tr(formatApiError(snap.error!)), style: TextStyle(color: theme.colorScheme.error));
        } else if (rows.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(tr('ไม่มีรายการรออนุมัติ'), style: theme.textTheme.bodySmall),
          );
        } else {
          body = Column(
            children: [
              for (final r in rows)
                Builder(builder: (context) {
                  final (title, subtitle) = _describe(r);
                  final id = r['id']?.toString() ?? '';
                  final busy = _busy.contains(id);
                  Future<void> act(bool approve) async {
                    setState(() => _busy.add(id));
                    await widget.onDecide(widget.kind, r, approve, title);
                    if (mounted) setState(() => _busy.remove(id));
                  }

                  return DenseCardTile(
                    title: title,
                    subtitle: subtitle,
                    onTap: (widget.kind == 'quotation' || widget.kind == 'activity' || widget.kind == 'job') && id.isNotEmpty
                        ? () => widget.onOpen != null && NxBreakpoint.of(context).twoPane
                            ? widget.onOpen!(widget.kind, id)
                            : widget.kind == 'activity'
                                ? nxPush<void>(context, ActivityByIdLoader(id: id))
                                : context.push(AppRoutes.crmRecord(widget.kind, id))
                        : null,
                    trailing: busy
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: tr(widget.kind == 'job' ? 'รับงาน' : 'อนุมัติ'),
                                icon: const Icon(NxI.checkCircle, color: Colors.green),
                                onPressed: () => act(true),
                              ),
                              IconButton(
                                tooltip: tr(widget.kind == 'job' ? 'เปิดงาน' : 'ไม่อนุมัติ'),
                                icon: const Icon(NxI.xCircle, color: Colors.red),
                                onPressed: () => act(false),
                              ),
                            ],
                          ),
                  );
                }),
            ],
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, body]);
      },
    );
  }
}
