import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/journey_rules.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../deep_link_loaders.dart';

/// Friendly Thai text for Service Journey error codes (web wording).
String journeyErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    switch (e.errorCode) {
      case 'VERSION_CONFLICT':
        return 'มีคนเปลี่ยนสถานะไปแล้ว — โหลดข้อมูลล่าสุดให้แล้ว';
      case 'JOB_SIGNATURE_INCOMPLETE':
        return 'ยังเก็บลายเซ็นไม่ครบ — เซ็นให้ครบก่อนปิดงาน';
      case 'QUOTATION_LOCKED':
        return 'ใบเสนอราคานี้ถูกล็อก แก้ไขได้เฉพาะสถานะเปิด/ไม่อนุมัติ — ใช้ Revise หรือทำสำเนา';
      case 'QUOTATION_CLOSED':
        return 'ใบเสนอราคานี้จบแล้ว (ปิดการขาย/ยกเลิก/มีฉบับใหม่) — ทำสำเนาเป็นใบใหม่แทน';
      case 'QUOTATION_NOT_APPROVED':
        return 'ต้องอนุมัติใบเสนอราคาก่อนปิดการขายแบบชนะ';
      case 'QUOTATION_OUTCOME_REQUIRED':
        return 'ปิดการขายต้องเลือกผล ชนะ/แพ้ พร้อมเหตุผล';
      case 'QUOTATION_STATUS_SYSTEM':
        return 'สถานะนี้เปลี่ยนตามขั้นตอน (ขออนุมัติ/อนุมัติ/ปิดการขาย) ไม่ได้ตั้งเอง';
      case 'MODULE_DISABLED':
        return 'ธุรกิจนี้ยังไม่เปิดเมนูใบสั่งงาน';
      case 'SMTP_NOT_CONFIGURED':
        return 'ยังไม่ได้ตั้งค่าอีเมลส่งออกของระบบ';
    }
  }
  return formatApiError(e);
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(text))));
}

String _userName(Map<String, dynamic> u) =>
    (u['display_name'] ?? u['name'] ?? u['full_name'] ?? '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim()).toString();
String _userId(Map<String, dynamic> u) => (u['user_id'] ?? u['id'] ?? '').toString();

/// Search + pick one business user.
Future<Map<String, dynamic>?> pickJourneyUser(BuildContext context, {String title = 'เลือกผู้รับงาน', Set<String> exclude = const {}}) async {
  final api = context.read<AppConfig>().apiClient;
  List<Map<String, dynamic>> users = const [];
  try {
    users = await api.getUsersCached();
  } catch (_) {}
  if (!context.mounted) return null;
  return showAppBottomSheet<Map<String, dynamic>>(
    context: context,
    title: tr(title),
    child: _UserPicker(users: [for (final u in users) if (!exclude.contains(_userId(u))) u]),
  );
}

class _UserPicker extends StatefulWidget {
  const _UserPicker({required this.users});
  final List<Map<String, dynamic>> users;

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final rows = [
      for (final u in widget.users)
        if (q.isEmpty || _userName(u).toLowerCase().contains(q) || (u['email'] ?? '').toString().toLowerCase().contains(q)) u,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('journey-user-search'),
          decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass), hintText: tr('ค้นหาชื่อ / อีเมล')),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('ไม่พบผู้ใช้'))),
        for (final u in rows.take(60))
          ListTile(
            key: ValueKey('journey-user-${_userId(u)}'),
            leading: CircleAvatar(child: Text(_userName(u).isEmpty ? '?' : _userName(u).characters.first)),
            title: Text(_userName(u)),
            subtitle: (u['email'] ?? '').toString().isEmpty ? null : Text(u['email'].toString()),
            onTap: () => Navigator.pop(context, u),
          ),
      ],
    );
  }
}

/// Generic confirm sheet with an optional note / reason and a checkbox.
class _ActionForm {
  _ActionForm({this.check = true, this.scope = 'job_and_activities'});
  String note = '';
  bool check;
  String scope;
}

