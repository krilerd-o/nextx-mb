import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'i18n_en.dart';

/// App UI language. Strings in the code are Thai; [tr] turns them into the
/// current language at display time (Text, hints, labels, tooltips), so data
/// and logic keep using the Thai values.
class L10n {
  L10n._();

  static final ValueNotifier<String> locale = ValueNotifier<String>('th');

  static bool get isEn => locale.value == 'en';

  /// Set by the app's switch layer: animates, calls `apply` while the screen
  /// is covered, then rebuilds every screen in the new language.
  static Future<void> Function(String code, VoidCallback apply)? switcher;

  static void set(String code) {
    final c = code == 'en' ? 'en' : 'th';
    if (locale.value == c) return;
    _cache.clear();
    locale.value = c;
  }

  /// Translations already resolved this session (exact + pattern hits).
  static final Map<String, String> _cache = {};

  static final List<_Pattern> _patterns = [
    for (final e in enPatterns.entries) _Pattern(e.key, e.value),
  ]..sort((a, b) => b.fixedLength.compareTo(a.fixedLength));

  static final RegExp _thai = RegExp(r'[฀-๿]');

  static String translate(String th) {
    if (!isEn || th.isEmpty) return th;
    final exact = enStrings[th];
    if (exact != null) return exact;
    final hit = _cache[th];
    if (hit != null) return hit;
    // Only Thai text can be a UI string; server data in English passes through.
    if (!_thai.hasMatch(th)) return th;
    var out = th;
    for (final p in _patterns) {
      final m = p.match(th);
      if (m != null) {
        out = m;
        break;
      }
    }
    if (_cache.length > 4000) _cache.clear();
    _cache[th] = out;
    return out;
  }
}

/// Current-language text for a Thai UI string (or a string built from one).
String tr(String th) => L10n.translate(th);

/// A Thai template with `{}` holes (from `'ลบ $x แล้ว'`) and its English form.
class _Pattern {
  _Pattern(String th, this.en) : _re = _compile(th), fixedLength = th.replaceAll('{}', '').length;

  final RegExp _re;
  final String en;
  final int fixedLength;

  static RegExp _compile(String th) {
    final parts = th.split('{}').map(RegExp.escape).toList();
    return RegExp('^${parts.join('(.*?)')}\$', dotAll: true);
  }

  String? match(String s) {
    final m = _re.firstMatch(s);
    if (m == null) return null;
    var i = 0;
    // Holes may themselves be UI strings (e.g. a translated label inside a sentence).
    return en.replaceAllMapped('{}', (_) {
      i++;
      final g = i <= m.groupCount ? (m.group(i) ?? '') : '';
      return L10n.translate(g);
    });
  }
}

/// Rebuilds every element under [context] (after a language switch), keeping
/// all state — screens, scroll positions and forms stay where they were.
void rebuildAllChildren(BuildContext context) {
  void rebuild(Element el) {
    el.markNeedsBuild();
    el.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}

/// [tr] for optional texts (hints, tooltips, labels that may be null).
String? trn(String? th) => th == null ? null : L10n.translate(th);

/// Year as shown in the UI: Buddhist Era in Thai, Gregorian in English.
int uiYear(int gregorianYear) => L10n.isEn ? gregorianYear : gregorianYear + 543;
