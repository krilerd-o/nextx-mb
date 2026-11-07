import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/mail/external_mail_compose_screen.dart';
import 'package:nextx_mobile/screens/mail/mail_compose_screen.dart';
import 'package:nextx_mobile/screens/mail/mail_home_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('connection rows become mail accounts; others are skipped', () {
    expect(MailAccount.fromMap({'id': 3, 'provider': 'gmail', 'email': 'a@x.com'})!.query, {'source': 'gmail', 'connectionId': '3'});
    expect(MailAccount.fromMap({'id': 4, 'provider': 'imap'}), isNull);
  });

  test('email list parsing and reply seed', () {
    expect(parseEmails('a@x.com, bad; b@y.co'), ['a@x.com', 'b@y.co']);
    final r = externalSeed(MailComposeMode.reply, {'id': 'm1', 'thread_id': 't1', 'subject': 'Hello', 'from_email': 'c@z.com'});
    expect(r.to, ['c@z.com']);
    expect(r.subject, 'Re: Hello');
    expect(r.replyToId, 'm1');
    expect(r.threadId, 't1');
  });

  test('external send carries source, connectionId and emails', () async {
    final adapter = FakeNextxAdapter({'POST /api/mail': {'id': 'x'}});
    final api = ApiClient(dio: Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter);
    await api.sendExternalMail(
      account: const MailAccount(id: '3', provider: 'outlook', email: 'me@x.com'),
      to: ['a@x.com'],
      subject: 'Hi',
      bodyHtml: '<p>yo</p>',
    );
    final body = adapter.calls.single.data as Map;
    expect(body['source'], 'outlook');
    expect(body['connectionId'], 3);
    expect(body['to'], ['a@x.com']);
    expect(body['body'], 'yo');
  });

  testWidgets('switching to Gmail lists its inbox with stars', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/mail/connections': {'list': [{'id': 3, 'provider': 'gmail', 'email': 'me@gmail.com', 'status': 'active'}]},
      'GET /api/mail': {'list': [
        {'id': 'g1', 'subject': 'ใบเสนอราคา', 'from_display': 'ลูกค้า A', 'starred': true, 'read_at': null, 'has_attachments': true},
      ]},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['mailbox']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: MailHomeScreen())));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byTooltip('เลือกกล่องเมล'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('me@gmail.com'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final last = adapter.calls.lastWhere((c) => c.path == '/api/mail');
    expect(last.queryParameters['source'], 'gmail');
    expect(last.queryParameters['connectionId'], '3');
    expect(find.text('ติดดาว'), findsWidgets);
    expect(find.text('ใบเสนอราคา'), findsOneWidget);
    expect(find.byTooltip('เอาดาวออก'), findsOneWidget);
  });
}
