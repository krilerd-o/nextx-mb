import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/journey_rules.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_status_stepper.dart';
import '../crm/entity_detail_parts.dart' show commentAttachments;
import 'job_journey.dart' show showPublicLinkSheet;
import 'journey_controller.dart';
import 'journey_photos.dart';
import 'journey_widgets.dart';
import 'quotation_versions.dart';
import 'status_followups.dart';

String _fmtDate(Object? v) {
  final d = parseThai(v);
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year + 543}';
}

String _fmtDateTime(Object? v) {
  final d = parseThai(v);
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year + 543} ${two(d.hour)}:${two(d.minute)}';
}

num _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0;

String _money(Object? v, [Object? currency]) {
  final n = _num(v);
  final s = n.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  final c = (currency ?? '').toString();
  return c.isEmpty || c == 'THB' ? '฿$s' : '$s $c';
}

/// Journey steps of a quotation: เปิด → ขออนุมัติ → อนุมัติ → ปิดการขาย.
List<NxStep> quotationSteps(QuotationStage st) => [
      for (final s in kQuotationStages)
        NxStep(
          id: s,
          label: jt('journey.quotation.stage.$s', fallback: switch (s) {
            'open' => 'เปิดใบเสนอราคา',
            'approval' => 'ขออนุมัติ',
            'approved' => 'อนุมัติ',
            _ => 'ปิดการขาย',
          }),
          isDone: s == 'closed',
          color: s == 'closed' && st.result == 'Lost' ? const Color(0xFFE11D48) : null,
        ),
    ];

String? quotationSideLabel(QuotationStage st) => switch (st.side) {
      'lost' => tr('ปิดแพ้'),
      'rejected' => tr('ไม่อนุมัติ'),
      'revised' => tr('เปลี่ยนแปลง (มีฉบับใหม่)'),
      'cancelled' => tr('ยกเลิก'),
      _ => null,
    };

/// Offer status bar: เสนอราคา → รอเปรียบเทียบ → รอใบสั่งซื้อ → ปิดการขาย.
class OfferStatusBar extends StatelessWidget {
  const OfferStatusBar({super.key, required this.row, required this.onPick, this.locked = false});
  final Map<String, dynamic> row;
  final ValueChanged<String>? onPick;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final cur = canonicalOfferStatus(row['offer_status']);
    final idx = Offer.all.indexOf(cur);
    final won = isQuotationWon(row);
    return NxStatusStepper(
      key: const ValueKey('offer-bar'),
      steps: [
        for (final o in Offer.all)
          NxStep(
            id: o,
            label: o,
            isDone: o == Offer.closed,
            color: o == Offer.closed && idx == 3 ? (won ? const Color(0xFF059669) : const Color(0xFFE11D48)) : null,
          ),
      ],
      current: idx,
      stepKeyPrefix: 'offer-',
      doneKeyPrefix: 'offer-done-',
      padding: EdgeInsets.zero,
      onPick: locked || onPick == null ? null : (i) => onPick!(Offer.all[i]),
    );
  }
}

/// Summary tab of a quotation.
class QuotationSummaryTab extends StatelessWidget {
  const QuotationSummaryTab({
    super.key,
    required this.row,
    required this.ctrl,
    required this.canEdit,
    required this.meId,
    required this.comments,
    required this.onAction,
    required this.onGoTab,
    required this.onReload,
    required this.onOpen,
    this.busy = false,
    this.jobEnabled = true,
  });

