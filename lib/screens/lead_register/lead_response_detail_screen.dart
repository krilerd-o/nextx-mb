import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_icons.dart';
import 'lead_form_detail_screen.dart' show leadFlowStatusColor, leadFlowStatusLabel;

const _stepInfo = {
  'lead': ('สร้าง Lead อัตโนมัติ', NxI.userPlus, Color(0xFF6366F1)),
  'email': ('ส่งอีเมล Salesheet', NxI.envelope, Color(0xFF0EA5E9)),
  'deal': ('สร้าง Deal อัตโนมัติ', NxI.handshake, Color(0xFFF59E0B)),
  'activity': ('สร้าง Activity ติดตาม', NxI.calendarCheck, Color(0xFF10B981)),
};

const _reasons = {
  'disabled': 'ปิดไว้ใน Flow',
  'no_email': 'ไม่มีอีเมลในคำตอบ',
  'smtp_not_configured': 'ยังไม่ได้ตั้งค่าการส่งอีเมล',
  'emails3_not_configured': 'ยังไม่ได้ตั้งค่าการส่งอีเมล',
  'condition': 'ไม่ตรงเงื่อนไข',
  'no_lead': 'ไม่มี Lead ให้ผูก',
};

/// One response: flow tracking (Lead → Email → Deal → Activity, retry) and answers.
class LeadResponseDetailScreen extends StatefulWidget {
  const LeadResponseDetailScreen({super.key, required this.responseId});
  final int responseId;
  @override
  State<LeadResponseDetailScreen> createState() => _LeadResponseDetailScreenState();
}

class _LeadResponseDetailScreenState extends State<LeadResponseDetailScreen> {
  Map<String, dynamic>? _r;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<AppConfig>().apiClient.getLeadFormResponse(widget.responseId);
    if (!mounted) return;
    setState(() => _r = r);
    final st = r['flow_status']?.toString();
    if (st == 'pending' || st == 'running') {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _load();
      });
    }
  }

  Future<void> _rerun(List<String>? steps) async {
    setState(() => _busy = steps?.join(',') ?? 'all');
    try {
      await context.read<AppConfig>().apiClient.rerunLeadFormFlow(widget.responseId, steps: steps, force: steps != null);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _fmt(dynamic d) {
    final dt = DateTime.tryParse('${d ?? ''}');
    if (dt == null) return '';
    final l = dt.toUtc().add(const Duration(hours: 7));
    return '${l.day}/${l.month}/${l.year} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(r == null ? '#${widget.responseId}' : (r['respondent_name'] ?? r['respondent_email'] ?? '#${widget.responseId}').toString())),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
                Row(children: [
                  Expanded(child: Text(tr('ติดตาม Flow'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  _chip(r['flow_status']?.toString() ?? 'pending'),
                ]),
                const SizedBox(height: 8),
                _timelineRow(icon: NxI.checkCircleFill, color: const Color(0xFF10B981), title: tr('ส่งแบบฟอร์ม'), lines: ['${_fmt(r['created_at'])} · ${r['channel'] ?? ''}${r['submitted_by_name'] != null && '${r['submitted_by_name']}'.trim().isNotEmpty ? ' · ${r['submitted_by_name']}' : ''}'], last: false),
                for (final (i, s) in ((r['flow']?['steps'] as List?) ?? const []).whereType<Map>().indexed) _step(Map<String, dynamic>.from(s), r, i == 3),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy != null ? null : () => _rerun(null),
                    icon: const Icon(NxI.arrowsClockwise, size: 16),
                    label: Text(tr('รันขั้นที่ค้าง/ล้มเหลว')),
                  ),
                ),
                const SizedBox(height: 20),
                Text(tr('คำตอบ'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
                  child: Column(children: [
                    for (final it in (r['items'] as List? ?? const []).whereType<Map>())
                      ListTile(
                        dense: true,
                        title: Text('${it['label']}', style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor)),
                        subtitle: Text(('${it['text'] ?? ''}').isEmpty ? '—' : '${it['text']}', style: theme.textTheme.bodyLarge),
                      ),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _chip(String st) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: leadFlowStatusColor(st).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(tr(leadFlowStatusLabel(st)), style: TextStyle(fontSize: 12, color: leadFlowStatusColor(st), fontWeight: FontWeight.w600)),
      );

  Widget _step(Map<String, dynamic> s, Map<String, dynamic> r, bool last) {
    final step = s['step']?.toString() ?? '';
    final info = _stepInfo[step];
    final st = s['status']?.toString() ?? 'pending';
    final det = s['detail_json'] is Map ? Map<String, dynamic>.from(s['detail_json'] as Map) : <String, dynamic>{};
    final lines = <String>[];
    VoidCallback? open;
    if (step == 'lead' && r['lead_id'] != null) {
      lines.add('${r['lead_no'] ?? 'Lead #${r['lead_id']}'}${det['attached'] == true ? ' · ${tr('ผูกกับ Lead เดิม (ตอบซ้ำ)')}' : ''}');
      open = () => context.push('/crm/lead/${r['lead_id']}');
    }
    if (step == 'email' && det['to'] != null) lines.add('→ ${det['to']}${det['attachments'] != null ? ' · ${det['attachments']} ${tr('ไฟล์แนบ')}' : ''}');
    if (step == 'deal' && r['deal_id'] != null) {
      lines.add('${r['deal_no'] ?? 'Deal #${r['deal_id']}'} · ${r['deal_stage'] ?? ''}');
      open = () => context.push('/crm/deal/${r['deal_id']}');
    }
    if (step == 'activity' && r['activity_due'] != null) lines.add('${tr('ครบกำหนด')} ${r['activity_due']} · ${r['activity_status'] ?? ''}');
    final reason = _reasons[det['reason']];
    if (reason != null) lines.add(tr(reason));
    if (s['error'] != null) lines.add('${s['error']}');
    final icon = switch (st) {
      'done' => NxI.checkCircleFill,
      'failed' => NxI.xCircle,
      'skipped' => NxI.prohibit,
      'running' => NxI.arrowsClockwise,
      _ => NxI.circle,
    };
    return _timelineRow(
      icon: icon,
      color: leadFlowStatusColor(st),
      leading: info == null ? null : Icon(info.$2, size: 14, color: info.$3),
      title: tr(info?.$1 ?? step),
      lines: lines,
      last: last,
      onTap: open,
      action: st == 'failed' || (st == 'skipped' && det['reason'] != 'disabled')
          ? TextButton(onPressed: _busy != null ? null : () => _rerun([step]), child: Text(tr('ลองใหม่')))
          : null,
    );
  }

  Widget _timelineRow({required IconData icon, required Color color, Widget? leading, required String title, required List<String> lines, required bool last, VoidCallback? onTap, Widget? action}) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Icon(icon, size: 22, color: color),
          if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: theme.colorScheme.outlineVariant)),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (leading != null) ...[leading, const SizedBox(width: 6)],
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ?action,
                ]),
                for (final l in lines) Text(l, style: theme.textTheme.bodySmall?.copyWith(color: onTap != null ? theme.colorScheme.primary : theme.hintColor)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
