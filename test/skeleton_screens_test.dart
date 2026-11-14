// Loading states of representative screens: the right skeleton, nothing jumps,
// and a revisit shows the cached data (NxSwrCache) instead of a skeleton.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/calendar_home_screen.dart';
import 'package:nextx_mobile/screens/chat/chat_home_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nextx_mobile/screens/doc_form/quotation_step_form.dart';
import 'package:nextx_mobile/screens/hr/leave_screen.dart';
import 'package:nextx_mobile/screens/notifications/notification_center_screen.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/widgets/nx_entity_row.dart';
import 'package:nextx_mobile/widgets/nx_list_toolbar.dart';
import 'package:nextx_mobile/widgets/nx_skeleton.dart';
import 'package:nextx_mobile/widgets/nx_status_stepper.dart';

import 'support/fake_api.dart';

/// Holds every reply until [open] (a slow network: the skeleton must show).
class _Gate implements HttpClientAdapter {
  _Gate(this.inner);
  final FakeNextxAdapter inner;
  Completer<void> _gate = Completer<void>();

  void open() {
    if (!_gate.isCompleted) _gate.complete();
  }

  /// Hold replies again (the next visit).
  void hold() => _gate = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    await _gate.future;
    return inner.fetch(o, s, c);
  }

  @override
  void close({bool force = false}) {}
}

final _leads = [
  for (final (i, n) in ['บริษัท สยามเทค จำกัด', 'คุณมานพ ศรีสุข', 'ร้านกาแฟดอยช้าง', 'บจก. ไทยโลจิสติกส์'].indexed)
    {'id': 100 + i, 'lastname': n, 'company': 'NEXTX', 'email': 'lead$i@example.com', 'leadstatus': 'New'},
];

const _leadFields = {
  'list': [
    {'fieldname': 'lastname', 'fieldlabel': 'ชื่อ', 'uitype': 1},
    {'fieldname': 'leadstatus', 'fieldlabel': 'สถานะ', 'uitype': 15},
  ],
  'picklists': {
    'leadstatus': [
      {'value': 'New', 'label': 'ใหม่'},
      {'value': 'Contacted', 'label': 'ติดต่อแล้ว'},
      {'value': 'Qualified', 'label': 'มีโอกาส'},
    ],
  },
};

late _Gate _api;

Future<AppConfig> _pump(WidgetTester tester, Widget screen, Map<String, Object?> replies, {List<String> menus = const [], Size size = const Size(412, 915)}) async {
  SharedPreferences.setMockInitialValues({'getting_started_done': true});
  FlutterSecureStorage.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
  HomeChartCache.instance.clear();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  config.debugOverrideSession(SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: menus, displayName: 'สมชาย ใจดี'));
  _api = _Gate(FakeNextxAdapter({'GET /api/health': {'status': 'ok'}, ...replies}));
  config.apiClient.debugSetHttpAdapter(_api);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  await tester.pump(const Duration(milliseconds: 400));
  return config;
}

