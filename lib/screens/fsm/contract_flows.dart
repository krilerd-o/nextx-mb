import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';

/// Service contract statuses (server values) and Thai labels — same as the web.
const kContractStatusTh = <String, String>{
  'Draft': 'ร่าง',
  'Implement': 'กำลังดำเนินการ',
  'Pending_Approval': 'รออนุมัติ',
  'Pending_Sign': 'รอเซ็น',
  'Wait_Start': 'รอเริ่ม',
  'Active': 'มีผล',
  'Expired': 'หมดอายุ',
  'Cancelled': 'ยกเลิก',
  'Renewed': 'ต่ออายุแล้ว',
};

String contractStatusLabel(Object? s) => tr(kContractStatusTh['${s ?? ''}'] ?? '${s ?? ''}');

/// Actions the server accepts from a status (port of
/// `contractWorkflowService.allowedActions`, plus admin reactivate).
List<String> contractActions(Map<String, dynamic> row, {bool admin = false}) {
  final s = '${row['contract_status'] ?? 'Draft'}'.isEmpty ? 'Draft' : '${row['contract_status'] ?? 'Draft'}';
  final needsApproval = '${row['requires_approval'] ?? '1'}' != '0' && row['requires_approval'] != false;
  return switch (s) {
    'Draft' => needsApproval ? ['submit_approval', 'start_implement', 'transfer', 'cancel'] : ['activate', 'start_implement', 'transfer', 'cancel'],
    'Implement' => needsApproval ? ['ready_for_ma', 'submit_approval', 'transfer', 'cancel'] : ['ready_for_ma', 'activate', 'transfer', 'cancel'],
    'Pending_Approval' => ['approve', 'reject', 'cancel'],
    'Pending_Sign' => ['mark_signed', 'activate', 'transfer', 'cancel'],
    'Wait_Start' => ['activate', 'transfer', 'cancel'],
    'Active' => ['transfer', 'cancel'],
    'Cancelled' => admin ? ['reactivate'] : const [],
    _ => const [],
  };
}

String contractActionLabel(String a) => tr(switch (a) {
  'submit_approval' => 'ส่งขออนุมัติ',
  'start_implement' => 'เริ่มติดตั้ง (Implement)',
  'ready_for_ma' => 'พร้อมเข้า MA',
  'approve' => 'อนุมัติ',
  'reject' => 'ไม่อนุมัติ',
  'mark_signed' => 'บันทึกวันที่ลูกค้าเซ็น',
  'activate' => 'ยืนยันมีผล',
  'transfer' => 'โอนผู้รับผิดชอบ',
  'cancel' => 'ยกเลิกสัญญา',
  'reactivate' => 'เปิดสัญญาใหม่',
  _ => a,
});

/// Status an action leads to (null: depends on the server / not a status move).
String? contractActionTarget(String a) => switch (a) {
      'submit_approval' => 'Pending_Approval',
      'start_implement' => 'Implement',
      'activate' => 'Active',
      'cancel' => 'Cancelled',
      'reject' || 'reactivate' => 'Draft',
      _ => null,
    };

/// Colour of a contract status.
Color contractStatusTone(ColorScheme cs, Object? s) => switch ('${s ?? ''}') {
      'Draft' => cs.onSurfaceVariant,
      'Implement' => const Color(0xFF2563EB),
      'Pending_Approval' || 'Pending_Sign' || 'Wait_Start' => const Color(0xFFF59E0B),
      'Active' || 'Renewed' => const Color(0xFF16A34A),
      'Cancelled' || 'Expired' => kNxDangerRed,
      final v => nxStatusTone(cs, v),
    };

IconData contractActionIcon(String a) => switch (a) {
  'submit_approval' => NxI.paperPlaneTilt,
  'approve' || 'activate' => NxI.check,
  'reject' || 'cancel' => NxI.x,
  'mark_signed' => NxI.penLine,
  'transfer' => NxI.arrowRight,
  'reactivate' => NxI.arrowClockwise,
  _ => NxI.flag,
};

