import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/nx_skeleton.dart';
import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../deep_link_loaders.dart';
import 'case_manday.dart' show mandayHuman;
import 'contract_flows.dart' show contractStatusLabel;

num _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

void _snack(BuildContext context, String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

/// Pick a Workspace board (writable). Returns `(id, name, code)`.
Future<({int id, String name, String code})?> pickWorkspaceBoard(BuildContext context, {String? title}) {
  return showModalBottomSheet<({int id, String name, String code})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * 0.7, child: _BoardPicker(title: title ?? tr('เลือกบอร์ด'))),
  );
}

class _BoardPicker extends StatefulWidget {
  const _BoardPicker({required this.title});
  final String title;
  @override
  State<_BoardPicker> createState() => _BoardPickerState();
}

class _BoardPickerState extends State<_BoardPicker> {
  List<Map<String, dynamic>>? _boards;
  String _q = '';
  @override
  void initState() {
    super.initState();
    context.read<AppConfig>().apiClient.getBoards(writable: true).then((b) {
      if (mounted) setState(() => _boards = b);
    }).catchError((_) {
      if (mounted) setState(() => _boards = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = [for (final b in _boards ?? const <Map<String, dynamic>>[]) if ('${b['name'] ?? ''} ${b['code'] ?? ''}'.toLowerCase().contains(_q.toLowerCase())) b];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาบอร์ด')), onChanged: (v) => setState(() => _q = v)),
        ]),
      ),
      Expanded(
        child: _boards == null
            ? const NxSkeletonRows(count: 6, style: NxSkelRowStyle.flat, leading: NxSkelLeading.icon, leadingSize: 36, lines: 2, trailing: NxSkelTrailing.none, top: 0)
            : list.isEmpty
                ? Center(child: Text(tr('ไม่มีบอร์ดที่แก้ไขได้')))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final b = list[i];
                      return ListTile(
                        key: ValueKey('board-pick-${b['id']}'),
                        leading: const Icon(NxI.kanban),
                        title: Text('${b['name'] ?? ''}'),
                        subtitle: '${b['code'] ?? ''}'.isEmpty ? null : Text('${b['code']}'),
                        onTap: () => Navigator.pop(context, (id: int.tryParse('${b['id']}') ?? 0, name: '${b['name'] ?? ''}', code: '${b['code'] ?? ''}')),
                      );
                    },
                  ),
      ),
    ]);
  }
}

void openWorkspaceResult(BuildContext context, Map<String, dynamic> r) {
  final board = '${r['board_id'] ?? ''}';
  final task = '${r['task_id'] ?? ''}';
  if (board.isEmpty) return;
  if (task.isNotEmpty && task != 'null') {
    nxPush<void>(context, TaskByIdLoader(boardId: board, taskId: task));
  } else {
    nxPush<void>(context, BoardByIdLoader(boardId: board));
  }
}

Widget _sectionCard(BuildContext context, {required IconData icon, required String title, required List<Widget> children, Key? key}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return Container(
    key: key,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 10),
      ...children,
    ]),
  );
}

// ============================================================ contract

/// Service contract tools (same as the web): Re-New, resend the sign link,
/// move Manday to the customer account, and the renewal history.
class ContractExtrasPanel extends StatefulWidget {
  const ContractExtrasPanel({super.key, required this.id, required this.row, required this.canEdit, this.onChanged});
  final String id;
  final Map<String, dynamic> row;
  final bool canEdit;
  final VoidCallback? onChanged;

  @override
  State<ContractExtrasPanel> createState() => _ContractExtrasPanelState();
}

class _ContractExtrasPanelState extends State<ContractExtrasPanel> {
  List<Map<String, dynamic>> _series = const [];
  String? _busy;

  ApiClient get _api => context.read<AppConfig>().apiClient;
  String get _status {
    final s = '${widget.row['contract_status'] ?? ''}';
    if (s == 'Active') {
      final end = DateTime.tryParse('${widget.row['end_date'] ?? ''}'.split('T').first);
      if (end != null && end.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) return 'Expired';
    }
    return s;
  }

  @override
  void initState() {
    super.initState();
    _api.getContractRenewalSeries(widget.id).then((r) {
      if (mounted) setState(() => _series = extractMapList(r['list']));
    }).catchError((_) {});
  }