  final Map<String, dynamic> row;
  final JourneyController ctrl;
  final bool canEdit;
  final int? meId;
  final List<Map<String, dynamic>> comments;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onGoTab;
  final VoidCallback onReload;
  final void Function(String module, String id) onOpen;
  final bool busy;
  final bool jobEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final jobs = ctrl.linked('jobs');
    final next = quotationNextAction(
      row,
      meId: meId,
      hasJob: jobs.isNotEmpty,
      jobEnabled: jobEnabled,
      lineCount: ctrl.linesLoaded ? ctrl.lines.length : null,
      canEdit: canEdit,
      approvalRequired: ctrl.approvalRequired,
      customer: ctrl.customer,
      staleDays: ctrl.staleDays,
    );
    final left = daysUntil(row['valid_until']);
    final hist = ctrl.approvalHistory;
    final apprState = (row['approval_state'] ?? 'none').toString();
    final cust = ctrl.customer;
    final custLabel = cust['signed_at'] != null
        ? tr('เซ็นแล้ว')
        : cust['accepted_at'] != null
            ? tr('ตอบรับแล้ว')
            : cust['viewed_at'] != null
                ? tr('เปิดดูแล้ว')
                : (cust['link_sent'] == true || (row['public_token'] ?? '').toString().isNotEmpty)
                    ? tr('ส่งลิงก์แล้ว')
                    : tr('ยังไม่ส่ง');
    final result = quotationResult(row);
    final activities = ctrl.linked('activities');
    final photos = [for (final c in comments) ...commentAttachments(c).where((a) => (a['mime'] ?? '').toString().startsWith('image/'))];
    final finished = isQuotationFinished(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NextActionCard(module: 'quotation', next: next, onAction: onAction, busy: busy),
        const SizedBox(height: 12),
        KpiGrid(tiles: [
          KpiTile(
            id: 'total',
            icon: NxI.receipt,
            label: tr('ยอดรวม'),
            value: _money(row['grand_total'] ?? row['total'], row['currency']),
            hint: _num(row['discount_total']) > 0 ? '${tr('ส่วนลด')} ${_money(row['discount_total'], row['currency'])}' : null,
            tone: 'primary',
            onTap: () => onGoTab('lines'),
          ),
          KpiTile(
            id: 'valid',
            icon: NxI.calendarClock,
            label: tr('ใช้ได้ถึง'),
            value: row['valid_until'] == null ? '-' : _fmtDate(row['valid_until']),
            hint: left == null ? null : (left < 0 ? tr('หมดอายุแล้ว ${-left} วัน') : tr('เหลือ $left วัน')),
            tone: left == null ? 'neutral' : (left < 0 ? 'danger' : (left <= 7 ? 'warning' : 'neutral')),
          ),
          KpiTile(
            id: 'approval',
            icon: NxI.shieldCheck,
            label: tr('อนุมัติ'),
            value: apprState == 'pending'
                ? tr('ระดับ ${hist['current'] ?? row['approval_level'] ?? 1}/${hist['total'] ?? '-'}')
                : switch (apprState) {
                    'approved' => tr('อนุมัติแล้ว'),
                    'rejected' => tr('ไม่อนุมัติ'),
                    _ => tr(ctrl.approvalRequired ? 'ยังไม่ส่ง' : 'ไม่บังคับ'),
                  },
            tone: switch (apprState) { 'pending' => 'warning', 'approved' => 'success', 'rejected' => 'danger', _ => 'neutral' },
            onTap: () => onGoTab('approval'),
          ),
          KpiTile(
            id: 'customer',
            icon: NxI.userCheck,
            label: tr('ลูกค้า'),
            value: custLabel,
            hint: _num(cust['view_count']) > 0 ? tr('เปิดดู ${cust['view_count']} ครั้ง') : null,
            tone: cust['signed_at'] != null || cust['accepted_at'] != null ? 'success' : 'neutral',
          ),
        ]),
        const SizedBox(height: 12),
        JourneySection(
          title: tr('สถานะการเสนอราคา'),
          icon: NxI.arrowRight,
          child: OfferStatusBar(
            row: row,
            locked: !canEdit || finished,
            onPick: (o) => onAction(o == Offer.closed ? 'close_sale' : 'offer:$o'),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 12),
          JourneySection(
            title: result == 'Won' ? tr('ผล: ชนะ') : tr('ผล: แพ้'),
            icon: result == 'Won' ? NxI.medal : NxI.xCircle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((row['outcome_reason'] ?? '').toString().isNotEmpty) Text('${tr('เหตุผล')}: ${row['outcome_reason']}'),
                if ((row['po_reference'] ?? '').toString().isNotEmpty) Text('PO: ${row['po_reference']}'),
                if ((row['outcome_note'] ?? '').toString().isNotEmpty) Text(row['outcome_note'].toString(), style: theme.textTheme.bodySmall),
                for (final j in jobs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(NxI.wrench),
                    title: Text((j['title'] ?? '').toString()),
                    subtitle: Text((j['status'] ?? '').toString()),
                    trailing: const Icon(NxI.caretRight, size: 16),
                    onTap: () => onOpen('job', '${j['id']}'),
                  ),
              ],
            ),
          ),
        ],
        if (cust['viewed_at'] != null || cust['accepted_at'] != null || cust['signed_at'] != null) ...[
          const SizedBox(height: 12),
          JourneySection(
            title: tr('การตอบรับของลูกค้า'),
            icon: NxI.userCheck,
            child: Column(children: [
              if (cust['viewed_at'] != null) ChecklistRow(label: tr('เปิดดู'), ok: true, value: _fmtDateTime(cust['viewed_at'])),
              if (cust['accepted_at'] != null) ChecklistRow(label: tr('ตอบรับ'), ok: true, value: _fmtDateTime(cust['accepted_at'])),
              if (cust['signed_at'] != null) ChecklistRow(label: '${tr('เซ็นโดย')} ${cust['signer_name'] ?? ''}', ok: true, value: _fmtDateTime(cust['signed_at'])),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        JourneySection(
          title: tr('ติดตามผล'),
          icon: NxI.calendarCheck,
          trailing: canEdit && !finished
              ? TextButton.icon(onPressed: () => onAction('follow_up'), icon: const Icon(NxI.calendarPlus, size: 16), label: Text(tr('นัดติดตาม')))
              : null,
          child: activities.isEmpty
              ? Text(tr('ยังไม่มีกิจกรรมติดตาม'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
              : Column(children: [
                  for (final a in activities.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(NxI.calendarCheck),
                      title: Text((a['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([a['subtitle'], a['status']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                      trailing: const Icon(NxI.caretRight, size: 16),
                      onTap: () => onOpen('activity', '${a['id']}'),
                    ),
                ]),
        ),
        if (ctrl.revisions.length > 1) ...[
          const SizedBox(height: 12),
          JourneySection(
            title: tr('เวอร์ชัน'),
            icon: NxI.arrowsLeftRight,
            trailing: TextButton.icon(
              key: const ValueKey('rev-compare'),
              onPressed: () => openQuotationCompare(context, currentId: '${row['id']}', revisions: ctrl.revisions),
              icon: const Icon(NxI.arrowsLeftRight, size: 16),
              label: Text(tr('เทียบฉบับ')),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in ctrl.revisions)
                  ChoiceChip(
                    key: ValueKey('rev-${r['id']}'),
                    label: Text('${r['quotation_no'] ?? ''}${r['is_current'] == true ? ' ✓' : ''}'),
                    selected: '${r['id']}' == '${row['id']}',
                    onSelected: '${r['id']}' == '${row['id']}' ? null : (_) => onOpen('quotation', '${r['id']}'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        JourneyPhotosSection(
          module: 'quotation',
          id: '${row['id']}',
          photos: photos,
          onChanged: onReload,
          canEdit: canEdit,
          title: 'รูป / ไฟล์ประกอบ',
        ),
      ],
    );
  }
}

/// Approval tab: level timeline + approve / reject inline + submit.
class QuotationApprovalTab extends StatelessWidget {
  const QuotationApprovalTab({super.key, required this.row, required this.ctrl, required this.meId, required this.canEdit, required this.onAction});
  final Map<String, dynamic> row;
  final JourneyController ctrl;
  final int? meId;
  final bool canEdit;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final h = ctrl.approvalHistory;
    final steps = [for (final s in (h['steps'] as List? ?? const [])) if (s is Map) Map<String, dynamic>.from(s)];
    final state = (row['approval_state'] ?? h['state'] ?? 'none').toString();
    final iApprove = meId != null && quotationCurrentApprovers(row).contains(meId);
    final canSubmit = canEdit && state != 'pending' && state != 'approved' && !isQuotationFinished(row);
    Color stColor(String s) => switch (s) {
          'approved' => const Color(0xFF059669),
          'rejected' => const Color(0xFFE11D48),
          'current' || 'pending' => const Color(0xFFD97706),
          _ => cs.onSurfaceVariant,
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (iApprove)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('qt-approve'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), minimumSize: const Size.fromHeight(48)),
                  onPressed: () => onAction('approve'),
                  icon: const Icon(NxI.shieldCheck),
                  label: Text(tr('อนุมัติ')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('qt-reject'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE11D48), minimumSize: const Size.fromHeight(48)),
                  onPressed: () => onAction('reject'),
                  icon: const Icon(NxI.x),
                  label: Text(tr('ไม่อนุมัติ')),
                ),
              ),
            ]),
          ),
        if (steps.isEmpty)
          JourneySection(
            title: tr('การอนุมัติ'),
            icon: NxI.shieldCheck,
            child: Text(tr(state == 'none' ? 'ยังไม่ได้ส่งขออนุมัติ' : 'สถานะ: $state'), style: theme.textTheme.bodyMedium),
          ),
        for (final s in steps) ...[
          JourneySection(
            title: (s['label'] ?? '${tr('ระดับ')} ${s['level']}').toString(),
            icon: NxI.shieldCheck,
            trailing: Chip(
              visualDensity: VisualDensity.compact,
              label: Text(tr(s['mode'] == 'all' ? 'ครบทุกคน' : 'คนใดคนหนึ่ง')),
            ),
            child: Column(
              children: [
                for (final u in (s['users'] as List? ?? const []))
                  if (u is Map)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        u['decision'] == 'approved' ? NxI.checkCircle : (u['decision'] == 'rejected' ? NxI.xCircle : NxI.clock),
                        color: stColor((u['decision'] ?? s['status'] ?? '').toString()),
                      ),
                      title: Text((u['user_name'] ?? u['user_id']).toString()),
                      subtitle: Text([
                        if (u['at'] != null) _fmtDateTime(u['at']),
                        if (u['via'] == 'email') tr('ผ่านอีเมล'),
                        if ((u['note'] ?? '').toString().isNotEmpty) u['note'].toString(),
                      ].join(' · ')),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (state == 'pending' && canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onAction('resend_approval'),
              icon: const Icon(NxI.envelope, size: 16),
              label: Text(tr('ส่งอีเมลขออนุมัติซ้ำ')),
            ),
          ),
        if (canSubmit) ...[
          const SizedBox(height: 6),
          FilledButton.icon(
            key: const ValueKey('qt-submit-approval'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => onAction('submit_approval'),
            icon: const Icon(NxI.paperPlaneTilt),
            label: Text(tr(state == 'rejected' ? 'ส่งขออนุมัติอีกครั้ง' : 'ส่งขออนุมัติ')),
          ),
        ],
      ],
    );
  }
}

/// Approver picker per level (settings `approval.levels`, candidates limit the list).
Future<List<Map<String, dynamic>>?> showSubmitApprovalSheet(BuildContext context, {required JourneyController ctrl, Map<String, dynamic>? row}) async {
  final api = context.read<AppConfig>().apiClient;
  List<Map<String, dynamic>> users = const [];
  try {
    users = await api.getUsersCached();
  } catch (_) {}
  if (!context.mounted) return null;
  var levels = ctrl.approvalLevels;
  if (levels.isEmpty) {
    levels = [
      {'level': 1, 'label': tr('ผู้อนุมัติ'), 'mode': 'any'},
    ];
  }
  final picked = <int, Set<String>>{for (final l in levels) (l['level'] as num?)?.toInt() ?? 1: <String>{}};
  // Pre-fill from the previous chain.
  for (final st in quotationApprovalSteps(row)) {
    picked[st.level]?.addAll(st.users.map((u) => '$u'));
  }
  String uid(Map<String, dynamic> u) => (u['user_id'] ?? u['id']).toString();
  String uname(Map<String, dynamic> u) => (u['display_name'] ?? u['name'] ?? u['email'] ?? uid(u)).toString();
  return showAppBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    title: tr('ส่งขออนุมัติ'),
    child: StatefulBuilder(builder: (ctx, setS) {
      final theme = Theme.of(ctx);
      final lastLevel = (levels.last['level'] as num?)?.toInt() ?? 1;
      final ok = picked[lastLevel]?.isNotEmpty == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in levels) ...[
            Builder(builder: (_) {
              final lv = (l['level'] as num?)?.toInt() ?? 1;
              final cand = {for (final c in (l['candidates'] as List? ?? const [])) '$c'};
              final pool = [for (final u in users) if (cand.isEmpty || cand.contains(uid(u))) u];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l['label'] ?? '${tr('ระดับ')} $lv'} · ${tr(lv == lastLevel ? 'ต้องเลือก' : 'ข้ามได้')}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final u in pool.take(40))
                        FilterChip(
                          key: ValueKey('approver-$lv-${uid(u)}'),
                          label: Text(uname(u)),
                          selected: picked[lv]!.contains(uid(u)),
                          onSelected: (v) => setS(() => v ? picked[lv]!.add(uid(u)) : picked[lv]!.remove(uid(u))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }),
          ],
          SizedBox(
            height: 50,
            child: FilledButton(
              key: const ValueKey('approval-submit'),
              onPressed: ok
                  ? () => Navigator.pop(ctx, [
                        for (final e in picked.entries)
                          if (e.value.isNotEmpty) {'level': e.key, 'user_ids': [for (final s in e.value) int.tryParse(s) ?? s]},
                      ])
                  : null,
              child: Text(tr('ส่งขออนุมัติ')),
            ),
          ),
        ],
      );
    }),
  );
}

