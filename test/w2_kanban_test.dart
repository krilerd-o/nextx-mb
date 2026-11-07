import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/workspace_models.dart';
import 'package:nextx_mobile/screens/workspace/ws_kanban.dart';

void main() {
  final statuses = WsStatus.list([
    {'id': 1, 'label_th': 'To do', 'sequence': 1, 'is_initial': 1},
    {'id': 2, 'label_th': 'Doing', 'sequence': 2},
    {'id': 3, 'label_th': 'Review', 'sequence': 3},
    {'id': 4, 'label_th': 'Done', 'sequence': 4, 'is_done': 1},
  ]);
  final items = [
    {'id': 11, 'title': '[QAM]: [QA] งาน A', 'status_id': 1, 'item_no': 1, 'sort_order': 0, 'type': 'task'},
    {'id': 12, 'title': '[QA] งาน B', 'status_id': 1, 'item_no': 2, 'sort_order': 1, 'type': 'bug'},
    {'id': 13, 'title': '[QA] งาน C', 'status_id': 4, 'item_no': 3, 'sort_order': 0, 'type': 'task'},
  ];

  Future<GlobalKey<WsKanbanState>> pumpBoard(WidgetTester tester, WsMove onMove) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey<WsKanbanState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WsKanban(
          key: key,
          statuses: statuses,
          items: items,
          boardCode: 'QAM',
          onOpen: (_) {},
          onMove: onMove,
        ),
      ),
    ));
    await tester.pump();
    return key;
  }

  /// Long-press a card, slide to the right edge and hold there.
  Future<TestGesture> dragToRightEdge(WidgetTester tester, String title) async {
    final g = await tester.startGesture(tester.getCenter(find.text(title)));
    await tester.pump(const Duration(milliseconds: 400)); // long-press delay
    for (var x = 0; x < 12; x++) {
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.moveTo(const Offset(396, 300));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return g;
  }

  testWidgets('card title hides the board prefix and shows the key', (tester) async {
    await pumpBoard(tester, (_, _, _) async => true);
    expect(find.text('[QA] งาน A'), findsOneWidget);
    expect(find.text('QAM-1'), findsOneWidget);
  });

  testWidgets('dragging to the edge auto-scrolls and drops into a far column', (tester) async {
    (Map<String, dynamic>, String, List<String>)? moved;
    final key = await pumpBoard(tester, (item, sid, order) async {
      moved = (item, sid, order);
      return true;
    });
    expect(key.currentState!.horizontalOffset, 0);
    final g = await dragToRightEdge(tester, '[QA] งาน A');
    expect(key.currentState!.horizontalOffset, greaterThan(500), reason: 'board scrolls itself toward Done');
    await g.up();
    await tester.pumpAndSettle();
    expect(moved, isNotNull);
    expect(moved!.$1['id'], 11);
    expect(moved!.$2, '4');
    expect(moved!.$3, containsAll(['11', '13']));
  });

  testWidgets('a refused move puts the card back', (tester) async {
    final key = await pumpBoard(tester, (_, _, _) async => false);
    final g = await dragToRightEdge(tester, '[QA] งาน A');
    await g.up();
    await tester.pumpAndSettle();
    // Back in To do: scroll home and the card is there again.
    expect(key.currentState!.horizontalOffset, greaterThan(0));
    await tester.drag(find.byType(ListView).first, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(find.text('[QA] งาน A'), findsOneWidget);
    expect(find.text('[QA] งาน B'), findsOneWidget);
  });

  test('parseDuration matches the web time format', () {
    expect(parseDuration('1h 30m'), 90);
    expect(parseDuration('2d'), 2880);
  });
}
