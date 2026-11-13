import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';

import '../../core/i18n.dart';
import '../../widgets/isaac_sticker.dart';

/// ISAAC AI look shared by the Communication AI screens (same mascot and copy as the NEXTX web).
const kIsaacIndigo = Color(0xFF4F46E5);
const kIsaacViolet = Color(0xFF7C3AED);
const kIsaacGradient = LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]);

/// ISAAC in a soft white circle.
class IsaacAvatar extends StatelessWidget {
  const IsaacAvatar({super.key, required this.mood, this.size = 44, this.ring = true, this.animate = true});
  final String mood;
  final double size;
  final bool ring;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? const Color(0xFF1E1B4B) : Colors.white,
        border: ring ? Border.all(color: kIsaacIndigo.withValues(alpha: 0.18), width: 2) : null,
        boxShadow: ring ? [BoxShadow(color: kIsaacIndigo.withValues(alpha: 0.18), blurRadius: size * 0.3, offset: Offset(0, size * 0.06))] : null,
      ),
      child: IsaacSticker(state: mood, size: size * 0.88, animate: animate && _canLoadGif(context)),
    );
  }
}

/// The moving GIF comes from the server; without an [AppConfig] (tests, previews) show the still PNG.
bool _canLoadGif(BuildContext context) {
  try {
    context.read<AppConfig>();
    return true;
  } catch (_) {
    return false;
  }
}

/// Gradient "ISAAC AI" chip.
class IsaacBadge extends StatelessWidget {
  const IsaacBadge({super.key, this.small = false});
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
      decoration: BoxDecoration(gradient: kIsaacGradient, borderRadius: BorderRadius.circular(999)),
      child: Text(tr('ไอแซคเอไอ'), style: TextStyle(color: Colors.white, fontSize: small ? 9 : 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
    );
  }
}

/// Page hero: ISAAC + title + badge + a line of help.
class CommAiHero extends StatelessWidget {
  const CommAiHero({super.key, required this.mood, required this.title, this.subtitle, this.trailing, this.footer});
  final String mood;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF312E81).withValues(alpha: 0.55), const Color(0xFF4C1D95).withValues(alpha: 0.35)]
              : [const Color(0xFFEEF2FF), const Color(0xFFF5F3FF), cs.surface],
        ),
        border: Border.all(color: kIsaacIndigo.withValues(alpha: dark ? 0.35 : 0.14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IsaacAvatar(mood: mood, size: 60),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                Text(tr(title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const IsaacBadge(),
              ]),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tr(subtitle!), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ]),
    );
  }
}

/// Centered ISAAC state (loading / empty / error) with an optional action.
class CommAiIsaacState extends StatelessWidget {
  const CommAiIsaacState({super.key, required this.mood, required this.title, this.message, this.action, this.busy = false, this.size = 96});
  final String mood;
  final String title;
  final String? message;
  final Widget? action;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        IsaacAvatar(mood: mood, size: size),
        const SizedBox(height: 12),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy) ...[const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8)],
          Flexible(child: Text(tr(title), textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(tr(message!), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
        ],
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]),
    );
  }
}

/// "ISAAC แนะนำ: …" tip row.
class IsaacTip extends StatelessWidget {
  const IsaacTip(this.text, {super.key, this.mood = 'idea'});
  final String text;
  final String mood;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: kIsaacIndigo.withValues(alpha: dark ? 0.16 : 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        IsaacAvatar(mood: mood, size: 34, ring: false, animate: false),
        const SizedBox(width: 10),
        Expanded(child: Text(tr(text), style: TextStyle(fontSize: 12.5, height: 1.4, color: dark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3)))),
      ]),
    );
  }
}

/// Section title used inside comm-AI pages.
class CommAiSectionTitle extends StatelessWidget {
  const CommAiSectionTitle(this.text, {super.key, this.icon, this.trailing});
  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(children: [
        if (icon != null) ...[Icon(icon, size: 16, color: kIsaacIndigo), const SizedBox(width: 6)],
        Expanded(child: Text(tr(text), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
        ?trailing,
      ]),
    );
  }
}
