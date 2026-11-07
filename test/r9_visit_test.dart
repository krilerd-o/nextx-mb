import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/visit_check_sheet.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/location_service.dart';

import 'support/fake_api.dart';

class _FakeGps extends LocationService {
  @override
  Future<GeoFix> currentFix() async => const GeoFix(latitude: 13.7466, longitude: 100.5393, accuracy: 8);
}

Future<(AppConfig, FakeNextxAdapter)> _pump(WidgetTester tester, Map<String, Object?> replies, {required bool checkIn}) async {
  SharedPreferences.setMockInitialValues({});
  final adapter = FakeNextxAdapter(replies);
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['calendar']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showVisitCheckSheet(
              context,
              activityId: '7',
              checkIn: checkIn,
              placeName: 'สยาม',
              checkedInAt: DateTime.now().subtract(const Duration(minutes: 75)),
              location: _FakeGps(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return (config, adapter);
}

void main() {
  test('stay duration reads in hours and minutes', () {
    final a = DateTime(2026, 11, 7, 9, 0);
    expect(stayDuration(a, DateTime(2026, 11, 7, 11, 15)), '2 ชม. 15 นาที');
    expect(thaiDateTime(DateTime(2026, 11, 7, 14, 5, 9)), '7 พ.ย. 2569 · 14:05:09');
  });

  testWidgets('check-in sheet shows coordinates, distance, confirms and shows success', (tester) async {
    final (_, adapter) = await _pump(tester, {
      'GET /api/activity/7/checkin/validate': {
        'allowed': true, 'button': true, 'distance': 42, 'has_destination': true,
        'dest_lat': 13.7467, 'dest_lng': 100.5394, 'range_meters': 200, 'enforce_range': true,
      },
      'POST /api/activity/7/checkin': {'ok': true},
    }, checkIn: true);
    expect(find.text('ยืนยันเช็คอิน'), findsWidgets);
    expect(find.textContaining('13.746600, 100.539300'), findsWidgets);
    expect(find.textContaining('42 ม.'), findsOneWidget);
    expect(adapter.calls.first.queryParameters['location'], '13.7466,100.5393');
    await tester.tap(find.widgetWithText(FilledButton, 'ยืนยันเช็คอิน'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(adapter.callKeys, contains('POST /api/activity/7/checkin'));
    expect(find.text('เช็คอินสำเร็จ'), findsOneWidget);
  });

  testWidgets('out of enforced range blocks the confirm button', (tester) async {
    await _pump(tester, {
      'GET /api/activity/7/checkin/validate': {
        'allowed': false, 'button': false, 'distance': 900, 'has_destination': true,
        'dest_lat': 13.75, 'dest_lng': 100.55, 'range_meters': 200, 'enforce_range': true,
      },
    }, checkIn: true);
    final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'อยู่นอกระยะเช็คอิน'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('check-out shows time spent at the place', (tester) async {
    await _pump(tester, {'POST /api/activity/7/checkout': {'ok': true}}, checkIn: false);
    expect(find.text('อยู่ในสถานที่'), findsOneWidget);
    expect(find.text('1 ชม. 15 นาที'), findsOneWidget);
  });

  test('activity photos upload with multer field "files"', () async {
    final adapter = FakeNextxAdapter({'POST /api/activity/7/photos': {'list': [{'path': 'business/1/a.png'}]}});
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = adapter;
    final api = ApiClient(dio: dio);
    final saved = await api.uploadActivityPhotos('7', [MultipartFile.fromBytes([1, 2, 3], filename: 'a.png')]);
    final form = adapter.calls.single.data as FormData;
    expect(form.files.single.key, 'files');
    expect(saved.single['path'], 'business/1/a.png');
  });
}