Future<_ActionForm?> _askForm(
  BuildContext context, {
  required String title,
  String? message,
  String? noteLabel,
  bool noteRequired = false,
  List<String> noteChips = const [],
  String? checkLabel,
  bool checkDefault = true,
  List<(String, String)> scopes = const [],
  String? scopeDefault,
  required String confirm,
  bool danger = false,
  Widget? extra,
}) {
  final form = _ActionForm(check: checkDefault, scope: scopeDefault ?? (scopes.isEmpty ? '' : scopes.first.$1));
  final ctrl = TextEditingController();
  return showAppBottomSheet<_ActionForm>(
    context: context,
    title: tr(title),
    child: StatefulBuilder(builder: (ctx, setS) {
      final cs = Theme.of(ctx).colorScheme;
      final canGo = !noteRequired || ctrl.text.trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message != null) ...[
            Text(tr(message), style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
          ],
          ?extra,
          if (scopes.isNotEmpty)
            RadioGroup<String>(
              groupValue: form.scope,
              onChanged: (v) => setS(() => form.scope = v ?? form.scope),
              child: Column(
                children: [
                  for (final s in scopes)
                    RadioListTile<String>(
                      key: ValueKey('scope-${s.$1}'),
                      contentPadding: EdgeInsets.zero,
                      value: s.$1,
                      title: Text(tr(s.$2)),
                    ),
                ],
              ),
            ),
          if (noteLabel != null) ...[
            TextField(
              key: const ValueKey('journey-note'),
              controller: ctrl,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: tr(noteLabel) + (noteRequired ? ' *' : '')),
              onChanged: (_) => setS(() {}),
            ),
            if (noteChips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in noteChips)
                    ActionChip(
                      label: Text(tr(c)),
                      onPressed: () => setS(() => ctrl.text = tr(c)),
                    ),
                ],
              ),
            ],
          ],
          if (checkLabel != null)
            CheckboxListTile(
              key: const ValueKey('journey-check'),
              contentPadding: EdgeInsets.zero,
              value: form.check,
              title: Text(tr(checkLabel)),
              onChanged: (v) => setS(() => form.check = v ?? false),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton(
              key: const ValueKey('journey-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: danger ? const Color(0xFFE11D48) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: canGo
                  ? () {
                      form.note = ctrl.text.trim();
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx, form);
                    }
                  : null,
              child: Text(tr(confirm), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      );
    }),
  );
}

/// Job workflow actions with the same dialogs as the web
/// (`JobWorkflowActions.jsx`, `JobCloseDialog.jsx`). Returns true when the job changed.
class JobFlows {
  JobFlows._();

