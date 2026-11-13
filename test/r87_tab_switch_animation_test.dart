// R87 — bottom tab switch: the opened tab fades in and slides a little from
// the side you moved toward; no animation with reduced motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/app_shell.dart';

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
}