  Future<void> _renew() async {
    setState(() => _busy = 'renew');
    try {
      final p = await _api.renewServiceContract(widget.id);
      if (!mounted) return;
      final existing = p['existing_draft_id'];
      if (existing != null) {
        _snack(context, '${tr('มีฉบับต่ออายุที่เป็นร่างอยู่แล้ว')} ${p['existing_draft_no'] ?? ''}');
        nxPush<void>(context, EntityByIdLoader(module: 'service_contract', id: '$existing'));
        return;
      }
      final d = p['defaults'] is Map ? Map<String, dynamic>.from(p['defaults'] as Map) : <String, dynamic>{};
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('ต่ออายุสัญญา (Re-New)')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tr('สร้างสัญญาฉบับใหม่ (ร่าง) ต่อจาก')} ${widget.row['contract_no'] ?? ''}'),
            const SizedBox(height: 10),
            if (d['start_date'] != null) Text('${tr('เริ่ม')}: ${thaiDate(d['start_date'])}'),
            if (d['end_date'] != null) Text('${tr('สิ้นสุด')}: ${thaiDate(d['end_date'])}'),
            if (p['next_version'] != null) Text('${tr('ฉบับที่')} ${p['next_version']}'),
            const SizedBox(height: 8),
            Text(tr('คัดลอกลูกค้า สินค้า/บริการ เงื่อนไข และสิทธิ์ Manday — แก้ไขได้ก่อนส่งอนุมัติ'), style: Theme.of(ctx).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(key: const ValueKey('renew-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('สร้างฉบับต่ออายุ'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final r = await _api.renewServiceContract(widget.id, commit: true);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _snack(context, '${tr('สร้างฉบับต่ออายุแล้ว')} ${r['contract_no'] ?? ''}');
      final id = '${r['id'] ?? ''}';
      if (id.isNotEmpty) nxPush<void>(context, EntityByIdLoader(module: 'service_contract', id: id));
    } catch (e) {
      if (mounted) _snack(context, tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _resendSign() async {
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResendSignSheet(email: '${widget.row['contact_email'] ?? ''}', contactId: widget.row['related_contact_id']),
    );
    if (body == null || !mounted) return;
    setState(() => _busy = 'sign');
    try {
      final r = await _api.resendServiceContractSign(widget.id, body);
      final url = r['sign_link'] is Map ? '${r['sign_link']['url'] ?? ''}' : '';
      if (!mounted) return;
      if (url.isEmpty) {
        _snack(context, tr('สร้างลิงก์ไม่สำเร็จ'));
        return;
      }
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      _snack(context, body['skip_email'] == true ? tr('สร้างลิงก์ใหม่แล้ว · คัดลอกลิงก์ให้แล้ว') : '${tr('ส่งลิงก์เซ็นใหม่ทางอีเมลแล้ว')} · ${tr('คัดลอกลิงก์ให้แล้ว')}');
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) _snack(context, tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _transfer() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MandayTransferSheet(contractId: widget.id),
    );
    if (done == true) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final canRenew = st == 'Expired' || (st == 'Active' && widget.canEdit);
    final canResend = widget.canEdit && st == 'Pending_Approval';
    final canTransfer = widget.canEdit && st == 'Active' && '${widget.row['contract_form'] ?? ''}' != 'Indirect' && '${widget.row['related_account_id'] ?? ''}'.isNotEmpty;
    final theme = Theme.of(context);
    if (!canRenew && !canResend && !canTransfer && _series.length < 2) return const SizedBox.shrink();
    Widget busyIcon(String k, IconData i) => _busy == k ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(i, size: 18);
    return _sectionCard(
      context,
      key: const ValueKey('contract-extras'),
      icon: NxI.arrowClockwise,
      title: tr('ต่ออายุ / ลิงก์เซ็น / Manday'),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (canRenew) FilledButton.tonalIcon(key: const ValueKey('contract-renew'), onPressed: _busy == null ? _renew : null, icon: busyIcon('renew', NxI.arrowClockwise), label: Text(tr('ต่ออายุ (Re-New)'))),
          if (canResend) OutlinedButton.icon(key: const ValueKey('contract-resend-sign'), onPressed: _busy == null ? _resendSign : null, icon: busyIcon('sign', NxI.link), label: Text(tr('ส่งลิงก์เซ็นใหม่'))),
          if (canTransfer) OutlinedButton.icon(key: const ValueKey('contract-transfer'), onPressed: _busy == null ? _transfer : null, icon: const Icon(NxI.arrowRight, size: 18), label: Text(tr('โอน Manday เข้าบัญชีลูกค้า'))),
        ]),
        if (_series.length > 1) ...[
          const SizedBox(height: 12),
          Text(tr('ประวัติการต่ออายุ'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
          for (final s in _series)
            ListTile(
              key: ValueKey('renew-series-${s['id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${s['renewal_version'] ?? 1}', style: const TextStyle(fontSize: 12))),
              title: Text('${s['contract_no'] ?? '#${s['id']}'}${'${s['id']}' == widget.id ? ' · ${tr('ฉบับนี้')}' : ''}'),
              subtitle: Text('${contractStatusLabel(s['contract_status'])} · ${thaiDate(s['start_date'])} – ${thaiDate(s['end_date'])}'),
              onTap: '${s['id']}' == widget.id ? null : () => nxPush<void>(context, EntityByIdLoader(module: 'service_contract', id: '${s['id']}')),
            ),
        ],
      ],
    );
  }
}

class _ResendSignSheet extends StatefulWidget {
  const _ResendSignSheet({required this.email, this.contactId});
  final String email;
  final Object? contactId;
  @override
  State<_ResendSignSheet> createState() => _ResendSignSheetState();
}

class _ResendSignSheetState extends State<_ResendSignSheet> {
  bool _email = false; // web default: copy the link only
  late final _to = TextEditingController(text: widget.email);
  String _expires = '7d';
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('ส่งลิงก์เซ็นใหม่'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr('ลิงก์เดิมจะใช้ไม่ได้'), style: theme.textTheme.bodySmall),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _email, title: Text(tr('ส่งอีเมลถึงผู้ลงนามด้วย')), onChanged: (v) => setState(() => _email = v)),
        if (_email) TextField(key: const ValueKey('resend-email'), controller: _to, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('อีเมลผู้ลงนาม'))),
        const SizedBox(height: 12),
        Text(tr('ลิงก์หมดอายุใน'), style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final (v, l) in const [('24h', '24 ชม.'), ('3d', '3 วัน'), ('7d', '7 วัน'), ('14d', '14 วัน'), ('30d', '30 วัน')])
            ChoiceChip(label: Text(tr(l)), selected: _expires == v, onSelected: (_) => setState(() => _expires = v)),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('resend-ok'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            if (_email && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_to.text.trim())) {
              setState(() => _error = tr('อีเมลผู้ลงนามไม่ถูกต้อง'));
              return;
            }
            final cid = int.tryParse('${widget.contactId ?? ''}');
            Navigator.pop(context, {
              'skip_email': !_email,
              if (_email) 'notify_email': _to.text.trim(),
              'related_contact_id': ?cid,
              'access_mode': 'public',
              'expires_preset': _expires,
            });
          },
          child: Text(tr('สร้างลิงก์ใหม่')),
        ),
      ]),
    );
  }
}

