import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_model.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_month_view.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_time_grid.dart';
import 'package:nextx_mobile/screens/calendar/cal/cal_year_view.dart';
import 'package:nextx_mobile/screens/calendar/calendar_home_screen.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = calDay(thaiNow());
  String iso(DateTime d) => '${calKey(d)}T${hm(d)}:00.000Z'; // fake-Z wall clock, as NEXTX sends

  Future<FakeNextxAdapter> pump(WidgetTester tester, {String view = 'month'}) async {
    SharedPreferences.setMockInitialValues({'flutter.nx_cal_view_': view});
    final adapter = FakeNextxAdapter({
      'GET /api/entity/activity': {
        'list': [
          {'id': 31, 'subject': '[QA] นัดเช้า', 'activitytype': 'Meeting', 'status': 'Planned', 'date_start': iso(today.add(const Duration(hours: 10))), 'date_end': iso(today.add(const Duration(hours: 11)))},
          for (final (i, t) in ['[QA] วันหยุด A', '[QA] วันหยุด B', '[QA] วันหยุด C'].indexed)
            {'id': 40 + i, 'subject': t, 'all_day': true, 'date_start': calKey(today), 'date_end': calKey(today.add(const Duration(days: 1)))},
        ],
        'total': 4,
      },
      'PUT /api/entity/activity/31': {'id': 31},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['calendar']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: const MaterialApp(home: CalendarHomeScreen())));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return adapter;
  }

  /// Scroll the time grid so 10:00 sits mid-screen (away from auto-scroll edges).
  Future<void> centerGrid(WidgetTester tester) async {
    final sv = tester.widget<SingleChildScrollView>(find.descendant(of: find.byType(CalTimeGrid), matching: find.byType(SingleChildScrollView)).first);
    sv.controller!.jumpTo(10 * 56 - 150);
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> lastPut(FakeNextxAdapter a) {
    final c = a.calls.lastWhere((c) => c.method == 'PUT');
    final d = c.data;
    return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
  }

  testWidgets('month: today\'s list in Thai wall time; scrolling folds the month into a week', (tester) async {
    await pump(tester);
    expect(find.text('[QA] นัดเช้า'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget, reason: 'fake-Z wall clock must not become 17:00');
    expect(find.text('17:00'), findsNothing);
    final state = tester.state<CalMonthViewState>(find.byType(CalMonthView));
    expect(state.collapse, 0);
    await tester.drag(find.text('[QA] นัดเช้า'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(state.collapse, greaterThan(0.99), reason: 'month folded to the selected week');
    // Tapping the handle opens it again.
    await tester.tap(find.byKey(const ValueKey('cal-month-handle')));
    await tester.pumpAndSettle();
    expect(state.collapse, lessThan(0.01));
  });

  testWidgets('title tap → year; a month tile zooms into that month', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('nx-header-title')));
    await tester.pumpAndSettle();
    expect(find.byType(CalYearView), findsOneWidget);
    expect(find.text('${uiYearTest(today.year)}'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('cal-year-month-1')));
    await tester.pumpAndSettle();
    expect(find.byType(CalMonthView), findsOneWidget);
    expect(find.text('ม.ค. ${uiYearTest(today.year)}'), findsOneWidget);
  });

  testWidgets('day view: "+N" opens the floating day card; resize saves a longer end', (tester) async {
    final adapter = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('cal-tab-day')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('cal-tab-day')));
    await tester.pumpAndSettle();
    // 3 all-day + the timed one: day view shows 2 chips + "+2".
    final more = find.byKey(ValueKey('cal-more-${calKey(today)}'));
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('[QA] วันหยุด C'), findsWidgets);
    expect(find.text('[QA] นัดเช้า'), findsWidgets);
    await tester.tapAt(const Offset(5, 5)); // close the card
    await tester.pumpAndSettle();

    // Drag the bottom edge of 10:00–11:00 down one hour → ends 12:00.
    final handle = find.byKey(const ValueKey('cal-resize-31'));
    await centerGrid(tester);
    await tester.drag(handle, const Offset(0, 56), touchSlopY: 0);
    await tester.pumpAndSettle();
    final body = lastPut(adapter);
    expect(body['date_start'], '${calKey(today)} 10:00:00');
    expect(body['date_end'], '${calKey(today)} 12:00:00');
    expect(find.text('เลิกทำ'), findsOneWidget);
  });

  testWidgets('day view: long-press drag moves the appointment (15-min steps)', (tester) async {
    final adapter = await pump(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('cal-tab-day')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('cal-tab-day')));
    await tester.pumpAndSettle();
    final block = find.byKey(const ValueKey('cal-block-31'));
    await centerGrid(tester);
    final g = await tester.startGesture(tester.getCenter(block) - const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(0, 14)); // 112 px = 2 hours
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(const ValueKey('cal-ghost-label')), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    final body = lastPut(adapter);
    expect(body['date_start'], '${calKey(today)} 12:00:00');
    expect(body['date_end'], '${calKey(today)} 13:00:00');
  });

  testWidgets('all seven views open', (tester) async {
    await pump(tester);
    for (final v in CalView.values) {
      await tester.ensureVisible(find.byKey(ValueKey('cal-tab-${v.name}')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(ValueKey('cal-tab-${v.name}')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: v.name);
    }
    // List view groups by day with Thai headings.
    expect(find.textContaining('วันนี้'), findsWidgets);
    expect(find.text('[QA] นัดเช้า'), findsOneWidget);
  });
}

int uiYearTest(int y) => y + 543;