  static Future<bool> run(
    BuildContext context, {
    required String jobId,
    required String action,
    required Map<String, dynamic> row,
    Map<String, dynamic>? overview,
    VoidCallback? openSignatures,
  }) async {
    final api = context.read<AppConfig>().apiClient;
    final expected = row['job_status']?.toString();
    try {
      switch (action) {
        case 'accept':
          final f = await _askForm(
            context,
            title: actionLabel('job', 'accept'),
            message: 'งานจะเป็น "กำลังดำเนินการ" และบันทึกเวลารับงาน',
            noteLabel: 'หมายเหตุ',
            checkLabel: 'ส่งอีเมลแจ้งลูกค้า',
            confirm: 'รับงาน',
          );
          if (f == null || !context.mounted) return false;
          await api.jobWorkflowAction(jobId, 'accept', expectedStatus: expected, note: f.note, skipEmail: !f.check);
          if (context.mounted) _snack(context, 'รับงานแล้ว — กำลังดำเนินการ');
          return true;
        case 'forward':
        case 'assign':
          final owner = (row['smownerid'] ?? '').toString();
          final u = await pickJourneyUser(context, title: 'ส่งต่องานให้', exclude: {owner});
          if (u == null || !context.mounted) return false;
          final f = await _askForm(
            context,
            title: 'ส่งต่องานให้ ${_userName(u)}',
            message: 'งานจะเป็น "รอการตอบรับ" จนกว่าผู้รับจะกดรับงาน',
            noteLabel: 'ข้อความถึงผู้รับ',
            checkLabel: 'ส่งอีเมลแจ้งผู้รับ',
            confirm: 'ส่งต่องาน',
          );
          if (f == null || !context.mounted) return false;
          final r = await api.jobWorkflowAction(jobId, 'forward', expectedStatus: expected, note: f.note, ownerId: _userId(u), skipEmail: !f.check);
          if (context.mounted) {
            final mail = (r['email'] is Map && r['email']['sent'] == true) ? ' · ส่งอีเมลแล้ว' : '';
            _snack(context, 'ส่งต่องานให้ ${_userName(u)} แล้ว — รอการตอบรับ$mail');
          }
          return true;
        case 'wait':
          final f = await _askForm(
            context,
            title: actionLabel('job', 'wait'),
            noteLabel: 'รออะไร',
            noteChips: const ['รออะไหล่', 'รอลูกค้ายืนยัน', 'รอเข้าพื้นที่', 'รอทีมอื่น'],
            confirm: 'พักงาน',
            checkLabel: null,
          );
          if (f == null || !context.mounted) return false;
          await api.jobWorkflowAction(jobId, 'wait', expectedStatus: expected, note: f.note);
          if (context.mounted) _snack(context, 'พักงานแล้ว — รอการตอบรับ');
          return true;
        case 'resume':
          await api.jobWorkflowAction(jobId, 'resume', expectedStatus: expected);
          if (context.mounted) _snack(context, 'ทำงานต่อแล้ว');
          return true;
        case 'cancel':
          final f = await _askForm(
            context,
            title: actionLabel('job', 'cancel'),
            message: 'กิจกรรมที่ยังไม่เสร็จของงานนี้จะถูกยกเลิกด้วย',
            noteLabel: 'เหตุผลที่ยกเลิก',
            noteRequired: true,
            noteChips: const ['ลูกค้ายกเลิก', 'ซ้ำกับงานอื่น', 'ข้อมูลไม่ถูกต้อง'],
            confirm: 'ยกเลิกงาน',
            danger: true,
          );
          if (f == null || !context.mounted) return false;
          await api.jobWorkflowAction(jobId, 'cancel', expectedStatus: expected, reason: f.note);
          if (context.mounted) _snack(context, 'ยกเลิกงานแล้ว');
          return true;
        case 'close':
          return await _close(context, jobId, expected, openSignatures);
        case 'reopen':
          final f = await _askForm(
            context,
            title: actionLabel('job', 'reopen'),
            message: 'งานจะกลับมาเป็น "กำลังดำเนินการ"',
            noteLabel: 'เหตุผล',
            checkLabel: 'เปิดกิจกรรมที่ปิดพร้อมงานกลับด้วย',
            checkDefault: false,
            confirm: 'เปิดงานกลับ',
          );
          if (f == null || !context.mounted) return false;
          await api.reopenJob(jobId, reopenActivities: f.check, note: f.note);
          if (context.mounted) _snack(context, 'เปิดงานกลับแล้ว');
          return true;
      }
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      if (e is ApiEnvelopeException && e.errorCode == 'VERSION_CONFLICT') return true; // reload
    }
    return false;
  }

