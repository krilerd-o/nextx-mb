import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/whats_new/whats_new_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, int lines) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: WhatsNewBody(child: Text(List.generate(lines, (i) => '• [QA] บรรทัด $i').join('\n'))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('what\'s new: long notes fold to 6 lines with ดูเพิ่มเติม', (tester) async {
    await pump(tester, 20);
    expect(find.text('ดูเพิ่มเติม'), findsOneWidget);
    final folded = tester.getSize(find.byType(WhatsNewBody)).height;
    await tester.tap(find.text('ดูเพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(find.text('ย่อ'), findsOneWidget);
    expect(tester.getSize(find.byType(WhatsNewBody)).height, greaterThan(folded + 100));
  });

  testWidgets('what\'s new: short notes fit, no button', (tester) async {
    await pump(tester, 3);
    expect(find.text('ดูเพิ่มเติม'), findsNothing);
  });
}
