// TipTap / web rich HTML helpers — display only (no editor).

class HtmlFileCard {
  const HtmlFileCard({
    required this.name,
    this.href,
    this.mime,
    this.date,
  });

  final String name;
  final String? href;
  final String? mime;
  final String? date;
}

class PreparedHtml {
  const PreparedHtml({
    required this.source,
    required this.body,
    required this.files,
  });

  final String source;
  final String body;
  final List<HtmlFileCard> files;

  bool get looksLikeHtml => looksLikeHtmlString(source);
  bool get isEmpty {
    if (files.isNotEmpty) return false;
    return stripHtmlPreview(body).trim().isEmpty;
  }
}

final _tagRe = RegExp(r'<[a-zA-Z][^>]*>');
final _closeOrVoidRe = RegExp(r'</[a-zA-Z]|/>');

/// Void tags that never close (`a<br>b` from the web's plain comment box).
final _voidTagRe = RegExp(r'<(br|hr|img|wbr)\b[^>]*>', caseSensitive: false);

bool looksLikeHtmlString(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return false;
  if (!s.contains('<')) {
    return s.contains('&amp;') || s.contains('&nbsp;') || s.contains('&lt;');
  }
  return _voidTagRe.hasMatch(s) || (_tagRe.hasMatch(s) && (_closeOrVoidRe.hasMatch(s) || s.startsWith('<')));
}

String decodeHtmlEntities(String input) {
  var s = input;
  s = s.replaceAll(RegExp(r'&nbsp;?', caseSensitive: false), ' ');
  s = s.replaceAll('&amp;', '&');
  s = s.replaceAll('&lt;', '<');
  s = s.replaceAll('&gt;', '>');
  s = s.replaceAll('&quot;', '"');
  s = s.replaceAll('&#39;', "'");
  s = s.replaceAll('&apos;', "'");
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final n = int.tryParse(m[1]!, radix: 16);
    if (n == null) return m[0]!;
    return String.fromCharCode(n);
  });
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final n = int.tryParse(m[1]!);
    if (n == null) return m[0]!;
    return String.fromCharCode(n);
  });
  return s;
}

String stripHtmlPreview(String? html, {int maxLen = 160}) {
  if (html == null || html.isEmpty) return '';
  var s = html;
  s = s.replaceAll(
    RegExp(
      r'<div[^>]*(?:data-moai-file|moai-file-attachment)[^>]*>[\s\S]*?</div>',
      caseSensitive: false,
    ),
    ' ',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = decodeHtmlEntities(s);
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return '';
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen)}…';
}

String sanitizeHtml(String raw) {
  var html = raw;
  html = html.replaceAll(
    RegExp(
      r'<\s*(script|iframe|object|embed|link|meta|base|form|svg|math)[^>]*>[\s\S]*?<\s*/\s*\1\s*>',
      caseSensitive: false,
    ),
    '',
  );
  html = html.replaceAll(
    RegExp(
      r'<\s*(script|iframe|object|embed|link|meta|base|form|svg|math)[^>]*/?\s*>',
      caseSensitive: false,
    ),
    '',
  );
  html = html.replaceAll(RegExp(r'<\s*style[^>]*>[\s\S]*?<\s*/\s*style\s*>', caseSensitive: false), '');
  html = html.replaceAll(RegExp(r"""\son[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)""", caseSensitive: false), '');
  html = html.replaceAll(RegExp(r"""(href|src)\s*=\s*(['"])\s*javascript:[^'"]*\2""", caseSensitive: false), r'$1=$2#$2');
  return html;
}

String resolveHtmlUrl(String url, [String? base]) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('mailto:')) {
    return trimmed;
  }
  if (base == null || base.isEmpty) return trimmed;
  final root = base.replaceAll(RegExp(r'/+$'), '');
  if (trimmed.startsWith('/')) return '$root$trimmed';
  return '$root/$trimmed';
}

