import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/widgets/nx_skeleton.dart';
import 'package:nextx_mobile/widgets/nx_status_stepper.dart';

/// Every shared skeleton block, laid out on a phone and a tablet, light and dark.
final _blocks = <String, Widget>{
  'row-card': const NxSkeletonRow(),
  'row-flat': const NxSkeletonRow(style: NxSkelRowStyle.flat, trailing: NxSkelTrailing.timeBadge, leadingSize: 50),
  'row-divided': const NxSkeletonRow(style: NxSkelRowStyle.divided, leading: NxSkelLeading.icon, lines: 3, trailing: NxSkelTrailing.text),
  'rows': const NxSkeletonRows(count: 4, dayHeaders: 2, loadMore: true),
  'rows-flat': const NxSkeletonRows(count: 4, style: NxSkelRowStyle.divided, padded: false),
  'entity-card': const NxSkeletonEntityCard(),
  'entity-cards': const NxSkeletonEntityCards(count: 3, loadMore: true),
  'toolbar': const NxSkeletonToolbar(chips: 6),
  'tabs': const NxSkeletonTabs(count: 7),
  'chevron': const NxSkeletonChevronBar(steps: 6),
  'hero': const NxSkeletonHero(cta: true),
  'detail-body': const NxSkeletonDetailBody(),
  'entity-detail': const NxSkeletonEntityDetail(cta: true),
  'task-detail': const NxSkeletonTaskDetail(),
  'settings-group': const NxSkeletonSettingsGroup(tiles: 4),
  'settings': const NxSkeletonSettings(groups: [3, 2, 2], trailing: NxSkelTrailing.chevron),
  'fields': const NxSkeletonFields(),
  'field-box': const NxSkeletonFieldBox(),
  'grid': const NxSkeletonGrid(cols: 3, count: 5),
  'grid-ring': const NxSkeletonGrid(cols: 2, ring: 84, tileHeight: 170),
  'grid-media': const NxSkeletonGrid(cols: 4, square: true, count: 8, gap: 4),
  'chart-columns': const NxSkeletonChart(height: 140),
  'chart-bars': const NxSkeletonChart(kind: NxChartKind.bars, height: 140),
  'chart-donut': const NxSkeletonChart(kind: NxChartKind.donut, height: 120),
  'chart-ring': const NxSkeletonChart(kind: NxChartKind.ring, height: 90),
  'chart-card': const NxSkeletonChartCard(kind: NxChartKind.line),
  'step-form': const SizedBox(height: 700, child: NxSkeletonStepForm()),
  'kv-card': const NxSkeletonKeyValueCard(),
  'timeline': const NxSkeletonTimeline(),
  'comments': const NxSkeletonComments(),
  'messages': const NxSkeletonMessageCards(),
  'article': const NxSkeletonArticle(cover: true),
  'agenda': const NxSkeletonAgenda(),
  'event-chips': const SizedBox(width: 40, child: NxSkeletonEventChips()),
  'list': const NxSkeletonList(padded: false),
  'board': const NxSkeletonBoard(columns: 3),
  'detail': const NxSkeletonDetail(),
  'calendar': const NxSkeletonCalendar(),
  'chat': const NxSkeletonChat(),
  'box': const NxSkeletonBox(pill: true),
  'figures': const NxSkeletonFigures(count: 6),
  'kpi': const NxSkeletonKpiGrid(),
  'form': const NxSkeletonForm(fields: 4),
};