/// Picks one of the allowed actions; null when cancelled or none.
Future<String?> pickContractAction(BuildContext context, Map<String, dynamic> row) {
  final admin = context.read<AppConfig>().session.isBusinessAdmin;
  final actions = contractActions(row, admin: admin);
  return showAppBottomSheet<String>(
    context: context,
    title: '${tr('สถานะสัญญา')} · ${contractStatusLabel(row['contract_status'])}',
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (actions.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('สัญญานี้ไม่มีขั้นตอนให้ดำเนินการต่อ'))),
      for (final a in actions)
        ListTile(
          key: ValueKey('contract-action-$a'),
          leading: Icon(contractActionIcon(a), color: a == 'cancel' || a == 'reject' ? const Color(0xFFE11D48) : null),
          title: Text(contractActionLabel(a)),
          onTap: () => Navigator.pop(context, a),
        ),
    ]),
  );
}

/// Contract workflow (same windows as the web): each action asks for what
/// the server needs (approver / reason / signed date / new owner) and posts
/// `POST /api/entity/service_contract/:id/workflow-action`.
class ContractFlows {
  /// Returns the updated record, or null when cancelled / failed (shown).
  static Future<Map<String, dynamic>?> run(BuildContext context, {required Map<String, dynamic> row, required String action}) async {
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final id = strId(row['id']);
    final cs = Theme.of(context).colorScheme;
    final target = contractActionTarget(action);
    // Shared status confirm: current → new (or the step), in contract colours.
    Future<NxStatusConfirm?> confirm({String? impact, bool reason = false, String? label, List<String> reasons = const []}) => showStatusChangeConfirm(
          context,
          title: '${contractActionLabel(action)}?',
          recordTitle: entityTitle(row, module: 'service_contract'),
          from: '${row['contract_status'] ?? ''}'.isEmpty ? null : contractStatusLabel(row['contract_status']),
          fromColor: contractStatusTone(cs, row['contract_status']),
          to: target == null ? contractActionLabel(action) : contractStatusLabel(target),
          toColor: target == null ? cs.primary : contractStatusTone(cs, target),
          impact: impact,
          requireReason: reason,
          reasons: reasons,
          noteLabel: label,
          destructive: action == 'cancel' || action == 'reject',
          confirmLabel: reason ? 'ยืนยัน' : contractActionLabel(action),
          noteKey: const ValueKey('contract-reason'),
          confirmKey: ValueKey(reason ? 'contract-reason-ok' : 'contract-confirm'),
        );
    Map<String, dynamic>? body;
    switch (action) {
      case 'reject' || 'cancel' || 'reactivate':
        final r = await confirm(
          reason: true,
          label: action == 'reject' ? tr('เหตุผลที่ไม่อนุมัติ') : action == 'cancel' ? tr('เหตุผลที่ยกเลิก') : tr('เหตุผลที่เปิดใหม่'),
          reasons: action == 'cancel' ? kNxCancelReasons : (action == 'reject' ? kNxRejectReasons : const []),
          impact: action == 'cancel' ? 'สัญญาจะหยุดมีผล และใช้ชั่วโมง Manday ต่อไม่ได้' : null,
        );
        if (r == null) return null;
        final reason = r.note;
        body = {
          'reason': reason,
          if (action == 'reject') 'reject_reason': reason,
          if (action == 'cancel') 'cancel_reason': reason,
          if (action == 'reactivate') 'reactivate_reason': reason,
        };
      case 'mark_signed':
        if (!context.mounted) return null;
        final d = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: tr('วันที่ลูกค้าเซ็น'),
        );
        if (d == null || !context.mounted) return null;
        final signed = '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}';
        if (await confirm(impact: '${tr('วันที่ลูกค้าเซ็น')}: ${d.day}/${d.month}/${uiYear(d.year)}') == null) return null;
        body = {'signed_date': signed};
      case 'submit_approval':
        if (!context.mounted) return null;
        body = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _SubmitSheet(row: row),
        );
        if (body == null) return null;
      case 'transfer':
        if (!context.mounted) return null;
        final owner = await pickUser(context, title: tr('โอนให้ผู้รับผิดชอบ'), excludeId: strId(row['smownerid']));
        if (owner == null) return null;
        body = {'smownerid': owner};
      default:
        if (!context.mounted) return null;
        final ok = await confirm(impact: action == 'activate' ? 'สัญญาจะเริ่มมีผล และนับสิทธิ์บริการตามสัญญา' : null);
        if (ok == null) return null;
        body = const {};
    }
    try {
      final r = await api.serviceContractWorkflowAction(id, {'action': action, ...body});
      final rec = r['record'] is Map ? Map<String, dynamic>.from(r['record'] as Map) : <String, dynamic>{};
      showNxStatusChangedSnack(messenger, label: '${contractActionLabel(action)} · ${contractStatusLabel(rec['contract_status'])}');
      return rec;
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      return null;
    }
  }
}

