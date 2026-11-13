/// Comment body helpers — the same wire format as the NEXTX web CommentComposer
/// (`frontend/src/ui/commentBody.js`):
///
/// * composer text → HTML: text escaped, line breaks → `<br>`, each picked
///   @mention → `<span data-type="mention" data-id="12" class="moai-mention">@Name</span>`
///   (the backend reads `data-id` to notify; `@[12:Name]` tokens are accepted too);
/// * HTML → editable text + the mentions it holds (for editing);
/// * HTML → display segments (text / mention chip / link / line break).
library;

const _mentionSpanRe =
    r'''<span[^>]*\bdata-type=["']mention["'][^>]*>([\s\S]*?)</span>''';
final _mentionSpan = RegExp(_mentionSpanRe, caseSensitive: false);
final _dataId = RegExp(r'''\bdata-id=["'](\d+)["']''', caseSensitive: false);
final _token = RegExp(r'@\[(\d+):([^\]]+)\]');

/// `http(s)://…` in plain text (trailing punctuation peeled off, like the web).
final kCommentUrlRe = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

String decodeCommentEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
    .replaceAllMapped(RegExp(r'&#x([0-9a-f]+);', caseSensitive: false), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// Peels `),.;:!?]` off the end of a matched URL → (url, trailing text).
(String, String) peelCommentUrl(String raw) {
  var url = raw;
  var trailing = '';
  while (url.length > 8 && RegExp(r'[),.;:!?\]]$').hasMatch(url)) {
    trailing = url.substring(url.length - 1) + trailing;
    url = url.substring(0, url.length - 1);
  }
  return (url, trailing);
}

/// URLs in a comment (plain text or HTML), in order, without duplicates.
List<String> commentUrls(String textOrHtml) {
  final plain = textOrHtml.contains('<') ? commentFromHtml(textOrHtml).text : textOrHtml;
  final out = <String>[];
  for (final m in kCommentUrlRe.allMatches(plain)) {
    final (url, _) = peelCommentUrl(m.group(0)!);
    if (!out.contains(url)) out.add(url);
  }
  return out;
}

/// Composer text → stored HTML. [mentions] maps a picked display name (without
/// `@`) to its user id; each `@Name` still in the text becomes a mention span.
String commentToHtml(String text, {Map<String, String> mentions = const {}}) {
  var html = _escape(text.trim());
  // Tokens typed / pasted in the web format.
  html = html.replaceAllMapped(_token, (m) => _span(m.group(1)!, m.group(2)!));
  final names = mentions.keys.where((n) => n.trim().isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    final id = mentions[name]!.replaceAll(RegExp(r'\D'), '');
    if (id.isEmpty) continue;
    final esc = RegExp.escape('@${_escape(name)}');
    // Not inside a span we already produced (data-…>@Name</span>).
    html = html.replaceAllMapped(RegExp('(?<![>\\w])$esc(?![\\w])'), (_) => _span(id, name));
  }
  return html.replaceAll('\n', '<br>');
}

String _span(String id, String name) => '<span data-type="mention" data-id="$id" class="moai-mention">@${_escape(name).replaceAll('@', '')}</span>';

/// Stored HTML → (editable text with `@Name`, picked mentions name → id).
({String text, Map<String, String> mentions}) commentFromHtml(String html) {
  final mentions = <String, String>{};
  var s = html;
  s = s.replaceAllMapped(_mentionSpan, (m) {
    final id = _dataId.firstMatch(m.group(0)!)?.group(1);
    final name = decodeCommentEntities(m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '')).trim().replaceFirst(RegExp(r'^@'), '');
    if (id == null || name.isEmpty) return m.group(0)!;
    mentions[name] = id;
    return '@$name';
  });
  s = s.replaceAllMapped(_token, (m) {
    mentions[m.group(2)!] = m.group(1)!;
    return '@${m.group(2)}';
  });
  s = s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*<p[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = decodeCommentEntities(s).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return (text: s, mentions: mentions);
}

/// User ids mentioned in stored HTML (span `data-id` or `@[id:Name]`).
List<String> commentMentionIds(String html) {
  final ids = <String>[];
  for (final m in _mentionSpan.allMatches(html)) {
    final id = _dataId.firstMatch(m.group(0)!)?.group(1);
    if (id != null && !ids.contains(id)) ids.add(id);
  }
  for (final m in _token.allMatches(html)) {
    if (!ids.contains(m.group(1)!)) ids.add(m.group(1)!);
  }
  return ids;
}

enum CommentSegKind { text, mention, url }

class CommentSeg {
  const CommentSeg(this.kind, this.value, {this.id});
  final CommentSegKind kind;
  final String value;

  /// User id of a mention.
  final String? id;

  @override
  String toString() => '${kind.name}:$value${id == null ? '' : '#$id'}';
}

/// Markup a plain text renderer cannot show (lists, tables, formatting) → use the HTML view.
bool commentNeedsRichView(String html) {
  final s = html.replaceAll(_mentionSpan, '');
  return RegExp(r'<(table|ul|ol|li|h[1-6]|b|strong|i|em|u|blockquote|pre|code|a)\b', caseSensitive: false).hasMatch(s);
}

/// Display segments of a comment: text, mention chips and links (line breaks kept in text).
List<CommentSeg> commentSegments(String html) {
  final parsed = commentFromHtml(html);
  final text = parsed.text;
  final byName = parsed.mentions;
  if (text.isEmpty) return const [];
  final out = <CommentSeg>[];
  // Mentions first: split on "@Name" for every known name (longest first).
  final names = byName.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  final mentionRe = names.isEmpty ? null : RegExp(names.map((n) => RegExp.escape('@$n')).join('|'));
  void addText(String t) {
    var last = 0;
    for (final m in kCommentUrlRe.allMatches(t)) {
      if (m.start > last) out.add(CommentSeg(CommentSegKind.text, t.substring(last, m.start)));
      final (url, trailing) = peelCommentUrl(m.group(0)!);
      out.add(CommentSeg(CommentSegKind.url, url));
      if (trailing.isNotEmpty) out.add(CommentSeg(CommentSegKind.text, trailing));
      last = m.end;
    }
    if (last < t.length) out.add(CommentSeg(CommentSegKind.text, t.substring(last)));
  }

  if (mentionRe == null) {
    addText(text);
  } else {
    var last = 0;
    for (final m in mentionRe.allMatches(text)) {
      if (m.start > last) addText(text.substring(last, m.start));
      final name = m.group(0)!.substring(1);
      out.add(CommentSeg(CommentSegKind.mention, name, id: byName[name]));
      last = m.end;
    }
    if (last < text.length) addText(text.substring(last));
  }
  return out;
}

/// `@query` right before the caret (null when not typing a mention).
({int start, String query})? mentionQueryAt(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  final before = text.substring(0, caret);
  final m = RegExp(r'(^|[\s ])@([^\s@]{0,40})$').firstMatch(before);
  if (m == null) return null;
  return (start: m.start + m.group(1)!.length, query: m.group(2)!);
}

/// Display name of a user row (`first_name last_name` → user_name → email), like the web.
String mentionUserLabel(Map<String, dynamic> u) {
  final full = [u['first_name'], u['last_name']].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ').trim();
  if (full.isNotEmpty) return full;
  for (final k in ['user_name', 'name', 'email1', 'email']) {
    final v = '${u[k] ?? ''}'.trim();
    if (v.isNotEmpty) return v;
  }
  return 'User ${u['id']}';
}

/// Users matching [query] (name / username / e-mail), at most [limit], no duplicates.
List<Map<String, dynamic>> filterMentionUsers(List<Map<String, dynamic>> users, String query, {int limit = 12, String? excludeId}) {
  final q = query.trim().toLowerCase();
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final u in users) {
    final id = '${u['id'] ?? ''}';
    if (id.isEmpty || seen.contains(id) || id == excludeId) continue;
    final hay = [mentionUserLabel(u), u['user_name'], u['email1'], u['email'], u['first_name_th'], u['last_name_th']]
        .where((v) => v != null)
        .join(' ')
        .toLowerCase();
    if (q.isNotEmpty && !hay.contains(q)) continue;
    seen.add(id);
    out.add(u);
    if (out.length >= limit) break;
  }
  return out;
}

