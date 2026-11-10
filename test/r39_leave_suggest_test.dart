import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/leave_suggest.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/hr/leave_screen.dart';

import 'support/fake_api.dart';

final _types = [
  {'id': 1, 'name': 'ลาป่วย', 'code': 'SICK'},
  {'id': 2, 'name': 'ลากิจ', 'code': 'PERSONAL'},
  {'id': 3, 'name': 'ลาพักร้อน', 'code': 'VACATION'},
];

void main() {
  test('kind from name / code', () {
    expect(leaveKindOf({'name': 'ลาป่วย'}), LeaveKind.sick);
    expect(leaveKindOf({'name': 'Annual leave', 'code': 'AL'}), LeaveKind.vacation);
    expect(leaveKindOf({'name': 'ลากิจส่วนตัว'}), LeaveKind.personal);
    expect(leaveKindOf({'name': 'ลาคลอด'}), LeaveKind.maternity);
    expect(leaveKindOf({'name': 'อื่นๆ'}), LeaveKind.other);
  });

  test('default range: sick = today, others = next working day', () {
    final fri = DateTime(2026, 11, 13); // Friday
    final sick = defaultLeaveRange(LeaveKind.sick, now: fri);
    expect(sick.start, DateTime(2026, 11, 13));
    final vac = defaultLeaveRange(LeaveKind.vacation, now: fri);
    expect(vac.start, DateTime(2026, 11, 16)); // Monday
    expect(leaveDays(vac), 1);
  });

  test('date presets on a Monday', () {
    final mon = DateTime(2026, 11, 9);
    final p = {for (final x in leaveDatePresets(now: mon)) x.id: x.range};
    expect(p['today']!.start, mon);
    expect(p['tomorrow']!.start, DateTime(2026, 11, 10));
    expect(leaveDays(p['to_friday']!), 5);
    expect(p['next_week']!.start, DateTime(2026, 11, 16));
    expect(leaveDays(p['next_week']!), 5);
  });

  test('suggested type: last used with days left, else first with days left', () {
    final remaining = {1: 30, 2: 0, 3: 6};
    final mine = [
      {'leave_type_id': 2, 'status': 'Approved', 'created_at': '2026-11-01'},
      {'leave_type_id': 3, 'status': 'Approved', 'created_at': '2026-10-01'},
    ];
    // Last used = 2 but no days left → next most recent with days = 3.
    expect(suggestLeaveTypeId(_types, remaining, mine), 3);
    expect(suggestLeaveTypeId(_types, {1: 0, 2: 3, 3: 6}, const []), 2);
    expect(suggestLeaveTypeId(_types, const {}, const []), 1);
  });

  test('overlap with my pending / approved request', () {
    final mine = [
      {'start_date': '2026-11-10', 'end_date': '2026-11-11', 'status': 'Pending'},
      {'start_date': '2026-11-20', 'end_date': '2026-11-20', 'status': 'Cancelled'},
    ];
    expect(overlappingLeave(DateTimeRange(start: DateTime(2026, 11, 11), end: DateTime(2026, 11, 12)), mine), isNotNull);
    expect(overlappingLeave(DateTimeRange(start: DateTime(2026, 11, 20), end: DateTime(2026, 11, 20)), mine), isNull);
    expect(leaveNeedsCertificateHint(LeaveKind.sick, 3), isTrue);
    expect(leaveNeedsCertificateHint(LeaveKind.sick, 2), isFalse);
  });

  testWidgets('request form: suggested type marked, sick → today, reason chip fills, summary shows balance', (tester) async {
    SharedPreferences.setMockInitialValues({'getting_started_done': true});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    config.apiClient.debugSetHttpAdapter(FakeNextxAdapter({
      'GET /api/health': {'status': 'ok'},
      'GET /api/hr/leave-types': {'list': _types},
      'GET /api/hr/leave-balance': {
        'list': [
          {'leave_type_id': 1, 'leave_type_name': 'ลาป่วย', 'total_days': 30, 'used_days': 2},
          {'leave_type_id': 2, 'leave_type_name': 'ลากิจ', 'total_days': 3, 'used_days': 3},
          {'leave_type_id': 3, 'leave_type_name': 'ลาพักร้อน', 'total_days': 6, 'used_days': 0},
        ],
      },
      'GET /api/hr/leave-requests': {
        'list': [
          {'id': 9, 'leave_type_id': 1, 'leave_type_name': 'ลาป่วย', 'status': 'Approved', 'start_date': '2026-10-01', 'end_date': '2026-10-02', 'created_at': '2026-10-01'},
        ],
      },
    }));
    config.debugOverrideSession(const SessionState(
      accessToken: 't', userId: '3', businessId: '1', businessName: '[QA] Biz', packageCode: 'crm', menusLoaded: true, menuKeys: ['leave'],
    ));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(theme: AppTheme.light, home: const LeaveScreen(initialTab: 1)),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('leave-request-form')), findsOneWidget);
    // Last used = ลาป่วย (days left) → suggested + selected; sick defaults to today (1 day).
    expect(find.descendant(of: find.byKey(const ValueKey('leave-type-1')), matching: find.text('แนะนำ')), findsOneWidget);
    expect(find.text('สิทธิ์หมดแล้ว'), findsOneWidget); // ลากิจ 3/3 used
    expect(find.textContaining('คงเหลือหลังลา 27 วัน'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-reason-ไม่สบาย มีไข้')));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'ไม่สบาย มีไข้'), findsOneWidget);
    // Next week (5 days) on the vacation type: 6 - 5 = 1 left.
    await tester.tap(find.byKey(const ValueKey('leave-type-3')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('leave-date-next_week')));
    await tester.tap(find.byKey(const ValueKey('leave-date-next_week')));
    await tester.pump();
    expect(find.textContaining('ลาพักร้อน · 5 วัน'), findsOneWidget);
    expect(find.textContaining('คงเหลือหลังลา 1 วัน'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
