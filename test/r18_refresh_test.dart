import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_refresh.dart';

void main() {
  Widget app(Widget child, {TargetPlatform platform = TargetPlatform.android}) =>
      MaterialApp(theme: ThemeData(platform: platform), home: Scaffold(body: child));

  Widget list() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('row $i'))],
      );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('pull past the trigger refreshes with spinner → ✓ อัปเดตแล้ว (${platform.name})', (tester) async {
      final done = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(app(
        NxRefresh(
          onRefresh: () {
            calls++;
            return done.future;
          },
          child: list(),
        ),
        platform: platform,
      ));
      expect(find.byKey(const ValueKey('nx-refresh')), findsNothing);

      final g = await tester.startGesture(tester.getCenter(find.text('row 1')));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byKey(const ValueKey('nx-refresh')), findsOneWidget, reason: 'bubble follows the finger');
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32)); // first bounce-back frame
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('nx-refresh')), findsOneWidget, reason: 'spins while loading');
      expect(find.text('อัปเดตแล้ว'), findsNothing);

      done.complete();
      await tester.pump(const Duration(milliseconds: 700)); // minimum spin
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('อัปเดตแล้ว'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800)); // ✓ stays a moment
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nx-refresh')), findsNothing, reason: 'slides away when done');
    });
  }

  testWidgets('a short pull springs back without refreshing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(NxRefresh(onRefresh: () async => calls++, child: list())));
    await tester.drag(find.text('row 1'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byKey(const ValueKey('nx-refresh')), findsNothing);
  });

  testWidgets('nested refreshers: only the inner one runs (one bubble)', (tester) async {
    var inner = 0, outer = 0;
    await tester.pumpWidget(app(NxRefresh(
      onRefresh: () async => outer++,
      child: NxRefresh(onRefresh: () async => inner++, child: list()),
    )));
    final g = await tester.startGesture(tester.getCenter(find.text('row 1')));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey('nx-refresh')), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect((inner, outer), (1, 0));
  });

  testWidgets('scrolling down the list never triggers a refresh', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(NxRefresh(onRefresh: () async => calls++, child: list())));
    await tester.drag(find.text('row 5'), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(find.text('row 8'), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
