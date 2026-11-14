import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/nx_skeleton.dart';
import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';

/// Hours as "1 วัน 2 ชม." using the contract's hours per day.
String mandayHuman(num hours, num? hoursPerDay) {
  final hpd = (hoursPerDay == null || hoursPerDay <= 0) ? 8 : hoursPerDay;
  final h = hours.toDouble();
  if (h.abs() < 1e-9) return '0 ${tr('ชม.')}';
  final days = (h / hpd).floor();
  final rest = h - days * hpd;
  String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (days <= 0) return '${n(h)} ${tr('ชม.')}';
  return rest < 1e-9 ? '$days ${tr('วัน')}' : '$days ${tr('วัน')} ${n(rest)} ${tr('ชม.')}';
}

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

/// Case → Contract & Manday (same as the web card): linked contracts with
/// what is left, request hours (contract + hours + how to get the customer's
/// sign-off), and approve / reject (with reason) / cancel / copy sign link.
class CaseMandayPanel extends StatefulWidget {
  const CaseMandayPanel({super.key, required this.id, this.row = const {}, this.canEdit = true});
  final String id;
  final Map<String, dynamic> row;
  final bool canEdit;

  @override
  State<CaseMandayPanel> createState() => _CaseMandayPanelState();
}

class _CaseMandayPanelState extends State<CaseMandayPanel> {
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _busy;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  List<Map<String, dynamic>> get _contracts => [
    for (final c in (_summary['case_contracts'] as List? ?? const []))
      if (c is Map) Map<String, dynamic>.from(c),
  ]..sort((a, b) => ((b['usable'] == true ? 2 : 0) + (b['is_primary'] == true ? 1 : 0)) - ((a['usable'] == true ? 2 : 0) + (a['is_primary'] == true ? 1 : 0)));

