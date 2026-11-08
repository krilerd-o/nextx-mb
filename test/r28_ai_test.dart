import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart';

import 'support/fake_api.dart';

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

final _base = <String, Object?>{
  'GET /api/ai/conversations': [
    {'id': 7, 'title': '[QA] แชทเก่า', 'updated_at': '2026-11-08T03:00:00Z'},
    {'id': 8, 'title': '[QA] แชทโปรเจกต์', 'project_id': 3, 'updated_at': '2026-11-08T02:00:00Z'},
  ],
  'GET /api/ai/projects': {
    'items': [
      {'id': 3, 'name': '[QA] โปรเจกต์ A'},
    ],
  },
  'GET /api/ai/usage': {'meters_cloud': false},
  'GET /api/ai/suggested-prompts': <Map<String, dynamic>>[],
  'PATCH /api/ai/conversations/7': {'id': 7},
  'DELETE /api/ai/conversations/7': {'ok': true},
};

Future<FakeNextxAdapter> _pump(WidgetTester tester, {Size size = const Size(400, 860)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig()..debugOverrideSession(_member);
  final adapter = FakeNextxAdapter(_base);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: AiAssistantScreen())));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

void main() {
  testWidgets('tablet: chats stay docked on the left, no drawer button', (tester) async {
    await _pump(tester, size: const Size(1200, 900));
    expect(find.byKey(const ValueKey('ai-chat-sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-open-chats')), findsNothing);
    expect(find.text('[QA] แชทเก่า'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('project filter shows only that project; move sends project_id', (tester) async {
    final adapter = await _pump(tester, size: const Size(1200, 900));
    expect(find.byKey(const ValueKey('ai-project-filter')), findsOneWidget);
    await tester.tap(find.text('[QA] โปรเจกต์ A'));
    await tester.pump();
    expect(find.text('[QA] แชทเก่า'), findsNothing);
    expect(find.text('[QA] แชทโปรเจกต์'), findsOneWidget);
    await tester.tap(find.text('ทั้งหมด'));
    await tester.pump();

    await tester.longPress(find.text('[QA] แชทเก่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ย้ายไปโปรเจกต์'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[QA] โปรเจกต์ A').last);
    await tester.pump(const Duration(milliseconds: 200));
    final patch = adapter.calls.lastWhere((c) => c.method == 'PATCH' && c.path == '/api/ai/conversations/7');
    expect(Map<String, dynamic>.from(patch.data as Map)['project_id'], '3');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('delete hides at once; undo keeps it (no DELETE)', (tester) async {
    final adapter = await _pump(tester, size: const Size(1200, 900));
    await tester.longPress(find.text('[QA] แชทเก่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบ').last);
    await tester.pumpAndSettle();
    expect(find.text('[QA] แชทเก่า'), findsNothing);
    await tester.tap(find.text('เลิกทำ'));
    await tester.pumpAndSettle();
    expect(find.text('[QA] แชทเก่า'), findsOneWidget);
    expect(adapter.callKeys, isNot(contains('DELETE /api/ai/conversations/7')));
  });

  testWidgets('delete without undo removes it on the server', (tester) async {
    final adapter = await _pump(tester, size: const Size(1200, 900));
    await tester.longPress(find.text('[QA] แชทเก่า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบ').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(adapter.callKeys, contains('DELETE /api/ai/conversations/7'));
  });
}
