import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/approval_queue.dart';
import '../../core/entity_display.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../core/i18n.dart';

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
  var _revision = 0;

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('เหตุผลที่ไม่อนุมัติ')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: tr('ไม่บังคับ')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('ไม่อนุมัติ'))),
        ],
      ),
    );
    ctrl.dispose();
    return reason;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(done))));
      setState(() => _revision++);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  Future<void> _decide(String kind, Map<String, dynamic> row, bool approve) async {
    final api = context.read<AppConfig>().apiClient;
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    String? reason;
    if (!approve && kind != 'join') {
      reason = await _askReason();
      if (reason == null) return;
    }
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
          final rows = await api.getPendingQuotationApprovals();
          return rows.where((r) => isAwaitingMyApproval(r, session.userId)).toList();
        }),
      if (MenuAccess.allow(session, MenuAccess.leaveManagement))
        'leave': _Section('การลา', NxI.calendarCheck, () => api.getLeaveRequests(all: true, status: 'Pending')),
      if (MenuAccess.allow(session, MenuAccess.pendingApprovals))
        'join': _Section('คำขอเข้าร่วมธุรกิจ', NxI.userPlus, api.getJoinRequests),
    };

    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'รออนุมัติ',
        actions: [
          IconButton(
            onPressed: () => setState(() => _revision++),
            icon: const Icon(NxI.arrowCounterClockwise),
          ),
        ],
      ),
      body: sections.isEmpty
          ? Center(child: Text(tr('ไม่มีสิทธิ์อนุมัติรายการใด')))
          : RefreshIndicator(
              onRefresh: () async => setState(() => _revision++),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: NxBreakpoint.of(context).scrollPadding(context),
                children: [
                  for (final e in sections.entries)
                    _ApprovalSection(
                      key: ValueKey('${e.key}-$_revision'),
                      kind: e.key,
                      section: e.value,
                      onDecide: _decide,
                    ),
                ],
              ),
            ),
    );
  }
}

class _ApprovalSection extends StatefulWidget {
  const _ApprovalSection({super.key, required this.kind, required this.section, required this.onDecide});

  final String kind;
  final _Section section;
  final Future<void> Function(String kind, Map<String, dynamic> row, bool approve) onDecide;

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
      case 'leave':
        return (
          r['user_name']?.toString() ?? r['leave_type_name']?.toString() ?? 'คำขอลา',
          '${r['start_date'] ?? ''} – ${r['end_date'] ?? ''} · ${r['leave_type_name'] ?? ''}'
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
                Text(tr('(${snap.data!.length})'), style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        );
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const NxSkeletonList(rows: 2);
        } else if (snap.hasError) {
          body = Text(tr(formatApiError(snap.error!)), style: TextStyle(color: theme.colorScheme.error));
        } else if (snap.data!.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(tr('ไม่มีรายการรออนุมัติ'), style: theme.textTheme.bodySmall),
          );
        } else {
          body = Column(
            children: [
              for (final r in snap.data!)
                Builder(builder: (context) {
                  final (title, subtitle) = _describe(r);
                  final id = r['id']?.toString() ?? '';
                  final busy = _busy.contains(id);
                  Future<void> act(bool approve) async {
                    setState(() => _busy.add(id));
                    await widget.onDecide(widget.kind, r, approve);
                    if (mounted) setState(() => _busy.remove(id));
                  }

                  return DenseCardTile(
                    title: title,
                    subtitle: subtitle,
                    onTap: widget.kind == 'quotation' && id.isNotEmpty
                        ? () => context.push(AppRoutes.crmRecord('quotation', id))
                        : null,
                    trailing: busy
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: tr('อนุมัติ'),
                                icon: const Icon(NxI.checkCircle, color: Colors.green),
                                onPressed: () => act(true),
                              ),
                              IconButton(
                                tooltip: tr('ไม่อนุมัติ'),
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
