import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/docs/doc_email_sheet.dart';
import 'package:nextx_mobile/screens/docs/document_preview.dart';
import 'package:nextx_mobile/screens/docs/document_tab.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';
import 'package:nextx_mobile/widgets/nx_rich_text_editor.dart';

import 'support/fake_api.dart';

Uint8List pdf(String tag) => Uint8List.fromList(utf8.encode('%PDF-1.4 $tag'));

/// What the backend's compose-defaults answers (shape of quotationComposeService / jobComposeService).
Map<String, Object?> defaults({bool ready = true, String kind = 'quotation'}) => {
  kind == 'job' ? 'job' : 'quotation': {'id': 7, kind == 'job' ? 'job_no' : 'quotation_no': kind == 'job' ? 'JOB-5' : 'QT-7', 'customer': 'บริษัท ลูกค้า'},
  'to': ['buyer@cust.test'],
  'cc': ['owner@biz.test'],
  'bcc': <String>[],
  'template_id': 'default',
  'subject': kind == 'job' ? 'ใบสั่งงาน_JOB-5_บริษัท ลูกค้า_261113' : 'ใบเสนอราคา_QT-7_บริษัท ลูกค้า_261113',
  'body_html': '<p>เรียน คุณลูกค้า</p><p>ขอส่งเอกสารเลขที่ <strong>QT-7</strong> ตามไฟล์แนบ</p><p>ขอแสดงความนับถือ<br>สมชาย</p>',
  'templates': [
    {'id': 'default', 'name': 'มาตรฐาน', 'is_default': true, 'subject': 'S1', 'body_html': '<p>B1</p>'},
  ],
  'attach_pdf': true,
  'include_link': false,
  'attachment': {'name': kind == 'job' ? 'ใบสั่งงาน_JOB-5.pdf' : 'ใบเสนอราคา_QT-7.pdf', 'kind': 'pdf'},
  'suggestions': [
    {'email': 'buyer@cust.test', 'label': 'คุณลูกค้า', 'source': 'contact'},
    {'email': 'owner@biz.test', 'label': 'สมชาย', 'source': 'owner'},
    {'email': 'somsri@biz.test', 'label': 'สมศรี ทดสอบ', 'source': 'user'},
  ],
  'limits': {'maxFiles': 10, 'maxFileMb': 15},
  'mail_ready': ready,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> rendered, saved, printed, shared;

  setUp(() {
    rendered = [];
    saved = [];
    printed = [];
    shared = [];
    RecordDocumentTab.clearCache();
    DocPreviewHooks.render = (bytes, dpi) async* {
      rendered.add(utf8.decode(bytes));
      for (var i = 0; i < 2; i++) {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 60, 85), Paint()..color = const Color(0xFFFFFFFF));
        yield await rec.endRecording().toImage(60, 85);
      }
    };
    DocPreviewHooks.save = (b, name) async {
      saved.add('$name:${utf8.decode(b)}');
      return '/storage/$name';
    };
    DocPreviewHooks.print = (b, name) async => printed.add(name);
    DocPreviewHooks.share = (b, name) async => shared.add(name);
    DocEmailHooks.pickFiles = null;
  });
  tearDown(() {
    DocPreviewHooks.render = null;
    DocPreviewHooks.save = null;
    DocPreviewHooks.print = null;
    DocPreviewHooks.share = null;
    DocEmailHooks.pickFiles = null;
  });

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<FakeNextxAdapter> pump(
    WidgetTester tester,
    Widget home,
    Map<String, Object?> replies, {
    Map<String, int> status = const {},
    Map<String, Map<String, Object?>>? errors,
    List<String> menus = const ['job', 'quotation'],
    Size size = const Size(420, 1600),
  }) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter(replies, statusFor: status, errorsFor: errors);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: menus));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: Scaffold(body: home))));
    await settle(tester, 8);
    return adapter;
  }

  Widget tab(Map<String, dynamic> row, {String module = 'quotation', bool canEmail = true}) =>
      SingleChildScrollView(child: RecordDocumentTab(module: module, row: row, canEmail: canEmail));

  // ------------------------------------------------------------ rich text

  group('rich text editor', () {
    test('template HTML → editable text → the same e-mail HTML', () {
      final c = NxRichTextController(html: '<p>เรียน {contact}</p><p>ขอส่ง <strong>QT-1</strong> &amp; ไฟล์</p><p>ขอแสดงความนับถือ<br>สมชาย<br>081</p>');
      expect(c.text, 'เรียน {contact}\n\nขอส่ง QT-1 & ไฟล์\n\nขอแสดงความนับถือ\nสมชาย\n081');
      expect(c.toHtml(), '<p>เรียน {contact}</p><p>ขอส่ง <strong>QT-1</strong> &amp; ไฟล์</p><p>ขอแสดงความนับถือ<br>สมชาย<br>081</p>');
    });

    test('bold / italic / underline on a selection; typing keeps the style; clear removes it', () {
      final c = NxRichTextController(html: '<p>hello world</p>');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.toggle(NxRich.bold);
      c.toggle(NxRich.underline);
      expect(c.toHtml(), '<p><strong><u>hello</u></strong> world</p>');
      expect(c.isActive(NxRich.bold), isTrue);
      // Type after "hello": inherits bold + underline.
      c.value = const TextEditingValue(text: 'hello! world', selection: TextSelection.collapsed(offset: 6));
      expect(c.toHtml(), '<p><strong><u>hello!</u></strong> world</p>');
      // Toggle italic for the next typed text at the end.
      c.selection = TextSelection.collapsed(offset: c.text.length);
      c.toggle(NxRich.italic);
      c.value = TextEditingValue(text: '${c.text}!', selection: TextSelection.collapsed(offset: c.text.length + 1));
      expect(c.toHtml(), '<p><strong><u>hello!</u></strong> world<em>!</em></p>');
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      c.clearFormatting();
      expect(c.toHtml(), '<p>hello! world!</p>');
    });

    test('lists: toggle, Enter continues / numbering, Enter on an empty item ends it; links', () {
      final c = NxRichTextController(html: '<p>a</p>');
      c.selection = const TextSelection.collapsed(offset: 1);
      c.toggleList(ordered: false);
      expect(c.text, '• a');
      c.value = const TextEditingValue(text: '• a\n', selection: TextSelection.collapsed(offset: 4));
      expect(c.text, '• a\n• ');
      c.value = const TextEditingValue(text: '• a\n• b', selection: TextSelection.collapsed(offset: 7));
      expect(c.toHtml(), '<ul><li>a</li><li>b</li></ul>');
      c.value = const TextEditingValue(text: '• a\n• b\n', selection: TextSelection.collapsed(offset: 8));
      c.value = TextEditingValue(text: '${c.text}\n', selection: TextSelection.collapsed(offset: c.text.length + 1));
      expect(c.text, '• a\n• b\n', reason: 'Enter on an empty item drops the bullet');
      final o = NxRichTextController(html: '<ol><li>one</li></ol>');
      expect(o.text, '1. one');
      o.value = const TextEditingValue(text: '1. one\n', selection: TextSelection.collapsed(offset: 7));
      expect(o.text, '1. one\n2. ');
      final l = NxRichTextController(html: '<p>see site</p>');
      l.selection = const TextSelection(baseOffset: 4, extentOffset: 8);
      l.setLink('https://x.test/a?b=1&c=2');
      expect(l.toHtml(), '<p>see <a href="https://x.test/a?b=1&amp;c=2">site</a></p>');
      expect(NxRichTextController(html: l.toHtml()).toHtml(), l.toHtml());
    });
  });

  // ------------------------------------------------------------ เอกสาร tab

  testWidgets('เอกสาร tab: the web\'s BIRT document of the record\'s template is shown first; download / share / print', (tester) async {
    final a = await pump(tester, tab({'id': 7, 'quotation_no': 'QT-7', 'template_key': 'template2'}), {
      'GET /api/quotation/7/birt-pdf?template=template2': pdf('birt-t2'),
      'GET /api/quotation/7/email-log': {'items': []},
    });
    expect(a.callKeys, contains('GET /api/quotation/7/birt-pdf?template=template2'));
    expect(a.callKeys.where((k) => k.startsWith('GET /api/quotation/7/pdf')), isEmpty, reason: 'never the built-in PDF on its own');
    expect(rendered, ['%PDF-1.4 birt-t2']);
    expect(find.byKey(const ValueKey('doc-tab-page-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-tab-page-1')), findsOneWidget);
    expect(find.textContaining('QT-7 · เทมเพลต 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('doc-tab-download')));
    await settle(tester, 3);
    expect(saved, ['QT-7.pdf:%PDF-1.4 birt-t2']);
    await tester.tap(find.byKey(const ValueKey('doc-tab-share')));
    await settle(tester, 3);
    expect(shared, ['QT-7.pdf']);
    await tester.tap(find.byKey(const ValueKey('doc-tab-print')));
    await settle(tester, 3);
    expect(printed, ['QT-7.pdf']);

    // Tap a page → full screen with the same bytes (no second report build).
    final birtCalls = a.callKeys.where((k) => k.contains('birt-pdf')).length;
    await tester.tap(find.byKey(const ValueKey('doc-tab-page-0')));
    await settle(tester, 8);
    expect(find.byType(DocumentPreviewScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-email')), findsOneWidget);
    expect(a.callKeys.where((k) => k.contains('birt-pdf')).length, birtCalls);
  });

  testWidgets('เอกสาร tab: report server error → server message + retry; never the built-in PDF on its own', (tester) async {
    final a = await pump(
      tester,
      tab({'id': 5, 'job_no': 'JOB-5', 'template_key': 'template1'}, module: 'job'),
      {
        'GET /api/field-service/jobs/5/pdf': pdf('std'),
        'GET /api/field-service/jobs/5/email-log': {'items': []},
      },
      errors: {
        'GET /api/field-service/jobs/5/birt-pdf': {'error_code': 'BIRT_NOT_CONFIGURED', 'message': 'ยังไม่ได้ตั้งค่า BIRT_JOB_PDF_URL'},
      },
    );
    expect(find.byKey(const ValueKey('doc-tab-error')), findsOneWidget);
    expect(find.text('ยังไม่ได้ตั้งค่า BIRT_JOB_PDF_URL'), findsOneWidget, reason: 'server message, not "API 503"');
    expect(find.byKey(const ValueKey('doc-tab-fallback')), findsOneWidget);
    expect(rendered, isEmpty);
    expect(a.callKeys, isNot(contains('GET /api/field-service/jobs/5/pdf')));
    expect(tester.widget<InkWell>(find.byKey(const ValueKey('doc-tab-download'))).onTap, isNull);

    // Retry asks the report server again.
    a.errorsFor.remove('GET /api/field-service/jobs/5/birt-pdf');
    a.replies['GET /api/field-service/jobs/5/birt-pdf'] = pdf('birt-ok');
    await tester.tap(find.byKey(const ValueKey('doc-tab-retry')));
    await settle(tester);
    expect(a.callKeys.where((k) => k == 'GET /api/field-service/jobs/5/birt-pdf').length, 2);
    expect(rendered, ['%PDF-1.4 birt-ok']);
    expect(find.byKey(const ValueKey('doc-tab-error')), findsNothing);
    expect(a.callKeys, isNot(contains('GET /api/field-service/jobs/5/pdf')));
  });

  testWidgets('เอกสาร tab: "ดูแบบสำรอง" shows the built-in PDF with a notice', (tester) async {
    await pump(
      tester,
      tab({'id': 5, 'job_no': 'JOB-5'}, module: 'job'),
      {
        'GET /api/field-service/jobs/5/pdf': pdf('std'),
        'GET /api/field-service/jobs/5/email-log': {'items': []},
      },
      status: {'GET /api/field-service/jobs/5/birt-pdf': 502},
    );
    await tester.tap(find.byKey(const ValueKey('doc-tab-fallback')));
    await settle(tester);
    expect(rendered, ['%PDF-1.4 std']);
    expect(find.byKey(const ValueKey('doc-tab-fallback-notice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-tab-download')));
    await settle(tester, 3);
    expect(saved, ['job-JOB-5-standard.pdf:%PDF-1.4 std']);
  });

  testWidgets('เอกสาร tab: sent e-mails listed; "ส่งซ้ำ" opens the sheet with the old values; no e-mail without permission', (tester) async {
    await pump(tester, tab({'id': 7, 'quotation_no': 'QT-7'}), {
      'GET /api/quotation/7/birt-pdf': pdf('birt'),
      'GET /api/quotation/7/compose-defaults': defaults(),
      'GET /api/quotation/7/email-log': {
        'items': [
          {
            'id': 3,
            'sent_at': '2026-11-12T03:00:00Z',
            'to': ['old@cust.test'],
            'cc': <String>[],
            'bcc': <String>[],
            'subject': 'เสนอราคารอบแรก',
            'body_html': '<p>สวัสดี</p>',
            'template_id': 'default',
            'attachments': [
              {'name': 'q.pdf', 'source': 'pdf_birt'},
            ],
            'status': 'sent',
            'sent_by': {'id': 1, 'name': 'สมชาย'},
          },
        ],
      },
    });
    expect(find.byKey(const ValueKey('doc-tab-email-log')), findsOneWidget);
    expect(find.text('เสนอราคารอบแรก'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-tab-resend-3')));
    await settle(tester, 8);
    expect(find.byType(DocEmailSheet), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'เสนอราคารอบแรก');
    expect(find.byKey(const ValueKey('chip-old@cust.test')), findsOneWidget);
  });

  testWidgets('no ส่งอีเมล in the tab when the user cannot edit the record', (tester) async {
    await pump(tester, tab({'id': 7, 'quotation_no': 'QT-7'}, canEmail: false), {
      'GET /api/quotation/7/birt-pdf': pdf('birt'),
      'GET /api/quotation/7/email-log': {'items': []},
    });
    expect(find.byKey(const ValueKey('doc-tab-download')), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-tab-email')), findsNothing);
  });

  // ------------------------------------------------------------ e-mail sheet

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open')));
    await settle(tester, 8);
  }

  Widget opener({String kind = 'quotation', String id = '7', int? pdfSize, void Function(bool)? onDone}) => Builder(
    builder: (context) => Center(
      child: FilledButton(
        key: const ValueKey('open'),
        onPressed: () async {
          final r = await showDocEmailSheet(context, kind: kind, id: id, pdfSize: pdfSize);
          onDone?.call(r);
        },
        child: const Text('open'),
      ),
    ),
  );

  testWidgets('e-mail sheet: prefilled like the web (subject, To, CC, template letter, auto PDF with size)', (tester) async {
    await pump(tester, opener(pdfSize: 1153434), {'GET /api/quotation/7/compose-defaults': defaults()}, size: const Size(420, 1000));
    await openSheet(tester);
    expect(find.text('ส่งอีเมลใบเสนอราคา'), findsOneWidget);
    expect(find.textContaining('QT-7 · บริษัท ลูกค้า'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'ใบเสนอราคา_QT-7_บริษัท ลูกค้า_261113');
    expect(find.byKey(const ValueKey('chip-buyer@cust.test')), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-owner@biz.test')), findsOneWidget);
    expect(find.text('คุณลูกค้า · buyer@cust.test'), findsOneWidget);
    final body = tester.widget<TextField>(find.byKey(const ValueKey('compose-body'))).controller as NxRichTextController;
    expect(body.text, startsWith('เรียน คุณลูกค้า\n\nขอส่งเอกสารเลขที่ QT-7'));
    expect(find.text('ใบเสนอราคา_QT-7.pdf'), findsOneWidget);
    expect(find.text('แนบอัตโนมัติจากรายงาน · 1.1 MB'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('compose-include-pdf'))).value, isTrue);
    expect(find.byKey(const ValueKey('compose-bcc')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('compose-show-bcc')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('compose-bcc')), findsOneWidget);
  });

  testWidgets('e-mail sheet: validation (subject, recipients, attachment) before calling the server', (tester) async {
    final a = await pump(tester, opener(), {'GET /api/quotation/7/compose-defaults': defaults()}, size: const Size(420, 1000));
    await openSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), '  ');
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 2);
    expect(find.text('กรุณาระบุหัวข้อ'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), 'หัวข้อ');
    // Remove both recipients.
    for (final e in ['buyer@cust.test', 'owner@biz.test']) {
      final chip = find.byKey(ValueKey('chip-$e'));
      await tester.tap(find.descendant(of: chip, matching: find.byIcon(NxI.x)));
      await settle(tester, 2);
    }
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 2);
    expect(find.text('กรุณาระบุผู้รับอย่างน้อย 1 คน'), findsOneWidget);
    // A bad address becomes a red chip and blocks sending.
    final toField = find.descendant(of: find.byKey(const ValueKey('compose-to')), matching: find.byType(TextField));
    await tester.enterText(toField, 'not-an-email ');
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 2);
    expect(find.textContaining('อีเมลไม่ถูกต้อง: not-an-email'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('chip-not-an-email')), matching: find.byIcon(NxI.x)));
    await settle(tester, 2);
    await tester.enterText(toField, 'x@cust.test,');
    await settle(tester, 2);
    // No PDF, no files → asks for an attachment.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('compose-include-pdf')), 200, scrollable: find.descendant(of: find.byType(DocEmailSheet), matching: find.byType(Scrollable)).first);
    await tester.tap(find.byKey(const ValueKey('compose-include-pdf')));
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 2);
    expect(find.text('กรุณาแนบไฟล์อย่างน้อย 1 ไฟล์'), findsOneWidget);
    expect(a.callKeys.where((k) => k.contains('compose-send')), isEmpty);
  });

  testWidgets('e-mail sheet: suggestions while typing; send → the web\'s multipart payload; toast; closes', (tester) async {
    bool? result;
    final a = await pump(
      tester,
      opener(onDone: (r) => result = r),
      {
        'GET /api/quotation/7/compose-defaults': defaults(),
        'POST /api/quotation/7/compose-send': {
          'id': 9,
          'status': 'sent',
          'queued': false,
          'to': ['buyer@cust.test', 'somsri@biz.test'],
          'cc': ['owner@biz.test'],
          'attachments': [
            {'name': 'ใบเสนอราคา_QT-7.pdf', 'source': 'pdf_birt'},
          ],
        },
      },
      size: const Size(420, 1000),
    );
    DocEmailHooks.pickFiles = (_) async => [MultipartFile.fromBytes(utf8.encode('spec'), filename: 'สเปค.txt')];
    await openSheet(tester);
    final toField = find.descendant(of: find.byKey(const ValueKey('compose-to')), matching: find.byType(TextField));
    await tester.tap(toField);
    await tester.enterText(toField, 'สมศ');
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('suggest-somsri@biz.test')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggest-buyer@cust.test')), findsNothing, reason: 'already added');
    await tester.tap(find.byKey(const ValueKey('suggest-somsri@biz.test')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('chip-somsri@biz.test')), findsOneWidget);

    // Bold the first word of the letter via the toolbar.
    final body = tester.widget<TextField>(find.byKey(const ValueKey('compose-body'))).controller as NxRichTextController;
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.ensureVisible(find.byKey(const ValueKey('rte-bold')));
    await tester.tap(find.byKey(const ValueKey('rte-bold')));
    await settle(tester, 1);

    await tester.ensureVisible(find.byKey(const ValueKey('compose-add-files')));
    await tester.tap(find.byKey(const ValueKey('compose-add-files')));
    await settle(tester, 2);
    expect(find.text('สเปค.txt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 8);
    final call = a.calls.lastWhere((c) => c.path == '/api/quotation/7/compose-send');
    expect(call.method, 'POST');
    final form = call.data as FormData;
    final f = {for (final e in form.fields) e.key: e.value};
    expect(f['to'], 'buyer@cust.test,somsri@biz.test');
    expect(f['cc'], 'owner@biz.test');
    expect(f['bcc'], '');
    expect(f['subject'], 'ใบเสนอราคา_QT-7_บริษัท ลูกค้า_261113');
    expect(f['include_pdf'], 'true');
    expect(f['include_link'], 'false');
    expect(f['template_id'], 'default');
    expect(f['body_html'], startsWith('<p><strong>เรียน</strong> คุณลูกค้า</p><p>ขอส่งเอกสารเลขที่ <strong>QT-7</strong> ตามไฟล์แนบ</p>'));
    expect(form.files.map((e) => '${e.key}:${e.value.filename}'), ['files:สเปค.txt']);
    expect(result, isTrue);
    expect(find.byType(DocEmailSheet), findsNothing);
    expect(find.textContaining('ส่งอีเมลเรียบร้อย'), findsOneWidget);
  });

  testWidgets('e-mail sheet (job): job endpoints; mail not set up → clear Thai notice and no send', (tester) async {
    final a = await pump(
      tester,
      opener(kind: 'job', id: '5'),
      {'GET /api/field-service/jobs/5/compose-defaults': defaults(kind: 'job', ready: false)},
      size: const Size(420, 1000),
    );
    await openSheet(tester);
    expect(a.callKeys, contains('GET /api/field-service/jobs/5/compose-defaults'));
    expect(find.text('ส่งอีเมลใบสั่งงาน'), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-mail-not-ready')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-include-link')), findsNothing, reason: 'customer link option is quotation-only');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('compose-send'))).onPressed, isNull);
    // รีเฟรช reloads the defaults (e.g. after an admin set up e-mail).
    a.replies['GET /api/field-service/jobs/5/compose-defaults'] = defaults(kind: 'job');
    await tester.tap(find.byKey(const ValueKey('compose-refresh')));
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('compose-mail-not-ready')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('compose-send'))).onPressed, isNotNull);
  });

  testWidgets('e-mail sheet: server refusal (mail transport) shown in the sheet', (tester) async {
    await pump(
      tester,
      opener(kind: 'job', id: '5'),
      {'GET /api/field-service/jobs/5/compose-defaults': defaults(kind: 'job')},
      status: {'POST /api/field-service/jobs/5/compose-send': 503},
      errors: {
        'POST /api/field-service/jobs/5/compose-send': {'error_code': 'SMTP_NOT_CONFIGURED', 'message': 'ยังไม่ได้ตั้งค่าการส่งอีเมล — ไปที่ ตั้งค่า › การส่งอีเมล'},
      },
      size: const Size(420, 1000),
    );
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 6);
    expect(find.byKey(const ValueKey('compose-error')), findsOneWidget);
    expect(find.textContaining('ยังไม่ได้ตั้งค่าการส่งอีเมล'), findsWidgets);
    expect(find.byType(DocEmailSheet), findsOneWidget);
  });

  // ------------------------------------------------------------ detail screen

  Future<FakeNextxAdapter> detail(WidgetTester tester, String module, {required List<String> menus, Map<String, Object?> extra = const {}}) async {
    ServiceJourney.debugClear();
    final row = module == 'job'
        ? {'id': 9, 'job_no': 'JOB-9', 'job_name': '[QA] R68', 'job_status': 'Open', 'smownerid': 1}
        : {'id': 9, 'quotation_no': 'QT-9', 'title_th': '[QA] R68', 'smownerid': 1};
    return pump(
      tester,
      EntityDetailScreen(module: module, row: const {'id': 9}),
      {
        'GET /api/entity/$module/9': row,
        'GET /api/entity/$module/9/comments': {'list': []},
        'GET /api/entity/$module/9/tags': {'list': []},
        'GET /api/tags': {'list': []},
        'GET /api/users': {'list': []},
        'GET /api/fields/$module': {'list': [], 'picklists': {}},
        'GET /api/links/$module/9': {'quotations': [], 'jobs': [], 'activities': []},
        ...extra,
      },
      menus: menus,
      size: const Size(430, 2400),
    );
  }

  testWidgets('detail: เอกสาร tab for quotation / job users; opens the template document', (tester) async {
    final a = await detail(tester, 'quotation', menus: ['quotation'], extra: {
      'GET /api/quotation/9/birt-pdf': pdf('qt9'),
      'GET /api/quotation/9/email-log': {'items': []},
    });
    expect(find.text('เอกสาร'), findsWidgets);
    await tester.tap(find.text('เอกสาร').first);
    await settle(tester, 10);
    expect(a.callKeys, contains('GET /api/quotation/9/birt-pdf'));
    expect(find.byType(RecordDocumentTab), findsOneWidget);
    expect(rendered, ['%PDF-1.4 qt9']);
  });

  testWidgets('detail: no เอกสาร tab without the menu permission', (tester) async {
    await detail(tester, 'job', menus: ['quotation']);
    expect(find.text('ข้อมูล'), findsWidgets);
    expect(find.text('เอกสาร'), findsNothing);
  });
}
