import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/navigation/push_tap.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/push_navigation.dart';
import 'package:nextx_mobile/screens/notifications/announcement_screen.dart';
import 'package:nextx_mobile/screens/notifications/notification_center_screen.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/screens/settings/devices_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/app_icon_badge.dart';
import 'package:nextx_mobile/services/device_push_service.dart';
import 'package:nextx_mobile/services/unread_service.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';
import 'package:nextx_mobile/widgets/nx_notification_view.dart';

import 'support/fake_api.dart';
import 'support/profile_harness.dart';

class _FakeBadge implements AppIconBadgeBackend {
  final calls = <int>[];
  @override
  Future<void> update(int count) async => calls.add(count);
}

String _isoAgo(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, Object?> _prefs() => {
      'channels': [
        {'key': 'push', 'label_th': 'มือถือ'},
        {'key': 'in_app', 'label_th': 'กระดิ่ง'},
      ],
      'push_paused': false,
      'groups': [
        {
          'key': 'work',
          'label_th': 'งาน',
          'events': [
            {'key': 'work_assigned', 'label_th': 'ได้รับมอบหมายงาน', 'channels': {'push': true, 'in_app': true}},
          ],
        },
      ],
    };

void main() {
  group('chat deep link: room is right with new and old payloads', () {
    test('new server: id = room, notification_id = bell row', () {
      expect(notificationDeepLinkFromData({'event': 'chat_message', 'url': '/camp?room=5&mid=9', 'id': '5', 'notification_id': '880'}), '/chat/5');
      expect(notificationDeepLinkFromData({'event': 'chat_message', 'url': '/camp', 'id': '5', 'notification_id': '880'}), '/chat/5');
      expect(notificationDeepLinkFromData({'event': 'chat_mention', 'url': '/community-chat', 'link_id': '6', 'id': '6', 'notification_id': '1'}), '/chat/6');
    });

    test('old server: id = bell row → the room of the url, never /chat/<bell row>', () {
      expect(notificationDeepLinkFromData({'event': 'chat_message', 'url': '/camp?room=5&mid=9', 'id': '880', 'notification_id': '880'}), '/chat/5');
      expect(notificationDeepLinkFromData({'url': '/community-chat?room=6', 'id': '881', 'notification_id': '881'}), '/chat/6');
      expect(notificationDeepLinkFromData({'event': 'chat_message', 'url': '/camp', 'id': '880', 'notification_id': '880'}), AppRoutes.chatHome);
      // Even with a different id, the url's room wins.
      expect(notificationDeepLinkFromData({'url': '/camp?room=5', 'id': '880'}), '/chat/5');
    });

    test('record id of a push', () {
      expect(pushRecordId({'id': '5', 'notification_id': '880'}), '5');
      expect(pushRecordId({'id': '880', 'notification_id': '880'}), isNull);
      expect(pushRecordId({'link_id': '7', 'id': '880', 'notification_id': '880'}), '7');
      expect(pushRecordId({'id': ''}), isNull);
      expect(pushChatRoom({'url': '/camp?room=9', 'id': '1'}), '9');
      expect(pushChatRoom({'event': 'chat_message', 'url': '/camp', 'id': '4', 'notification_id': '2'}), '4');
      expect(pushChatRoom({'event': 'work_assigned', 'url': '/workspace/X-1', 'id': '4'}), isNull);
    });
  });

  group('announcements', () {
    tearDown(() {
      PushNavigation.instance.take();
      pushStoreLauncher = (uri) async => false;
    });

    test('push / bell row → /announcements/:id (with the bell row to mark read)', () {
      expect(notificationDeepLinkFromData({'event': 'announcement', 'url': '/announcements/77', 'id': '77', 'notification_id': '901'}), '/announcements/77?n=901');
      // Maintenance / general notices come as system_notice.
      expect(notificationDeepLinkFromData({'event': 'system_notice', 'url': '/announcements/79', 'id': '79', 'notification_id': '903'}), '/announcements/79?n=903');
      // No event but an announcement link.
      expect(notificationDeepLinkFromData({'url': '/announcements/80'}), '/announcements/80');
      expect(notificationItemRoute({'id': 901, 'type': 'announcement', 'link_path': '/announcements/77'}), '/announcements/77?n=901');
      // Older rows without a link still open in the center.
      expect(notificationItemRoute({'id': 5, 'type': 'announcement', 'link_path': null}), '/notifications?id=5');
      expect(AppRoutes.announcement('7'), '/announcements/7');
      expect(announcementIdOf('https://evil.example.com/announcements/1'), isNull);
      // Same access as the notification center: not gated by a menu.
      expect(requiredMenusFor('/announcements/77'), isNull);
    });

    test('app_update: store when usable, else the announcement, else the notification', () async {
      final opened = <Uri>[];
      pushStoreLauncher = (uri) async {
        opened.add(uri);
        return true;
      };
      await handlePushTap({'event': 'app_update', 'url': '/announcements/78', 'id': '78', 'notification_id': '902', 'store_android': 'https://play.google.com/store/apps/details?id=x', 'store_ios': 'https://apps.apple.com/app/id1'});
      expect(opened, hasLength(1));
      expect(PushNavigation.instance.pending, isNull);

      // Round-1 system broadcast: the store link was the url.
      expect(appStoreLinkOf({'event': 'app_update', 'url': 'https://play.google.com/store/apps/details?id=y'}, ios: false), contains('id=y'));
      expect(appStoreLinkOf({'store_ios': 'https://apps.apple.com/app/id1'}, ios: false), contains('apple'), reason: 'other platform as a fallback');
      expect(appStoreLinkOf({'store_android': 'javascript:alert(1)'}, ios: false), isNull);

      pushStoreLauncher = (uri) async => false;
      await handlePushTap({'event': 'app_update', 'url': '/announcements/78', 'id': '78', 'notification_id': '902', 'store_android': 'https://play.google.com/x'});
      expect(PushNavigation.instance.take(), '/announcements/78?n=902');

      await handlePushTap({'event': 'app_update', 'url': '/announcements/78', 'notification_id': '902'});
      expect(PushNavigation.instance.take(), '/announcements/78?n=902', reason: 'no store link → the announcement');

      await handlePushTap({'event': 'app_update', 'notification_id': '902'});
      expect(PushNavigation.instance.take(), '/notifications?id=902');
    });

    testWidgets('reader: kind, title, sender, Thai date, body; bell row marked read', (tester) async {
      final (_, api) = await pumpProfilePage(tester, const AnnouncementScreen(id: '77', notificationId: '901'), {
        'GET /api/announcements/77': {
          'id': 77,
          'kind': 'maintenance',
          'title': 'ปิดปรับปรุงระบบ **คืนวันเสาร์**',
          'body': 'ระบบจะปิดปรับปรุง 22:00–23:00 น.\nขออภัยในความไม่สะดวก',
          'created_at': '2026-11-14T02:30:00Z',
          'sender_name': 'ฝ่ายไอที',
        },
        'PATCH /api/notifications/901/read': {},
        'GET /api/notifications/summary': {'total': 0},
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ann-card')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('ann-kind')), matching: find.text('ปิดปรับปรุงระบบ')), findsOneWidget);
      expect(find.text('ปิดปรับปรุงระบบ คืนวันเสาร์', findRichText: true), findsOneWidget);
      expect(find.text('จาก ฝ่ายไอที'), findsOneWidget);
      // 02:30 UTC = 09:30 Bangkok, BE year.
      expect(tester.widget<Text>(find.byKey(const ValueKey('ann-date'))).data, '14/11/2569 09:30');
      expect(find.textContaining('ขออภัยในความไม่สะดวก', findRichText: true), findsOneWidget);
      final bodyText = tester.widget<SelectableText>(find.byKey(const ValueKey('ann-body'))).textSpan!.toPlainText();
      expect(bodyText, contains('23:00 น.\nขออภัย'), reason: 'line breaks kept');
      expect(find.byKey(const ValueKey('ann-update')), findsNothing, reason: 'not an app update');
      expect(callCount(api, 'PATCH /api/notifications/901/read'), 1);
      expect(callCount(api, 'GET /api/announcements/77'), 1);
    });

    testWidgets('app_update: "อัปเดตแอป" opens the store of this platform', (tester) async {
      final opened = <Uri>[];
      pushStoreLauncher = (uri) async {
        opened.add(uri);
        return true;
      };
      addTearDown(() => pushStoreLauncher = (uri) async => false);
      await pumpProfilePage(tester, const AnnouncementScreen(id: '78', ios: true), {
        'GET /api/announcements/78': {
          'id': 78,
          'kind': 'app_update',
          'title': 'MOAI NEXT เวอร์ชันใหม่',
          'body': 'แก้ปัญหาการแจ้งเตือน',
          'created_at': '2026-11-14 09:00:00',
          'store_android': 'https://play.google.com/store/apps/details?id=com.moai.nextt.mobile',
          'store_ios': 'https://apps.apple.com/app/id123',
        },
      });
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('ann-kind')), matching: find.text('อัปเดตแอป')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ann-update')));
      await tester.pumpAndSettle();
      expect(opened.single.host, 'apps.apple.com');
    });

    testWidgets('missing fields are fine', (tester) async {
      await pumpProfilePage(tester, const AnnouncementScreen(id: '79'), {
        'GET /api/announcements/79': {'id': 79, 'title': 'ประกาศ'},
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ann-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('ann-sender')), findsNothing);
    });

    testWidgets('404: not there', (tester) async {
      await pumpProfilePage(tester, const AnnouncementScreen(id: '404'), {});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ann-error')), findsOneWidget);
      expect(find.text('ไม่พบประกาศนี้'), findsOneWidget);
    });
  });

  group('app icon badge', () {
    late _FakeBadge fake;
    setUp(() {
      fake = _FakeBadge();
      AppIconBadge.instance
        ..backend = fake
        ..debugReset();
    });
    tearDown(() {
      UnreadNotifications.instance.clear();
      AppIconBadge.instance.backend = PluginAppIconBadge();
    });

    test('follows the unread count: start, foreground push, read, read all', () async {
      final unread = UnreadNotifications.instance;
      unread.clear();
      expect(fake.calls, [0], reason: 'first set even when 0 (clears a stale badge)');
      final api = ApiClient()..debugSetHttpAdapter(FakeNextxAdapter({'GET /api/notifications/summary': {'total': 4}}));
      await unread.refresh(api);
      expect(fake.calls.last, 4);
      await onForegroundPush({'event': 'work_assigned', 'badge': '9'}, hasNotification: true, ios: true, show: () async {});
      expect(fake.calls.last, 9);
      unread.markedRead();
      expect(fake.calls.last, 8);
      unread.clear();
      expect(fake.calls.last, 0);
      final before = fake.calls.length;
      unread.clear();
      expect(fake.calls.length, before, reason: 'same number: no extra call');
    });

    test('a failing plugin never throws', () async {
      AppIconBadge.instance.backend = _ThrowingBadge();
      await AppIconBadge.instance.set(3);
      expect(AppIconBadge.instance.last, 3);
    });

    testWidgets('logout clears it', (tester) async {
      final (config, _) = await pumpProfilePage(tester, const SizedBox(), {'GET /api/notifications/summary': {'total': 5}});
      await tester.runAsync(() => UnreadNotifications.instance.refresh(config.apiClient));
      expect(fake.calls.last, 5);
      await tester.runAsync(config.logout);
      expect(fake.calls.last, 0);
    });
  });

  group('Android foreground notifications', () {
    test('chat: one slot per room, a new message replaces the old one', () {
      final a = foregroundNotificationSlot({'event': 'chat_message', 'url': '/camp?room=5&mid=1', 'id': '5', 'notification_id': '10'}, fallbackId: 1);
      final b = foregroundNotificationSlot({'event': 'chat_message', 'url': '/camp?room=5&mid=2', 'id': '5', 'notification_id': '11'}, fallbackId: 2);
      final c = foregroundNotificationSlot({'event': 'chat_message', 'url': '/camp?room=6&mid=3', 'id': '6', 'notification_id': '12'}, fallbackId: 3);
      expect(a.id, b.id);
      expect(a.tag, 'chat-5');
      expect(b.tag, 'chat-5');
      expect(c.id, isNot(a.id));
      expect(c.tag, 'chat-6');
      // Old payload (id = bell row) still groups by the url's room.
      expect(foregroundNotificationSlot({'event': 'chat_message', 'url': '/camp?room=5', 'id': '99', 'notification_id': '99'}, fallbackId: 4).tag, 'chat-5');
      // Not a chat message: its own notification.
      final w = foregroundNotificationSlot({'event': 'work_assigned', 'url': '/workspace/X-1', 'id': '1'}, fallbackId: 77);
      expect((w.id, w.tag), (77, null));
      final call = foregroundNotificationSlot({'event': 'call_missed', 'url': '/camp?room=5', 'id': '5'}, fallbackId: 78);
      expect(call.tag, isNull, reason: 'a missed call is not replaced by messages');
      // The tag reaches Android.
      final details = foregroundNotificationDetails(tag: a.tag, badge: 3);
      expect(details.android!.tag, 'chat-5');
      expect(details.android!.number, 3);
      expect(details.android!.channelId, 'high_importance_channel');
      expect(details.android!.importance, Importance.high);
    });

    test('high_importance_channel: high importance with sound', () {
      expect(highImportanceChannel.id, 'high_importance_channel');
      expect(highImportanceChannel.importance, Importance.high);
      expect(highImportanceChannel.playSound, isTrue);
      expect(highImportanceChannel.showBadge, isTrue);
    });
  });

  group('devices: อุปกรณ์ที่รับแจ้งเตือน', () {
    setUp(() => ApiClient.deviceHeaders = const {'X-Device-Name': 'Galaxy%20S24', 'X-Device-Platform': 'android'});
    tearDown(() => ApiClient.deviceHeaders = const {});

    testWidgets('lists the push devices: platform, name, last seen, this phone first', (tester) async {
      await pumpProfilePage(tester, const DevicesScreen(), {
        'GET /api/me/sessions': {'current_sid': 'me', 'list': []},
        'GET /api/notifications/devices': {
          'items': [
            {'id': 2, 'platform': 'ios', 'device_name': 'iPhone ของสมชาย', 'last_seen_at': _isoAgo(const Duration(days: 2))},
            {'id': 1, 'platform': 'android', 'device_name': 'Galaxy S24', 'last_seen_at': _isoAgo(const Duration(minutes: 5)), 'current': true},
            {'id': 3, 'platform': 'web', 'last_seen_at': _isoAgo(const Duration(hours: 3))},
          ],
        },
      }, size: const Size(430, 2600));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dev-push')), findsOneWidget);
      expect(find.text('อุปกรณ์ที่รับแจ้งเตือน (3)'), findsOneWidget);
      expect(find.byKey(const ValueKey('dev-push-this-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('dev-push-this-2')), findsNothing);
      expect(find.text('iPhone ของสมชาย'), findsOneWidget);
      expect(find.text('iPhone / iPad'), findsOneWidget);
      expect(find.text('เบราว์เซอร์'), findsOneWidget, reason: 'no name → the platform');
      final seen = tester.widget<Text>(find.byKey(const ValueKey('dev-push-seen-3'))).data!;
      expect(seen, contains('3 ชั่วโมงที่แล้ว'));
      expect(seen, matches(RegExp(r'\d{2}/\d{2}/25\d{2} \d{2}:\d{2}')));
      // This phone is listed first.
      final y1 = tester.getTopLeft(find.byKey(const ValueKey('dev-push-1'))).dy;
      final y2 = tester.getTopLeft(find.byKey(const ValueKey('dev-push-2'))).dy;
      expect(y1, lessThan(y2));
      expect(pushDeviceKind('huawei').$2, 'Huawei');
    });

    testWidgets('older server (404): no section', (tester) async {
      await pumpProfilePage(tester, const DevicesScreen(), {'GET /api/me/sessions': {'current_sid': 'me', 'list': []}}, size: const Size(430, 2400));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dev-push')), findsNothing);
      expect(find.byKey(const ValueKey('dev-this-device')), findsOneWidget);
    });
  });

  group('language → server', () {
    tearDown(() => L10n.set('th'));

    testWidgets('switching TH/EN sends PUT /api/me/language; 404 is ignored', (tester) async {
      final (config, api) = await pumpProfilePage(tester, const SizedBox(), {'PUT /api/me/language': {'lang': 'en'}});
      await tester.runAsync(() => config.setUiLocaleCode('en'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(bodyOf(api, 'PUT', '/api/me/language'), {'lang': 'en'});
      // Already known → not again at the next start.
      final n = callCount(api, 'PUT /api/me/language');
      await tester.runAsync(config.syncServerLanguage);
      expect(callCount(api, 'PUT /api/me/language'), n);

      // Older server: 404, nothing breaks, the app is in Thai again.
      api.replies.remove('PUT /api/me/language');
      await tester.runAsync(() => config.setUiLocaleCode('th'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(config.uiLocaleCode, 'th');
      expect(bodyOf(api, 'PUT', '/api/me/language'), {'lang': 'th'});
      expect(tester.takeException(), isNull);
    });

    testWidgets('once after start when the server does not know yet', (tester) async {
      final (config, api) = await pumpProfilePage(tester, const SizedBox(), {'PUT /api/me/language': {'lang': 'th'}});
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(config.syncServerLanguage);
      expect(bodyOf(api, 'PUT', '/api/me/language'), {'lang': 'th'});
      final n = callCount(api, 'PUT /api/me/language');
      await tester.runAsync(config.syncServerLanguage);
      expect(callCount(api, 'PUT /api/me/language'), n);
      await tester.runAsync(() => config.syncServerLanguage(force: true));
      expect(callCount(api, 'PUT /api/me/language'), n + 1);
    });

    test('not signed in: nothing is sent', () async {
      SharedPreferences.setMockInitialValues({});
      final config = AppConfig();
      final adapter = FakeNextxAdapter({});
      config.apiClient.debugSetHttpAdapter(adapter);
      await config.syncServerLanguage(force: true);
      expect(adapter.callKeys, isNot(contains('PUT /api/me/language')));
    });
  });

  group('notification center: every server category', () {
    test('categories and their look', () {
      expect(notificationCategoryKeys, containsAll(['hr', 'contract', 'store', 'ai', 'other', 'social']));
      expect(notifCategory({'link_path': '/hr/leave-management'}), 'hr');
      expect(notifCategory({'link_path': '/commercial-store/orders/9'}), 'store');
      expect(notifCategory({'link_path': '/ai?c=1', 'type': 'ai_job'}), 'ai');
      expect(notifCategory({'link_path': '/modules/service_contract?open=3'}), 'contract');
      expect(notifCategory({'meta': {'module': 'hr'}}), 'hr');
      expect(notifCategory({'link_path': '/'}), 'other');
      expect(notifCategoryStyle('hr').label, 'บุคคล');
      expect(notifCategoryStyle('store').icon, NxI.package);
      expect(notifCategoryStyle('ai').icon, NxI.sparkle);
    });

    testWidgets('chips with Thai labels + icons; picking one asks the server for it', (tester) async {
      final (_, api) = await pumpProfilePage(tester, const NotificationCenterScreen(), {
        'GET /api/notifications': {
          'items': [
            {'id': 1, 'type': 'leave', 'title': 'คำขอลาใหม่', 'link_path': '/hr/leave-management', 'read_at': null, 'created_at': '2026-11-14 09:00:00'},
          ],
        },
        'GET /api/notifications/summary': {'total': 1},
      }, size: const Size(430, 1600));
      await tester.pumpAndSettle();
      for (final label in ['บุคคล', 'สัญญา', 'ร้านค้า', 'AI', 'อื่นๆ']) {
        expect(find.widgetWithText(FilterChip, label), findsOneWidget, reason: label);
      }
      expect(find.descendant(of: find.widgetWithText(FilterChip, 'บุคคล'), matching: find.byIcon(NxI.idCard)), findsOneWidget);
      final chip = find.widgetWithText(FilterChip, 'บุคคล');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final last = api.calls.lastWhere((c) => c.path == '/api/notifications');
      expect(last.queryParameters['category'], 'hr');
    });
  });

  group('"ส่งทดสอบมาที่เครื่องนี้": result per device', () {
    Widget screen() => NotificationPrefsScreen(permission: () async => true, openSettings: () async {}, debounce: const Duration(milliseconds: 300));

    testWidgets('new server: a sheet with each device', (tester) async {
      await pumpProfilePage(tester, screen(), {
        'GET /api/me/notification-preferences': _prefs(),
        'POST /api/notifications/test': {
          'transport': 'notify',
          'job_id': 1966,
          'no_devices': false,
          'devices': [
            {'platform': 'android', 'device_name': 'Galaxy S24', 'token_hint': '…a1b2c3', 'result': 'sent', 'detail': ''},
            {'platform': 'ios', 'device_name': 'iPhone', 'token_hint': '…d4e5f6', 'result': 'invalid_removed', 'detail': 'UNREGISTERED'},
            {'platform': 'android', 'token_hint': '…zzz', 'result': 'failed', 'detail': 'timeout'},
          ],
        },
      }, size: const Size(430, 2000));
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('np-test-sheet')), findsOneWidget);
      expect(find.text('ส่งถึง 1 จาก 3 เครื่อง'), findsOneWidget);
      expect(find.text('ส่งผ่าน Notify · job 1966'), findsOneWidget);
      expect(find.text('Galaxy S24'), findsOneWidget);
      expect(find.text('iPhone · …d4e5f6'), findsOneWidget);
      expect(find.text('ส่งแล้ว'), findsOneWidget);
      expect(find.text('เครื่องนี้ใช้ไม่ได้แล้ว'), findsOneWidget);
      expect(find.text('ส่งไม่สำเร็จ'), findsOneWidget);
      expect(find.text('UNREGISTERED'), findsOneWidget);
      expect(find.byKey(const ValueKey('np-test-result')), findsNothing, reason: 'the sheet instead of a snackbar');
      expect(tester.takeException(), isNull);
    });

    testWidgets('new server, no devices → the snackbar says so; older answer → generic success', (tester) async {
      final (_, api) = await pumpProfilePage(tester, screen(), {
        'GET /api/me/notification-preferences': _prefs(),
        'POST /api/notifications/test': {'transport': 'none', 'no_devices': true, 'devices': []},
      }, size: const Size(430, 2000));
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('np-test-sheet')), findsNothing);
      expect(find.textContaining('ยังไม่มีเครื่องที่ลงทะเบียน'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('np-test')))).clearSnackBars();
      api.replies['POST /api/notifications/test'] = {'notification': {'id': 5}};
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ส่งการแจ้งเตือนทดสอบแล้ว'), findsOneWidget);
    });

    test('result helpers', () {
      expect(notifTestResultText({'no_devices': true, 'devices': []}), contains('ยังไม่มีเครื่อง'));
      expect(notifTestResultText({'devices': [{'result': 'sent'}]}), contains('ส่งการแจ้งเตือนทดสอบแล้ว'));
      expect(notifTestDevices({'devices': 2}), isEmpty);
      expect(notifTransportLabel('fcm'), 'ส่งผ่าน Firebase โดยตรง');
      expect(notifTransportLabel('none'), '');
      expect(notifTestResultStyle('weird').label, 'ส่งไม่สำเร็จ');
    });
  });
}

class _ThrowingBadge implements AppIconBadgeBackend {
  @override
  Future<void> update(int count) async => throw StateError('no launcher');
}
