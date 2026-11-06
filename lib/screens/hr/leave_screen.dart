import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
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
            for (final b in list)
              DenseCardTile(
                title: b['leave_type_name']?.toString() ?? '',
                trailing: Text(
                  '${b['used_days'] ?? 0}/${b['total_days'] ?? 0} วัน',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
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

class _LeaveMineTab extends StatelessWidget {
  const _LeaveMineTab({required this.revision});
  final int revision;

  @override
  Widget build(BuildContext context) {
    return NxCachedFuture<List<Map<String, dynamic>>>(
      revision: revision,
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
              DenseCardTile(
                title: p['leave_type_name']?.toString() ?? 'ลา',
                subtitle: '${p['start_date'] ?? ''} – ${p['end_date'] ?? ''} · ${p['status'] ?? ''}',
              ),
          ],
        );
      },
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
    try {
      await context.read<AppConfig>().apiClient.approveLeave(id, approve: approve);
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
              DenseCardTile(
                title: p['user_name']?.toString() ?? p['leave_type_name']?.toString() ?? '',
                subtitle: '${p['start_date'] ?? ''} – ${p['end_date'] ?? ''} · ${p['leave_type_name'] ?? ''}',
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
