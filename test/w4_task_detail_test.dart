import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/workspace_models.dart';
import 'package:nextx_mobile/screens/workspace/task_detail_screen.dart';
import 'package:nextx_mobile/screens/workspace/ws_activity_panel.dart';

import 'support/fake_api.dart';

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final task = {
    'id': 1,
    'board_id': 1,
    'board_code': 'QAM',
    'board_name': '[QA] Mobile board',
    'item_no': 1,
    'title': '[QAM]: [QA] Task A',
    'type': 'task',
    'status_id': 1,
    'priority': 'high',
    'assignee_id': 5,
    'original_estimate_minutes': 120,
    'time_spent_minutes': 45,
  };

  Future<FakeNextxAdapter> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/boards/1/tasks': {
        'list': [
          task,
          {'id': 2, 'item_no': 2, 'title': '[QA] Sub 1', 'type': 'subtask', 'parent_id': 1, 'status_id': 3},
        ],
      },
      'GET /api/boards/1/statuses': [
        {'id': 1, 'label_th': 'To do', 'sequence': 1, 'is_initial': 1},
        {'id': 2, 'label_th': 'กำลังทำ', 'sequence': 2},
        {'id': 3, 'label_th': 'Done', 'sequence': 3, 'is_done': 1},
      ],
      'GET /api/boards/1/epics': {'list': []},
      'GET /api/users': {
        'list': [
          {'id': 5, 'first_name': 'QA', 'last_name': 'Tester'},
        ],
      },
      'GET /api/boards/1/items/task/1/watchers': {'list': []},
      'GET /api/boards/1/items/task/1/links': {'list': []},
      'GET /api/boards/1/items/task/1/smart-checklist': {'items': []},
      'GET /api/boards/1/tasks/1/comments': {
        'list': [
          {'id': '9', 'body': '<p>[QA] เห็นด้วย</p>', 'user_id': 5, 'user_name': 'QA Tester', 'like_count': 0, 'liked_by_me': false},
        ],
      },
      'GET /api/boards/1/tasks/1/worklogs': {
        'list': [
          {'id': 1, 'user_id': 5, 'time_spent_minutes': 45, 'work_description': '[QA] เริ่มงาน', 'created_at': '2026-11-07T03:00:00Z', 'can_manage': true},
        ],
      },
      'GET /api/boards/1/activity': {
        'list': [
          {'id': 1, 'user_name': 'QA Tester', 'action': 'status_change', 'old_value': '1', 'new_value': '2', 'created_at': '2026-11-07T03:00:00Z'},
        ],
      },
      'PUT /api/boards/1/tasks/1': {'id': 1},
      'POST /api/boards/1/tasks/1/worklogs': {'id': 2},
      'POST /api/boards/1/tasks/1/comments': {'id': '10'},
      'POST /api/boards/1/tasks/1/comments/9/like': {'liked': true, 'like_count': 1},
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

  testWidgets('detail shows key, time, fields, subtasks and comments', (tester) async {
    await pump(tester);
    expect(find.text('[QA] Task A'), findsOneWidget);
    expect(find.text('QAM-1'), findsWidgets);
    expect(find.textContaining('45m / 2h', findRichText: true), findsOneWidget, reason: 'spent / estimate');
    expect(find.text('38%'), findsOneWidget);
    expect(find.text('QA Tester'), findsWidgets, reason: 'assignee name from the users cache');
    expect(find.textContaining('[QA] Sub 1'), findsOneWidget);
    expect(find.text('[QA] เห็นด้วย'), findsOneWidget);
  });

  testWidgets('tapping a status step updates status_id', (tester) async {
    final adapter = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('ws-step-2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_body(adapter, 'PUT /api/boards/1/tasks/1'), {'status_id': 2});
  });

  testWidgets('log time sheet posts minutes parsed from "1h 30m"', (tester) async {
    final adapter = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('ws-log-time')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ws-log-spent')), '1h 30m');
    await tester.tap(find.byKey(const ValueKey('ws-log-save')));
    await tester.pumpAndSettle();
    final b = _body(adapter, 'POST /api/boards/1/tasks/1/worklogs');
    expect(b['time_spent_minutes'], 90);
    expect(b['started_at'], matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:00$')));
  });

  testWidgets('comment send and like', (tester) async {
    final adapter = await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('ws-comment-input')), '[QA] ความเห็นใหม่');
    await tester.tap(find.byKey(const ValueKey('ws-comment-send')));
    await tester.pump(const Duration(milliseconds: 300));
    expect('${_body(adapter, 'POST /api/boards/1/tasks/1/comments')['body']}', contains('[QA] ความเห็นใหม่'));
    await tester.tap(find.byKey(const ValueKey('ws-like-9')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.callKeys, contains('POST /api/boards/1/tasks/1/comments/9/like'));
  });

  test('history turns ids into names', () {
    final l = WsLookups(
      users: const {'5': 'QA Tester'},
      statuses: WsStatus.list([
        {'id': 1, 'label_th': 'To do', 'sequence': 1},
        {'id': 2, 'label_th': 'กำลังทำ', 'sequence': 2},
      ]),
      items: const {
        'epic:3': {'id': 3, 'item_no': 7, 'board_code': 'QAM', 'title': '[QA] Epic'},
      },
    );
    final s = wsDescribeActivity({'action': 'status_change', 'old_value': '1', 'new_value': '2'}, l);
    expect((s.from, s.to), ('To do', 'กำลังทำ'));
    final a = wsDescribeActivity({'action': 'field_change', 'target_type': 'assignee_id', 'old_value': null, 'new_value': '5'}, l);
    expect(a.to, 'QA Tester');
    final e = wsDescribeActivity({'action': 'field_change', 'target_type': 'epic_id', 'old_value': null, 'new_value': '3'}, l);
    expect(e.to, 'QAM-7 [QA] Epic');
    final est = wsDescribeActivity({'action': 'field_change', 'target_type': 'original_estimate_minutes', 'old_value': '60', 'new_value': '90'}, l);
    expect((est.from, est.to), ('1h', '1h 30m'));
  });
}
