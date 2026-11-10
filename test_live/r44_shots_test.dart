// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Screenshots of the R44 convert / visit / photo mode (manual): SHOTS_DIR=… flutter test test_live/r44_shots_test.dart
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
import 'package:nextx_mobile/screens/crm/lead_convert_sheet.dart';
import 'package:nextx_mobile/screens/calendar/activity_detail_screen.dart';
import 'package:nextx_mobile/screens/calendar/visit_photo_flow.dart';
import 'package:nextx_mobile/services/geo_address.dart';

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
    GeoAddress.debugLookup = (lat, lng) async => 'ลุมพินี ทาวเวอร์\n1168/111 ถนนพระรามที่ 4\nทุ่งมหาเมฆ สาทร';
    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final adapter = FakeNextxAdapter({
        'GET /api/entity/lead/9/convert/preview': {
          'lead_id': 9, 'lead_name': '[QA] บริษัท ทดสอบ R44 จำกัด', 'lead_status': 'Qualified', 'smownerid': 2, 'owner_label': '[QA] Second',
          'already_converted': false,
          'settings': {'contact_enabled': true, 'contact_mode': 'optional', 'account_enabled': true, 'account_mode': 'optional'},
          'can_convert_contact': true, 'can_convert_account': true,
          'form_defaults': {'account_name': '[QA] บริษัท ทดสอบ R44 จำกัด', 'contact_firstname': '[QA] สมชาย', 'contact_lastname': 'ทดสอบ', 'account_owner_id': 2, 'contact_owner_id': 2},
          'duplicates': {'contacts': [], 'accounts': [{'id': 44, 'name': '[QA] บริษัท ทดสอบ (เดิม)'}]},
        },
        'GET /api/users': {'list': [{'id': 2, 'first_name': '[QA]', 'last_name': 'Second'}]},
        'GET /api/entity/activity/7': {'id': 7, 'subject': '[QA] ทดสอบเข้าพบ', 'activitytype': 'Visit', 'date_start': '2026-11-09T23:30:00.000Z', 'date_end': '2026-11-10T00:30:00.000Z', 'attendees': [{'kind': 'user', 'user_id': 2, 'response': 'accepted'}]},
        'GET /api/entity/activity/7/comments': {'list': []},
        'GET /api/activity/7/visit': {'checked_in': true, 'checkindate': '2026-11-09T23:55:00.000Z', 'checkin_lat': 13.7133845, 'checkin_lng': 100.7407911, 'photos': []},
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'calendar']));
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
          final img = await ro.toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/r44_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(
              key: const ValueKey('shot'),
              child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home),
            ),
          );

      // Convert sheet.
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => showLeadConvertSheet(context, leadId: '9'), child: const Text('go')))),
      )));
      await frames();
      await tester.tap(find.text('go'));
      await frames(20);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('convert-account')), matching: find.byType(Switch)));
      await frames();
      await shot('convert');
      await tester.pumpWidget(const SizedBox());
      await frames(4);

      // Activity: check-in 23:55, RSVP selected, then the place panel and photo-mode sheet.
      tester.view.physicalSize = const Size(400, 1300);
      await tester.pumpWidget(app(const ActivityDetailScreen(row: {'id': 7})));
      await frames(20);
      await shot('activity');
      await tester.tap(find.byKey(const ValueKey('visit-step-in')));
      await frames(20);
      await shot('place');
      await tester.pumpWidget(const SizedBox());
      await frames(4);
      tester.view.physicalSize = const Size(400, 860);
      await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => askPhotoTagMode(context, source: PhotoSource.gallery, count: 8), child: const Text('go')))),
      )));
      await frames();
      await tester.tap(find.text('go'));
      await frames(20);
      await shot('photo_mode');
      await tester.pumpWidget(const SizedBox());
      await frames(4);
    }
    GeoAddress.debugLookup = null;
  });
}
