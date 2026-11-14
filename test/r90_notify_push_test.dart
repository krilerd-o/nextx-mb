import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/navigation/push_tap.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/push_navigation.dart';
import 'package:nextx_mobile/core/spaces.dart';
import 'package:nextx_mobile/screens/hr/leave_screen.dart';
import 'package:nextx_mobile/screens/notifications/notification_center_screen.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/services/device_push_service.dart';
import 'package:nextx_mobile/services/unread_service.dart';

import 'support/fake_api.dart';
import 'support/profile_harness.dart';

/// `GET /api/me/notification-preferences` of the new server: 3 channels,
/// frequency lines, a company-locked event; `job_sla` is off for the company
/// so the server leaves it out (and the whole "service" group with it).
Map<String, Object?> _prefs3() => {
      'channels': [
        {'key': 'push', 'label_th': 'มือถือ', 'label_en': 'Mobile'},
        {'key': 'in_app', 'label_th': 'กระดิ่ง', 'label_en': 'Bell'},
        {'key': 'web_push', 'label_th': 'เบราว์เซอร์', 'label_en': 'Browser'},
      ],
      'push_paused': false,
      'groups': [
        {
          'key': 'work',
          'label_th': 'งาน',
          'label_en': 'Work',
          'events': [
            {
              'key': 'work_assigned',
              'label_th': 'ได้รับมอบหมายงาน',
              'label_en': 'Work assigned',
              'description_th': 'มอบหมาย/เปลี่ยนผู้รับผิดชอบงานหรือ Epic',
              'frequency_th': 'ทันที ทุกครั้งที่เปลี่ยนผู้รับผิดชอบ',
              'frequency_en': 'Instantly, on every change',
              'channels': {'in_app': true, 'push': true, 'web_push': false},
              'available_channels': ['in_app', 'push', 'web_push'],
              'locked': false,
              'company_default': {'in_app': true, 'push': true, 'web_push': true},
            },
            {
              'key': 'work_digest',
              'label_th': 'สรุปงานประจำวัน',
              'label_en': 'Daily digest',
              'frequency_th': 'วันละครั้ง 09:00',
              'frequency_en': 'Daily at 09:00',
              'channels': {'in_app': true, 'push': true, 'web_push': true},
              'available_channels': ['in_app', 'push', 'web_push'],
              'locked': true,
              'company_default': {'in_app': true, 'push': true, 'web_push': true},
            },
          ],
        },
        {'key': 'service', 'label_th': 'งานบริการ', 'label_en': 'Service', 'events': []},
        {
          'key': 'chat',
          'label_th': 'แชทและการโทร',
          'label_en': 'Chat & calls',
          'events': [
            {
              'key': 'call_missed',
              'label_th': 'สายที่ไม่ได้รับ',
              'label_en': 'Missed call',
              'frequency_th': '1 ครั้งต่อสาย',
              'channels': {'push': true, 'in_app': true},
              'available_channels': ['push', 'in_app'],
              'locked': false,
            },
          ],
        },
      ],
    };

Widget _screen() => NotificationPrefsScreen(permission: () async => true, openSettings: () async {}, debounce: const Duration(milliseconds: 300));

bool _on(WidgetTester tester, String key) => tester.widget<Switch>(find.byKey(ValueKey(key))).value;