/// Let held replies through and settle.
Future<void> _release(WidgetTester tester) async {
  _api.open();
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _end(WidgetTester tester) async {
  _api.open();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  setUp(() => Effects.preference.value = EffectsPreference.lite);

  testWidgets('entity detail: status bar room is held at the real bar height; tabs do not jump', (tester) async {
    // Opened from the list: the row already has the head's data; only fields / statuses load.
    await _pump(
      tester,
      EntityDetailScreen(module: 'lead', row: {..._leads[1], 'id': '101'}),
      {'GET /api/entity/lead/101': _leads[1], 'GET /api/fields/lead': _leadFields},
      menus: ['lead'],
    );
    final reserve = find.byKey(const ValueKey('detail-status-reserve'));
    expect(reserve, findsOneWidget);
    expect(find.byType(NxSkeletonDetailBody), findsOneWidget);
    // Body only: no second title / thin stepper inside the body skeleton.
    expect(find.byType(NxSkeletonHero), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('nx-skeleton-status-bar'))).height, NxStatusStepper.barHeight);
    final tabTop = tester.getTopLeft(find.byKey(const ValueKey('detail-tab-0'))).dy;

    await _release(tester);
    expect(reserve, findsNothing);
    final bar = find.byKey(const ValueKey('nx-status-bar'));
    expect(bar, findsOneWidget);
    expect(tester.getSize(bar).height, NxStatusStepper.barHeight);
    expect(tester.getTopLeft(find.byKey(const ValueKey('detail-tab-0'))).dy, closeTo(tabTop, 0.5));
    await _end(tester);
  });

  testWidgets('entity list: row skeleton ≈ real row height', (tester) async {
    await _pump(
      tester,
      const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง'),
      {'GET /api/entity/lead': {'list': _leads, 'meta': {'total': _leads.length}}},
      menus: ['lead'],
    );
    expect(find.byKey(const ValueKey('entity-list-skeleton')), findsOneWidget);
    final skelH = tester.getSize(find.byType(NxSkeletonRow).first).height;
    await _release(tester);
    expect(find.byType(NxEntityRow), findsWidgets);
    final realH = tester.getSize(find.byType(NxEntityRow).first).height;
    expect((skelH - realH).abs(), lessThanOrEqualTo(8), reason: 'skeleton $skelH vs row $realH');
    await _end(tester);
  });

  testWidgets('entity list revisit: cached first page at once, refreshes underneath', (tester) async {
    final config = await _pump(
      tester,
      const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง'),
      {'GET /api/entity/lead': {'list': _leads, 'meta': {'total': _leads.length}}},
      menus: ['lead'],
    );
    await _release(tester);
    final calls = _api.inner.calls.where((c) => c.path == '/api/entity/lead').length;
    _api.hold();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: SizedBox())));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง'))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('entity-list-skeleton')), findsNothing);
    expect(find.text('บริษัท สยามเทค จำกัด'), findsOneWidget);
    await _release(tester);
    expect(_api.inner.calls.where((c) => c.path == '/api/entity/lead').length, greaterThan(calls), reason: 'refreshed in the background');
    await _end(tester);
  });

  testWidgets('entity detail revisit: last record at once, no skeleton', (tester) async {
    final config = await _pump(
      tester,
      const EntityDetailScreen(module: 'lead', row: {'id': '101', 'lastname': 'คุณมานพ'}),
      {'GET /api/entity/lead/101': {..._leads[1], 'mobile': '0899999999'}, 'GET /api/fields/lead': _leadFields},
      menus: ['lead'],
    );
    await _release(tester);
    _api.hold();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: SizedBox())));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityDetailScreen(module: 'lead', row: {'id': '101', 'lastname': 'คุณมานพ'})),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NxSkeletonDetailBody), findsNothing);
    expect(find.byKey(const ValueKey('nx-status-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-refresh-bar')), findsOneWidget);
    await _release(tester);
    expect(find.byKey(const ValueKey('nx-refresh-bar')), findsNothing);
    await _end(tester);
  });

  testWidgets('notification center: flat divided rows under day headings', (tester) async {
    await _pump(tester, const NotificationCenterScreen(), {'GET /api/notifications': {'list': []}});
    expect(find.byKey(const ValueKey('notif-skeleton')), findsOneWidget);
    expect(find.byType(NxSkeletonCard), findsNothing, reason: 'flat rows, not cards');
    expect(find.byType(Divider), findsWidgets);
    await _end(tester);
  });

  testWidgets('notification settings: SettingsGroup skeleton', (tester) async {
    await _pump(tester, const NotificationPrefsScreen(), {});
    expect(find.byKey(const ValueKey('notif-prefs-skeleton')), findsOneWidget);
    expect(find.byType(NxSkeletonSettingsGroup), findsWidgets);
    await _end(tester);
  });

  testWidgets('chat home: the real toolbar stays above the row skeleton', (tester) async {
    await _pump(tester, const ChatHomeScreen(), {'GET /api/chat/rooms': []}, menus: ['chat']);
    expect(find.byKey(const ValueKey('chat-home-skeleton')), findsOneWidget);
    expect(find.byType(NxListToolbar), findsOneWidget);
    await _end(tester);
  });

  testWidgets('leave: balance grid with rings; tabs kept alive (no re-fetch on swipe back)', (tester) async {
    await _pump(tester, const LeaveScreen(), {
      'GET /api/hr/leave-balance': {
        'list': [
          {'leave_type_id': 1, 'leave_type_name': 'ลาป่วย', 'total_days': 30, 'used_days': 2},
        ],
      },
      'GET /api/hr/leave-types': {'list': []},
      'GET /api/hr/leave-requests': {'list': []},
    }, menus: ['leave']);
    expect(find.byKey(const ValueKey('leave-balance-skeleton')), findsOneWidget);
    expect(find.byType(NxSkeletonGrid), findsOneWidget);
    await _release(tester);
    final before = _api.inner.calls.where((c) => c.path == '/api/hr/leave-balance').length;
    await tester.tap(find.text('ของฉัน'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('คงเหลือ'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_api.inner.calls.where((c) => c.path == '/api/hr/leave-balance').length, before);
    expect(find.byKey(const ValueKey('leave-balance-skeleton')), findsNothing);
    await _end(tester);
  });

  testWidgets('calendar agenda: day headings + event tiles, no week strip', (tester) async {
    await _pump(tester, const CalendarHomeScreen(), {'GET /api/entity/activity': {'list': []}}, menus: ['calendar']);
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NxSkeletonAgenda), findsOneWidget);
    await _end(tester);
  });

  testWidgets('step form: real step strip over section cards and the action bar', (tester) async {
    await _pump(tester, const QuotationStepForm(), {}, menus: ['quotation']);
    expect(find.byKey(const ValueKey('docform-skeleton')), findsOneWidget);
    expect(find.byType(NxSkeletonStepForm), findsOneWidget);
    expect(find.byType(NxSkeletonFieldBox), findsWidgets);
    await _end(tester);
  });

  testWidgets('home: saved widgets as frames (chart cards at their fixed height)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['deal', 'quotation', 'workspace', 'attendance']));
    await tester.runAsync(() => HomeLayout.instance.load(config.businessScope, legacyScope: config.prefsScope, force: true));
    _api = _Gate(FakeNextxAdapter({}));
    config.apiClient.debugSetHttpAdapter(_api);
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: Scaffold(body: MobileDashboardScreen()))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('home-skeleton')), findsOneWidget);
    expect(find.byType(NxSkeletonKpiGrid), findsNothing);
    expect(find.byKey(const ValueKey('home-skel-sales')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-skel-work')), findsOneWidget);
    final chart = find.byKey(const ValueKey('home-skel-chart_pipeline'));
    expect(chart, findsOneWidget);
    expect(tester.getSize(chart).height, 252);
    await _end(tester);
  });
}
