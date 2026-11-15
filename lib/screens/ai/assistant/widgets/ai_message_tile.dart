import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../core/ai_assistant.dart';
import '../../../../core/i18n.dart';
import '../../../../core/thai_time.dart';
import '../../../../widgets/isaac_sticker.dart';
import '../../../../widgets/nx_attachments.dart';
import '../../../../widgets/nx_icons.dart';
import '../../../../widgets/nx_markdown.dart';
import 'ai_style.dart';

/// The user's message: a soft bubble on the right. Long-press for actions.
class AiUserBubble extends StatelessWidget {
  const AiUserBubble({super.key, required this.message, required this.onLongPress});
  final AiMessage message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width.clamp(0, AiStyle.maxContentWidth) * 0.82),
        child: GestureDetector(
          key: ValueKey('ai-user-${message.id ?? message.hashCode}'),
          behavior: HitTestBehavior.opaque,
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4, left: 48),
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? cs.primary.withValues(alpha: 0.22) : const Color(0xFFEDEDFB),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: NxAttachmentStrip(items: message.attachments, thumb: 72),
                  ),
                if (message.content.trim().isNotEmpty) Text(message.content, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Isaac's reply: full width, no bubble (like ChatGPT / Claude).
///
/// While streaming only this tile rebuilds — it listens to [streamTick] —
/// so long answers stay smooth.
class AiAssistantTile extends StatelessWidget {
  const AiAssistantTile({
    super.key,
    required this.message,
    required this.isLast,
    required this.sending,
    required this.mood,
    required this.streamTick,
    required this.statusLabel,
    required this.routeSteps,
    required this.sendStartedAt,
    required this.onOpenLink,
    required this.onLongPress,
    required this.extras,
    this.actions,
  });

  final AiMessage message;
  final bool isLast;
  final bool sending;
  final String mood;
  final ValueListenable<int> streamTick;
  final String statusLabel;
  final List<Map<String, dynamic>> routeSteps;
  final DateTime? sendStartedAt;
  final ValueChanged<String> onOpenLink;
  final VoidCallback onLongPress;

  /// Proposal / ask-user / downloads / citations cards.
  final List<Widget> extras;

  /// Action row (copy · regenerate · share), shown under the latest reply.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final waiting = message.streaming && message.content.isEmpty;
    return Padding(
      key: ValueKey('ai-reply-${message.id ?? message.hashCode}'),
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IsaacSticker(state: isLast ? mood : 'happy', size: 30, animate: isLast),
              const SizedBox(width: 8),
              Text(tr('ไอแซค'), style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              AiModelBadge(provider: message.provider, model: message.model),
            ],
          ),
          if (message.toolSteps.isNotEmpty) AiToolSteps(steps: message.toolSteps, live: message.streaming),
          const SizedBox(height: 6),
          if (waiting)
            AiTypingIndicator(label: statusLabel, startedAt: sendStartedAt, steps: routeSteps)
          else
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: message.streaming ? null : onLongPress,
              child: message.streaming
                  ? ValueListenableBuilder<int>(
                      valueListenable: streamTick,
                      builder: (_, _, _) => NxMarkdown(data: message.content, streaming: true, onOpenLink: onOpenLink),
                    )
                  : NxMarkdown(data: message.content, onOpenLink: onOpenLink),
            ),
          ...extras,
          ?actions,
        ],
      ),
    );
  }
}

/// Small pill naming the model family; tap shows the exact model.
class AiModelBadge extends StatelessWidget {
  const AiModelBadge({super.key, this.provider, this.model});
  final String? provider;
  final String? model;

