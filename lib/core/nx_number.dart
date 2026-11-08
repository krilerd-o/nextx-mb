/// Numbers for people: thousands separated with commas (12,294; ฿10,250,000).
library;

/// 12294 → "12,294"; -1500.5 → "-1,501" (whole numbers on cards).
String nxInt(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0;
  return _group(n.round());
}

/// 10250000 → "฿10,250,000".
String nxBaht(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0;
  final r = n.round();
  return r < 0 ? '-฿${_group(-r)}' : '฿${_group(r)}';
}

String _group(int n) {
  final neg = n < 0;
  final s = (neg ? -n : n).toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}
