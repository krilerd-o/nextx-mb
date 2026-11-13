import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/html_display.dart';
import 'nx_attachments.dart' show openNxImageViewer;
import 'nx_icons.dart';
import 'nx_media.dart';
import 'nx_rich_code.dart';
import '../core/i18n.dart';

class NxHtmlView extends StatelessWidget {
  const NxHtmlView({
    super.key,
    required this.html,
    this.style,
    this.baseUrl,
    this.onOpenUrl,
    this.selectable = true,
  });

  final String html;
  final TextStyle? style;
  final String? baseUrl;
  final Future<void> Function(String url)? onOpenUrl;

  /// false = plain text (chat bubbles: long press opens the message menu instead of selecting).
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = style ?? theme.textTheme.bodyMedium;
    final resolvedBase = baseUrl ?? _baseUrlOf(context);
    // HTML saved escaped (`a&lt;br&gt;b`) shows its tags as text: render the
    // decoded markup instead when it is real HTML.
    var html = this.html;
    if (!html.contains('<') && html.contains('&lt;')) {
      final decoded = decodeHtmlEntities(html);
      if (looksLikeHtmlString(decoded) && decoded.contains('<')) html = decoded;
    }
    if (!looksLikeHtmlString(html)) {
      final coded = backtickCodeToHtml(decodeHtmlEntities(html));
      if (coded != null) {
        return _HtmlBody(html: coded, style: bodyStyle, baseUrl: resolvedBase, onOpenUrl: (u) => (onOpenUrl ?? _launch)(u), selectable: selectable);
      }
      final plain = decodeHtmlEntities(html);
      if (plain.trim().isEmpty) {
        return Text(tr('—'), style: bodyStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant));
      }
      return selectable ? SelectableText(tr(plain), style: bodyStyle) : Text(tr(plain), style: bodyStyle);
    }
    final prepared = prepareHtml(html);
    // Links to videos / images open in the app's player / viewer.
    Future<void> open(String url) async {
      if (nxIsVideoUrl(url)) return openNxVideoPlayer(context, url);
      if (RegExp(r'\.(png|jpe?g|gif|webp|bmp|heic)$', caseSensitive: false).hasMatch(url.split('?').first)) {
        return openNxImageViewer(context, [url], 0);
      }
      return (onOpenUrl ?? _launch)(url);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stripHtmlPreview(prepared.body).isNotEmpty)
          _HtmlBody(
            html: prepared.body,
            style: bodyStyle,
            baseUrl: resolvedBase,
            onOpenUrl: open,
            selectable: selectable,
          ),
        for (final file in prepared.files) ...[
          const SizedBox(height: 8),
          _FileChip(
            card: file,
            baseUrl: resolvedBase,
            onOpenUrl: open,
          ),
        ],
      ],
    );
  }

  static String? _baseUrlOf(BuildContext context) {
    try {
      return context.read<AppConfig>().apiClient.baseUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({
    required this.card,
    this.baseUrl,
    this.onOpenUrl,
  });

  final HtmlFileCard card;
  final String? baseUrl;
  final Future<void> Function(String url)? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final href = card.href == null ? null : resolveHtmlUrl(card.href!, baseUrl);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: href == null || href.isEmpty ? null : () => onOpenUrl?.call(href),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(NxI.paperclip, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(card.name), style: theme.textTheme.titleSmall),
                    if (card.date != null)
                      Text(
                        tr(card.date!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (href != null) Icon(NxI.arrowSquareOut, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _HtmlBody extends StatelessWidget {
  const _HtmlBody({
    required this.html,
    required this.style,
    this.baseUrl,
    this.onOpenUrl,
    this.selectable = true,
  });

  final String html;
  final TextStyle? style;
  final String? baseUrl;
  final Future<void> Function(String url)? onOpenUrl;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final nodes = _parseHtmlBlocks(html);
    if (nodes.isEmpty) {
      final preview = stripHtmlPreview(html);
      if (preview.isEmpty) return const SizedBox.shrink();
      return selectable ? SelectableText(tr(preview), style: style) : Text(tr(preview), style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) _block(context, node),
      ],
    );
  }

  /// Every image in this text (for swiping in the viewer).
  List<String> _imageUrls() => [
        for (final m in RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false).allMatches(html))
          if (!m.group(1)!.startsWith('data:') && !nxIsVideoUrl(m.group(1)!)) resolveHtmlUrl(m.group(1)!, baseUrl),
      ];

  Widget _block(BuildContext context, _HtmlNode node) {
    switch (node.tag) {
      case 'ul':
      case 'ol':
        return Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < node.children.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text(
                          tr(node.tag == 'ol' ? '${i + 1}.' : '•'),
                          style: style,
                        ),
                      ),
                      Expanded(child: _inline(context, node.children[i])),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'img':
        final src = node.attrs['src'];
        if (src == null || src.isEmpty) return const SizedBox.shrink();
        final url = resolveHtmlUrl(src, baseUrl);
        if (nxIsVideoUrl(url)) return Padding(padding: const EdgeInsets.only(bottom: 8), child: NxVideoTile(url: url));
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // Tap = full-screen viewer (zoom, swipe through this text's images, download).
          child: GestureDetector(
            key: ValueKey('html-img-$url'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final all = _imageUrls();
              openNxImageViewer(context, all, all.indexOf(url).clamp(0, all.length - 1));
            },
            // Tappable even while the picture is still loading.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120, minHeight: 48),
              child: Image(image: ResizeImage(CachedNetworkImageProvider(url), height: 480, policy: ResizeImagePolicy.fit), height: 160, fit: BoxFit.contain, errorBuilder: (_, _, _) {
                return Text(tr(node.attrs['alt'] ?? url), style: style);
              }),
            ),
          ),
        );
      case 'pre':
        return _codeBlock(node);
      case 'table':
        return _table(context, node);
      case 'video':
        var src = node.attrs['src'] ?? '';
        if (src.isEmpty) {
          for (final c in node.children) {
            if (c.tag == 'source' && (c.attrs['src'] ?? '').isNotEmpty) {
              src = c.attrs['src']!;
              break;
            }
          }
        }
        if (src.isEmpty) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: NxVideoTile(url: resolveHtmlUrl(src, baseUrl)));
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _inline(context, node, heading: node.tag.startsWith('h')),
        );
    }
  }

  /// `<pre><code class="language-sql" data-line-numbers data-word-wrap>` (TipTap) → web-style block.
  Widget _codeBlock(_HtmlNode pre) {
    _HtmlNode? code;
    for (final c in pre.children) {
      if (c.tag == 'code') {
        code = c;
        break;
      }
    }
    String attr(String name) => (code?.attrs[name] ?? '').isNotEmpty ? code!.attrs[name]! : (pre.attrs[name] ?? '');
    bool flag(String name, bool fallback) {
      final v = attr(name).toLowerCase();
      if (v == 'false' || v == '0') return false;
      if (v == 'true' || v == '1') return true;
      return fallback;
    }

    var lang = attr('data-saved-language');
    if (lang.isEmpty) lang = attr('data-language');
    if (lang.isEmpty) {
      final m = RegExp(r'(?:^|\s)language-([\w#+.-]+)', caseSensitive: false).firstMatch('${code?.attrs['class'] ?? ''} ${pre.attrs['class'] ?? ''}');
      lang = m?[1] ?? '';
    }
    final text = decodeHtmlEntities(_rawText(pre)).replaceAll(RegExp(r'\n$'), '');
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return NxRichCodeBlock(
      code: text,
      language: lang,
      lineNumbers: flag('data-line-numbers', true),
      wordWrap: flag('data-word-wrap', false),
    );
  }

  /// Text exactly as written (code keeps its spaces and line breaks).
  static String _rawText(_HtmlNode n) {
    if (n.tag == '#text') return n.text;
    if (n.tag == 'br') return '\n';
    final b = StringBuffer();
    for (final c in n.children) {
      b.write(_rawText(c));
    }
    if (n.tag == 'p' || n.tag == 'div') b.write('\n');
    return b.toString();
  }

  /// `<table>` (TipTap table): header row tinted, cells wrap at a readable width,
  /// wide tables scroll sideways.
  Widget _table(BuildContext context, _HtmlNode table) {
    final cs = Theme.of(context).colorScheme;
    final rows = <(_HtmlNode, bool)>[];
    void collect(_HtmlNode n, bool head) {
      for (final c in n.children) {
        if (c.tag == 'tr') {
          rows.add((c, head || c.children.any((x) => x.tag == 'th') && !c.children.any((x) => x.tag == 'td')));
        } else if (c.tag == 'thead' || c.tag == 'tbody' || c.tag == 'tfoot') {
          collect(c, c.tag == 'thead');
        }
      }
    }

    collect(table, false);
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.map((r) => r.$1.children.where((c) => c.tag == 'td' || c.tag == 'th').length).fold<int>(0, (a, b) => b > a ? b : a);
    if (cols == 0) return const SizedBox.shrink();
    final line = cs.outlineVariant.withValues(alpha: 0.7);
    return Padding(
      key: const ValueKey('html-table'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(horizontalInside: BorderSide(color: line), verticalInside: BorderSide(color: line)),
            children: [
              for (final (tr, head) in rows)
                TableRow(
                  decoration: head ? BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.8)) : null,
                  children: [
                    for (var i = 0; i < cols; i++)
                      Builder(builder: (context) {
                        final cells = tr.children.where((c) => c.tag == 'td' || c.tag == 'th').toList();
                        final cell = i < cells.length ? cells[i] : null;
                        return ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 64, maxWidth: 260),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: cell == null
                                ? const SizedBox.shrink()
                                : _inline(context, cell, heading: head || cell.tag == 'th'),
                          ),
                        );
                      }),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inline(BuildContext context, _HtmlNode node, {bool heading = false}) {
    final theme = Theme.of(context);
    final base = heading
        ? (style ?? theme.textTheme.bodyMedium)?.copyWith(fontWeight: FontWeight.w600)
        : style;
    final spans = <InlineSpan>[];
    _spans(node, base, spans, const _InlineStyle(), theme.colorScheme.primary, dark: theme.brightness == Brightness.dark);
    if (spans.isEmpty) return const SizedBox.shrink();
    return selectable ? SelectableText.rich(TextSpan(style: base, children: spans)) : Text.rich(TextSpan(style: base, children: spans));
  }

  void _spans(_HtmlNode node, TextStyle? base, List<InlineSpan> out, _InlineStyle st, Color linkColor, {required bool dark}) {
    if (node.tag == '#text') {
      final t = decodeHtmlEntities(node.text);
      if (t.isEmpty) return;
      if (st.code) {
        // Thin spaces stand in for the web chip's side padding.
        out.add(TextSpan(text: '\u2009$t\u2009', style: webInlineCodeStyle(base, dark: dark)));
        return;
      }
      out.add(
        TextSpan(
          text: trn(t),
          style: base?.copyWith(
            fontWeight: st.bold ? FontWeight.w700 : base.fontWeight,
            fontStyle: st.italic ? FontStyle.italic : base.fontStyle,
            decoration: st.underline || st.link ? TextDecoration.underline : base.decoration,
            color: st.link ? linkColor : base.color,
          ),
          recognizer: st.href == null
              ? null
              : (TapGestureRecognizer()
                ..onTap = () {
                  final url = resolveHtmlUrl(st.href!, baseUrl);
                  onOpenUrl?.call(url);
                }),
        ),
      );
      return;
    }
    if (node.tag == 'br') {
      out.add(TextSpan(text: tr('\n')));
      return;
    }
    var next = st;
    if (node.tag == 'b' || node.tag == 'strong') next = st.copyWith(bold: true);
    if (node.tag == 'i' || node.tag == 'em') next = st.copyWith(italic: true);
    if (node.tag == 'u') next = st.copyWith(underline: true);
    if (node.tag == 'a') next = st.copyWith(link: true, href: node.attrs['href'] ?? st.href);
    if (node.tag == 'code') next = st.copyWith(code: true);
    // Paragraphs inside one block (table cells, list items) each start a new line.
    if ((node.tag == 'p' || node.tag == 'div') && out.isNotEmpty) out.add(TextSpan(text: tr('\n')));
    for (final c in node.children) {
      _spans(c, base, out, next, linkColor, dark: dark);
    }
  }
}

