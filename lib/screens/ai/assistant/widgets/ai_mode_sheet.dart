import 'package:flutter/material.dart';

import '../../../../core/ai_assistant.dart';
import '../../../../core/i18n.dart';
import '../../../../widgets/nx_icons.dart';
import '../ai_assistant_controller.dart';
import 'ai_style.dart';

/// Providers offered under "ขั้นสูง" (business policy may hide some).
const kAiProviders = [
  ('gemini', 'Gemini'),
  ('claude', 'Claude'),
  ('openai', 'ChatGPT'),
  ('deepseek', 'DeepSeek'),
  ('kimi', 'Kimi'),
  ('qwen', 'Qwen'),
  ('gemma', 'Gemma'),
  ('ollama', 'Ollama'),
];

/// "โหมดการตอบ": Auto · เร็ว · คิดลึก, the CRM-data switch, and — folded
/// away under "ขั้นสูง" — a manual model and the creativity level.
class AiModeSheet extends StatefulWidget {
  const AiModeSheet({super.key, required this.controller});
  final AiAssistantController controller;

  @override
  State<AiModeSheet> createState() => _AiModeSheetState();
}

class _AiModeSheetState extends State<AiModeSheet> {
  late bool _advanced = widget.controller.provider != 'auto';
  String? _open;
  final Map<String, List<String>> _models = {};
  final Set<String> _loading = {};

  AiAssistantController get c => widget.controller;

  Future<void> _load(String p) async {
    setState(() {
      _open = _open == p ? null : p;
      if (!_models.containsKey(p)) _loading.add(p);
    });
    if (_models.containsKey(p)) return;
    final fromPolicy = c.policy?.models(p);
    if (fromPolicy != null) {
      _models[p] = fromPolicy;
      setState(() => _loading.remove(p));
      return;
    }
    try {
      final r = await c.api.getAiModels(provider: p);
      final list = r['models'] is List ? r['models'] as List : const [];
      _models[p] = [
        for (final m in list)
          if (m is Map) '${m['id'] ?? m['name'] ?? m['model'] ?? ''}' else '$m',
      ].where((e) => e.isNotEmpty).toList();
    } catch (_) {
      _models[p] = const [];
    }
    if (mounted) setState(() => _loading.remove(p));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        key: const ValueKey('ai-mode-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(tr('โหมดการตอบ'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final m in kAiModes)
            _ModeOption(
              key: ValueKey('ai-mode-$m'),
              icon: AiStyle.modeIcon(m),
              title: m == 'auto' ? 'Auto (แนะนำ)' : aiModeLabel(m),
              subtitle: aiModeHint(m),
              selected: c.provider == 'auto' && c.autoMode == m,
              onTap: () {
                c.setMode(m);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            key: const ValueKey('ai-inject-context'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            secondary: Icon(NxI.database, color: cs.primary),
            title: Text(tr('ใช้ข้อมูล CRM'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('ให้ไอแซคอ่านข้อมูลธุรกิจของคุณประกอบคำตอบ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            value: c.injectContext,
            onChanged: c.setInjectContext,
          ),
          const Divider(height: 20),
          InkWell(
            key: const ValueKey('ai-mode-advanced'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _advanced = !_advanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Icon(_advanced ? NxI.caretDown : NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('ขั้นสูง (เลือกโมเดล / ความสร้างสรรค์)'), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  if (c.provider != 'auto')
                    Flexible(
                      child: Text(
                        aiModelBadge(c.provider, c.model),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_advanced) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: SegmentedButton<double>(
                key: const ValueKey('ai-temperature'),
                showSelectedIcon: false,
                segments: [for (final (v, label) in kAiTemperatures) ButtonSegment(value: v, label: Text(tr(label)))],
                selected: {kAiTemperatures.map((e) => e.$1).reduce((a, b) => (a - c.temperature).abs() <= (b - c.temperature).abs() ? a : b)},
                onSelectionChanged: (s) => c.setTemperature(s.first),
              ),
            ),
            for (final (id, label) in kAiProviders.where((x) => c.policy?.providerEnabled(x.$1) ?? true)) ...[
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(label),
                trailing: _loading.contains(id)
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_open == id ? NxI.caretUp : NxI.caretDown, size: 18),
                onTap: () => _load(id),
              ),
              if (_open == id)
                if ((_models[id] ?? const []).isEmpty && !_loading.contains(id))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(tr('ยังไม่ได้ตั้งค่าผู้ให้บริการนี้'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  )
                else
                  for (final m in _models[id] ?? const <String>[])
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 28, right: 4),
                      dense: true,
                      title: Text(m),
                      trailing: c.provider == id && c.model == m ? Icon(NxI.check, color: cs.primary) : null,
                      onTap: () {
                        c.setModel(id, m);
                        Navigator.pop(context);
                      },
                    ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AiStyle.tint(context) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: selected ? AiStyle.accent : null, color: selected ? null : AiStyle.tint(context)),
                  child: Icon(icon, size: 18, color: selected ? Colors.white : cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(tr(subtitle), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (selected) Icon(NxI.check, color: cs.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
