// Manual tool: screenshots of the R50 journey pages (SHOTS_DIR=… flutter test test_live/r50_shots_test.dart)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/fast_take_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/services/shutter_sound.dart';
import 'package:nextx_mobile/widgets/shutter_sound_picker.dart';
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

class _Mem extends XFile {
  _Mem() : super('x.jpg');
  @override
  Future<Uint8List> readAsBytes() async => Uint8List(0);
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
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      ServiceJourney.debugClear();
      ShutterSound.debugOnPlay = (_) {};
      final adapter = FakeNextxAdapter({
        'GET /api/settings/job': {'config': {}},
        'GET /api/tags': {'list': []},
        'GET /api/users': {
          'list': [
            {'user_id': 2, 'display_name': '[QA] Second'},
            {'user_id': 5, 'display_name': '[QA] ช่างเอ'},
          ],
        },
        for (final m in ['job', 'quotation']) ...{
          'GET /api/entity/$m/9/comments': {'list': []},
          'GET /api/entity/$m/9/tags': {'list': []},
          'GET /api/fields/$m': {'list': [], 'picklists': {}},
        },
        'GET /api/entity/job/9': {
          'id': 9,
          'job_no': 'JOB26111100001',
          'job_name': '[QA] ติดตั้งแอร์ 3 เครื่อง',
          'job_status': 'In Progress',
          'smownerid': 2,
          'smownerid_name': '[QA] Second',
          'account_name': 'บริษัท [QA] จำกัด',
          'account_id': 31,
          'plan_start': '2026-11-12T09:00:00',
          'evidence_photos': [],
        },
        'GET /api/field-service/jobs/9/overview': {
          'job_status': 'In Progress',
          'has_owner': true,
          'can_close': true,
          'activities': {'total': 2, 'open': 0, 'done': 2, 'next_at': null},
          'signatures': {'total': 2, 'signed': 1},
          'parts': 1,
          'quotation': {'id': 7, 'quotation_no': 'Q26111100001', 'title_th': 'ติดตั้งแอร์', 'outcome_result': 'Won', 'po_reference': 'PO-8891'},
        },
        'GET /api/field-service/jobs/9/signatures': {
          'slots': [
            {'slot_key': 'tech', 'position_th': 'ช่างผู้ปฏิบัติงาน', 'signer_role': 'staff', 'signature_path': 'x.png', 'signer_name': '[QA] Second', 'signed_at': '2026-11-11T10:20:00'},
            {'slot_key': 'customer', 'position_th': 'ลูกค้าผู้ตรวจรับ', 'signer_role': 'customer', 'signature_path': null},
          ],
        },
        'GET /api/links/job/9': {
          'activities': [
            {'id': 3, 'title': '[QA] เข้าหน้างาน', 'subtitle': '12/11 09:00', 'status': 'Done'},
          ],
        },
        'GET /api/field-service/jobs/9/close-preview': {'can_close': true, 'open_activities': 0},
        'GET /api/entity/quotation/9': {
          'id': 9,
          'quotation_no': 'Q26111100002',
          'title_th': '[QA] ติดตั้งระบบกล้อง',
          'quotation_status': 'อนุมัติใบเสนอราคา',
          'approval_state': 'approved',
          'offer_status': 'รอเปรียบเทียบ',
          'grand_total': 128400,
          'discount_total': 2600,
          'valid_until': '2026-11-16',
          'public_token': 'x',
        },
        'GET /api/quotation/9/approval-history': {'state': 'approved', 'current': 2, 'total': 2, 'steps': []},
        'GET /api/quotation/9/revisions': {
          'list': [
            {'id': 8, 'quotation_no': 'Q26111100002'},
            {'id': 9, 'quotation_no': 'Q26111100002-R1', 'is_current': true},
          ],
        },
        'GET /api/quotation/9/customer-activity': {'link_sent': true, 'viewed_at': '2026-11-11T08:12:00', 'view_count': 3},
        'GET /api/quotation/9/lines': {'list': [{'id': 1}]},
        'GET /api/settings/quotation': {'config': {'approval': {'required': true, 'levels': []}}},
        'GET /api/links/quotation/9': {
          'activities': [
            {'id': 4, 'title': '[QA] โทรติดตามราคา', 'subtitle': '13/11 14:00', 'status': 'Planned'},
          ],
        },
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(
        accessToken: 't',
        userId: '2',
        businessId: '1',
        displayName: '[QA] Second',
        businessRole: 'admin',
        menusLoaded: true,
        menuKeys: ['job', 'quotation', 'activity', 'inspection'],
      ));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(400, 2000);
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
          File('$_out/r50_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: MaterialApp(key: UniqueKey(), theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home),
            ),
          );

      await tester.pumpWidget(app(EntityDetailScreen(key: UniqueKey(), module: 'job', row: const {'id': 9})));
      await frames(24);
      await shot('job_summary');
      await tester.tap(find.byKey(const ValueKey('next-action-open_signatures')));
      await frames(10);
      await shot('job_signatures');
      await tester.tap(find.byKey(const ValueKey('jstep-Completed')));
      await frames(14);
      await shot('job_close');

      await tester.pumpWidget(app(EntityDetailScreen(key: UniqueKey(), module: 'quotation', row: const {'id': 9})));
      await frames(24);
      await shot('qt_summary');
      await tester.tap(find.byKey(const ValueKey('next-secondary-close_sale')));
      await frames(10);
      await tester.tap(find.byKey(const ValueKey('outcome-Won')));
      await frames(6);
      await shot('qt_outcome');

      tester.view.physicalSize = const Size(400, 860);
      debugFastTakeCapture = () async => _Mem();
      await tester.pumpWidget(app(const FastTakeScreen(onShot: _ignore)));
      await frames(6);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('fast-take-shutter')));
        await frames(2);
      }
      await frames(6);
      await shot('fast_take');
      debugFastTakeCapture = null;

      await tester.pumpWidget(app(Builder(builder: (context) {
        return Scaffold(body: Center(child: TextButton(onPressed: () => showShutterSoundPicker(context), child: const Text('open'))));
      })));
      await frames(4);
      await tester.tap(find.text('open'));
      await frames(10);
      await shot('shutter_picker');
    });
  }
}

void _ignore(XFile _) {}
