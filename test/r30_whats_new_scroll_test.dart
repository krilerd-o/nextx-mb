import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/whats_new/whats_new_screen.dart';

/// "มีอะไรใหม่": scrolling down then back up must follow the finger.
/// Before the fix, cards built while scrolling up first laid out at full
/// height and shrank a frame later, so the list jumped / felt stuck.
void main() {
  Widget card(int i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: WhatsNewBody(
          key: ValueKey('wn-$i'),
          child: Text(List.generate(i.isEven ? 30 : 3, (l) => '[QA] ข่าว $i บรรทัด $l').join('\n')),
        ),
      );

  testWidgets('cards are folded from their first frame (no height change after build)', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: SingleChildScrollView(child: card(0))))));
    final first = tester.getSize(find.byType(WhatsNewBody)).height;
    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byType(WhatsNewBody)).height;
    // the only growth allowed is the "ดูเพิ่มเติม" button row appearing below the text
    expect(settled - first, lessThan(60));
    expect(find.text('ดูเพิ่มเติม'), findsOneWidget);
  });

  testWidgets('scroll down then up moves the list by the drag distance', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 700,
          child: ListView.builder(controller: controller, itemCount: 30, itemBuilder: (_, i) => card(i)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (var k = 0; k < 6; k++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    final down = controller.offset;
    expect(down, greaterThan(2000));
    for (var k = 0; k < 4; k++) {
      final before = controller.offset;
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();
      final moved = before - controller.offset;
      expect(moved, closeTo(300, 40), reason: 'scroll up step $k moved $moved px');
    }
  });
}
