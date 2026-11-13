import 'dart:convert';

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
import '../../core/entity_display.dart' show userDisplayName;
import '../calendar/activity_outcome_notes.dart';
import '../profile/my_signatures_screen.dart' show SignaturePadScreen;
import 'job_activity_gen.dart';
import 'job_report_signatures.dart';
import 'job_sign_link.dart';
import 'job_work_sections.dart';
import 'journey_controller.dart';
import 'journey_photos.dart';
import '../docs/document_preview.dart';
import 'journey_widgets.dart';
import 'status_followups.dart';

export 'job_activity_gen.dart' show showJobActivityGenSheet;
export 'job_sign_link.dart' show showPublicLinkSheet, PublicLinkHooks;

const _danger = Color(0xFFE11D48);

/// Job journey steps: เปิดงาน → รอการตอบรับ → กำลังดำเนินการ → ปิดงาน (+ ยกเลิก).
List<NxStep> jobSteps() => [
      for (final s in kJobMain) NxStep(id: s, label: jobStatusLabel(s), isDone: s == 'Completed'),
    ];

int jobCurrentStep(Map<String, dynamic> row) {
  final c = canonicalJobStatus(row['job_status']);
  return kJobMain.indexOf(c);
}

String _fmt(Object? v) {
  final d = parseThai(v);
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month}/${d.year + 543} ${two(d.hour)}:${two(d.minute)}';
}

int _n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Summary of a job — ONE scrolling page with everything to do the work:
/// next step, KPIs, work info (customer / site / asset / SLA), the activities
/// (ปฏิบัติงาน), job photos, the report write-ups (Problem / Action Taken /
/// Suggestions / Remark), the two report signatures, field work (skills,
/// parts, Workspace, inspection), close checklist and the journey trail.
/// [sectionKeys] (`activities`, `signatures`, `ops`) let the page scroll to a
/// section instead of switching tabs.
class JobSummaryTab extends StatelessWidget {
  const JobSummaryTab({
    super.key,
    required this.row,
    required this.ctrl,
    required this.canEdit,
    required this.onAction,
    required this.onGoTab,
    required this.onReload,
    required this.onOpen,
    this.busy = false,
    this.sectionKeys = const {},
    this.fieldOps,
    this.users = const [],
    this.picklists = const {},
    this.onCreateActivity,
    this.onSaveActivityTemplate,
    this.reloadToken,
  });

  final Map<String, dynamic> row;
  final JourneyController ctrl;
  final bool canEdit;
  final bool busy;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onGoTab;
  final VoidCallback onReload;
  final void Function(String module, String id) onOpen;
  final Map<String, GlobalKey> sectionKeys;

  /// "งานสนาม" (skills, parts, matching technicians, Workspace, inspection).
  final Widget? fieldOps;
  final List<Map<String, dynamic>> users;
  final Map<String, List<Map<String, dynamic>>> picklists;
  final VoidCallback? onCreateActivity;
  final VoidCallback? onSaveActivityTemplate;
  final Object? reloadToken;

