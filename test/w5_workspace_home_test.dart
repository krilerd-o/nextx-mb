import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/workspace/workspace_home_screen.dart';
import 'package:nextx_mobile/screens/workspace/workspace_trash_screen.dart';

import 'support/fake_api.dart';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = thaiNow();
  final mine = [
    {'id': 1, 'item_no': 1, 'board_id': 1, 'board_code': 'QAM', 'board_name': '[QA] Mobile board', 'title': '[QAM]: [QA] เลยกำหนด', 'type': 'task', 'due_date': _ymd(now.subtract(const Duration(days: 2)))},
    {'id': 2, 'item_no': 2, 'board_id': 1, 'board_code': 'QAM', 'title': '[QA] วันนี้', 'type': 'bug', 'due_date': _ymd(now)},
    {'id': 3, 'item_no': 3, 'board_id': 1, 'board_code': 'QAM', 'title': '[QA] ไม่มีกำหนด', 'type': 'task'},
  ];

  test('my work scopes by due date', () {
    expect(wsMyWork(mine, WsMyScope.overdue).map((e) => e['id']), [1]);
    expect(wsMyWork(mine, WsMyScope.today).map((e) => e['id']), [2]);
    expect(wsMyWork(mine, WsMyScope.week).map((e) => e['id']), [1, 2]);
    expect(wsMyWork(mine, WsMyScope.all).map((e) => e['id']), [1, 2, 3]);
  });

  Future<FakeNextxAdapter> pump(WidgetTester tester, Widget home) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/boards': {
        'list': [
          {'id': 1, 'name': '[QA] Mobile board', 'code': 'QAM', 'task_count': 4, 'done_count': 1, 'member_count': 2},
        ],
      },
      'GET /api/workspace/items': {'list': mine},
      'GET /api/workspace/trash': {
        'list': [
          {'id': 7, 'kind': 'task', 'title': '[QA] งานที่ลบ', 'board_name': '[QA] Mobile board', 'deleted_by_name': 'QA Tester'},
        ],
        'total': 1,
        'can_purge': false,
      },
      'POST /api/workspace/trash/7/restore': {'ok': true},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '5', businessId: '1', menusLoaded: true, menuKeys: ['workspace']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return adapter;
  }

  testWidgets('home lists my open work and boards with progress', (tester) async {
    final adapter = await pump(tester, const WorkspaceHomeScreen());
    final q = adapter.calls.firstWhere((c) => c.path == '/api/workspace/items').queryParameters;
    expect(q['assignee_id'], '5');
    expect(q['exclude_done'], '1');
    // Folded by default; opens on today's work.
    expect(find.text('[QA] วันนี้'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ws-my-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('[QA] วันนี้'), findsOneWidget);
    expect(find.text('[QA] เลยกำหนด'), findsNothing, reason: 'default scope is today');
    await tester.tap(find.textContaining('เลยกำหนด'));
    await tester.pumpAndSettle();
    expect(find.text('[QA] เลยกำหนด'), findsOneWidget);
    expect(find.text('เลย 2 วัน'), findsOneWidget);
    // Board search lives in the header.
    expect(find.byKey(const ValueKey('ws-board-q')), findsNothing);
    await tester.tap(find.byTooltip('ค้นหาบอร์ด'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ws-board-q')), findsOneWidget);
    expect(find.text('[QA] Mobile board'), findsWidgets);
    expect(find.text('เสร็จ 1/4'), findsOneWidget);
  });

  testWidgets('trash restores an item', (tester) async {
    final adapter = await pump(tester, const WorkspaceTrashScreen());
    expect(find.text('[QA] งานที่ลบ'), findsOneWidget);
    expect(find.byTooltip('ลบถาวร'), findsNothing, reason: 'server says no purge right');
    await tester.tap(find.byKey(const ValueKey('ws-restore-7')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(adapter.callKeys, contains('POST /api/workspace/trash/7/restore'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('[QA] งานที่ลบ'), findsNothing);
  });
}
