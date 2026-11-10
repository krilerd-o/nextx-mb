import 'dart:typed_data';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/calendar/activity_detail_screen.dart';
import 'package:nextx_mobile/screens/calendar/visit_photo_flow.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/lead_convert_sheet.dart';
import 'package:nextx_mobile/services/geo_address.dart';
import 'package:nextx_mobile/services/photo_watermark.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(FakeNextxAdapter, AppConfig)> _pump(WidgetTester tester, Widget home, Map<String, Object?> replies, {Size size = const Size(420, 1600)}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final adapter = FakeNextxAdapter(replies);
  final config = AppConfig();
  // Let AppConfig finish loading storage first, so it can't overwrite the test session.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'calendar']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: Scaffold(body: home))));
  await _frames(tester);
  return (adapter, config);
}

Map<String, Object?> _preview({String contactMode = 'optional', String accountMode = 'optional', bool converted = false, bool dup = false}) => {
      'lead_id': 9,
      'lead_name': '[QA] R44 บริษัททดสอบ',
      'lead_status': 'Qualified',
      'smownerid': 2,
      'owner_label': '[QA] Second',
      'already_converted': converted,
      'settings': {'contact_enabled': true, 'contact_mode': contactMode, 'account_enabled': true, 'account_mode': accountMode},
      'can_convert_contact': true,
      'can_convert_account': true,
      'form_defaults': {
        'account_name': '[QA] R44 บริษัททดสอบ',
        'contact_firstname': '[QA] สมชาย',
        'contact_lastname': 'ทดสอบ',
        'account_owner_id': 2,
        'contact_owner_id': 2,
      },
      'duplicates': {
        'contacts': [],
        'accounts': [
          if (dup) {'id': 44, 'name': '[QA] บริษัทเดิม'},
        ],
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lead convert', () {
    testWidgets('optional settings: contact on, account off; turning account on sends the web body', (tester) async {
      final (adapter, _) = await _pump(tester, const LeadConvertBody(leadId: '9'), {
        'GET /api/entity/lead/9/convert/preview': _preview(),
        'GET /api/users': {'list': [{'id': 2, 'first_name': '[QA]', 'last_name': 'Second'}]},
        'POST /api/entity/lead/9/convert': {'account_id': 31, 'contact_id': 32, 'deal_id': 33},
      });
      expect(find.byKey(const ValueKey('convert-lead-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('convert-account')), findsOneWidget);
      expect(find.byKey(const ValueKey('convert-contact')), findsOneWidget);
      // Account section is off until switched on.
      expect(find.byKey(const ValueKey('convert-account-name')), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('convert-account')), matching: find.byType(Switch)));
      await _frames(tester);
      expect(find.byKey(const ValueKey('convert-account-name')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('convert-submit')));
      await tester.tap(find.byKey(const ValueKey('convert-submit')));
      await _frames(tester);
      final post = adapter.calls.lastWhere((c) => c.method == 'POST' && c.path == '/api/entity/lead/9/convert');
      final body = Map<String, dynamic>.from(post.data as Map);
      expect(body['create_contact'], isTrue);
      expect(body['create_account'], isTrue);
      expect(body['create_deal'], isTrue);
      expect(body['copy_history'], isTrue);
      expect(body['account_name'], '[QA] R44 บริษัททดสอบ');
      expect(body['contact_firstname'], '[QA] สมชาย');
      expect(body['account_owner_id'], 2);
      // Success page links to what was created.
      expect(find.byKey(const ValueKey('convert-success')), findsOneWidget);
      for (final m in ['account', 'contact', 'deal']) {
        expect(find.byKey(ValueKey('convert-open-$m')), findsOneWidget);
      }
    });

    testWidgets('always: shows "สร้างเสมอ", no switch; deal off is sent', (tester) async {
      final (adapter, _) = await _pump(tester, const LeadConvertBody(leadId: '9'), {
        'GET /api/entity/lead/9/convert/preview': _preview(contactMode: 'always', accountMode: 'always'),
        'GET /api/users': {'list': []},
        'POST /api/entity/lead/9/convert': {'account_id': 31, 'contact_id': 32},
      });
      expect(find.text('สร้างเสมอ'), findsNWidgets(2));
      expect(find.text('สร้าง Account ใหม่'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('convert-deal')));
      await tester.tap(find.byKey(const ValueKey('convert-deal')));
      await _frames(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('convert-submit')));
      await tester.tap(find.byKey(const ValueKey('convert-submit')));
      await _frames(tester);
      final body = Map<String, dynamic>.from(adapter.calls.lastWhere((c) => c.method == 'POST').data as Map);
      expect(body['create_account'], isTrue);
      expect(body['create_contact'], isTrue);
      expect(body['create_deal'], isFalse);
      expect(find.byKey(const ValueKey('convert-open-deal')), findsNothing);
    });

    testWidgets('duplicates: tap to link the existing account', (tester) async {
      final (adapter, _) = await _pump(tester, const LeadConvertBody(leadId: '9'), {
        'GET /api/entity/lead/9/convert/preview': _preview(dup: true),
        'GET /api/users': {'list': []},
        'POST /api/entity/lead/9/convert': {'account_id': 44, 'contact_id': 32},
      });
      expect(find.byKey(const ValueKey('convert-duplicates')), findsOneWidget);
      await tester.tap(find.text('[QA] บริษัทเดิม'));
      await _frames(tester);
      expect(find.text('ใช้ของเดิม: [QA] บริษัทเดิม'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('convert-submit')));
      await tester.tap(find.byKey(const ValueKey('convert-submit')));
      await _frames(tester);
      final body = Map<String, dynamic>.from(adapter.calls.lastWhere((c) => c.method == 'POST').data as Map);
      expect(body['existing_account_id'], 44);
      expect(body['create_account'], isTrue);
    });

    testWidgets('already converted: notice and no submit', (tester) async {
      await _pump(tester, const LeadConvertBody(leadId: '9'), {
        'GET /api/entity/lead/9/convert/preview': _preview(converted: true),
        'GET /api/users': {'list': []},
      });
      expect(find.byKey(const ValueKey('convert-already')), findsOneWidget);
      expect(find.byKey(const ValueKey('convert-submit')), findsNothing);
    });

    testWidgets('lead detail shows the convert button; converted lead does not', (tester) async {
      final common = <String, Object?>{
        'GET /api/entity/lead/9/comments': {'list': []},
        'GET /api/entity/lead/9/tags': {'list': []},
        'GET /api/tags': {'list': []},
        'GET /api/fields/lead': {'list': [{'name': 'lead_name', 'label_th': 'ชื่อ'}], 'picklists': {}},
        'GET /api/users': {'list': []},
      };
      await _pump(tester, const EntityDetailScreen(module: 'lead', row: {'id': 9}), {
        ...common,
        'GET /api/entity/lead/9': {'id': 9, 'lead_name': '[QA] R44', 'lead_status': 'Qualified'},
      });
      expect(find.byKey(const ValueKey('lead-convert-cta')), findsOneWidget);
      await _pump(tester, const EntityDetailScreen(key: ValueKey('converted'), module: 'lead', row: {'id': 9}), {
        ...common,
        'GET /api/entity/lead/9': {'id': 9, 'lead_name': '[QA] R44', 'lead_status': 'Converted', 'convert_account_id': 31},
      });
      expect(find.byKey(const ValueKey('lead-convert-cta')), findsNothing);
    });
  });

  group('Activity visit', () {
    Map<String, Object?> replies({Map<String, Object?> visit = const {}, List attendees = const []}) => {
          'GET /api/entity/activity/7': {'id': 7, 'subject': '[QA] ทดสอบเข้าพบ', 'attendees': attendees},
          'GET /api/entity/activity/7/comments': {'list': []},
          'GET /api/activity/7/visit': {'checked_in': false, ...visit},
          'POST /api/activity/7/rsvp': {'response': 'accepted'},
        };

    test('check-in / check-out stamps are Bangkok wall clock (like the web)', () {
      expect(isWallClockField('checkindate'), isTrue);
      expect(isWallClockField('checkoutdate'), isTrue);
      final d = parseThaiField('2026-11-09T23:55:00.000Z', 'checkindate')!;
      expect((d.day, d.hour, d.minute), (9, 23, 55));
    });

    testWidgets('check-in time shows 23:55 (not 06:55) and tapping it opens the place panel', (tester) async {
      GeoAddress.debugLookup = (lat, lng) async => 'Lumpini Tower\nThung Maha Mek';
      addTearDown(() => GeoAddress.debugLookup = null);
      await _pump(tester, const ActivityDetailScreen(row: {'id': 7}), replies(visit: {
        'checked_in': true,
        'checkindate': '2026-11-09T23:55:00.000Z',
        'checkin_lat': 13.7133845,
        'checkin_lng': 100.7407911,
      }));
      final step = find.byKey(const ValueKey('visit-step-in'));
      expect(find.descendant(of: step, matching: find.textContaining('23:55')), findsOneWidget);
      expect(find.descendant(of: step, matching: find.textContaining('06:55')), findsNothing);
      await tester.tap(step);
      await _frames(tester, 16);
      expect(find.text('13.713385, 100.740791'), findsWidgets);
      expect(find.textContaining('Lumpini Tower'), findsOneWidget);
      expect(find.byKey(const ValueKey('place-maps')), findsOneWidget);
    });

    testWidgets('RSVP shows my current answer and switches at once', (tester) async {
      final (adapter, _) = await _pump(tester, const ActivityDetailScreen(row: {'id': 7}), replies(attendees: [
        {'kind': 'user', 'user_id': 2, 'response': 'tentative'},
      ]));
      await tester.ensureVisible(find.byKey(const ValueKey('rsvp-accepted')));
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('rsvp-tentative'))).selected, isTrue);
      expect(find.byKey(const ValueKey('rsvp-current')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rsvp-accepted')));
      await _frames(tester);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('rsvp-accepted'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('rsvp-tentative'))).selected, isFalse);
      final post = adapter.calls.lastWhere((c) => c.path == '/api/activity/7/rsvp');
      expect(post.data, {'response': 'accepted'});
      expect(find.text('ตอบรับนัด: เข้าร่วม'), findsOneWidget);
    });
  });

  group('Photos', () {
    test('uploads in batches of 5 and keeps a failed batch for retry', () async {
      final sizes = <int>[];
      var call = 0;
      final flow = VisitPhotoFlow(upload: (files) async {
        call++;
        sizes.add(files.length);
        if (call == 2) throw StateError('4G drop');
      });
      final parts = [for (var i = 0; i < 12; i++) MultipartFile.fromBytes([1, 2, 3], filename: '$i.jpg')];
      await expectLater(flow.uploadBatches(parts), throwsA(isA<PhotoUploadIncomplete>()));
      expect(sizes, [5, 5, 2]);
      expect(flow.pending, hasLength(5));
      final n = await flow.retryPending();
      expect(n, 5);
      expect(flow.pending, isEmpty);
    });

    testWidgets('gallery: asks "with location / photo only", plain uploads as is', (tester) async {
      final uploaded = <List<MultipartFile>>[];
      late VisitPhotoFlow flow;

      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () {
                flow = VisitPhotoFlow(
                  upload: (f) async => uploaded.add(f),
                  pick: (_) async => [for (var i = 0; i < 3; i++) _MemFile(Uint8List.fromList([1, 2, 3, i]), 'g$i.jpg')],
                );
                flow.run(context, PhotoSource.gallery).catchError((Object e, StackTrace st) {
                  // ignore: avoid_print
                  print('RUN ERROR $e\n$st');
                  return 0;
                });
              },
              child: const Text('go'),
            ),
          ),
        ),
        {},
      );
      await tester.tap(find.text('go'));
      await _frames(tester);
      expect(find.byKey(const ValueKey('photo-mode-withLocation')), findsOneWidget);
      expect(find.text('อัปโหลดพร้อมพิกัด'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-mode-plain')));
      for (var i = 0; i < 4; i++) {
        await _frames(tester, 6);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      }
      await _frames(tester);
      expect(uploaded, hasLength(1));
      expect(uploaded.first.map((f) => f.filename), ['g0.jpg', 'g1.jpg', 'g2.jpg']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('nx_visit_photo_mode_v1'), 'plain');
    });

    testWidgets('watermark: JPEG of the same size with text bottom-right, rest untouched', (tester) async {
      final src = img.Image(width: 800, height: 600);
      img.fill(src, color: img.ColorRgb8(60, 90, 120));
      final png = Uint8List.fromList(img.encodePng(src));
      final out = await tester.runAsync(() => watermarkPhoto(
            png,
            WatermarkInfo(at: DateTime(2026, 11, 9, 23, 55, 12), lat: 13.713384513561897, lng: 100.74079119034677, address: 'Lumpini Tower\nThung Maha Mek'),
          ));
      final dec = img.decodeJpg(out!)!;
      expect((dec.width, dec.height), (800, 600));
      // Top-left keeps the photo colour.
      final tl = dec.getPixel(20, 20);
      expect((tl.r - 60).abs() < 12 && (tl.b - 120).abs() < 12, isTrue);
      // Bottom-right block has bright text pixels.
      var bright = 0;
      for (var y = 450; y < 590; y += 2) {
        for (var x = 400; x < 790; x += 2) {
          final p = dec.getPixel(x, y);
          if (p.r > 200 && p.g > 200 && p.b > 200) bright++;
        }
      }
      expect(bright, greaterThan(50));
      expect(WatermarkInfo(at: DateTime(2026, 11, 9, 23, 55, 12), lat: 1.5, lng: 2.25, address: 'A\nB').lines, ['9/11/2026    23:55:12', '1.5,2.25', 'A', 'B']);
    });
  });
}


/// In-memory picked file (no disk IO inside the widget test).
class _MemFile extends XFile {
  _MemFile(this._bytes, String path) : super(path);
  final Uint8List _bytes;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Future<DateTime> lastModified() async => DateTime.now();
}
