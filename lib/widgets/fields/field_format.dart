import 'dart:convert';

bool isTruthyFieldValue(dynamic value) {
  if (value == true || value == 1) return true;
  final s = value?.toString().trim().toLowerCase() ?? '';
  return s == '1' || s == 'yes' || s == 'true' || s == 'on';
}

String yesNoStored(bool checked) => checked ? '1' : '0';

String digitsOnly(dynamic raw, [int max = 32]) {
  return String.fromCharCodes(
    (raw?.toString() ?? '').codeUnits.where((c) => c >= 48 && c <= 57),
  ).substringSafe(max);
}

String formatPhoneDisplay(dynamic raw) {
  final d = digitsOnly(raw, 10);
  if (d.length <= 3) return d;
  if (d.length <= 6) return '${d.substring(0, 3)}-${d.substring(3)}';
  return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
}

String formatTaxIdDisplay(dynamic raw) {
  final d = digitsOnly(raw, 13);
  if (d.isEmpty) return '';
  final p1 = d.substring(0, d.length.clamp(0, 1));
  final p2 = d.length > 1 ? d.substring(1, d.length.clamp(1, 5)) : '';
  final p3 = d.length > 5 ? d.substring(5, d.length.clamp(5, 10)) : '';
  final p4 = d.length > 10 ? d.substring(10, d.length.clamp(10, 12)) : '';
  final p5 = d.length > 12 ? d.substring(12, 13) : '';
  var out = p1;
  if (p2.isNotEmpty) out += '-$p2';
  if (p3.isNotEmpty) out += '-$p3';
  if (p4.isNotEmpty) out += '-$p4';
  if (p5.isNotEmpty) out += '-$p5';
  return out;
}

String two(int n) => n.toString().padLeft(2, '0');

String formatYmd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String formatHm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

DateTime? parseDate(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

Map<String, String> parseRange(dynamic raw, {int slice = 10}) {
  if (raw is Map) {
    return {
      'start': (raw['start'] ?? '').toString().takeSlice(slice),
      'end': (raw['end'] ?? '').toString().takeSlice(slice),
    };
  }
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return {'start': '', 'end': ''};
  try {
    final j = jsonDecode(s);
    if (j is Map) {
      return {
        'start': (j['start'] ?? '').toString().takeSlice(slice),
        'end': (j['end'] ?? '').toString().takeSlice(slice),
      };
    }
  } catch (_) {}
  return {'start': '', 'end': ''};
}

String formatRange(String start, String end) {
  if (start.isEmpty && end.isEmpty) return '';
  return jsonEncode({'start': start, 'end': end});
}

({String lat, String lng}) parseLatLong(dynamic raw) {
  if (raw is Map) {
    return (lat: '${raw['lat'] ?? ''}', lng: '${raw['lng'] ?? ''}');
  }
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return (lat: '', lng: '');
  try {
    final j = jsonDecode(s);
    if (j is Map) {
      return (lat: '${j['lat'] ?? ''}', lng: '${j['lng'] ?? ''}');
    }
  } catch (_) {}
  final parts = s.split(',');
  if (parts.length >= 2) {
    return (lat: parts[0].trim(), lng: parts[1].trim());
  }
  return (lat: '', lng: '');
}

String formatLatLong(String lat, String lng) {
  final la = double.tryParse(lat);
  final ln = double.tryParse(lng);
  if (la == null || ln == null) return '';
  return '${(la * 1e6).round() / 1e6},${(ln * 1e6).round() / 1e6}';
}

({double? x, double? y}) parseXy(dynamic raw) {
  if (raw is Map) {
    return (
      x: double.tryParse('${raw['x'] ?? ''}'),
      y: double.tryParse('${raw['y'] ?? ''}'),
    );
  }
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return (x: null, y: null);
  try {
    final j = jsonDecode(s);
    if (j is Map) {
      return (
        x: double.tryParse('${j['x'] ?? ''}'),
        y: double.tryParse('${j['y'] ?? ''}'),
      );
    }
  } catch (_) {}
  return (x: null, y: null);
}

String formatXy(double x, double y) =>
    jsonEncode({'x': (x * 10000).round() / 10000, 'y': (y * 10000).round() / 10000});

({String url, dynamic fileId}) parseMedia(dynamic raw) {
  if (raw is Map) {
    return (url: '${raw['url'] ?? raw['src'] ?? ''}', fileId: raw['file_id']);
  }
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return (url: '', fileId: null);
  try {
    final j = jsonDecode(s);
    if (j is Map) {
      return (url: '${j['url'] ?? j['src'] ?? ''}', fileId: j['file_id']);
    }
  } catch (_) {}
  return (url: s, fileId: null);
}

String formatMedia({String? url, dynamic fileId}) {
  final u = (url ?? '').trim();
  if (u.isEmpty && fileId == null) return '';
  if (fileId != null && u.isNotEmpty) {
    return jsonEncode({'url': u, 'file_id': fileId});
  }
  return u;
}

Map<String, dynamic> parsePost(dynamic raw) {
  const defaults = {
    'authorName': '',
    'rating': 5,
    'body': '',
    'likeCount': 0,
  };
  if (raw == null || raw.toString().trim().isEmpty) return Map.of(defaults);
  if (raw is Map) return {...defaults, ...Map<String, dynamic>.from(raw)};
  try {
    final j = jsonDecode(raw.toString());
    if (j is Map) return {...defaults, ...Map<String, dynamic>.from(j)};
  } catch (_) {}
  return {...defaults, 'body': raw.toString()};
}

String formatPost(Map<String, dynamic> post) => jsonEncode({
      'authorName': (post['authorName'] ?? '').toString(),
      'rating': post['rating'] ?? 5,
      'body': (post['body'] ?? '').toString(),
      'likeCount': post['likeCount'] ?? 0,
    });

List<String> splitMulti(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return [];
  if (s.startsWith('[')) {
    try {
      final j = jsonDecode(s);
      if (j is List) {
        return j.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
  }
  return s.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

String joinMulti(Iterable<String> values) =>
    values.map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');

double clampPercent(dynamic raw) {
  final n = double.tryParse(raw?.toString() ?? '') ?? 0;
  if (n < 0) return 0;
  if (n > 100) return 100;
  return n;
}

String displayHexColor(dynamic raw) {
  final s = (raw?.toString() ?? '').trim();
  if (s.isEmpty) return '';
  if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s)) return s.toUpperCase();
  if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(s)) return '#${s.toUpperCase()}';
  return s;
}

extension _Slice on String {
  String takeSlice(int n) => length <= n ? this : substring(0, n);
  String substringSafe(int max) => length <= max ? this : substring(0, max);
}
