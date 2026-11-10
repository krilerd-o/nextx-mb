// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Screenshots of the CRM list long-press sheet (manual): SHOTS_DIR=… flutter test test_live/r43_shots_test.dart
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
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';

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
    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({'nx_crm_row_actions_hint_v1': true});
      FlutterSecureStorage.setMockInitialValues({});
      final rows = [
        {'id': 5, 'lead_no': 'LD-QA-0005', 'lead_name': '[QA] บริษัท ทดสอบ R43 จำกัด', 'lead_status': 'Contacted', 'mobile': '0812345678'},
        {'id': 6, 'lead_no': 'LD-QA-0006', 'lead_name': '[QA] คุณสมชาย ทดสอบ', 'lead_status': 'New'},
        {'id': 7, 'lead_no': 'LD-QA-0007', 'lead_name': '[QA] ร้านกาแฟตัวอย่าง', 'lead_status': 'Qualified'},
      ];
      final adapter = FakeNextxAdapter({
        'GET /api/modules': [],
        'GET /api/customviews': {'list': [], 'default_id': null},
        'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
        'GET /api/fields/lead': {
          'list': [
            {'name': 'lead_no', 'label_th': 'เลขที่'},
            {'name': 'lead_name', 'label_th': 'ชื่อ'},
            {'name': 'lead_status', 'label_th': 'สถานะ', 'uitype': '15'},
            {'name': 'mobile', 'label_th': 'มือถือ'},
          ],
          'picklists': {
            'lead_status': [
              {'value': 'New', 'label': 'ใหม่', 'color': '#64748B'},
              {'value': 'Contacted', 'label': 'ติดต่อแล้ว', 'color': '#F59E0B'},
              {'value': 'Qualified', 'label': 'ผ่านเกณฑ์', 'color': '#16A34A'},
              {'value': 'Unqualified', 'label': 'ไม่ผ่านเกณฑ์', 'color': '#EF4444'},
            ],
          },
        },
        'GET /api/entity/lead': {'list': rows, 'total': 3},
        'GET /api/entity/lead/5': rows.first,
        'GET /api/entity/lead/5/comments': {'list': [
          {'id': 1, 'user_name': '[QA] Second', 'body': 'โทรนัดเข้าพบแล้ว รอใบเสนอราคา', 'created_at': '2026-11-08T03:00:00Z'},
          {'id': 2, 'user_name': '[QA] Third', 'body': 'ส่งโบรชัวร์ทางอีเมลแล้ว', 'created_at': '2026-11-09T02:00:00Z'},
        ]},
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            debugShowCheckedModeBanner: false,
            home: const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง'),
          ),
        ),
      ));
      Future<void> frames([int n = 14]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      Future<void> shot(String name) async {
        final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        await tester.runAsync(() async {
          final img = await ro.toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/r43_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      await frames();
      await tester.longPress(find.textContaining('[QA] บริษัท ทดสอบ R43').first);
      await frames();
      await shot('sheet');
      await tester.tap(find.byKey(const ValueKey('row-act-status')));
      await frames();
      await shot('status');
      Navigator.of(tester.element(find.byKey(const ValueKey('status-opt-New'))), rootNavigator: true).pop();
      await frames();
      await tester.longPress(find.textContaining('[QA] บริษัท ทดสอบ R43').first);
      await frames();
      await tester.tap(find.byKey(const ValueKey('row-act-comment')));
      await frames(20);
      await shot('comment');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    }
  });
}
