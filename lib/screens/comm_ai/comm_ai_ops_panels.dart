import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import 'comm_ai_errors.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_widgets.dart';

/// Quota kinds of `GET /api/comm-ai/usage` → (label, unit).
const kCommAiQuotaKinds = <String, (String, String)>{
  'stt_minutes': ('นาทีถอดเสียง', 'นาที'),
  'summaries': ('การสรุปของไอแซค', 'ครั้ง'),
  'translations': ('การแปลคำบรรยาย', 'ครั้ง'),
};

const _warnColor = Color(0xFFD97706);
const _errorColor = Color(0xFFE11D48);
const _okColor = Color(0xFF059669);

List<Map<String, dynamic>> _items(Map<String, dynamic>? usage) =>
    [for (final x in (usage?['items'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

String _amount(dynamic v, String kind) {
  final n = v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  if (kind == 'stt_minutes' && n != n.roundToDouble()) return n.toStringAsFixed(1);
  return '${n.round()}';
}

/// Card in the settings style: tinted icon, title, optional description.
class CommAiPanel extends StatelessWidget {
  const CommAiPanel({super.key, required this.icon, required this.title, this.desc, required this.children, this.color = kIsaacIndigo});
  final IconData icon;
  final String title;
  final String? desc;
  final List<Widget> children;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxSurfaceCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (desc != null) Text(tr(desc!), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

/// "การใช้งานเดือนนี้": used vs the Package limit per kind (bar turns amber at 80 %, red when used up).
class CommAiUsagePanel extends StatelessWidget {
  const CommAiUsagePanel({super.key, required this.usage});
  final Map<String, dynamic> usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final month = '${usage['month'] ?? ''}';
    return CommAiPanel(
      key: const ValueKey('comm-ai-usage'),
      icon: NxI.chartBar,
      title: 'การใช้งานเดือนนี้',
      desc: '${month.isEmpty ? '' : '$month · '}${tr('ตามโควตาของแพ็กเกจ (ไม่ตั้ง = ไม่จำกัด)')}',
      children: [
        for (final it in _items(usage)) _row(context, it, hint),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> it, Color hint) {
    final kind = '${it['kind']}';
    final (label, unit) = kCommAiQuotaKinds[kind] ?? (kind, '');
    final unlimited = it['unlimited'] == true || it['limit'] == null;
    final exceeded = it['exceeded'] == true;
    final warn = it['warn'] == true;
    final color = exceeded ? _errorColor : warn ? _warnColor : kIsaacIndigo;
    final pct = ((it['percent'] as num?)?.toDouble() ?? 0).clamp(0, 100) / 100;
    final used = _amount(it['used'], kind);
    return Padding(
      key: ValueKey('comm-ai-usage-$kind'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          Text(
            unlimited ? '$used · ${tr('ไม่จำกัด')}' : '$used / ${_amount(it['limit'], kind)} ${tr(unit)}',
            style: TextStyle(fontSize: 13, fontWeight: exceeded || warn ? FontWeight.w700 : FontWeight.w500, color: exceeded || warn ? color : hint, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ]),
        if (!unlimited) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct.toDouble(), minHeight: 7, color: color, backgroundColor: color.withValues(alpha: 0.12)),
          ),
        ],
        if (exceeded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('ครบโควตาแล้ว — ไอแซคหยุดส่วนนี้จนถึงเดือนถัดไป'), style: const TextStyle(fontSize: 12, color: _errorColor)),
          ),
      ]),
    );
  }
}

/// Compact notice when any quota is at 80 % or more (nothing otherwise).
class CommAiQuotaNotice extends StatelessWidget {
  const CommAiQuotaNotice({super.key, required this.usage});
  final Map<String, dynamic>? usage;

  @override
  Widget build(BuildContext context) {
    final hot = [for (final it in _items(usage)) if (it['warn'] == true || it['exceeded'] == true) it];
    if (hot.isEmpty) return const SizedBox.shrink();
    final exceeded = hot.any((it) => it['exceeded'] == true);
    final color = exceeded ? _errorColor : _warnColor;
    final parts = [
      for (final it in hot)
        '${tr(kCommAiQuotaKinds['${it['kind']}']?.$1 ?? '${it['kind']}')} ${_amount(it['used'], '${it['kind']}')}/${_amount(it['limit'], '${it['kind']}')} (${(it['percent'] as num?)?.round() ?? 100}%)',
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('comm-ai-quota-notice'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(NxI.warning, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${tr(exceeded ? 'ใช้โควตาไอแซคครบแล้ว' : 'ใช้โควตาไอแซคไปเกิน 80% แล้ว')}  ', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            TextSpan(text: parts.join(' · '), style: const TextStyle(fontSize: 12.5)),
          ])),
        ),
      ]),
    );
  }
}