/// Copy as a new quotation (web: `/quotation/new?from=` → POST /quotation/save):
/// fresh status, no approval / outcome / customer link.
Future<String?> duplicateQuotation(ApiClient api, Map<String, dynamic> row) async {
  const drop = {
    'id', 'quotation_no', 'quotation_status', 'offer_status', 'approval_state', 'approval_level', 'approval_chain',
    'outcome_result', 'outcome_reason', 'outcome_note', 'outcome_at', 'po_reference', 'public_token', 'revision_no',
    'revision_of_id', 'createdtime', 'modifiedtime', 'created_by', 'modified_by', 'deleted', 'business_id',
    'customer_viewed_at', 'customer_accepted_at', 'customer_signed_at', 'signer_name', 'signature_path',
    'approver_1_user_id', 'approver_2_user_id', '_shared_permission',
  };
  final fields = <String, dynamic>{
    for (final e in row.entries)
      if (!drop.contains(e.key) && !e.key.startsWith('_') && e.value is! Map && e.value is! List) e.key: e.value,
  };
  final lines = [
    for (final l in await api.getQuotationLines('${row['id']}'))
      {
        for (final e in l.entries)
          if (e.key != 'id' && e.key != 'quotation_id' && e.key != 'createdtime' && e.key != 'modifiedtime') e.key: e.value,
      },
  ];
  final r = await api.saveQuotation(fields: fields, lines: lines);
  final id = r['id'] ?? (r['quotation'] is Map ? r['quotation']['id'] : null);
  return id?.toString();
}

