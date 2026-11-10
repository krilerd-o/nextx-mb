// Manual tool (not part of `flutter test`): R44 against a local NEXTX
// backend (nextx_qa) with [QA] records this test creates.
// QA_TOKEN_FILE=… flutter test test_live/r44_live_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/photo_watermark.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  setUpAll(() async {
    await _font('GoogleSans', ['assets/fonts/GoogleSans-Regular.ttf', 'assets/fonts/GoogleSans-SemiBold.ttf']);
    await _font('IBMPlexSansThai', ['assets/fonts/IBMPlexSansThai-Regular.ttf', 'assets/fonts/IBMPlexSansThai-SemiBold.ttf']);
  });

  testWidgets('convert [QA] lead, RSVP, check-in time, watermarked photo upload', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
      final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final cleanup = <(String, String)>[];
      try {
        // 1. Convert a new [QA] lead with the same body the sheet builds.
        final lead = await api.postEntity('lead', {
          'lead_name': '[QA] R44 แปลง $stamp',
          'lead_firstname': '[QA] R44',
          'lead_lastname': 'แปลง',
          'lead_status': 'Qualified',
        });
        final leadId = '${lead['id']}';
        cleanup.add(('lead', leadId));
        final p = await api.previewLeadConvert(leadId);
        print('[convert] settings=${p['settings']} defaults=${p['form_defaults']}');
        expect(p['already_converted'], isFalse);
        final d = Map<String, dynamic>.from(p['form_defaults'] as Map);
        final r = await api.convertLead(leadId, {
          'create_contact': true,
          'create_account': true,
          'create_deal': true,
          'account_name': d['account_name'],
          'contact_firstname': d['contact_firstname'],
          'contact_lastname': d['contact_lastname'],
          'account_owner_id': d['account_owner_id'],
          'contact_owner_id': d['contact_owner_id'],
          'deal_name': d['account_name'],
          'copy_history': true,
        });
        print('[convert] result=$r');
        for (final m in ['account', 'contact', 'deal']) {
          final id = '${r['${m}_id'] ?? ''}';
          expect(id, isNot(anyOf('', 'null')), reason: m);
          cleanup.add((m, id));
          final row = await api.getEntity(m, id);
          expect(row, isNotEmpty, reason: '$m exists');
        }
        final after = await api.previewLeadConvert(leadId);
        expect(after['already_converted'], isTrue);

        // 2. Activity: RSVP + check-in time is Bangkok wall clock.
        final now = thaiNow();
        String two(int n) => n.toString().padLeft(2, '0');
        final start = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:00:00';
        final act = await api.postEntity('activity', {
          'subject': '[QA] R44 เข้าพบ $stamp',
          'activitytype': 'Visit',
          'date_start': start,
          'date_end': start,
          'smownerid': 2,
        });
        final actId = '${act['id']}';
        cleanup.add(('activity', actId));
        final rs = await api.activityRsvp(actId, 'accepted');
        expect(rs['response'], 'accepted');
        final row = await api.getEntity('activity', actId);
        final mine = (row['attendees'] as List).cast<Map>().where((g) => '${g['user_id']}' == '2').toList();
        print('[rsvp] attendees=${row['attendees']}');
        expect(mine.single['response'], 'accepted');

        try {
          await api.activityCheckin(actId, lat: 13.7133845, lng: 100.7407911);
          final visit = await api.getActivityVisit(actId);
          final at = parseThaiField(visit['checkindate'], 'checkindate')!;
          print('[checkin] raw=${visit['checkindate']} shown=$at thaiNow=${thaiNow()}');
          expect(at.difference(thaiNow()).inMinutes.abs(), lessThan(3));
        } catch (e) {
          print('[checkin] skipped: $e');
          rethrow;
        }

        // 3. Watermarked photo upload.
        final src = img.Image(width: 1200, height: 900);
        img.fill(src, color: img.ColorRgb8(90, 120, 150));
        final jpg = await watermarkPhoto(
          Uint8List.fromList(img.encodeJpg(src)),
          WatermarkInfo(at: thaiNow(), lat: 13.7133845, lng: 100.7407911, address: '[QA] ลุมพินี ทาวเวอร์\n1168/111 ถนนพระรามที่ 4\nทุ่งมหาเมฆ สาทร'),
        );
        final up = await api.uploadActivityPhotos(actId, [MultipartFile.fromBytes(jpg, filename: 'r44_qa.jpg')]);
        print('[photo] uploaded $up (${jpg.length} bytes)');
        final visit2 = await api.getActivityVisit(actId);
        expect(extractMapList(visit2['photos']), isNotEmpty);
        File('${Platform.environment['SHOTS_DIR'] ?? '/tmp'}/r44_watermark_live.jpg').writeAsBytesSync(jpg);
      } finally {
        for (final (m, id) in cleanup.reversed) {
          try {
            await api.deleteEntity(m, id);
            print('deleted $m/$id');
          } catch (e) {
            print('delete $m/$id failed: $e');
          }
        }
      }
    });
  });
}
