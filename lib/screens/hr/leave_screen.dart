import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';

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
      context.watch<AppConfig>().session,
      MenuAccess.leaveManagement,
    );
    final tabCount = canApprove ? 4 : 3;
    return DefaultTabController(
      length: tabCount,
      initialIndex: widget.initialTab.clamp(0, tabCount - 1),
      child: Scaffold(
        appBar: const NxAppHeader(title: 'การลา'),
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
      empty: const Center(child: Text('ไม่มีข้อมูลสิทธิ์ลา')),
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
  final _reason = TextEditingController();
  DateTimeRange? _range;
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
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _range ?? DateTimeRange(start: now, end: now.add(const Duration(days: 1))),
    );
    if (r != null) setState(() => _range = r);
  }

  Future<void> _submit() async {
    if (_typeId == null || _range == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เลือกประเภทลาและวันที่')));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppConfig>().apiClient.postLeaveRequest(
            leaveTypeId: _typeId!,
            startDate: _ymd(_range!.start),
            endDate: _ymd(_range!.end),
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งคำขอลาแล้ว')));
        _reason.clear();
        widget.onSubmitted();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
              DropdownButtonFormField<int>(
                value: _typeId,
                decoration: const InputDecoration(labelText: 'ประเภท'),
                items: _types
                    .map(
                      (e) => DropdownMenuItem(
                        value: int.tryParse(e['id']?.toString() ?? ''),
                        child: Text(e['name']?.toString() ?? ''),
                      ),
                    )
                    .where((e) => e.value != null)
                    .toList(),
                onChanged: (v) => setState(() => _typeId = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ช่วงวันที่'),
                subtitle: Text(
                  _range == null
                      ? 'แตะเพื่อเลือก'
                      : '${_range!.start.day}/${_range!.start.month} – ${_range!.end.day}/${_range!.end.month}',
                ),
                trailing: const Icon(NxI.calendarBlank),
                onTap: _pickRange,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(labelText: 'เหตุผล'),
                maxLines: 3,
              ),
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
  var _local = 0;

  Future<void> _cancel(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกคำขอลา?'),
        content: Text('${p['leave_type_name'] ?? 'ลา'} ${p['start_date'] ?? ''} – ${p['end_date'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ไม่')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ยกเลิกคำขอ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppConfig>().apiClient.cancelLeave(p['id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกคำขอลาแล้ว')));
      setState(() => _local++);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
      empty: const Center(child: Text('ยังไม่มีคำขอลา')),
      builder: (context, list) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: NxBreakpoint.of(context).scrollPadding(context),
          children: [
            for (final p in list)
              _LeaveRequestCard(
                row: p,
                onCancel: p['status']?.toString() == 'Pending' ? () => _cancel(p) : null,
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
  const _LeaveRequestCard({required this.row, this.onCancel, this.trailing});
  final Map<String, dynamic> row;
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
                          who != null && who.isNotEmpty ? who : (row['leave_type_name']?.toString() ?? 'ลา'),
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                        child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (who != null && who.isNotEmpty) row['leave_type_name']?.toString() ?? '',
                      '${d(row['start_date'])} – ${d(row['end_date'])}',
                      if (row['days'] != null) '${row['days']} วัน',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (reason.isNotEmpty) Text('เหตุผล: $reason', style: theme.textTheme.bodySmall),
                  if (reject.isNotEmpty)
                    Text('เหตุผลที่ไม่อนุมัติ: $reject', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ],
              ),
            ),
            if (onCancel != null) TextButton(onPressed: onCancel, child: const Text('ยกเลิก')),
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
                Expanded(child: Text(row['leave_type_name']?.toString() ?? '', style: theme.textTheme.titleSmall)),
                Text('คงเหลือ ${n(left < 0 ? 0 : left)} วัน', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ratio, minHeight: 8),
            ),
            const SizedBox(height: 4),
            Text('ใช้ไป ${n(used)} จาก ${n(total)} วัน', style: theme.textTheme.bodySmall),
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
          title: const Text('เหตุผลที่ไม่อนุมัติ'),
          content: TextField(controller: ctrl, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'ไม่บังคับ')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('ไม่อนุมัติ')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
      empty: const Center(child: Text('ไม่มีคำขอรออนุมัติ')),
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
