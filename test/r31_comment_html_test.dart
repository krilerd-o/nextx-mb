import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/html_display.dart';
import 'package:nextx_mobile/widgets/nx_html_view.dart';

String _shown(WidgetTester tester) => [
      for (final w in tester.widgetList<RichText>(find.byType(RichText))) w.text.toPlainText(),
      for (final w in tester.widgetList<SelectableText>(find.byType(SelectableText))) w.data ?? w.textSpan?.toPlainText() ?? '',
    ].join('\n');

void main() {
  test('a comment with bare <br> (no closing tag) is HTML', () {
    expect(looksLikeHtmlString('ตีไปก่อน <br>flow ละ 100-150 flow <br>OCR Flow ละ 150K'), isTrue);
    expect(looksLikeHtmlString('แก้ไข MA 20%'), isFalse);
    expect(looksLikeHtmlString('ราคา 5 < 10'), isFalse);
  });

  for (final (name, body) in [
    ('bare <br>', 'ตีไปก่อน <br>flow ละ 100-150 flow <br>OCR Flow ละ 150K'),
    ('escaped &lt;br&gt;', 'ตีไปก่อน &lt;br&gt;flow ละ 100-150 flow &lt;br&gt;OCR Flow ละ 150K'),
  ]) {
    testWidgets('comment with $name shows line breaks, not tags', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NxHtmlView(html: body, baseUrl: 'https://x.test'))));
      await tester.pump();
      final text = _shown(tester);
      expect(text, isNot(contains('<br>')));
      expect(text, contains('ตีไปก่อน'));
      expect(text, contains('OCR Flow ละ 150K'));
      expect(text.contains('\n'), isTrue, reason: 'br becomes a new line: $text');
    });
  }
}
