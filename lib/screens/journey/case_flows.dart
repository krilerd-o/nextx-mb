import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/nx_skeleton.dart';
import '../../core/app_config.dart';
import '../../core/history_events.dart' show historyActionTitle;
import '../../core/i18n.dart';
import '../../core/status_labels.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../core/entity_display.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/fields/nx_field_chrome.dart';
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
/// Plus (server-supported, mobile only): in progress → พักเคส (wait);
/// waiting → ทำต่อ (resume).
List<String> caseActions(Object? status) {
  final k = classifyCaseStatus(status);
  if (k == 'closed' || k == 'cancelled') return const [];
  if (k == 'in_progress') return const ['close', 'wait', 'forward', 'cancel'];
  if (k == 'waiting') return const ['accept', 'resume', 'forward', 'cancel'];
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
      'wait' => 'พักเคส',
      'resume' => 'ทำต่อ',
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
      'cancel' => await _cancel(context, caseId, row),
      'wait' => await _wait(context, row),
      'resume' => await _resume(context, row),
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
            'wait' => 'พักเคสแล้ว — รอการตอบรับ',
            'resume' => 'กลับมาดำเนินการต่อแล้ว',
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

  static Widget _save(BuildContext ctx, String label, VoidCallback? onTap, {bool danger = false}) => NxConfirmButtons(
        confirmKey: const ValueKey('case-flow-save'),
        confirmLabel: label,
        color: danger ? kNxDangerRed : Theme.of(ctx).colorScheme.primary,
        onConfirm: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
      );

  /// Status a case action leads to.
  static String _target(String action) => switch (action) {
        'accept' || 'resume' => 'กำลังดำเนินการ',
        'forward' || 'wait' => 'รอการตอบรับ',
        'close' => 'ปิดเคส',
        _ => 'ยกเลิก',
      };

  /// Colour of a case status (open grey, in progress blue, waiting amber, closed green, cancelled red).
  static Color tone(ColorScheme cs, Object? status) => switch (classifyCaseStatus(status)) {
        'open' => cs.onSurfaceVariant,
        'in_progress' || 'accepted' => const Color(0xFF2563EB),
        'waiting' || 'forwarded' => const Color(0xFFF59E0B),
        'closed' => const Color(0xFF16A34A),
        'cancelled' => kNxDangerRed,
        _ => nxStatusTone(cs, '${status ?? ''}'),
      };

  /// Window header shared with every status change: record + current → new (+ impact).
  static Widget _head(BuildContext ctx, Map<String, dynamic> row, String action) {
    final cs = Theme.of(ctx).colorScheme;
    final cur = '${row['case_status'] ?? ''}'.trim();
    final to = _target(action);
    final impact = switch (action) {
      'close' => 'ปิดเคสแล้วหยุดนับเวลา SLA ของเคสนี้',
      'wait' => 'หยุดนับเวลา SLA ระหว่างพักเคส',
      'cancel' => 'หยุดนับเวลา SLA และแจ้งผู้ติดตามเคส',
      _ => null,
    };
    final title = entityTitle(row, module: 'case');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.trim().isNotEmpty) ...[
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(20)),
          child: NxStatusTransition(from: cur.isEmpty ? null : cur, fromColor: tone(cs, cur), to: to, toColor: tone(cs, to)),
        ),
        if (impact != null) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('status-confirm-impact'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: tone(cs, to).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(NxI.info, size: 18, color: tone(cs, to)),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(impact), style: Theme.of(ctx).textTheme.bodyMedium)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  static String _contactEmail(Map<String, dynamic> c) => '${c['email_1st'] ?? c['email'] ?? c['email1'] ?? ''}'.trim();
  static String _contactName(Map<String, dynamic> c) {
    final n = '${c['contact_firstname'] ?? ''} ${c['contact_lastname'] ?? ''}'.trim();
    return n.isNotEmpty ? n : '${c['contact_name'] ?? c['name'] ?? c['id']}';
  }

  /// Contacts of the case's customer that have an email (empty when none / no access).
  static Future<List<Map<String, dynamic>>> _contacts(BuildContext context, Map<String, dynamic> row) async {
    final acc = '${row['related_account_id'] ?? row['account_id'] ?? ''}'.trim();
    if (acc.isEmpty || acc == 'null' || acc == '0') return const [];
    try {
      final list = await context.read<AppConfig>().apiClient.getAccountContacts(acc);
      return [for (final c in list) if (_contactEmail(c).contains('@')) c];
    } catch (_) {
      return const [];
    }
  }

  /// Contact chips: tap fills the email (and remembers the contact for accept).
  static Widget _contactPicker(BuildContext ctx, List<Map<String, dynamic>> contacts, String? selected, void Function(Map<String, dynamic>) onPick) {
    if (contacts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(ctx);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('เลือกผู้ติดต่อของลูกค้า'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in contacts.take(12))
            ChoiceChip(
              key: ValueKey('case-contact-${c['id']}'),
              avatar: const Icon(NxI.user, size: 16),
              label: Text('${_contactName(c)} · ${_contactEmail(c)}', overflow: TextOverflow.ellipsis),
              selected: selected == '${c['id']}',
              onSelected: (_) => onPick(c),
            ),
        ]),
      ]),
    );
  }

  static Future<Map<String, dynamic>?> _accept(BuildContext context, String id, Map<String, dynamic> row) async {
    final summary = await _preview(context, id, 'accept');
    if (!context.mounted) return null;
    final contacts = await _contacts(context, row);
    if (!context.mounted) return null;
    String? contactId = '${row['related_contact_id'] ?? ''}'.trim();
    if (contactId.isEmpty || contactId == 'null') contactId = null;
    final current = contacts.where((c) => '${c['id']}' == contactId).firstOrNull;
    final email = TextEditingController(text: current != null ? _contactEmail(current) : '${row['customer_email'] ?? ''}');
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
            _head(ctx, row, 'accept'),
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
              _contactPicker(ctx, contacts, contactId, (c) => setS(() {
                    contactId = '${c['id']}';
                    email.text = _contactEmail(c);
                  })),
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
                  if (contactId != null) 'related_contact_id': int.tryParse(contactId!) ?? contactId,
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
          Builder(builder: (ctx) => _head(ctx, row, 'forward')),
          Text(tr('เคสจะเป็น "รอการตอบรับ" จนกว่า $name จะกดรับเคส และระบบจะแจ้งผู้รับทันที'), style: Theme.of(context).textTheme.bodyMedium),
          _gap(),
          _hint(context, summary),
          Builder(builder: (ctx) => _save(ctx, 'ส่งต่อเคส', () => Navigator.pop(ctx, {'action': 'forward', 'smownerid': int.tryParse(uid) ?? uid}))),
        ],
      ),
    );
  }

  static final _timeRe = RegExp(r'^\s*(\d+(\.\d+)?\s*[wdhm]\s*)+$', caseSensitive: false);

  /// "1w 2d 3h 30m" → minutes (1d = 24h, 1w = 7d — same as the web).
  static int? parseCaseMinutes(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(t)) return int.parse(t) == 0 ? 0 : null;
    if (!_timeRe.hasMatch(t)) return null;
    var m = 0.0;
    for (final x in RegExp(r'(\d+(?:\.\d+)?)\s*([wdhm])', caseSensitive: false).allMatches(t)) {
      final v = double.parse(x.group(1)!);
      m += switch (x.group(2)!.toLowerCase()) { 'w' => v * 7 * 24 * 60, 'd' => v * 24 * 60, 'h' => v * 60, _ => v };
    }
    return m.round();
  }

  /// Case estimate in minutes: `estimate_workday` (minutes) first, else
  /// `original_estimate_minutes` — same order as the web.
  static int caseEstimateMinutes(Map<String, dynamic> row) {
    final a = num.tryParse('${row['estimate_workday'] ?? ''}') ?? 0;
    if (a > 0) return a.round();
    final b = num.tryParse('${row['original_estimate_minutes'] ?? ''}') ?? 0;
    return b > 0 ? b.round() : 0;
  }

  static String _plain(Object? html) => '${html ?? ''}'
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  static Future<Map<String, dynamic>?> _close(BuildContext context, String id, Map<String, dynamic> row) async {
    final api = context.read<AppConfig>().apiClient;
    final summary = await _preview(context, id, 'close');
    if (!context.mounted) return null;
    final contacts = await _contacts(context, row);
    if (!context.mounted) return null;
    // Approved Manday of this case → what can go back to the contract.
    var approved = <Map<String, dynamic>>[];
    var contracts = <Map<String, dynamic>>[];
    try {
      final sum = await api.getCaseMandaySummary(id);
      contracts = extractMapList(sum['case_contracts']);
      approved = [for (final r in await api.getCaseMandayRequests(id)) if ('${r['status']}' == 'Approved') r];
    } catch (_) {}
    if (!context.mounted) return null;
    String? contactId;
    final est = caseEstimateMinutes(row);
    final hasEstimate = est > 0;
    final time = TextEditingController(text: hasEstimate ? _fmtMinutes(est) : '');
    final desc = TextEditingController(text: _plain(row['case_description_closed']));
    final email = TextEditingController(text: '${row['customer_email'] ?? ''}');
    final cc = TextEditingController(text: '${row['email_cc'] ?? ''}');
    var skip = true;
    var returnManday = false;
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: tr('ปิดเคส'),
      child: StatefulBuilder(builder: (ctx, setS) {
        final mins = parseCaseMinutes(time.text);
        final badTime = time.text.trim().isNotEmpty && mins == null;
        final used = (mins ?? 0) / 60;
        final rows = [
          for (final r in approved)
            () {
              final req = num.tryParse('${r['requested_hours'] ?? ''}') ?? 0;
              final c = contracts.where((x) => '${x['id']}' == '${r['contract_id']}').firstOrNull;
              final release = (req - used) < 0 ? 0 : req - used;
              return (label: '${c?['contract_no'] ?? 'SC #${r['contract_id']}'}${c?['contract_name'] == null ? '' : ' · ${c!['contract_name']}'}', req: req, release: release);
            }(),
        ];
        final canReturn = rows.any((r) => r.release > 0);
        String h(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _head(ctx, row, 'close'),
            _hint(ctx, summary),
            if (hasEstimate || time.text.isNotEmpty) ...[
              TextField(
                key: const ValueKey('case-time-spent'),
                controller: time,
                decoration: InputDecoration(labelText: tr('เวลาที่ใช้'), helperText: tr('เช่น 30m, 2h 30m, 1d (1 วัน = 24 ชม.)'), errorText: badTime ? tr('ระบุเวลา เช่น 0h, 30m หรือ 1h') : null),
                onChanged: (_) => setS(() {}),
              ),
              _gap(),
            ] else if (est > 0)
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setS(() => time.text = _fmtMinutes(est)), child: Text(tr('เติมจากเวลาประมาณของเคส')))),
            TextField(
              key: const ValueKey('case-close-desc'),
              controller: desc,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: tr('รายละเอียดปิดเคส'), alignLabelWithHint: true),
            ),
            _gap(),
            if (rows.isNotEmpty) ...[
              Text(tr('Manday ที่อนุมัติแล้ว'), style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${r.label}: ${tr('ขอ')} ${h(r.req)} ${tr('ชม.')} · ${tr('ใช้')} ${h(used)} ${tr('ชม.')} · '
                    '${r.release <= 0 ? tr('ใช้ครบ') : returnManday ? '${tr('คืน')} ${h(r.release)} ${tr('ชม.')}' : '${h(r.release)} ${tr('ชม. จะไม่ถูกคืน')}'}',
                    key: const ValueKey('case-close-manday-row'),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              if (canReturn)
                SwitchListTile(
                  key: const ValueKey('case-close-return'),
                  contentPadding: EdgeInsets.zero,
                  value: returnManday,
                  title: Text(tr('คืนชั่วโมง Manday ที่เหลือเข้าสัญญา')),
                  onChanged: (v) => setS(() => returnManday = v),
                ),
              _gap(),
            ],
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: !skip,
              title: Text(tr('ส่งอีเมลแจ้งปิดเคสถึงลูกค้า')),
              onChanged: (v) => setS(() => skip = !(v ?? false)),
            ),
            if (!skip) ...[
              _contactPicker(ctx, contacts, contactId, (c) => setS(() {
                    contactId = '${c['id']}';
                    email.text = _contactEmail(c);
                  })),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('อีเมลแจ้ง'))),
              _gap(),
              TextField(controller: cc, decoration: InputDecoration(labelText: tr('CC'))),
              _gap(),
            ],
            const SizedBox(height: 6),
            _save(
              danger: true,
              ctx,
              'บันทึกและปิดเคส',
              badTime
                  ? null
                  : () => Navigator.pop(ctx, {
                        'action': 'close',
                        'skip_email': skip,
                        'return_unused_manday': canReturn && returnManday,
                        if (desc.text.trim().isNotEmpty) 'case_description_closed': '<p>${_esc(desc.text.trim()).replaceAll('\n', '<br>')}</p>',
                        'time_spent_minutes': ?mins,
                        if (!skip && email.text.trim().isNotEmpty) 'email': email.text.trim(),
                        if (!skip && cc.text.trim().isNotEmpty) 'cc': cc.text.trim(),
                      }),
            ),
          ],
        );
      }),
    );
  }

  /// Minutes → "1d 2h 30m" (1d = 24h, 1w = 7d) like the web.
  static String _fmtMinutes(int m) {
    if (m <= 0) return '0m';
    final parts = <String>[];
    var r = m;
    for (final (u, v) in const [('w', 7 * 24 * 60), ('d', 24 * 60), ('h', 60), ('m', 1)]) {
      if (r >= v) {
        parts.add('${r ~/ v}$u');
        r %= v;
      }
    }
    return parts.join(' ');
  }

  static Future<Map<String, dynamic>?> _wait(BuildContext context, Map<String, dynamic> row) {
    final note = TextEditingController();
    const reasons = ['รอลูกค้าตอบกลับ', 'รออะไหล่ / อุปกรณ์', 'รอข้อมูลเพิ่มเติม', 'รอนัดหมาย'];
    return showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      title: tr('พักเคส'),
      child: StatefulBuilder(builder: (ctx, setS) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _head(ctx, row, 'wait'),
            Text(tr('เคสจะเป็น "รอการตอบรับ" ชั่วคราว กด "ทำต่อ" เมื่อพร้อมดำเนินการ — ผู้ติดตามเคสจะได้รับแจ้ง'), style: Theme.of(ctx).textTheme.bodyMedium),
            _gap(),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in reasons)
                ActionChip(key: ValueKey('case-wait-$r'), label: Text(tr(r)), onPressed: () => setS(() => note.text = tr(r))),
            ]),
            _gap(),
            TextField(key: const ValueKey('case-wait-note'), controller: note, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('เหตุผล (ไม่บังคับ)'))),
            const SizedBox(height: 18),
            _save(ctx, 'พักเคส', () => Navigator.pop(ctx, {'action': 'wait', if (note.text.trim().isNotEmpty) 'note': note.text.trim()})),
          ],
        );
      }),
    );
  }

  static Future<Map<String, dynamic>?> _resume(BuildContext context, Map<String, dynamic> row) => showAppBottomSheet<Map<String, dynamic>>(
        context: context,
        title: tr('ทำต่อ'),
        child: Builder(
          builder: (ctx) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _head(ctx, row, 'resume'),
              Text(tr('เคสจะกลับมาเป็น "กำลังดำเนินการ"'), style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 18),
              _save(ctx, 'ทำต่อ', () => Navigator.pop(ctx, {'action': 'resume'})),
            ],
          ),
        ),
      );

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  static Future<Map<String, dynamic>?> _cancel(BuildContext context, String id, Map<String, dynamic> row) async {
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
            _head(ctx, row, 'cancel'),
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
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (i, r) in kNxCancelReasons.indexed)
                ChoiceChip(
                  key: ValueKey('status-reason-$i'),
                  label: Text(tr(r)),
                  selected: note.text.trim() == tr(r),
                  onSelected: (_) => setS(() => note.text = tr(r)),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('case-cancel-reason'),
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: NxFieldStyle.input(context, label: 'เหตุผลที่ยกเลิก', required: true, multiline: true),
              onChanged: (_) => setS(() {}),
            ),
            const SizedBox(height: 18),
            _save(
              ctx,
              'ยกเลิกเคส',
              note.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, {
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
              'wait' => NxI.pause,
              'resume' => NxI.play,
              _ => NxI.x,
            }, color: a == 'cancel' ? const Color(0xFFE11D48) : null),
            title: Text(caseActionLabel(a)),
            onTap: () => Navigator.pop(context, a),
          ),
      ],
    ),
  );
}