class _MandayTransferSheet extends StatefulWidget {
  const _MandayTransferSheet({required this.contractId});
  final String contractId;
  @override
  State<_MandayTransferSheet> createState() => _MandayTransferSheetState();
}

class _MandayTransferSheetState extends State<_MandayTransferSheet> {
  Map<String, dynamic>? _p;
  Object? _error;
  final _hours = TextEditingController();
  final _note = TextEditingController();
  bool _confirm = false;
  bool _busy = false;
  Map<String, dynamic>? _done;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _api.getContractMandayTransferPreview(widget.contractId).then((p) {
      if (mounted) setState(() => _p = p);
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  String _blockText(Object? r) => tr(switch ('$r') {
    'no_account' => 'สัญญานี้ยังไม่ผูกบัญชีลูกค้า',
    'not_active' => 'โอนได้เฉพาะสัญญาที่มีผล',
    'indirect' => 'สัญญาแบบ Indirect โอนไม่ได้',
    'pool_missing' => 'บัญชีลูกค้ายังไม่มีกระเป๋า Manday',
    _ => 'โอนไม่ได้',
  });

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await _api.transferContractMandayToAccount(widget.contractId, {
        'qty': num.parse(_hours.text.trim()),
        'unit': 'Hour',
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        'account_id': _p!['account_id'],
      });
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _done = r);
    } catch (e) {
      if (mounted) {
        setState(() => _confirm = false);
        _snack(context, tr(formatApiError(e)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = _p;
    Widget body;
    if (_error != null) {
      body = Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error));
    } else if (p == null) {
      // Contract card: heading, key-value lines.
      body = const NxSkeletonKeyValueCard(key: ValueKey('service-contract-skeleton'), rows: 4, total: false);
    } else {
      final c = p['contract'] is Map ? Map<String, dynamic>.from(p['contract'] as Map) : <String, dynamic>{};
      final hpd = _n(c['md_hours_per_day']) == 0 ? 8 : _n(c['md_hours_per_day']);
      final remain = _n(c['md_remain_hours']);
      final available = _n(c['available_hours']);
      final h = num.tryParse(_hours.text.trim()) ?? 0;
      if (_done != null) {
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(NxI.check, size: 44, color: Color(0xFF16A34A)),
          const SizedBox(height: 8),
          Text('${tr('โอนแล้ว')} ${mandayHuman(_n(_done!['hours']), hpd)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${tr('สัญญาคงเหลือ')} ${mandayHuman(_n(_done!['contract_md_remain_hours']), hpd)} · ${tr('บัญชีคงเหลือ')} ${mandayHuman(_n(_done!['account_hours_remain']), hpd)}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('เสร็จ'))),
        ]);
      } else if (p['can_transfer'] != true) {
        body = Text(_blockText(p['block_reason']), style: TextStyle(color: cs.error));
      } else {
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${tr('ไปที่บัญชี')}: ${p['account_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${tr('สัญญาคงเหลือ')} ${mandayHuman(remain, hpd)} · ${tr('ว่าง')} ${mandayHuman(available, hpd)} · ${tr('บัญชีมี')} ${mandayHuman(_n(p['account_hours_remain']), hpd)}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('transfer-hours'), controller: _hours, enabled: !_confirm, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: tr('จำนวนชั่วโมง')), onChanged: (_) => setState(() {})),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final (l, f) in [('ทั้งหมด', 1.0), ('50%', 0.5), ('25%', 0.25)])
              ActionChip(label: Text(tr(l)), onPressed: _confirm ? null : () => setState(() => _hours.text = (available * f).toStringAsFixed(available * f == (available * f).roundToDouble() ? 0 : 1))),
          ]),
          if (h > available && h <= remain) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('เกินชั่วโมงว่าง — จะดึงจากที่รออนุมัติอยู่'), style: const TextStyle(color: Color(0xFFD97706)))),
          if (h > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${tr('หลังโอน')}: ${tr('สัญญา')} ${mandayHuman(remain - h, hpd)} · ${tr('บัญชี')} ${mandayHuman(_n(p['account_hours_remain']) + h, hpd)}', style: theme.textTheme.bodySmall)),
          const SizedBox(height: 8),
          TextField(controller: _note, enabled: !_confirm, decoration: InputDecoration(labelText: tr('หมายเหตุ'))),
          const SizedBox(height: 16),
          if (!_confirm)
            FilledButton(key: const ValueKey('transfer-next'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), onPressed: h > 0 && h <= remain ? () => setState(() => _confirm = true) : null, child: Text(tr('ถัดไป')))
          else
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _busy ? null : () => setState(() => _confirm = false), child: Text(tr('แก้ไข')))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(key: const ValueKey('transfer-ok'), onPressed: _busy ? null : _submit, child: Text('${tr('ยืนยันโอน')} ${mandayHuman(h, hpd)}'))),
            ]),
        ]);
      }
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('โอน Manday เข้าบัญชีลูกค้า'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          body,
        ]),
      ),
    );
  }
}

