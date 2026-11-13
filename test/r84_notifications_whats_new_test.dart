import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_version.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/screens/whats_new/whats_new_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/profile_harness.dart';

Map<String, Object?> _prefs() => {
      'channels': [
        {'key': 'in_app', 'label_th': 'ในแอป', 'label_en': 'In-app'},
        {'key': 'push', 'label_th': 'พุช', 'label_en': 'Push'},
      ],
      'push_paused': false,
      'groups': [
        {
          'key': 'work',
          'label_th': 'งาน',
          'label_en': 'Work',
          'events': [
            {'key': 'task_assigned', 'label_th': 'ได้รับมอบหมายงาน', 'label_en': 'Task assigned', 'description_th': 'เมื่อมีคนมอบหมายงานให้คุณ', 'channels': {'in_app': true, 'push': true}},
            {'key': 'task_due', 'label_th': 'งานใกล้ครบกำหนด', 'label_en': 'Task due soon', 'channels': {'in_app': true, 'push': false}},
            {'key': 'call_incoming', 'label_th': 'สายเข้า', 'label_en': 'Incoming call', 'channels': {'push': true}, 'available_channels': ['push']},
          ],
        },
        {
          'key': 'system',
          'label_th': 'ระบบ',
          'label_en': 'System',
          'events': [
            {'key': 'system_notice', 'label_th': 'ประกาศจากระบบ', 'label_en': 'System notice', 'channels': {'in_app': true, 'push': true}, 'locked': true},
          ],
        },
      ],
    };

Widget _screen() => NotificationPrefsScreen(permission: () async => false, openSettings: () async {}, debounce: const Duration(milliseconds: 300));

bool _on(WidgetTester tester, String key) => tester.widget<Switch>(find.byKey(ValueKey(key))).value;

