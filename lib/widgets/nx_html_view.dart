import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/html_display.dart';
import 'nx_icons.dart';

class NxHtmlView extends StatelessWidget {
  const NxHtmlView({
    super.key,
    required this.html,
    this.style,
    this.baseUrl,
    this.onOpenUrl,
  });

  final String html;
  final TextStyle? style;
  final String? baseUrl;
  final Future<void> Function(String url)? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = style ?? theme.textTheme.bodyMedium;
    final resolvedBase = baseUrl ?? _baseUrlOf(context);
    if (!looksLikeHtmlString(html)) {
      final plain = decodeHtmlEntities(html);
      if (plain.trim().isEmpty) {
        return Text('—', style: bodyStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant));
      }
      return SelectableText(plain, style: bodyStyle);
    }
    final prepared = prepareHtml(html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stripHtmlPreview(prepared.body).isNotEmpty)
          _HtmlBody(
            html: prepared.body,
            style: bodyStyle,
            baseUrl: resolvedBase,
            onOpenUrl: onOpenUrl ?? _launch,
          ),
        for (final file in prepared.files) ...[
          const SizedBox(height: 8),
          _FileChip(
            card: file,
            baseUrl: resolvedBase,
            onOpenUrl: onOpenUrl ?? _launch,
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
                    Text(card.name, style: theme.textTheme.titleSmall),
                    if (card.date != null)
                      Text(
                        card.date!,
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
  });

  final String html;
  final TextStyle? style;
  final String? baseUrl;
  final Future<void> Function(String url)? onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final nodes = _parseHtmlBlocks(html);
    if (nodes.isEmpty) {
      final preview = stripHtmlPreview(html);
      if (preview.isEmpty) return const SizedBox.shrink();
      return SelectableText(preview, style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) _block(context, node),
      ],
    );
  }

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
                          node.tag == 'ol' ? '${i + 1}.' : '•',
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Image.network(url, height: 160, fit: BoxFit.contain, errorBuilder: (_, __, ___) {
            return Text(node.attrs['alt'] ?? url, style: style);
          }),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _inline(context, node, heading: node.tag.startsWith('h')),
        );
    }
  }

  Widget _inline(BuildContext context, _HtmlNode node, {bool heading = false}) {
    final theme = Theme.of(context);
    final base = heading
        ? (style ?? theme.textTheme.bodyMedium)?.copyWith(fontWeight: FontWeight.w600)
        : style;
    final spans = <InlineSpan>[];
    _spans(node, base, spans, const _InlineStyle(), theme.colorScheme.primary);
    if (spans.isEmpty) return const SizedBox.shrink();
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }

  void _spans(_HtmlNode node, TextStyle? base, List<InlineSpan> out, _InlineStyle st, Color linkColor) {
    if (node.tag == '#text') {
      final t = decodeHtmlEntities(node.text);
      if (t.isEmpty) return;
      out.add(
        TextSpan(
          text: t,
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
      out.add(const TextSpan(text: '\n'));
      return;
    }
    var next = st;
    if (node.tag == 'b' || node.tag == 'strong') next = st.copyWith(bold: true);
    if (node.tag == 'i' || node.tag == 'em') next = st.copyWith(italic: true);
    if (node.tag == 'u') next = st.copyWith(underline: true);
    if (node.tag == 'a') next = st.copyWith(link: true, href: node.attrs['href'] ?? st.href);
    for (final c in node.children) {
      _spans(c, base, out, next, linkColor);
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
  });
  final bool bold;
  final bool italic;
  final bool underline;
  final bool link;
  final String? href;
  _InlineStyle copyWith({bool? bold, bool? italic, bool? underline, bool? link, String? href}) {
    return _InlineStyle(
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

final _blockTags = {'p', 'div', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'pre'};

List<_HtmlNode> _parseHtmlBlocks(String html) {
  final root = _parseFragment(html);
  final blocks = <_HtmlNode>[];
  void walk(_HtmlNode n, List<_HtmlNode> inlineAcc) {
    if (_blockTags.contains(n.tag)) {
      _flushInline(inlineAcc, blocks);
      if (n.tag == 'ul' || n.tag == 'ol') {
        final items = n.children.where((c) => c.tag == 'li').toList();
        blocks.add(_HtmlNode(n.tag, children: items.isEmpty ? n.children : items));
      } else if (n.tag == 'li') {
        blocks.add(_HtmlNode('p', children: n.children));
      } else {
        blocks.add(_HtmlNode(n.tag == 'div' ? 'p' : n.tag, children: n.children, attrs: n.attrs));
      }
      return;
    }
    if (n.tag == 'img') {
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
          const {'br', 'img', 'hr', 'input', 'meta', 'link'}.contains(tag);
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
