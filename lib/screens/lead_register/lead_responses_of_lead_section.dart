import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import 'lead_form_fill_screen.dart';
import 'lead_response_detail_screen.dart';

/// "Form responses" on a Lead: every answer this Lead gave, across all forms,
/// newest first, with key answers and where its follow-up flow stands.
class LeadResponsesOfLeadSection extends StatefulWidget {
  const LeadResponsesOfLeadSection({super.key, required this.leadId});
  final int leadId;

  @override
  State<LeadResponsesOfLeadSection> createState() => _LeadResponsesOfLeadSectionState();
}

class _LeadResponsesOfLeadSectionState extends State<LeadResponsesOfLeadSection> {
  List<Map<String, dynamic>>? _list;
  bool _failed = false;
  final Set<int> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LeadResponsesOfLeadSection old) {
    super.didUpdateWidget(old);
    if (old.leadId != widget.leadId) _load();
  }

  Future<void> _load() async {
    final cfg = context.read<AppConfig>();
    if (!cfg.isLoggedIn || !MenuAccess.allow(cfg.session, MenuAccess.leadRegister)) {
      setState(() => _failed = true);
      return;
    }
    try {
      final list = await context.read<AppConfig>().apiClient.getLeadRegisterResponsesOfLead(widget.leadId);
      if (mounted) setState(() => _list = list);
    } catch (_) {
      // No Lead Register access (menu off / 403): hide the section.
      if (mounted) setState(() => _failed = true);
    }
  }

  static String _date(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static (String, Color) _flow(String? s) => switch (s) {
        'done' => ('ครบทุกขั้น', const Color(0xFF10B981)),
        'partial' => ('บางขั้นไม่สำเร็จ', const Color(0xFFF59E0B)),
        'failed' => ('ไม่สำเร็จ', const Color(0xFFEF4444)),
        'running' || 'pending' => ('กำลังทำงาน', const Color(0xFF6366F1)),
        _ => ('-', const Color(0xFF94A3B8)),
      };

  static String _channel(String? c) => switch (c) {
        'kiosk' => tr('คีออสก์'),
        'mobile' => tr('แอปมือถือ'),
        'qr' => 'QR',
        'staff' => tr('พนักงานกรอก'),
        _ => tr('เว็บ'),
      };

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (_failed || list == null || list.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('${tr('คำตอบแบบฟอร์ม')} (${list.length})', style: theme.textTheme.titleMedium)),
        ]),
        const SizedBox(height: 8),
        for (final r in list) _item(context, r),
      ]),
    );
  }

  Widget _item(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final id = (r['id'] as num).toInt();
    final open = _open.contains(id);
    final items = (r['items'] is List ? r['items'] as List : const []).whereType<Map>().toList();
    final (flowLabel, flowColor) = _flow(r['flow_status']?.toString());
    final shown = open ? items : items.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NxSurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(NxI.clipboardText, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(r['form_name']?.toString() ?? '', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: tr('ดูรายละเอียด'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(NxI.arrowRight, size: 18),
              onPressed: () => nxPush<void>(context, LeadResponseDetailScreen(responseId: id)),
            ),
          ]),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_date(r['created_at']), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            Text('· ${_channel(r['channel']?.toString())}', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: flowColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(tr(flowLabel), style: theme.textTheme.labelSmall?.copyWith(color: flowColor, fontWeight: FontWeight.w600)),
            ),
            if (r['deal_no'] != null) Text('${r['deal_no']} · ${r['deal_stage'] ?? ''}', style: theme.textTheme.bodySmall),
            if (r['activity_due'] != null) Text('${tr('ติดตาม')} ${r['activity_due']} (${tr(r['activity_status']?.toString() ?? '')})', style: theme.textTheme.bodySmall),
          ]),
          if (shown.isNotEmpty) const SizedBox(height: 8),
          for (final it in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 6),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${it['label']}: ', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                TextSpan(text: '${it['text']}', style: theme.textTheme.bodySmall),
              ])),
            ),
          Row(children: [
            if (items.length > 3)
              TextButton(
                onPressed: () => setState(() => open ? _open.remove(id) : _open.add(id)),
                child: Text(open ? tr('ย่อ') : '${tr('ดูคำตอบทั้งหมด')} (${items.length})'),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await nxPush<void>(context, LeadFormFillScreen(formId: (r['form_id'] as num).toInt(), leadId: widget.leadId));
                if (mounted) _load();
              },
              icon: const Icon(NxI.plus, size: 16),
              label: Text(tr('ตอบอีกครั้ง')),
            ),
          ]),
        ]),
      ),
    );
  }
}