  static Future<bool> _close(BuildContext context, String jobId, String? expected, VoidCallback? openSignatures) async {
    final api = context.read<AppConfig>().apiClient;
    Map<String, dynamic> preview = const {};
    Map<String, dynamic> sigs = const {};
    try {
      preview = await api.getJobClosePreview(jobId);
    } catch (_) {}
    try {
      sigs = await api.getJobSignatures(jobId);
    } catch (_) {}
    if (!context.mounted) return false;
    if (preview['can_close'] == false) {
      _snack(context, 'ปิดงานได้เฉพาะเจ้าของงานหรือผู้ดูแล');
      return false;
    }
    final slots = [for (final s in (sigs['slots'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
    final missing = [for (final s in slots) if ((s['signature_path'] ?? '').toString().isEmpty) s];
    final open = (preview['open_activities'] is num) ? (preview['open_activities'] as num).toInt() : int.tryParse('${preview['open_activities'] ?? 0}') ?? 0;
    final theme = Theme.of(context);
    final f = await _askForm(
      context,
      title: actionLabel('job', 'close'),
      message: open > 0 ? 'มีกิจกรรมที่ยังไม่เสร็จ $open รายการ' : 'กิจกรรมเสร็จครบแล้ว',
      extra: missing.isEmpty
          ? null
          : Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFD97706).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('ลายเซ็นที่ยังขาด'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  for (final s in missing) Text('• ${s['position_th'] ?? s['slot_key']}'),
                  if (openSignatures != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('close-go-sign'),
                        icon: const Icon(NxI.penLine, size: 16),
                        label: Text(tr('ไปเซ็น')),
                        onPressed: () {
                          Navigator.pop(context);
                          openSignatures();
                        },
                      ),
                    ),
                ],
              ),
            ),
      scopes: const [('job_and_activities', 'ปิดงานและกิจกรรมทั้งหมด'), ('job_only', 'ปิดเฉพาะงาน (กิจกรรมยังเปิดอยู่)')],
      scopeDefault: open > 0 ? 'job_and_activities' : 'job_only',
      noteLabel: 'สรุปผลการปิดงาน',
      checkLabel: 'ส่งอีเมลรายงานบริการให้ลูกค้า',
      confirm: 'ปิดงาน',
    );
    if (f == null || !context.mounted) return false;
    final r = await api.closeJob(jobId, scope: f.scope, note: f.note, expectedStatus: expected, skipEmail: !f.check);
    if (!context.mounted) return true;
    HapticFeedback.heavyImpact();
    _snack(context, 'ปิดงานแล้ว');
    final caseInfo = r['suggest_close_case'];
    if (caseInfo is Map && caseInfo['case_id'] != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('ปิดเคสต้นทางด้วยไหม?')),
          content: Text(tr('งานนี้มาจากเคส ${caseInfo['case_no'] ?? ''} — เปิดเคสเพื่อปิดต่อได้เลย')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ภายหลัง'))),
            FilledButton(key: const ValueKey('open-source-case'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('เปิดเคส'))),
          ],
        ),
      );
      if (go == true && context.mounted) {
        nxPush<void>(context, EntityByIdLoader(module: 'case', id: caseInfo['case_id'].toString()));
      }
    }
    return true;
  }
}

