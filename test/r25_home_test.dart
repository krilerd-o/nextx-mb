import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_boxes.dart';

import 'support/fake_api.dart';

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget child, Map<String, Object?> replies, {Map<String, int> status = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  final adapter = FakeNextxAdapter(replies, statusFor: status);
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['workspace', 'case', 'deal']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return adapter;
}

void main() {
  test('periods: week is Monday–Sunday, quarter and month end correctly', () {
    final now = DateTime(2026, 11, 8); // Sunday
    expect(periodRange(NxPeriod.week, now), (DateTime(2026, 11, 2), DateTime(2026, 11, 8)));
    expect(periodRange(NxPeriod.month, now), (DateTime(2026, 11, 1), DateTime(2026, 11, 30)));
    expect(periodRange(NxPeriod.quarter, now), (DateTime(2026, 10, 1), DateTime(2026, 12, 31)));
    expect(myWorkRange(MyWorkRange.tomorrow, now), (DateTime(2026, 11, 9), DateTime(2026, 11, 9)));
  });

  test('pending / my work keep only Task, Subtask, Bug, Story', () {
    expect(isWorkType({'type': 'task'}), isTrue);
    expect(isWorkType({'type': 'subtask'}), isTrue);
    expect(isWorkType({'type': 'epic', 'row_kind': 'epic'}), isFalse);
    expect(isWorkType({'type': 'checklist'}), isFalse);
  });

  testWidgets('my work: today by default, chips change the due range, collapsible', (tester) async {
    final adapter = await _pump(tester, const MyWorkBox(), {
      'GET /api/workspace/items': [
        {'id': 1, 'board_id': 3, 'title': '[QA] งานวันนี้', 'type': 'task', 'board_name': 'NEXTT', 'status_name': 'To do'},
        {'id': 2, 'board_id': 3, 'title': '[QA] Epic', 'type': 'epic', 'row_kind': 'epic'},
      ],
    });
    final first = adapter.calls.firstWhere((c) => c.path == '/api/workspace/items');
    expect(first.queryParameters['due_from'], first.queryParameters['due_to'], reason: 'today = one day');
    expect(first.queryParameters['assignee_id'], '7');
    expect(find.text('[QA] Epic'), findsNothing);
    expect(find.textContaining('[QA] งานวันนี้'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('mywork-MyWorkRange.week')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mywork-MyWorkRange.week')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final week = adapter.calls.lastWhere((c) => c.path == '/api/workspace/items');
    expect(week.queryParameters['due_from'], isNot(week.queryParameters['due_to']));
    await tester.tap(find.byKey(const ValueKey('mywork-header')));
    await tester.pumpAndSettle();
    expect(find.textContaining('[QA] งานวันนี้'), findsNothing);
  });

  testWidgets('cases: this week by default, status buckets and SLA', (tester) async {
    final adapter = await _pump(tester, const CasePeriodBox(), {
      'GET /api/service-dashboard/case-summary': {
        'kpis': {'opened': 12, 'open_now': 5, 'closed': 6, 'overdue_now': 2},
        'by_status': [
          {'key': 'in_progress', 'count': 3},
          {'key': 'accepted', 'count': 1},
          {'key': 'waiting', 'count': 2},
        ],
      },
      'GET /api/service-dashboard/case-performance': {'kpis': {'sla_pct': 87.5}},
    });
    final call = adapter.calls.firstWhere((c) => c.path == '/api/service-dashboard/case-summary');
    expect(call.queryParameters['dateFrom'], isNotNull);
    for (final t in ['เคสทั้งหมด', 'เคสที่เปิด', 'กำลังดำเนินการ', 'เคสที่ปิด', 'เคสค้าง', 'รอปิด', 'SLA']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('4'), findsOneWidget, reason: 'in progress + accepted');
    expect(find.text('88%'), findsOneWidget);
  });

  testWidgets('sales: this month by default and sends the date range', (tester) async {
    final adapter = await _pump(tester, const SalesPeriodBox(), {
      'GET /api/dashboard/sales': {
        'deal': {'openCount': 3, 'openAmount': 100000, 'wonAmount': 50000, 'wonCount': 1},
        'quotation': {'awaitingCount': 2},
      },
    });
    final call = adapter.calls.firstWhere((c) => c.path == '/api/dashboard/sales');
    expect(call.queryParameters['dateFrom'], endsWith('-01'));
    expect(find.text('ดีลเปิดอยู่'), findsOneWidget);
  });
}
