import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/hr/attendance_punch_sheet.dart';
import 'package:nextx_mobile/screens/hr/attendance_screen.dart';
import 'package:nextx_mobile/screens/search/global_search_screen.dart';
import 'package:nextx_mobile/services/location_service.dart';

import 'support/fake_api.dart';

class _FakeGps extends LocationService {
  @override
  Future<GeoFix> currentFix() async => const GeoFix(latitude: 13.7466, longitude: 100.5393, accuracy: 8, address: 'สยาม กรุงเทพฯ');
}

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Widget home, Map<String, Object?> replies, {List<String> menus = const ['attendance']}) async {
  SharedPreferences.setMockInitialValues({});
  final adapter = FakeNextxAdapter(replies);
  final config = AppConfig();
  config.debugOverrideSession(SessionState(accessToken: 't', userId: '1', businessId: '1', displayName: 'QA User', menusLoaded: true, menuKeys: menus));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(420, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return (config, adapter);
}

Future<void> _settle(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('clock in: map, time, coordinates, place; confirm → success; photos optional', (tester) async {
    PunchResult? result;
    final (_, adapter) = await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showAttendancePunchSheet(context, clockIn: true, location: _FakeGps()),
            child: const Text('open'),
          ),
        ),
      ),
      {'POST /api/hr/attendance/clock-in': {'ok': true}},
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('ยืนยันลงเวลาเข้า'), findsWidgets);
    expect(find.textContaining('13.746600, 100.539300'), findsWidgets);
    expect(find.text('สยาม กรุงเทพฯ'), findsWidgets);
    expect(find.text('(ไม่บังคับ)'), findsOneWidget, reason: 'photos are optional');
    await tester.tap(find.byKey(const ValueKey('punch-confirm')));
    await _settle(tester);
    final call = adapter.calls.singleWhere((c) => c.path == '/api/hr/attendance/clock-in');
    final body = Map<String, dynamic>.from(call.data as Map);
    expect((body['latitude'], body['longitude'], body['address']), (13.7466, 100.5393, 'สยาม กรุงเทพฯ'));
    expect(find.text('ลงเวลาเข้าสำเร็จ'), findsOneWidget);
    expect(adapter.calls.where((c) => c.path.startsWith('/api/files')), isEmpty, reason: 'no photo → nothing uploaded');
    await tester.tap(find.byKey(const ValueKey('punch-finish')));
    await _settle(tester, 6);
    expect(result?.clockIn, isTrue);
  });

  testWidgets('attendance page shows clearly that I have clocked in, with hours and the place', (tester) async {
    final now = DateTime.now().toUtc();
    await _pump(tester, const AttendanceScreen(), {
      'GET /api/hr/attendance/summary': {
        'summary': {
          'clock_in_at': now.subtract(const Duration(hours: 2, minutes: 5)).toIso8601String(),
          'clock_in_lat': 13.7466,
          'clock_in_lng': 100.5393,
          'clock_in_address': 'สำนักงาน',
        },
      },
      'GET /api/hr/attendance': [],
    });
    expect(find.text('เข้างานแล้ว'), findsOneWidget);
    expect(find.textContaining('ทำงานไปแล้ว 2 ชม.'), findsOneWidget);
    expect(find.text('สำนักงาน'), findsOneWidget);
    expect(find.text('ลงเวลาออก'), findsOneWidget, reason: 'the one action follows the state');
  });

  testWidgets('search all: menus instantly, records stream in by group, highlighted', (tester) async {
    final (_, adapter) = await _pump(
      tester,
      const GlobalSearchScreen(),
      {
        'GET /api/users': {'list': []},
        'GET /api/entity/lead': {
          'list': [
            {'id': 5, 'lead_name': '[QA] บริษัทลาดพร้าว', 'company_name': 'Ladprao'},
          ],
        },
      },
      menus: ['lead', 'leave-request'],
    );
    await tester.enterText(find.byKey(const ValueKey('search-all-field')), 'ลา');
    await tester.pump(const Duration(milliseconds: 100));
    // Records wait for the 2.5 s countdown (ring shown in the box).
    expect(find.byKey(const ValueKey('nx-search-countdown')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    await _settle(tester, 8);
    // Menu "ขอลา" from the device + the lead from the server.
    expect(find.textContaining('ขอลา'), findsWidgets);
    expect(find.textContaining('[QA] บริษัทลาดพร้าว'), findsOneWidget);
    final call = adapter.calls.singleWhere((c) => c.path == '/api/entity/lead');
    expect(call.queryParameters['q'], 'ลา');
    expect(call.queryParameters['limit'], '4', reason: 'only a few rows per source (fast with big data)');
  });

  testWidgets('typing fast sends one query (debounced)', (tester) async {
    final (_, adapter) = await _pump(tester, const GlobalSearchScreen(), {'GET /api/entity/lead': {'list': []}, 'GET /api/users': {'list': []}}, menus: ['lead']);
    for (final t in ['s', 'si', 'sia', 'siam']) {
      await tester.enterText(find.byKey(const ValueKey('search-all-field')), t);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 2500));
    await _settle(tester, 8);
    final leadCalls = adapter.calls.where((c) => c.path == '/api/entity/lead').toList();
    expect(leadCalls.length, 1);
    expect(leadCalls.single.queryParameters['q'], 'siam');
  });

  testWidgets('keyboard Search runs at once, without the countdown', (tester) async {
    final (_, adapter) = await _pump(tester, const GlobalSearchScreen(), {'GET /api/entity/lead': {'list': []}, 'GET /api/users': {'list': []}}, menus: ['lead']);
    await tester.enterText(find.byKey(const ValueKey('search-all-field')), 'bangna');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester, 4);
    expect(adapter.calls.where((c) => c.path == '/api/entity/lead').length, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  test('no screen header has a refresh button (pull down to refresh instead)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      if (RegExp(r"tooltip: tr\('รีเฟรช'\)|label: 'รีเฟรช'").hasMatch(s)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
