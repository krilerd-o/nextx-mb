import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../core/i18n.dart';
import 'nx_icons.dart';

/// Red that stays readable on both themes (plain `error` is too dark on the
/// dark surface, too pale as text on a tinted fill).
Color nxDangerColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark ? const Color(0xFFFF8A8A) : theme.colorScheme.error;
}

/// "ออกจากระบบ" confirm: says plainly what happens and that signing back
/// in later is fine. Returns true when the user confirms.
Future<bool> confirmNxLogout(BuildContext context, AppConfig config) async {
  final space = config.activeSpace?.title;
  final others = config.spaces.length > 1;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final danger = nxDangerColor(ctx);
      Widget point(IconData icon, String text) => Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(text), style: theme.textTheme.bodyMedium?.copyWith(height: 1.45))),
            ]),
          );
      return AlertDialog(
        key: const ValueKey('nx-logout-dialog'),
        // Small phones / large text: the message scrolls, the buttons stay.
        scrollable: true,
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: danger.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(NxI.signOut, color: danger, size: 26),
        ),
        title: Text(tr('ออกจากระบบใช่ไหม?'), textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (space != null && space.isNotEmpty)
            Center(
              child: Text(
                space,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          point(NxI.shieldCheck, 'ข้อมูลและงานของคุณยังอยู่ครบ ไม่มีอะไรถูกลบ'),
          point(NxI.signIn, 'กลับมาเข้าสู่ระบบได้อีกครั้งทุกเมื่อ ด้วยบัญชีเดิม'),
          if (others) point(NxI.squaresFour, 'Space อื่นในแอปยังใช้งานได้ตามปกติ'),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('nx-logout-cancel'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => Navigator.pop(ctx, false),
                child: _oneLine(tr('อยู่ต่อ')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const ValueKey('nx-logout-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: _oneLine(tr('ออกจากระบบ')),
              ),
            ),
          ]),
        ],
      );
    },
  );
  if (ok == true) HapticFeedback.mediumImpact();
  return ok == true;
}

/// Full-width sign-out button: tinted outline, readable red in light and dark.
class NxLogoutButton extends StatelessWidget {
  const NxLogoutButton({super.key, required this.onPressed, this.subtitle});
  final VoidCallback onPressed;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = nxDangerColor(context);
    return Material(
      color: danger.withValues(alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: danger.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('nx-logout-button'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(NxI.signOut, size: 20, color: danger),
              const SizedBox(width: 10),
              Text(tr('ออกจากระบบ'), style: theme.textTheme.titleSmall?.copyWith(color: danger, fontWeight: FontWeight.w700)),
            ]),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Button label on one line: shrinks a little on narrow dialogs / large fonts
/// instead of wrapping to two lines.
Widget _oneLine(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
