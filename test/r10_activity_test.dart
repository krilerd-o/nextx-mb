import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/activity_detail_screen.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('activity opened with only an id loads the record and can be duplicated', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/entity/activity/5': {'id': 5, 'subject': '[QA] เยี่ยมลูกค้า', 'location': 'สยาม'},
      'GET /api/entity/activity/5/comments': {'list': []},
      'GET /api/activity/5/visit': {'checked_in': false},
      'POST /api/entity/activity/5/duplicate': {'id': 9},
      'GET /api/entity/activity/9': {'id': 9, 'subject': '[QA] เยี่ยมลูกค้า (สำเนา)'},
      'GET /api/entity/activity/9/comments': {'list': []},
      'GET /api/activity/9/visit': {'checked_in': false},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['calendar']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: ActivityDetailScreen(row: {'id': 5})),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('[QA] เยี่ยมลูกค้า'), findsWidgets);
    expect(find.text('สยาม'), findsOneWidget);
    expect(find.text('ความคิดเห็น'), findsOneWidget);

    await tester.tap(find.byTooltip('เพิ่มเติม'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ทำซ้ำ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ทำซ้ำ'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(adapter.callKeys, contains('POST /api/entity/activity/5/duplicate'));
  });
}
