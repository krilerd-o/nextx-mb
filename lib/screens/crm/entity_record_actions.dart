import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_form_rules.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_skeleton.dart';
import '../deep_link_loaders.dart';
import 'entity_create_screen.dart';
import 'entity_detail_parts.dart';
import 'lead_convert_sheet.dart';
import '../../core/journey_rules.dart';
import '../../core/service_journey.dart';
import '../../core/deal_stage.dart';
import '../fsm/contract_flows.dart';
import '../fsm/service_more.dart';
import '../journey/case_flows.dart';
import '../doc_form/doc_form_launcher.dart';
import '../journey/status_followups.dart';

/// What the current user may do with one record (same rules as the web list:
/// `_shared_permission` read_only = view only, edit = edit/duplicate, full =
/// also delete; a converted lead is locked).
class EntityRowPerms {
  const EntityRowPerms({required this.canEdit, required this.canDelete, required this.canStatus});

  final bool canEdit;
  final bool canDelete;

  /// Status can change here (not for cases: those move on the case screen).
  final bool canStatus;

  static const _converted = {'converted', 'แปลงแล้ว', 'แปลงเป็นลูกค้าแล้ว'};

  static bool leadLocked(Map<String, dynamic> row) {
    bool has(String k) {
      final v = row[k];
      return v != null && '$v'.trim().isNotEmpty && '$v' != '0' && '$v' != 'null';
    }

    if (has('convert_contact_id') || has('convert_account_id')) return true;
    if (has('convert_contact') && has('contact_name')) return true;
    if (has('convert_account') && has('account_name')) return true;
    final s = '${row['lead_status'] ?? row['leadstatus'] ?? ''}'.trim().toLowerCase();
    return _converted.contains(s);
  }

  factory EntityRowPerms.of(String module, Map<String, dynamic> row) {
    final perm = '${row['_shared_permission'] ?? 'full'}';
    var edit = perm != 'read_only';
    if (module == 'lead' && leadLocked(row)) edit = false;
    return EntityRowPerms(canEdit: edit, canDelete: perm == 'full', canStatus: module == 'case' || edit);
  }
}

/// Record commands shared by the list (long-press sheet) and the detail
/// screen: change status, comments, edit, duplicate, delete.
class EntityRecordActions {
  EntityRecordActions._();

  /// Status column per module, like the web (`getEntityStatusColumn`).
  static String webStatusColumn(String module) => switch (module) {
        'contact' => 'contact_status',
        'account' => 'account_status',
        'case' => 'case_status',
        'product' => 'product_status',
        'service' => 'service_status',
        'deal' => 'deal_stage',
        'quotation' => 'quotation_status',
        'service_contract' => 'contract_status',
        'activity' => 'status',
        _ => 'lead_status',
      };

  static const _statusCandidates = [
    'status', 'leadstatus', 'lead_status', 'deal_stage', 'sales_stage', 'case_status', 'quotation_status',
    'job_status', 'inspection_status', 'account_status', 'contact_status', 'activity_status', 'contract_status',
  ];

  /// The picklist field that holds the record's status (null = none).
  static String? statusKey(String module, Map<String, List<Map<String, dynamic>>> picklists, [Map<String, dynamic>? row]) {
    for (final k in [webStatusColumn(module), '${module}_status', '${module}_stage', ..._statusCandidates]) {
      if ((picklists[k] ?? const []).isNotEmpty) return k;
    }
    return row == null ? null : entityStatusKey(row, module);
  }

  /// Status choices in their real order (Product / Service: draft first).
  static List<({String value, String label, String? color})> statusOptions(
    String module,
    String? key,
    Map<String, List<Map<String, dynamic>>> picklists, {
    String? current,
  }) {
    if (key == null) return const [];
    final raw = picklists[key] ?? const <Map<String, dynamic>>[];
    final colors = <String, String?>{};
    final opts = <({String value, String label})>[];
    for (final o in raw) {
      final p = NxPickOption.fromMap(o);
      colors[p.value] = o['color']?.toString();
      final canon = statusCurrent(module, p.value);
      if (canon != null) colors.putIfAbsent(canon, () => o['color']?.toString());
      opts.add((value: p.value, label: p.label));
    }
    return [
      for (final o in orderStatusOptions(module, opts, current: current)) (value: o.value, label: o.label, color: colors[o.value]),
    ];
  }

