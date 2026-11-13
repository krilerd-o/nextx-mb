import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/card_scan/card_ocr.dart';
import 'package:nextx_mobile/screens/crm/card_scan/card_scan_flow.dart';
import 'package:nextx_mobile/screens/crm/card_scan/card_scan_models.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/widgets/nx_create_fab.dart';

import 'support/fake_api.dart';

final _jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 160, height: 98)));

Map<String, Object?> _schema() => {
      'list': [
        {'name': 'lead_titlename', 'label_th': 'คำนำหน้า', 'uitype': 'Enum'},
        {'name': 'lead_firstname', 'label_th': 'ชื่อ', 'uitype': 'Text'},
        {'name': 'lead_lastname', 'label_th': 'นามสกุล', 'uitype': 'Text'},
        {'name': 'company_name', 'label_th': 'ชื่อบริษัท', 'uitype': 'Text'},
        {'name': 'position', 'label_th': 'ตำแหน่ง', 'uitype': 'Text'},
        {'name': 'mobile_1st', 'label_th': 'เบอร์ติดต่อ (หลัก)', 'uitype': 'Phone'},
        {'name': 'email_1st', 'label_th': 'อีเมล (หลัก)', 'uitype': 'Email'},
        {'name': 'description', 'label_th': 'รายละเอียด', 'uitype': 'LongText'},
      ],
      'picklists': {
        'lead_titlename': [
          {'value': 'นาย'},
          {'value': 'นาง'},
        ],
      },
    };

