import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_config.dart';
import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../widgets/nx_attachments.dart';
import '../../../widgets/nx_icons.dart';

/// Field labels in proposal previews (web `AiToolProposalCard.jsx`).
const _kFieldLabels = {
  'lead_firstname': 'ชื่อ', 'lead_lastname': 'นามสกุล', 'lead_name': 'ชื่อ Lead', 'company_name': 'บริษัท',
  'mobile_1st': 'มือถือ', 'email_1st': 'อีเมล', 'lead_status': 'สถานะ Lead', 'contact_firstname': 'ชื่อ',
  'contact_lastname': 'นามสกุล', 'contact_name': 'ชื่อ Contact', 'account_name': 'ชื่อบัญชี', 'case_name': 'ชื่อเคส',
  'case_status': 'สถานะเคส', 'customer_name': 'ลูกค้า', 'subject': 'หัวข้อ', 'description': 'รายละเอียด',
  'activitytype': 'ประเภทกิจกรรม', 'date_start': 'เริ่ม', 'date_end': 'สิ้นสุด', 'priority': 'ความสำคัญ',
  'status': 'สถานะ', 'title': 'หัวข้อ', 'type': 'ประเภท', 'level': 'ชั้น', 'job_name': 'ชื่องาน',
};

const _kToolLabels = {
  'create_lead': 'สร้าง Lead', 'create_contact': 'สร้าง Contact', 'create_account': 'สร้าง Account',
  'create_activity': 'สร้างนัดในปฏิทิน', 'create_case': 'สร้าง Case', 'create_quotation': 'สร้างใบเสนอราคา',
  'create_call_log': 'บันทึกการโทร', 'create_product': 'สร้างสินค้า', 'update_status': 'เปลี่ยนสถานะ',
  'update_entity': 'อัปเดตรายการ', 'add_case_comment': 'เพิ่มคอมเมนต์เคส', 'convert_lead': 'แปลง Lead',
  'create_workspace_item': 'สร้างงาน Workspace', 'create_workspace_epic': 'สร้าง Epic Workspace',
  'update_workspace_item': 'อัปเดตงาน Workspace', 'plan_bulk_work': 'วางแผนงานจำนวนมาก',
  'execute_bulk_plan': 'รันงานจำนวนมาก', 'analyze_work_document': 'วิเคราะห์เอกสารเป็นงาน',
  'plan_workspace_tree': 'วางแผนต้นไม้งาน Workspace', 'execute_workspace_tree_plan': 'สร้างต้นไม้งาน Workspace',
  'create_analytics_dashboard': 'สร้างแดชบอร์ด Analytics', 'share_analytics_report': 'แชร์รายงาน Analytics',
};

String _fieldLabel(String k) => _kFieldLabels[k] ?? k;

/// "ยืนยันการทำงานบน CRM": what the AI wants to write, then ยืนยัน / ยกเลิก.
class AiProposalCard extends StatelessWidget {
  const AiProposalCard({
    super.key,
    required this.proposal,
    required this.state,
    required this.onConfirm,
    required this.onCancel,
    this.boards,
    this.boardId,
    this.onBoard,
  });
  final Map<String, dynamic> proposal;

  /// Workspace tree proposals: boards the user can write to, and the pick.
  final List<Map<String, dynamic>>? boards;
  final String? boardId;
  final ValueChanged<String?>? onBoard;

