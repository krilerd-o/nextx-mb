import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/session_ended.dart';
import 'nx_icons.dart';

/// "You were signed out" — why NEXTX ended this device's session (usage mode, auto sign-out,
/// admin, business security rule). Shown once on the login screen after the sign-out.
Future<void> showNxSessionEndedDialog(BuildContext context, SessionEnded ended) {
  final text = sessionEndedText(ended);
  final icon = switch (ended.reason) {
    'replaced' => NxI.deviceMobile,
    'limit' => NxI.users,
    'idle' => NxI.clock,
    _ => ended.isPolicyBlock ? NxI.shieldCheck : NxI.signOut,
  };
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      return AlertDialog(
        key: const ValueKey('nx-session-ended-dialog'),
        scrollable: true,
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.amber.shade800, size: 26),
        ),
        title: Text(tr(text.title), textAlign: TextAlign.center),
        content: Text(tr(text.body), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: cs.onSurface)),
        actions: [
          FilledButton(
            key: const ValueKey('nx-session-ended-ok'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('รับทราบ')),
          ),
        ],
      );
    },
  );
}
