import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import 'nx_icons.dart';

/// Inline style flags of [NxRichTextController].
class NxRich {
  NxRich._();
  static const bold = 1;
  static const italic = 2;
  static const underline = 4;
}

final _ulRe = RegExp(r'^• ');
final _olRe = RegExp(r'^(\d+)\. ');

/// Plain text + per-character style flags / link, parsed from simple HTML.
class NxRichDoc {
  NxRichDoc(this.text, this.styles, this.links);
  final String text;
  final List<int> styles;
  final List<String?> links;
}

String _decodeEntities(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// E-mail body HTML (p / br / strong·b / em·i / u / a / ul·ol·li) → editable
/// text: paragraphs are separated by a blank line, list items start with
/// "• " or "1. ". Other tags are dropped, their text kept.
NxRichDoc parseRichHtml(String html) {
  final buf = StringBuffer();
  final styles = <int>[];
  final links = <String?>[];
  var bold = 0, italic = 0, underline = 0;
  final linkStack = <String?>[];
  final lists = <List<Object>>[]; // [ordered, counter]
  var wantNl = 0;

  int trailingNl() {
    final s = buf.toString();
    var n = 0;
    for (var i = s.length - 1; i >= 0 && s[i] == '\n'; i--) {
      n++;
    }
    return n;
  }

  void add(String t, {bool plain = false}) {
    if (t.isEmpty) return;
    if (buf.isNotEmpty && wantNl > 0) {
      final have = trailingNl();
      for (var i = have; i < wantNl; i++) {
        buf.write('\n');
        styles.add(0);
        links.add(null);
      }
    }
    wantNl = 0;
    final st = plain ? 0 : (bold > 0 ? NxRich.bold : 0) | (italic > 0 ? NxRich.italic : 0) | (underline > 0 ? NxRich.underline : 0);
    final link = plain ? null : (linkStack.isEmpty ? null : linkStack.last);
    buf.write(t);
    for (var i = 0; i < t.length; i++) {
      styles.add(st);
      links.add(link);
    }
  }

  final tokens = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|<!--[\s\S]*?-->|([^<]+)|<').allMatches(html);
  for (final m in tokens) {
    final text = m[4];
    if (text != null) {
      var t = _decodeEntities(text.replaceAll(RegExp(r'\s+'), ' '));
      final s = buf.toString();
      if (s.isEmpty || s.endsWith('\n') || wantNl > 0) t = t.trimLeft();
      add(t);
      continue;
    }
    final name = m[2]?.toLowerCase();
    if (name == null) continue;
    final close = m[1] == '/';
    switch (name) {
      case 'p' || 'div' || 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' || 'blockquote' || 'table' || 'tr':
        if (buf.isNotEmpty) wantNl = wantNl < 2 ? 2 : wantNl;
      case 'br':
        if (wantNl > 0) {
          add('\n', plain: true);
        } else {
          buf.write('\n');
          styles.add(0);
          links.add(null);
        }
      case 'strong' || 'b':
        bold += close ? -1 : 1;
      case 'em' || 'i':
        italic += close ? -1 : 1;
      case 'u':
        underline += close ? -1 : 1;
      case 'a':
        if (close) {
          if (linkStack.isNotEmpty) linkStack.removeLast();
        } else {
          final href = RegExp(r'''href\s*=\s*["']([^"']*)["']''', caseSensitive: false).firstMatch(m[3] ?? '')?[1];
          linkStack.add(href == null || href.isEmpty ? null : _decodeEntities(href));
        }
      case 'ul' || 'ol':
        if (close) {
          if (lists.isNotEmpty) lists.removeLast();
          if (lists.isEmpty) wantNl = 2;
        } else {
          lists.add([name == 'ol', 0]);
          if (buf.isNotEmpty) wantNl = wantNl < 2 ? 2 : wantNl;
        }
      case 'li':
        if (!close) {
          if (buf.isNotEmpty && wantNl < 1) wantNl = 1;
          final l = lists.isEmpty ? <Object>[false, 0] : lists.last;
          l[1] = (l[1] as int) + 1;
          add(l[0] == true ? '${l[1]}. ' : '• ', plain: true);
        }
    }
    if (bold < 0) bold = 0;
    if (italic < 0) italic = 0;
    if (underline < 0) underline = 0;
  }
  // Trim trailing blank lines.
  var s = buf.toString();
  var end = s.length;
  while (end > 0 && (s[end - 1] == '\n' || s[end - 1] == ' ')) {
    end--;
  }
  s = s.substring(0, end);
  return NxRichDoc(s, styles.sublist(0, end), links.sublist(0, end));
}

/// A [TextEditingController] that keeps bold / italic / underline / link per
/// character, draws them, and reads / writes e-mail HTML. Lists are text
/// lines starting with "• " or "1. " (Enter continues them; Enter on an
/// empty item ends the list).
class NxRichTextController extends TextEditingController {
  NxRichTextController({String html = ''}) {
    setHtml(html);
  }

  List<int> _styles = [];
  List<String?> _links = [];
  int? _pending;
  String _last = '';

  /// Style flags of each character (tests / serialisation).
  List<int> get styles => List.unmodifiable(_styles);

  void setHtml(String html) {
    final d = parseRichHtml(html);
    _styles = List.of(d.styles);
    _links = List.of(d.links);
    _pending = null;
    _last = d.text;
    super.value = TextEditingValue(text: d.text, selection: TextSelection.collapsed(offset: d.text.length));
  }

  void _syncLength(String t) {
    if (_styles.length != t.length) {
      _styles = List.filled(t.length, 0, growable: true);
      _links = List.filled(t.length, null, growable: true);
    }
  }

  int _styleBefore(int caret) {
    if (caret > 0 && caret <= _styles.length) {
      // A newline carries no style of its own: look at the line's text.
      var i = caret - 1;
      if (_last.isNotEmpty && i < _last.length && _last[i] == '\n') return 0;
      return _styles[i];
    }
    return 0;
  }

  @override
  set value(TextEditingValue v) {
    final old = _last;
    final now = v.text;
    if (now == old) {
      if (v.selection != value.selection) _pending = null;
      super.value = v;
      return;
    }
    _syncLength(old);
    var p = 0;
    final minLen = old.length < now.length ? old.length : now.length;
    while (p < minLen && old.codeUnitAt(p) == now.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < minLen - p && old.codeUnitAt(old.length - 1 - s) == now.codeUnitAt(now.length - 1 - s)) {
      s++;
    }
    final removed = old.length - p - s;
    final inserted = now.substring(p, now.length - s);
    final style = _pending ?? _styleBefore(p);
    final link = p > 0 && p + removed < old.length && _links[p - 1] != null && _links[p - 1] == _links[p + removed] ? _links[p - 1] : null;
    _styles.replaceRange(p, p + removed, List.filled(inserted.length, style));
    _links.replaceRange(p, p + removed, List.filled(inserted.length, link));
    if (inserted.isNotEmpty) _pending = null;
    var text = now;
    var sel = v.selection;
    var composing = v.composing;

    // Enter inside a list: continue it, or end it on an empty item.
    if (inserted == '\n' && removed == 0) {
      final lineStart = p == 0 ? 0 : text.lastIndexOf('\n', p - 1) + 1;
      final line = text.substring(lineStart, p);
      final ul = _ulRe.firstMatch(line);
      final ol = _olRe.firstMatch(line);
      if (ul != null || ol != null) {
        final prefixLen = (ul ?? ol)!.end;
        if (line.length == prefixLen) {
          // Empty item → drop the bullet and the new line.
          text = text.replaceRange(lineStart, p + 1, '');
          _styles.removeRange(lineStart, p + 1);
          _links.removeRange(lineStart, p + 1);
          sel = TextSelection.collapsed(offset: lineStart);
        } else {
          final next = ul != null ? '• ' : '${int.parse(ol![1]!) + 1}. ';
          text = text.replaceRange(p + 1, p + 1, next);
          _styles.insertAll(p + 1, List.filled(next.length, 0));
          _links.insertAll(p + 1, List.filled(next.length, null));
          sel = TextSelection.collapsed(offset: p + 1 + next.length);
        }
        composing = TextRange.empty;
      }
    }
    _last = text;
    super.value = TextEditingValue(text: text, selection: sel, composing: composing);
  }

  TextSelection get _sel => selection.isValid ? selection : TextSelection.collapsed(offset: text.length);

  /// Whether [flag] is on at the caret / over the whole selection.
  bool isActive(int flag) {
    final sel = _sel;
    _syncLength(text);
    if (sel.isCollapsed) return ((_pending ?? _styleBefore(sel.start)) & flag) != 0;
    var any = false;
    for (var i = sel.start; i < sel.end; i++) {
      if (text[i] == '\n') continue;
      any = true;
      if (_styles[i] & flag == 0) return false;
    }
    return any;
  }

  /// Bold / italic / underline on the selection, or for the next typed text.
  void toggle(int flag) {
    final sel = _sel;
    _syncLength(text);
    if (sel.isCollapsed) {
      _pending = (_pending ?? _styleBefore(sel.start)) ^ flag;
      notifyListeners();
      return;
    }
    final on = !isActive(flag);
    for (var i = sel.start; i < sel.end; i++) {
      if (text[i] == '\n') continue;
      _styles[i] = on ? _styles[i] | flag : _styles[i] & ~flag;
    }
    notifyListeners();
  }

  /// Removes styles and links from the selection (or the next typed text).
  void clearFormatting() {
    final sel = _sel;
    _syncLength(text);
    if (sel.isCollapsed) {
      _pending = 0;
    } else {
      for (var i = sel.start; i < sel.end; i++) {
        _styles[i] = 0;
        _links[i] = null;
      }
    }
    notifyListeners();
  }

  /// Link on the selection; with no selection the address is inserted.
  /// An empty [url] removes the link from the selection.
  void setLink(String url) {
    final sel = _sel;
    _syncLength(text);
    final u = url.trim();
    if (sel.isCollapsed) {
      if (u.isEmpty) return;
      final at = sel.start;
      final t = text.replaceRange(at, at, u);
      _styles.insertAll(at, List.filled(u.length, _styleBefore(at)));
      _links.insertAll(at, List.filled(u.length, u));
      _last = t;
      super.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: at + u.length));
      return;
    }
    for (var i = sel.start; i < sel.end; i++) {
      _links[i] = u.isEmpty ? null : u;
    }
    notifyListeners();
  }

  /// Link under the caret / selection start.
  String? get linkAtCaret {
    final i = _sel.start;
    if (i < _links.length && _links[i] != null) return _links[i];
    if (i > 0 && i - 1 < _links.length) return _links[i - 1];
    return null;
  }

  /// Bulleted ("• ") or numbered ("1. ") list on the selected lines; again to remove.
  void toggleList({required bool ordered}) {
    final sel = _sel;
    _syncLength(text);
    var t = text;
    final from = sel.start == 0 ? 0 : t.lastIndexOf('\n', sel.start - 1) + 1;
    var to = t.indexOf('\n', sel.end);
    if (to < 0) to = t.length;
    // Line starts in the range.
    final starts = <int>[from];
    for (var i = from; i < to; i++) {
      if (t[i] == '\n') starts.add(i + 1);
    }
    final re = ordered ? _olRe : _ulRe;
    final all = starts.every((s) => re.hasMatch(t.substring(s)));
    var base = sel.baseOffset, extent = sel.extentOffset;
    // Edit from the last line up so earlier offsets stay valid.
    for (var k = starts.length - 1; k >= 0; k--) {
      final s = starts[k];
      final rest = t.substring(s);
      final old = _ulRe.firstMatch(rest) ?? _olRe.firstMatch(rest);
      final oldLen = old?.end ?? 0;
      final next = all ? '' : (ordered ? '${k + 1}. ' : '• ');
      t = t.replaceRange(s, s + oldLen, next);
      _styles.replaceRange(s, s + oldLen, List.filled(next.length, 0));
      _links.replaceRange(s, s + oldLen, List.filled(next.length, null));
      final d = next.length - oldLen;
      int shift(int o) => o >= s + oldLen ? o + d : (o > s ? s + next.length : o);
      base = shift(base);
      extent = shift(extent);
    }
    _last = t;
    super.value = TextEditingValue(text: t, selection: TextSelection(baseOffset: base.clamp(0, t.length), extentOffset: extent.clamp(0, t.length)));
  }

  bool lineIsList({required bool ordered}) {
    final t = text;
    final at = _sel.start;
    final s = at == 0 ? 0 : t.lastIndexOf('\n', at - 1) + 1;
    return (ordered ? _olRe : _ulRe).hasMatch(t.substring(s));
  }

  String _inline(int a, int b) {
    final out = StringBuffer();
    var i = a;
    while (i < b) {
      var j = i + 1;
      while (j < b && _styles[j] == _styles[i] && _links[j] == _links[i]) {
        j++;
      }
      var seg = _esc(text.substring(i, j));
      final st = _styles[i];
      if (st & NxRich.underline != 0) seg = '<u>$seg</u>';
      if (st & NxRich.italic != 0) seg = '<em>$seg</em>';
      if (st & NxRich.bold != 0) seg = '<strong>$seg</strong>';
      final l = _links[i];
      if (l != null) seg = '<a href="${_esc(l)}">$seg</a>';
      out.write(seg);
      i = j;
    }
    return out.toString();
  }

  /// The message as e-mail HTML (paragraphs, line breaks, lists, styles, links).
  String toHtml() {
    final t = text;
    _syncLength(t);
    final out = StringBuffer();
    final para = <String>[];
    String? listTag;
    final items = <String>[];
    void flushPara() {
      if (para.isNotEmpty) out.write('<p>${para.join('<br>')}</p>');
      para.clear();
    }

    void flushList() {
      if (listTag != null && items.isNotEmpty) out.write('<$listTag>${items.map((x) => '<li>$x</li>').join()}</$listTag>');
      items.clear();
      listTag = null;
    }

    var start = 0;
    while (start <= t.length) {
      var end = t.indexOf('\n', start);
      if (end < 0) end = t.length;
      final line = t.substring(start, end);
      final ul = _ulRe.firstMatch(line);
      final ol = _olRe.firstMatch(line);
      if (ul != null || ol != null) {
        flushPara();
        final tag = ul != null ? 'ul' : 'ol';
        if (listTag != tag) flushList();
        listTag = tag;
        items.add(_inline(start + (ul ?? ol)!.end, end));
      } else if (line.trim().isEmpty) {
        flushPara();
        flushList();
      } else {
        flushList();
        para.add(_inline(start, end));
      }
      if (end >= t.length) break;
      start = end + 1;
    }
    flushPara();
    flushList();
    return out.toString();
  }

  /// The text with list markers, for a quick check that something was written.
  bool get isBlank => text.trim().isEmpty;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final t = text;
    if (_styles.length != t.length || t.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final linkColor = Theme.of(context).colorScheme.primary;
    final children = <TextSpan>[];
    var i = 0;
    while (i < t.length) {
      var j = i + 1;
      while (j < t.length && _styles[j] == _styles[i] && _links[j] == _links[i]) {
        j++;
      }
      final st = _styles[i];
      final link = _links[i] != null;
      children.add(TextSpan(
        text: t.substring(i, j),
        style: TextStyle(
          fontWeight: st & NxRich.bold != 0 ? FontWeight.w700 : null,
          fontStyle: st & NxRich.italic != 0 ? FontStyle.italic : null,
          decoration: st & NxRich.underline != 0 || link ? TextDecoration.underline : null,
          color: link ? linkColor : null,
        ),
      ));
      i = j;
    }
    return TextSpan(style: style, children: children);
  }
}