/// Status history of a case (who changed what, when), newest first.
Future<void> showCaseStatusHistory(BuildContext context, String caseId) {
  return showAppBottomSheet<void>(
    context: context,
    title: tr('ประวัติสถานะเคส'),
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: context.read<AppConfig>().apiClient.getCaseStatusEvents(caseId),
      builder: (context, snap) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        if (snap.connectionState != ConnectionState.done) {
          return const NxSkeletonTimeline(key: ValueKey('case-status-events-skeleton'), rows: 4, padded: true);
        }
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text(caseErrorText(snap.error!)));
        final list = snap.data ?? const [];
        if (list.isEmpty) return Padding(padding: const EdgeInsets.all(24), child: Text(tr('ยังไม่มีประวัติสถานะ')));
        return Column(
          key: const ValueKey('case-history'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < list.length; i++)
              _HistoryRow(event: list[i], last: i == list.length - 1, color: cs.primary),
          ],
        );
      },
    ),
  );
}

String _historyLabel(String action) => tr(switch (action) {
      'create' => 'เปิดเคส',
      'accept' => 'รับเคส',
      'forward' => 'ส่งต่อเคส',
      'wait' => 'พักเคส',
      'resume' => 'ทำต่อ',
      'cancel' => 'ยกเลิกเคส',
      'close' => 'ปิดเคส',
      // Never the raw key (see history_events.dart).
      _ => historyActionTitle('case.$action').title,
    });

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event, required this.last, required this.color});
  final Map<String, dynamic> event;
  final bool last;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final e = event;
    final details = e['details'] is Map ? e['details'] as Map : const {};
    final note = '${details['note'] ?? details['to_owner_name'] ?? ''}'.trim();
    final when = formatThaiField(e['at'], 'at', year: uiYear);
    final from = statusValueLabel(e['from_status'], module: 'case');
    final to = statusValueLabel(e['to_status'], module: 'case');
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            const SizedBox(height: 4),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: cs.outlineVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_historyLabel('${e['action'] ?? ''}'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (from.isNotEmpty || to.isNotEmpty) Text('${from.isEmpty ? '—' : from} → $to', style: theme.textTheme.bodySmall),
              if (note.isNotEmpty) Text(note, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              Text('${e['user_name'] ?? ''}${when.isEmpty ? '' : ' · $when'}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ]),
    );
  }
}
