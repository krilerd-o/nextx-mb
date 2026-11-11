import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../services/shutter_sound.dart';
import 'app_bottom_sheet.dart';
import 'nx_icons.dart';

/// Settings sheet: pick the shutter sound (tap = play a sample) or turn it off.
Future<void> showShutterSoundPicker(BuildContext context) async {
  await ShutterSound.instance.load();
  if (!context.mounted) return;
  await showAppBottomSheet<void>(
    context: context,
    title: tr('เสียงชัตเตอร์'),
    child: const _Picker(),
  );
}

class _Picker extends StatefulWidget {
  const _Picker();

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  ShutterStyle _sel = ShutterSound.instance.style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in ShutterStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: s == _sel ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: s == _sel ? cs.primary : Colors.transparent, width: 1.4),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('shutter-${s.name}'),
                leading: CircleAvatar(
                  backgroundColor: cs.primary.withValues(alpha: 0.14),
                  child: Icon(s == ShutterStyle.off ? NxI.bellSlash : NxI.camera, color: cs.primary, size: 20),
                ),
                title: Text(tr(s.labelTh), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr(s.hintTh)),
                trailing: s == _sel ? Icon(NxI.check, color: cs.primary) : null,
                onTap: () async {
                  HapticFeedback.selectionClick();
                  ShutterSound.instance.play(s);
                  setState(() => _sel = s);
                  await ShutterSound.instance.setStyle(s);
                },
              ),
            ),
          ),
        Text(
          tr('ใช้เสียงที่สร้างขึ้นเองสำหรับแอปนี้ · iPhone ที่เปิดโหมดเงียบจะไม่มีเสียง'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
