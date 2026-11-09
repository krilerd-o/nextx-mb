import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';

/// Place name / address for a coordinate, from the phone's own geocoder (no
/// API key). Null when the device can't tell (offline, no service).
class GeoAddress {
  GeoAddress._();

  static final Map<String, String?> _cache = {};

  /// Test hook: replaces the platform geocoder.
  @visibleForTesting
  static Future<String?> Function(double lat, double lng)? debugLookup;

  static String _key(double lat, double lng) => '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Up to three short lines: place / street, district, province.
  static Future<String?> lookup(double lat, double lng, {Duration timeout = const Duration(seconds: 6)}) async {
    final k = _key(lat, lng);
    if (_cache.containsKey(k)) return _cache[k];
    String? out;
    try {
      if (debugLookup != null) {
        out = await debugLookup!(lat, lng);
      } else {
        final marks = await Geocoding(locale: const Locale('th', 'TH')).placemarkFromCoordinates(lat, lng).timeout(timeout);
        if (marks.isNotEmpty) out = format(marks.first);
      }
    } catch (_) {
      out = null;
    }
    if (out != null && out.trim().isEmpty) out = null;
    _cache[k] = out;
    return out;
  }

  /// `Lumpini Tower\n1168/111 Rama IV Rd\nThung Maha Mek` style lines.
  static String format(Placemark p) {
    String c(String? s) => (s ?? '').trim();
    final lines = <String>[];
    void add(String s) {
      if (s.isEmpty) return;
      if (lines.any((l) => l.contains(s))) return;
      lines.add(s);
    }

    final name = c(p.name);
    final street = [c(p.subThoroughfare), c(p.thoroughfare)].where((e) => e.isNotEmpty).join(' ');
    if (name.isNotEmpty && name != c(p.subThoroughfare) && !RegExp(r'^\d+[/\d]*$').hasMatch(name)) add(name);
    add(street.isEmpty ? c(p.street) : street);
    final area = [c(p.subLocality), c(p.locality)].where((e) => e.isNotEmpty).toSet().join(' ');
    add(area.isEmpty ? c(p.subAdministrativeArea) : area);
    if (lines.length < 3) add(c(p.administrativeArea));
    return lines.take(3).join('\n');
  }
}
