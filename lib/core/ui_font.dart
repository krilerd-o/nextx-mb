/// App fonts — the same choices as the web (frontend/src/constants/uiFonts.js).
/// All are bundled in assets/fonts (no network). Thai text falls back to
/// IBM Plex Sans Thai / Noto Sans Thai, like the web font stack.
class UiFont {
  const UiFont(this.id, this.family, this.label);

  /// Stored id (same ids as the web).
  final String id;

  /// pubspec `fonts:` family.
  final String family;

  /// Name shown in the picker.
  final String label;
}

const String kDefaultUiFontId = 'google_sans';

const List<UiFont> kUiFonts = [
  UiFont('google_sans', 'GoogleSans', 'Google Sans'),
  UiFont('ibm_plex_sans_thai', 'IBMPlexSansThai', 'IBM Plex Sans Thai'),
  UiFont('noto_sans_thai', 'NotoSansThai', 'Noto Sans Thai'),
  UiFont('sarabun', 'Sarabun', 'Sarabun'),
  UiFont('bai_jamjuree', 'BaiJamjuree', 'Bai Jamjuree'),
  UiFont('maitree', 'Maitree', 'Maitree'),
];

/// Known id or the default (Google Sans).
String resolveUiFontId(String? id) =>
    kUiFonts.any((f) => f.id == id) ? id! : kDefaultUiFontId;

UiFont uiFontById(String? id) {
  final r = resolveUiFontId(id);
  return kUiFonts.firstWhere((f) => f.id == r);
}

/// Fallback chain for glyphs a font lacks (Thai first).
List<String> uiFontFallback(String family) => [
  if (family != 'IBMPlexSansThai') 'IBMPlexSansThai',
  if (family != 'NotoSansThai') 'NotoSansThai',
  'Leelawadee UI',
  'Tahoma',
  'sans-serif',
];

/// Screen scale steps (Settings → ขนาดหน้าจอ). Default 95%.
const List<double> kUiScales = [0.9, 0.95, 1.0, 1.05, 1.1];
const double kDefaultUiScale = 0.95;

double resolveUiScale(double? v) {
  if (v == null) return kDefaultUiScale;
  for (final s in kUiScales) {
    if ((s - v).abs() < 0.001) return s;
  }
  return kDefaultUiScale;
}