// ============================================================ case / job

/// Case → Workspace: work items from a template, or one task on a board.
class CaseWorkspacePanel extends StatefulWidget {
  const CaseWorkspacePanel({super.key, required this.caseId, required this.row});
  final String caseId;
  final Map<String, dynamic> row;
  @override
  State<CaseWorkspacePanel> createState() => _CaseWorkspacePanelState();
}

class _CaseWorkspacePanelState extends State<CaseWorkspacePanel> {
  String? _busy;
  ApiClient get _api => context.read<AppConfig>().apiClient;

  Future<void> _fromTemplate() async {
    final pick = await showModalBottomSheet<({int templateId, ({int id, String name, String code})? board})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CaseTemplateSheet(),
    );
    if (pick == null || !mounted) return;
    setState(() => _busy = 'tpl');
    try {
      final r = await _api.generateCaseWork(widget.caseId, {
        'template_id': pick.templateId,
        'board_id': pick.board?.id,
        'overrides': const <String, dynamic>{},
        'include_case_context': true,
        'locale': L10n.isEn ? 'en' : 'th',
      });
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final n = r['created_count'] ?? 0;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${tr('สร้างงานแล้ว')} $n ${tr('รายการ')}'),
          content: Text('${tr('บอร์ด')} ${r['board_name'] ?? r['board_code'] ?? ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ปิด'))),
            FilledButton(key: const ValueKey('case-work-open-board'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('เปิดบอร์ด'))),
          ],
        ),
      );
      if (go == true && mounted) openWorkspaceResult(context, {'board_id': r['board_id']});
    } catch (e) {
      if (mounted) _snack(context, tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _task() async {
    final b = await pickWorkspaceBoard(context, title: tr('สร้างงานบนบอร์ด'));
    if (b == null || !mounted) return;
    setState(() => _busy = 'task');
    try {
      final r = await _api.createCaseWorkspaceTask(widget.caseId, boardId: b.id);
      if (!mounted) return;
      _snack(context, '${tr('สร้างงานบนบอร์ดแล้ว')} · ${b.name}');
      openWorkspaceResult(context, r);
    } catch (e) {
      if (mounted) _snack(context, tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget busyIcon(String k, IconData i) => _busy == k ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(i, size: 18);
    return _sectionCard(context, key: const ValueKey('case-workspace'), icon: NxI.kanban, title: tr('งานใน Workspace'), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(key: const ValueKey('case-work-template'), onPressed: _busy == null ? _fromTemplate : null, icon: busyIcon('tpl', NxI.listChecks), label: Text(tr('สร้างงานจากเทมเพลต'))),
        OutlinedButton.icon(key: const ValueKey('case-workspace-task'), onPressed: _busy == null ? _task : null, icon: busyIcon('task', NxI.plus), label: Text(tr('สร้าง Task บนบอร์ด'))),
      ]),
    ]);
  }
}