/// Close sale (win / lose) — same as the web `QuotationOutcomeDialog`.
/// Returns the server result, or null when cancelled.
Future<Map<String, dynamic>?> showQuotationOutcomeSheet(
  BuildContext context, {
  required String quotationId,
  List<({String value, String label})> winReasons = const [],
  List<({String value, String label})> lostReasons = const [],
  String? sourceModule,
  String? sourceId,
}) async {
  final api = context.read<AppConfig>().apiClient;
  const defaultsWin = ['ราคาเหมาะสม', 'คุณภาพสินค้า/บริการ', 'ความสัมพันธ์กับลูกค้า', 'บริการหลังการขาย', 'ส่งมอบได้เร็ว', 'อื่น ๆ'];
  const defaultsLost = ['ราคาสูงกว่าคู่แข่ง', 'ลูกค้าเลื่อน/ยกเลิกโครงการ', 'ไม่ตรงความต้องการ', 'งบประมาณไม่พอ', 'เลือกเจ้าเดิม', 'อื่น ๆ'];
  String? result; // Won | Lost
  String? reason;
  final note = TextEditingController();
  final po = TextEditingController();
  var busy = false;
  return showAppBottomSheet<Map<String, dynamic>>(
    context: context,
    title: tr('ปิดการขาย'),
    child: StatefulBuilder(builder: (ctx, setS) {
      final theme = Theme.of(ctx);
      final reasons = result == 'Won'
          ? (winReasons.isNotEmpty ? winReasons : [for (final r in defaultsWin) (value: r, label: r)])
          : (lostReasons.isNotEmpty ? lostReasons : [for (final r in defaultsLost) (value: r, label: r)]);
      Widget card(String value, IconData icon, String label, String hint, Color color) {
        final sel = result == value;
        return Expanded(
          child: Material(
            color: sel ? color.withValues(alpha: 0.14) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: sel ? color : Colors.transparent, width: 1.6)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('outcome-$value'),
              onTap: () {
                HapticFeedback.selectionClick();
                setS(() {
                  result = value;
                  reason = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
                child: Column(
                  children: [
                    Icon(icon, size: 34, color: color),
                    const SizedBox(height: 6),
                    Text(tr(label), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
                    Text(tr(hint), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            card('Won', NxI.medal, 'ชนะ', 'ลูกค้าตกลงซื้อ', const Color(0xFF059669)),
            const SizedBox(width: 12),
            card('Lost', NxI.xCircle, 'แพ้', 'ไม่ได้งานนี้', const Color(0xFFE11D48)),
          ]),
          if (result != null) ...[
            const SizedBox(height: 14),
            Text('${tr('เหตุผล')} *', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in reasons)
                  ChoiceChip(
                    key: ValueKey('outcome-reason-${r.value}'),
                    label: Text(tr(r.label)),
                    selected: reason == r.value,
                    onSelected: (_) => setS(() => reason = r.value),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (result == 'Won')
              TextField(
                key: const ValueKey('outcome-po'),
                controller: po,
                maxLength: 200,
                decoration: InputDecoration(labelText: tr('เลขที่ใบสั่งซื้อ (PO)'), counterText: ''),
              ),
            if (result == 'Won') const SizedBox(height: 12),
            TextField(
              key: const ValueKey('outcome-note'),
              controller: note,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('หมายเหตุ')),
            ),
            if (result == 'Won')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  tr('ปิดชนะแล้ว ระบบอาจสร้างใบสั่งงานให้อัตโนมัติตามการตั้งค่า'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              key: const ValueKey('outcome-save'),
              style: FilledButton.styleFrom(
                backgroundColor: result == 'Lost' ? const Color(0xFFE11D48) : const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: result == null || reason == null || busy
                  ? null
                  : () async {
                      setS(() => busy = true);
                      try {
                        final r = await api.setQuotationOutcome(
                          quotationId,
                          status: result!,
                          reason: reason!,
                          note: note.text,
                          poReference: po.text,
                          sourceModule: sourceModule,
                          sourceId: sourceId,
                        );
                        HapticFeedback.heavyImpact();
                        if (ctx.mounted) Navigator.pop(ctx, {...r, 'result': result});
                      } catch (e) {
                        setS(() => busy = false);
                        if (ctx.mounted) _snack(ctx, journeyErrorText(e));
                      }
                    },
              child: Text(tr(result == 'Lost' ? 'บันทึกปิดแพ้' : 'บันทึกปิดชนะ'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      );
    }),
  );
}

/// Suggest closing the deal as won (after quotation won / customer accepted):
/// one tap closes it (stage Closed Won, probability 100) like the web.
Future<void> maybeSuggestCloseDeal(BuildContext context, Object? suggest) async {
  if (suggest is! Map || suggest['deal_id'] == null) return;
  final dealId = suggest['deal_id'].toString();
  final go = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('ปิดดีลเป็น "ชนะ" ด้วยไหม?')),
      content: Text('${tr('ดีล')} ${suggest['deal_name'] ?? suggest['deal_no'] ?? ''} ${tr('ยังเปิดอยู่')}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ภายหลัง'))),
        TextButton(key: const ValueKey('open-deal'), onPressed: () => Navigator.pop(ctx, 'open'), child: Text(tr('เปิดดีล'))),
        FilledButton(key: const ValueKey('close-deal-won'), onPressed: () => Navigator.pop(ctx, 'won'), child: Text(tr('ปิดดีลเป็นชนะ'))),
      ],
    ),
  );
  if (!context.mounted || go == null) return;
  if (go == 'open') {
    nxPush<void>(context, EntityByIdLoader(module: 'deal', id: dealId));
    return;
  }
  try {
    await context.read<AppConfig>().apiClient.putEntity('deal', dealId, {'deal_stage': 'Closed Won', 'probability': 100});
    HapticFeedback.mediumImpact();
    if (context.mounted) _snack(context, tr('ปิดดีลเป็นชนะแล้ว'));
  } catch (e) {
    if (context.mounted) _snack(context, journeyErrorText(e));
  }
}

/// Small helpers shared by the quotation flows.
class QuotationFlows {
  QuotationFlows._();

  static Future<bool> cancel(BuildContext context, String id) async {
    final f = await _askForm(context, title: 'ยกเลิกใบเสนอราคา', message: 'ยกเลิกแล้วเปิดกลับได้ภายหลัง', confirm: 'ยกเลิกใบเสนอราคา', danger: true);
    if (f == null || !context.mounted) return false;
    try {
      await context.read<AppConfig>().apiClient.putEntity('quotation', id, {'quotation_status': QS.cancelled});
      if (context.mounted) _snack(context, 'ยกเลิกใบเสนอราคาแล้ว');
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      return false;
    }
  }

  static Future<bool> reopen(BuildContext context, String id) async {
    try {
      await context.read<AppConfig>().apiClient.putEntity('quotation', id, {'quotation_status': QS.open});
      if (context.mounted) _snack(context, 'เปิดใบเสนอราคากลับแล้ว');
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      return false;
    }
  }

  static Future<bool> reject(BuildContext context, String id) async {
    final f = await _askForm(
      context,
      title: 'ไม่อนุมัติใบเสนอราคา',
      noteLabel: 'เหตุผล',
      noteChips: const ['ราคาต่ำเกินไป', 'เงื่อนไขไม่เหมาะสม', 'ข้อมูลไม่ครบ', 'ส่วนลดเกินอำนาจ'],
      confirm: 'ไม่อนุมัติ',
      danger: true,
    );
    if (f == null || !context.mounted) return false;
    try {
      await context.read<AppConfig>().apiClient.rejectQuotation(id, reason: f.note);
      if (context.mounted) _snack(context, 'ไม่อนุมัติแล้ว');
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      return false;
    }
  }

  static Future<bool> approve(BuildContext context, String id) async {
    try {
      final r = await context.read<AppConfig>().apiClient.approveQuotation(id);
      HapticFeedback.mediumImpact();
      if (context.mounted) _snack(context, r['final'] == true ? 'อนุมัติแล้ว — ใบเสนอราคาอนุมัติครบทุกระดับ' : 'อนุมัติแล้ว — รอระดับถัดไป');
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      return false;
    }
  }

  static Future<bool> sendEmail(BuildContext context, String id, {String? to}) async {
    final toCtrl = TextEditingController(text: to ?? '');
    final msg = TextEditingController();
    final ok = await showAppBottomSheet<bool>(
      context: context,
      title: tr('ส่งใบเสนอราคาทางอีเมล'),
      child: StatefulBuilder(builder: (ctx, setS) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('qt-mail-to'),
              controller: toCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: '${tr('ถึง')} *', prefixIcon: const Icon(NxI.envelope)),
              onChanged: (_) => setS(() {}),
            ),
            const SizedBox(height: 12),
            TextField(controller: msg, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('ข้อความ'))),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                key: const ValueKey('qt-mail-send'),
                icon: const Icon(NxI.paperPlaneTilt),
                label: Text(tr('ส่งอีเมล')),
                onPressed: toCtrl.text.trim().contains('@') ? () => Navigator.pop(ctx, true) : null,
              ),
            ),
          ],
        );
      }),
    );
    if (ok != true || !context.mounted) return false;
    try {
      await context.read<AppConfig>().apiClient.sendQuotationEmail(id, to: toCtrl.text.trim(), message: msg.text.trim());
      if (context.mounted) _snack(context, 'ส่งอีเมลถึง ${toCtrl.text.trim()} แล้ว');
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      return false;
    }
  }

  /// Offer status bar change (not "ปิดการขาย" — that is [showQuotationOutcomeSheet]).
  static Future<bool> setOffer(BuildContext context, String id, String offer) async {
    try {
      final r = await context.read<AppConfig>().apiClient.setQuotationOfferStatus(id, offer);
      HapticFeedback.selectionClick();
      if (context.mounted) _snack(context, 'สถานะการเสนอราคา: $offer');
      if (context.mounted) await maybeSuggestCloseDeal(context, r['suggest_close_deal']);
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, journeyErrorText(e));
      return false;
    }
  }
}