/// Opens the link dialog for the caret / selection of [c].
Future<void> nxRichEditLink(BuildContext context, NxRichTextController c, {FocusNode? focus}) async {
  final ctrl = TextEditingController(text: c.linkAtCaret ?? 'https://');
  final url = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('ลิงก์')),
      content: TextField(
        key: const ValueKey('rte-link-url'),
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'https://…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('เอาลิงก์ออก'))),
        FilledButton(key: const ValueKey('rte-link-ok'), onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('ตกลง'))),
      ],
    ),
  );
  ctrl.dispose();
  if (url == null) return;
  final u = url.trim() == 'https://' ? '' : url.trim();
  c.setLink(u.isEmpty || RegExp(r'^(https?:|mailto:|tel:)', caseSensitive: false).hasMatch(u) ? u : 'https://$u');
  focus?.requestFocus();
}

/// Formatting buttons for [NxRichTextController] (bold, italic, underline,
/// bullets, numbering, link, clear formatting) — inside [NxRichTextEditor]
/// or docked on its own (e.g. above the keyboard in a mail composer).
class NxRichToolbar extends StatefulWidget {
  const NxRichToolbar({super.key, required this.controller, this.focusNode, this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2), this.trailing});
  final NxRichTextController controller;

  /// Focus returned to the text after the link dialog.
  final FocusNode? focusNode;
  final EdgeInsets padding;
  final List<Widget>? trailing;

  @override
  State<NxRichToolbar> createState() => _NxRichToolbarState();
}