/// Search-and-pick a user of the business; returns the user id.
Future<String?> pickUser(BuildContext context, {required String title, String? excludeId}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.7, child: _UserPicker(title: title, excludeId: excludeId)),
  );
}

class _UserPicker extends StatefulWidget {
  const _UserPicker({required this.title, this.excludeId});
  final String title;
  final String? excludeId;

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  List<Map<String, dynamic>>? _users;
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.read<AppConfig>().apiClient.getUsersCached().then((u) {
      if (mounted) setState(() => _users = u);
    }).catchError((_) {
      if (mounted) setState(() => _users = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = [
      for (final u in _users ?? const <Map<String, dynamic>>[])
        if (strId(u['id'] ?? u['user_id']) != widget.excludeId && userDisplayName(u).toLowerCase().contains(_q.toLowerCase())) u,
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาชื่อ')), onChanged: (v) => setState(() => _q = v)),
        ]),
      ),
      Expanded(
        child: _users == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey('user-pick-${strId(list[i]['id'] ?? list[i]['user_id'])}'),
                  leading: CircleAvatar(child: Text(userDisplayName(list[i]).characters.firstOrNull ?? '?')),
                  title: Text(userDisplayName(list[i])),
                  onTap: () => Navigator.pop(context, strId(list[i]['id'] ?? list[i]['user_id'])),
                ),
              ),
      ),
    ]);
  }
}

/// Submit for approval: approver in the system, or e-mail a sign link.
class _SubmitSheet extends StatefulWidget {
  const _SubmitSheet({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_SubmitSheet> createState() => _SubmitSheetState();
}

class _SubmitSheetState extends State<_SubmitSheet> {
  String _channel = 'in_app';
  String? _approverId;
  String? _approverName;
  late final _email = TextEditingController(text: '${widget.row['contact_email'] ?? widget.row['email'] ?? ''}');
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickApprover() async {
    final id = await pickUser(context, title: tr('เลือกผู้อนุมัติ'));
    if (id == null || !mounted) return;
    final users = await context.read<AppConfig>().apiClient.getUsersCached();
    final u = users.where((x) => strId(x['id'] ?? x['user_id']) == id).firstOrNull;
    setState(() {
      _approverId = id;
      _approverName = u == null ? '#$id' : userDisplayName(u);
      _error = null;
    });
  }

  void _submit() {
    if (_channel == 'in_app' && _approverId == null) return setState(() => _error = tr('กรุณาเลือกผู้อนุมัติ'));
    if (_channel == 'email_sign' && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      return setState(() => _error = tr('อีเมลผู้ลงนามไม่ถูกต้อง'));
    }
    Navigator.pop(context, {
      'approval_channel': _channel,
      if (_channel == 'in_app') 'approver_user_id': int.tryParse(_approverId!) ?? _approverId,
      if (_channel == 'email_sign') ...{'notify_email': _email.text.trim(), 'access_mode': 'public', 'expires_preset': '7d'},
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('ส่งขออนุมัติสัญญา'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'in_app', icon: const Icon(NxI.user, size: 16), label: Text(tr('ผู้อนุมัติในระบบ'))),
              ButtonSegment(value: 'email_sign', icon: const Icon(NxI.envelope, size: 16), label: Text(tr('ลิงก์เซ็นทางอีเมล'))),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() {
              _channel = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 14),
          if (_channel == 'in_app')
            OutlinedButton.icon(
              key: const ValueKey('contract-approver'),
              onPressed: _pickApprover,
              icon: const Icon(NxI.user, size: 18),
              label: Text(_approverName ?? tr('เลือกผู้อนุมัติ')),
            )
          else
            TextField(key: const ValueKey('contract-sign-email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('อีเมลผู้ลงนาม'))),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('contract-submit'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: _submit, child: Text(tr('ส่งขออนุมัติ'))),
        ]),
      ),
    );
  }
}