  /// Colour for a status: the picklist's own colour, else from the word.
  static Color statusColor(ColorScheme cs, String value, [String? hex]) => nxStatusTone(cs, value, hex);

  /// Tap-to-pick reasons for losing a deal (same presets as the web).
  static const dealLostReasons = ['ราคาสูงกว่าคู่แข่ง', 'ลูกค้าเลื่อน/ยกเลิกโครงการ', 'ไม่ตรงความต้องการ', 'งบประมาณไม่พอ', 'เลือกเจ้าเดิม'];

  /// What else changes when a record moves to [to] (shown in the confirm sheet).
  static String? statusImpact(String module, String to) {
    final w = to.toLowerCase();
    switch (module) {
      case 'deal':
        if (to == kDealClosedWon) return 'นับเป็นดีลที่ชนะในยอดขาย · ความน่าจะเป็น 100%';
        if (to == kDealClosedLost) return 'นับเป็นดีลที่แพ้ · ความน่าจะเป็น 0%';
        final p = dealProbabilityFor(to);
        return p == null ? null : 'ความน่าจะเป็นของดีลจะเป็น $p%';
      case 'lead':
        if (RegExp(r'unqualified|lost|junk|ไม่ผ่าน').hasMatch(w)) return 'ผู้มุ่งหวังนี้จะหลุดจากรายการที่กำลังติดตาม';
        return null;
      case 'activity':
        if (RegExp(r'cancel|not held|ยกเลิก').hasMatch(w)) return 'กิจกรรมนี้จะไม่นับในงานที่ต้องทำ';
        if (RegExp(r'held|done|complete|เสร็จ').hasMatch(w)) return 'นับเป็นกิจกรรมที่ทำเสร็จแล้ว';
        return null;
      case 'product' || 'service':
        if (RegExp(r'inactive|discontinued|ไม่ใช้งาน|เลิก').hasMatch(w)) return 'จะเลือกใช้ในใบเสนอราคา / เอกสารใหม่ไม่ได้';
        return null;
      case 'account' || 'contact':
        if (RegExp(r'inactive|ไม่ใช้งาน').hasMatch(w)) return 'รายการนี้จะถูกซ่อนจากการเลือกในเอกสารใหม่';
        return null;
    }
    return null;
  }

