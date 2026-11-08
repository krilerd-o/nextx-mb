import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_birthdays.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_model.dart';
import 'package:nextx_mobile/screens/dashboard/home_birthday_box.dart';
import 'package:nextx_mobile/services/birthday_reminders.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(CalBirthdays.clearCache);

  final today = calDay(thaiNow());
  String born(int y, DateTime d) => '$y-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  CalBirthday bd(String module, int id, String name, DateTime d, {int year = 1990, String? org}) =>
      CalBirthday.from(module, {'id': id, module == 'account' ? 'account_name' : '${module}_name': name, CalBirthday.fields[module]!: born(year, d), 'company_name': ?org})!;

  group('reminder plan (1 day before)', () {
    test('groups people by birthday over the next 30 days, excluding today', () {
      final now = DateTime(2026, 11, 8, 10);
      final all = [
        bd('contact', 1, 'A', DateTime(2026, 11, 8)), // today: no reminder (it was due yesterday)
        bd('lead', 2, 'B', DateTime(2026, 11, 9)),
        bd('contact', 3, 'C', DateTime(2026, 11, 9)),
        bd('lead', 4, 'D', DateTime(2026, 12, 7)), // 29 days ahead
        bd('lead', 5, 'E', DateTime(2026, 12, 9)), // 31 days: later
      ];
      final p = BirthdayReminders.plan(all, now);
      expect(p.keys, [DateTime(2026, 11, 9), DateTime(2026, 12, 7)]);
      expect(p[DateTime(2026, 11, 9)]!.map((b) => b.id), ['2', '3']);
    });

    test('message says who, which type and the age', () {
      final one = BirthdayReminders.message([bd('lead', 2, '[QA] B', DateTime(2026, 11, 9), year: 1995, org: 'ACME')], DateTime(2026, 11, 9));
      expect(one.$1, 'พรุ่งนี้วันเกิด [QA] B');
      expect(one.$2, contains('(Lead · ACME)'));
      expect(one.$2, contains('ครบ 31 ปี'));
      final many = BirthdayReminders.message([for (var i = 0; i < 7; i++) bd('contact', i, 'P$i', DateTime(2026, 11, 9))], DateTime(2026, 11, 9));
      expect(many.$1, 'พรุ่งนี้วันเกิดลูกค้า 7 คน');
      expect(many.$2, contains('และอีก 2 คน'));
    });
  });

  test('home layout has the birthday box after pending', () {
    expect(HomeLayout.defaultOrder.indexOf('birthdays'), HomeLayout.defaultOrder.indexOf('pending') + 1);
    expect(HomeLayout.sections['birthdays']!.$1, 'วันเกิดลูกค้าวันนี้');
  });

  Future<void> pump(WidgetTester tester, Map<String, dynamic> replies) async {
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter(replies);
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['calendar']));
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HomeBirthdayBox()))),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('home box: today with type badge, tomorrow underneath; tap opens the card', (tester) async {
    await pump(tester, {
      'GET /api/entity/contact': {
        'list': [
          {'id': 71, 'contact_name': '[QA] คุณวันนี้', 'birthdate': born(1990, today), 'mobile_1st': '0811111111'},
        ],
      },
      'GET /api/entity/lead': {
        'list': [
          {'id': 72, 'lead_name': '[QA] ลีดพรุ่งนี้', 'birthdate': born(1995, today.add(const Duration(days: 1)))},
        ],
      },
    });
    expect(find.byKey(const ValueKey('home-birthdays')), findsOneWidget);
    expect(find.text('วันเกิดลูกค้าวันนี้'), findsOneWidget);
    expect(find.text('1 คน · พรุ่งนี้ 1 คน'), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-bday-contact-71')), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-bday-lead-72')), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Lead'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cal-bday-contact-71')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cal-bday-card')), findsOneWidget);
  });

  testWidgets('home box hides when nobody has a birthday today or tomorrow', (tester) async {
    await pump(tester, {
      'GET /api/entity/contact': {
        'list': [
          {'id': 71, 'contact_name': 'x', 'birthdate': born(1990, today.add(const Duration(days: 5)))},
        ],
      },
    });
    expect(find.byKey(const ValueKey('home-birthdays')), findsNothing);
  });
}
