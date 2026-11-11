// Manual tool: screenshots of R52 (two-pane, compare, revise, case history, upload pill) (SHOTS_DIR=… flutter test test_live/r50_shots_test.dart)
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
import 'package:nextx_mobile/screens/journey/quotation_versions.dart';
import 'package:nextx_mobile/screens/journey/case_flows.dart';
import 'package:nextx_mobile/widgets/nx_upload_pill.dart';
import 'package:nextx_mobile/services/photo_upload_center.dart';
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
    testWidgets('r52 shots dark=$dark', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      ServiceJourney.debugClear();
      final adapter = FakeNextxAdapter({
        'GET /api/settings/job': {'config': {}},
        'GET /api/tags': {'list': []},
        'GET /api/users': {'list': [{'user_id': 2, 'display_name': '[QA] Second'}]},
        for (final m in ['job', 'case']) ...{
          'GET /api/entity/$m/9/comments': {'list': []},
          'GET /api/entity/$m/9/tags': {'list': []},
          'GET /api/fields/$m': {'list': [], 'picklists': {}},
        },
        'GET /api/entity/job/9': {'id': 9, 'job_no': 'JOB26111100001', 'job_name': '[QA] ติดตั้งแอร์ 3 เครื่อง', 'job_status': 'In Progress', 'smownerid': 2, 'smownerid_name': '[QA] Second', 'account_name': 'บริษัท [QA] จำกัด', 'plan_start': '2026-11-12T09:00:00', 'evidence_photos': []},
        'GET /api/field-service/jobs/9/overview': {'job_status': 'In Progress', 'has_owner': true, 'can_close': true, 'activities': {'total': 2, 'open': 0, 'done': 2}, 'signatures': {'total': 2, 'signed': 1}, 'parts': 1},
        'GET /api/field-service/jobs/9/signatures': {'slots': [{'slot_key': 'tech', 'position_th': 'ช่างผู้ปฏิบัติงาน', 'signer_role': 'staff', 'signature_path': 'x.png', 'signer_name': '[QA] Second'}, {'slot_key': 'customer', 'position_th': 'ลูกค้าผู้ตรวจรับ', 'signer_role': 'customer'}]},
        'GET /api/links/job/9': {'activities': [{'id': 3, 'title': '[QA] เข้าหน้างาน', 'subtitle': '12/11 09:00', 'status': 'Done'}]},
        'GET /api/entity/case/9': {'id': 9, 'case_no': 'CS26111100009', 'case_title': '[QA] เครื่องพิมพ์ใช้งานไม่ได้', 'case_status': 'กำลังดำเนินการ', 'smownerid': 2},
        'GET /api/entity/case/9/status-events': {'list': [
          {'action': 'wait', 'from_status': 'กำลังดำเนินการ', 'to_status': 'รอการตอบรับ', 'details': {'note': '[QA] รออะไหล่'}, 'at': '2026-11-11T03:10:00Z', 'user_name': '[QA] Second'},
          {'action': 'accept', 'from_status': 'เปิดเคส', 'to_status': 'กำลังดำเนินการ', 'details': {}, 'at': '2026-11-11T02:00:00Z', 'user_name': '[QA] Second'},
          {'action': 'create', 'to_status': 'เปิดเคส', 'details': {}, 'at': '2026-11-10T09:30:00Z', 'user_name': '[QA] Second'},
        ]},
        'GET /api/quotation/8/compare/9': {
          'a': {'header': {'quotation_no': 'Q26111100002', 'title_th': '[QA] ติดตั้งระบบกล้อง', 'grand_total': 13910, 'discount_total': 0, 'valid_until': '2026-11-30'}, 'lines': [
            {'description': '[QA] กล้อง IP 4MP', 'product_id': 5, 'quantity': 4, 'unit_price': 2500},
            {'description': '[QA] ค่าติดตั้ง', 'quantity': 1, 'unit_price': 3000},
          ]},
          'b': {'header': {'quotation_no': 'Q26111100002-R1', 'title_th': '[QA] ติดตั้งระบบกล้อง', 'grand_total': 25038, 'discount_total': 500, 'valid_until': '2026-12-15'}, 'lines': [
            {'description': '[QA] กล้อง IP 4MP', 'product_id': 5, 'quantity': 6, 'unit_price': 2400},
            {'description': '[QA] เครื่องบันทึก 8 ช่อง', 'quantity': 1, 'unit_price': 9000},
          ]},
        },
        'GET /api/quotation/9/lines': {'list': [
          {'id': 1, 'product_id': 5, 'description': '[QA] กล้อง IP 4MP', 'quantity': 6, 'unit_price': 2400},
          {'id': 2, 'description': '[QA] เครื่องบันทึก 8 ช่อง', 'quantity': 1, 'unit_price': 9000},
        ]},
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', displayName: '[QA] Second', businessRole: 'admin', menusLoaded: true, menuKeys: ['job', 'quotation', 'case']));
      config.apiClient.debugSetHttpAdapter(adapter);
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
          final i = await ro.toImage(pixelRatio: dark ? 1 : 1.5);
          final bytes = await i.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/r52_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: MaterialApp(key: UniqueKey(), theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home),
            ),
          );

      tester.view.physicalSize = const Size(1280, 860);
      await tester.pumpWidget(app(EntityDetailScreen(key: UniqueKey(), module: 'job', row: const {'id': 9})));
      await frames(26);
      await shot('job_tablet');
      if (dark) return;

      tester.view.physicalSize = const Size(420, 900);
      await tester.pumpWidget(app(const QuotationCompareScreen(versions: [
        {'id': 8, 'quotation_no': 'Q26111100002'},
        {'id': 9, 'quotation_no': 'Q26111100002-R1'},
      ], aId: '8', bId: '9')));
      await frames(12);
      await shot('qt_compare');

      await tester.pumpWidget(app(const QuotationReviseScreen(row: {'id': 9, 'quotation_no': 'Q26111100002-R1', 'title_th': '[QA] ติดตั้งระบบกล้อง', 'valid_until': '2026-12-15'})));
      await frames(12);
      await shot('qt_revise');

      await tester.pumpWidget(app(EntityDetailScreen(key: UniqueKey(), module: 'case', row: const {'id': 9})));
      await frames(22);
      await shot('case_actions');
      await tester.tap(find.byKey(const ValueKey('case-history-btn')));
      await frames(12);
      await shot('case_history');

      PhotoUploadCenter.instance.offline = true;
      await tester.pumpWidget(app(Scaffold(body: Stack(children: [
        const Center(child: Text('[QA] หน้าใดก็ได้')),
        NxUploadPill(navigatorKey: GlobalKey<NavigatorState>()),
      ]))));
      PhotoUploadCenter.instance.value = const UploadCenterState(active: 5, sent: 7, total: 12);
      await frames(8);
      await shot('upload_pill');
    });
  }
}