  Map<String, dynamic>? _contract(Object? id) => _contracts.where((c) => '${c['id']}' == '$id').firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!context.read<AppConfig>().isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    try {
      final s = await _api.getCaseMandaySummary(widget.id);
      var r = <Map<String, dynamic>>[];
      try {
        r = await _api.getCaseMandayRequests(widget.id);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _summary = s;
          _requests = r;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(String key, Future<void> Function() fn) async {
    setState(() => _busy = key);
    try {
      await fn();
    } catch (e) {
      _snack(tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _request() async {
    final usable = _contracts.where((c) => c['usable'] != false).toList();
    if (usable.isEmpty) {
      _snack(tr('ยังไม่มีสัญญาบริการที่ใช้ได้กับเคสนี้'));
      return;
    }
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RequestSheet(contracts: usable, defaultEmail: '${widget.row['customer_email'] ?? ''}'.trim(), contactId: widget.row['related_contact_id']),
    );
    if (res == null || !mounted) return;
    await _run('request', () async {
      final r = await _api.postCaseMandayRequest(widget.id, res);
      final url = (r['sign_link'] is Map ? r['sign_link']['url'] : null) ?? (r['signLink'] is Map ? r['signLink']['url'] : null);
      final emailSent = r['email'] is Map && r['email']['sent'] == true;
      HapticFeedback.mediumImpact();
      if (res['send_sign_email'] == true && res['skip_email'] == true && url != null) {
        await Clipboard.setData(ClipboardData(text: '$url'));
        _snack(tr('ส่งคำขอแล้ว · คัดลอกลิงก์ให้ลูกค้าเซ็นแล้ว'));
      } else if (emailSent) {
        _snack('${tr('ส่งคำขอแล้ว · ส่งอีเมลถึง')} ${res['notify_email']}');
      } else {
        _snack(tr('ส่งคำขอแล้ว'));
      }
      await _load();
    });
  }

  /// Approve / cancel a manday request after the shared status confirm.
  Future<bool> _confirm(Map<String, dynamic> req, {required String to, required Color toColor, String? impact, required String confirm}) async {
    final ok = await showStatusChangeConfirm(
      context,
      recordTitle: _reqTitle(req),
      from: tr('รออนุมัติ'),
      fromColor: const Color(0xFFD97706),
      to: to,
      toColor: toColor,
      impact: impact,
      confirmLabel: confirm,
    );
    return ok != null && mounted;
  }

  String _reqTitle(Map<String, dynamic> req) {
    final c = _contract(req['contract_id']);
    final hours = _num(req['requested_hours'] ?? req['qty']);
    return '${mandayHuman(hours, c?['md_hours_per_day'] == null ? null : _num(c!['md_hours_per_day']))} · ${c?['contract_no'] ?? 'SC #${req['contract_id']}'}';
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final ok = await showStatusChangeConfirm(
      context,
      title: 'ไม่อนุมัติคำขอ Manday',
      recordTitle: _reqTitle(req),
      from: tr('รออนุมัติ'),
      fromColor: const Color(0xFFD97706),
      to: tr('ไม่อนุมัติ'),
      toColor: kNxDangerRed,
      impact: 'ชั่วโมงที่จองไว้จะคืนกลับเข้าสัญญา',
      requireReason: true,
      reasons: const ['เกินขอบเขตสัญญา', 'ข้อมูลไม่ครบ', 'ซ้ำกับคำขออื่น'],
      noteLabel: 'เหตุผล',
      confirmLabel: 'ไม่อนุมัติ',
      noteKey: const ValueKey('manday-reject-reason'),
      confirmKey: const ValueKey('manday-reject-ok'),
    );
    final reason = ok?.note;
    if (reason == null || !mounted) return;
    await _run('reject-${req['id']}', () async {
      final r = await _api.rejectMandayRequest(strId(req['id']), reason: reason);
      final released = _num(r['released_hours']);
      _snack(released > 0 ? '${tr('ไม่อนุมัติแล้ว · คืนชั่วโมง')} ${mandayHuman(released, _contract(req['contract_id'])?['md_hours_per_day'])}' : tr('ไม่อนุมัติแล้ว'));
      await _load();
    });
  }

  Future<void> _copyLink(Map<String, dynamic> req) => _run('link-${req['id']}', () async {
    final r = await _api.resendCaseMandaySign(strId(req['id']), skipEmail: true);
    final url = (r['sign_link'] is Map ? r['sign_link']['url'] : null) ?? (r['signLink'] is Map ? r['signLink']['url'] : null);
    if (url == null) {
      _snack(tr('ไม่มีลิงก์ให้เซ็น'));
      return;
    }
    await Clipboard.setData(ClipboardData(text: '$url'));
    _snack(tr('คัดลอกลิงก์ให้ลูกค้าเซ็นแล้ว'));
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final contracts = _contracts;
    final account = _summary['account'] is Map ? Map<String, dynamic>.from(_summary['account'] as Map) : null;
    return Container(
      key: const ValueKey('case-manday'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(NxI.calendarCheck, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('สัญญาและ Manday'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          if (account != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('${tr('ใช้ได้')} ${mandayHuman(_num(account['available_hours']), _num(account['hours_per_day']))}', style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 10),
        if (_loading)
          const NxSkeletonRows(key: ValueKey('case-manday-skeleton'), count: 2, padded: false, top: 0, leading: NxSkelLeading.icon, leadingSize: 36, trailing: NxSkelTrailing.pill)
        else if (contracts.isEmpty && _requests.isEmpty)
          Text(tr('ยังไม่ผูกสัญญาบริการกับเคสนี้'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
        else ...[
          for (final c in contracts) _contractTile(theme, c),
          if (_requests.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(tr('คำขอใช้ Manday'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final r in _requests) _requestTile(theme, r),
          ],
        ],
        if (widget.canEdit && contracts.isNotEmpty) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const ValueKey('manday-request'),
            onPressed: _busy == null ? _request : null,
            icon: _busy == 'request' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.plus, size: 18),
            label: Text(tr('ขอใช้ Manday')),
          ),
        ],
      ]),
    );
  }

  Widget _contractTile(ThemeData theme, Map<String, dynamic> c) {
    final cs = theme.colorScheme;
    final hpd = _num(c['md_hours_per_day']);
    final ent = _num(c['md_entitlement_hours']);
    final remain = _num(c['md_remain_hours']);
    final usable = c['usable'] != false;
    final used = ent <= 0 ? 0.0 : ((ent - remain) / ent).clamp(0, 1).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: (usable ? cs.primary : cs.outline).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${c['contract_no'] ?? 'SC #${c['id']}'}${c['contract_name'] == null ? '' : ' · ${c['contract_name']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (c['is_primary'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: Text(tr('หลัก'), style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 12))),
          if (!usable) Padding(padding: const EdgeInsets.only(left: 6), child: Text(tr('ใช้ไม่ได้'), style: TextStyle(color: cs.outline, fontSize: 12))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: used, minHeight: 6, backgroundColor: cs.onSurface.withValues(alpha: 0.08))),
        const SizedBox(height: 6),
        Text(
          '${tr('คงเหลือ')} ${mandayHuman(remain, hpd)} / ${mandayHuman(ent, hpd)}'
          '${_num(c['pending_hours']) > 0 ? ' · ${tr('รออนุมัติ')} ${mandayHuman(_num(c['pending_hours']), hpd)}' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }

  Widget _requestTile(ThemeData theme, Map<String, dynamic> r) {
    final cs = theme.colorScheme;
    final st = '${r['status'] ?? ''}';
    final (Color color, String label) = switch (st) {
      'Pending' => (const Color(0xFFD97706), tr('รออนุมัติ')),
      'Approved' => (const Color(0xFF16A34A), tr('อนุมัติแล้ว')),
      'Rejected' => (cs.error, tr('ไม่อนุมัติ')),
      'Cancelled' => (cs.outline, tr('ยกเลิกแล้ว')),
      _ => (cs.outline, st),
    };
    final c = _contract(r['contract_id']);
    final hours = r['requested_hours'] ?? r['qty'];
    final pending = st == 'Pending';
    final id = '${r['id']}';
    return Container(
      key: ValueKey('manday-req-$id'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              '${mandayHuman(_num(hours), c?['md_hours_per_day'] == null ? null : _num(c!['md_hours_per_day']))} · ${c?['contract_no'] ?? 'SC #${r['contract_id']}'}',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
            child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 6),
        ]),
        if ('${r['note'] ?? ''}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${r['note']}', style: theme.textTheme.bodySmall)),
        if (st == 'Rejected' && '${r['reject_reason'] ?? ''}'.trim().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('${tr('เหตุผล')}: ${r['reject_reason']}', style: theme.textTheme.bodySmall?.copyWith(color: cs.error))),
        if (pending && r['approvals_required'] != null && _num(r['approvals_required']) > 1)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('${tr('ลูกค้าเซ็นแล้ว')} ${r['approvals_count'] ?? 0}/${r['approvals_required']}', style: theme.textTheme.bodySmall)),
        if (pending && widget.canEdit)
          Wrap(spacing: 2, children: [
            TextButton.icon(key: ValueKey('manday-approve-$id'), onPressed: _busy == null ? () async {
              if (!await _confirm(r, to: tr('อนุมัติแล้ว'), toColor: const Color(0xFF16A34A), impact: 'หักชั่วโมงจากสัญญาบริการ', confirm: 'อนุมัติ')) return;
              await _run('approve-$id', () async {
              await _api.approveMandayRequest(id);
              _snack(tr('อนุมัติแล้ว'));
              await _load();
              });
            } : null, icon: const Icon(NxI.check, size: 16), label: Text(tr('อนุมัติ'))),
            TextButton.icon(key: ValueKey('manday-reject-$id'), onPressed: _busy == null ? () => _reject(r) : null, icon: Icon(NxI.x, size: 16, color: cs.error), label: Text(tr('ไม่อนุมัติ'), style: TextStyle(color: cs.error))),
            TextButton.icon(key: ValueKey('manday-link-$id'), onPressed: _busy == null ? () => _copyLink(r) : null, icon: const Icon(NxI.link, size: 16), label: Text(tr('ลิงก์เซ็น'))),
            TextButton(key: ValueKey('manday-cancel-$id'), onPressed: _busy == null ? () async {
              if (!await _confirm(r, to: tr('ยกเลิกแล้ว'), toColor: kNxDangerRed, impact: 'ชั่วโมงที่จองไว้จะคืนกลับเข้าสัญญา', confirm: 'ยกเลิกคำขอ')) return;
              await _run('cancel-$id', () async {
                await _api.cancelMandayRequest(id);
                _snack(tr('ยกเลิกคำขอแล้ว'));
                await _load();
              });
            } : null, child: Text(tr('ยกเลิกคำขอ'))),
          ]),
      ]),
    );
  }
}

/// Request form: contract, hours, note and how the customer signs off.
class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.contracts, required this.defaultEmail, this.contactId});
  final List<Map<String, dynamic>> contracts;
  final String defaultEmail;
  final Object? contactId;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  late String _contractId = '${widget.contracts.first['id']}';
  final _hours = TextEditingController();
  final _note = TextEditingController();
  late final _email = TextEditingController(text: widget.defaultEmail);
  String _delivery = 'email';
  String? _error;

  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    _email.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _c => widget.contracts.firstWhere((c) => '${c['id']}' == _contractId);

