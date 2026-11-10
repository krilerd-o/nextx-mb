// Manual tool (not part of `flutter test`): business card scan against a local
// NEXTX backend (nextx_qa) — a [QA] card read through the phone-OCR path (no AI
// key locally), saved the way the form saves it, card photo attached, cleaned up.
// QA_TOKEN_FILE=… flutter test test_live/r46_card_live_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nextx_mobile/screens/crm/card_scan/card_scan_flow.dart';
import 'package:nextx_mobile/screens/crm/card_scan/card_scan_models.dart';
import 'package:nextx_mobile/services/api_client.dart';

void main() {
  test('[QA] card → contact fields → saved by the user → photo attached', () async {
    HttpOverrides.global = null;
    final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
    final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final card = img.Image(width: 900, height: 550);
    img.fill(card, color: img.ColorRgb8(250, 250, 250));
    final jpeg = Uint8List.fromList(img.encodeJpg(card));
    final ocr = '[QA] Card Test $stamp Co., Ltd.\n'
        'Mr. Qa Tester\n'
        'Sales Director\n'
        'Tel: 02-555-1234\n'
        'Mobile: 089-123-${(1000 + stamp % 9000)}\n'
        'Fax: 02-555-1235\n'
        'qa.card$stamp@example.com\n'
        'www.qa-card-test.co.th';

    final data = await api.scanBusinessCard('contact', front: jpeg, ocrText: ocr);
    final r = CardScanResult.from(data);
    print('[scan] status=${r.status} engine=${r.engine} fields=${{for (final f in r.fields) f.name: f.value}} extras=${r.extras.map((e) => '${e.kind}=${e.value}').toList()}');
    expect(r.status, 'ok');
    final v = {for (final f in r.fields) f.name: f.value};
    expect(v['contact_firstname'], 'Qa');
    expect(v['contact_lastname'], 'Tester');
    expect(v['position'], 'Sales Director');
    expect(v['contact_titlename'] ?? 'นาย', 'นาย');
    expect(v['email_1st'], 'qa.card$stamp@example.com');
    expect(v['contact_tel'], '025551234');
    expect(v['mobile_1st'], startsWith('089123'));
    expect(r.extras.any((e) => e.kind == 'fax' && e.value == '025551235'), isTrue);

    // The user saves the form (required fields the card doesn't have are filled by hand).
    final schema = await api.getFieldSchema('contact', fresh: true);
    final status = (schema.picklists['contact_status'] ?? const []).firstOrNull?['value'];
    final created = await api.postEntity('contact', {...v, 'contact_status': status ?? 'Active'});
    final id = '${created['id']}';
    print('[save] contact id=$id');
    try {
      final row = await api.getEntity('contact', id);
      expect(row['email_1st'], 'qa.card$stamp@example.com');
      expect('${row['contact_tel']}', '025551234');
      await CardScanFlow.attachToRecord(api, module: 'contact', id: id, images: CardImages(front: jpeg));
      final comments = await api.getEntityComments('contact', id);
      final att = comments.expand((c) => (c['attachments'] as List? ?? const [])).toList();
      print('[attach] comments=${comments.length} attachments=$att');
      expect(att, isNotEmpty);
    } finally {
      await api.deleteEntity('contact', id);
      print('deleted contact/$id');
    }
  });
}
