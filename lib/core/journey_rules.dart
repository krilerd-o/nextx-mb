/// Service Journey rules for Quotation and Job detail pages.
///
/// Port of NEXTX `frontend/src/components/crm/recordJourney/journeyStages.js`
/// (pure functions — keep in sync with the web). Texts come from
/// [kJourneyText] (generated from the web i18n) via [jt].
library;

import 'dart:convert';

import 'i18n.dart';
import 'journey_text.dart';

String _norm(Object? v) => (v ?? '').toString().trim();
String _lower(Object? v) => _norm(v).toLowerCase();

/// Text for a web `journey.*` / `sj.*` key in the current language.
/// `{name}` placeholders are filled from [params]. Missing key → [fallback] or the key.
String jt(String key, {Map<String, Object?> params = const {}, String? fallback}) {
  final pair = kJourneyText[key];
  var s = pair == null ? (fallback ?? key) : (L10n.isEn ? pair[1] : pair[0]);
  params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

bool jtHas(String key) => kJourneyText.containsKey(key);

/// Next step suggestion: `key` → `journey.<module>.next.<key>.title|hint`,
/// `action` / `secondary` → `journey.<module>.action.<action>`.
class NextAction {
  const NextAction(this.key, this.tone, this.action, [this.secondary = const []]);
  final String key;

  /// primary | warning | success | neutral | danger
  final String tone;
  final String? action;
  final List<String> secondary;

  @override
  String toString() => 'NextAction($key, $tone, $action, $secondary)';
}

// ------------------------------------------------------------------ Quotation

class QS {
  QS._();
  static const open = 'เปิดใบเสนอราคา';
  static const pending = 'ขออนุมัติใบเสนอราคา';
  static const approved = 'อนุมัติใบเสนอราคา';
  static const rejected = 'ไม่อนุมัติใบเสนอราคา';
  static const cancelled = 'ยกเลิกใบเสนอราคา';
  static const revised = 'เปลี่ยนแปลงใบเสนอราคา';
  static const closed = 'ปิดการขาย';
  static const all = [open, pending, approved, rejected, cancelled, revised, closed];
}

class Offer {
  Offer._();
  static const quoted = 'เสนอราคา';
  static const comparing = 'รอเปรียบเทียบ';
  static const waitingPo = 'รอใบสั่งซื้อ';
  static const closed = 'ปิดการขาย';
  static const all = [quoted, comparing, waitingPo, closed];
}

const kQuotationStages = ['open', 'approval', 'approved', 'closed'];

const _legacyStatus = {
  'draft': QS.open, 'open': QS.open, 'sent': QS.open, 'pending': QS.pending, 'approved': QS.approved,
  'rejected': QS.rejected, 'cancelled': QS.cancelled, 'canceled': QS.cancelled, 'expired': QS.cancelled,
  'revised': QS.revised, 'closed': QS.closed, 'won': QS.closed, 'win': QS.closed, 'lost': QS.closed, 'lose': QS.closed,
};
const _legacyOffer = {
  'proposed': Offer.quoted, 'quoted': Offer.quoted, 'negotiating': Offer.comparing, 'comparing': Offer.comparing,
  'accepted': Offer.waitingPo, 'signed': Offer.waitingPo, 'won': Offer.closed, 'lost': Offer.closed, 'closed': Offer.closed,
};

String canonicalQuotationStatus(Object? v) {
  final raw = _norm(v);
  if (raw.isEmpty || QS.all.contains(raw)) return raw;
  return _legacyStatus[raw.toLowerCase()] ?? raw;
}

String canonicalOfferStatus(Object? v) {
  final raw = _norm(v);
  if (raw.isEmpty || Offer.all.contains(raw)) return raw;
  return _legacyOffer[raw.toLowerCase()] ?? raw;
}

/// 'Won' | 'Lost' | null
String? quotationResult(Map<String, dynamic>? r) {
  final o = _lower(r?['outcome_result']);
  if (o == 'won' || o == 'win') return 'Won';
  if (o == 'lost' || o == 'lose') return 'Lost';
  final st = _lower(r?['quotation_status']);
  if (st == 'won' || st == 'win') return 'Won';
  if (st == 'lost' || st == 'lose') return 'Lost';
  return null;
}

bool isQuotationClosed(Map<String, dynamic>? r) => canonicalQuotationStatus(r?['quotation_status']) == QS.closed;
bool isQuotationWon(Map<String, dynamic>? r) => quotationResult(r) == 'Won';

/// Status / offer value that means "close sale" — needs the win/lose dialog.
bool isOutcomeStatus(Object? v) => canonicalOfferStatus(v) == Offer.closed || canonicalQuotationStatus(v) == QS.closed;

bool quotationSentToCustomer(Map<String, dynamic>? r, [Map<String, dynamic>? customer]) {
  final offer = canonicalOfferStatus(r?['offer_status']);
  bool has(Object? v) => v != null && v != false && _norm(v).isNotEmpty;
  return has(r?['public_token']) ||
      has(customer?['link_sent']) ||
      has(customer?['viewed_at']) ||
      has(customer?['accepted_at']) ||
      has(r?['customer_viewed_at']) ||
      has(r?['customer_accepted_at']) ||
      offer == Offer.comparing ||
      offer == Offer.waitingPo;
}

class QuotationStage {
  const QuotationStage(this.stage, {this.side, this.result, this.skippedApproval = false});
  final String stage;
  final String? side;
  final String? result;
  final bool skippedApproval;
}

QuotationStage quotationStage(Map<String, dynamic>? r, {bool approvalRequired = false, Map<String, dynamic>? customer}) {
  final st = canonicalQuotationStatus(r?['quotation_status']);
  final appr = _lower(r?['approval_state'] ?? 'none');
  final noApproval = appr == 'none' || appr.isEmpty;
  if (st == QS.closed) {
    final res = quotationResult(r);
    return QuotationStage('closed', side: res == 'Lost' ? 'lost' : null, result: res, skippedApproval: noApproval);
  }
  final base = appr == 'approved' ? 'approved' : appr == 'pending' ? 'approval' : 'open';
  if (st == QS.cancelled) return QuotationStage(base, side: 'cancelled');
  if (st == QS.revised) return QuotationStage(base, side: 'revised');
  if (st == QS.rejected || appr == 'rejected') return const QuotationStage('approval', side: 'rejected');
  if (st == QS.pending || appr == 'pending') return const QuotationStage('approval');
  if (st == QS.approved || appr == 'approved') return const QuotationStage('approved');
  return QuotationStage('open', skippedApproval: !approvalRequired && noApproval && quotationSentToCustomer(r, customer));
}

bool isQuotationEditable(Map<String, dynamic>? r) {
  final st = canonicalQuotationStatus(r?['quotation_status']);
  return st.isEmpty || st == QS.open || st == QS.rejected;
}

/// Closed / cancelled / revised: approval tab and offer bar are locked too.
bool isQuotationFinished(Map<String, dynamic>? r) {
  final st = canonicalQuotationStatus(r?['quotation_status']);
  return st == QS.closed || st == QS.cancelled || st == QS.revised;
}

class ApprovalStep {
  const ApprovalStep(this.level, this.label, this.mode, this.users, this.decisions);
  final int level;
  final String? label;
  final String mode;
  final List<int> users;
  final List<Map<String, dynamic>> decisions;
}

int? _toId(Object? v) {
  final n = int.tryParse('${v ?? ''}');
  return n != null && n > 0 ? n : null;
}

List<ApprovalStep> quotationApprovalSteps(Map<String, dynamic>? r) {
  Object? raw = r?['approval_chain'];
  if (raw is String) {
    try {
      raw = _jsonDecode(raw);
    } catch (_) {
      raw = null;
    }
  }
  if (raw is List && raw.isNotEmpty && raw.every((x) => x is Map)) {
    var i = 0;
    return [
      for (final st in raw.cast<Map>())
        ApprovalStep(
          _toId(st['level']) ?? (++i),
          st['label']?.toString(),
          st['mode'] == 'all' ? 'all' : 'any',
          [for (final u in (st['users'] as List? ?? const [])) ?_toId(u)],
          [
            for (final d in (st['decisions'] as List? ?? const []))
              if (d is Map && _toId(d['user_id']) != null) Map<String, dynamic>.from(d),
          ],
        ),
    ];
  }
  final flat = [if (raw is List) for (final u in raw) ?_toId(u)];
  final ids = flat.isNotEmpty ? flat : [?_toId(r?['approver_1_user_id']), ?_toId(r?['approver_2_user_id'])];
  return [for (var i = 0; i < ids.length; i++) ApprovalStep(i + 1, null, 'any', [ids[i]], const [])];
}

List<int> quotationCurrentApprovers(Map<String, dynamic>? r) {
  if (_lower(r?['approval_state']) != 'pending') return const [];
  final steps = quotationApprovalSteps(r);
  final idx = (int.tryParse('${r?['approval_level'] ?? ''}') ?? 1) - 1;
  if (idx < 0 || idx >= steps.length) return const [];
  final step = steps[idx];
  final decided = {for (final d in step.decisions) _toId(d['user_id'])};
  if (step.mode == 'any' && step.decisions.any((d) => d['decision'] == 'approved')) return const [];
  return step.users.where((u) => !decided.contains(u)).toList();
}

/// Days until [date] (negative = past); null when no / invalid date.
int? daysUntil(Object? date, {DateTime? now}) {
  if (date == null || _norm(date).isEmpty) return null;
  final d = DateTime.tryParse(_norm(date));
  if (d == null) return null;
  final n = now ?? DateTime.now();
  final local = d.isUtc ? d.toLocal() : d;
  final a = DateTime.utc(local.year, local.month, local.day);
  final b = DateTime.utc(n.year, n.month, n.day);
  return a.difference(b).inDays;
}

NextAction quotationNextAction(
  Map<String, dynamic>? r, {
  int? meId,
  bool hasJob = false,
  bool jobEnabled = true,
  int? lineCount,
  bool canEdit = true,
  bool approvalRequired = false,
  Map<String, dynamic>? customer,
  int staleDays = 7,
  DateTime? now,
}) {
  final s = quotationStage(r, approvalRequired: approvalRequired, customer: customer);
  final offer = canonicalOfferStatus(r?['offer_status']);
  if (s.side == 'revised') return const NextAction('revised', 'neutral', 'open_latest', ['compare_versions']);
  if (s.side == 'cancelled') return NextAction('cancelled', 'danger', 'duplicate', canEdit ? const ['reopen_quotation'] : const []);
  if (s.side == 'lost') return const NextAction('lost', 'neutral', 'duplicate', ['follow_up']);
  if (s.side == 'rejected') {
    return NextAction('rejected', 'danger', canEdit ? 'edit_quotation' : null, canEdit ? const ['submit_approval', 'cancel'] : const []);
  }
  if (s.stage == 'closed') {
    if (s.result == 'Won') {
      if (hasJob) return const NextAction('won_job', 'success', null, ['open_job', 'duplicate']);
      return NextAction('won', 'success', null, [if (jobEnabled && canEdit) 'create_job', 'duplicate']);
    }
    return NextAction('closed_no_result', 'warning', canEdit ? 'close_sale' : null, const ['duplicate']);
  }
  if (s.stage == 'approval') {
    if (meId != null && quotationCurrentApprovers(r).contains(meId)) {
      return const NextAction('approve_now', 'warning', 'approve', ['reject']);
    }
    return const NextAction('waiting_approval', 'warning', 'view_approval');
  }
  if (!canEdit) return const NextAction('read_only', 'neutral', null);
  final left = daysUntil(r?['valid_until'], now: now);
  if (left != null && left < 0 && offer != Offer.waitingPo) {
    return NextAction('expired', 'danger', isQuotationEditable(r) ? 'edit_quotation' : 'revise', const ['follow_up']);
  }
  if (s.stage == 'approved' || s.skippedApproval) {
    final revise = s.stage == 'approved' ? const ['revise'] : const <String>[];
    if (offer == Offer.waitingPo) return const NextAction('waiting_po', 'primary', 'close_sale', ['follow_up']);
    final ago = daysUntil(customer?['offer_status_at'], now: now);
    final since = ago == null ? null : -ago;
    if (staleDays > 0 && since != null && since >= staleDays && quotationSentToCustomer(r, customer)) {
      return const NextAction('stale_follow_up', 'warning', 'follow_up', ['send_email', 'close_sale']);
    }
    if (offer == Offer.comparing) {
      return NextAction('comparing', 'primary', 'offer_waiting_po', ['follow_up', 'close_sale', ...revise]);
    }
    if (s.skippedApproval) return const NextAction('sent_no_approval', 'primary', 'offer_comparing', ['follow_up', 'close_sale']);
    return NextAction('send_customer', 'primary', 'send_email', ['public_link', 'offer_comparing', ...revise]);
  }
  if (lineCount == 0) return const NextAction('add_lines', 'primary', 'edit');
  if (approvalRequired) return const NextAction('submit_approval', 'primary', 'submit_approval');
  return const NextAction('submit_or_send', 'primary', 'submit_approval', ['send_email', 'close_sale']);
}

// ------------------------------------------------------------------------ Job

const kJobMain = ['Open', 'Waiting', 'In Progress', 'Completed'];
const kJobSide = ['Cancelled'];
const kJobStatusLabels = {
  'Open': ['เปิดงาน', 'Open'],
  'Waiting': ['รอการตอบรับ', 'Waiting'],
  'In Progress': ['กำลังดำเนินการ', 'In progress'],
  'Completed': ['ปิดงาน', 'Closed'],
  'Cancelled': ['ยกเลิก', 'Cancelled'],
};

const _jobAliases = {
  'planned': 'Open', 'scheduled': 'Open', 'draft': 'Open', 'open': 'Open', 'เปิดงาน': 'Open',
  'waiting': 'Waiting', 'on hold': 'Waiting', 'onhold': 'Waiting', 'รอการตอบรับ': 'Waiting',
  'in progress': 'In Progress', 'inprogress': 'In Progress', 'accepted': 'In Progress', 'กำลังดำเนินการ': 'In Progress',
  'closed': 'Completed', 'done': 'Completed', 'completed': 'Completed', 'ปิดงาน': 'Completed',
  'cancelled': 'Cancelled', 'canceled': 'Cancelled', 'ยกเลิก': 'Cancelled',
};

String canonicalJobStatus(Object? v) {
  final s = _norm(v);
  return _jobAliases[s.toLowerCase()] ?? s;
}

String jobStatusLabel(Object? v) {
  final c = canonicalJobStatus(v);
  final l = kJobStatusLabels[c];
  if (l == null) return _norm(v);
  return L10n.isEn ? l[1] : l[0];
}

List<String> jobWorkflowActions(Object? status) {
  switch (canonicalJobStatus(status)) {
    case 'Open':
      return const ['accept', 'forward', 'cancel'];
    case 'Waiting':
      return const ['accept', 'resume', 'forward', 'cancel'];
    case 'In Progress':
      return const ['close', 'forward', 'wait', 'cancel'];
    case 'Completed':
      return const ['reopen'];
  }
  return const [];
}

/// Tapping a step on the status strip → the workflow action that reaches it.
String? jobStepAction(Object? from, Object? to) {
  final f = canonicalJobStatus(from);
  final t = canonicalJobStatus(to);
  if (t == 'In Progress') return f == 'Completed' ? 'reopen' : 'accept';
  if (t == 'Waiting') return f == 'In Progress' ? 'wait' : 'forward';
  if (t == 'Completed') return 'close';
  if (t == 'Cancelled') return 'cancel';
  if (t == 'Open' && f == 'Completed') return 'reopen';
  return null;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// The two signatures the job report prints (BIRT job_template2 page 2):
/// "Serviced by / ผู้ให้บริการ" and "Customer accepted by / ลูกค้าเซ็นรับทราบ".
/// Stored on the job row: `{role}_signature` (upload path), `{role}_signed_by_name`,
/// `{role}_signed_at` with role `technician` | `customer`.
const kJobReportSigners = ['technician', 'customer'];

bool jobReportSigned(Map<String, dynamic>? r, String role) => _norm(r?['${role}_signature']).isNotEmpty && _norm(r?['${role}_signature']) != 'null';

/// Report signers still missing (`technician`, `customer`).
List<String> jobReportMissing(Map<String, dynamic>? r) => [for (final k in kJobReportSigners) if (!jobReportSigned(r, k)) k];

/// Job priority as on the web (`picklistLabel(job_priority)` — the seeded
/// values Urgent / High / Normal / Low); unknown values pass through.
const kJobPriorityLabels = {
  'urgent': ['เร่งด่วน', 'Urgent'],
  'high': ['สูง', 'High'],
  'normal': ['ปกติ', 'Normal'],
  'medium': ['ปกติ', 'Normal'],
  'low': ['ต่ำ', 'Low'],
};

String jobPriorityLabel(Object? v, {List<Map<String, dynamic>> options = const []}) {
  final s = _norm(v);
  if (s.isEmpty || s == 'null') return '';
  for (final o in options) {
    if (_norm(o['value']) == s) {
      final l = L10n.isEn ? (o['value_en'] ?? o['label_en']) : (o['value_th'] ?? o['label_th']);
      if (_norm(l).isNotEmpty) return _norm(l);
    }
  }
  final l = kJobPriorityLabels[s.toLowerCase()];
  if (l == null) return s;
  return L10n.isEn ? l[1] : l[0];
}

/// Job type / category labels of the seeded picklists (web `picklistLabel`,
/// `value_th` — the seed keeps job types as "Service Job" / "Request Job").
const kJobTypeLabels = {
  'service': ['Service Job', 'Service Job'],
  'request': ['Request Job', 'Request Job'],
  'installation': ['ติดตั้ง', 'Installation'],
  'pm': ['ตรวจเช็คสภาพ (PM)', 'PM'],
  'check': ['ตรวจสอบ', 'Check'],
  'repair': ['ซ่อมแซม', 'Repair'],
  'calibration': ['การปรับเทียบ', 'Calibration'],
  'other': ['อื่นๆ', 'Others'],
};

String jobPickLabel(Object? v, {List<Map<String, dynamic>> options = const []}) {
  final s = _norm(v);
  if (s.isEmpty || s == 'null') return '';
  for (final o in options) {
    if (_norm(o['value']) == s) {
      final l = L10n.isEn ? (o['value_en'] ?? o['label_en']) : (o['value_th'] ?? o['label_th']);
      if (_norm(l).isNotEmpty) return _norm(l);
    }
  }
  final l = kJobTypeLabels[s.toLowerCase()];
  if (l == null) return s;
  return L10n.isEn ? l[1] : l[0];
}

/// [requireReportSignatures]: the app's rule "ทุกใบงานจะต้องมีลายเซ็น" — both
/// report signatures (ผู้ให้บริการ + ลูกค้า) before the job can be closed.
NextAction jobNextAction(Map<String, dynamic>? r, Map<String, dynamic>? overview, {bool canEdit = true, bool requireReportSignatures = false}) {
  final status = canonicalJobStatus(r?['job_status']);
  final ov = overview ?? const {};
  final sig = _map(ov['signatures']);
  final acts = _map(ov['activities']);
  if (status == 'Cancelled') return const NextAction('cancelled', 'neutral', null);
  if (status == 'Completed') return NextAction('completed', 'success', ov['can_reopen'] == true ? 'reopen' : null);
  if (!canEdit) return const NextAction('read_only', 'neutral', null);
  final canAccept = ov['can_accept'] ?? true;
  if (status == 'Waiting') {
    return canAccept == true
        ? const NextAction('waiting_accept', 'warning', 'accept', ['forward'])
        : const NextAction('waiting_other', 'neutral', null, ['forward']);
  }
  if (status == 'Open') {
    final hasOwner = ov['has_owner'] ?? (_int(r?['smownerid']) > 0);
    if (hasOwner != true) return const NextAction('assign', 'primary', 'forward', ['accept']);
    return canAccept == true
        ? const NextAction('accept', 'primary', 'accept', ['forward', 'schedule'])
        : const NextAction('open_other', 'neutral', null, ['forward']);
  }
  if (_int(acts['total']) == 0) return const NextAction('gen_activity', 'primary', 'gen_activity', ['wait']);
  if (_int(acts['open']) > 0) return const NextAction('work_activities', 'primary', 'open_activities', ['wait']);
  if (_int(sig['total']) > _int(sig['signed'])) return const NextAction('collect_signatures', 'warning', 'open_signatures');
  if (requireReportSignatures && jobReportMissing(r).isNotEmpty) return const NextAction('report_signatures', 'warning', 'open_signatures');
  if (ov['can_close'] == true) return const NextAction('ready_to_close', 'success', 'close');
  return const NextAction('owner_closes', 'neutral', null);
}

class ChecklistItem {
  const ChecklistItem(this.key, this.ok, {this.value, this.info = false});
  final String key;
  final bool ok;
  final String? value;
  final bool info;
}

List<ChecklistItem> jobCloseChecklist(Map<String, dynamic>? r, Map<String, dynamic>? overview, {bool requireReportSignatures = false}) {
  final ov = overview ?? const {};
  final sig = _map(ov['signatures']);
  final acts = _map(ov['activities']);
  final total = _int(acts['total']), open = _int(acts['open']);
  final st = _int(sig['total']), ss = _int(sig['signed']);
  return [
    ChecklistItem('owner', (ov['has_owner'] ?? (_int(r?['smownerid']) > 0)) == true),
    ChecklistItem('activities', open == 0, value: '${total - open}/$total'),
    if (requireReportSignatures)
      ChecklistItem('report_signatures', jobReportMissing(r).isEmpty, value: '${2 - jobReportMissing(r).length}/2'),
    if (!requireReportSignatures || st > 0) ChecklistItem('signatures', st == 0 || ss >= st, value: '$ss/$st'),
    ChecklistItem('parts', _int(ov['parts']) > 0, value: '${_int(ov['parts'])}', info: true),
  ];
}

/// Title / hint / button text for a next action.
String nextTitle(String module, NextAction a, {Map<String, Object?> params = const {}}) =>
    jt('journey.$module.next.${a.key}.title', fallback: a.key, params: params);
String nextHint(String module, NextAction a, {Map<String, Object?> params = const {}}) =>
    jt('journey.$module.next.${a.key}.hint', fallback: '', params: params);
String actionLabel(String module, String action) => jt('journey.$module.action.$action', fallback: action);

Object? _jsonDecode(String s) => jsonDecode(s);
