import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/notebook/notebook_home_screen.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('library ⋮ → delete all my recordings → confirm → DELETE /api/comm-ai/me/notebook-recordings', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, displayName: 'QA'));
    final adapter = FakeNextxAdapter({
      'GET /api/ai/notebooks': {'items': <Object>[]},
      'DELETE /api/comm-ai/me/notebook-recordings': {'recordings': 2, 'segments': 9, 'files': 2, 'sources': 2, 'notes': 2, 'notebook_ids': [3]},
    });
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: NotebookHomeScreen())));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.byKey(const ValueKey('notebook-home-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notebook-delete-my-recordings')));
    await tester.pumpAndSettle();
    expect(find.text('ไฟล์เสียงที่ฉันบันทึกในสมุดโน้ตทุกเล่ม'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ').last);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(adapter.callKeys, contains('DELETE /api/comm-ai/me/notebook-recordings'));
    expect(find.text('ลบบันทึกเสียงแล้ว 2 รายการ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