  Widget _anchor(String id, Widget child) {
    final k = sectionKeys[id];
    return k == null ? child : KeyedSubtree(key: k, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ov = ctrl.overview;
    // Business setting close.require_both_signatures (default on); signed
    // staff / customer slots count like on the server.
    final requireBoth = ctrl.requireBothSignatures;
    final slots = ctrl.signatureSlots;
    final next = jobNextAction(row, ov, canEdit: canEdit, requireReportSignatures: requireBoth, slots: slots);
    final acts = _m(ov['activities']);
    final sig = _m(ov['signatures']);
    final hasOwner = ov['has_owner'] ?? (_n(row['smownerid']) > 0);
    final owner = (row['smownerid_name'] ?? row['owner_name'] ?? row['assigned_user_name'] ?? '').toString();
    final planStart = row['plan_start'] ?? row['planned_start'] ?? row['date_start'];
    final nextAt = acts['next_at'];
    final checklist = jobCloseChecklist(row, ov, requireReportSignatures: requireBoth, slots: slots);
    final status = canonicalJobStatus(row['job_status']);
    final qt = _m(ov['quotation']);
    final account = (row['account_name'] ?? row['accountid_name'] ?? '').toString();
    final activities = ctrl.linked('activities');
    final photos = jobEvidencePhotos(row);
    // Close rule: technician + customer (a signed slot of that role counts).
    final reportSigned = 2 - jobReportMissing(row, slots: slots).length;
    final sigSigned = 2 - jobReportMissing(row).length + _n(sig['signed']);
    const ok = Color(0xFF16A34A);
    final badgeColor = reportSigned == 2 ? ok : (requireBoth ? const Color(0xFFD97706) : theme.colorScheme.onSurfaceVariant);
    final sigTotal = 2 + _n(sig['total']);
    final ownerName = () {
      if (owner.isNotEmpty) return owner;
      final id = '${row['smownerid'] ?? ''}';
      for (final u in users) {
        if ('${u['user_id'] ?? u['id']}' == id) return userDisplayName(u);
      }
      return '';
    }();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NextActionCard(
          module: 'job',
          compact: true,
          next: next,
          onAction: onAction,
          busy: busy,
          params: {'signed': next.key == 'report_signatures' ? reportSigned : _n(sig['signed']), 'total': _n(sig['total']), 'open': _n(acts['open']), 'n': _n(acts['open'])},
        ),
        const SizedBox(height: 12),
        KpiGrid(tiles: [
          KpiTile(
            id: 'schedule',
            icon: NxI.calendarClock,
            label: tr('นัดหมาย'),
            value: planStart == null ? tr('ยังไม่นัด') : _fmt(planStart),
            hint: nextAt == null ? null : '${tr('กิจกรรมถัดไป')} ${_fmt(nextAt)}',
            tone: planStart == null ? 'warning' : 'neutral',
            onTap: () => onGoTab('ops'),
          ),
          KpiTile(
            id: 'owner',
            icon: NxI.userCircle,
            label: tr('ช่าง / ผู้รับผิดชอบ'),
            value: hasOwner == true ? (ownerName.isEmpty ? tr('มอบหมายแล้ว') : ownerName) : tr('ยังไม่มอบหมาย'),
            tone: hasOwner == true ? 'neutral' : 'warning',
            onTap: () => onGoTab('ops'),
          ),
          KpiTile(
            id: 'activities',
            icon: NxI.calendarCheck,
            label: tr('กิจกรรมเสร็จ'),
            value: '${_n(acts['done'])}/${_n(acts['total'])}',
            hint: _n(acts['open']) > 0 ? tr('ค้าง ${_n(acts['open'])} รายการ') : null,
            tone: _n(acts['open']) > 0 ? 'primary' : 'success',
            onTap: () => onGoTab('activities'),
          ),
          KpiTile(
            id: 'signatures',
            icon: NxI.penLine,
            label: tr('ลายเซ็น'),
            value: '$sigSigned/$sigTotal',
            hint: requireBoth && reportSigned < 2 ? tr('ต้องมีลายเซ็น 2 รายการ') : null,
            tone: sigTotal <= sigSigned
                ? 'success'
                : ((requireBoth && reportSigned < 2) || _n(sig['total']) > _n(sig['signed']) ? 'warning' : 'neutral'),
            onTap: () => onGoTab('signatures'),
          ),
        ]),
        const SizedBox(height: 12),
        JobWorkInfoCard(row: row, onOpen: onOpen, picklists: picklists),
        const SizedBox(height: 12),
        _anchor(
          'activities',
          JobActivitiesList(
            jobId: '${row['id']}',
            linked: activities,
            users: users,
            canEdit: canEdit && status != 'Cancelled' && status != 'Completed',
            onOpen: (id) => onOpen('activity', id),
            onGenerate: () => onAction('gen_activity'),
            onCreate: onCreateActivity,
            onSaveTemplate: onSaveActivityTemplate,
            reloadToken: reloadToken,
          ),
        ),
        const SizedBox(height: 12),
        JourneyPhotosSection(
          module: 'job',
          id: '${row['id']}',
          photos: photos,
          onChanged: onReload,
          compact: true,
          canEdit: canEdit && status != 'Cancelled',
        ),
        const SizedBox(height: 12),
        JourneySection(
          key: const ValueKey('job-report-section'),
          title: tr('บันทึกรายงานงาน'),
          icon: NxI.clipboardText,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('พิมพ์แล้วบันทึกเอง — ขึ้นในใบรายงานงานทันที'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              ActivityOutcomeNotes(
                key: ValueKey('job-report-notes-${row['id']}'),
                activityId: '${row['id']}',
                module: 'job',
                sections: kJobReportSections,
                row: row,
                readOnly: !canEdit || status == 'Cancelled',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _anchor(
          'signatures',
          JourneySection(
            key: const ValueKey('job-signatures-section'),
            title: tr('ลายเซ็น'),
            icon: NxI.penLine,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('$reportSigned/2', key: const ValueKey('job-signatures-badge'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: badgeColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                JobReportSignatures(jobId: '${row['id']}', row: row, canEdit: canEdit, onChanged: onReload),
                JobSignaturesTab(jobId: '${row['id']}', ctrl: ctrl, canEdit: canEdit, row: row, onChanged: onReload, embedded: true),
              ],
            ),
          ),
        ),
        if (status == 'In Progress' || status == 'Completed') ...[
          const SizedBox(height: 12),
          JourneySection(
            title: tr('ความพร้อมปิดงาน'),
            icon: NxI.checks,
            trailing: ov['can_close'] == true && status == 'In Progress'
                ? FilledButton.tonal(key: const ValueKey('checklist-close'), onPressed: busy ? null : () => onAction('close'), child: Text(actionLabel('job', 'close')))
                : (ov['can_reopen'] == true && status == 'Completed')
                    ? OutlinedButton(onPressed: busy ? null : () => onAction('reopen'), child: Text(actionLabel('job', 'reopen')))
                    : null,
            child: Column(
              children: [
                for (final c in checklist)
                  ChecklistRow(
                    label: switch (c.key) {
                      'owner' => tr('มีผู้รับผิดชอบ'),
                      'activities' => tr('กิจกรรมเสร็จครบ'),
                      'report_signatures' => tr('ลายเซ็นผู้ให้บริการ + ลูกค้า'),
                      'signatures' => tr('ลายเซ็นครบ'),
                      _ => tr('อะไหล่ที่ใช้'),
                    },
                    ok: c.ok,
                    value: c.key == 'owner' ? null : c.value,
                    info: c.info,
                  ),
              ],
            ),
          ),
        ],
        if (fieldOps != null) ...[
          const SizedBox(height: 12),
          _anchor('ops', fieldOps!),
        ],
        const SizedBox(height: 12),
        JourneySection(
          title: tr('เส้นทางงาน'),
          icon: NxI.arrowsLeftRight,
          child: JourneyTrail(nodes: [
            (NxI.buildings, account.isEmpty ? ((row['customer_name'] ?? '').toString().isEmpty ? tr('ลูกค้า') : row['customer_name'].toString()) : account, tr('ลูกค้า'), false,
                (row['account_id'] ?? row['related_account_id']) != null ? () => onOpen('account', '${row['account_id'] ?? row['related_account_id']}') : null),
            if (qt.isNotEmpty)
              (
                NxI.receipt,
                '${qt['quotation_no'] ?? ''} ${qt['title_th'] ?? ''}'.trim(),
                [tr('ใบเสนอราคา'), if (qt['outcome_result'] == 'Won') tr('ชนะ'), if ((qt['po_reference'] ?? '').toString().isNotEmpty) 'PO ${qt['po_reference']}'].join(' · '),
                false,
                () => onOpen('quotation', '${qt['id']}'),
              ),
            (NxI.wrench, '${row['job_no'] ?? ''} ${row['job_name'] ?? ''}'.trim(), '${tr('ใบสั่งงาน')} · ${jobStatusLabel(row['job_status'])}', true, null),
            (NxI.calendarCheck, tr('กิจกรรม ${_n(acts['total'])} รายการ'), _n(acts['open']) > 0 ? tr('ยังเปิด ${_n(acts['open'])}') : null, false, () => onGoTab('activities')),
          ]),
        ),
        const SizedBox(height: 12),
        DocumentCard(source: () => jobDocumentSource(row)),
        if ((row['cancel_reason'] ?? ov['cancel_reason'] ?? '').toString().isNotEmpty || (ov['close_note'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          JourneySection(
            title: status == 'Cancelled' ? tr('เหตุผลที่ยกเลิก') : tr('สรุปผลการปิดงาน'),
            icon: NxI.note,
            child: Text((status == 'Cancelled' ? (row['cancel_reason'] ?? ov['cancel_reason']) : ov['close_note']).toString(), style: theme.textTheme.bodyMedium),
          ),
        ],
      ],
    );
  }
}

/// Signature slots: sign on screen, "use my signature", clear.
/// [embedded] (job summary): only the settings' extra slots (if any) and the
/// customer link — no empty-state card, no document card.
class JobSignaturesTab extends StatefulWidget {
  const JobSignaturesTab({super.key, required this.jobId, required this.ctrl, required this.canEdit, required this.onChanged, required this.row, this.embedded = false});
  final bool embedded;
  final String jobId;
  final JourneyController ctrl;
  final bool canEdit;
  final VoidCallback onChanged;
  final Map<String, dynamic> row;

  @override
  State<JobSignaturesTab> createState() => _JobSignaturesTabState();
}

class _JobSignaturesTabState extends State<JobSignaturesTab> {
  String? _busy;

  List<Map<String, dynamic>> get _slots => [
        for (final s in (widget.ctrl.signatures['slots'] as List? ?? const []))
          if (s is Map) Map<String, dynamic>.from(s),
      ];

  bool get _locked {
    final st = canonicalJobStatus(widget.row['job_status']);
    return st == 'Completed' || st == 'Cancelled';
  }

  Future<void> _sign(Map<String, dynamic> slot, {bool mine = false}) async {
    final key = slot['slot_key'].toString();
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    String? sigPath;
    if (mine) {
      try {
        final me = await api.getMySignatures();
        sigPath = (me['upload_signature_th'] ?? me['upload_signature_en'])?.toString();
      } catch (_) {}
      if (sigPath == null || sigPath.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(tr('ยังไม่มีลายเซ็นของฉัน — ตั้งได้ที่ โปรไฟล์ → ลายเซ็น'))));
        return;
      }
    } else {
      if (!mounted) return;
      final png = await Navigator.of(context, rootNavigator: true).push<List<int>>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SignaturePadScreen()),
      );
      if (png == null || png.isEmpty) return;
      sigPath = 'data:image/png;base64,${base64Encode(png)}';
    }
    if (!mounted) return;
    var name = (slot['signer_name'] ?? '').toString();
    final required = slot['name_mode'] == 'required';
    if (name.isEmpty) {
      final me = context.read<AppConfig>().session;
      name = mine ? (me.displayName ?? '') : '';
      final ctrl = TextEditingController(text: name);
      final ok = await showAppBottomSheet<bool>(
        context: context,
        title: tr('ชื่อผู้เซ็น'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(key: const ValueKey('signer-name'), controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: tr(required ? 'ชื่อ-นามสกุล *' : 'ชื่อ-นามสกุล'))),
            const SizedBox(height: 12),
            FilledButton(key: const ValueKey('signer-save'), onPressed: () => Navigator.pop(context, true), child: Text(tr('บันทึกลายเซ็น'))),
          ],
        ),
      );
      if (ok != true) return;
      name = ctrl.text.trim();
      if (required && name.isEmpty) return;
    }
    setState(() => _busy = key);
    try {
      await api.putJobSignature(widget.jobId, key, signerName: name, signature: sigPath);
      HapticFeedback.mediumImpact();
      widget.onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(journeyErrorText(e)))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _clear(Map<String, dynamic> slot) async {
    final api = context.read<AppConfig>().apiClient;
    setState(() => _busy = slot['slot_key'].toString());
    try {
      await api.putJobSignature(widget.jobId, slot['slot_key'].toString(), signerName: null, signature: null);
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(journeyErrorText(e)))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final api = context.read<AppConfig>().apiClient;
    final slots = _slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded && slots.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(tr('ลายเซ็นตามตั้งค่างาน'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
        ],
        if (slots.isEmpty && !widget.embedded)
          JourneySection(title: tr('ลายเซ็น'), icon: NxI.penLine, child: Text(tr('งานประเภทนี้ไม่ต้องเก็บลายเซ็น'), style: theme.textTheme.bodyMedium)),
        for (final s in slots) ...[
          JourneySection(
            title: (L10n.isEn ? s['position_en'] : s['position_th'])?.toString() ?? s['slot_key'].toString(),
            icon: NxI.penLine,
            trailing: Chip(
              visualDensity: VisualDensity.compact,
              label: Text(tr(s['signer_role'] == 'customer' ? 'ลูกค้า' : 'พนักงาน')),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ((s['signature_path'] ?? '').toString().isNotEmpty) ...[
                  Container(
                    height: 110,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
                    padding: const EdgeInsets.all(8),
                    child: Image.network(
                      (s['signature_path'].toString().startsWith('data:'))
                          ? s['signature_path'].toString()
                          : api.absoluteUrl(s['signature_url']?.toString() ?? '/uploads/${s['signature_path'].toString().replaceFirst(RegExp(r'^/+'), '')}'),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Center(child: Icon(NxI.checkCircle, color: cs.primary)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${s['signer_name'] ?? ''}${s['signed_at'] == null ? '' : ' · ${_fmt(s['signed_at'])}'}', style: theme.textTheme.bodySmall),
                ] else
                  Text(tr('ยังไม่ได้เซ็น'), style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFD97706))),
                if (widget.canEdit && !_locked) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: ValueKey('sign-${s['slot_key']}'),
                        onPressed: _busy != null ? null : () => _sign(s),
                        icon: const Icon(NxI.penLine, size: 18),
                        label: Text(tr((s['signature_path'] ?? '').toString().isEmpty ? 'เซ็นบนจอ' : 'เซ็นใหม่')),
                      ),
                    ),
                    if (s['signer_role'] != 'customer') ...[
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: _busy != null ? null : () => _sign(s, mine: true), child: Text(tr('ใช้ลายเซ็นของฉัน'))),
                    ],
                    if ((s['signature_path'] ?? '').toString().isNotEmpty)
                      IconButton(tooltip: tr('ล้าง'), onPressed: _busy != null ? null : () => _clear(s), icon: const Icon(NxI.trash)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.embedded)
          JobSignLinkCard(jobId: widget.jobId, row: widget.row, overview: widget.ctrl.overview, canEdit: widget.canEdit, onChanged: widget.onChanged)
        else ...[
          DocumentCard(source: () => jobDocumentSource(widget.row)),
          const SizedBox(height: 12),
          JobSignLinkCard(jobId: widget.jobId, row: widget.row, overview: widget.ctrl.overview, canEdit: widget.canEdit, onChanged: widget.onChanged, embedded: false),
        ],
      ],
    );
  }
}

