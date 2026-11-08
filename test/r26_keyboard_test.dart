import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_keyboard_follow.dart';

void main() {
  testWidgets('keyboard opening late still brings the focused field into view', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => NxKeyboardFollow(child: child!),
      home: Scaffold(
        body: ListView(controller: scroll, children: [for (var i = 0; i < 9; i++) SizedBox(height: 80, child: Text('row $i')), const TextField(key: ValueKey('f'))]),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('f')));
    await tester.pump();
    // Keyboard grows in steps (like a real phone animation).
    for (final h in [100.0, 250.0, 380.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: h);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('f'))).bottom, lessThanOrEqualTo(800 - 380 + 1));
  });
}