  void _submit() {
    final h = num.tryParse(_hours.text.trim()) ?? 0;
    final remain = _num(_c['md_remain_hours']);
    if (h <= 0) return setState(() => _error = tr('ระบุจำนวนชั่วโมง'));
    if (h > remain + 1e-6) return setState(() => _error = '${tr('เกินที่คงเหลือของสัญญา')} (${mandayHuman(remain, _num(_c['md_hours_per_day']))})');
    if (_delivery == 'email' && !_emailRe.hasMatch(_email.text.trim())) return setState(() => _error = tr('อีเมลลูกค้าไม่ถูกต้อง'));
    final cid = int.tryParse('${widget.contactId ?? ''}');
    Navigator.pop(context, {
      'contract_id': int.tryParse(_contractId) ?? _contractId,
      'qty': h,
      'unit': 'Hour',
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      'send_sign_email': _delivery != 'none',
      'skip_email': _delivery != 'email',
      if (_delivery == 'email') 'notify_email': _email.text.trim(),
      'related_contact_id': ?cid,
      'access_mode': 'public',
      'expires_preset': '7d',
      'approvals_required': 1,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hpd = _num(_c['md_hours_per_day']);
    final h = num.tryParse(_hours.text.trim()) ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr('ขอใช้ Manday'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: const ValueKey('manday-contract'),
            initialValue: _contractId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('สัญญาบริการ')),
            items: [
              for (final c in widget.contracts)
                DropdownMenuItem(value: '${c['id']}', child: Text('${c['contract_no'] ?? 'SC #${c['id']}'} · ${tr('คงเหลือ')} ${mandayHuman(_num(c['md_remain_hours']), _num(c['md_hours_per_day']))}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _contractId = v ?? _contractId),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('manday-hours'),
            controller: _hours,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('จำนวนชั่วโมง'), helperText: h > 0 ? '= ${mandayHuman(h, hpd)} (${hpd == 0 ? 8 : hpd} ${tr('ชม./วัน')})' : null),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final q in [1, 2, 4, 8])
              ActionChip(label: Text(q == 8 ? '1 ${tr('วัน')}' : '$q ${tr('ชม.')}'), onPressed: () => setState(() => _hours.text = '$q')),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
          const SizedBox(height: 16),
          Text(tr('ให้ลูกค้ายืนยันอย่างไร'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'email', icon: const Icon(NxI.envelope, size: 16), label: Text(tr('อีเมล'))),
              ButtonSegment(value: 'link', icon: const Icon(NxI.link, size: 16), label: Text(tr('ลิงก์'))),
              ButtonSegment(value: 'none', icon: const Icon(NxI.shieldCheck, size: 16), label: Text(tr('ใน CRM'))),
            ],
            selected: {_delivery},
            onSelectionChanged: (s) => setState(() => _delivery = s.first),
          ),
          if (_delivery == 'email') ...[
            const SizedBox(height: 10),
            TextField(key: const ValueKey('manday-email'), controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('อีเมลลูกค้า'))),
          ],
          if (_delivery == 'link') Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('ส่งแล้วแอปจะคัดลอกลิงก์ให้ลูกค้าเซ็นให้'), style: theme.textTheme.bodySmall)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('manday-submit'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: _submit, child: Text(tr('ส่งคำขอ'))),
        ]),
      ),
    );
  }
}
