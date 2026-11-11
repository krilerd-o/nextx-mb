import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_status_stepper.dart';
import 'status_followups.dart' show pickJourneyUser;

/// Case status values (NEXTX `caseWorkflowService.CASE_STATUS`).
class CaseStatus {
  CaseStatus._();
  static const open = 'เปิดเคส';
  static const waiting = 'รอการตอบรับ';
  static const inProgress = 'กำลังดำเนินการ';
  static const closed = 'ปิดเคส';
  static const cancelled = 'ยกเลิก';
  static const main = [open, waiting, inProgress, closed];
}

/// open | waiting | forwarded | accepted | in_progress | closed | cancelled | other
/// (same order of checks as the web: "เปิดเคส" contains "ปิดเคส").
String classifyCaseStatus(Object? v) {
  final s = '${v ?? ''}'.trim();
  final l = s.toLowerCase();
  if (RegExp(r'ยกเลิก|cancel', caseSensitive: false).hasMatch(s)) return 'cancelled';
  if (RegExp(r'เปิดเคส|เปิดงาน').hasMatch(s) || l == 'open') return 'open';
  if (RegExp(r'กำลังดำเนินการ|in.?progress', caseSensitive: false).hasMatch(s)) return 'in_progress';
  if (RegExp(r'รอการตอบรับ|waiting|pending', caseSensitive: false).hasMatch(s)) return 'waiting';
  if (s.contains('ส่งต่อ')) return 'forwarded';
  if (RegExp(r'รับเคส|รับงาน').hasMatch(s) || l == 'accepted') return 'accepted';
  if (RegExp(r'ปิดเคส|ปิดงาน').hasMatch(s) || l == 'closed') return 'closed';
  return s.isEmpty ? 'open' : 'other';
}

/// Actions shown like the web: in progress → close / forward / cancel;
/// open, waiting… → accept / forward / cancel; closed / cancelled → none.
List<String> caseActions(Object? status) {
  final k = classifyCaseStatus(status);
  if (k == 'closed' || k == 'cancelled') return const [];
  if (k == 'in_progress') return const ['close', 'forward', 'cancel'];
  return const ['accept', 'forward', 'cancel'];
}

int caseStepIndex(Object? status) => switch (classifyCaseStatus(status)) {
      'closed' => 3,
      'in_progress' => 2,
      'waiting' || 'forwarded' => 1,
      'cancelled' => -1,
      _ => 0,
    };

/// Stepper click → action (waiting = forward, in progress = accept, closed = close).
String? caseStepAction(int step) => switch (step) {
      1 => 'forward',
      2 => 'accept',
      3 => 'close',
      _ => null,
    };

List<NxStep> caseSteps() => [
      NxStep(id: CaseStatus.open, label: L10n.isEn ? 'Open' : CaseStatus.open),
      NxStep(id: CaseStatus.waiting, label: L10n.isEn ? 'Waiting' : CaseStatus.waiting),
      NxStep(id: CaseStatus.inProgress, label: L10n.isEn ? 'In progress' : CaseStatus.inProgress),
      NxStep(id: CaseStatus.closed, label: L10n.isEn ? 'Closed' : CaseStatus.closed, isDone: true),
    ];

String caseActionLabel(String a) => tr(switch (a) {
      'accept' => 'รับเคส',
      'forward' => 'ส่งต่อเคส',
      'close' => 'ปิดเคส',
      'cancel' => 'ยกเลิกเคส',
      _ => a,
    });

bool _isAdmin(AppConfig c) {
  final r = (c.session.businessRole ?? '').toLowerCase();
  return r == 'owner' || r == 'admin' || c.session.isSuperadmin == true;
}

/// Clear, friendly "you can't do this" dialog (instead of a silent no-op).
Future<void> showCaseNotAllowed(BuildContext context, String message, {String? hint}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('case-not-allowed'),
      icon: const Icon(NxI.lock, size: 32, color: Color(0xFFD97706)),
      title: Text(tr('ทำรายการนี้ไม่ได้')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr(message), textAlign: TextAlign.center),
          if (hint != null) ...[
            const SizedBox(height: 10),
            Text(tr(hint), textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('เข้าใจแล้ว')))],
    ),
  );
}