class _NxRichToolbarState extends State<NxRichToolbar> {
  NxRichTextController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(NxRichToolbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget b(String key, IconData icon, String tip, bool active, VoidCallback onTap) => IconButton(
      key: ValueKey('rte-$key'),
      tooltip: tr(tip),
      visualDensity: VisualDensity.compact,
      isSelected: active,
      style: IconButton.styleFrom(backgroundColor: active ? cs.primary.withValues(alpha: 0.14) : null, foregroundColor: active ? cs.primary : null),
      onPressed: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      icon: Icon(icon, size: 20),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Row(children: [
        b('bold', NxI.textB, 'ตัวหนา', _c.isActive(NxRich.bold), () => _c.toggle(NxRich.bold)),
        b('italic', NxI.textItalic, 'ตัวเอียง', _c.isActive(NxRich.italic), () => _c.toggle(NxRich.italic)),
        b('underline', NxI.textUnderline, 'ขีดเส้นใต้', _c.isActive(NxRich.underline), () => _c.toggle(NxRich.underline)),
        const SizedBox(width: 4),
        b('ul', NxI.listBullets, 'รายการสัญลักษณ์', _c.lineIsList(ordered: false), () => _c.toggleList(ordered: false)),
        b('ol', NxI.listNumbers, 'รายการลำดับเลข', _c.lineIsList(ordered: true), () => _c.toggleList(ordered: true)),
        b('link', NxI.link, 'ลิงก์', _c.linkAtCaret != null, () => nxRichEditLink(context, _c, focus: widget.focusNode)),
        b('clear', NxI.textTSlash, 'ล้างรูปแบบ', false, _c.clearFormatting),
        ...?widget.trailing,
      ]),
    );
  }
}

