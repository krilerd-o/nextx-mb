import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/nx_page_route.dart';

void main() {
  Future<void> run(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => nxOpenDetail<void>(context, Scaffold(appBar: AppBar(title: const Text('detail')), body: const Text('[QA] รายละเอียด'))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('tablet: detail slides in as a right panel; tap outside closes', (tester) async {
    await run(tester, const Size(1200, 800));
    expect(find.byKey(const ValueKey('side-panel')), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('side-panel'))).left, greaterThan(500));
    expect(find.byType(BackButton), findsNothing);
    await tester.tapAt(const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(find.text('[QA] รายละเอียด'), findsNothing);
  });

  testWidgets('phone: normal full page', (tester) async {
    await run(tester, const Size(400, 800));
    expect(find.byKey(const ValueKey('side-panel')), findsNothing);
    expect(find.text('[QA] รายละเอียด'), findsOneWidget);
  });
}
