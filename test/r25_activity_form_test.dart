import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/activity_guests.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/activity_form_screen.dart';

import 'support/fake_api.dart';

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Widget screen, [Map<String, Object?> replies = const {}]) async {
  SharedPreferences.setMockInitialValues({});
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: 'QA Second', menusLoaded: true, menuKeys: ['calendar']));
  final adapter = FakeNextxAdapter({'POST /api/entity/activity': {'id': 99}, ...replies});
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (config, adapter);
}

Map<String, dynamic> _lastPost(FakeNextxAdapter a) =>
    Map<String, dynamic>.from(a.calls.lastWhere((c) => c.method == 'POST' && c.path == '/api/entity/activity').data as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('guests (same format as the web)', () {
    test('reads ids, user / entity / email objects and JSON strings; drops duplicates', () {
      final g = parseActivityGuests('[3, {"user_id":3}, {"module":"lead","entity_id":7,"name":"[QA] Lead"}, {"email":"A@x.com"}, {"foo":1}]');
      expect(g.map((e) => e.key), ['user:3', 'entity:lead:7', 'email:a@x.com']);
      expect(g[1].kind, 'entity');
    });

    test('owner is first and organizer; first customer guest becomes the related record', () {
      final list = ensureOwnerGuest([ActivityGuest(kind: 'entity', module: 'contact', entityId: 5, name: '[QA] C', phone: '081')], 2, ownerName: 'QA');
      expect(list.first.key, 'user:2');
      expect(list.first.isOrganizer, isTrue);
      final rel = projectRelatedFromGuests(list);
      expect(rel['related_module'], 'contact');
      expect(rel['related_id'], 5);
      expect(rel['customer_mobile'], '081');
      expect(list.first.toJson()['isOrganizer'], isTrue);
    });
  });

  testWidgets('edit: wall time from the API (with a fake Z) shows hh:mm, not ISO', (tester) async {
    await _pump(
      tester,
      const ActivityFormScreen(recordId: '5', initial: {
        'id': 5,
        'subject': '[QA] นัด',
        'date_start': '2026-11-04T17:54:00.000Z',
        'date_end': '2026-11-04T18:54:00.000Z',
        'smownerid': 2,
      }),
      {'PUT /api/entity/activity/5': {'id': 5}},
    );
    expect(find.textContaining('2026-11-04T'), findsNothing);
    expect(find.text('17:54'), findsOneWidget);
    expect(find.text('18:54'), findsOneWidget);
    expect(find.textContaining('4 พ.ย. 2569'), findsNWidgets(2));
  });

  testWidgets('all-day hides the times and saves 00:00 → 23:59', (tester) async {
    final (_, adapter) = await _pump(tester, ActivityFormScreen(start: DateTime(2026, 11, 10, 9)));
    expect(find.text('09:00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('act-allday')));
    await tester.pump();
    expect(find.byKey(const ValueKey('act-start-time')), findsNothing);
    expect(find.byKey(const ValueKey('act-end-time')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('act-subject')), '[QA] ทั้งวัน');
    await tester.tap(find.byKey(const ValueKey('act-save')));
    await tester.pump(const Duration(milliseconds: 200));
    final body = _lastPost(adapter);
    expect(body['all_day'], isTrue);
    expect(body['date_start'], '2026-11-10 00:00:00');
    expect(body['date_end'], '2026-11-10 23:59:00');
  });

  testWidgets('from a lead: lead is a suggested guest; pick a user and an email; owner is organizer', (tester) async {
    final (_, adapter) = await _pump(
      tester,
      ActivityFormScreen(start: DateTime(2026, 11, 10, 9), initial: const {'related_module': 'lead', 'related_id': 7, 'customer_name': '[QA] Lead', 'subject': '[QA] เยี่ยม'}),
      {
        'GET /api/users': {
          'list': [
            {'id': 2, 'first_name': 'QA', 'last_name': 'Second'},
            {'id': 3, 'first_name': 'QA', 'last_name': 'Third', 'email1': 'qa3@example.com'},
          ],
        },
      },
    );
    expect(find.byKey(const ValueKey('act-guest-user:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('act-guest-entity:lead:7')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('act-add-guest')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('guest-mode-user')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guest-mode-user')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guest-opt-user:2')), findsNothing); // already a guest
    await tester.tap(find.byKey(const ValueKey('guest-opt-user:3')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('guest-mode-email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guest-mode-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('guest-q')), 'Guest@Example.com');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guest-add-email')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guest-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('act-guest-user:3')), findsOneWidget);
    expect(find.byKey(const ValueKey('act-guest-email:guest@example.com')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('act-remind-30')));
    await tester.tap(find.byKey(const ValueKey('act-save')));
    await tester.pump(const Duration(milliseconds: 200));
    final body = _lastPost(adapter);
    final guests = (body['attendees'] as List).cast<Map>();
    expect(guests.map((g) => g['kind']), ['user', 'entity', 'user', 'email']);
    expect(guests.first['isOrganizer'], isTrue);
    expect(body['related_module'], 'lead');
    expect(body['related_id'], 7);
    expect(body['reminder_minutes'], 30);
    expect(body['smownerid'], 2);
  });

  test('duplicate seed drops id, check-in and series data', () {
    final seed = ActivityFormScreen.duplicateSeed({'id': 5, 'subject': 'x', 'checkindate': 'y', 'series_id': 3, 'attendees': []});
    expect(seed.keys, containsAll(['subject', 'attendees']));
    expect(seed.keys, isNot(contains('id')));
    expect(seed.keys, isNot(contains('checkindate')));
    expect(seed.keys, isNot(contains('series_id')));
  });
}