/// Toolbar + text area for [NxRichTextController]. [bordered] false and
/// [showToolbar] false give a bare text area (the toolbar docked elsewhere).
class NxRichTextEditor extends StatefulWidget {
  const NxRichTextEditor({
    super.key,
    required this.controller,
    this.minLines = 6,
    this.hint,
    this.fieldKey,
    this.focusNode,
    this.bordered = true,
    this.showToolbar = true,
    this.enabled = true,
    this.contentPadding = const EdgeInsets.fromLTRB(12, 10, 12, 12),
    this.style,
  });
  final NxRichTextController controller;
  final int minLines;
  final String? hint;
  final Key? fieldKey;
  final FocusNode? focusNode;
  final bool bordered;
  final bool showToolbar;
  final bool enabled;
  final EdgeInsets contentPadding;
  final TextStyle? style;

  @override
  State<NxRichTextEditor> createState() => _NxRichTextEditorState();
}

class _NxRichTextEditorState extends State<NxRichTextEditor> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(NxRichTextEditor old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_changed);
      _focus.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focus,
      enabled: widget.enabled,
      minLines: widget.minLines,
      maxLines: null,
      style: widget.style,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      onTap: () => setState(() {}),
      decoration: InputDecoration(
        hintText: widget.hint == null ? null : tr(widget.hint!),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        contentPadding: widget.contentPadding,
      ),
    );
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showToolbar) ...[
        NxRichToolbar(controller: widget.controller, focusNode: _focus),
        Divider(height: 1, color: cs.outlineVariant),
      ],
      field,
    ]);
    if (!widget.bordered) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _focus.hasFocus ? cs.primary : cs.outlineVariant),
      ),
      child: body,
    );
  }
}
