import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/settings/devices_screen.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('device kind labels', () {
    expect(deviceKind({'platform': 'android', 'client': 'mobile'}).$2, 'แอป Android');
    expect(deviceKind({'platform': 'windows', 'client': 'web'}).$2, 'เว็บบนคอมพิวเตอร์');
  });

  testWidgets('without device_sessions only "this device" sign-out is offered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1'));
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: DevicesScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ออกจากระบบเครื่องนี้'), findsOneWidget);
    expect(find.textContaining('ออกจากระบบอุปกรณ์อื่น'), findsNothing);
    expect(find.textContaining('ยังไม่รองรับ'), findsOneWidget);
  });
}