class _CaseTemplateSheet extends StatefulWidget {
  @override
  State<_CaseTemplateSheet> createState() => _CaseTemplateSheetState();
}

class _CaseTemplateSheetState extends State<_CaseTemplateSheet> {
  List<Map<String, dynamic>>? _list;
  Object? _error;
  int? _sel;
  ({int id, String name, String code})? _board;

  @override
  void initState() {
    super.initState();
    context.read<AppConfig>().apiClient.getCaseWorkTemplates().then((l) {
      if (!mounted) return;
      setState(() {
        _list = l;
        _sel = l.isEmpty ? null : int.tryParse('${l.first['id']}');
      });
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  int _count(Object? tree) {
    var n = 0;
    void walk(Object? t) {
      if (t is List) {
        for (final x in t) {
          walk(x);
        }
      } else if (t is Map) {
        n++;
        walk(t['children']);
      }
    }
    walk(tree);
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _list;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('สร้างงานจากเทมเพลต'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        Expanded(
          child: _error != null
              ? Center(child: Text(tr(formatApiError(_error!))))
              : list == null
                  ? const NxSkeletonRows(count: 5, style: NxSkelRowStyle.flat, leading: NxSkelLeading.avatar, leadingSize: 22, lines: 2, trailing: NxSkelTrailing.none, top: 0)
                  : list.isEmpty
                      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('ยังไม่มีเทมเพลตงานของเคส — สร้างได้ที่เว็บ (ตั้งค่า › เทมเพลตงานเคส)'), textAlign: TextAlign.center)))
                      : ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                          for (final t in list)
                            RadioListTile<int>(
                              key: ValueKey('case-tpl-${t['id']}'),
                              value: int.tryParse('${t['id']}') ?? 0,
                              groupValue: _sel,
                              onChanged: (v) => setState(() => _sel = v),
                              title: Text('${t['name'] ?? ''}'),
                              subtitle: Text([if ('${t['category'] ?? ''}'.isNotEmpty) '${t['category']}', '${_count(t['tree'])} ${tr('รายการ')}'].join(' · ')),
                            ),
                        ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: OutlinedButton.icon(
            onPressed: () async {
              final b = await pickWorkspaceBoard(context);
              if (b != null) setState(() => _board = b);
            },
            icon: const Icon(NxI.kanban, size: 18),
            label: Text(_board?.name ?? tr('บอร์ดบริการของเคส (อัตโนมัติ)')),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: FilledButton(
              key: const ValueKey('case-tpl-ok'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _sel == null ? null : () => Navigator.pop(context, (templateId: _sel!, board: _board)),
              child: Text(tr('สร้างงาน')),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Job → create a Task or an Epic on a Workspace board.
class JobWorkspaceButton extends StatefulWidget {
  const JobWorkspaceButton({super.key, required this.jobId});
  final String jobId;
  @override
  State<JobWorkspaceButton> createState() => _JobWorkspaceButtonState();
}

class _JobWorkspaceButtonState extends State<JobWorkspaceButton> {
  bool _busy = false;

  Future<void> _go() async {
    final b = await pickWorkspaceBoard(context, title: tr('ส่งงานนี้เข้า Workspace'));
    if (b == null || !mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text('${tr('สร้างบน')} ${b.name}'), children: [
        SimpleDialogOption(key: const ValueKey('job-ws-task'), onPressed: () => Navigator.pop(ctx, 'task'), child: ListTile(leading: const Icon(NxI.checkSquare), title: Text(tr('Task (งานเดียว)')))),
        SimpleDialogOption(key: const ValueKey('job-ws-epic'), onPressed: () => Navigator.pop(ctx, 'epic'), child: ListTile(leading: const Icon(NxI.lightning), title: Text(tr('Epic (โครงงานใหญ่)')))),
      ]),
    );
    if (mode == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await context.read<AppConfig>().apiClient.createJobWorkspace(widget.jobId, boardId: b.id, mode: mode);
      if (!mounted) return;
      _snack(context, '${tr('สร้างใน Workspace แล้ว')} · ${b.name}');
      openWorkspaceResult(context, mode == 'epic' ? {'board_id': r['board_id']} : r);
    } catch (e) {
      if (mounted) _snack(context, tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('job-workspace'),
    onPressed: _busy ? null : _go,
    icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.kanban, size: 18),
    label: Text(tr('ส่งเข้า Workspace (Task / Epic)')),
  );
}

// ============================================================ deal

/// Deal ↔ Workspace board: open / change / unlink, or create / link one.
class DealWorkspacePanel extends StatefulWidget {
  const DealWorkspacePanel({super.key, required this.dealId, required this.canEdit});
  final String dealId;
  final bool canEdit;
  @override
  State<DealWorkspacePanel> createState() => _DealWorkspacePanelState();
}

class _DealWorkspacePanelState extends State<DealWorkspacePanel> {
  Map<String, dynamic>? _ws;

  Future<void> _load() async {
    try {
      final r = await context.read<AppConfig>().apiClient.getDealWorkspace(widget.dealId);
      if (mounted) setState(() => _ws = r);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final ws = _ws;
    if (ws == null) return const SizedBox.shrink();
    final board = ws['board'] is Map ? Map<String, dynamic>.from(ws['board'] as Map) : null;
    if (board == null && !widget.canEdit) return const SizedBox.shrink();
    return _sectionCard(context, key: const ValueKey('deal-workspace'), icon: NxI.kanban, title: tr('บอร์ดงานของดีล'), children: [
      if (board != null) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(NxI.kanban),
          title: Text('${board['name'] ?? ''}'),
          subtitle: Text('${board['code'] ?? ''}'),
          trailing: const Icon(NxI.caretRight, size: 16),
          onTap: () => openWorkspaceResult(context, {'board_id': board['id']}),
        ),
        if (widget.canEdit)
          Wrap(spacing: 8, children: [
            TextButton(onPressed: () async {
              if (await showDealWorkspaceHandoff(context, widget.dealId, initialMode: 'link') && mounted) _load();
            }, child: Text(tr('เปลี่ยนบอร์ด'))),
            TextButton(
              key: const ValueKey('deal-ws-unlink'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('ยกเลิกการผูกบอร์ด?')),
                    content: Text(tr('บอร์ดและงานยังอยู่ แค่ไม่ผูกกับดีลนี้')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ยกเลิกการผูก'))),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
                try {
                  await context.read<AppConfig>().apiClient.unlinkDealWorkspace(widget.dealId);
                  _load();
                } catch (e) {
                  if (mounted) _snack(context, tr(formatApiError(e)));
                }
              },
              child: Text(tr('ยกเลิกการผูก')),
            ),
          ]),
      ] else
        FilledButton.tonalIcon(
          key: const ValueKey('deal-ws-create'),
          onPressed: () async {
            if (await showDealWorkspaceHandoff(context, widget.dealId) && mounted) _load();
          },
          icon: const Icon(NxI.plus, size: 18),
          label: Text(tr('สร้าง / ผูกบอร์ดงาน')),
        ),
    ]);
  }
}

/// Create a board for the deal (name, code, kickoff tasks) or link one.
/// Returns true when linked. Opens the board afterwards like the web.
Future<bool> showDealWorkspaceHandoff(BuildContext context, String dealId, {String initialMode = 'create', bool afterWon = false}) async {
  final api = context.read<AppConfig>().apiClient;
  Map<String, dynamic> ws;
  try {
    ws = await api.getDealWorkspace(dealId);
  } catch (e) {
    if (context.mounted) _snack(context, tr(formatApiError(e)));
    return false;
  }
  if (!context.mounted) return false;
  final r = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DealHandoffSheet(dealId: dealId, ws: ws, mode: initialMode, afterWon: afterWon),
  );
  if (r == null || !context.mounted) return false;
  _snack(context, '${r['created'] == true ? tr('สร้างบอร์ดแล้ว') : tr('ผูกบอร์ดแล้ว')} · ${r['board_name'] ?? ''}');
  openWorkspaceResult(context, {'board_id': r['board_id']});
  return true;
}

class _DealHandoffSheet extends StatefulWidget {
  const _DealHandoffSheet({required this.dealId, required this.ws, required this.mode, required this.afterWon});
  final String dealId;
  final Map<String, dynamic> ws;
  final String mode;
  final bool afterWon;
  @override
  State<_DealHandoffSheet> createState() => _DealHandoffSheetState();
}

class _DealHandoffSheetState extends State<_DealHandoffSheet> {
  late String _mode = widget.mode;
  late final _name = TextEditingController(text: '${widget.ws['suggest_name'] ?? ''}');
  late final _code = TextEditingController(text: '${widget.ws['suggest_code'] ?? ''}');
  bool _kickoff = true;
  ({int id, String name, String code})? _board;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_mode == 'link' && _board == null) return setState(() => _error = tr('เลือกบอร์ด'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await context.read<AppConfig>().apiClient.linkDealWorkspace(widget.dealId, _mode == 'link'
          ? {'mode': 'link', 'board_id': _board!.id}
          : {'mode': 'create', if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(), if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(), 'seed_kickoff': _kickoff});
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) setState(() => _error = tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.afterWon ? tr('ปิดชนะแล้ว — สร้างบอร์ดงานส่งมอบ?') : tr('บอร์ดงานของดีล'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'create', icon: const Icon(NxI.plus, size: 16), label: Text(tr('สร้างบอร์ดใหม่'))),
              ButtonSegment(value: 'link', icon: const Icon(NxI.link, size: 16), label: Text(tr('ผูกบอร์ดที่มี'))),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          if (_mode == 'create') ...[
            TextField(key: const ValueKey('deal-ws-name'), controller: _name, decoration: InputDecoration(labelText: tr('ชื่อบอร์ด'))),
            const SizedBox(height: 8),
            TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('รหัสบอร์ด'))),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: _kickoff, onChanged: (v) => setState(() => _kickoff = v ?? true), title: Text(tr('สร้างงานเริ่มต้นโครงการ (Kickoff)'))),
          ] else
            OutlinedButton.icon(
              key: const ValueKey('deal-ws-pick'),
              onPressed: () async {
                final b = await pickWorkspaceBoard(context);
                if (b != null) setState(() => _board = b);
              },
              icon: const Icon(NxI.kanban, size: 18),
              label: Text(_board?.name ?? tr('เลือกบอร์ด')),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('deal-ws-ok'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _busy ? null : _submit,
            child: Text(_mode == 'create' ? tr('สร้างบอร์ด') : tr('ผูกบอร์ด')),
          ),
          if (widget.afterWon) TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ภายหลัง'))),
        ]),
      ),
    );
  }
}
