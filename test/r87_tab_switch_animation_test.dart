// R87 — bottom tab switch: the opened tab fades in and slides a little from
// the side you moved toward; no animation with reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/app_shell.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';
import 'package:nextx_mobile/widgets/nx_tab_nav.dart';

Widget _host(bool active, int dir, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: NxTabEntrance(active: active, direction: dir, child: const SizedBox(key: ValueKey('tab-body'), width: 100, height: 100)),
      ),
    );

/// Sideways shift applied around the tab body (the slide transform).
double _slideX(WidgetTester tester) => tester
    .widgetList<Transform>(find.ancestor(of: find.byKey(const ValueKey('tab-body')), matching: find.byType(Transform)))
    .map((t) => t.transform.getTranslation().x)
    .firstWhere((x) => x != 0, orElse: () => 0);

double? _opacity(WidgetTester tester) {
  final o = find.ancestor(of: find.byKey(const ValueKey('tab-body')), matching: find.byType(Opacity));
  return o.evaluate().isEmpty ? null : tester.widget<Opacity>(o.first).opacity;
}

void main() {
  testWidgets('becoming active plays a short fade + slide from the side moved toward', (tester) async {
    await tester.pumpWidget(_host(false, 0));
    expect(_opacity(tester), isNull, reason: 'idle tabs are not wrapped');
    await tester.pumpWidget(_host(true, 1));
    await tester.pump(const Duration(milliseconds: 60));
    final mid = _opacity(tester);
    expect(mid, isNotNull);
    expect(mid!, inExclusiveRange(0.0, 1.0));
    expect(_slideX(tester), greaterThan(0), reason: 'moving right: enters from the right');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacity(tester), isNull, reason: 'settled: plain child again');
  });

  testWidgets('moving left enters from the left', (tester) async {
    await tester.pumpWidget(_host(false, 0));
    await tester.pumpWidget(_host(true, -1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(_slideX(tester), lessThan(0));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('reduced motion: switches instantly', (tester) async {
    await tester.pumpWidget(_host(false, 0, reduce: true));
    await tester.pumpWidget(_host(true, 1, reduce: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_opacity(tester), isNull);
  });

  testWidgets('menu bar: one highlight slides to the tapped menu and stretches while moving', (tester) async {
    const dests = [
      NxTabDestination(icon: NxI.house, selectedIcon: NxI.house, label: 'หน้าหลัก'),
      NxTabDestination(icon: NxI.calendarBlank, selectedIcon: NxI.calendarBlank, label: 'ปฏิทิน'),
      NxTabDestination(icon: NxI.gear, selectedIcon: NxI.gear, label: 'เมนู'),
    ];
    Widget bar(int i) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 360, child: NxTabBarCard(destinations: dests, selectedIndex: i)))));
    Rect pill() => tester.getRect(find.descendant(of: find.byKey(const ValueKey('nx-tab-sliding-dot')), matching: find.byType(Container)).first);
    await tester.pumpWidget(bar(0));
    final start = pill();
    expect(start.width, NxTabNav.dot);
    final iconStart = tester.getCenter(find.byIcon(NxI.house));
    expect((start.center.dx - iconStart.dx).abs(), lessThan(1), reason: 'sits under the selected icon');
    expect((start.center.dy - iconStart.dy).abs(), lessThan(1));

    await tester.pumpWidget(bar(2));
    await tester.pump(const Duration(milliseconds: 90));
    final mid = pill();
    expect(mid.center.dx, greaterThan(start.center.dx), reason: 'moving toward the new menu');
    expect(mid.width, greaterThan(NxTabNav.dot), reason: 'stretches while moving');

    await tester.pump(const Duration(milliseconds: 500));
    final end = pill();
    expect(end.width, NxTabNav.dot);
    expect((end.center.dx - tester.getCenter(find.byIcon(NxI.gear)).dx).abs(), lessThan(1));
  });
}