/// Run a job next-step / step action.
Future<bool> runJobAction(
  BuildContext context, {
  required String action,
  required Map<String, dynamic> row,
  required JourneyController ctrl,
  required ValueChanged<String> goTab,
}) async {
  final id = '${row['id']}';
  switch (action) {
    case 'gen_activity':
      final ok = await showJobActivityGenSheet(context, jobId: id, row: row);
      if (ok) goTab('activities');
      return ok;
    case 'close':
      // close.require_both_signatures (business setting, default on): both
      // report signatures — or signed staff / customer slots — before closing.
      final missing = ctrl.closeSignaturesMissing(row);
      if (missing.isNotEmpty) {
        await showJobSignaturesRequired(context, jobId: id, row: row, missing: missing, openSignatures: () => goTab('signatures'));
        return true; // reload: a signature may have been added
      }
    case 'open_activities':
      goTab('activities');
      return false;
    case 'open_signatures':
      goTab('signatures');
      return false;
    case 'schedule':
      goTab('ops');
      return false;
  }
  return JobFlows.run(context, jobId: id, action: action, row: row, overview: ctrl.overview, openSignatures: () => goTab('signatures'));
}

/// Side chip for a cancelled job.
String? jobSideLabel(Map<String, dynamic> row) =>
    canonicalJobStatus(row['job_status']) == 'Cancelled' ? jobStatusLabel('Cancelled') : null;

Color get jobDangerColor => _danger;
