import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/widgets/nx_app_header.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/workspace_models.dart';
import 'package:nextx_mobile/screens/workspace/workspace_board_screen.dart';
import 'package:nextx_mobile/screens/workspace/workspace_item_form.dart';

import 'support/fake_api.dart';

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final statusRows = [
    {'id': 1, 'label_th': 'To do', 'sequence': 1, 'is_initial': 1},
    {'id': 2, 'label_th': 'กำลังทำ', 'sequence': 2},
    {'id': 4, 'label_th': 'Done', 'sequence': 4, 'is_done': 1},
  ];

  Future<FakeNextxAdapter> pumpForm(WidgetTester tester, Widget form, {Map<String, Object?> extra = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/boards/1/item-tags': {'list': []},
      'POST /api/boards/1/tasks': {'id': 77, 'title': '[QAM]: x'},
      ...extra,
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '5', businessId: '1', menusLoaded: true, menuKeys: ['workspace']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: form)));
    await tester.pumpAndSettle();
    return adapter;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ws-save')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('create sends web defaults: initial status, medium priority, me as assignee', (tester) async {
    final adapter = await pumpForm(
      tester,
      WorkspaceItemFormScreen(board: const {'id': 1, 'code': 'QAM', 'name': '[QA] Mobile board'}, statuses: WsStatus.list(statusRows)),
    );
    // Empty title: nothing is sent.
    await save(tester);
    expect(adapter.callKeys, isNot(contains('POST /api/boards/1/tasks')));

    await tester.enterText(find.byType(TextField).first, '[QA] งานใหม่');
    await tester.pump();
    await save(tester);
    final b = _body(adapter, 'POST /api/boards/1/tasks');
    expect(b['title'], '[QA] งานใหม่');
    expect(b['status_id'], 1);
    expect(b['priority'], 'medium');
    expect(b['type'], 'task');
    expect(b['assignee_id'], 5);
    expect(b['reporter_id'], 5);
    expect(b.containsKey('time_spent_minutes'), isFalse);
  });

  testWidgets('duplicate prefills from the source with a copy suffix and copies the estimate', (tester) async {
    final adapter = await pumpForm(
      tester,
      WorkspaceItemFormScreen(
        board: const {'id': 1, 'code': 'QAM'},
        statuses: WsStatus.list(statusRows),
        duplicateFrom: const {
          'id': 3,
          'title': '[QAM]: [QA] งานต้นฉบับ',
          'type': 'bug',
          'status_id': 4,
          'priority': 'high',
          'original_estimate_minutes': 90,
          'time_spent_minutes': 30,
          'labels': ['qa'],
        },
      ),
    );
    expect(find.text('[QA] งานต้นฉบับ (สำเนา)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('คัดลอกงานย่อยและเช็กลิสต์ด้วย'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('คัดลอกงานย่อยและเช็กลิสต์ด้วย'), findsOneWidget);
    await save(tester);
    final b = _body(adapter, 'POST /api/boards/1/tasks');
    expect(b['title'], '[QA] งานต้นฉบับ (สำเนา)');
    expect(b['type'], 'bug');
    expect(b['priority'], 'high');
    expect(b['status_id'], 1, reason: 'a copy starts in the initial status');
    expect(b['original_estimate'], 90);
    expect(b['labels'], ['qa']);
    expect(b.containsKey('time_spent_minutes'), isFalse);
  });

  testWidgets('board screen loads columns and cards from the API', (tester) async {
    final adapter = await pumpForm(
      tester,
      const WorkspaceBoardScreen(board: {'id': 1, 'name': '[QA] Mobile board', 'code': 'QAM'}),
      extra: {
        'GET /api/boards/1/statuses': statusRows,
        'GET /api/boards/1/tasks': {
          'list': [
            {'id': 11, 'title': '[QAM]: [QA] การ์ด A', 'status_id': 1, 'item_no': 1, 'type': 'task'},
            {'id': 12, 'title': '[QA] การ์ด B', 'status_id': 4, 'item_no': 2, 'type': 'bug'},
          ],
        },
        'GET /api/boards/1/epics': {'list': []},
        'GET /api/boards/1': {'id': 1, 'code': 'QAM', 'name': '[QA] Mobile board'},
        'GET /api/users': {'list': []},
      },
    );
    expect(adapter.callKeys, contains('GET /api/boards/1/tasks'));
    expect(find.text('[QA] การ์ด A'), findsOneWidget);
    expect(find.text('QAM-1'), findsOneWidget);
    final header = tester.widget<NxAppHeader>(find.byType(NxAppHeader).first);
    expect([for (final m in header.menu ?? const <NxHeaderMenuItem>[]) m.label], containsAllInOrder(['สร้าง Task', 'สร้าง Epic']));
  });
}
