import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai_commands.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../widgets/nx_icons.dart';

/// "ไอแซคด่วน" on Home: the user's 3 most used commands (else /lead, /นัด,
/// /สรุป). Tap → the AI chat with that command waiting in the composer.
class IsaacShortcuts extends StatefulWidget {
  const IsaacShortcuts({super.key, this.allowed});

  /// Hide commands the user may not use (create commands follow menu access).
  final bool Function(AiCommand c)? allowed;

  @override
  State<IsaacShortcuts> createState() => _IsaacShortcutsState();
}

class _IsaacShortcutsState extends State<IsaacShortcuts> {
  List<AiCommand> _cmds = const [];

  @override
  void initState() {
    super.initState();
    aiTopCommands(n: 6).then((names) {
      if (!mounted) return;
      final all = {for (final c in kAiBuiltinCommands) c.command: c};
      setState(() {
        _cmds = [
          for (final n in names)
            if (all[n] != null && (widget.allowed?.call(all[n]!) ?? true)) all[n]!,
        ].take(3).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cmds.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      key: const ValueKey('home-isaac-shortcuts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(children: [
            Icon(NxI.sparkle, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(tr('ไอแซคด่วน'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          ]),
        ),
        Row(
          children: [
            for (final (i, c) in _cmds.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    key: ValueKey('home-isaac-cmd-${c.command}'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push(AppRoutes.aiCommand(c.command)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('/${c.command}', style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(tr(c.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
