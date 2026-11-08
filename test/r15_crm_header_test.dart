import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CRM list header shows the NEXTX menu name and the current view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/modules': [
        {'name': 'Lead', 'tablabel': '[QA] ลีดของฉัน', 'tablabel_en': 'My leads'},
      ],
      'GET /api/customviews': {
        'list': [
          {'id': 1, 'name': 'All', 'is_system': true, 'is_default': true},
          {'id': 2, 'name': '[QA] ลีดร้อน', 'is_system': false},
        ],
        'default_id': '1',
      },
      'GET /api/entity/lead': {'list': [], 'total': 0},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง')),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(adapter.callKeys, contains('GET /api/modules'));
    expect(find.text('[QA] ลีดของฉัน'), findsOneWidget, reason: 'menu name from aicrm_tab, not the built-in title');
    expect(find.text('ผู้มุ่งหวัง'), findsNothing);
    final cvRow = find.byKey(const ValueKey('crm-cv-row'));
    expect(cvRow, findsOneWidget);
    expect(find.descendant(of: cvRow, matching: find.text('ทั้งหมด')), findsOneWidget);
  });
}