/// Admins: "สถานะ AI" — provider keys, transcription and summaries (levels error / warning, since when).
class CommAiHealthPanel extends StatelessWidget {
  const CommAiHealthPanel({super.key, required this.list});
  final List<Map<String, dynamic>> list;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget box(Color color, IconData icon, Widget child, {Key? key}) => Container(
          key: key,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withValues(alpha: dark ? 0.18 : 0.08), borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: child),
          ]),
        );
    return CommAiPanel(
      key: const ValueKey('comm-ai-health'),
      icon: NxI.heartbeat,
      title: 'สถานะ AI',
      desc: 'ตรวจ key ของผู้ให้บริการ การถอดเสียง และการสรุป — ผู้ดูแลได้รับแจ้งเตือนเมื่อมีปัญหา',
      children: [
        if (list.isEmpty)
          box(_okColor, NxI.checkCircle, Text(tr('ทุกอย่างปกติ'), style: const TextStyle(color: _okColor, fontWeight: FontWeight.w600)), key: const ValueKey('comm-ai-health-ok'))
        else
          for (final p in list)
            box(
              p['level'] == 'error' ? _errorColor : _warnColor,
              p['level'] == 'error' ? NxI.xCircle : NxI.warning,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(L10n.isEn ? '${p['message_en'] ?? p['message'] ?? p['code']}' : '${p['message'] ?? p['code']}', style: const TextStyle(fontSize: 13.5, height: 1.35)),
                if (commAiWhen(p['since']).isNotEmpty)
                  Text('${tr('เริ่มเมื่อ')} ${commAiWhen(p['since'])}', style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
              ]),
              key: ValueKey('comm-ai-health-${p['code']}'),
            ),
      ],
    );
  }
}

/// "ส่วนตัว": my daily follow-up digest (notification, optionally e-mail). Saved right away.
class CommAiPersonalPanel extends StatefulWidget {
  const CommAiPersonalPanel({super.key, required this.prefs});
  final Map<String, dynamic> prefs;

  @override
  State<CommAiPersonalPanel> createState() => _CommAiPersonalPanelState();
}

class _CommAiPersonalPanelState extends State<CommAiPersonalPanel> {
  late Map<String, dynamic> _prefs = {'digest': true, 'digest_email': false, ...widget.prefs};
  String? _busy;

  Future<void> _save(String key, bool value) async {
    final prev = Map<String, dynamic>.from(_prefs);
    setState(() {
      _busy = key;
      _prefs = {..._prefs, key: value};
    });
    try {
      final out = await context.read<AppConfig>().apiClient.saveCommAiPrefs({key: value});
      if (mounted && out.isNotEmpty) setState(() => _prefs = {..._prefs, ...out});
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(commAiErrorText(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digest = _prefs['digest'] != false;
    return CommAiPanel(
      key: const ValueKey('comm-ai-personal'),
      icon: NxI.bellRinging,
      title: 'ส่วนตัว',
      desc: 'ตั้งค่าเฉพาะของคุณ ไม่กระทบคนอื่น',
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('comm-ai-pref-digest'),
          contentPadding: EdgeInsets.zero,
          value: digest,
          onChanged: _busy != null ? null : (v) => _save('digest', v),
          title: Text(tr('สรุปงานติดตามทุกเช้า 08:00'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          subtitle: Text(tr('งานจากบทสนทนาที่ยังไม่ได้ติ๊ก ที่มอบให้คุณหรือคุณสร้าง — แจ้งเตือนวันละครั้ง'), style: const TextStyle(fontSize: 12.5)),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('comm-ai-pref-digest-email'),
          contentPadding: EdgeInsets.zero,
          value: _prefs['digest_email'] == true,
          onChanged: _busy != null || !digest ? null : (v) => _save('digest_email', v),
          title: Text(tr('ส่งทางอีเมลด้วย'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
          subtitle: Text(tr('ส่งเมื่อธุรกิจตั้งค่าการส่งอีเมลไว้แล้ว'), style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}