/// One comment with its replies (oldest first), for the thread view.
class CommentNode {
  CommentNode(this.comment, this.depth);
  final Map<String, dynamic> comment;
  final int depth;
  final List<CommentNode> replies = [];

  String get id => '${comment['id']}';

  /// Every reply below this comment (any depth).
  int get replyCount => replies.fold(0, (n, r) => n + 1 + r.replyCount);

  Iterable<CommentNode> get descendants sync* {
    for (final r in replies) {
      yield r;
      yield* r.descendants;
    }
  }
}

DateTime _at(Map<String, dynamic> c) => DateTime.tryParse('${c['created_at'] ?? c['createdAt'] ?? ''}') ?? DateTime(0);

/// Comments → tree (roots oldest first like the web thread; orphans become roots;
/// cycles are broken). [maxDepth] caps nesting: deeper replies hang under the last allowed level.
List<CommentNode> buildCommentTree(List<Map<String, dynamic>> rows, {int maxDepth = 5}) {
  final byId = {for (final r in rows) '${r['id']}': r};
  String? parentOf(Map<String, dynamic> r) {
    final p = r['parent_id'] ?? r['parentId'] ?? r['replyToId'];
    final k = p == null ? '' : '$p';
    return k.isEmpty || k == 'null' || !byId.containsKey(k) || k == '${r['id']}' ? null : k;
  }

  final children = <String, List<Map<String, dynamic>>>{};
  final roots = <Map<String, dynamic>>[];
  for (final r in rows) {
    // Walk up to detect cycles (a → b → a): treat as root.
    var p = parentOf(r);
    final seen = <String>{'${r['id']}'};
    var cyclic = false;
    while (p != null) {
      if (!seen.add(p)) {
        cyclic = true;
        break;
      }
      p = parentOf(byId[p]!);
    }
    final parent = cyclic ? null : parentOf(r);
    if (parent == null) {
      roots.add(r);
    } else {
      (children[parent] ??= []).add(r);
    }
  }
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) => _at(a).compareTo(_at(b));
  CommentNode build(Map<String, dynamic> c, int depth) {
    final node = CommentNode(c, depth);
    final kids = [...?children['${c['id']}']]..sort(cmp);
    for (final k in kids) {
      final child = build(k, depth + 1 < maxDepth ? depth + 1 : depth);
      node.replies.add(child);
    }
    return node;
  }

  roots.sort(cmp);
  return [for (final r in roots) build(r, 0)];
}
