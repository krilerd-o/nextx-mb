import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/widgets/nx_skeleton.dart';

double _opacity(WidgetTester tester) =>
    tester.widget<FadeTransition>(find.descendant(of: find.byType(NxSkeleton), matching: find.byType(FadeTransition)).first).opacity.value;

Widget _app(Widget child, {Brightness b = Brightness.light, bool reduce = false}) => MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('fast loads never show the skeleton; slow ones fade it in', (tester) async {
    await tester.pumpWidget(_app(const NxSkeletonList()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_opacity(tester), greaterThan(0.9));
  });

  testWidgets('dark theme: card = theme card colour, bones are faint tints (not white)', (tester) async {
    await tester.pumpWidget(_app(const NxSkeletonList(rows: 1), b: Brightness.dark));
    final ctx = tester.element(find.byType(NxBone).first);
    final c = NxSkeletonColors.of(ctx);
    expect(c.card, Theme.of(ctx).cardTheme.color);
    expect(c.card, isNot(Theme.of(ctx).scaffoldBackgroundColor));
    expect(c.bone.a, lessThan(0.2));
    expect(c.highlight.a, lessThan(0.2));
  });

  testWidgets('reduced motion: no shimmer frames once visible', (tester) async {
    await tester.pumpWidget(_app(const NxSkeletonBoard(), reduce: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('board / detail / calendar / chat / box skeletons lay out', (tester) async {
    for (final w in const [NxSkeletonBoard(), NxSkeletonDetail(), NxSkeletonCalendar(), NxSkeletonChat(), NxSkeletonBox()]) {
      await tester.pumpWidget(_app(SingleChildScrollView(child: w)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byType(NxBone), findsWidgets);
    }
  });
}
