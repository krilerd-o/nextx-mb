// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Screenshots of the R46 business card scan (manual): SHOTS_DIR=… flutter test test_live/r46_shots_test.dart
import 'dart:io';
import 'dart:typed_data';
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
import 'package:nextx_mobile/core/session_state.dart';
import 'package:image/image.dart' as img;
import 'package:nextx_mobile/screens/crm/card_scan/card_ocr.dart';
import 'package:nextx_mobile/screens/crm/card_scan/card_scan_flow.dart';
import 'package:nextx_mobile/screens/crm/card_scan/card_scan_models.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/widgets/nx_create_fab.dart';

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

  testWidgets('shots', (tester) async {
    // Sample [QA] card image.
    final card = img.Image(width: 900, height: 550);
    img.fill(card, color: img.ColorRgb8(252, 252, 250));
    img.fillRect(card, x1: 0, y1: 0, x2: 900, y2: 70, color: img.ColorRgb8(22, 163, 74));
    img.drawString(card, 'QA TESTING CO., LTD.', font: img.arial48, x: 40, y: 110, color: img.ColorRgb8(20, 20, 20));
    img.drawString(card, 'Somchai Jaidee', font: img.arial24, x: 40, y: 220, color: img.ColorRgb8(20, 20, 20));
    img.drawString(card, 'Sales Manager', font: img.arial24, x: 40, y: 255, color: img.ColorRgb8(90, 90, 90));
    img.drawString(card, 'M: 081-234-5678   T: 02-123-4567   F: 02-123-4568', font: img.arial24, x: 40, y: 350, color: img.ColorRgb8(40, 40, 40));
    img.drawString(card, 'somchai@qa-test.co.th   www.qa-test.co.th', font: img.arial24, x: 40, y: 390, color: img.ColorRgb8(40, 40, 40));
    img.drawString(card, '1168/111 Rama IV Rd, Thung Maha Mek, Sathon, Bangkok 10120', font: img.arial14, x: 40, y: 450, color: img.ColorRgb8(80, 80, 80));
    final jpeg = Uint8List.fromList(img.encodeJpg(card));
    CardScanFlow.debugCapture = (_) async => CardImages(front: jpeg);
    CardOcr.debugRead = (_) async => null;
    final scan = {
      'status': 'ok',
      'engine': 'gemini',
      'raw_text': 'QA TESTING CO., LTD.\nนายสมชาย ใจดี\nSomchai Jaidee\nSales Manager',
      'fields': {
        'lead_titlename': {'value': 'นาย', 'label': 'คำนำหน้า', 'confidence': 'high'},
        'lead_firstname': {'value': '[QA] สมชาย', 'label': 'ชื่อ', 'confidence': 'high'},
        'lead_lastname': {'value': 'ใจดี', 'label': 'นามสกุล', 'confidence': 'high'},
        'company_name': {'value': 'QA Testing Co., Ltd.', 'label': 'ชื่อบริษัท', 'confidence': 'high'},
        'position': {'value': 'Sales Manager', 'label': 'ตำแหน่ง', 'confidence': 'medium'},
        'mobile_1st': {'value': '0812345678', 'label': 'เบอร์ติดต่อ (หลัก)', 'confidence': 'high'},
        'mobile_2nd': {'value': '021234567', 'label': 'เบอร์ติดต่อ 2', 'confidence': 'high'},
        'email_1st': {'value': 'somchai@qa-test.co.th', 'label': 'อีเมล (หลัก)', 'confidence': 'high'},
        'address_postal_code': {'value': '10120', 'label': 'รหัสไปรษณีย์', 'confidence': 'high'},
      },
      'unmapped': [
        {'kind': 'fax', 'value': '021234568', 'label': 'โทรสาร'},
        {'kind': 'website', 'value': 'https://www.qa-test.co.th', 'label': 'เว็บไซต์'},
      ],
      'duplicates': [
        {'module': 'lead', 'id': 7, 'name': '[QA] สมชาย ใจดี', 'reason': 'อีเมล'},
      ],
    };
    final fields = [
      for (final e in {
        'lead_titlename': 'คำนำหน้า', 'lead_firstname': 'ชื่อ', 'lead_lastname': 'นามสกุล', 'company_name': 'ชื่อบริษัท', 'position': 'ตำแหน่ง',
        'mobile_1st': 'เบอร์ติดต่อ (หลัก)', 'mobile_2nd': 'เบอร์ติดต่อ 2', 'email_1st': 'อีเมล (หลัก)', 'address_postal_code': 'รหัสไปรษณีย์', 'description': 'รายละเอียด',
      }.entries)
        {'name': e.key, 'label_th': e.value, 'uitype': e.key == 'lead_titlename' ? 'Enum' : (e.key.startsWith('mobile') ? 'Phone' : 'Text')},
    ];
    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({'nx_crm_row_actions_hint_v1': true});
      FlutterSecureStorage.setMockInitialValues({});
      final adapter = FakeNextxAdapter({
        'GET /api/fields/lead': {'list': fields, 'picklists': {'lead_titlename': [{'value': 'นาย'}, {'value': 'นาง'}, {'value': 'นางสาว'}]}},
        'GET /api/modules': [],
        'GET /api/customviews': {'list': [], 'default_id': null},
        'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
        'GET /api/entity/lead': {'list': [], 'total': 0},
        'GET /api/users': {'list': []},
        'POST /api/crm/business-card/scan': scan,
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      Future<void> frames([int n = 14]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      Future<void> shot(String name) async {
        final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        await tester.runAsync(() async {
          final i = await ro.toImage(pixelRatio: 2);
          final bytes = await i.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/r46_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home),
            ),
          );

      await tester.pumpWidget(app(const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง')));
      await frames();
      await tester.tap(find.byType(NxCreateFab));
      await frames();
      await shot('options');
      await tester.pumpWidget(const SizedBox());
      await frames(4);

      tester.view.physicalSize = const Size(400, 1150);
      await tester.pumpWidget(app(const EntityCreateScreen(module: 'lead', title: 'สร้างผู้มุ่งหวัง')));
      await frames();
      await shot('form_banner');
      await tester.tap(find.byKey(const ValueKey('form-scan-banner')));
      await frames(30);
      await shot('review');
      await tester.dragUntilVisible(find.byKey(const ValueKey('card-extra-fax')), find.byType(Scrollable).first, const Offset(0, -300));
      await tester.tap(find.byKey(const ValueKey('card-extra-fax')));
      await frames(4);
      await tester.tap(find.byKey(const ValueKey('card-apply')));
      await frames(20);
      await shot('form_filled');
      await tester.pumpWidget(const SizedBox());
      await frames(4);
      tester.view.physicalSize = const Size(400, 860);
    }
    CardScanFlow.debugCapture = null;
    CardOcr.debugRead = null;
  });
}