  static String family(String? provider, String? model) {
    final p = (provider ?? '').toLowerCase();
    final m = (model ?? '').toLowerCase();
    bool has(String x) => p.contains(x) || m.contains(x);
    if (has('gemini')) return 'Gemini';
    if (has('claude') || has('opus') || has('sonnet') || has('haiku')) return 'Claude';
    if (has('gpt') || p == 'openai') return 'ChatGPT';
    if (has('deepseek')) return 'DeepSeek';
    if (has('kimi')) return 'Kimi';
    if (has('qwen')) return 'Qwen';
    if (has('gemma')) return 'Gemma';
    if (has('ollama') || has('llama')) return 'Ollama';
    return 'Auto';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final full = aiModelBadge(provider, model);
    return Tooltip(
      key: const ValueKey('ai-model-badge'),
      message: full,
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AiStyle.tint(context), borderRadius: BorderRadius.circular(999)),
        child: Text(
          family(provider, model),
          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// "ค้นหาข้อมูล ✓ · สร้าง Lead…" — collapsed; tap to see every step.
class AiToolSteps extends StatefulWidget {
  const AiToolSteps({super.key, required this.steps, required this.live});
  final List<Map<String, dynamic>> steps;
  final bool live;

  @override
  State<AiToolSteps> createState() => _AiToolStepsState();
}

class _AiToolStepsState extends State<AiToolSteps> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final steps = widget.steps;
    final last = steps.last;
    final summary = steps.length == 1
        ? '${tr('${last['label']}')}${last['done'] == true ? ' ✓' : '…'}'
        : '${tr('${last['label']}')}${last['done'] == true ? ' ✓' : '…'}  ·  ${tr('${steps.length} ขั้นตอน')}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        key: const ValueKey('ai-tool-steps'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: AnimatedSize(
            duration: AiStyle.of(context),
            curve: AiStyle.curve,
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_open ? NxI.caretDown : NxI.caretRight, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Icon(NxI.wrench, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                if (_open)
                  for (final s in steps)
                    Padding(
                      padding: const EdgeInsets.only(left: 22, top: 6),
                      child: Row(
                        children: [
                          s['done'] == true
                              ? Icon(NxI.check, size: 14, color: cs.primary)
                              : SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: cs.primary)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(tr('${s['label']}'), style: theme.textTheme.labelMedium)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bouncing dots + what Isaac is doing + seconds (after 3s).
/// Owns its own clock, so the screen does not rebuild every second.
class AiTypingIndicator extends StatefulWidget {
  const AiTypingIndicator({super.key, required this.label, this.startedAt, this.steps = const []});
  final String label;
  final DateTime? startedAt;
  final List<Map<String, dynamic>> steps;

  @override
  State<AiTypingIndicator> createState() => _AiTypingIndicatorState();
}

class _AiTypingIndicatorState extends State<AiTypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AiStyle.of(context) == Duration.zero) {
      _a.stop();
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final secs = widget.startedAt == null ? 0 : DateTime.now().difference(widget.startedAt!).inSeconds;
    return Column(
      key: const ValueKey('ai-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedBuilder(
              animation: _a,
              builder: (_, _) => Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      width: 7,
                      height: 7,
                      transform: Matrix4.translationValues(0, -3 * _bounce((_a.value - i * 0.18) % 1.0), 0),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.45 + 0.5 * _bounce((_a.value - i * 0.18) % 1.0)),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('${tr(widget.label)}${secs >= 3 ? '  ${secs}s' : ''}', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ],
        ),
        if (widget.steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              tr('${widget.steps.last['label'] ?? widget.steps.last['id'] ?? ''}'),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
            ),
          ),
      ],
    );
  }

  static double _bounce(double t) => t < 0.5 ? (t * 2) : (2 - t * 2);
}

/// Row of small actions under the latest reply.
class AiReplyActions extends StatelessWidget {
  const AiReplyActions({super.key, required this.onCopy, required this.onShare, this.onRegenerate, this.onMore});
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onRegenerate;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          _ActionIcon(key: const ValueKey('ai-copy'), icon: NxI.copySimple, label: 'คัดลอก', onTap: onCopy),
          if (onRegenerate != null) _ActionIcon(key: const ValueKey('ai-regenerate'), icon: NxI.arrowsClockwise, label: 'สร้างใหม่', onTap: onRegenerate),
          _ActionIcon(icon: NxI.shareNetwork, label: 'แชร์', onTap: onShare),
          if (onMore != null) _ActionIcon(icon: NxI.dotsThree, label: 'เพิ่มเติม', onTap: onMore),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({super.key, required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tr(label),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: cs.onSurfaceVariant),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}

/// "วันนี้" / "เมื่อวาน" / date line between days.
class AiDaySeparator extends StatelessWidget {
  const AiDaySeparator({super.key, required this.day});
  final DateTime day;

  static String label(DateTime day, {DateTime? now}) {
    final n = now ?? thaiNow();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(day.year, day.month, day.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'วันนี้';
    if (diff == 1) return 'เมื่อวาน';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(tr(label(day)), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(child: Divider(color: cs.outlineVariant.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