Future<void> _pump(WidgetTester tester, Widget child, {required double width, required Brightness brightness, bool disableAnimations = false}) async {
  tester.view.physicalSize = Size(width * 2, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.themed(brightness: brightness),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  tearDown(() => Effects.preference.value = EffectsPreference.lite);

  for (final width in [360.0, 1180.0]) {
    for (final b in Brightness.values) {
      testWidgets('blocks lay out at ${width.toInt()} px (${b.name}) without overflow', (tester) async {
        for (final e in _blocks.entries) {
          await _pump(tester, e.value, width: width, brightness: b);
          expect(tester.takeException(), isNull, reason: e.key);
          expect(find.byType(NxBone), findsWidgets, reason: e.key);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('chevron skeleton is exactly as tall as the real status bar', (tester) async {
    await _pump(
      tester,
      const Column(children: [
        NxSkeletonChevronBar(),
        NxStatusStepper(steps: [NxStep(id: 'a', label: 'ใหม่'), NxStep(id: 'b', label: 'กำลังทำ')], current: 0, padding: EdgeInsets.zero),
      ]),
      width: 360,
      brightness: Brightness.light,
    );
    expect(tester.getSize(find.byKey(const ValueKey('nx-skeleton-status-bar'))).height, tester.getSize(find.byKey(const ValueKey('nx-status-bar'))).height);
    expect(NxStatusStepper.barHeight, tester.getSize(find.byKey(const ValueKey('nx-status-bar'))).height);
  });

  testWidgets('blocks nested in a skeleton share its one shimmer listener', (tester) async {
    Effects.preference.value = EffectsPreference.full;
    await _pump(tester, const NxSkeletonEntityDetail(), width: 360, brightness: Brightness.light);
    // Hero, chevron bar, tabs, body and rows are all inside one NxSkeleton root.
    expect(NxShimmerClock.instance.listenerCount, 1);
    // Bones are plain render boxes: no AnimatedBuilder per bone.
    final bones = find.byType(NxBone).evaluate().toList();
    expect(bones.length, greaterThan(20));
    final builders = find.descendant(of: find.byType(NxSkeleton).first, matching: find.byType(AnimatedBuilder)).evaluate();
    expect(builders.where((e) => (e.widget as AnimatedBuilder).listenable is NxShimmerClock), isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(NxShimmerClock.instance.listenerCount, 0);
    expect(NxShimmerClock.instance.isTicking, isFalse);
  });

  testWidgets('one ticker drives every skeleton on screen', (tester) async {
    Effects.preference.value = EffectsPreference.full;
    final before = NxShimmerClock.instance.debugTickersCreated;
    await _pump(tester, const Column(children: [NxSkeletonRows(count: 2), NxSkeletonArticle(), NxSkeletonAgenda(days: 1)]), width: 360, brightness: Brightness.light);
    expect(NxShimmerClock.instance.listenerCount, 3);
    expect(NxShimmerClock.instance.isTicking, isTrue);
    expect(NxShimmerClock.instance.debugTickersCreated - before, lessThanOrEqualTo(1));
    final p0 = NxShimmerClock.instance.value;
    await tester.pump(const Duration(milliseconds: 300));
    expect(NxShimmerClock.instance.value, isNot(p0));
    await tester.pumpWidget(const SizedBox());
    expect(NxShimmerClock.instance.isTicking, isFalse);
  });

  testWidgets('lite, off and reduced motion show still bones (no ticker)', (tester) async {
    for (final pref in [EffectsPreference.lite, EffectsPreference.off]) {
      Effects.preference.value = pref;
      await _pump(tester, const NxSkeletonRows(count: 2), width: 360, brightness: Brightness.light);
      expect(NxShimmerClock.instance.listenerCount, 0, reason: pref.name);
      expect(NxShimmerClock.instance.isTicking, isFalse, reason: pref.name);
    }
    Effects.preference.value = EffectsPreference.full;
    await _pump(tester, const NxSkeletonRows(count: 2), width: 360, brightness: Brightness.light, disableAnimations: true);
    expect(NxShimmerClock.instance.listenerCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching effects while a skeleton shows starts / stops the shimmer', (tester) async {
    Effects.preference.value = EffectsPreference.lite;
    await _pump(tester, const NxSkeletonRows(count: 2), width: 360, brightness: Brightness.light);
    expect(NxShimmerClock.instance.listenerCount, 0);
    Effects.preference.value = EffectsPreference.full;
    await tester.pump();
    expect(NxShimmerClock.instance.listenerCount, 1);
    expect(NxShimmerClock.instance.isTicking, isTrue);
    Effects.preference.value = EffectsPreference.lite;
    await tester.pump();
    expect(NxShimmerClock.instance.listenerCount, 0);
    expect(NxShimmerClock.instance.isTicking, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('list skeletons drop their own sides inside a padded list', (tester) async {
    await _pump(tester, const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: NxSkeletonList(padded: false, rows: 1)), width: 360, brightness: Brightness.light);
    final card = find.byType(NxSkeletonCard).first;
    expect(tester.getTopLeft(card).dx, 16);
    expect(tester.getSize(card).width, 328);
  });
}
