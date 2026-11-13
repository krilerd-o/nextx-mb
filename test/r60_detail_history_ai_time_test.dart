import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_cards.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('AI proposal card shows a contact blacklist time in Thai time', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiProposalCard(
          proposal: const {
            'proposalId': 'p1',
            'tool': 'update_record',
            'preview': {
              'module': 'contact',
              'fields': {'blacklist_datetime': '2026-11-11T03:37:00.000Z'},
            },
          },
          state: null,
          onConfirm: () {},
          onCancel: () {},
        ),
      ),
    ));
    expect(find.textContaining('10:37'), findsOneWidget);
    expect(find.textContaining('03:37'), findsNothing);
  });

  testWidgets('a record opened straight on the history tab loads its timeline', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    SharedPreferences.setMockInitialValues({});
    const contact = {'id': 4, 'firstname': '[QA]', 'lastname': 'ประวัติ'};
    final adapter = FakeNextxAdapter({
      'GET /api/fields/contact': {'list': [{'name': 'firstname', 'label_th': 'ชื่อ'}], 'picklists': {}},
      'GET /api/entity/contact/4': contact,
      'GET /api/entity/contact/4/comments': {'list': []},
      'GET /api/entity/contact/4/timeline': {
        'list': [
          {'type': 'field_change', 'field_name': 'firstname', 'field_label_th': 'ชื่อ', 'old_value': 'เก่า', 'new_value': '[QA]', 'at': '2026-11-11T03:37:00.000Z'},
        ],
      },
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['contact']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityDetailScreen(module: 'contact', row: contact, initialTab: 'history')),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(adapter.callKeys, contains('GET /api/entity/contact/4/timeline'));
  });
}