void main() {
  tearDown(() => L10n.set('th'));

  testWidgets('groups as sections, two switches per event, locked disabled, channel not offered hidden', (tester) async {
    await pumpProfilePage(tester, _screen(), {'GET /api/me/notification-preferences': _prefs()}, size: const Size(430, 2400));
    expect(find.text('งาน'.toUpperCase()), findsOneWidget);
    expect(find.text('ได้รับมอบหมายงาน'), findsOneWidget);
    expect(find.text('เมื่อมีคนมอบหมายงานให้คุณ'), findsOneWidget);
    expect(_on(tester, 'np-task_assigned-push'), isTrue);
    expect(_on(tester, 'np-task_due-push'), isFalse);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('np-system_notice-in_app'))).onChanged, isNull, reason: 'locked');
    expect(find.byKey(const ValueKey('np-locked-system_notice')), findsOneWidget);
    expect(find.byKey(const ValueKey('np-call_incoming-in_app')), findsNothing);
    expect(find.byKey(const ValueKey('np-call_incoming-in_app-na')), findsOneWidget);
    // Device permission (off here) with a shortcut to the phone's settings.
    expect(find.text('เครื่องนี้ปิดการแจ้งเตือนของแอปอยู่'), findsOneWidget);
    expect(find.byKey(const ValueKey('np-open-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-bday-remind')), findsOneWidget);
  });

  testWidgets('changes are debounced into one PUT with only the changed events', (tester) async {
    final (_, api) = await pumpProfilePage(tester, _screen(), {
      'GET /api/me/notification-preferences': _prefs(),
      'PUT /api/me/notification-preferences': _prefs(),
    }, size: const Size(430, 2400));
    await tester.tap(find.byKey(const ValueKey('np-task_assigned-push')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('np-task_due-in_app')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.callKeys, isNot(contains('PUT /api/me/notification-preferences')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(callCount(api, 'PUT /api/me/notification-preferences'), 1);
    expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
      'events': {
        'task_assigned': {'push': false},
        'task_due': {'in_app': false},
      },
    });
  });

  testWidgets('group "ปิดทั้งหมด" skips locked events and channels the event does not offer; pause push', (tester) async {
    // The server answers with the saved state (here: everything in "work" on).
    final saved = _prefs();
    (((saved['groups'] as List).first as Map)['events'] as List)[1]['channels'] = {'in_app': true, 'push': true};
    final (_, api) = await pumpProfilePage(tester, _screen(), {
      'GET /api/me/notification-preferences': _prefs(),
      'PUT /api/me/notification-preferences': saved,
    }, size: const Size(430, 2400));
    expect(find.byKey(const ValueKey('np-all-system')), findsNothing, reason: 'only locked events');
    await tester.tap(find.byKey(const ValueKey('np-all-work')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
      'events': {
        'task_due': {'push': true},
      },
    }, reason: 'not all on yet → "เปิดทั้งหมด" turns the rest on; locked and not-offered channels untouched');
    expect(find.text('ปิดทั้งหมด'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('np-all-work')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {
      'events': {
        'task_assigned': {'in_app': false, 'push': false},
        'task_due': {'in_app': false, 'push': false},
        'call_incoming': {'push': false},
      },
    });
    await tester.tap(find.byKey(const ValueKey('np-pause')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(bodyOf(api, 'PUT', '/api/me/notification-preferences'), {'push_paused': true});
  });

  testWidgets('a failed save rolls the switch back', (tester) async {
    final (_, api) = await pumpProfilePage(tester, _screen(), {'GET /api/me/notification-preferences': _prefs()}, errors: {
      'PUT /api/me/notification-preferences': {'error_code': 'VALIDATION', 'message': 'unknown event'},
    }, size: const Size(430, 2400));
    await tester.tap(find.byKey(const ValueKey('np-task_due-push')));
    await tester.pump();
    expect(_on(tester, 'np-task_due-push'), isTrue, reason: 'optimistic');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(callCount(api, 'PUT /api/me/notification-preferences'), 1);
    expect(_on(tester, 'np-task_due-push'), isFalse);
    expect(find.textContaining('บันทึกการแจ้งเตือนไม่สำเร็จ'), findsOneWidget);
  });

  testWidgets('English labels from the server', (tester) async {
    await pumpProfilePage(tester, _screen(), {'GET /api/me/notification-preferences': _prefs()}, size: const Size(430, 2400));
    L10n.set('en');
    rebuildAllChildren(tester.element(find.byType(MaterialApp)));
    await tester.pump();
    expect(find.text('Task assigned'), findsOneWidget);
    expect(find.text('WORK'), findsOneWidget);
    expect(find.text('Push'), findsWidgets);
  });

  testWidgets('older server (404): a note, the device card and the local reminders stay', (tester) async {
    await pumpProfilePage(tester, _screen(), const {});
    expect(find.byKey(const ValueKey('np-unsupported')), findsOneWidget);
    expect(find.byKey(const ValueKey('np-device')), findsOneWidget);
    expect(find.byKey(const ValueKey('np-center')), findsOneWidget);
  });

  testWidgets('มีอะไรใหม่: app icon + version on top, no "เปิด…" go-to buttons', (tester) async {
    final (_, api) = await pumpProfilePage(tester, const WhatsNewScreen(), {
      'GET /api/whats-new': [
        {'id': 3, 'type': 'feature', 'version': '1.5.0', 'title_th': 'หน้าโปรไฟล์ใหม่', 'description_th': '<p>จัดการทุกอย่างได้ในที่เดียว</p>', 'date': '2026-11-13', 'link_path': '/profile', 'link_label_th': 'เปิดโปรไฟล์'},
      ],
      'POST /api/whats-new/views/batch': {},
      'POST /api/whats-new/3/ack': {},
    });
    expect(find.byKey(const ValueKey('wn-app-icon')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('wn-app-version'))).data, 'เวอร์ชัน ${AppVersion.value}');
    expect(tester.getTopLeft(find.byKey(const ValueKey('wn-app-header'))).dy, lessThan(tester.getTopLeft(find.text('หน้าโปรไฟล์ใหม่')).dy));
    expect(find.text('เปิดโปรไฟล์'), findsNothing);
    expect(find.text('v1.5.0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wn-ack-3')));
    await tester.pumpAndSettle();
    expect(callCount(api, 'POST /api/whats-new/3/ack'), 1);
    expect(find.text('รับทราบแล้ว'), findsOneWidget);
  });

  test('401 that refuses a proof never signs out; a real 401 still does', () {
    expect(isStepUpRefusal('/api/crm/lead', {'error_code': 'STEP_UP_REQUIRED'}), isTrue);
    expect(isStepUpRefusal('/api/me/delete-account', {'error_code': 'AUTH_REQUIRED'}), isTrue);
    expect(isStepUpRefusal('/api/me/verify/confirm', null), isTrue);
    expect(isStepUpRefusal('/api/me/phone/otp/verify', {'error_code': 'AUTH_INVALID_CREDENTIALS'}), isTrue);
    expect(isStepUpRefusal('/api/crm/lead', {'error_code': 'AUTH_REQUIRED'}), isFalse);
    expect(notifEventChanges({'a': {'push': true, 'in_app': true}}, {'a': {'push': false, 'in_app': true}}), {'a': {'push': false}});
  });

  testWidgets('STEP_UP_REQUIRED on any endpoint keeps the session', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const SizedBox(), const {}, status: {'GET /api/me/profile': 401}, errors: {
      'GET /api/me/profile': {'error_code': 'STEP_UP_REQUIRED', 'message': 'ยืนยันตัวตนก่อน', 'data': {'required': ['email'], 'missing': ['email']}},
    });
    Object? err;
    await tester.runAsync(() async {
      try {
        await config.apiClient.getVerifyMethods(); // 404, unrelated
      } catch (_) {}
      try {
        await config.apiClient.getMyProfile();
      } catch (e) {
        err = e;
      }
    });
    expect(err, isA<ApiEnvelopeException>());
    expect((err as ApiEnvelopeException).details?['missing'], ['email']);
    expect(config.isLoggedIn, isTrue);
  });
}
