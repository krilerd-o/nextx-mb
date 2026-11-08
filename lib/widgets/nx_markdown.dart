import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../core/effects.dart';
import '../core/i18n.dart';
import 'nx_icons.dart';
import 'nx_mermaid_view.dart';

/// Markdown (GFM) like the web AI answer view (`AiAnswerView.jsx`): tables in
/// a rounded box that scrolls sideways, code blocks with a language label +
/// copy + fold, links handed to [onOpenLink], a blinking caret while streaming.
class NxMarkdown extends StatelessWidget {
  const NxMarkdown({super.key, required this.data, this.onOpenLink, this.streaming = false, this.selectable = true});

  final String data;
  final ValueChanged<String>? onOpenLink;
  final bool streaming;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodyLarge!.copyWith(height: 1.6, fontSize: 15.5);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 2),
      h1: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.35),
      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.4),
      h3: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.4),
      h1Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      a: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: cs.primary.withValues(alpha: 0.4)),
      listBullet: base,
      listIndent: 22,
      blockSpacing: 10,
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: 13.5,
        backgroundColor: cs.surfaceContainerHighest,
        color: cs.onSurface,
      ),
      blockquote: base.copyWith(color: cs.onSurfaceVariant),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(left: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      // Tables: intrinsic columns → horizontal scroll, rounded border, tinted header.
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableHead: base.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      tableBody: base.copyWith(fontSize: 14, height: 1.45),
      tableBorder: TableBorder.all(color: cs.outlineVariant.withValues(alpha: 0.7), width: 0.8, borderRadius: BorderRadius.circular(12)),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      tableHeadCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      tableCellsDecoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.55)),
      tableScrollbarThumbVisibility: false,
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant, width: 1))),
    );
    final text = streaming ? '$data ▍' : data;
    return MarkdownBody(
      data: text,
      selectable: selectable && !streaming,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      builders: {'pre': _CodeBuilder()},
      onTapLink: (_, href, _) {
        if (href != null && href.isNotEmpty) onOpenLink?.call(href);
      },
      imageBuilder: (uri, title, alt) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text(alt ?? '', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

class _CodeBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    var lang = '';
    var code = element.textContent;
    final child = element.children?.firstOrNull;
    if (child is md.Element) {
      final cls = child.attributes['class'] ?? '';
      if (cls.startsWith('language-')) lang = cls.substring(9);
      code = child.textContent;
    }
    return NxCodeBlock(code: code.replaceAll(RegExp(r'\n$'), ''), language: lang);
  }
}

/// Code block with language label, copy and fold (web `AiCodeBlock`). JSON is
/// pretty-printed; `mermaid` shows the source with a diagram hint.
class NxCodeBlock extends StatefulWidget {
  const NxCodeBlock({super.key, required this.code, this.language = ''});
  final String code;
  final String language;

  @override
  State<NxCodeBlock> createState() => _NxCodeBlockState();
}

class _NxCodeBlockState extends State<NxCodeBlock> {
  bool _open = false;
  bool _copied = false;

  String get _lang {
    final l = widget.language.toLowerCase();
    if (l.isNotEmpty) return l;
    final t = widget.code.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) return 'json';
    return '';
  }

  String get _code {
    if (_lang != 'json') return widget.code;
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(widget.code));
    } catch (_) {
      return widget.code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final code = _code;
    final lines = '\n'.allMatches(code).length + 1;
    final long = lines > 16;
    final hl = HighlightView(
      code,
      language: _lang.isEmpty || _lang == 'mermaid' ? 'plaintext' : _lang,
      theme: {
        ...(dark ? atomOneDarkTheme : atomOneLightTheme),
        'root': TextStyle(backgroundColor: Colors.transparent, color: dark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937)),
      },
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
    );
    return Container(
      key: const ValueKey('nx-code-block'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(children: [
            Text(_lang.isEmpty ? 'code' : _lang, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (long)
              IconButton(
                tooltip: tr(_open ? 'ย่อ' : 'ขยาย'),
                visualDensity: VisualDensity.compact,
                icon: Icon(_open ? NxI.caretUp : NxI.caretDown, size: 16),
                onPressed: () => setState(() => _open = !_open),
              ),
            if (_lang == 'mermaid')
              TextButton.icon(
                key: const ValueKey('nx-mermaid-view'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NxMermaidView(code: widget.code))),
                icon: const Icon(NxI.chartBar, size: 14),
                label: Text(tr('ดูไดอะแกรม'), style: const TextStyle(fontSize: 12)),
              ),
            TextButton.icon(
              key: const ValueKey('nx-code-copy'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                HapticFeedback.selectionClick();
                if (!mounted) return;
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
              icon: Icon(_copied ? NxI.check : NxI.copySimple, size: 14),
              label: Text(tr(_copied ? 'คัดลอกแล้ว' : 'คัดลอก'), style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: long && !_open ? 16 * 19.5 : double.infinity),
          child: ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: hl,
            ),
          ),
        ),
      ]),
    );
  }
}

/// True when [s] uses markdown the plain text view would show raw.
bool looksLikeMarkdown(String s) =>
    RegExp(r'(\*\*[^*]+\*\*)|(^#{1,6}\s)|(^\s*[-*]\s)|(^\s*\d+\.\s)|(^\|.*\|\s*$)|(`[^`]+`)', multiLine: true).hasMatch(s);

/// Markdown that types itself in (home AI summary); all at once when effects are off.
class NxRevealMarkdown extends StatelessWidget {
  const NxRevealMarkdown({super.key, required this.data, this.charsPerSecond = 220});
  final String data;
  final int charsPerSecond;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true || Effects.of(context) == EffectsLevel.off;
    if (still) return NxMarkdown(data: data, selectable: false);
    final ms = (data.length * 1000 / charsPerSecond).clamp(300, 4000).round();
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: data.length),
      duration: Duration(milliseconds: ms),
      builder: (context, n, _) => NxMarkdown(data: data.substring(0, n), streaming: n < data.length, selectable: false),
    );
  }
}
