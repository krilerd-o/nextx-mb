import 'package:flutter/material.dart';

import '../../../../core/ai_assistant.dart';
import '../../../../widgets/nx_icons.dart';

/// Design tokens of the ISAAC chat: calm near-white canvas, one indigo
/// accent, soft surfaces instead of borders, pill chips, 8pt spacing.
class AiStyle {
  AiStyle._();

  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFF8B5CF6);

  /// The only gradient: send button, Isaac ring, mode chip.
  static const accent = LinearGradient(colors: [indigo, violet], begin: Alignment.topLeft, end: Alignment.bottomRight);

  static const composerRadius = 28.0;
  static const cardRadius = 20.0;
  static const sheetRadius = 28.0;
  static const gutter = 16.0;

  /// Readable chat width on tablets.
  static const maxContentWidth = 720.0;

  static const motion = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static Color canvas(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F1115) : const Color(0xFFF7F7FB);

  /// Raised surface (composer, cards) on the canvas.
  static Color surface(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1C23) : Colors.white;

  /// Quiet fill for chips and the user's bubble.
  static Color tint(BuildContext context) => Theme.of(context).colorScheme.primary.withValues(alpha: 0.09);

  static List<BoxShadow> softShadow(BuildContext context) => Theme.of(context).brightness == Brightness.dark
      ? const []
      : [
          BoxShadow(color: const Color(0xFF1C1C3A).withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 6)),
          BoxShadow(color: const Color(0xFF1C1C3A).withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1)),
        ];

  /// Animations off when the user asked for reduced motion.
  static Duration of(BuildContext context, [Duration d = motion]) => MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;

  /// Warning colour that works in both themes (instead of a hard-coded amber).
  static Color warn(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);

  static Color folderColor(BuildContext context, String? hex) {
    final v = aiHexColor(hex);
    return v == null ? Theme.of(context).colorScheme.primary : Color(v);
  }

  static IconData modeIcon(String mode) => switch (mode) {
    'fast' => NxI.lightning,
    'deep' => AiIcons.brain,
    _ => NxI.sparkle,
  };

  /// Icon for a slash command's icon key.
  static IconData commandIcon(String key) => switch (key) {
    'search' => NxI.magnifyingGlass,
    'userPlus' => NxI.userPlus,
    'contact' => NxI.addressBook,
    'case' => NxI.lifeBuoy,
    'calendar' => NxI.calendarPlus,
    'summary' => NxI.textAlignLeft,
    'mail' => NxI.envelope,
    'excel' => NxI.fileXls,
    'pdf' => NxI.filePdf,
    'doc' => NxI.fileDoc,
    'board' => NxI.kanban,
    'chart' => NxI.chartBar,
    'translate' => NxI.languages,
    'deep' => AiIcons.brain,
    'building' => NxI.buildings,
    'user' => NxI.user,
    _ => NxI.sparkle,
  };
}

/// Icons used by the ISAAC screens (all from [NxI]).
class AiIcons {
  AiIcons._();
  static const brain = NxI.brain;
  static const slash = NxI.squareSlash;
  static const folderPlus = NxI.folderPlus;
  static const folderOpen = NxI.folderOpen;
  static const pin = NxI.pushPin;
  static const pinOff = NxI.pinOff;
  static const restore = NxI.archiveRestore;
  static const toBottom = NxI.arrowDownToLine;
  static const newChat = NxI.messageSquarePlus;
  static const wand = NxI.wandSparkles;
}