class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.link = false,
    this.href,
    this.code = false,
  });
  final bool code;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool link;
  final String? href;
  _InlineStyle copyWith({bool? bold, bool? italic, bool? underline, bool? link, String? href, bool? code}) {
    return _InlineStyle(
      code: code ?? this.code,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      link: link ?? this.link,
      href: href ?? this.href,
    );
  }
}

class _HtmlNode {
  _HtmlNode(this.tag, {this.text = '', this.attrs = const {}, this.children = const []});
  final String tag;
  final String text;
  final Map<String, String> attrs;
  final List<_HtmlNode> children;
}

final _blockTags = {'p', 'div', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre', 'table'};

/// Kept whole as one block (their inner structure matters).
const _wholeBlocks = {'pre', 'table'};

List<_HtmlNode> _parseHtmlBlocks(String html) {
  final root = _parseFragment(html);
  final blocks = <_HtmlNode>[];
  void walk(_HtmlNode n, List<_HtmlNode> inlineAcc) {
    if (_blockTags.contains(n.tag)) {
      _flushInline(inlineAcc, blocks);
      if (_wholeBlocks.contains(n.tag)) {
        blocks.add(n);
      } else if (n.tag == 'ul' || n.tag == 'ol') {
        final items = n.children.where((c) => c.tag == 'li').toList();
        blocks.add(_HtmlNode(n.tag, children: items.isEmpty ? n.children : items));
      } else if (n.tag == 'li') {
        blocks.add(_HtmlNode('p', children: n.children));
      } else {
        // Images / videos inside a paragraph become their own (tappable) blocks.
        final tag = n.tag == 'div' ? 'p' : n.tag;
        var run = <_HtmlNode>[];
        for (final c in n.children) {
          if (c.tag == 'img' || c.tag == 'video' || _wholeBlocks.contains(c.tag)) {
            if (run.isNotEmpty) blocks.add(_HtmlNode(tag, children: run, attrs: n.attrs));
            run = <_HtmlNode>[];
            blocks.add(c);
          } else {
            run.add(c);
          }
        }
        if (run.isNotEmpty || n.children.isEmpty) blocks.add(_HtmlNode(tag, children: run, attrs: n.attrs));
      }
      return;
    }
    if (n.tag == 'img' || n.tag == 'video') {
      _flushInline(inlineAcc, blocks);
      blocks.add(n);
      return;
    }
    inlineAcc.add(n);
  }

  final acc = <_HtmlNode>[];
  for (final c in root.children) {
    walk(c, acc);
  }
  _flushInline(acc, blocks);
  return blocks;
}

void _flushInline(List<_HtmlNode> acc, List<_HtmlNode> blocks) {
  if (acc.isEmpty) return;
  final hasText = acc.any((n) => stripHtmlPreview(n.tag == '#text' ? n.text : 'x').isNotEmpty || n.tag != '#text');
  if (hasText) blocks.add(_HtmlNode('p', children: List.of(acc)));
  acc.clear();
}

_HtmlNode _parseFragment(String html) {
  final root = _HtmlNode('root', children: []);
  final stack = <_HtmlNode>[root];
  var i = 0;
  while (i < html.length) {
    if (html[i] == '<') {
      if (html.startsWith('<!--', i)) {
        final end = html.indexOf('-->', i + 4);
        i = end < 0 ? html.length : end + 3;
        continue;
      }
      final gt = html.indexOf('>', i);
      if (gt < 0) {
        stack.last.children.add(_HtmlNode('#text', text: html.substring(i)));
        break;
      }
      final raw = html.substring(i + 1, gt).trim();
      i = gt + 1;
      if (raw.isEmpty) continue;
      if (raw.startsWith('/')) {
        final name = raw.substring(1).trim().split(RegExp(r'\s+')).first.toLowerCase();
        for (var s = stack.length - 1; s > 0; s--) {
          if (stack[s].tag == name) {
            stack.removeRange(s, stack.length);
            break;
          }
        }
        continue;
      }
      final voidTag = raw.endsWith('/');
      final body = voidTag ? raw.substring(0, raw.length - 1).trim() : raw;
      final parts = _splitTag(body);
      final tag = parts.name;
      final node = _HtmlNode(tag, attrs: parts.attrs, children: []);
      stack.last.children.add(node);
      final isVoid = voidTag ||
          const {'br', 'img', 'hr', 'input', 'meta', 'link', 'source'}.contains(tag);
      if (!isVoid) stack.add(node);
    } else {
      final next = html.indexOf('<', i);
      final end = next < 0 ? html.length : next;
      final text = html.substring(i, end);
      if (text.isNotEmpty) stack.last.children.add(_HtmlNode('#text', text: text));
      i = end;
    }
  }
  return root;
}

({String name, Map<String, String> attrs}) _splitTag(String body) {
  final m = RegExp(r'^([^\s]+)([\s\S]*)$').firstMatch(body.trim());
  final name = (m?[1] ?? 'span').toLowerCase();
  final rest = m?[2] ?? '';
  final attrs = <String, String>{};
  for (final am in RegExp(
    r'''([:@\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
  ).allMatches(rest)) {
    attrs[am[1]!.toLowerCase()] = am[2] ?? am[3] ?? am[4] ?? '';
  }
  return (name: name, attrs: attrs);
}