  /// null | working | done | cancelled
  final String? state;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tool = '${proposal['tool'] ?? ''}';
    final preview = proposal['preview'] is Map ? Map<String, dynamic>.from(proposal['preview'] as Map) : const <String, dynamic>{};
    final fields = preview['fields'] is Map ? Map<String, dynamic>.from(preview['fields'] as Map) : const <String, dynamic>{};
    final sample = preview['sample'] is List ? [for (final r in preview['sample'] as List) if (r is Map) Map<String, dynamic>.from(r)] : const <Map<String, dynamic>>[];
    final total = num.tryParse('${preview['total'] ?? ''}')?.toInt();
    // Lead / Contact / Account *_datetime are real UTC instants (shown +7); others wall clock.
    final module = '${preview['module'] ?? ''}';
    final cols = sample.isEmpty ? const <String>[] : sample.first.keys.where((k) => !k.startsWith('_')).take(4).toList();
    final done = state == 'done', cancelled = state == 'cancelled', working = state == 'working';
    return Container(
      key: ValueKey('ai-proposal-${proposal['proposalId']}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(NxI.shieldCheck, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('ยืนยันการทำงานบน CRM'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 4),
        Text(tr(_kToolLabels[tool] ?? tool), style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
        if ('${preview['comment'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${preview['comment']}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
        if (fields.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6))),
            child: Column(children: [
              for (final (i, e) in fields.entries.where((e) => e.value != null && '${e.value}'.isNotEmpty).indexed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 110, child: Text(tr(_fieldLabel(e.key)), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                    Expanded(child: Text(_fmt(e.key, e.value, module), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                  ]),
                ),
            ]),
          ),
        ],
        if (sample.isNotEmpty) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 44,
              columnSpacing: 18,
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6))),
              columns: [for (final c in cols) DataColumn(label: Text(tr(_fieldLabel(c)), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)))],
              rows: [
                for (final r in sample.take(5))
                  DataRow(cells: [for (final c in cols) DataCell(Text(_fmt(c, r[c], module), style: theme.textTheme.bodySmall))]),
              ],
            ),
          ),
          if (total != null && total > sample.take(5).length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('แสดง ${sample.take(5).length} จาก $total'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ],
        if (boards != null && !done && !cancelled) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: const ValueKey('ai-proposal-board'),
            initialValue: boards!.any((b) => '${b['id']}' == boardId) ? boardId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('บอร์ดที่จะสร้างงาน'), isDense: true),
            hint: Text(tr('— เลือกบอร์ด —')),
            items: [
              for (final b in boards!)
                DropdownMenuItem(value: '${b['id']}', child: Text('${b['name'] ?? b['title'] ?? b['id']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: working ? null : onBoard,
          ),
        ],
        const SizedBox(height: 10),
        if (done)
          Row(children: [
            const Icon(NxI.checkCircle, size: 18, color: Color(0xFF16A34A)),
            const SizedBox(width: 6),
            Text(tr('ทำรายการแล้ว'), style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
          ])
        else if (cancelled)
          Text(tr('ยกเลิกแล้ว'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
        else
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('ai-proposal-confirm'),
                onPressed: working ? null : onConfirm,
                child: working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('ยืนยัน')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(key: const ValueKey('ai-proposal-cancel'), onPressed: working ? null : onCancel, child: Text(tr('ยกเลิก')))),
          ]),
      ]),
    );
  }

  static String _fmt(String key, dynamic v, [String? module]) {
    if (v == null) return '—';
    if (key.contains('date') && '$v'.length >= 10) {
      final d = parseWall(v);
      if (d != null) return formatThaiField('$v', key, module: module == null || module.isEmpty ? null : module);
    }
    return '$v';
  }
}

/// "ถามกลับ": options the user taps to answer (web `AiAskUserCard`).
class AiAskUserCard extends StatelessWidget {
  const AiAskUserCard({super.key, required this.questions, required this.onPick, this.enabled = true});
  final List<Map<String, dynamic>> questions;
  final ValueChanged<String> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final q in questions)
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(NxI.question, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('${q['prompt'] ?? ''}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in (q['options'] is List ? q['options'] as List : const []))
                if (o is Map)
                  ActionChip(
                    key: ValueKey('ai-ask-${o['label']}'),
                    label: Text('${o['label'] ?? ''}'),
                    onPressed: enabled ? () => onPick('${o['send_prompt'] ?? o['label'] ?? ''}') : null,
                  ),
            ]),
          ]),
        ),
    ]);
  }
}

/// Downloadable files produced by tools (web `AiDownloadChip`).
class AiDownloadChips extends StatelessWidget {
  const AiDownloadChips({super.key, required this.downloads, this.onRegenerate});
  final List<Map<String, dynamic>> downloads;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final api = context.read<AppConfig>().apiClient;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final d in downloads)
        Builder(builder: (context) {
          final exp = parseThai('${d['expiresAt'] ?? ''}');
          final expired = exp != null && exp.isBefore(thaiNow());
          final name = '${d['fileName'] ?? 'download'}';
          final st = nxFileStyle({'name': name});
          return Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('ai-download-$name'),
              borderRadius: BorderRadius.circular(14),
              onTap: expired ? onRegenerate : () => openNxFile(api.absoluteUrl('${d['url']}')),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(NxI.downloadSimple, size: 18, color: expired ? cs.onSurfaceVariant : st.color),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(expired ? tr('ลิงก์หมดอายุ — แตะเพื่อสร้างใหม่') : '${d['format'] ?? st.label}', style: theme.textTheme.labelSmall?.copyWith(color: expired ? cs.error : cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        }),
    ]);
  }
}

/// Source chips under a grounded answer.
class AiCitationChips extends StatelessWidget {
  const AiCitationChips({super.key, required this.citations});
  final List<Map<String, dynamic>> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final (i, c) in citations.indexed)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
          child: Text(
            '[${i + 1}] ${c['title'] ?? c['source_id'] ?? ''}${'${c['loc'] ?? ''}'.isEmpty ? '' : ' · ${c['loc']}'}',
            style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
          ),
        ),
    ]);
  }
}
