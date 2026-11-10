import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/workspace_child_sort.dart';
import 'package:nextx_mobile/core/workspace_models.dart';
import 'package:nextx_mobile/screens/workspace/task_detail_screen.dart';
import 'package:nextx_mobile/screens/workspace/workspace_board_screen.dart';
import 'package:nextx_mobile/screens/workspace/ws_bulk_dock.dart';

import 'support/fake_api.dart';

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
}

final _statusRows = [
  {'id': 1, 'label_th': 'รอทำ', 'sequence': 1, 'is_initial': 1},
  {'id': 2, 'label_th': 'กำลังทำ', 'sequence': 2},
  {'id': 3, 'label_th': 'เสร็จ', 'sequence': 3, 'is_done': 1},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wsSortChildren', () {
    final rows = [
      {'id': 3, 'item_no': 12, 'title': '[QA] ค', 'priority': 'low', 'sort_order': 0, 'status_id': 2, 'due_date': '2026-11-20'},
      {'id': 1, 'item_no': 5, 'title': '[QA] ก', 'priority': 'highest', 'sort_order': 2, 'status_id': 1},
      {'id': 2, 'item_no': 9, 'title': '[QA] ข', 'priority': 'medium', 'sort_order': 1, 'status_id': 3, 'due_date': '2026-11-10'},
    ];
    final statuses = [for (final r in _statusRows) WsStatus(r)];
    List<int> ids(List<Map<String, dynamic>> l) => [for (final r in l) r['id'] as int];

    test('default: item number low → high; desc reverses', () {
      expect(ids(wsSortChildren(rows, 'no', true)), [1, 2, 3]);
      expect(ids(wsSortChildren(rows, 'no', false)), [3, 2, 1]);
    });

    test('title, priority (highest first), status by board order, due with empties last, manual', () {
      expect(ids(wsSortChildren(rows, 'title', true)), [1, 2, 3]);
      expect(ids(wsSortChildren(rows, 'priority', true)), [1, 2, 3]);
      expect(ids(wsSortChildren(rows, 'status', true, statuses: statuses)), [1, 3, 2]);
      expect(ids(wsSortChildren(rows, 'due', true)), [2, 3, 1]);
      expect(ids(wsSortChildren(rows, 'due', false)), [3, 2, 1], reason: 'empty due stays last when descending too');
      expect(ids(wsSortChildren(rows, 'manual', true)), [3, 2, 1]);
    });
  });

  final task = {
    'id': 1,
    'board_id': 1,
    'board_code': 'QAM',
    'board_name': '[QA] Mobile board',
    'item_no': 1,
    'title': '[QA] Task แม่',
    'type': 'task',
    'status_id': 1,
  };

  Future<FakeNextxAdapter> pumpDetail(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/boards/1/tasks': {
        'list': [
          task,
          {'id': 23, 'item_no': 9, 'title': '[QA] Sub ค', 'type': 'subtask', 'parent_id': 1, 'status_id': 1, 'priority': 'low', 'labels': ['เดิม']},
          {'id': 21, 'item_no': 4, 'title': '[QA] Sub ก', 'type': 'subtask', 'parent_id': 1, 'status_id': 1, 'priority': 'high'},
          {'id': 22, 'item_no': 6, 'title': '[QA] Sub ข', 'type': 'subtask', 'parent_id': 1, 'status_id': 3, 'priority': 'medium'},
        ],
      },
      'GET /api/boards/1/statuses': _statusRows,
      'GET /api/boards/1/epics': {'list': []},
      'GET /api/users': {
        'list': [
          {'id': 5, 'first_name': '[QA]', 'last_name': 'Tester'},
        ],
      },
      'GET /api/boards/1/items/task/1/watchers': {'list': []},
      'GET /api/boards/1/items/task/1/links': {'list': []},
      'GET /api/boards/1/items/task/1/smart-checklist': {'items': []},
      'GET /api/boards/1/tasks/1/comments': {'list': []},
      'GET /api/boards/1/tasks/1/worklogs': {'list': []},
      'GET /api/boards/1/activity': {'list': []},
      'PUT /api/boards/1/bulk-update': {'updated': 2},
      'POST /api/boards/1/bulk-delete': {'deleted': 2, 'trash_ids': [7, 8]},
      'POST /api/workspace/trash/bulk-restore': {'done': [7, 8]},
      'POST /api/boards/1/bulk-duplicate': {'created': 1, 'items': [{'id': 30, 'title': '[QA] Sub ก (สำเนา)'}]},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '5', businessId: '1', menusLoaded: true, menuKeys: ['workspace']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(430, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: TaskDetailScreen(task: task))));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return adapter;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('subtasks: sorted by item number, long-press opens the bulk dock, priority applies + undo', (tester) async {
    final adapter = await pumpDetail(tester);
    final order = [
      for (final id in [21, 22, 23]) tester.getTopLeft(find.byKey(ValueKey('ws-child-$id'))).dy,
    ];
    expect(order[0] < order[1] && order[1] < order[2], isTrue, reason: 'QAM-4, QAM-6, QAM-9');
    expect(find.byType(WsBulkDock), findsNothing);

    await tester.longPress(find.byKey(const ValueKey('ws-child-21')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ws-child-23')));
    await settle(tester);
    expect(find.byType(WsBulkDock), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ws-bulk-count')), matching: find.text('2')), findsOneWidget);

    // The dock is the theme's inverse colour (dark on a light theme).
    final mat = tester.widget<Material>(find.byKey(const ValueKey('ws-bulk-dock')));
    final ctx = tester.element(find.byType(WsBulkDock));
    expect(mat.color, Theme.of(ctx).colorScheme.inverseSurface);

    await tester.ensureVisible(find.byKey(const ValueKey('bulk-tool-priority')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-tool-priority')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bulk-priority-lowest')));
    await settle(tester);
    var b = _body(adapter, 'PUT /api/boards/1/bulk-update');
    expect(b['updates'], {'priority': 'lowest'});
    expect([for (final i in b['item_ids'] as List) (i as Map)['id']]..sort(), [21, 23]);

    await tester.tap(find.text('เลิกทำ'));
    await settle(tester);
    b = _body(adapter, 'PUT /api/boards/1/bulk-update');
    expect((b['updates'] as Map)['priority'], isIn(['high', 'low']), reason: 'undo sends each item its old priority');
    expect(adapter.calls.where((c) => c.path == '/api/boards/1/bulk-update').length, 3);
  });

  testWidgets('dock: labels add, delete with undo from the trash, back clears the selection', (tester) async {
    final adapter = await pumpDetail(tester);
    await tester.longPress(find.byKey(const ValueKey('ws-child-22')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ws-child-23')));
    await settle(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('bulk-tool-labels')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-tool-labels')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('bulk-label-input')), 'ด่วน');
    await tester.tap(find.byKey(const ValueKey('bulk-label-add')));
    await settle(tester);
    expect(_body(adapter, 'PUT /api/boards/1/bulk-update')['updates'], {
      'labels_add': ['ด่วน'],
    });

    await tester.ensureVisible(find.byKey(const ValueKey('bulk-tool-delete')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-tool-delete')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('bulk-delete-confirm')));
    await settle(tester);
    expect(adapter.callKeys, contains('POST /api/boards/1/bulk-delete'));
    expect(find.byType(WsBulkDock), findsNothing, reason: 'selection cleared after delete');
    await tester.tap(find.text('เลิกทำ'));
    await settle(tester);
    expect(_body(adapter, 'POST /api/workspace/trash/bulk-restore')['ids'], [7, 8]);

    // Selection + system back → only the selection is cleared.
    await tester.longPress(find.byKey(const ValueKey('ws-child-21')));
    await settle(tester);
    expect(find.byType(WsBulkDock), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(WsBulkDock), findsNothing);
    expect(find.byType(TaskDetailScreen), findsOneWidget);
  });

  testWidgets('sort choice is remembered (stored per business)', (tester) async {
    await pumpDetail(tester);
    final chip = find.byKey(const ValueKey('ws-child-sort'));
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.textContaining('เลขที่')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('ws_child_sort_')), isEmpty);
  });

  testWidgets('board: long-press a card shows the same dock; duplicate calls the API', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/boards/1/statuses': _statusRows,
      'GET /api/boards/1/tasks': {
        'list': [
          {'id': 11, 'title': '[QA] การ์ด A', 'status_id': 1, 'item_no': 1, 'type': 'task'},
          {'id': 12, 'title': '[QA] การ์ด B', 'status_id': 1, 'item_no': 2, 'type': 'task'},
        ],
      },
      'GET /api/boards/1/epics': {'list': []},
      'GET /api/boards/1': {'id': 1, 'code': 'QAM', 'name': '[QA] Mobile board'},
      'GET /api/users': {'list': []},
      'POST /api/boards/1/bulk-duplicate': {'created': 1, 'items': [{'id': 40}]},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '5', businessId: '1', menusLoaded: true, menuKeys: ['workspace']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: WorkspaceBoardScreen(board: {'id': 1, 'name': '[QA] Mobile board', 'code': 'QAM'})),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('[QA] การ์ด A'));
    await settle(tester);
    expect(find.byType(WsBulkDock), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('bulk-tool-duplicate')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-tool-duplicate')));
    await settle(tester);
    expect(adapter.callKeys, contains('POST /api/boards/1/bulk-duplicate'));
    expect(find.textContaining('ทำซ้ำ 1 รายการ'), findsOneWidget);
  });
}
