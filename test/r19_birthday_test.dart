import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_birthdays.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_model.dart';
import 'package:nextx_mobile/screens/calendar/calendar_home_screen.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = calDay(thaiNow());
  String born(int year, DateTime d) => '$year-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('birthday model', () {
    test('modules, names, age and the 29 Feb rule', () {
      final c = CalBirthday.from('contact', {'id': 7, 'contact_name': '[QA] สมชาย', 'nickname': 'ชาย', 'birthdate': '1990-11-10', 'account_name_1st': 'บริษัท ก', 'mobile_1st': '0812345678'})!;
      expect(c.name, '[QA] สมชาย (ชาย)');
      expect(c.org, 'บริษัท ก');
      expect(c.on(DateTime(2026, 11, 10)), isTrue);
      expect(c.ageIn(2026), 36);
      // Account: the contact person's birthday, named after the person.
      final a = CalBirthday.from('account', {'id': 2, 'account_name': '[QA] ACME', 'contact_name_1st': 'คุณเอ', 'contact_person_birthdate': '1985-03-01'})!;
      expect((a.name, a.org), ('คุณเอ', '[QA] ACME'));
      // DATE from a Bangkok-TZ server (previous day 17:00Z) is still the right day.
      final l = CalBirthday.from('lead', {'id': 3, 'lead_name': 'x', 'birthdate': '1990-11-09T17:00:00.000Z'})!;
      expect((l.born.month, l.born.day), (11, 10));
      final leap = CalBirthday.from('lead', {'id': 4, 'lead_name': 'y', 'birthdate': '2000-02-29'})!;
      expect(leap.inYear(2027), DateTime(2027, 2, 28));
      expect(leap.inYear(2028), DateTime(2028, 2, 29));
      expect(CalBirthday.from('lead', {'id': 5, 'lead_name': 'z', 'birthdate': null}), isNull);
    });
  });

  Future<FakeNextxAdapter> pump(WidgetTester tester, {String view = 'month', bool? showBirthdays}) async {
    final adapter = FakeNextxAdapter({
      'GET /api/entity/activity': {'list': [], 'total': 0},
      'GET /api/entity/contact': {
        'list': [
          {'id': 71, 'contact_name': '[QA] คุณวันเกิด', 'birthdate': born(1990, today), 'account_name_1st': '[QA] บริษัททดสอบ', 'mobile_1st': '0811111111', 'email_1st': 'qa@example.com'},
        ],
      },
      'GET /api/entity/lead': {
        'list': [
          {'id': 72, 'lead_name': '[QA] ลีดพรุ่งนี้', 'birthdate': born(1995, today.add(const Duration(days: 1))), 'company_name': '[QA] Lead Co'},
        ],
      },
      // Account module not permitted → 404 here: must be skipped quietly.
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['calendar']));
    config.apiClient.debugSetHttpAdapter(adapter);
    final scope = config.prefsScope;
    SharedPreferences.setMockInitialValues({
      'flutter.nx_cal_view_$scope': view,
      if (showBirthdays != null) 'flutter.nx_cal_birthdays_$scope': showBirthdays,
    });
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: CalendarHomeScreen())));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return adapter;
  }

  testWidgets('month: pink cake on the day, birthday row, tap → card with who and when', (tester) async {
    final adapter = await pump(tester);
    // Asked for records that have a birthday (period over every year).
    final call = adapter.calls.firstWhere((c) => c.path == '/api/entity/contact');
    expect(call.queryParameters['period_field'], 'birthdate');
    expect(call.queryParameters['period_preset'], 'custom');

    expect(find.byKey(ValueKey('cal-bday-mark-${calKey(today)}')), findsOneWidget);
    final row = find.byKey(const ValueKey('cal-bday-contact-71'));
    expect(row, findsOneWidget);
    expect(find.text('[QA] คุณวันเกิด'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cal-bday-card')), findsOneWidget);
    expect(find.text('สุขสันต์วันเกิดวันนี้'), findsOneWidget);
    expect(find.text('ผู้ติดต่อ'), findsOneWidget);
    expect(find.text('ครบ ${today.year - 1990} ปี'), findsWidgets);
    expect(find.text('[QA] บริษัททดสอบ'), findsWidgets);
    expect(find.text('0811111111'), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-bday-plan')), findsOneWidget);
  });

  testWidgets('day view: birthday chip in the all-day row', (tester) async {
    await pump(tester, view: 'day');
    expect(find.byKey(const ValueKey('cal-bday-chip-contact-71')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cal-bday-chip-contact-71')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cal-bday-card')), findsOneWidget);
  });

  testWidgets('list view shows days that have only birthdays', (tester) async {
    await pump(tester, view: 'list');
    expect(find.byKey(const ValueKey('cal-bday-contact-71')), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-bday-lead-72')), findsOneWidget);
    expect(find.textContaining('· พรุ่งนี้'), findsOneWidget);
  });

  testWidgets('switched off in the menu: no marks', (tester) async {
    await pump(tester, showBirthdays: false);
    expect(find.byKey(ValueKey('cal-bday-mark-${calKey(today)}')), findsNothing);
    expect(find.byKey(const ValueKey('cal-bday-contact-71')), findsNothing);
  });
}