Map<String, Object?> _scan({String status = 'ok', String engine = 'gemini'}) => {
      'status': status,
      'engine': engine,
      'raw_text': 'บริษัท คิวเอ ทดสอบ จำกัด\nนายสมชาย ใจดี\nM: 081-234-5678\nsomchai@qa-test.co.th\nFax 02-123-4568',
      'fields': {
        'lead_titlename': {'value': 'นาย', 'label': 'คำนำหน้า', 'confidence': 'high'},
        'lead_firstname': {'value': '[QA] สมชาย', 'label': 'ชื่อ', 'confidence': 'high'},
        'lead_lastname': {'value': 'ใจดี', 'label': 'นามสกุล', 'confidence': 'high'},
        'company_name': {'value': 'บริษัท คิวเอ ทดสอบ จำกัด', 'label': 'ชื่อบริษัท', 'confidence': 'high'},
        'position': {'value': 'ผู้จัดการ', 'label': 'ตำแหน่ง', 'confidence': 'low'},
        'mobile_1st': {'value': '0812345678', 'label': 'เบอร์ติดต่อ (หลัก)', 'confidence': 'high'},
        'email_1st': {'value': 'somchai@qa-test.co.th', 'label': 'อีเมล (หลัก)', 'confidence': 'high'},
      },
      'unmapped': [
        {'kind': 'fax', 'value': '021234568', 'label': 'โทรสาร'},
      ],
      'duplicates': [
        {'module': 'lead', 'id': 7, 'name': '[QA] สมชาย เดิม', 'reason': 'อีเมล'},
      ],
    };

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget home, Map<String, Object?> extra) async {
  SharedPreferences.setMockInitialValues({'nx_crm_row_actions_hint_v1': true});
  FlutterSecureStorage.setMockInitialValues({});
  final adapter = FakeNextxAdapter({
    'GET /api/fields/lead': _schema(),
    'GET /api/fields/deal': {'list': [{'name': 'deal_name', 'label_th': 'ชื่อดีล'}], 'picklists': {}},
    'GET /api/modules': [],
    'GET /api/customviews': {'list': [], 'default_id': null},
    'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
    'GET /api/entity/lead': {'list': [], 'total': 0},
    'GET /api/entity/deal': {'list': [], 'total': 0},
    'GET /api/users': {'list': []},
    ...extra,
  });
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'deal']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
  await _frames(tester);
  return adapter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CardScanFlow.debugCapture = (_) async => CardImages(front: _jpeg);
    CardOcr.debugRead = (_) async => null;
  });
  tearDown(() {
    CardScanFlow.debugCapture = null;
    CardOcr.debugRead = null;
  });

  test('scan result parses fields, extras, duplicates', () {
    final r = CardScanResult.from(Map<String, dynamic>.from(_scan()));
    expect(r.fields, hasLength(7));
    expect(r.fields.firstWhere((f) => f.name == 'position').sure, isFalse);
    expect(r.extras.single.kind, 'fax');
    expect(r.duplicates.single.id, '7');
    expect(r.offline, isFalse);
    expect(CardScanResult.from({'status': 'ok', 'engine': 'device_ocr'}).offline, isTrue);
  });

  testWidgets('lead list: + opens "ใหม่ / สแกนนามบัตร"', (tester) async {
    await _pump(tester, const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง'), {});
    await tester.tap(find.byType(NxCreateFab));
    await _frames(tester);
    expect(find.byKey(const ValueKey('create-manual')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-scan')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-manual')));
    await _frames(tester, 20);
    expect(find.byType(EntityCreateScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('form-scan-banner')), findsOneWidget);
  });

  testWidgets('deal list: + opens the form directly (no card scan)', (tester) async {
    await _pump(tester, const EntityListScreen(module: 'deal', title: 'ดีล'), {});
    await tester.tap(find.byType(NxCreateFab));
    await _frames(tester, 20);
    expect(find.byKey(const ValueKey('create-scan')), findsNothing);
    expect(find.byType(EntityCreateScreen), findsOneWidget);
  });

  testWidgets('scan → review → "ใช้ข้อมูลนี้" fills the form only; save creates the record and attaches the card', (tester) async {
    final adapter = await _pump(tester, const EntityCreateScreen(module: 'lead', title: 'สร้างผู้มุ่งหวัง'), {
      'POST /api/crm/business-card/scan': _scan(),
      'POST /api/entity/lead': {'id': 77},
      'POST /api/files/upload': {
        'list': [
          {'storage_path': 'business/1/card.jpg', 'file_name': 'business_card_front.jpg', 'mime_type': 'image/jpeg'},
        ],
      },
      'POST /api/entity/lead/77/comments': {'id': 1},
    });
    await tester.tap(find.byKey(const ValueKey('form-scan-banner')));
    await _frames(tester, 30);
    expect(adapter.calls.any((c) => c.path == '/api/crm/business-card/scan'), isTrue);
    final scanCall = adapter.calls.firstWhere((c) => c.path == '/api/crm/business-card/scan');
    expect('${(scanCall.data as dynamic).fields}', contains('lead'));

    // Review screen.
    expect(find.text('ตรวจข้อมูลจากนามบัตร'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-duplicates')), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('card-keep-lead_firstname'))).value, isTrue);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('card-keep-position'))).value, isFalse, reason: 'unsure value starts unticked');
    expect(find.byKey(const ValueKey('card-extra-fax')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('card-extra-fax')));
    await _frames(tester, 4);
    await tester.tap(find.byKey(const ValueKey('card-apply')));
    await _frames(tester, 20);

    // Back on the form: values in, nothing saved yet.
    expect(find.byKey(const ValueKey('form-scanned')), findsOneWidget);
    expect(find.text('[QA] สมชาย'), findsWidgets);
    expect(find.text('somchai@qa-test.co.th'), findsWidgets);
    expect(adapter.calls.where((c) => c.method == 'POST' && c.path == '/api/entity/lead'), isEmpty);

    // The user saves.
    await tester.ensureVisible(find.byKey(const ValueKey('entity-save')));
    await tester.tap(find.byKey(const ValueKey('entity-save')));
    await _frames(tester, 30);
    final post = adapter.calls.firstWhere((c) => c.method == 'POST' && c.path == '/api/entity/lead');
    final body = Map<String, dynamic>.from(post.data as Map);
    expect(body['lead_firstname'], '[QA] สมชาย');
    expect(body['mobile_1st'], '0812345678');
    expect(body['lead_titlename'], 'นาย');
    expect(body.containsKey('position'), isFalse, reason: 'unticked value not used');
    expect('${body['description']}', contains('021234568'), reason: 'fax kept in รายละเอียด');
    expect(adapter.callKeys, contains('POST /api/files/upload'));
    expect(adapter.callKeys, contains('POST /api/entity/lead/77/comments'));
  });

  testWidgets('edit: a field that already has a value is not overwritten unless ticked', (tester) async {
    await _pump(
      tester,
      const EntityCreateScreen(module: 'lead', title: 'แก้ไข', recordId: '5', initialValues: {'lead_firstname': 'ชื่อเดิม', 'email_1st': ''}),
      {'POST /api/crm/business-card/scan': _scan()},
    );
    expect(find.byKey(const ValueKey('form-scan-banner')), findsNothing, reason: 'no banner when editing');
    await tester.tap(find.byTooltip('สแกนนามบัตร'));
    await _frames(tester, 30);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('card-keep-lead_firstname'))).value, isFalse);
    expect(find.text('ค่าเดิมในฟอร์ม: ชื่อเดิม'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('card-keep-email_1st'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('card-apply')));
    await _frames(tester, 20);
    expect(find.text('ชื่อเดิม'), findsWidgets);
    expect(find.text('somchai@qa-test.co.th'), findsWidgets);
  });

  testWidgets('no AI and no phone OCR → clear message, form untouched', (tester) async {
    final adapter = await _pump(tester, const EntityCreateScreen(module: 'lead', title: 'สร้างผู้มุ่งหวัง'), {
      'POST /api/crm/business-card/scan': {'status': 'no_ai', 'engine': 'none', 'fields': {}, 'unmapped': [], 'duplicates': []},
    });
    await tester.tap(find.byKey(const ValueKey('form-scan-banner')));
    await _frames(tester, 30);
    expect(find.text('สแกนนามบัตรไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('ยังไม่ได้ตั้งค่า AI'), findsOneWidget);
    await tester.tap(find.text('ตกลง'));
    await _frames(tester);
    expect(find.byKey(const ValueKey('form-scanned')), findsNothing);
    expect(adapter.calls.where((c) => c.method == 'POST' && c.path == '/api/entity/lead'), isEmpty);
  });

  testWidgets('fast path: photo goes first; phone OCR only after "no_ai", then just its text', (tester) async {
    var ocrRuns = 0;
    CardOcr.debugRead = (_) async {
      ocrRuns++;
      return 'ACME Co., Ltd.\nJohn Smith';
    };
    final adapter = await _pump(tester, const EntityCreateScreen(module: 'lead', title: 'สร้างผู้มุ่งหวัง'), {});
    final queue = [
      {'status': 'no_ai', 'engine': 'none', 'fields': {}, 'unmapped': [], 'duplicates': []},
      _scan(engine: 'device_ocr'),
    ];
    adapter.onRequest = (o) {
      if (o.path == '/api/crm/business-card/scan' && queue.isNotEmpty) adapter.replies['POST /api/crm/business-card/scan'] = queue.removeAt(0);
    };
    await tester.tap(find.byKey(const ValueKey('form-scan-banner')));
    await _frames(tester, 40);
    final calls = adapter.calls.where((c) => c.path == '/api/crm/business-card/scan').toList();
    expect(calls, hasLength(2));
    expect((calls[0].data as dynamic).files.length, 1, reason: 'first call: the photo, no OCR text');
    expect('${(calls[0].data as dynamic).fields}', isNot(contains('John Smith')));
    expect((calls[1].data as dynamic).files.length, 0, reason: 'second call: text only, no re-upload');
    expect('${(calls[1].data as dynamic).fields}', contains('John Smith'));
    expect(ocrRuns, 1);
    expect(find.textContaining('อ่านด้วยเครื่อง'), findsOneWidget);
  });

  testWidgets('AI path: OCR never runs; Isaac shows time, model and notes', (tester) async {
    var ocrRuns = 0;
    CardOcr.debugRead = (_) async {
      ocrRuns++;
      return null;
    };
    final adapter = await _pump(tester, const EntityCreateScreen(module: 'lead', title: 'สร้างผู้มุ่งหวัง'), {
      'POST /api/crm/business-card/scan': {
        ..._scan(),
        'isaac': {'provider': 'gemini', 'model': 'gemini-3.8-flash', 'ms': 1840},
        'timing_ms': 1950,
        'insights': [
          {'type': 'duplicate', 'level': 'warn', 'text': 'พบรายการที่อาจซ้ำ 1 รายการ — ตรวจก่อนสร้างใหม่'},
          {'type': 'domain_match', 'level': 'ok', 'text': 'อีเมลกับเว็บไซต์เป็นโดเมนเดียวกัน — ข้อมูลบริษัทน่าเชื่อถือ'},
        ],
      },
    });
    await tester.tap(find.byKey(const ValueKey('form-scan-banner')));
    await _frames(tester, 6);
    expect(find.byKey(const ValueKey('card-reading')), findsOneWidget);
    expect(find.text('ไอแซคกำลังอ่านนามบัตร…'), findsOneWidget);
    await _frames(tester, 40);
    expect(ocrRuns, 0);
    expect(adapter.calls.where((c) => c.path == '/api/crm/business-card/scan'), hasLength(1));
    expect(find.byKey(const ValueKey('card-isaac')), findsOneWidget);
    expect(find.text('ไอแซคอ่านได้ 7 ช่องใน 1.8 วินาที'), findsOneWidget);
    expect(find.text('gemini-3.8-flash'), findsOneWidget);
    expect(find.textContaining('โดเมนเดียวกัน'), findsOneWidget);
  });

  testWidgets('opened from "สแกนนามบัตร": the scan starts by itself', (tester) async {
    final adapter = await _pump(tester, const EntityCreateScreen(module: 'lead', title: 'สร้างผู้มุ่งหวัง', autoScan: true), {
      'POST /api/crm/business-card/scan': _scan(),
    });
    await _frames(tester, 30);
    expect(adapter.calls.any((c) => c.path == '/api/crm/business-card/scan'), isTrue);
    expect(find.text('ตรวจข้อมูลจากนามบัตร'), findsOneWidget);
  });
}
