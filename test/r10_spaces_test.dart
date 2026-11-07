import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/spaces.dart';

import 'support/fake_api.dart';

Space _space(String id, String url, String uid, String biz) => Space(
      id: id,
      baseUrl: url,
      userId: uid,
      businessName: biz,
      bundle: {
        'api_base_url': url,
        'session_user_id': uid,
        'session_business_id': '1',
        'session_business_name': biz,
        'session_package_code': 'next_x',
        'server_confirmed': true,
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('space title, initials, host and json round-trip', () {
    final s = _space('a', 'https://babcuat.moai-crm.com', '7', 'NEXTX Kit DEV');
    expect(s.title, 'NEXTX Kit DEV');
    expect(s.initials, 'NK');
    expect(s.host, 'babcuat.moai-crm.com');
    expect(Space(id: 'x', baseUrl: 'https://bafcuat.moai-crm.com').title, 'bafcuat.moai-crm.com');
    final back = decodeSpaces(encodeSpaces([s])).single;
    expect(back.bundle['session_business_name'], 'NEXTX Kit DEV');
    expect(findSpaceFor([s], 'https://BABCUAT.moai-crm.com/', '7')?.id, 'a');
    expect(findSpaceFor([s], 'https://babcuat.moai-crm.com', '8'), isNull);
  });

  testWidgets('switching Space restores its server, account, business and token', (tester) async {
    final a = _space('a', 'https://moainext.moai-crm.com', '1', 'บริษัท เอ');
    final b = _space('b', 'https://babcuat.moai-crm.com', '9', 'บริษัท บี');
    SharedPreferences.setMockInitialValues({
      ...a.bundle.map((k, v) => MapEntry('flutter.$k', v as Object)),
      'flutter.spaces_v1': encodeSpaces([a, b]),
      'flutter.spaces_active_v1': 'a',
    });
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok-a', 'space_token_a': 'tok-a', 'space_token_b': 'tok-b'});
    final config = AppConfig();
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && !config.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(config.activeSpace?.id, 'a');
      expect(config.session.accessToken, 'tok-a');

      await config.switchSpace('b');
      expect(config.activeSpace?.id, 'b');
      expect(config.apiBaseUrl, 'https://babcuat.moai-crm.com');
      expect(config.session.userId, '9');
      expect(config.session.businessName, 'บริษัท บี');
      expect(config.session.accessToken, 'tok-b');

      await config.switchSpace('a');
      expect(config.apiBaseUrl, 'https://moainext.moai-crm.com');
      expect(config.session.accessToken, 'tok-a');
      expect(config.spaces.length, 2);
    });
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('renaming a Space keeps it; removing another Space keeps the current one', (tester) async {
    final a = _space('a', 'https://moainext.moai-crm.com', '1', 'บริษัท เอ');
    final b = _space('b', 'https://bafcuat.moai-crm.com', '9', 'บริษัท บี');
    SharedPreferences.setMockInitialValues({
      ...a.bundle.map((k, v) => MapEntry('flutter.$k', v as Object)),
      'flutter.spaces_v1': encodeSpaces([a, b]),
      'flutter.spaces_active_v1': 'a',
    });
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok-a', 'space_token_a': 'tok-a'});
    final config = AppConfig();
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({}));
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && !config.isReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await config.updateSpace('b', label: 'UAT ลูกค้า', colorValue: 0xFF10B981);
      expect(config.spaces.firstWhere((s) => s.id == 'b').title, 'UAT ลูกค้า');
      await config.removeSpace('b');
      expect(config.spaces.map((s) => s.id), ['a']);
      expect(config.activeSpace?.id, 'a');
      expect(config.session.accessToken, 'tok-a');
    });
    await tester.pump(const Duration(minutes: 5));
  });
}
