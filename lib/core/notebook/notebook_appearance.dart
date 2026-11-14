import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notebook cover look — colour, icon, cover style, pin (NEXTX notebook v6
/// `appearance` JSON; keys match backend `aiNotebookAppearance.js` and the
/// web `notebookAppearance.js`).
///
/// Older servers have no `appearance`: the title hash picks a colour + icon so
/// the library still looks varied, and the user's own pick is kept on the
/// device ([NotebookAppearanceStore]) until the server can store it.

/// One palette entry: [light] on white cards, [dark] on the dark theme.
@immutable
class NotebookColor {
  const NotebookColor(this.key, this.label, this.light, this.dark);
  final String key;

  /// Thai name (wrap with tr()).
  final String label;
  final Color light;
  final Color dark;

  Color of(Brightness b) => b == Brightness.dark ? dark : light;
}

const kNotebookColors = <NotebookColor>[
  NotebookColor('violet', 'ม่วง', Color(0xFF7C3AED), Color(0xFFA78BFA)),
  NotebookColor('indigo', 'คราม', Color(0xFF4F46E5), Color(0xFF818CF8)),
  NotebookColor('blue', 'น้ำเงิน', Color(0xFF2563EB), Color(0xFF60A5FA)),
  NotebookColor('sky', 'ฟ้า', Color(0xFF0284C7), Color(0xFF38BDF8)),
  NotebookColor('teal', 'เขียวน้ำทะเล', Color(0xFF0D9488), Color(0xFF2DD4BF)),
  NotebookColor('green', 'เขียว', Color(0xFF16A34A), Color(0xFF4ADE80)),
  NotebookColor('amber', 'เหลืองอำพัน', Color(0xFFD97706), Color(0xFFFBBF24)),
  NotebookColor('orange', 'ส้ม', Color(0xFFEA580C), Color(0xFFFB923C)),
  NotebookColor('rose', 'ชมพูกุหลาบ', Color(0xFFE11D48), Color(0xFFFB7185)),
  NotebookColor('slate', 'เทา', Color(0xFF475569), Color(0xFF94A3B8)),
];

/// Icon keys → Lucide (same names on the web).
const kNotebookIcons = <String, IconData>{
  'book': LucideIcons300.bookOpen,
  'briefcase': LucideIcons300.briefcase,
  'users': LucideIcons300.users,
  'chart': LucideIcons300.chartColumn,
  'lightbulb': LucideIcons300.lightbulb,
  'graduation': LucideIcons300.graduationCap,
  'megaphone': LucideIcons300.megaphone,
  'shield': LucideIcons300.shield,
  'wrench': LucideIcons300.wrench,
  'globe': LucideIcons300.globe,
  'sparkles': LucideIcons300.sparkles,
  'file_text': LucideIcons300.fileText,
  'calendar': LucideIcons300.calendar,
  'target': LucideIcons300.target,
  'heart': LucideIcons300.heart,
  'code': LucideIcons300.code,
  'flask': LucideIcons300.flaskConical,
  'scale': LucideIcons300.scale,
  'receipt': LucideIcons300.receipt,
  'package': LucideIcons300.package,
  'headset': LucideIcons300.headset,
  'map_pin': LucideIcons300.mapPin,
  'camera': LucideIcons300.camera,
  'music': LucideIcons300.music,
};

/// Cover styles: สมุด (spine + ribbon) / ไล่สี (gradient top) / เรียบ (plain).
const kNotebookCovers = <(String, String)>[('book', 'สมุด'), ('gradient', 'ไล่สี'), ('minimal', 'เรียบ')];

final List<String> _colorKeys = [for (final c in kNotebookColors) c.key];
final List<String> _iconKeys = kNotebookIcons.keys.toList();
const _coverKeys = ['book', 'gradient', 'minimal'];

/// 32-bit hash of the trimmed title (UTF-16 units, ×31) — same as the web's `notebookTitleHash`.
int notebookTitleHash(String title) {
  var h = 0;
  for (final c in title.trim().codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

@immutable
class NotebookAppearance {
  const NotebookAppearance({this.color = 'violet', this.icon = 'book', this.cover = 'book', this.pinned = false});

  final String color;
  final String icon;

  /// book | gradient | minimal
  final String cover;
  final bool pinned;

  /// Colour + icon from the title, book cover, not pinned (varied with no user effort).
  factory NotebookAppearance.forTitle(String title) {
    final h = notebookTitleHash(title);
    return NotebookAppearance(color: _colorKeys[h % _colorKeys.length], icon: _iconKeys[(h ~/ _colorKeys.length) % _iconKeys.length]);
  }

  /// Server / stored JSON; unknown keys fall back to [fallback] (or the defaults). Not a map → null.
  static NotebookAppearance? tryParse(Object? raw, {NotebookAppearance? fallback}) {
    Object? v = raw;
    if (v is String && v.trim().startsWith('{')) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    if (v is! Map) return null;
    final d = fallback ?? const NotebookAppearance();
    String pick(List<String> list, Object? x, String dflt) {
      final k = '${x ?? ''}'.trim().toLowerCase().replaceAll('-', '_');
      return list.contains(k) ? k : dflt;
    }

    final p = v['pinned'];
    return NotebookAppearance(
      color: pick(_colorKeys, v['color'], d.color),
      icon: pick(_iconKeys, v['icon'], d.icon),
      cover: pick(_coverKeys, v['cover'], d.cover),
      pinned: p == null ? d.pinned : (p == true || p == 1 || '$p'.toLowerCase() == 'true'),
    );
  }

  Map<String, dynamic> toJson() => {'color': color, 'icon': icon, 'cover': cover, 'pinned': pinned};

  NotebookAppearance copyWith({String? color, String? icon, String? cover, bool? pinned}) =>
      NotebookAppearance(color: color ?? this.color, icon: icon ?? this.icon, cover: cover ?? this.cover, pinned: pinned ?? this.pinned);

  NotebookColor get palette => kNotebookColors.firstWhere((c) => c.key == color, orElse: () => kNotebookColors.first);
  IconData get iconData => kNotebookIcons[icon] ?? LucideIcons300.bookOpen;

  /// Colour for [context]'s brightness.
  Color tint(BuildContext context) => palette.of(Theme.of(context).brightness);

  @override
  bool operator ==(Object other) =>
      other is NotebookAppearance && other.color == color && other.icon == icon && other.cover == cover && other.pinned == pinned;

  @override
  int get hashCode => Object.hash(color, icon, cover, pinned);

  @override
  String toString() => 'NotebookAppearance($color, $icon, $cover, pinned: $pinned)';
}

/// The user's picks kept on the device, per space (server + user + business) and notebook id —
/// used when the server has no `appearance` yet (or did not store it).
class NotebookAppearanceStore {
  NotebookAppearanceStore._();

  static String key(String scope) => 'nx_notebook_look_v1_$scope';

  static Future<Map<String, NotebookAppearance>> load(String scope) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key(scope));
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      final out = <String, NotebookAppearance>{};
      for (final e in m.entries) {
        final a = NotebookAppearance.tryParse(e.value);
        if (a != null) out['${e.key}'] = a;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String scope, String notebookId, NotebookAppearance? look) async {
    try {
      final p = await SharedPreferences.getInstance();
      final all = await load(scope);
      if (look == null) {
        all.remove(notebookId);
      } else {
        all[notebookId] = look;
      }
      await p.setString(key(scope), jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }
}
