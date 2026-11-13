import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import '../core/i18n.dart';
import 'nx_icons.dart';

/// Code in rich text (task description, comments, chat, mail) drawn like the
/// web's TipTap code block (`enhanceMoaiCodeBlocksHtml.js` + `index.css`):
/// slate surface, line numbers, lowlight colours, wrap + copy at the top right.
class NxRichCodeBlock extends StatefulWidget {
  const NxRichCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.lineNumbers = true,
    this.wordWrap = false,
  });

  final String code;
  final String? language;
  final bool lineNumbers;
  final bool wordWrap;

  @override
  State<NxRichCodeBlock> createState() => _NxRichCodeBlockState();
}

class _NxRichCodeBlockState extends State<NxRichCodeBlock> {
  late bool _wrap = widget.wordWrap;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final code = widget.code.replaceAll('\t', '  ');
    const fontSize = 13.0;
    const lineHeight = 24.0; // web: text-sm leading-6
    const strut = StrutStyle(fontFamily: 'monospace', fontSize: fontSize, height: lineHeight / fontSize, forceStrutHeight: true);
    final base = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['IBMPlexSansThai'],
      fontSize: fontSize,
      height: lineHeight / fontSize,
      color: dark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
    );
    final text = SelectableText.rich(
      TextSpan(style: base, children: webCodeSpans(code, widget.language, dark: dark)),
      strutStyle: strut,
    );
    // Room on the right for the two buttons (web: pr-12).
    final padded = Padding(padding: const EdgeInsets.fromLTRB(12, 12, 48, 12), child: text);
    final lines = '\n'.allMatches(code).length + 1;
    // Numbers only line up with unwrapped lines.
    final showGutter = widget.lineNumbers && !_wrap;
    final gutter = Container(
      key: const ValueKey('nx-rich-code-gutter'),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0x660F172A) : const Color(0x66E2E8F0),
        border: Border(right: BorderSide(color: dark ? const Color(0x99475569) : const Color(0xB3E2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= lines; i++)
            SizedBox(
              height: lineHeight,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('$i', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: dark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
              ),
            ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('nx-rich-code'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xE61E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dark ? const Color(0xCC475569) : const Color(0xCCE2E8F0)),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showGutter) gutter,
              Expanded(
                child: _wrap
                    ? padded
                    : SingleChildScrollView(key: const ValueKey('nx-rich-code-scroll'), scrollDirection: Axis.horizontal, child: padded),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CodeButton(
                  key: const ValueKey('nx-rich-code-wrap'),
                  icon: NxI.wrapText,
                  tooltip: tr(_wrap ? 'ไม่ตัดบรรทัด' : 'ตัดบรรทัด'),
                  active: _wrap,
                  onTap: () => setState(() => _wrap = !_wrap),
                ),
                const SizedBox(width: 4),
                _CodeButton(
                  key: const ValueKey('nx-rich-code-copy'),
                  icon: _copied ? NxI.check : NxI.copySimple,
                  tooltip: tr(_copied ? 'คัดลอกแล้ว' : 'คัดลอกโค้ด'),
                  done: _copied,
                  onTap: _copy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeButton extends StatelessWidget {
  const _CodeButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.active = false, this.done = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = active ? (dark ? const Color(0x80172554) : const Color(0xFFEFF6FF)) : (dark ? const Color(0xFF1E293B) : Colors.white);
    final border = active ? (dark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD)) : (dark ? const Color(0xFF475569) : const Color(0xFFE2E8F0));
    final fg = done
        ? const Color(0xFF059669)
        : active
            ? (dark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB))
            : (dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569));
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: border)),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          // 32px target, drawn like the web's 28px button.
          child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 15, color: fg)),
        ),
      ),
    );
  }
}

