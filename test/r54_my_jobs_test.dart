import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/jobs/my_jobs_screen.dart';

import 'support/fake_api.dart';

String _ymd(DateTime d, [String time = '09:30:00']) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T$time';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = thaiNow();
  final today = _ymd(now);
  final tomorrow = _ymd(now.add(const Duration(days: 1)), '13:00:00');
  final lastWeek = _ymd(now.subtract(const Duration(days: 3)));

  test('buckets', () {
    expect(myJobBucket({'job_status': 'Open', 'plan_start': today}, now), MyJobBucket.today);
    expect(myJobBucket({'job_status': 'Open', 'plan_start': lastWeek}, now), MyJobBucket.today);
    expect(myJobOverdue({'job_status': 'Open', 'plan_start': lastWeek}, now), isTrue);
    expect(myJobBucket({'job_status': 'In Progress', 'plan_start': tomorrow}, now), MyJobBucket.active);
    expect(myJobBucket({'job_status': 'Open', 'plan_start': tomorrow}, now), MyJobBucket.upcoming);
    expect(myJobBucket({'job_status': 'Open'}, now), MyJobBucket.unscheduled);
    expect(myJobBucket({'job_status': 'Completed', 'plan_start': today}, now), MyJobBucket.done);
  });

  Future<FakeNextxAdapter> pump(WidgetTester tester, {bool hintSeen = false}) async {
    SharedPreferences.setMockInitialValues({if (hintSeen) 'nx_my_jobs_hint_v1': true});
    FlutterSecureStorage.setMockInitialValues({});
    ServiceJourney.debugClear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter({
      'GET /api/settings/job': {'config': {}},
      'GET /api/field-service/jobs/awaiting-me': {'list': []},
      'GET /api/field-service/me/jobs': {'list': [
        {'id': 1, 'job_no': 'JOB-1', 'job_name': '[QA] ล้างแอร์', 'job_status': 'Open', 'plan_start': today, 'customer_name': '[QA] ร้านกาแฟ', 'customer_mobile': '081-234-5678', 'site_address_snapshot': '99 ถ.สุขุมวิท กรุงเทพฯ'},
        {'id': 2, 'job_no': 'JOB-2', 'job_name': '[QA] ซ่อมปั๊ม', 'job_status': 'Open', 'plan_start': lastWeek, 'customer_name': '[QA] โรงงาน'},
        {'id': 3, 'job_no': 'JOB-3', 'job_name': '[QA] ติดตั้ง', 'job_status': 'In Progress', 'plan_start': today, 'related_activity_id': 8},
        {'id': 4, 'job_no': 'JOB-4', 'job_name': '[QA] ตรวจเช็ค', 'job_status': 'Open', 'plan_start': tomorrow},
        {'id': 5, 'job_no': 'JOB-5', 'job_name': '[QA] เสร็จแล้ว', 'job_status': 'Completed', 'plan_start': lastWeek},
      ]},
    });
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['job']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: MyJobsScreen())));
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    return adapter;
  }

  testWidgets('today first: today + overdue, KPIs, field actions on the card; done jobs requested', (tester) async {
    final a = await pump(tester);
    final call = a.calls.firstWhere((c) => c.path == '/api/field-service/me/jobs');
    expect(call.queryParameters['include_done'], '1');
    expect(find.byKey(const ValueKey('my-jobs-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-overdue-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-4')), findsNothing);
    expect(find.byKey(const ValueKey('my-job-nav-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-call-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-accept-1')), findsOneWidget); // journey server: accept on the card
    expect(find.text('09:30'), findsWidgets);
  });

  testWidgets('tabs switch buckets; search filters', (tester) async {
    await pump(tester, hintSeen: true);
    expect(find.byKey(const ValueKey('my-jobs-hint')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('my-jobs-tab-1')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('my-jobs-tab-1')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('my-job-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-checkin-3')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('my-jobs-tab-2')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('my-jobs-tab-2')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('my-job-4')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('my-jobs-tab-4')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('my-jobs-tab-4')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('my-job-5')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('my-jobs-tab-0')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('my-jobs-tab-0')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('my-jobs-search')), 'โรงงาน');
    await tester.pump();
    expect(find.byKey(const ValueKey('my-job-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('my-job-1')), findsNothing);
  });

  testWidgets('explains the difference from the Job menu', (tester) async {
    await pump(tester, hintSeen: true);
    await tester.tap(find.byTooltip('ต่างจากใบสั่งงานอย่างไร'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.text('ใบสั่งงาน (Job)'), findsOneWidget);
    expect(find.byKey(const ValueKey('my-jobs-open-all')), findsOneWidget);
  });
}
