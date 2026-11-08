import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_app_header.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';
import 'package:nextx_mobile/widgets/nx_overlay_panel.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

void main() {
  testWidgets('⋯ menu grows out of the button (top-right), not centred on screen', (tester) async {
    NxTapTracker.ensure();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var picked = '';
    await tester.pumpWidget(MaterialApp(
      home: NxScrollScaffold(
        header: NxAppHeader(
          title: '[QA] หน้า',
          menu: [
            NxHeaderMenuItem(label: '[QA] ทำซ้ำ', icon: NxI.copySimple, onTap: () => picked = 'dup'),
            NxHeaderMenuItem(label: '[QA] ลบ', icon: NxI.trash, onTap: () => picked = 'del'),
          ],
        ),
        body: const SizedBox.expand(),
      ),
    ));
    final button = tester.getCenter(find.byTooltip('เพิ่มเติม'));
    await tester.tap(find.byTooltip('เพิ่มเติม'));
    await tester.pumpAndSettle();

    final item = tester.getRect(find.text('[QA] ทำซ้ำ'));
    // Opens just under the button on its side of the screen.
    expect(item.top, greaterThan(button.dy));
    expect(item.top, lessThan(200), reason: 'not in the middle of the screen');
    final card = tester.getRect(find.ancestor(of: find.text('[QA] ทำซ้ำ'), matching: find.byType(SingleChildScrollView)).first);
    expect(card.right, closeTo(button.dx + 20, 24), reason: 'right edge lines up with the ⋯ button');

    await tester.tap(find.text('[QA] ลบ'));
    await tester.pumpAndSettle();
    expect(picked, 'del');
    expect(find.text('[QA] ทำซ้ำ'), findsNothing);
  });

  testWidgets('a menu opened low on the screen opens upward', (tester) async {
    NxTapTracker.ensure();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: const Alignment(-0.8, 0.9),
          child: Builder(
            builder: (context) => IconButton(
              tooltip: '[QA] ตัวเลือก',
              icon: const Icon(NxI.dotsThreeVertical),
              onPressed: () => showNxBlurPanel<void>(
                context: context,
                builder: (_) => const ListTile(title: Text('[QA] รายการ')),
              ),
            ),
          ),
        ),
      ),
    ));
    final button = tester.getRect(find.byTooltip('[QA] ตัวเลือก'));
    await tester.tap(find.byTooltip('[QA] ตัวเลือก'));
    await tester.pumpAndSettle();
    final item = tester.getRect(find.text('[QA] รายการ'));
    expect(item.bottom, lessThan(button.top), reason: 'above the button');
    expect(item.left, lessThan(200), reason: 'stays on the button side');
  });

  testWidgets('a screen-reader tap (no pointer event) still anchors at the button', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: const Alignment(-0.8, 0.9),
          child: Builder(
            builder: (bc) => IconButton(
              tooltip: '[QA] แถว',
              icon: const Icon(NxI.dotsThreeVertical),
              onPressed: NxTapTracker.from(
                bc,
                () => showNxBlurPanel<void>(context: bc, builder: (_) => const ListTile(title: Text('[QA] เมนูแถว'))),
              ),
            ),
          ),
        ),
      ),
    ));
    // No pointer position known: only the button itself can tell where it is.
    NxTapTracker.last = null;
    tester.semantics.tap(find.semantics.byPredicate((n) => n.tooltip == '[QA] แถว' && n.getSemanticsData().hasAction(SemanticsAction.tap)));
    await tester.pumpAndSettle();
    final button = tester.getRect(find.byTooltip('[QA] แถว'));
    final item = tester.getRect(find.text('[QA] เมนูแถว'));
    expect(item.bottom, lessThan(button.top), reason: 'opens above the low button');
    expect(item.bottom, greaterThan(button.top - 80), reason: 'right next to it, not at the top of the screen');
    expect(item.left, lessThan(200));
    handle.dispose();
  });
}
