import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_version.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/settings/devices_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/profile_harness.dart';

String _isoAgo(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, Object?> _sessions() => {
      'current_sid': 'me',
      'list': [
        {'sid': 'me', 'client': 'mobile', 'platform': 'android', 'device_name': 'Pixel 8', 'app_version': '1.4.0', 'ip': '10.0.0.2', 'last_seen_at': _isoAgo(Duration.zero), 'current': true},
        {'sid': 'web1', 'client': 'web', 'platform': 'windows', 'user_agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/120.0 Safari/537.36', 'ip': '203.0.113.9', 'last_seen_at': _isoAgo(const Duration(hours: 3))},
        {'sid': 'ios1', 'client': 'mobile', 'platform': 'ios', 'device_name': 'iPhone ของสมชาย', 'app_version': '1.3.9', 'last_seen_at': _isoAgo(const Duration(days: 2))},
      ],
    };

void main() {
  setUp(() => ApiClient.deviceHeaders = const {'X-Device-Name': 'Galaxy%20S24', 'X-Device-Platform': 'android', 'X-App-Version': '1.4.0'});
  tearDown(() => ApiClient.deviceHeaders = const {});

  test('device labels: browser from the user agent, Bangkok last active', () {
    expect(browserFromUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit Safari/605.1'), 'Safari · macOS');
    expect(browserFromUserAgent('Mozilla/5.0 (Windows NT 10.0) Chrome/120.0 Safari/537.36 Edg/120.0'), 'Edge · Windows');
    expect(deviceDisplayName({'client': 'web', 'platform': 'windows', 'user_agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/120 Safari/537'}), 'Chrome · Windows');
    expect(deviceDisplayName({'client': 'mobile', 'platform': 'ios'}), 'แอป iPhone');
    // 07:05 UTC = 14:05 in Bangkok.
    expect(deviceLastActive('2026-01-02T07:05:00Z'), '02/01/2569 14:05');
    expect(formatThaiField('2026-01-02T07:05:00Z', null), '02/01/2026 14:05');
  });

  testWidgets('this device card, other devices with version, IP and last active', (tester) async {
    await pumpProfilePage(tester, const DevicesScreen(), {'GET /api/me/sessions': _sessions()}, size: const Size(430, 2400));
    final me = find.byKey(const ValueKey('dev-this-device'));
    expect(find.descendant(of: me, matching: find.text('Pixel 8')), findsOneWidget);
    expect(find.descendant(of: me, matching: find.text('เครื่องนี้')), findsOneWidget);
    expect(find.descendant(of: me, matching: find.text('แอป Android')), findsOneWidget);
    expect(find.descendant(of: me, matching: find.textContaining('1.4.0')), findsOneWidget);
    expect(find.text('อุปกรณ์อื่น (2)'.toUpperCase()), findsOneWidget);
    expect(find.text('Chrome · Windows'), findsOneWidget);
    expect(find.text('203.0.113.9'), findsOneWidget);
    expect(find.text('iPhone ของสมชาย'), findsOneWidget);
    expect(find.text('แอป iPhone · v1.3.9'), findsOneWidget);
    final seen = tester.widget<Text>(find.byKey(const ValueKey('dev-seen-web1'))).data!;
    expect(seen, contains('3 ชั่วโมงที่แล้ว'));
    expect(seen, matches(RegExp(r'\d{2}/\d{2}/25\d{2} \d{2}:\d{2}')), reason: 'absolute Bangkok time, BE year');
    // Moved here from settings.
    for (final k in ['dev-tab-editor', 'dev-role-editor', 'dev-home-editor']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
  });

  testWidgets('sign one device out after confirming; cancel sends nothing', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const DevicesScreen(), {
      'GET /api/me/sessions': _sessions(),
      'DELETE /api/me/sessions/web1': {'revoked': 'web1'},
    }, size: const Size(430, 2400));
    await tester.tap(find.byKey(const ValueKey('dev-kick-web1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dev-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(api.callKeys, isNot(contains('DELETE /api/me/sessions/web1')));
    await tester.tap(find.byKey(const ValueKey('dev-kick-web1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dev-confirm-ok')));
    await tester.pumpAndSettle();
    expect(callCount(api, 'DELETE /api/me/sessions/web1'), 1);
  });

  testWidgets('sign out all other devices', (tester) async {
    final (config, api) = await pumpProfilePage(tester, const DevicesScreen(), {
      'GET /api/me/sessions': _sessions(),
      'POST /api/me/sessions/revoke-others': {'ok': true},
    }, size: const Size(430, 2400));
    expect(find.text('ออกจากระบบอุปกรณ์อื่นทั้งหมด (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dev-revoke-others')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dev-confirm-ok')));
    await tester.pumpAndSettle();
    expect(callCount(api, 'POST /api/me/sessions/revoke-others'), 1);
    expect(config.isLoggedIn, isTrue, reason: 'this device stays signed in');
  });

  testWidgets('server says unavailable → this device + a gentle note, not a blank page', (tester) async {
    await pumpProfilePage(tester, const DevicesScreen(), {
      'GET /api/me/sessions': {'list': [], 'current_sid': null, 'unavailable': true},
    });
    expect(find.byKey(const ValueKey('dev-this-device')), findsOneWidget);
    expect(find.text('Galaxy S24'), findsOneWidget, reason: 'name from the headers this app sends');
    expect(find.textContaining(AppVersion.value), findsWidgets);
    expect(find.byKey(const ValueKey('dev-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('dev-revoke-others')), findsNothing);
  });

  testWidgets('older server (404) → same: this device + note', (tester) async {
    await pumpProfilePage(tester, const DevicesScreen(), const {});
    expect(find.byKey(const ValueKey('dev-this-device')), findsOneWidget);
    expect(find.byKey(const ValueKey('dev-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('dev-error')), findsNothing);
  });
}
