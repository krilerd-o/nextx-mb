import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/app_bottom_sheet.dart' show nxSheetHeight;
import 'package:nextx_mobile/widgets/fields/nx_lift_sheet.dart' show liftPopoverRect;
import 'package:nextx_mobile/widgets/nx_back_handler.dart';
import 'package:nextx_mobile/widgets/nx_split_view.dart';
import 'package:nextx_mobile/widgets/nx_unsaved_guard.dart';

void main() {
  testWidgets('tab back handler runs only for the showing tab and only while active', (tester) async {
    var closed = 0;
    var active = true;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: NxShellTabScope(
        tabId: 'files',
        child: StatefulBuilder(builder: (c, s) {
          set = s;
          return NxBackHandler(active: active, onBack: () => s(() { closed++; active = false; }), child: const SizedBox());
        }),
      ),
    ));
    expect(NxShellBack.instance.handle('mail'), isFalse);
    expect(NxShellBack.instance.handle('files'), isTrue);
    await tester.pump();
    expect(closed, 1);
    expect(NxShellBack.instance.handle('files'), isFalse, reason: 'nothing open any more');
    set(() {});
  });

  testWidgets('pushed page: back closes the open thing first, then leaves', (tester) async {
    var open = true;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (c, s) => NxBackHandler(active: open, onBack: () => s(() => open = false), child: const Scaffold(body: Text('page'))),
            ),
          )),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(open, isFalse);
    expect(find.text('page'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('page'), findsNothing);
  });

  testWidgets('two-pane: back clears the selected detail first', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget? detail = const Text('detail');
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (c, s) => Scaffold(body: NxSplitView(list: const Text('list'), detail: detail, onClose: () => s(() => detail = null))),
            ),
          )),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(find.text('list'), findsOneWidget);
  });

  testWidgets('unsaved form: back asks; untouched form leaves at once', (tester) async {
    final ctl = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            builder: (_) => NxUnsavedGuard(snapshot: () => ctl.text, child: Scaffold(body: TextField(controller: ctl))),
          )),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '[QA] ลูกค้า');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nx-discard-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nx-discard-stay')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nx-discard-leave')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    // Untouched: no question.
    ctl.clear();
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nx-discard-dialog')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  test('picker popover stays in its side of the fold and above the keyboard', () {
    const area = Rect.fromLTWH(600, 0, 600, 800); // right side of a fold
    final r = liftPopoverRect(field: const Rect.fromLTWH(700, 500, 300, 48), area: area, keyboard: 320);
    // returned rect is relative to the area
    expect(r.left, greaterThanOrEqualTo(16));
    expect(r.left + r.width, lessThanOrEqualTo(area.width - 16));
    expect(r.top + r.height, lessThanOrEqualTo(area.height - 320 - 16 + 0.01));
    expect(r.height, greaterThanOrEqualTo(160));
  });

  testWidgets('sheet height fits above the keyboard', (tester) async {
    late double h;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(400, 800), viewInsets: EdgeInsets.only(bottom: 300), padding: EdgeInsets.only(top: 24)),
      child: Builder(builder: (c) {
        h = nxSheetHeight(c, 0.7);
        return const SizedBox();
      }),
    ));
    expect(h, 800 - 300 - 24 - 24);
  });
}
