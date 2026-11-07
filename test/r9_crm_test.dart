import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('comments group into threads; replies oldest first', () {
    final t = threadComments([
      {'id': 1, 'created_at': '2026-11-01T10:00:00Z'},
      {'id': 2, 'parent_id': 1, 'created_at': '2026-11-01T12:00:00Z'},
      {'id': 3, 'parent_id': 1, 'created_at': '2026-11-01T11:00:00Z'},
      {'id': 4, 'created_at': '2026-11-02T10:00:00Z'},
    ]);
    expect(t.map((e) => e.$1['id']), [4, 1]);
    expect(t[1].$2.map((e) => e['id']), [3, 2]);
  });

  test('timeline field change reads as old → new', () {
    final d = describeTimelineEvent({'type': 'field_change', 'field_label_th': 'สถานะ', 'old_value': 'New', 'new_value': 'Qualified'});
    expect(d.title, 'แก้ สถานะ');
    expect(d.detail, 'New → Qualified');
    final th = describeTimelineEvent(
      {'type': 'field_change', 'field_name': 'lead_status', 'old_value': 'New', 'new_value': 'Qualified'},
      valueLabel: (f, v) => {'New': 'ใหม่', 'Qualified': 'ผ่านเกณฑ์'}[v] ?? v,
    );
    expect(th.detail, 'ใหม่ → ผ่านเกณฑ์');
    expect(describeTimelineEvent({'type': 'engagement', 'event_type': 'comment'}).title, 'แสดงความคิดเห็น');
  });

  test('status key picks module field first', () {
    expect(entityStatusKey({'lead_status': 'New', 'status': 'x'}, 'lead'), 'lead_status');
  });

  testWidgets('delete waits for undo window; undo keeps the record', (tester) async {
    var deleted = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      return TextButton(
        onPressed: () => PendingEntityDeletes.instance.schedule(
          messenger: ScaffoldMessenger.of(context),
          module: 'lead',
          ids: ['9'],
          label: 'ลีด A',
          commit: () async => deleted++,
        ),
        child: const Text('ลบ'),
      );
    }))));
    await tester.tap(find.text('ลบ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(PendingEntityDeletes.instance.isPending('lead', '9'), isTrue);
    expect(find.text('เลิกทำ'), findsOneWidget);
    await tester.tap(find.byType(SnackBarAction), warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(find.text('เลิกทำ'), findsNothing);
    expect(deleted, 0);
    expect(PendingEntityDeletes.instance.isPending('lead', '9'), isFalse);
  });

  testWidgets('detail shows tabs, status stepper and loads history', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/entity/lead/5': {'id': 5, 'lead_no': 'L1', 'lead_name': 'คุณเอ', 'lead_status': 'New'},
      'GET /api/entity/lead/5/comments': {'list': [
        {'id': 1, 'user_name': 'บี', 'body': 'สวัสดี', 'created_at': '2026-11-01T10:00:00Z', 'attachments': [
          {'url': '/uploads/a.png', 'name': 'a.png', 'mime': 'image/png'},
        ]},
      ]},
      'GET /api/entity/lead/5/tags': {'list': []},
      'GET /api/tags': {'list': []},
      'GET /api/fields/lead': {
        'fields': [
          {'name': 'lead_name', 'label_th': 'ชื่อ'},
          {'name': 'lead_status', 'label_th': 'สถานะ', 'uitype': 'picklist'},
        ],
        'picklists': {
          'lead_status': [
            {'value': 'New', 'label': 'ใหม่'},
            {'value': 'Qualified', 'label': 'ผ่านเกณฑ์'},
          ],
        },
      },
      'GET /api/entity/lead/5/timeline': {'list': [
        {'type': 'field_change', 'field_name': 'lead_status', 'field_label_th': 'สถานะ', 'old_value': 'New', 'new_value': 'Qualified', 'at': '2026-11-02T10:00:00Z', 'user_name': 'บี'},
      ]},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityDetailScreen(module: 'lead', row: {'id': 5})),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('คุณเอ'), findsWidgets);
    expect(find.text('ความคิดเห็น 1'), findsOneWidget);
    await tester.tap(find.text('ประวัติ'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(adapter.callKeys, contains('GET /api/entity/lead/5/timeline'));
    expect(find.text('ใหม่ → ผ่านเกณฑ์'), findsOneWidget);
  });
}
