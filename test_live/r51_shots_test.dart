// Manual tool: screenshots of the R51 case status windows (SHOTS_DIR=… flutter test test_live/r50_shots_test.dart)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_api.dart';

final _out = Platform.environment['SHOTS_DIR'] ?? '/tmp';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
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
    testWidgets('case shots dark=$dark', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      ServiceJourney.debugClear();
      final row = {
        'id': 7, 'case_no': 'CS26111100007', 'case_title': '[QA] เครื่องพิมพ์สำนักงานใช้งานไม่ได้', 'case_status': 'กำลังดำเนินการ',
        'smownerid': 2, 'smownerid_name': '[QA] Second', 'account_name': 'บริษัท [QA] จำกัด', 'original_estimate_minutes': 90,
      };
      final adapter = FakeNextxAdapter({
        'GET /api/settings/job': {'config': {}},
        'GET /api/tags': {'list': []},
        'GET /api/entity/case/7': row,
        'GET /api/entity/case/8': {...row, 'id': 8, 'case_status': 'เปิดเคส', '_shared_permission': 'read_only'},
        for (final i in [7, 8]) ...{
          'GET /api/entity/case/$i/comments': {'list': []},
          'GET /api/entity/case/$i/tags': {'list': []},
        },
        'GET /api/fields/case': {'list': [], 'picklists': {}},
        'GET /api/entity/case/7/workflow-preview': {'summaryTh': 'ยังไม่ได้ตั้ง SMTP — ระบบจะบันทึกแต่ยังไม่ส่งอีเมล'},
        'GET /api/field-service/cases/7/open-jobs': {'list': [{'id': 3, 'job_no': 'JOB26111100003'}]},
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: '[QA] Second', businessRole: 'member', menusLoaded: true, menuKeys: ['case']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(400, 860);
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
          File('$_out/r51_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: MaterialApp(key: UniqueKey(), theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home),
            ),
          );
      await tester.pumpWidget(app(EntityDetailScreen(key: UniqueKey(), module: 'case', row: const {'id': 7})));
      await frames(24);
      await shot('case_detail');
      await tester.tap(find.byKey(const ValueKey('case-btn-close')));
      await frames(12);
      await shot('case_close');
      Navigator.of(tester.element(find.byKey(const ValueKey('case-flow-save')))).pop();
      await frames(8);
      await tester.tap(find.byKey(const ValueKey('case-btn-cancel')));
      await frames(12);
      await shot('case_cancel');
      await tester.pumpWidget(app(EntityDetailScreen(key: UniqueKey(), module: 'case', row: const {'id': 8})));
      await frames(24);
      await tester.tap(find.byKey(const ValueKey('case-btn-accept')));
      await frames(10);
      await shot('case_no_permission');
    });
  }
}
