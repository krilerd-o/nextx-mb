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
import '../profile/my_signatures_screen.dart' show SignaturePadScreen;
import 'journey_controller.dart';
import 'journey_photos.dart';
import 'journey_widgets.dart';
import 'status_followups.dart';

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

/// Summary tab of a job: next step, KPIs, today's work, photos, close
/// checklist, journey trail — everything to finish a job on one page.
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
  });

  final Map<String, dynamic> row;
  final JourneyController ctrl;
  final bool canEdit;
  final bool busy;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onGoTab;
  final VoidCallback onReload;
  final void Function(String module, String id) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ov = ctrl.overview;
    final next = jobNextAction(row, ov, canEdit: canEdit);
    final acts = _m(ov['activities']);
    final sig = _m(ov['signatures']);
    final hasOwner = ov['has_owner'] ?? (_n(row['smownerid']) > 0);
    final owner = (row['smownerid_name'] ?? row['owner_name'] ?? row['assigned_user_name'] ?? '').toString();
    final planStart = row['plan_start'] ?? row['planned_start'] ?? row['date_start'];
    final nextAt = acts['next_at'];
    final checklist = jobCloseChecklist(row, ov);
    final status = canonicalJobStatus(row['job_status']);
    final qt = _m(ov['quotation']);
    final account = (row['account_name'] ?? row['accountid_name'] ?? '').toString();
    final activities = ctrl.linked('activities');
    final photos = jobEvidencePhotos(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NextActionCard(
          module: 'job',
          next: next,
          onAction: onAction,
          busy: busy,
          params: {'signed': _n(sig['signed']), 'total': _n(sig['total']), 'open': _n(acts['open']), 'n': _n(acts['open'])},
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
            value: hasOwner == true ? (owner.isEmpty ? tr('มอบหมายแล้ว') : owner) : tr('ยังไม่มอบหมาย'),
            tone: hasOwner == true ? 'neutral' : 'warning',
            onTap: () => onGoTab('ops'),
          ),
          KpiTile(
            id: 'activities',
            icon: NxI.calendarCheck,
            label: tr('กิจกรรมเสร็จ'),
            value: '${_n(acts['done'])}/${_n(acts['total'])}',
            tone: _n(acts['open']) > 0 ? 'primary' : 'success',
            onTap: () => onGoTab('activities'),
          ),
          KpiTile(
            id: 'signatures',
            icon: NxI.penLine,
            label: tr('ลายเซ็น'),
            value: '${_n(sig['signed'])}/${_n(sig['total'])}',
            tone: _n(sig['total']) > _n(sig['signed']) ? 'warning' : 'success',
            onTap: () => onGoTab('signatures'),
          ),
        ]),
        if (activities.isNotEmpty && (status == 'In Progress' || status == 'Open' || status == 'Waiting')) ...[
          const SizedBox(height: 12),
          JourneySection(
            title: tr('ปฏิบัติงาน'),
            icon: NxI.mapPinned,
            trailing: TextButton(onPressed: () => onGoTab('activities'), child: Text(tr('ทั้งหมด'))),
            child: Column(
              children: [
                for (final a in activities.take(3))
                  ListTile(
                    key: ValueKey('job-act-${a['id']}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(NxI.calendarCheck),
                    title: Text((a['title'] ?? a['subject'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([a['subtitle'], a['status']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                    trailing: const Icon(NxI.caretRight, size: 16),
                    onTap: () => onOpen('activity', '${a['id']}'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        JourneyPhotosSection(
          module: 'job',
          id: '${row['id']}',
          photos: photos,
          onChanged: onReload,
          canEdit: canEdit && status != 'Cancelled',
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
        const SizedBox(height: 12),
        JourneySection(
          title: tr('เส้นทางงาน'),
          icon: NxI.arrowsLeftRight,
          child: JourneyTrail(nodes: [
            (NxI.buildings, account.isEmpty ? tr('ลูกค้า') : account, tr('ลูกค้า'), false,
                row['account_id'] != null ? () => onOpen('account', '${row['account_id']}') : null),
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
class JobSignaturesTab extends StatefulWidget {
  const JobSignaturesTab({super.key, required this.jobId, required this.ctrl, required this.canEdit, required this.onChanged, required this.row});
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

  Future<void> _customerLink() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final r = await api.jobPublicLink(widget.jobId);
      if (!mounted) return;
      await showPublicLinkSheet(context, api.absoluteUrl((r['path'] ?? '').toString()), pdf: r['pdf_path'] == null ? null : api.absoluteUrl(r['pdf_path'].toString()));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(journeyErrorText(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final api = context.read<AppConfig>().apiClient;
    final slots = _slots;
    final ack = (widget.ctrl.overview['customer_ack_status'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slots.isEmpty)
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
        JourneySection(
          title: tr('ลิงก์ให้ลูกค้าตอบรับ / เซ็น'),
          icon: NxI.link,
          trailing: Chip(visualDensity: VisualDensity.compact, label: Text(_ackLabel(ack))),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(key: const ValueKey('job-public-link'), onPressed: _customerLink, icon: const Icon(NxI.link, size: 18), label: Text(tr('สร้างลิงก์ลูกค้า'))),
          ),
        ),
      ],
    );
  }

  String _ackLabel(String s) => switch (s) {
        'signed' => tr('ลูกค้าเซ็นแล้ว'),
        'accepted' => tr('ลูกค้าตอบรับแล้ว'),
        'link_sent' || 'sent' => tr('ส่งลิงก์แล้ว'),
        _ => tr('ยังไม่มีลิงก์'),
      };
}

/// Link + copy / share for a customer page.
Future<void> showPublicLinkSheet(BuildContext context, String url, {String? pdf}) {
  return showAppBottomSheet<void>(
    context: context,
    title: tr('ลิงก์สำหรับลูกค้า'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(url, key: const ValueKey('public-link-url')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(context);
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('คัดลอกลิงก์แล้ว'))));
              },
              icon: const Icon(NxI.copySimple, size: 18),
              label: Text(tr('คัดลอกลิงก์')),
            ),
          ),
        ]),
        if (pdf != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pdf));
              Navigator.pop(context);
            },
            icon: const Icon(NxI.filePdf, size: 18),
            label: Text(tr('คัดลอกลิงก์ PDF')),
          ),
        ],
      ],
    ),
  );
}

/// "สร้างกิจกรรม": from a template (server settings) or a quick single visit.
Future<bool> showJobActivityGenSheet(BuildContext context, {required String jobId}) async {
  final api = context.read<AppConfig>().apiClient;
  List<Map<String, dynamic>> templates = const [];
  try {
    templates = await api.getJobActivityTemplates();
  } catch (_) {}
  if (!context.mounted) return false;
  final subject = TextEditingController(text: tr('เข้าหน้างาน'));
  var offset = 0;
  var time = const TimeOfDay(hour: 9, minute: 0);
  var busy = false;
  final created = await showAppBottomSheet<bool>(
    context: context,
    title: tr('สร้างกิจกรรมของงาน'),
    child: StatefulBuilder(builder: (ctx, setS) {
      final theme = Theme.of(ctx);
      Future<void> run(Map<String, dynamic> body) async {
        setS(() => busy = true);
        try {
          final r = await api.generateJobActivities(jobId, body);
          HapticFeedback.mediumImpact();
          if (ctx.mounted) {
            ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(tr('สร้างกิจกรรม ${r['created'] ?? (r['activity_ids'] as List?)?.length ?? ''} รายการแล้ว'))));
            Navigator.pop(ctx, true);
          }
        } catch (e) {
          setS(() => busy = false);
          if (ctx.mounted) ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(tr(journeyErrorText(e)))));
        }
      }

      String two(int n) => n.toString().padLeft(2, '0');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (templates.isNotEmpty) ...[
            Text(tr('จากเทมเพลต'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final t in templates)
              ListTile(
                key: ValueKey('act-template-${t['id']}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(NxI.listChecks),
                title: Text((t['name'] ?? '').toString()),
                subtitle: Text(tr('${(t['items'] as List?)?.length ?? 0} กิจกรรม')),
                trailing: const Icon(NxI.caretRight, size: 16),
                onTap: busy ? null : () => run({'template_id': t['id']}),
              ),
            const Divider(height: 24),
          ],
          Text(tr('สร้างด่วน 1 กิจกรรม'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          TextField(key: const ValueKey('quick-act-subject'), controller: subject, decoration: InputDecoration(labelText: tr('หัวข้อ'))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in const [0, 1, 2, 7])
                ChoiceChip(
                  label: Text(tr(d == 0 ? 'วันนัด' : '+$d วัน')),
                  selected: offset == d,
                  onSelected: (_) => setS(() => offset = d),
                ),
              ActionChip(
                avatar: const Icon(NxI.clock, size: 16),
                label: Text('${two(time.hour)}:${two(time.minute)}'),
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: time);
                  if (t != null) setS(() => time = t);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton(
              key: const ValueKey('quick-act-create'),
              onPressed: busy || subject.text.trim().isEmpty
                  ? null
                  : () => run({
                        'items': [
                          {
                            'key': 'k1',
                            'subject': subject.text.trim(),
                            'activitytype': 'Visit',
                            'offset_days': offset,
                            'start_time': '${two(time.hour)}:${two(time.minute)}',
                            'duration_min': 60,
                            'owner_rule': 'job_owner',
                          },
                        ],
                      }),
              child: Text(tr('สร้างกิจกรรม')),
            ),
          ),
        ],
      );
    }),
  );
  return created == true;
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
      return showJobActivityGenSheet(context, jobId: id);
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
