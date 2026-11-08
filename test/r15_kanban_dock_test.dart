import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/workspace_models.dart';
import 'package:nextx_mobile/screens/workspace/ws_kanban.dart';
import 'package:nextx_mobile/widgets/nx_chrome.dart';

void main() {
  final statuses = WsStatus.list([
    {'id': 1, 'name': 'todo', 'label_th': 'To do', 'sequence': 1, 'is_initial': 1},
    {'id': 2, 'name': 'doing', 'label_th': 'Doing', 'sequence': 2},
    {'id': 3, 'name': 'review', 'label_th': 'Review', 'sequence': 3},
    {'id': 4, 'name': 'done', 'label_th': 'Done', 'sequence': 4, 'is_done': 1},
    {'id': 5, 'name': 'cancelled', 'label_th': 'ยกเลิก', 'sequence': 5},
  ]);
  final items = [
    {'id': 11, 'title': '[QA] งาน A', 'status_id': 1, 'item_no': 1, 'sort_order': 0, 'type': 'task'},
    {'id': 12, 'title': '[QA] งาน B', 'status_id': 1, 'item_no': 2, 'sort_order': 1, 'type': 'task'},
  ];

  test('end states are recognised', () {
    expect(statuses.where((s) => s.isTerminal).map((s) => s.id), ['4', '5']);
    expect(statuses.firstWhere((s) => s.id == '5').isCancelled, isTrue);
  });

  Future<List<(String, String)>> pumpBoard(WidgetTester tester) async {
    NxChromeBus.reset();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final moves = <(String, String)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WsKanban(
          statuses: statuses,
          items: items,
          boardCode: 'QAM',
          onOpen: (_) {},
          onMove: (item, sid, _) async {
            moves.add(('${item['id']}', sid));
            return true;
          },
        ),
      ),
    ));
    await tester.pump();
    return moves;
  }

  /// Long-press the card, then bring it down onto the "ย้ายไปที่" pill.
  Future<TestGesture> dragToDock(WidgetTester tester) async {
    final g = await tester.startGesture(tester.getCenter(find.text('[QA] งาน A')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(NxChromeBus.dragging.value, isTrue, reason: 'tab bar / FAB step aside');
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 400)); // pill rises
    expect(find.byKey(const ValueKey('ws-dock-pill')), findsOneWidget);
    await g.moveTo(const Offset(200, 762));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // panel opens
    expect(find.byKey(const ValueKey('ws-dock-panel')), findsOneWidget);
    return g;
  }

  Finder inPanel(String text) =>
      find.descendant(of: find.byKey(const ValueKey('ws-dock-panel')), matching: find.text(text));

  testWidgets('pill opens a panel: statuses as rows, end states as big buttons', (tester) async {
    final moves = await pumpBoard(tester);
    final g = await dragToDock(tester);
    for (final t in ['To do', 'Doing', 'Review', 'Done', 'ยกเลิก']) {
      expect(inPanel(t), findsOneWidget, reason: t);
    }
    expect(inPanel('ปัจจุบัน'), findsOneWidget, reason: 'the card\'s own status is marked');
    await g.moveTo(tester.getCenter(inPanel('Review')));
    await tester.pump();
    expect(inPanel('3/3'), findsOneWidget, reason: 'counter of the hovered row');
    await g.up();
    await tester.pumpAndSettle();
    expect(moves, [('11', '3')]);
    expect(NxChromeBus.dragging.value, isFalse);
    expect(find.byKey(const ValueKey('ws-dock-panel')), findsNothing);
  });

  testWidgets('drop on the Done button, then undo moves it back', (tester) async {
    final moves = await pumpBoard(tester);
    final g = await dragToDock(tester);
    await g.moveTo(tester.getCenter(inPanel('Done')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(moves, [('11', '4')]);
    expect(find.text('ย้ายไปยัง Done แล้ว'), findsOneWidget);
    await tester.tap(find.text('เลิกทำ'));
    await tester.pumpAndSettle();
    expect(moves, [('11', '4'), ('11', '1')]);
  });

  testWidgets('releasing on the panel header moves nothing', (tester) async {
    final moves = await pumpBoard(tester);
    final g = await dragToDock(tester);
    await g.moveTo(tester.getCenter(inPanel('ย้ายไปที่')));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(moves, isEmpty);
    expect(find.text('[QA] งาน A'), findsOneWidget);
  });
}