/// Web `index.css` lowlight colours (`.moai-code-block-code .hljs-*`).
Map<String, TextStyle> webCodeTheme({required bool dark}) {
  final comment = TextStyle(color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontStyle: FontStyle.italic);
  const keyword = TextStyle(color: Color(0xFF7C3AED));
  final string = TextStyle(color: dark ? const Color(0xFF34D399) : const Color(0xFF059669));
  const number = TextStyle(color: Color(0xFFD97706));
  const attr = TextStyle(color: Color(0xFF2563EB));
  return {
    'comment': comment,
    'quote': comment,
    'keyword': keyword,
    'selector-tag': keyword,
    'built_in': keyword,
    'string': string,
    'regexp': string,
    'addition': string,
    'number': number,
    'literal': number,
    'attr': attr,
    'attribute': attr,
    'title': attr,
  };
}

const _languageAliases = {
  'js': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'html': 'xml',
  'vue': 'xml',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'yml': 'yaml',
  'py': 'python',
  'md': 'markdown',
  'csharp': 'cs',
  'c#': 'cs',
  'c++': 'cpp',
  'kt': 'kotlin',
  'rb': 'ruby',
  'ps1': 'powershell',
  'docker': 'dockerfile',
  'gql': 'graphql',
};

/// The code as coloured spans. Unknown language = auto-detect like the web
/// (`lowlight.highlightAuto`); plain text when nothing fits.
List<TextSpan> webCodeSpans(String code, String? language, {required bool dark}) {
  final theme = webCodeTheme(dark: dark);
  var lang = (language ?? '').trim().toLowerCase();
  if (lang == 'null' || lang == 'plaintext' || lang == 'text' || lang == 'plain') lang = '';
  lang = _languageAliases[lang] ?? lang;
  List<Node>? nodes;
  try {
    if (lang.isNotEmpty) {
      nodes = highlight.parse(code, language: lang).nodes;
    } else if (code.length <= 20000) {
      final r = highlight.parse(code, autoDetection: true);
      // A weak guess on prose colours random words; keep it plain then.
      if ((r.relevance ?? 0) >= 3) nodes = r.nodes;
    }
  } catch (_) {
    nodes = null;
  }
  if (nodes == null || nodes.isEmpty) return [TextSpan(text: code)];

  List<TextSpan> convert(List<Node> list) => [
        for (final n in list)
          if (n.value != null)
            TextSpan(text: n.value, style: n.className == null ? null : theme[n.className!])
          else if (n.children != null)
            TextSpan(style: n.className == null ? null : theme[n.className!], children: convert(n.children!)),
      ];
  return convert(nodes);
}

/// Inline `code` like the web (`:not(pre) > code`): monospace on a soft chip.
TextStyle webInlineCodeStyle(TextStyle? base, {required bool dark}) => (base ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['IBMPlexSansThai'],
      fontSize: (base?.fontSize ?? 14) * 0.875,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      color: dark ? const Color(0xFFE2E8F0) : const Color(0xFF212529),
      backgroundColor: dark ? const Color(0xE0334155) : const Color(0xFFF1F3F5),
      decoration: TextDecoration.none,
    );

final _fence = RegExp(r'```[ \t]*([\w#+.-]*)[ \t]*\n?([\s\S]*?)\n?```');
final _tick = RegExp(r'`([^`\n]+)`');

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Plain text typed with Markdown code marks (```` ```sql … ``` ```` and
/// `` `x` ``) as HTML the rich-text view understands; null when there are none.
String? backtickCodeToHtml(String plain) {
  if (!plain.contains('`')) return null;
  if (!_fence.hasMatch(plain) && !_tick.hasMatch(plain)) return null;
  final out = StringBuffer();
  var last = 0;
  String para(String s) {
    final t = s.replaceAll(RegExp(r'^\n+|\n+$'), '');
    if (t.trim().isEmpty) return '';
    final html = _esc(t).replaceAllMapped(_tick, (m) => '<code>${m[1]}</code>').replaceAll('\n', '<br>');
    return '<p>$html</p>';
  }

  for (final m in _fence.allMatches(plain)) {
    out.write(para(plain.substring(last, m.start)));
    final lang = (m[1] ?? '').trim();
    out.write('<pre><code${lang.isEmpty ? '' : ' class="language-$lang"'}>${_esc(m[2] ?? '')}</code></pre>');
    last = m.end;
  }
  out.write(para(plain.substring(last)));
  return out.toString();
}