void main() {
  group('notification settings (3 channels)', () {
    testWidgets('three switches, frequency line, lock, and only the events the server sent', (tester) async {
      await pumpProfilePage(tester, _screen(), {'GET /api/me/notification-preferences': _prefs3()}, size: const Size(430, 2600));
      for (final c in ['push', 'in_app', 'web_push']) {
        expect(find.byKey(ValueKey('np-work_assigned-$c')), findsOneWidget, reason: c);
      }
      expect(_on(tester, 'np-work_assigned-push'), isTrue);
      expect(_on(tester, 'np-work_assigned-web_push'), isFalse);
      expect(find.text('มือถือ'), findsWidgets);
      expect(find.text('กระดิ่ง'), findsWidgets);
      expect(find.text('เบราว์เซอร์'), findsWidgets);
      // Frequency under the name.
      expect(find.byKey(const ValueKey('np-freq-work_assigned')), findsOneWidget);
      expect(find.text('ทันที ทุกครั้งที่เปลี่ยนผู้รับผิดชอบ'), findsOneWidget);
      expect(find.text('วันละครั้ง 09:00'), findsOneWidget);
      // Locked by the company: lock badge, switches disabled.
      expect(find.byKey(const ValueKey('np-locked-work_digest')), findsOneWidget);
      expect(find.text('บริษัทกำหนด'), findsOneWidget);
      for (final c in ['push', 'in_app', 'web_push']) {
        expect(tester.widget<Switch>(find.byKey(ValueKey('np-work_digest-$c'))).onChanged, isNull, reason: c);
      }
      // An event without web push shows two switches only.
      expect(find.byKey(const ValueKey('np-call_missed-push')), findsOneWidget);
      expect(find.byKey(const ValueKey('np-call_missed-web_push')), findsNothing);
      // Events the company switched off are not in the answer → not shown; an empty group has no header.
      expect(find.byKey(const ValueKey('np-event-job_sla')), findsNothing);
      expect(find.byKey(const ValueKey('np-group-service')), findsNothing);
      expect(find.text('งานบริการ'.toUpperCase()), findsNothing);
      expect(find.byKey(const ValueKey('np-test')), findsOneWidget);
    });

    testWidgets('English: server labels and frequency', (tester) async {
      addTearDown(() => L10n.set('th'));
      await pumpProfilePage(tester, _screen(), {'GET /api/me/notification-preferences': _prefs3()}, size: const Size(430, 2600));
      L10n.set('en');
      rebuildAllChildren(tester.element(find.byType(MaterialApp)));
      await tester.pump();
      expect(find.text('Work assigned'), findsOneWidget);
      expect(find.text('Daily at 09:00'), findsOneWidget);
      expect(find.text('Browser'), findsWidgets);
      expect(find.text('Set by company'), findsOneWidget);
    });

    testWidgets('PUT carries web_push; "เปิดทั้งหมด" turns on every offered channel, not locked ones', (tester) async {
      final (_, api) = await pumpProfilePage(tester, _screen(), {
        'GET /api/me/notification-preferences': _prefs3(),
        'PUT /api/me/notification-preferences': _prefs3(),
      }, size: const Size(430, 2600));
      await tester.tap(find.byKey(const ValueKey('np-work_assigned-web_push')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
        'events': {
          'work_assigned': {'web_push': true},
        },
      });
      // Server answered with the old state; group "work": work_assigned web off again → all on.
      await tester.tap(find.byKey(const ValueKey('np-all-work')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
        'events': {
          'work_assigned': {'web_push': true},
        },
      }, reason: 'the locked work_digest is left alone');
    });

    testWidgets('tapping the channel cell (not only the switch) toggles it', (tester) async {
      final (_, api) = await pumpProfilePage(tester, _screen(), {
        'GET /api/me/notification-preferences': _prefs3(),
        'PUT /api/me/notification-preferences': _prefs3(),
      }, size: const Size(430, 2600));
      final cell = find.ancestor(of: find.byKey(const ValueKey('np-call_missed-in_app')), matching: find.byType(InkWell)).first;
      await tester.tapAt(tester.getTopLeft(cell) + const Offset(12, 10));
      await tester.pump();
      expect(_on(tester, 'np-call_missed-in_app'), isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
        'events': {
          'call_missed': {'in_app': false},
        },
      });
    });

    testWidgets('"ส่งทดสอบมาที่เครื่องนี้" posts /api/notifications/test and says what happened', (tester) async {
      final (_, api) = await pumpProfilePage(tester, _screen(), {
        'GET /api/me/notification-preferences': _prefs3(),
        'POST /api/notifications/test': {'sent': 1, 'devices': 2},
      }, size: const Size(430, 2600));
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(callCount(api, 'POST /api/notifications/test'), 1);
      expect(find.textContaining('ส่งการแจ้งเตือนทดสอบแล้ว'), findsOneWidget);
    });

    testWidgets('test button: no device / old server / error', (tester) async {
      final (_, api) = await pumpProfilePage(tester, _screen(), {
        'GET /api/me/notification-preferences': _prefs3(),
        'POST /api/notifications/test': {'sent': 0, 'devices': 0},
      }, size: const Size(430, 2600));
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังไม่มีเครื่องที่ลงทะเบียน'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('np-test')))).clearSnackBars();
      api.replies.remove('POST /api/notifications/test');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังส่งทดสอบไม่ได้'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('np-test')))).clearSnackBars();
      api.errorsFor['POST /api/notifications/test'] = {'error_code': 'INTERNAL', 'message': 'boom'};
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('np-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ส่งทดสอบไม่สำเร็จ'), findsOneWidget);
    });

    testWidgets('older server shape (in_app + push, no frequency / lock data) still works', (tester) async {
      final old = {
        'channels': [
          {'key': 'in_app', 'label_th': 'ในแอป', 'label_en': 'In-app'},
          {'key': 'push', 'label_th': 'พุช', 'label_en': 'Push'},
        ],
        'push_paused': false,
        'groups': [
          {
            'key': 'work',
            'label_th': 'งาน',
            'events': [
              {'key': 'task_assigned', 'label_th': 'ได้รับมอบหมายงาน', 'channels': {'in_app': true, 'push': false}},
            ],
          },
        ],
      };
      final (_, api) = await pumpProfilePage(tester, _screen(), {
        'GET /api/me/notification-preferences': old,
        'PUT /api/me/notification-preferences': old,
      });
      expect(find.byKey(const ValueKey('np-task_assigned-in_app')), findsOneWidget);
      expect(find.byKey(const ValueKey('np-task_assigned-push')), findsOneWidget);
      expect(find.byKey(const ValueKey('np-task_assigned-web_push')), findsNothing);
      expect(find.byKey(const ValueKey('np-freq-task_assigned')), findsNothing);
      expect(find.text('พุช'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('np-task_assigned-push')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
        'events': {
          'task_assigned': {'push': true},
        },
      });
    });

    testWidgets('narrow phone, large text: no overflow', (tester) async {
      await pumpProfilePage(tester, _screen(), {'GET /api/me/notification-preferences': _prefs3()}, size: const Size(320, 2600), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('np-work_assigned-web_push')), findsOneWidget);
    });

    test('test result text', () {
      expect(notifTestResultText({'sent': 1}), contains('ส่งการแจ้งเตือนทดสอบแล้ว'));
      expect(notifTestResultText({}), contains('ส่งการแจ้งเตือนทดสอบแล้ว'));
      expect(notifTestResultText({'devices': 0}), contains('ยังไม่มีเครื่อง'));
      expect(notifTestResultText({'sent': '0'}), contains('ยังไม่มีเครื่อง'));
    });
  });

  group('push tap → screen (every event of the plan)', () {
    // event → (push data, app route). URLs are the link_path each server event uses.
    final cases = <String, (Map<String, dynamic>, String)>{
      'work_assigned': ({'url': '/workspace/NSMO-250', 'id': '250'}, '/workspace/NSMO-250'),
      'work_watching': ({'url': '/workspace/NSMO-250'}, '/workspace/NSMO-250'),
      'work_updated': ({'url': '/workspace/boards/12'}, '/workspace/12'),
      'work_worklog': ({'url': '/workspace/NSMO-251'}, '/workspace/NSMO-251'),
      'work_due': ({'url': '/workspace/NSMO-252'}, '/workspace/NSMO-252'),
      'work_digest': ({'url': '/workspace'}, AppRoutes.workspaceHome),
      'calendar_invite': ({'url': '/calendar?open=41', 'id': '41'}, '/calendar/41'),
      'calendar_rsvp': ({'url': '/calendar?open=41'}, '/calendar/41'),
      'calendar_reminder': ({'url': '/calendar?open=41'}, '/calendar/41'),
      'activity_assigned': ({'url': '/calendar?open=42'}, '/calendar/42'),
      'sales_assigned': ({'url': '/modules/lead?open=5'}, '/crm/lead/5'),
      'sales_shared': ({'url': '/modules/contact/view/8'}, '/crm/contact/8'),
      'deal_stage': ({'url': '/modules/deal/view/3'}, '/crm/deal/3'),
      'lead_queue': ({'url': '/modules/lead?open=9'}, '/crm/lead/9'),
      'lead_score': ({'url': '/settings/lead-scoring'}, '/crm/lead'),
      'call_task': ({'url': '/call-log?open=77'}, '/call-log?open=77'),
      'quotation_status': ({'url': '/modules/quotation/view/15'}, '/crm/quotation/15'),
      'quotation_customer': ({'url': '/modules/quotation/view/15', 'extra': 'quotation_customer_accepted'}, '/crm/quotation/15?tab=summary'),
      'contract_update': ({'url': '/modules/service_contract?open=3'}, '/fsm/service_contract/3'),
      'contract_reminder': ({'url': '/modules/service_contract?open=3'}, '/fsm/service_contract/3'),
      'store_order': ({'url': '/commercial-store/orders/9', 'id': '9'}, AppRoutes.commerce),
      'job_assigned': ({'url': '/modules/job/view/21'}, '/fsm/job/21'),
      'job_update': ({'url': '/modules/job/view/21', 'extra': 'job_closed'}, '/fsm/job/21?tab=summary'),
      'job_sla': ({'url': '/modules/job/view/21'}, '/fsm/job/21'),
      'case_assigned': ({'url': '/modules/case?open=31'}, '/crm/case/31'),
      'case_update': ({'url': '/modules/case/view/31'}, '/crm/case/31'),
      'case_sla': ({'url': '/modules/case?open=31'}, '/crm/case/31'),
      'case_from_email': ({'url': '/modules/case?open=32'}, '/crm/case/32'),
      'approval_request': ({'url': '/modules/quotation/view/15', 'extra': 'quotation_approval_request'}, '/crm/quotation/15?tab=approval'),
      'approval_result': ({'url': '/modules/quotation/view/15', 'extra': 'quotation_approved'}, '/crm/quotation/15?tab=approval'),
      'leave_request': ({'url': '/hr/leave-management', 'id': '12'}, '/hr/leave?tab=approve&id=12'),
      'leave_result': ({'url': '/hr/leave', 'id': '12'}, '/hr/leave?tab=mine&id=12'),
      'mention_work': ({'url': '/workspace/NSMO-250'}, '/workspace/NSMO-250'),
      'mention_record': ({'url': '/modules/deal/view/3?section=comments&comment=9'}, '/crm/deal/3?tab=comments&comment=9'),
      'work_comment': ({'url': '/workspace/NSMO-250'}, '/workspace/NSMO-250'),
      'case_comment': ({'url': '/modules/case/view/31?section=comments'}, '/crm/case/31?tab=comments'),
      'chat_message': ({'url': '/camp?room=5&mid=9', 'id': '5'}, '/chat/5'),
      'chat_mention': ({'url': '/community-chat?room=6&mid=1'}, '/chat/6'),
      'chat_invite': ({'url': '/camp?room=7', 'id': '7'}, '/chat/7'),
      'call_missed': ({'url': '/camp?room=5', 'id': '5'}, '/chat/5'),
      'ai_job': ({'url': '/ai?c=abc'}, '/ai?c=abc'),
      'ai_notebook': ({'url': '/ai/notebook/3', 'id': '3', 'extra': '17'}, '/notebook/3?recording=17'),
      'comm_ai_summary': ({'url': '/comm-ai/history?call=55'}, '/comm-ai/calls/55'),
      'comm_ai_admin': ({'url': '/settings/comm-ai'}, AppRoutes.commAiSettings),
      'mail_connection': ({'url': '/mailbox'}, AppRoutes.mail),
      'report_failed': ({'url': '/analytics-reports/report/3', 'id': '3', 'notification_id': '880'}, '/notifications?id=880'),
      'system_notice': ({'url': '/', 'notification_id': '900'}, '/notifications?id=900'),
      'announcement': ({'notification_id': '901'}, '/notifications?id=901'),
      'app_update': ({'notification_id': '902', 'store_android': 'https://play.google.com/store/apps/details?id=x'}, '/notifications?id=902'),
    };

    for (final e in cases.entries) {
      test(e.key, () {
        final data = {...e.value.$1, 'event': e.key, 'type': 'notification', 'business_id': '1', 'badge': '3'};
        expect(notificationDeepLinkFromData(data), e.value.$2);
      });
    }

    test('every routed location is one the router knows', () {
      for (final e in cases.entries) {
        final loc = notificationDeepLinkFromData({...e.value.$1, 'event': e.key})!;
        expect(loc, startsWith('/'), reason: e.key);
        expect(loc.startsWith('/modules') || loc.startsWith('/settings/') || loc.startsWith('/commercial-store'), isFalse, reason: '${e.key} → $loc');
      }
      // Leave links are gated by the leave menus, like the web.
      expect(requiredMenusFor('/hr/leave?tab=approve&id=12'), isNotNull);
    });

    test('a leave push without url still opens the leave record', () {
      expect(notificationDeepLinkFromData({'event': 'leave_request', 'id': '4'}), '/hr/leave?tab=approve&id=4');
      expect(notificationDeepLinkFromData({'event': 'leave_result', 'link_id': '4'}), '/hr/leave?tab=mine&id=4');
      expect(notificationDeepLinkFromData({'event': 'announcement'}), AppRoutes.notifications);
      expect(notificationDeepLinkFromData({}), AppRoutes.notifications);
    });

    test('rows of the notification list: announcement opens itself, records open their page', () {
      expect(notificationItemRoute({'id': 5, 'type': 'announcement', 'title': 'ประกาศ', 'link_path': null}), '/notifications?id=5');
      expect(notificationItemRoute({'id': 6, 'link_path': '/hr/leave', 'link_id': 12}), '/hr/leave?tab=mine&id=12');
      expect(notificationItemRoute({'id': 7, 'link_path': '/modules/deal/view/3'}), '/crm/deal/3');
      expect(notificationItemRoute({'id': 8, 'link_path': '', 'meta': {'event': 'leave_request'}, 'link_id': 2}), '/hr/leave?tab=approve&id=2');
    });

    test('leave tab names', () {
      expect(leaveTabIndex('mine'), 2);
      expect(leaveTabIndex('approve'), 3);
      expect(leaveTabIndex('request'), 1);
      expect(leaveTabIndex(null), 0);
      expect(AppRoutes.leave(), AppRoutes.leaveList);
      final rows = [
        {'id': 1},
        {'id': 2},
        {'id': 3},
      ];
      expect([for (final r in leaveFocusFirst(rows, '3')) r['id']], [3, 1, 2]);
      expect(leaveFocusFirst(rows, '9'), same(rows));
    });
  });

  testWidgets('a push about an announcement opens the center with it marked read and shown in full', (tester) async {
    const long = 'บริษัทจะปิดปรับปรุงระบบวันเสาร์นี้ 22:00–23:00 น. ระหว่างนั้นจะใช้งานแอปและเว็บไม่ได้ ขออภัยในความไม่สะดวก';
    final (_, api) = await pumpProfilePage(tester, const NotificationCenterScreen(focusId: '901'), {
      'GET /api/notifications': {
        'items': [
          {'id': 901, 'type': 'announcement', 'title': 'ประกาศ: ปิดปรับปรุงระบบ', 'body': long, 'link_path': null, 'read_at': null, 'created_at': '2026-11-14 09:00:00'},
          {'id': 902, 'type': 'workspace', 'title': 'งานใหม่', 'link_path': '/workspace/NSMO-1', 'read_at': null},
        ],
      },
      'GET /api/notifications/summary': {'total': 2},
      'PATCH /api/notifications/901/read': {},
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notif-reader')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('notif-reader')), matching: find.text(long, findRichText: true)), findsOneWidget);
    expect(callCount(api, 'PATCH /api/notifications/901/read'), 1);
  });

  group('push tap actions', () {
    tearDown(() {
      PushNavigation.instance.take();
      pushStoreLauncher = (uri) async => false;
    });

    test('business_id travels with the location', () async {
      await handlePushTap({'url': '/modules/deal/view/3', 'event': 'deal_stage', 'business_id': '22'});
      expect(PushNavigation.instance.pending, '/crm/deal/3');
      expect(PushNavigation.instance.pendingBusinessId, '22');
      expect(PushNavigation.instance.take(), '/crm/deal/3');
      expect(PushNavigation.instance.pendingBusinessId, isNull);
    });

    test('app_update opens the store link of this platform', () async {
      final opened = <Uri>[];
      pushStoreLauncher = (uri) async {
        opened.add(uri);
        return true;
      };
      const data = {
        'event': 'app_update',
        'notification_id': '902',
        'store_android': 'https://play.google.com/store/apps/details?id=com.moai.nextt.mobile',
        'store_ios': 'https://apps.apple.com/app/id123',
      };
      expect(pushTapFromData(data, ios: false).storeUrl, contains('play.google.com'));
      expect(pushTapFromData(data, ios: true).storeUrl, contains('apps.apple.com'));
      expect(pushTapFromData({'event': 'app_update', 'store_android': 'not a url'}, ios: false).storeUrl, isNull);
      expect(pushTapFromData({'event': 'announcement', 'store_android': 'https://x.y'}, ios: false).storeUrl, isNull);
      await handlePushTap(data);
      expect(opened.single.host, anyOf('play.google.com', 'apps.apple.com'));
      expect(PushNavigation.instance.pending, isNull, reason: 'the store opened instead');
    });

    test('app_update without a store (or store cannot open) → the notification', () async {
      pushStoreLauncher = (uri) async => false;
      await handlePushTap({'event': 'app_update', 'notification_id': '902', 'store_android': 'https://play.google.com/x', 'store_ios': 'https://apps.apple.com/x'});
      expect(PushNavigation.instance.pending, '/notifications?id=902');
    });

    test('foreground banner payload round-trips (local notification tap)', () async {
      final payload = encodePushPayload({'url': '/modules/lead?open=5', 'business_id': '3', 'event': 'lead_queue', 'title': 'x', 'badge': '2'});
      final m = jsonDecode(payload) as Map;
      expect(m.containsKey('title'), isFalse);
      expect(m['business_id'], '3');
      await handleNotificationPayload(payload);
      expect(PushNavigation.instance.pending, '/crm/lead/5');
      expect(PushNavigation.instance.pendingBusinessId, '3');
      // Birthday reminders still hand over a plain location.
      await handleNotificationPayload('/crm/contact/4');
      expect(PushNavigation.instance.pending, '/crm/contact/4');
      expect(PushNavigation.instance.pendingBusinessId, isNull);
    });

    test('iOS shows a push with a notification part itself: no second banner', () {
      expect(shouldShowLocalForeground(ios: true, hasNotification: true), isFalse);
      expect(shouldShowLocalForeground(ios: true, hasNotification: false), isTrue);
      expect(shouldShowLocalForeground(ios: false, hasNotification: true), isTrue);
    });

    test('a foreground push bumps the unread count (badge wins), calls do not', () async {
      final unread = UnreadNotifications.instance..clear();
      var shown = 0;
      Future<void> show() async => shown++;
      await onForegroundPush({'event': 'work_assigned', 'business_id': '1'}, hasNotification: true, ios: false, currentBusinessId: '1', show: show);
      expect(unread.count, 1);
      expect(shown, 1);
      await onForegroundPush({'event': 'work_assigned', 'badge': '7'}, hasNotification: true, ios: true, currentBusinessId: '1', show: show);
      expect(unread.count, 7);
      expect(shown, 1, reason: 'iOS shows it itself');
      await onForegroundPush({'event': 'chat_message', 'business_id': '99'}, hasNotification: true, ios: false, currentBusinessId: '1', show: show);
      expect(unread.count, 7, reason: 'another Space');
      await onForegroundPush({'type': 'call_incoming', 'call_id': 'c1'}, hasNotification: false, ios: false, currentBusinessId: '1', show: show);
      expect(unread.count, 7);
      expect(shown, 2);
      unread.clear();
    });
  });

  group('push from another Space', () {
    Space space(String id, String url, String uid, String biz) => Space(
          id: id,
          baseUrl: url,
          userId: uid,
          businessName: 'บริษัท $biz',
          bundle: {
            'api_base_url': url,
            'session_user_id': uid,
            'session_business_id': biz,
            'session_business_name': 'บริษัท $biz',
            'session_package_code': 'next_x',
            'server_confirmed': true,
          },
        );

    test('spaceForBusiness: same server first, never the active one', () {
      final a = space('a', 'https://one.example.com', '1', '10');
      final b = space('b', 'https://two.example.com', '2', '20');
      final c = space('c', 'https://one.example.com', '3', '20');
      expect(spaceForBusiness([a, b, c], '20', excludeId: 'a', preferBaseUrl: 'https://one.example.com/')?.id, 'c');
      expect(spaceForBusiness([a, b], '20', excludeId: 'a')?.id, 'b');
      expect(spaceForBusiness([a, b], '10', excludeId: 'a'), isNull);
      expect(spaceForBusiness([a, b], '', excludeId: 'a'), isNull);
    });

    testWidgets('tapping a push of business 20 switches to its Space, then the location opens there', (tester) async {
      final a = space('a', 'https://one.example.com', '1', '10');
      final b = space('b', 'https://two.example.com', '9', '20');
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
        expect(config.session.businessId, '10');

        // Same business → open here, no switch.
        PushNavigation.instance.remember('/crm/deal/3', businessId: '10');
        expect(config.holdPushForSpace(), isFalse);
        expect(PushNavigation.instance.take(), '/crm/deal/3');

        // Unknown business → open here too.
        PushNavigation.instance.remember('/crm/deal/4', businessId: '77');
        expect(config.holdPushForSpace(), isFalse);
        expect(PushNavigation.instance.take(), '/crm/deal/4');

        // Business of Space b → hold, switch, then open.
        PushNavigation.instance.remember('/crm/deal/5', businessId: '20');
        expect(config.holdPushForSpace(), isTrue);
        expect(config.holdPushForSpace(), isTrue, reason: 'still switching');
        for (var i = 0; i < 50 && (config.activeSpace?.id != 'b' || PushNavigation.instance.pendingBusinessId != null); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(config.activeSpace?.id, 'b');
        expect(config.session.businessId, '20');
        expect(config.holdPushForSpace(), isFalse);
        expect(PushNavigation.instance.take(), '/crm/deal/5');
      });
      await tester.pump(const Duration(minutes: 5));
    });
  });
}