PreparedHtml prepareHtml(String? raw) {
  final source = raw ?? '';
  if (source.trim().isEmpty) {
    return const PreparedHtml(source: '', body: '', files: []);
  }
  final extracted = _extractFileCards(source);
  return PreparedHtml(
    source: source,
    body: sanitizeHtml(extracted.body),
    files: extracted.files,
  );
}

({String body, List<HtmlFileCard> files}) _extractFileCards(String html) {
  final files = <HtmlFileCard>[];
  final buf = StringBuffer();
  var i = 0;
  final lower = html.toLowerCase();
  while (i < html.length) {
    final divAt = lower.indexOf('<div', i);
    if (divAt < 0) {
      buf.write(html.substring(i));
      break;
    }
    buf.write(html.substring(i, divAt));
    final tagEnd = html.indexOf('>', divAt);
    if (tagEnd < 0) {
      buf.write(html.substring(divAt));
      break;
    }
    final openTag = html.substring(divAt, tagEnd + 1);
    final openLower = openTag.toLowerCase();
    final isFile = openLower.contains('data-moai-file') || openLower.contains('moai-file-attachment');
    if (!isFile) {
      buf.write(openTag);
      i = tagEnd + 1;
      continue;
    }
    final innerEnd = _findMatchingDivEnd(html, tagEnd + 1);
    final inner = innerEnd == null ? '' : html.substring(tagEnd + 1, innerEnd);
    files.add(_fileCardFromMarkup(openTag, inner));
    i = innerEnd ?? (tagEnd + 1);
    if (innerEnd == null) {
      buf.write(openTag);
    }
  }
  return (body: buf.toString(), files: files);
}

int? _findMatchingDivEnd(String html, int from) {
  var depth = 1;
  var i = from;
  final lower = html.toLowerCase();
  while (i < html.length && depth > 0) {
    final nextOpen = lower.indexOf('<div', i);
    final nextClose = lower.indexOf('</div', i);
    if (nextClose < 0) return null;
    if (nextOpen >= 0 && nextOpen < nextClose) {
      depth++;
      final end = html.indexOf('>', nextOpen);
      i = end < 0 ? html.length : end + 1;
    } else {
      depth--;
      final end = html.indexOf('>', nextClose);
      i = end < 0 ? html.length : end + 1;
      if (depth == 0) return i;
    }
  }
  return null;
}

HtmlFileCard _fileCardFromMarkup(String openTag, String inner) {
  final name = _attr(openTag, 'data-file-name') ??
      _attr(openTag, 'data-name') ??
      _attr(openTag, 'name') ??
      _attr(inner, 'data-file-name') ??
      _linkText(inner) ??
      'ไฟล์';
  final href = _attr(openTag, 'href') ??
      _attr(openTag, 'data-src') ??
      _attr(openTag, 'src') ??
      _attr(inner, 'href') ??
      _attr(inner, 'data-src') ??
      _attr(inner, 'src');
  return HtmlFileCard(
    name: decodeHtmlEntities(name),
    href: href,
    mime: _attr(openTag, 'data-mime') ?? _attr(openTag, 'mime'),
    date: _spanText(inner, 'moai-file-card-date'),
  );
}

String? _attr(String html, String name) {
  final re = RegExp(
    '${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  );
  final m = re.firstMatch(html);
  if (m == null) return null;
  final v = (m[1] ?? m[2] ?? m[3] ?? '').trim();
  return v.isEmpty ? null : decodeHtmlEntities(v);
}

String? _linkText(String html) {
  final m = RegExp(r'<a\b[^>]*>([\s\S]*?)</a>', caseSensitive: false).firstMatch(html);
  if (m == null) return null;
  final t = stripHtmlPreview(m[1], maxLen: 240);
  return t.isEmpty ? null : t;
}

String? _spanText(String html, String className) {
  final m = RegExp(
    '<span[^>]*$className[^>]*>([\\s\\S]*?)</span>',
    caseSensitive: false,
  ).firstMatch(html);
  if (m == null) return null;
  final t = stripHtmlPreview(m[1], maxLen: 80);
  return t.isEmpty ? null : t;
}
