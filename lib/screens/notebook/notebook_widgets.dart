import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../comm_ai/comm_ai_isaac.dart';

/// Shared bits of the native ISAAC Notebook screens.

const kNotebookAccent = Color(0xFF6366F1);

/// Gradient cover with the notebook's emoji.
class NotebookCover extends StatelessWidget {
  const NotebookCover({super.key, required this.id, this.size = 48, this.radius = 14, this.emojiSize});
  final String id;
  final double size;
  final double radius;
  final double? emojiSize;

  @override
  Widget build(BuildContext context) {
    final c = notebookCover(id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c.colors),
        boxShadow: [BoxShadow(color: c.colors.first.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Text(c.emoji, style: TextStyle(fontSize: emojiSize ?? size * 0.46)),
    );
  }
}

/// Icon + tint of a source kind.
({IconData icon, Color color}) sourceKindStyle(NotebookSource s) {
  if (s.isYoutube) return (icon: LucideIcons300.circlePlay, color: const Color(0xFFEF4444));
  switch (s.kind) {
    case 'file':
      final mime = '${s.config['mime'] ?? ''}';
      final name = s.title.toLowerCase();
      if (mime.startsWith('image/') || RegExp(r'\.(png|jpe?g|webp|heic)$').hasMatch(name)) return (icon: LucideIcons300.image, color: const Color(0xFF0EA5E9));
      if (mime.startsWith('audio/') || RegExp(r'\.(mp3|m4a|wav|ogg|aac)$').hasMatch(name)) return (icon: LucideIcons300.audioLines, color: const Color(0xFF8B5CF6));
      if (name.endsWith('.pdf')) return (icon: LucideIcons300.fileText, color: const Color(0xFFDC2626));
      if (RegExp(r'\.(xlsx?|csv)$').hasMatch(name)) return (icon: LucideIcons300.sheet, color: const Color(0xFF16A34A));
      return (icon: LucideIcons300.file, color: const Color(0xFF2563EB));
    case 'url':
      return (icon: LucideIcons300.globe, color: const Color(0xFF0891B2));
    case 'library':
      return (icon: LucideIcons300.library, color: const Color(0xFFD97706));
    case 'crm_module':
    case 'picklist':
      return (icon: LucideIcons300.database, color: const Color(0xFF7C3AED));
    case 'recording':
      return (icon: LucideIcons300.mic, color: const Color(0xFFDB2777));
  }
  return (icon: LucideIcons300.textCursorInput, color: const Color(0xFF64748B));
}

/// Rounded tinted square holding [icon].
class NotebookIconBadge extends StatelessWidget {
  const NotebookIconBadge({super.key, required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: dark ? 0.22 : 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Gradient badge for a studio kind.
class StudioKindBadge extends StatelessWidget {
  const StudioKindBadge({super.key, required this.kind, this.size = 40});
  final StudioKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.32),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: kind.colors),
        ),
        child: Icon(kind.icon, size: size * 0.5, color: Colors.white),
      );
}

/// ISAAC + message for empty / error / disabled screens.
class NotebookState extends StatelessWidget {
  const NotebookState({super.key, required this.mood, required this.title, this.message, this.action, this.size = 96, this.busy = false});
  final String mood;
  final String title;
  final String? message;
  final Widget? action;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: CommAiIsaacState(mood: mood, title: title, message: message, action: action, size: size, busy: busy),
          ),
        ),
      );
}

/// "สมุดโน้ตถูกปิด" (AI_NOTEBOOK_DISABLED / AI_FEATURE_DISABLED).
class NotebookDisabledState extends StatelessWidget {
  const NotebookDisabledState({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => NotebookState(
        key: const ValueKey('notebook-disabled'),
        mood: 'sleepy',
        title: 'สมุดโน้ต AI ยังไม่เปิดใช้',
        message: message ?? 'ให้ผู้ดูแลระบบเปิด AI Notebook ในการตั้งค่า AI ของธุรกิจ แล้วลองใหม่อีกครั้ง',
      );
}

/// Small caps label above a section.
class NotebookSectionLabel extends StatelessWidget {
  const NotebookSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(tr(text), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.2)),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Soft card used across the notebook (light: white, dark: raised surface).
class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.onLongPress, this.color, this.border, this.radius = 20});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    return Material(
      color: color ?? (dark ? const Color(0xFF1C1D26) : Colors.white),
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border ?? cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small rounded pill (topics, citations) — tighter than a Material chip.
class NotebookPill extends StatelessWidget {
  const NotebookPill({super.key, required this.label, this.leading, this.onTap, this.maxWidth = 220});
  final String label;
  final Widget? leading;
  final VoidCallback? onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leading == null ? 12 : 6, 5, 12, 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Background behind the notebook screens: a soft indigo wash at the top.
class NotebookBackdrop extends StatelessWidget {
  const NotebookBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.35, 1],
          colors: dark
              ? const [Color(0xFF17162A), Color(0xFF111114), Color(0xFF111114)]
              : const [Color(0xFFEEF0FF), Color(0xFFF6F7FB), Color(0xFFF6F7FB)],
        ),
      ),
      child: child,
    );
  }
}