  /// Confirm sheet for a plain status change (current → new). Deal
  /// "Closed Lost" needs a reason (saved as `closed_reason`); other modules
  /// take no note on a plain update, so none is asked. Null = cancelled.
  static Future<NxStatusConfirm?> confirmStatus(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    required List<({String value, String label, String? color})> options,
    required String? from,
    required String to,
  }) {
    final cs = Theme.of(context).colorScheme;
    final cur = statusCurrent(module, from) ?? from;
    final f = options.where((o) => o.value == cur || o.value == from || (from != null && o.label == from)).firstOrNull;
    final t = options.where((o) => o.value == to).firstOrNull;
    final lost = module == 'deal' && to == kDealClosedLost;
    return showStatusChangeConfirm(
      context,
      recordTitle: entityTitle(row, module: module),
      from: f?.label ?? from,
      fromColor: f == null && (from ?? '').isEmpty ? null : statusColor(cs, f?.value ?? from ?? '', f?.color),
      to: t?.label ?? to,
      toColor: statusColor(cs, to, t?.color),
      impact: statusImpact(module, to),
      requireReason: lost,
      reasons: lost ? dealLostReasons : const [],
      noteLabel: lost ? 'เหตุผลที่แพ้' : null,
      initialNote: lost ? '${row['closed_reason'] ?? ''}'.trim() : '',
      noteKey: lost ? const ValueKey('deal-lost-reason') : const ValueKey('status-confirm-note'),
      destructive: nxIsDestructiveStatus('$to ${t?.label ?? ''}'),
    );
  }

  /// Fields the edit / duplicate form shows (schema, else the row's keys).
  static List<Map<String, dynamic>> editableFields(List<Map<String, dynamic>> fields, Map<String, dynamic> row) {
    if (fields.isNotEmpty) {
      return fields.where((f) {
        final name = fieldName(f);
        if (name.isEmpty || name == 'id' || name == 'business_id') return false;
        return !fieldIsReadonly(f);
      }).toList();
    }
    return row.keys
        .where((k) {
          final lower = k.toLowerCase();
          return k != 'id' && k != 'business_id' && !lower.startsWith('_') && lower != 'created_at' && lower != 'updated_at';
        })
        .map((k) => <String, dynamic>{'name': k, 'label_th': k})
        .toList();
  }

  static void _snack(ScaffoldMessengerState? m, String text) {
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr(text))));
  }

  /// Full record + schema (list rows are slim: only the card's columns).
  static Future<({Map<String, dynamic> row, ModuleFieldSchema? schema})> load(
    BuildContext context,
    String module,
    Map<String, dynamic> row,
  ) async {
    final api = context.read<AppConfig>().apiClient;
    final id = '${row['id'] ?? ''}';
    ModuleFieldSchema? schema;
    var full = row;
    await Future.wait([
      () async {
        try {
          schema = await api.getFieldSchema(module);
        } catch (_) {}
      }(),
      if (id.isNotEmpty)
        api.getEntity(module, id).then((r) {
          if (r.isNotEmpty) full = {...row, ...r};
        }),
    ]);
    return (row: full, schema: schema);
  }

  /// Sheet of status pills; picking one saves at once. Returns the new value.
  static Future<String?> changeStatus(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    Map<String, List<Map<String, dynamic>>>? picklists,
    void Function(String key, String value)? onChanged,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final api = context.read<AppConfig>().apiClient;
    // Service Journey: job / quotation status moves through the workflow (with its dialogs).
    if (ServiceJourney.handles(module) && await ServiceJourney.supported(api)) {
      if (!context.mounted) return null;
      return _journeyStatus(context, module: module, row: row, onChanged: onChanged);
    }
    if (!context.mounted) return null;
    // Case: same windows as the web (accept / forward / close / cancel).
    if (module == 'case') {
      final id = '${row['id'] ?? row['caseid'] ?? ''}';
      final action = await pickCaseAction(context, row);
      if (action == null || !context.mounted) return null;
      final ok = await CaseFlows.run(context, caseId: id, action: action, row: row);
      if (!ok) return null;
      try {
        final fresh = await api.getEntity('case', id);
        final v = '${fresh['case_status'] ?? ''}';
        onChanged?.call('case_status', v);
        return v;
      } catch (_) {
        return '';
      }
    }
    // Activity waiting for approval: the server keeps its status until decided.
    if (module == 'activity' && '${row['approval_state'] ?? ''}'.toLowerCase() == 'pending') {
      messenger?.showSnackBar(SnackBar(content: Text(tr('กิจกรรมนี้รออนุมัติอยู่ — เปลี่ยนสถานะได้หลังผู้อนุมัติตัดสิน (เมนูรออนุมัติ)'))));
      return null;
    }
    // Service contract: status moves only through the workflow (approve, sign…).
    if (module == 'service_contract') {
      final action = await pickContractAction(context, row);
      if (action == null || !context.mounted) return null;
      final rec = await ContractFlows.run(context, row: row, action: action);
      if (rec == null) return null;
      final v = '${rec['contract_status'] ?? ''}';
      onChanged?.call('contract_status', v);
      return v;
    }
    var lists = picklists;
    if (lists == null || lists.isEmpty) {
      try {
        lists = (await api.getFieldSchema(module)).picklists;
      } catch (e) {
        _snack(messenger, formatApiError(e));
        return null;
      }
    }
    if (!context.mounted) return null;
    final key = statusKey(module, lists, row);
    final options = statusOptions(module, key, lists, current: key == null ? null : row[key]?.toString());
    if (key == null || options.isEmpty) {
      _snack(messenger, 'เมนูนี้ไม่มีสถานะให้เปลี่ยน');
      return null;
    }
    final before = row[key]?.toString();
    final picked = await showAppBottomSheet<String>(
      context: context,
      title: tr('ปรับสถานะ'),
      child: EntityStatusPickList(options: options, current: statusCurrent(module, before)),
    );
    if (picked == null || picked == before || picked == statusCurrent(module, before) || !context.mounted) return null;
    // A lead becomes "Converted" only through the convert window (creates Account / Contact).
    if (module == 'lead' && isLeadConvertedStatus(picked)) {
      final r = await showLeadConvertSheet(context, leadId: '${row['id']}');
      if (r == null) return null;
      onChanged?.call(key, 'Converted');
      return 'Converted';
    }
    final id = '${row['id'] ?? ''}';
    final label = options.firstWhere((o) => o.value == picked).label;
    final ok = await confirmStatus(context, module: module, row: row, options: options, from: before, to: picked);
    if (ok == null || !context.mounted) return null;
    // Deal: probability follows the stage; Closed Lost needs a reason (like the web).
    Map<String, dynamic> payload = {key: picked};
    Map<String, dynamic> back = {key: before};
    if (module == 'deal' && key == 'deal_stage') {
      payload = dealStagePayload(picked, lostReason: picked == kDealClosedLost ? ok.note : null);
      if (before != null) back = dealStagePayload(before);
    }
    onChanged?.call(key, picked);
    try {
      await api.putEntity(module, id, payload);
      if (module == 'deal' && picked == kDealClosedWon && '${row['related_board_id'] ?? ''}'.isEmpty && context.mounted) {
        showDealWorkspaceHandoff(context, id, afterWon: true);
      }
      showNxStatusChangedSnack(
        messenger,
        label: label,
        undo: before == null
            ? null
            : () async {
                onChanged?.call(key, before);
                try {
                  await api.putEntity(module, id, back);
                } catch (e) {
                  onChanged?.call(key, picked);
                  _snack(messenger, formatApiError(e));
                }
              },
      );
      return picked;
    } catch (e) {
      if (before != null) onChanged?.call(key, before);
      _snack(messenger, formatApiError(e));
      return null;
    }
  }

  /// Job: allowed workflow actions; quotation: offer status / close sale / cancel.
  static Future<String?> _journeyStatus(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    void Function(String key, String value)? onChanged,
  }) async {
    final api = context.read<AppConfig>().apiClient;
    final id = '${row['id'] ?? ''}';
    var full = row;
    try {
      final r = await api.getEntity(module, id);
      if (r.isNotEmpty) full = {...row, ...r};
    } catch (_) {}
    if (!context.mounted) return null;
    if (module == 'job') {
      final actions = jobWorkflowActions(full['job_status']);
      if (actions.isEmpty) {
        _snack(ScaffoldMessenger.maybeOf(context), 'งานนี้ยกเลิกแล้ว — เปลี่ยนสถานะไม่ได้');
        return null;
      }
      final picked = await showAppBottomSheet<String>(
        context: context,
        title: '${tr('ปรับสถานะ')} · ${jobStatusLabel(full['job_status'])}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                key: ValueKey('job-status-action-$a'),
                leading: Icon(a == 'cancel' ? NxI.x : (a == 'close' ? NxI.flag : NxI.arrowRight)),
                title: Text(jt('journey.job.action.$a', fallback: a)),
                onTap: () => Navigator.pop(context, a),
              ),
          ],
        ),
      );
      if (picked == null || !context.mounted) return null;
      final ok = await JobFlows.run(context, jobId: id, action: picked, row: full);
      if (!ok) return null;
      try {
        final r = await api.getEntity('job', id);
        final v = r['job_status']?.toString();
        if (v != null) onChanged?.call('job_status', v);
        return v;
      } catch (_) {
        return null;
      }
    }
    // quotation
    final finished = isQuotationFinished(full);
    final cancelled = canonicalQuotationStatus(full['quotation_status']) == QS.cancelled;
    final offer = canonicalOfferStatus(full['offer_status']);
    final picked = await showAppBottomSheet<String>(
      context: context,
      title: tr('ปรับสถานะใบเสนอราคา'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!finished)
            for (final o in Offer.all)
              ListTile(
                key: ValueKey('qt-status-$o'),
                leading: Icon(o == Offer.closed ? NxI.flag : NxI.arrowRight),
                title: Text(o),
                trailing: o == offer ? const Icon(NxI.check) : null,
                onTap: o == offer ? null : () => Navigator.pop(context, o == Offer.closed ? 'close_sale' : 'offer:$o'),
              ),
          if (!finished)
            ListTile(key: const ValueKey('qt-status-cancel'), leading: const Icon(NxI.x), title: Text(tr('ยกเลิกใบเสนอราคา')), onTap: () => Navigator.pop(context, 'cancel')),
          if (cancelled)
            ListTile(leading: const Icon(NxI.arrowsClockwise), title: Text(tr('เปิดใบเสนอราคากลับ')), onTap: () => Navigator.pop(context, 'reopen')),
          if (finished && !cancelled)
            Padding(padding: const EdgeInsets.all(12), child: Text(tr('ใบเสนอราคานี้จบแล้ว — ทำสำเนาเป็นใบใหม่แทน'))),
        ],
      ),
    );
    if (picked == null || !context.mounted) return null;
    var ok = false;
    if (picked == 'close_sale') {
      final r = await showQuotationOutcomeSheet(context, quotationId: id);
      ok = r != null;
      // Won → offer to close the linked deal too (same as the detail page).
      if (r != null && context.mounted) await maybeSuggestCloseDeal(context, r['suggest_close_deal']);
    } else if (picked.startsWith('offer:')) {
      ok = await QuotationFlows.setOffer(context, id, picked.substring(6), from: offer.isEmpty ? null : offer, record: entityTitle(full, module: module));
    } else if (picked == 'cancel') {
      ok = await QuotationFlows.cancel(context, id, from: canonicalQuotationStatus(full['quotation_status']), record: entityTitle(full, module: module));
    } else if (picked == 'reopen') {
      ok = await QuotationFlows.reopen(context, id, record: entityTitle(full, module: module));
    }
    if (!ok) return null;
    try {
      final r = await api.getEntity('quotation', id);
      final v = r['quotation_status']?.toString();
      if (v != null) onChanged?.call('quotation_status', v);
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Tall sheet: the record's comment thread + composer (reply, attach).
  static Future<void> openComments(BuildContext context, {required String module, required Map<String, dynamic> row}) {
    return showNxSnapSheet<void>(
      context: context,
      title: tr('อัปเดตคอมเมนต์'),
      snaps: const [0.6, 0.92],
      initial: 0.6,
      builder: (ctx, controller) => _CommentsSheet(module: module, row: row, controller: controller),
    );
  }

  /// Edit form for the record; true when saved.
  static Future<bool> edit(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    List<Map<String, dynamic>>? fields,
    Map<String, List<Map<String, dynamic>>>? picklists,
    bool? root,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Quotation / job: the step form (loads its own record + schema).
    if (kStepFormModules.contains(module)) {
      final r = await openDocForm(context, module: module, mode: DocFormMode.edit, id: '${row['id']}', root: root);
      if (r != null) _snack(messenger, 'บันทึกแล้ว');
      return r != null;
    }
    var full = row;
    var f = fields;
    var p = picklists;
    if (f == null || p == null) {
      try {
        final l = await load(context, module, row);
        full = l.row;
        f = l.schema?.fields ?? const [];
        p = l.schema?.picklists ?? const {};
      } catch (e) {
        _snack(messenger, formatApiError(e));
        return false;
      }
    }
    if (!context.mounted) return false;
    final saved = await nxPush<bool>(
      context,
      EntityCreateScreen(
        module: module,
        title: 'แก้ไข',
        recordId: '${full['id']}',
        initialValues: Map<String, dynamic>.from(full),
        fields: editableFields(f, full),
        picklists: p,
      ),
      root: root,
    );
    if (saved == true) _snack(messenger, 'บันทึกแล้ว');
    return saved == true;
  }

  /// Duplicate like the web: a pre-filled form to review the copy; documents
  /// (quotation / job) are copied on the server with their lines.
  static Future<bool> duplicate(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    List<Map<String, dynamic>>? fields,
    Map<String, List<Map<String, dynamic>>>? picklists,
    bool? root,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final config = context.read<AppConfig>();
    final title = entityTitle(row, module: module);
    // Quotation / job: a pre-filled step form (customer, lines / place, terms copied; number, status, dates cleared).
    if (kStepFormModules.contains(module)) {
      final r = await openDocForm(context, module: module, mode: DocFormMode.duplicate, id: '${row['id']}', root: root ?? true);
      final newId = '${r?['id'] ?? ''}';
      if (newId.isEmpty || newId == 'null') return false;
      _snack(messenger, 'ทำซ้ำแล้ว — เปิดรายการใหม่');
      if (context.mounted) nxPush<void>(context, EntityByIdLoader(module: module, id: newId), root: root);
      return true;
    }
    if (!kServerDuplicateModules.contains(module)) {
      var full = row;
      var f = fields;
      var p = picklists;
      if (f == null || p == null) {
        try {
          final l = await load(context, module, row);
          full = l.row;
          f = l.schema?.fields ?? const [];
          p = l.schema?.picklists ?? const {};
        } catch (e) {
          _snack(messenger, formatApiError(e));
          return false;
        }
      }
      if (f.isNotEmpty) {
        final values = duplicateFormValues(module, full, userId: config.session.userId, picklists: p);
        if (values['smownerid'] != null) {
          values['smownerid'] = {
            'id': '${values['smownerid']}',
            'label': config.session.displayName ?? config.session.email ?? '${values['smownerid']}',
          };
        }
        if (!context.mounted) return false;
        final saved = await nxPush<bool>(
          context,
          EntityCreateScreen(
            module: module,
            title: 'ทำซ้ำ ${entityTitle(full, module: module)}',
            initialValues: values,
            fields: editableFields(f, full),
            picklists: p,
          ),
          root: root ?? true,
        );
        if (saved == true) _snack(messenger, 'ทำซ้ำแล้ว');
        return saved == true;
      }
    }
    if (!context.mounted) return false;
    // Other server-side copies (lines and links come along).
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(NxI.copySimple),
        title: Text(tr('ทำซ้ำรายการนี้?')),
        content: Text(tr('สร้างสำเนาของ $title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ทำซ้ำ'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return false;
    try {
      final newId = await config.apiClient.duplicateEntity(module, '${row['id']}');
      if (newId.isEmpty) return false;
      _snack(messenger, 'ทำซ้ำแล้ว — เปิดรายการใหม่');
      if (context.mounted) nxPush<void>(context, EntityByIdLoader(module: module, id: newId), root: root);
      return true;
    } catch (e) {
      _snack(messenger, formatApiError(e));
      return false;
    }
  }

  /// Confirm, then delete with a 5 s undo. True when scheduled.
  static Future<bool> delete(
    BuildContext context, {
    required String module,
    required Map<String, dynamic> row,
    VoidCallback? onCommitted,
  }) async {
    final title = entityTitle(row, module: module);
    final ok = await showDeleteConfirm(context, name: title, loses: entityDeleteLoses(module));
    if (!ok || !context.mounted) return false;
    final api = context.read<AppConfig>().apiClient;
    final id = '${row['id']}';
    PendingEntityDeletes.instance.schedule(
      messenger: ScaffoldMessenger.of(context),
      module: module,
      ids: [id],
      label: title,
      commit: () async {
        await api.deleteEntity(module, id);
        onCommitted?.call();
      },
    );
    return true;
  }
}

/// Status choices as coloured rows; the current one is ticked.
class EntityStatusPickList extends StatelessWidget {
  const EntityStatusPickList({super.key, required this.options, required this.current});

  final List<({String value, String label, String? color})> options;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, o) in options.indexed)
          () {
            final c = EntityRecordActions.statusColor(cs, o.value, o.color);
            final sel = o.value == current || o.label == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: sel ? c.withValues(alpha: 0.14) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: sel ? c : Colors.transparent, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('status-opt-${o.value}'),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, o.value);
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: c.withValues(alpha: 0.18), shape: BoxShape.circle),
                            child: Text(
                              '${i + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tr(o.label),
                              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
                            ),
                          ),
                          if (sel) Icon(NxI.checkCircle, color: c) else Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.module, required this.row, required this.controller});

  final String module;
  final Map<String, dynamic> row;
  final ScrollController controller;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<Map<String, dynamic>>? _comments;
  Object? _error;

  String get _id => '${widget.row['id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await context.read<AppConfig>().apiClient.getEntityComments(widget.module, _id);
      if (mounted) setState(() => _comments = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 20),
      children: [
        Row(
          children: [
            Icon(NxI.chatCircle, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entityTitle(widget.row, module: widget.module),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null && _comments == null)
          NxErrorRetry(error: _error!, onRetry: () {
            setState(() => _error = null);
            _load();
          })
        else if (_comments == null)
          const NxSkeletonList(rows: 3)
        else
          EntityCommentsPanel(module: widget.module, id: _id, comments: _comments!, onChanged: _load),
      ],
    );
  }
}

/// What a delete takes with it (listed in the red confirm sheet).
List<String> entityDeleteLoses(String module) => [
      switch (module) {
        'lead' => 'ข้อมูลผู้มุ่งหวังและที่อยู่',
        'contact' => 'ข้อมูลผู้ติดต่อ',
        'account' => 'ข้อมูลบัญชีลูกค้า',
        'deal' => 'ข้อมูลดีลและมูลค่า',
        'quotation' => 'ใบเสนอราคาและรายการสินค้า',
        'case' => 'ข้อมูลเคสและการนับ SLA',
        'job' => 'ใบสั่งงานและรายละเอียดงาน',
        'activity' => 'ข้อมูลกิจกรรมและรูปถ่าย',
        _ => 'ข้อมูลทั้งหมดของรายการนี้',
      },
      'คอมเม้นท์และไฟล์แนบ',
      'ประวัติการเปลี่ยนแปลง',
    ];