/// Run a quotation next-step / bar action. Returns true when the record changed.
Future<bool> runQuotationAction(
  BuildContext context, {
  required String action,
  required Map<String, dynamic> row,
  required JourneyController ctrl,
  required ValueChanged<String> goTab,
  required void Function(String module, String id) open,
  required VoidCallback edit,
  required VoidCallback followUp,
  List<({String value, String label})> winReasons = const [],
  List<({String value, String label})> lostReasons = const [],
}) async {
  final id = '${row['id']}';
  final api = context.read<AppConfig>().apiClient;
  final messenger = ScaffoldMessenger.of(context);
  void snack(String t) => messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(t))));
  try {
    if (action.startsWith('offer:')) return await QuotationFlows.setOffer(context, id, action.substring(6));
    switch (action) {
      case 'close_sale':
        final r = await showQuotationOutcomeSheet(context, quotationId: id, winReasons: winReasons, lostReasons: lostReasons);
        if (r == null) return false;
        if (r['result'] == 'Won') {
          snack(r['job_created'] == true ? 'ปิดการขาย: ชนะ — สร้างใบสั่งงานให้แล้ว' : 'ปิดการขาย: ชนะ');
        } else {
          snack('ปิดการขาย: แพ้');
        }
        if (context.mounted) await maybeSuggestCloseDeal(context, r['suggest_close_deal']);
        return true;
      case 'offer_comparing':
        return await QuotationFlows.setOffer(context, id, Offer.comparing);
      case 'offer_waiting_po':
        return await QuotationFlows.setOffer(context, id, Offer.waitingPo);
      case 'approve':
        return await QuotationFlows.approve(context, id);
      case 'reject':
        return await QuotationFlows.reject(context, id);
      case 'view_approval':
        goTab('approval');
        return false;
      case 'submit_approval':
        final levels = await showSubmitApprovalSheet(context, ctrl: ctrl, row: row);
        if (levels == null) return false;
        await api.submitQuotationApprovalLevels(id, levels);
        HapticFeedback.mediumImpact();
        snack('ส่งขออนุมัติแล้ว');
        return true;
      case 'resend_approval':
        await api.resendQuotationApprovalEmail(id);
        snack('ส่งอีเมลขออนุมัติซ้ำแล้ว');
        return false;
      case 'send_email':
        return await QuotationFlows.sendEmail(context, id, to: (row['contact_email'] ?? row['email'] ?? '').toString());
      case 'public_link':
        final r = await api.quotationPublicLink(id);
        if (context.mounted) {
          await showPublicLinkSheet(context, api.absoluteUrl((r['path'] ?? '').toString()), pdf: r['pdf_path'] == null ? null : api.absoluteUrl(r['pdf_path'].toString()));
        }
        return true;
      case 'create_job':
        final r = await api.quotationCreateJob(id);
        snack(r['created'] == true ? 'สร้างใบสั่งงานแล้ว' : 'มีใบสั่งงานอยู่แล้ว');
        if (r['job_id'] != null) open('job', '${r['job_id']}');
        return true;
      case 'open_job':
        final jobs = ctrl.linked('jobs');
        if (jobs.isNotEmpty) open('job', '${jobs.first['id']}');
        return false;
      case 'revise':
        // Edit first (new servers take the edited header + lines), then create -R n.
        final r = await openQuotationRevise(context, row);
        if (r == null) return false;
        snack('สร้างฉบับแก้ไข ${r['quotation_no'] ?? ''} แล้ว');
        if (r['id'] != null) open('quotation', '${r['id']}');
        return true;
      case 'open_latest':
        final cur = ctrl.revisions.where((r) => r['is_current'] == true).toList();
        if (cur.isNotEmpty) open('quotation', '${cur.first['id']}');
        return false;
      case 'compare_versions':
        if (context.mounted) await openQuotationCompare(context, currentId: id, revisions: ctrl.revisions);
        return false;
      case 'duplicate':
        final newId = await duplicateQuotation(api, row);
        snack('ทำสำเนาเป็นใบใหม่แล้ว');
        if (newId != null) open('quotation', newId);
        return false;
      case 'cancel':
        return await QuotationFlows.cancel(context, id);
      case 'reopen_quotation':
        return await QuotationFlows.reopen(context, id);
      case 'edit':
        goTab('lines');
        return false;
      case 'edit_quotation':
        edit();
        return false;
      case 'follow_up':
        followUp();
        return false;
    }
  } catch (e) {
    snack(journeyErrorText(e));
  }
  return false;
}
