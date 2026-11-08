import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/nx_breakpoint.dart';
import 'package:nextx_mobile/widgets/nx_split_view.dart';

Widget _app(List<DisplayFeature> features, {Size size = const Size(673, 841)}) => MediaQuery(
      data: MediaQueryData(size: size, displayFeatures: features),
      child: const MaterialApp(
        home: Scaffold(
          body: NxSplitView(
            list: ColoredBox(key: ValueKey('list'), color: Colors.red),
            detail: ColoredBox(key: ValueKey('detail'), color: Colors.blue),
          ),
        ),
      ),
    );

void main() {
  testWidgets('opened foldable (book style): list and detail split exactly at the hinge', (tester) async {
    tester.view.physicalSize = const Size(673, 841);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const hinge = DisplayFeature(bounds: Rect.fromLTWH(330, 0, 13, 841), type: DisplayFeatureType.hinge, state: DisplayFeatureState.postureFlat);
    await tester.pumpWidget(_app(const [hinge]));
    await tester.pump();
    expect(find.byKey(const ValueKey('nx-hinge-split')), findsOneWidget);
    final list = tester.getRect(find.byKey(const ValueKey('list')));
    final detail = tester.getRect(find.byKey(const ValueKey('detail')));
    expect(list.right, 330, reason: 'list ends where the hinge starts');
    expect(detail.left, 343, reason: 'detail starts after the hinge (nothing under it)');
  });

  testWidgets('horizontal fold (tabletop) or closed phone: single pane', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const flat = DisplayFeature(bounds: Rect.fromLTWH(0, 450, 412, 0), type: DisplayFeatureType.fold, state: DisplayFeatureState.postureHalfOpened);
    await tester.pumpWidget(_app(const [flat], size: const Size(412, 915)));
    await tester.pump();
    expect(find.byKey(const ValueKey('nx-hinge-split')), findsNothing);
    expect(find.byKey(const ValueKey('detail')), findsNothing);
  });

  testWidgets('a fold with unknown state does not split', (tester) async {
    await tester.pumpWidget(Builder(builder: (context) {
      return MediaQuery(
        data: const MediaQueryData(size: Size(673, 841), displayFeatures: [
          DisplayFeature(bounds: Rect.fromLTWH(336, 0, 0, 841), type: DisplayFeatureType.fold, state: DisplayFeatureState.unknown),
        ]),
        child: Builder(builder: (c) => Text(NxBreakpoint.verticalHinge(c) == null ? 'none' : 'hinge', textDirection: TextDirection.ltr)),
      );
    }));
    expect(find.text('none'), findsOneWidget);
  });
}
