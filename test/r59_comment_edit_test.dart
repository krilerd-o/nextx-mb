import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';

import 'support/fake_api.dart';

void main() {
  test('comment text for editing keeps line breaks and drops tags', () {
    expect(commentPlainText('<p>สวัสดี</p><p>ลูกค้า &amp; ทีม</p>'), 'สวัสดี\nลูกค้า & ทีม');
    expect(commentPlainText('แถว 1<br/>แถว 2<img src="x.png">'), 'แถว 1\nแถว 2');
  });

  testWidgets('own comment can be edited; others only by admins', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'PUT /api/entity/contact/3/comments/11': {'id': 11, 'body': 'แก้แล้ว', 'attachments': []},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['contact']));
    config.apiClient.debugSetHttpAdapter(adapter);
    var reloads = 0;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EntityCommentsPanel(
              module: 'contact',
              id: '3',
              comments: const [
                {'id': 11, 'user_id': 2, 'user_name': 'ฉัน', 'body': 'พิมพ์ผิด', 'created_at': '2026-11-11T03:00:00Z'},
                {'id': 12, 'user_id': 9, 'user_name': 'เพื่อน', 'body': 'ของคนอื่น', 'created_at': '2026-11-11T03:01:00Z'},
              ],
              onChanged: () async => reloads++,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-edit-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-edit-12')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('comment-edit-11')));
    await tester.pumpAndSettle();
    expect(find.text('พิมพ์ผิด'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('comment-edit-field')), 'แก้แล้ว');
    await tester.tap(find.byKey(const ValueKey('comment-edit-save')));
    await tester.pumpAndSettle();
    final put = adapter.calls.where((c) => c.method == 'PUT').single;
    expect(put.path, '/api/entity/contact/3/comments/11');
    final data = put.data is String ? jsonDecode(put.data as String) : put.data;
    expect(data['body'], 'แก้แล้ว');
    expect(reloads, 1);
  });
}