/// Turns server errors into plain words.
String caseErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    if (e.statusCode == 403 || e.errorCode == 'PERMISSION_DENIED') {
      final m = e.message.trim();
      return m.isEmpty || m == 'Forbidden' ? 'คุณไม่มีสิทธิ์เปลี่ยนสถานะเคสนี้' : m;
    }
    if (e.statusCode == 404) return 'ไม่พบเคสนี้ หรือคุณไม่มีสิทธิ์เข้าถึง';
    return e.message;
  }
  if (e is ApiException && e.statusCode == 403) return 'คุณไม่มีสิทธิ์เปลี่ยนสถานะเคสนี้';
  return formatApiError(e);
}

class CaseFlows {
  CaseFlows._();

  /// Checks permission first (clear dialog when not allowed), then opens the
  /// action's window like the web. Returns true when the case changed.
  static Future<bool> run(BuildContext context, {required String caseId, required String action, required Map<String, dynamic> row}) async {
    final config = context.read<AppConfig>();
    if ('${row['_shared_permission'] ?? ''}' == 'read_only') {
      await showCaseNotAllowed(
        context,
        'คุณดูเคสนี้ได้อย่างเดียว จึงเปลี่ยนสถานะไม่ได้',
        hint: 'ให้เจ้าของเคส หัวหน้า หรือผู้ดูแลระบบเป็นผู้ดำเนินการ หรือขอสิทธิ์แก้ไขเคสนี้',
      );
      return false;
    }
    final allowed = caseActions(row['case_status']);
    if (!allowed.contains(action)) {
      final k = classifyCaseStatus(row['case_status']);
      await showCaseNotAllowed(
        context,
        k == 'closed' || k == 'cancelled'
            ? (k == 'closed' ? 'เคสนี้ปิดแล้ว จึงเปลี่ยนสถานะไม่ได้' : 'เคสนี้ยกเลิกแล้ว จึงเปลี่ยนสถานะไม่ได้')
            : action == 'close'
                ? 'ต้องกด "รับเคส" ให้เป็นกำลังดำเนินการก่อน จึงจะปิดเคสได้'
                : 'ขั้นนี้ทำต่อจากสถานะปัจจุบันไม่ได้',
      );
      return false;
    }
    final k = classifyCaseStatus(row['case_status']);
    final mine = '${row['smownerid'] ?? ''}' == (config.session.userId ?? '');
    if (action == 'accept' && (k == 'waiting' || k == 'forwarded') && !mine && !_isAdmin(config)) {
      await showCaseNotAllowed(
        context,
        'เคสนี้ส่งต่อให้คนอื่นแล้ว — รับเคสได้เฉพาะผู้รับผิดชอบปัจจุบันหรือผู้ดูแลระบบ',
        hint: 'ถ้าต้องการรับเคสนี้ ให้ผู้รับผิดชอบส่งต่อมาให้คุณก่อน',
      );
      return false;
    }
    final Map<String, dynamic>? body = switch (action) {
      'accept' => await _accept(context, caseId, row),
      'forward' => await _forward(context, caseId, row),
      'close' => await _close(context, caseId, row),
      'cancel' => await _cancel(context, caseId),
      _ => null,
    };
    if (body == null || !context.mounted) return false;
    try {
      await config.apiClient.caseWorkflowAction(caseId, body);
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(tr(switch (action) {
            'accept' => 'รับเคสแล้ว — กำลังดำเนินการ',
            'forward' => 'ส่งต่อเคสแล้ว — รอการตอบรับ',
            'close' => 'ปิดเคสแล้ว',
            _ => 'ยกเลิกเคสแล้ว',
          })),
        ));
      }
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      final forbidden = (e is ApiEnvelopeException && (e.statusCode == 403 || e.errorCode == 'PERMISSION_DENIED')) || (e is ApiException && e.statusCode == 403);
      if (forbidden) {
        await showCaseNotAllowed(context, caseErrorText(e), hint: 'ติดต่อเจ้าของเคสหรือผู้ดูแลระบบหากต้องการสิทธิ์');
      } else {
        await showCaseNotAllowed(context, caseErrorText(e));
      }
      return false;
    }
  }

  static Future<String?> _preview(BuildContext context, String id, String action, {String? owner}) async {
    try {
      final p = await context.read<AppConfig>().apiClient.previewCaseWorkflow(id, action, ownerId: owner);
      return (L10n.isEn ? p['summaryEn'] : p['summaryTh'])?.toString();
    } catch (_) {
      return null;
    }
  }

  static Widget _hint(BuildContext context, String? text) {
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(NxI.info, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }

  static Widget _gap() => const SizedBox(height: 14);

  static Widget _save(BuildContext ctx, String label, VoidCallback? onTap, {bool danger = false}) => SizedBox(
        height: 50,
        child: FilledButton(
          key: const ValueKey('case-flow-save'),
          style: FilledButton.styleFrom(
            backgroundColor: danger ? const Color(0xFFE11D48) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: onTap,
          child: Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  static Future<Map<String, dynamic>?> _accept(BuildContext context, String id, Map<String, dynamic> row) async {
    final summary = await _preview(context, id, 'accept');
    if (!context.mounted) return null;
    final email = TextEditingController(text: '${row['customer_email'] ?? ''}');
    final cc = TextEditingController(text: '${row['email_cc'] ?? ''}');
    final info = TextEditingController();
    var skip = true;
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: tr('รับเคส'),
      child: StatefulBuilder(builder: (ctx, setS) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('เคสจะเปลี่ยนเป็น "กำลังดำเนินการ" และบันทึกเวลารับเคส'), style: Theme.of(ctx).textTheme.bodyMedium),
            _gap(),
            _hint(ctx, summary),
            CheckboxListTile(
              key: const ValueKey('case-skip-email'),
              contentPadding: EdgeInsets.zero,
              value: !skip,
              title: Text(tr('ส่งอีเมลแจ้งลูกค้า')),
              onChanged: (v) => setS(() => skip = !(v ?? false)),
            ),
            if (!skip) ...[
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('อีเมลแจ้ง'))),
              _gap(),
              TextField(controller: cc, decoration: InputDecoration(labelText: tr('CC'))),
              _gap(),
            ],
            TextField(controller: info, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('ข้อมูลการช่วยเหลือ (Support Info)'))),
            const SizedBox(height: 18),
            _save(ctx, 'บันทึกรับเคส', () => Navigator.pop(ctx, {
                  'action': 'accept',
                  'skip_email': skip,
                  if (!skip && email.text.trim().isNotEmpty) 'email': email.text.trim(),
                  if (!skip && cc.text.trim().isNotEmpty) 'cc': cc.text.trim(),
                  if (info.text.trim().isNotEmpty) 'support_info': info.text.trim(),
                })),
          ],
        );
      }),
    );
  }

  static Future<Map<String, dynamic>?> _forward(BuildContext context, String id, Map<String, dynamic> row) async {
    final u = await pickJourneyUser(context, title: 'ส่งต่อเคสให้');
    if (u == null || !context.mounted) return null;
    final uid = '${u['user_id'] ?? u['id']}';
    final name = '${u['display_name'] ?? u['name'] ?? uid}';
    final summary = await _preview(context, id, 'forward', owner: uid);
    if (!context.mounted) return null;
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: tr('ส่งต่อเคสให้ $name'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('เคสจะเป็น "รอการตอบรับ" จนกว่า $name จะกดรับเคส และระบบจะแจ้งผู้รับทันที'), style: Theme.of(context).textTheme.bodyMedium),
          _gap(),
          _hint(context, summary),
          Builder(builder: (ctx) => _save(ctx, 'ส่งต่อเคส', () => Navigator.pop(ctx, {'action': 'forward', 'smownerid': int.tryParse(uid) ?? uid}))),
        ],
      ),
    );
  }

  static final _timeRe = RegExp(r'^\s*(\d+(\.\d+)?\s*[hm]\s*)+$', caseSensitive: false);

  static Future<Map<String, dynamic>?> _close(BuildContext context, String id, Map<String, dynamic> row) async {
    final summary = await _preview(context, id, 'close');
    if (!context.mounted) return null;
    final est = num.tryParse('${row['original_estimate_minutes'] ?? ''}') ?? 0;
    final estDays = num.tryParse('${row['estimate_workday'] ?? ''}') ?? 0;
    final hasEstimate = est > 0 || estDays > 0;
    final time = TextEditingController(text: est > 0 ? _fmtMinutes(est.round()) : '');
    final desc = TextEditingController();
    final email = TextEditingController(text: '${row['customer_email'] ?? ''}');
    final cc = TextEditingController(text: '${row['email_cc'] ?? ''}');
    var skip = true;
    var returnManday = false;
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: tr('ปิดเคส'),
      child: StatefulBuilder(builder: (ctx, setS) {
        final badTime = hasEstimate && time.text.trim().isNotEmpty && !_timeRe.hasMatch(time.text);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _hint(ctx, summary),
            if (hasEstimate) ...[
              TextField(
                key: const ValueKey('case-time-spent'),
                controller: time,
                decoration: InputDecoration(labelText: tr('เวลาที่ใช้'), helperText: tr('เช่น 30m, 1h, 2h 30m'), errorText: badTime ? tr('ระบุเวลา เช่น 0h, 30m หรือ 1h') : null),
                onChanged: (_) => setS(() {}),
              ),
              _gap(),
            ],
            TextField(
              key: const ValueKey('case-close-desc'),
              controller: desc,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: tr('รายละเอียดปิดเคส'), alignLabelWithHint: true),
            ),
            _gap(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: returnManday,
              title: Text(tr('คืนชั่วโมง Manday ที่เหลือเข้าสัญญา')),
              onChanged: (v) => setS(() => returnManday = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: !skip,
              title: Text(tr('ส่งอีเมลแจ้งปิดเคสถึงลูกค้า')),
              onChanged: (v) => setS(() => skip = !(v ?? false)),
            ),
            if (!skip) ...[
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('อีเมลแจ้ง'))),
              _gap(),
              TextField(controller: cc, decoration: InputDecoration(labelText: tr('CC'))),
              _gap(),
            ],
            const SizedBox(height: 6),
            _save(
              ctx,
              'บันทึกและปิดเคส',
              badTime
                  ? null
                  : () => Navigator.pop(ctx, {
                        'action': 'close',
                        'skip_email': skip,
                        'return_unused_manday': returnManday,
                        if (desc.text.trim().isNotEmpty) 'case_description_closed': '<p>${_esc(desc.text.trim()).replaceAll('\n', '<br>')}</p>',
                        if (hasEstimate && time.text.trim().isNotEmpty) 'time_spent': time.text.trim(),
                        if (!skip && email.text.trim().isNotEmpty) 'email': email.text.trim(),
                        if (!skip && cc.text.trim().isNotEmpty) 'cc': cc.text.trim(),
                      }),
            ),
          ],
        );
      }),
    );
  }

  static String _fmtMinutes(int m) {
    final h = m ~/ 60, r = m % 60;
    if (h == 0) return '${r}m';
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static Future<Map<String, dynamic>?> _cancel(BuildContext context, String id) async {
    List<Map<String, dynamic>> jobs = const [];
    try {
      jobs = await context.read<AppConfig>().apiClient.getCaseOpenJobs(id);
    } catch (_) {}
    if (!context.mounted) return null;
    var cancelJobs = true;
    final note = TextEditingController();
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: tr('ยืนยันยกเลิกเคส'),
      child: StatefulBuilder(builder: (ctx, setS) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('งานและกิจกรรมที่อยู่ภายใต้เคสนี้จะถูกปรับสถานะเป็นยกเลิก และเคสจะเปลี่ยนเป็นยกเลิก'), style: Theme.of(ctx).textTheme.bodyMedium),
            _gap(),
            if (jobs.isNotEmpty)
              CheckboxListTile(
                key: const ValueKey('case-cancel-jobs'),
                contentPadding: EdgeInsets.zero,
                value: cancelJobs,
                title: Text(tr('ยกเลิกใบสั่งงานที่ยังเปิดของเคสนี้ด้วย (${jobs.length} ใบ)')),
                subtitle: Text(jobs.map((j) => '${j['job_no'] ?? j['id']}').join(', ')),
                onChanged: (v) => setS(() => cancelJobs = v ?? false),
              ),
            TextField(controller: note, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('เหตุผล (ไม่บังคับ)'))),
            const SizedBox(height: 18),
            _save(
              ctx,
              'ยกเลิกเคส',
              () => Navigator.pop(ctx, {
                'action': 'cancel',
                if (jobs.isNotEmpty && cancelJobs) 'cancel_jobs': true,
                if (note.text.trim().isNotEmpty) 'reason': note.text.trim(),
              }),
              danger: true,
            ),
          ],
        );
      }),
    );
  }
}

/// Sheet listing the case actions allowed now (long-press in the list).
Future<String?> pickCaseAction(BuildContext context, Map<String, dynamic> row) {
  final actions = caseActions(row['case_status']);
  return showAppBottomSheet<String>(
    context: context,
    title: '${tr('ปรับสถานะเคส')} · ${row['case_status'] ?? ''}',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('เคสนี้ปิดหรือยกเลิกแล้ว — ไม่มีคำสั่งเพิ่ม'))),
        for (final a in actions)
          ListTile(
            key: ValueKey('case-action-$a'),
            leading: Icon(switch (a) {
              'accept' => NxI.check,
              'forward' => NxI.arrowRight,
              'close' => NxI.flag,
              _ => NxI.x,
            }, color: a == 'cancel' ? const Color(0xFFE11D48) : null),
            title: Text(caseActionLabel(a)),
            onTap: () => Navigator.pop(context, a),
          ),
      ],
    ),
  );
}
