// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Screenshots of the R47 Home widgets (manual): SHOTS_DIR=… flutter test test_live/r47_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/screens/dashboard/home_charts.dart';
import 'package:nextx_mobile/screens/dashboard/home_layout_editor.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';

import '../test/support/fake_api.dart';

final _out = Platform.environment['SHOTS_DIR'] ?? '/tmp';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

Map<String, dynamic> _sales(String from) {
  final m = int.parse(from.substring(5, 7));
  final f = 1 + (m % 3) * 0.15;
  return {
    'deal': {
      'byStage': [
        {'name': 'Qualification', 'value': 14, 'amount': 2800000},
        {'name': 'Value Proposition', 'value': 9, 'amount': 2100000},
        {'name': 'Proposal Sent', 'value': '6', 'amount': '1650000'},
        {'name': 'Negotiation', 'value': 3, 'amount': 900000},
        {'name': 'Closed Won', 'value': 8, 'amount': 1250000},
      ],
      'wonCount': 8,
      'wonAmount': 1250000 * f,
      'lostCount': 5,
      'winRate': null,
    },
    'quotation': {
      'byStatus': [
        {'name': 'Sent', 'value': '12'},
        {'name': 'Accepted', 'value': 7},
        {'name': 'Draft', 'value': 4},
        {'name': 'Rejected', 'value': 2},
      ],
    },
    'trend': [
      for (final (i, v) in [420000, 610000, 380000, 890000, 760000, 1250000].indexed)
        {'month': '2026-${(6 + i).toString().padLeft(2, '0')}', 'won_amount': '$v'},
    ],
  };
}

void main() {
  setUpAll(() async {
    final pc = '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.1/assets/build_font';
    await _font('GoogleSans', ['assets/fonts/GoogleSans-Regular.ttf', 'assets/fonts/GoogleSans-Medium.ttf', 'assets/fonts/GoogleSans-SemiBold.ttf', 'assets/fonts/GoogleSans-Bold.ttf']);
    await _font('IBMPlexSansThai', ['assets/fonts/IBMPlexSansThai-Regular.ttf', 'assets/fonts/IBMPlexSansThai-Medium.ttf', 'assets/fonts/IBMPlexSansThai-SemiBold.ttf', 'assets/fonts/IBMPlexSansThai-Bold.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide300', ['$pc/LucideVariable-w300.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide500', ['$pc/LucideVariable-w500.ttf']);
  });

  for (final dark in [false, true]) {
    testWidgets('shots dark=$dark', (tester) async {
      SharedPreferences.setMockInitialValues({
        // A Home that shows the charts first (classic sections after).
      });
      FlutterSecureStorage.setMockInitialValues({});
      HomeChartCache.instance.clear();
      resetHomeChartMemory();
      final adapter = FakeNextxAdapter({
        'GET /api/dashboard/home-summary': {'stats': {}},
        'GET /api/home/work': {
          'counts': {'overdue': 2, 'today': 3, 'upcoming': 5},
          'work_weeks': [
            for (final (i, w) in ['2026-10-05', '2026-10-12', '2026-10-19', '2026-10-26', '2026-11-02', '2026-11-09'].indexed)
              {'week': w, 'created': [6, 9, 7, 11, 8, 10][i], 'cleared': '${[4, 7, 8, 9, 10, 9][i]}'},
          ],
        },
        'GET /api/dashboard/customer': {
          'lead': {
            'bySource': [
              {'name': 'Website', 'value': 18},
              {'name': 'Facebook', 'value': '11'},
              {'name': 'LINE', 'value': 8},
              {'name': '—', 'value': 5},
            ],
            'kpis': {'created': 50, 'converted': 17, 'conversion_rate': 0.34},
          },
        },
        'GET /api/home/case-sla-summary': {'counts': {'met': '41', 'missed': 4}, 'compliance_pct': null},
        'GET /api/hr/leave-balance': [
          {'leave_type_name': 'ลาป่วย', 'total_days': '30.00', 'used_days': 4},
          {'leave_type_name': 'ลากิจ', 'total_days': '3.00', 'used_days': 1},
          {'leave_type_name': 'ลาพักร้อน', 'total_days': '6.00', 'used_days': 2},
        ],
      });
      adapter.onRequest = (o) {
        if (o.path == '/api/dashboard/sales') adapter.replies['GET /api/dashboard/sales'] = _sales('${o.queryParameters['dateFrom']}');
      };
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(
        accessToken: 't',
        userId: '2',
        businessId: '1',
        displayName: '[QA] Second',
        businessRole: 'admin',
        menusLoaded: true,
        menuKeys: ['deal', 'quotation', 'lead', 'case', 'workspace', 'leave-request'],
      ));
      config.apiClient.debugSetHttpAdapter(adapter);
      await tester.runAsync(() => HomeLayout.instance.saveEntries(config.businessScope, const [
            HomeEntry('chart_won', size: HomeSize.half),
            HomeEntry('chart_winrate', size: HomeSize.half),
            HomeEntry('chart_sales_trend'),
            HomeEntry('chart_pipeline'),
            HomeEntry('chart_lead_source', size: HomeSize.half),
            HomeEntry('chart_case_sla', size: HomeSize.half),
            HomeEntry('chart_work'),
            HomeEntry('chart_leave', size: HomeSize.half),
            HomeEntry('chart_lead_conv', size: HomeSize.half),
            HomeEntry('quick'),
          ]));
      tester.view.physicalSize = const Size(400, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      Future<void> frames([int n = 14]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      Future<void> shot(String name) async {
        final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        await tester.runAsync(() async {
          final i = await ro.toImage(pixelRatio: 2);
          final bytes = await i.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/r47_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home),
            ),
          );

      await tester.pumpWidget(app(const Scaffold(body: MobileDashboardScreen())));
      await frames(20);
      await shot('home');

      // Edit mode, mid-drag of "Pipeline".
      await tester.longPress(find.byKey(const ValueKey('home-chart-chart_won')));
      await frames(4);
      final from = tester.getCenter(find.byKey(const ValueKey('home-chart-chart_pipeline')));
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 450));
      await g.moveBy(const Offset(30, -60));
      await tester.pump(const Duration(milliseconds: 120));
      await g.moveBy(const Offset(10, -40));
      await tester.pump(const Duration(milliseconds: 120));
      await shot('edit_drag');
      await g.cancel();
      await frames(4);

      await tester.tap(find.byKey(const ValueKey('home-edit-add')));
      await frames(10);
      await shot('gallery');
      await tester.pumpWidget(const SizedBox());
      await frames(4);

      tester.view.physicalSize = const Size(400, 860);
      await tester.pumpWidget(app(const HomeLayoutEditorScreen()));
      await frames(8);
      await shot('settings');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });
  }
}
