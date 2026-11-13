// R83 — code in task descriptions / comments: inline `code`, web-style code
// blocks (lowlight colours, line numbers, wrap + copy), tables, and plain
// text typed with Markdown code marks.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_html_view.dart';
import 'package:nextx_mobile/widgets/nx_rich_code.dart';

Future<void> _pump(WidgetTester tester, String html, {Brightness b = Brightness.light}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: b),
    home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: NxHtmlView(html: html, baseUrl: 'https://x.test')))),
  ));
  await tester.pump();
}

/// Text pieces with the style they actually get (parent styles merged in).
Iterable<TextSpan> _leaves(InlineSpan s, [TextStyle? inherited]) sync* {
  if (s is TextSpan) {
    final style = inherited == null ? s.style : inherited.merge(s.style);
    if (s.text != null) yield TextSpan(text: s.text, style: style);
    for (final c in s.children ?? const <InlineSpan>[]) {
      yield* _leaves(c, style);
    }
  }
}

void main() {
  const tiptap = '<p>Endpoint: <code>GET /api/notify</code> ใช้ทดสอบ</p>'
      '<pre><code class="language-sql">SELECT id, name\nFROM aicrm_notification -- note\nWHERE id = 42;</code></pre>';

  testWidgets('TipTap code block: web block with line numbers, colours, wrap and copy', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await _pump(tester, tiptap);
    expect(find.byKey(const ValueKey('nx-rich-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-rich-code-gutter')), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // three numbered lines

    // SQL keywords use the web's violet; strings/comments their colours.
    final code = tester.widget<SelectableText>(find.descendant(of: find.byKey(const ValueKey('nx-rich-code')), matching: find.byType(SelectableText)));
    final leaves = _leaves(code.textSpan!).toList();
    expect(leaves.firstWhere((s) => s.text == 'SELECT').style?.color, const Color(0xFF7C3AED));
    expect(leaves.firstWhere((s) => s.text == '42').style?.color, const Color(0xFFD97706));
    expect(leaves.firstWhere((s) => s.text!.contains('-- note')).style?.color, const Color(0xFF64748B));

    // Copy (top right) puts the raw code on the clipboard and shows a tick.
    await tester.tap(find.byKey(const ValueKey('nx-rich-code-copy')));
    await tester.pump();
    expect(copied, 'SELECT id, name\nFROM aicrm_notification -- note\nWHERE id = 42;');
    expect(find.byTooltip('คัดลอกแล้ว'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('คัดลอกโค้ด'), findsOneWidget);

    // Wrap: no sideways scroll, numbers hidden (they would not line up).
    expect(find.byKey(const ValueKey('nx-rich-code-scroll')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nx-rich-code-wrap')));
    await tester.pump();
    expect(find.byKey(const ValueKey('nx-rich-code-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('nx-rich-code-gutter')), findsNothing);
  });

  testWidgets('inline code is monospace on a chip, the rest stays prose', (tester) async {
    await _pump(tester, tiptap);
    final para = tester.widgetList<SelectableText>(find.byType(SelectableText)).first;
    final leaves = _leaves(para.textSpan!).toList();
    final chip = leaves.firstWhere((s) => s.text!.contains('GET /api/notify'));
    expect(chip.style?.fontFamily, 'monospace');
    expect(chip.style?.backgroundColor, const Color(0xFFF1F3F5));
    expect(leaves.firstWhere((s) => s.text!.contains('ใช้ทดสอบ')).style?.fontFamily, isNot('monospace'));
  });

  testWidgets('dark mode uses the web dark colours', (tester) async {
    await _pump(tester, tiptap, b: Brightness.dark);
    final para = tester.widgetList<SelectableText>(find.byType(SelectableText)).first;
    expect(_leaves(para.textSpan!).firstWhere((s) => s.text!.contains('GET')).style?.backgroundColor, const Color(0xE0334155));
  });

  testWidgets('saved block options: no line numbers, wrapped', (tester) async {
    await _pump(tester, '<pre data-line-numbers="false"><code data-word-wrap="true" data-saved-language="json">{"a": 1}</code></pre>');
    expect(find.byKey(const ValueKey('nx-rich-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-rich-code-gutter')), findsNothing);
    expect(find.byKey(const ValueKey('nx-rich-code-scroll')), findsNothing);
  });

  testWidgets('tables keep rows and cells (were flattened into one line)', (tester) async {
    await _pump(
      tester,
      '<table><tbody><tr><th><p>Block Name</p></th><th><p>Column Name</p></th></tr>'
      '<tr><td><p>Notification Info</p></td><td><p>notificationid</p><p><code>PK</code></p></td></tr></tbody></table>',
    );
    expect(find.byKey(const ValueKey('html-table')), findsOneWidget);
    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children.length, 2);
    expect(table.children.first.children.length, 2);
    expect(find.textContaining('Block Name', findRichText: true), findsOneWidget);
    expect(find.textContaining('Notification Info', findRichText: true), findsOneWidget);
  });

  testWidgets('plain text typed with ``` fences and `ticks` (mobile comments)', (tester) async {
    await _pump(tester, 'ลองรัน `npm test` ก่อนนะ\n```bash\nnpm ci\nnpm test\n```\nแล้วแจ้งผล');
    expect(find.byKey(const ValueKey('nx-rich-code')), findsOneWidget);
    expect(find.textContaining('แล้วแจ้งผล', findRichText: true), findsOneWidget);
    expect(find.textContaining('```', findRichText: true), findsNothing);
  });

  test('backtickCodeToHtml escapes and leaves plain text alone', () {
    expect(backtickCodeToHtml('no code here'), isNull);
    expect(backtickCodeToHtml('a `<b>` c'), '<p>a <code>&lt;b&gt;</code> c</p>');
    expect(backtickCodeToHtml('```\nx < 1\n```'), '<pre><code>x &lt; 1</code></pre>');
  });

  test('unknown language falls back to plain text, no crash', () {
    final spans = webCodeSpans('hello world', 'not-a-language', dark: false);
    expect(spans.map((s) => s.toPlainText()).join(), 'hello world');
  });
}
