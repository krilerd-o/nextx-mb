// R75: the document e-mail composer (quotation / job) — modern mail layout,
// same server payloads as before.
import 'dart:async';
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
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/docs/doc_email_parts.dart';
import 'package:nextx_mobile/screens/docs/doc_email_sheet.dart';
import 'package:nextx_mobile/screens/docs/document_preview.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';

import 'support/fake_api.dart';

Map<String, Object?> defaults({bool ready = true, String kind = 'quotation', List<String> cc = const ['owner@biz.test']}) => {
  kind == 'job' ? 'job' : 'quotation': {'id': 7, kind == 'job' ? 'job_no' : 'quotation_no': kind == 'job' ? 'JOB-5' : 'QT-7', 'customer': 'บริษัท ลูกค้า'},
  'to': ['buyer@cust.test'],
  'cc': cc,
  'bcc': <String>[],
  'template_id': 'default',
  'subject': kind == 'job' ? 'ใบสั่งงาน_JOB-5' : 'ใบเสนอราคา_QT-7',
  'body_html': '<p>เรียน คุณลูกค้า</p><p>ขอส่งเอกสารเลขที่ <strong>QT-7</strong></p>',
  'templates': [
    {'id': 'default', 'name': 'มาตรฐาน', 'is_default': true, 'subject': 'S1', 'body_html': '<p>B1</p>'},
    {'id': 'short', 'name': 'แบบสั้น', 'subject': 'สั้น', 'body_html': '<p>สั้นๆ</p>'},
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

const sentReply = {
  'id': 9,
  'status': 'sent',
  'queued': false,
  'to': ['buyer@cust.test'],
  'cc': ['owner@biz.test'],
};

/// Reads the multipart body (so upload progress is reported) and can hold
/// the reply until [release].
class UploadAdapter extends FakeNextxAdapter {
  UploadAdapter(super.replies) : super(statusFor: <String, int>{}, errorsFor: <String, Map<String, Object?>>{});
  Completer<void>? gate;
  bool get held => gate != null && !gate!.isCompleted;
  void holdNext() => gate = Completer<void>();
  void release() => gate?.complete();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('compose-send') && requestStream != null) {
      final g = gate;
      if (g != null) {
        // Stop after the first chunk: part of the body is "uploaded".
        final first = Completer<void>();
        late StreamSubscription<Uint8List> sub;
        sub = requestStream.listen((_) {
          if (!first.isCompleted) {
            sub.pause();
            first.complete();
          }
        });
        await first.future;
        await g.future;
        sub.resume();
        await sub.asFuture<void>();
      } else {
        await requestStream.drain<void>();
      }
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DocEmailHooks.pickFiles = null;
    DocPreviewHooks.render = (bytes, dpi) async* {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 60, 85), Paint()..color = const Color(0xFFFFFFFF));
      yield await rec.endRecording().toImage(60, 85);
    };
  });
  tearDown(() {
    DocEmailHooks.pickFiles = null;
    DocPreviewHooks.render = null;
  });

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  bool? result;

  Future<UploadAdapter> open(WidgetTester tester, {String kind = 'quotation', Map<String, Object?>? d, Size size = const Size(420, 1000), Map<String, Object?> extra = const {}}) async {
    result = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final base = kind == 'job' ? '/api/field-service/jobs/5' : '/api/quotation/7';
    final a = UploadAdapter({
      'GET $base/compose-defaults': d ?? defaults(kind: kind),
      'POST $base/compose-send': sentReply,
      ...extra,
    });
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['job', 'quotation']));
    config.apiClient.debugSetHttpAdapter(a);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const ValueKey('open'),
                onPressed: () async => result = await showDocEmailSheet(context, kind: kind, id: kind == 'job' ? '5' : '7', pdfSize: 2048),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('open')));
    await settle(tester, 8);
    return a;
  }

  VoidCallback? sendAction(WidgetTester t) => t.widget<FilledButton>(find.byKey(const ValueKey('compose-send'))).onPressed;
  Finder field(String line) => find.descendant(of: find.byKey(ValueKey(line)), matching: find.byType(TextField));
  Map<String, String> fields(FakeNextxAdapter a, String path) {
    final form = a.calls.lastWhere((c) => c.path == path).data as FormData;
    return {for (final e in form.fields) e.key: e.value};
  }

  testWidgets('full-screen composer: app bar with close, title, document chip, send; no bottom bar', (tester) async {
    await open(tester);
    expect(find.byType(DocEmailSheet), findsOneWidget);
    expect(find.text('ส่งอีเมล'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('compose-doc-chip')), matching: find.text('QT-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-menu')), findsOneWidget);
    expect(find.text('ส่งรายงาน'), findsNothing);
    expect(find.text('รีเฟรช'), findsNothing);
    // Send sits in the top bar.
    expect(tester.getTopLeft(find.byKey(const ValueKey('compose-send'))).dy, lessThan(80));
    expect(sendAction(tester), isNotNull);
    // Format bar only while writing the letter.
    expect(find.byKey(const ValueKey('compose-format-bar')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('compose-body')));
    await settle(tester, 1);
    expect(find.byKey(const ValueKey('compose-format-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('rte-bold')), findsOneWidget);
  });

  testWidgets('send disabled until valid: subject, recipients, attachment; tap explains why', (tester) async {
    final a = await open(tester);
    expect(sendAction(tester), isNotNull);
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), ' ');
    await settle(tester, 1);
    expect(sendAction(tester), isNull);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 2);
    expect(find.descendant(of: find.byKey(const ValueKey('compose-error')), matching: find.text('กรุณาระบุหัวข้อ')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), 'หัวข้อใหม่');
    await settle(tester, 1);
    expect(sendAction(tester), isNotNull);
    expect(find.byKey(const ValueKey('compose-error')), findsNothing);

    // No recipients → disabled; an address still being typed counts.
    for (final e in ['buyer@cust.test', 'owner@biz.test']) {
      await tester.tap(find.descendant(of: find.byKey(ValueKey('chip-$e')), matching: find.byIcon(NxI.x)));
      await settle(tester, 1);
    }
    expect(sendAction(tester), isNull);
    await tester.enterText(field('compose-to'), 'typed@cust.test');
    await settle(tester, 1);
    expect(sendAction(tester), isNotNull);

    // No attachment → disabled.
    await tester.tap(find.byKey(const ValueKey('compose-include-pdf')));
    await settle(tester, 1);
    expect(sendAction(tester), isNull);
    expect(find.byKey(const ValueKey('compose-no-attachment')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-restore-pdf')));
    await settle(tester, 1);
    expect(sendAction(tester), isNotNull);

    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 20);
    final f = fields(a, '/api/quotation/7/compose-send');
    expect(f['to'], 'typed@cust.test', reason: 'the typed address is sent');
    expect(f['subject'], 'หัวข้อใหม่');
    expect(result, isTrue);
  });

  testWidgets('recipient chips: comma adds, invalid shown red with a hint, tap to edit, remove via sheet', (tester) async {
    await open(tester);
    await tester.enterText(field('compose-to'), 'new@cust.test,');
    await settle(tester, 1);
    expect(find.byKey(const ValueKey('chip-new@cust.test')), findsOneWidget);
    await tester.enterText(field('compose-to'), 'oops ');
    await settle(tester, 1);
    expect(find.byKey(const ValueKey('chip-oops')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-invalid-hint')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('chip-oops')), matching: find.byIcon(NxI.warningCircle)), findsOneWidget);
    expect(sendAction(tester), isNull);

    // Tap the invalid chip → back into the field to fix it.
    await tester.tap(find.byKey(const ValueKey('chip-oops')));
    await settle(tester, 1);
    expect(find.byKey(const ValueKey('chip-oops')), findsNothing);
    expect(tester.widget<TextField>(field('compose-to')).controller!.text, 'oops');
    await tester.enterText(field('compose-to'), 'oops@cust.test ');
    await settle(tester, 1);
    expect(find.byKey(const ValueKey('chip-oops@cust.test')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-invalid-hint')), findsNothing);
    expect(sendAction(tester), isNotNull);

    // Tap a valid chip → details sheet → remove.
    await tester.tap(find.byKey(const ValueKey('chip-buyer@cust.test')));
    await settle(tester, 4);
    expect(find.text('คุณลูกค้า'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('compose-chip-remove')));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('chip-buyer@cust.test')), findsNothing);

    // … or edit.
    await tester.tap(find.byKey(const ValueKey('chip-new@cust.test')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('compose-chip-edit')));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('chip-new@cust.test')), findsNothing);
    expect(tester.widget<TextField>(field('compose-to')).controller!.text, 'new@cust.test');
  });

  testWidgets('suggestions show avatar, name, email; tap adds', (tester) async {
    await open(tester);
    await tester.tap(field('compose-to'));
    await tester.enterText(field('compose-to'), 'สมศ');
    await settle(tester, 2);
    final s = find.byKey(const ValueKey('suggest-somsri@biz.test'));
    expect(s, findsOneWidget);
    expect(find.descendant(of: s, matching: find.byType(RecipientAvatar)), findsOneWidget);
    expect(find.descendant(of: s, matching: find.text('สมศรี ทดสอบ')), findsOneWidget);
    expect(find.descendant(of: s, matching: find.text('somsri@biz.test')), findsOneWidget);
    await tester.tap(s);
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('chip-somsri@biz.test')), findsOneWidget);
  });

  testWidgets('Cc/Bcc: one collapsed line without CC; expands on tap; Bcc reaches the payload', (tester) async {
    final a = await open(tester, d: defaults(cc: const []));
    expect(find.byKey(const ValueKey('compose-cc')), findsNothing);
    expect(find.byKey(const ValueKey('compose-bcc')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('compose-show-bcc')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('compose-cc')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-bcc')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-show-bcc')), findsNothing);
    await tester.enterText(field('compose-bcc'), 'audit@biz.test,');
    await settle(tester, 1);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 20);
    final f = fields(a, '/api/quotation/7/compose-send');
    expect(f['cc'], '');
    expect(f['bcc'], 'audit@biz.test');
  });

  testWidgets('attachments row: auto document card (preview), add / remove files, size + count limits', (tester) async {
    await open(tester, extra: {'GET /api/quotation/7/birt-pdf': Uint8List.fromList(utf8.encode('%PDF-1.4 doc'))});
    final card = find.byKey(const ValueKey('compose-pdf-card'));
    expect(find.descendant(of: card, matching: find.text('ใบเสนอราคา_QT-7.pdf')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('แนบอัตโนมัติ')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('2 KB')), findsOneWidget);

    DocEmailHooks.pickFiles = (_) async => [
      MultipartFile.fromBytes(List.filled(3000, 1), filename: 'a.jpg'),
      MultipartFile.fromBytes(List.filled(16 * 1024 * 1024, 1), filename: 'big.zip'),
    ];
    await tester.tap(find.byKey(const ValueKey('compose-attach')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('compose-file-0')), findsOneWidget);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('big.zip'), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('compose-error')), matching: find.textContaining('ไฟล์ใหญ่เกิน 15 MB: big.zip')), findsOneWidget);
    expect(find.textContaining('ไฟล์แนบ 2'), findsOneWidget);

    DocEmailHooks.pickFiles = (_) async => [for (var i = 0; i < 12; i++) MultipartFile.fromBytes([i], filename: 'f$i.txt')];
    await tester.tap(find.byKey(const ValueKey('compose-attach')));
    await settle(tester, 2);
    expect(find.descendant(of: find.byKey(const ValueKey('compose-error')), matching: find.text('แนบไฟล์ได้สูงสุด 10 ไฟล์')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('compose-attach'))).onPressed, isNull, reason: 'full');

    await tester.drag(find.byKey(const ValueKey('compose-attachments')), const Offset(-200, 0));
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('compose-file-remove-0')));
    await settle(tester, 1);
    expect(find.text('a.jpg'), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('compose-attach'))).onPressed, isNotNull);

    // Tap the document → the existing document preview.
    await tester.drag(find.byKey(const ValueKey('compose-attachments')), const Offset(400, 0));
    await settle(tester, 2);
    await tester.tap(card);
    await settle(tester, 8);
    expect(find.byType(DocumentPreviewScreen), findsOneWidget);
  });

  testWidgets('sending: spinner, upload progress per file, fields locked; success then closes', (tester) async {
    final a = await open(tester);
    DocEmailHooks.pickFiles = (_) async => [MultipartFile.fromBytes(List.filled(40000, 7), filename: 'spec.pdf')];
    await tester.tap(find.byKey(const ValueKey('compose-add-files')));
    await settle(tester, 2);
    a.holdNext();
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 3);
    expect(a.held, isTrue);
    expect(find.byKey(const ValueKey('compose-progress')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('compose-send')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    expect(sendAction(tester), isNull);
    expect(tester.widget<AttachmentCard>(find.byKey(const ValueKey('compose-file-0'))).progress, isNotNull);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).enabled, isFalse);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('compose-close'))).onPressed, isNull);

    a.release();
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('compose-success')), findsOneWidget);
    expect(find.text('ส่งแล้ว'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('compose-success-who'))).data, 'ถึง คุณลูกค้า, สมชาย');
    await settle(tester, 14);
    expect(find.byType(DocEmailSheet), findsNothing);
    expect(result, isTrue);
    expect(find.textContaining('ส่งอีเมลเรียบร้อย'), findsOneWidget);
  });

  testWidgets('error: draft kept, message inline, send again works', (tester) async {
    final a = await open(tester, kind: 'job');
    a.statusFor['POST /api/field-service/jobs/5/compose-send'] = 503;
    a.errorsFor['POST /api/field-service/jobs/5/compose-send'] = {'error_code': 'SMTP', 'message': 'เชื่อมต่อ SMTP ไม่ได้'};
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), 'แก้หัวข้อ');
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 6);
    expect(find.descendant(of: find.byKey(const ValueKey('compose-error')), matching: find.text('เชื่อมต่อ SMTP ไม่ได้')), findsOneWidget);
    expect(find.byType(DocEmailSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-success')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'แก้หัวข้อ');
    expect(sendAction(tester), isNotNull);

    a.statusFor.clear();
    a.errorsFor.clear();
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 20);
    expect(result, isTrue);
    expect(a.calls.where((c) => c.path.endsWith('compose-send')).length, 2);
  });

  testWidgets('mail not configured: slim banner, send disabled, re-check keeps the draft', (tester) async {
    final a = await open(tester, kind: 'job', d: defaults(kind: 'job', ready: false));
    expect(find.byKey(const ValueKey('compose-mail-not-ready')), findsOneWidget);
    expect(find.text('ยังไม่ได้ตั้งค่าการส่งอีเมลของธุรกิจ', findRichText: true), findsNothing);
    expect(find.textContaining('ยังไม่ได้ตั้งค่าการส่งอีเมลของธุรกิจ', findRichText: true), findsOneWidget);
    expect(sendAction(tester), isNull);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('compose-error')), findsNothing, reason: 'the banner already says why');

    await tester.enterText(find.byKey(const ValueKey('compose-subject')), 'ร่างของฉัน');
    a.replies['GET /api/field-service/jobs/5/compose-defaults'] = defaults(kind: 'job');
    await tester.tap(find.byKey(const ValueKey('compose-recheck')));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('compose-mail-not-ready')), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'ร่างของฉัน');
    expect(sendAction(tester), isNotNull);
  });

  testWidgets('discard guard: no question without edits; "ทิ้งอีเมลนี้?" with edits', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('compose-close')));
    await settle(tester, 8);
    expect(find.byType(DocEmailSheet), findsNothing);
    expect(result, isFalse);

    await tester.tap(find.byKey(const ValueKey('open')));
    await settle(tester, 8);
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), 'แก้แล้ว');
    await tester.tap(find.byKey(const ValueKey('compose-close')));
    await settle(tester, 3);
    expect(find.text('ทิ้งอีเมลนี้?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-confirm-cancel')));
    await settle(tester, 3);
    expect(find.byType(DocEmailSheet), findsOneWidget);

    // System back asks too.
    await tester.binding.handlePopRoute();
    await settle(tester, 3);
    expect(find.text('ทิ้งอีเมลนี้?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-discard-ok')));
    await settle(tester, 8);
    expect(find.byType(DocEmailSheet), findsNothing);
    expect(result, isFalse);
  });

  testWidgets('⋮ menu: reload default text (confirm when edited), template, sent history → reuse', (tester) async {
    final a = await open(tester, extra: {
      'GET /api/quotation/7/email-log': {
        'items': [
          {
            'id': 3,
            'sent_at': '2026-11-12T03:00:00Z',
            'to': ['old@cust.test'],
            'cc': <String>[],
            'bcc': <String>[],
            'subject': 'รอบแรก',
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
    expect(a.callKeys.where((k) => k.contains('email-log')), isEmpty, reason: 'history loads only when asked');
    await tester.enterText(find.byKey(const ValueKey('compose-subject')), 'แก้แล้ว');

    await tester.tap(find.byKey(const ValueKey('compose-menu')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('compose-refresh')));
    await settle(tester, 4);
    expect(find.text('โหลดข้อความตั้งต้นใหม่?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-confirm-ok')));
    await settle(tester, 4);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'ใบเสนอราคา_QT-7');

    await tester.tap(find.byKey(const ValueKey('compose-menu')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('compose-template')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('compose-template-short')));
    await settle(tester, 4);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'สั้น');

    await tester.tap(find.byKey(const ValueKey('compose-menu')));
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('compose-history')));
    await settle(tester, 6);
    expect(a.callKeys, contains('GET /api/quotation/7/email-log'));
    expect(find.text('รอบแรก'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('compose-history-3')));
    await settle(tester, 4);
    // The template switch counted as an edit → confirm.
    if (find.byKey(const ValueKey('compose-confirm-ok')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('compose-confirm-ok')));
      await settle(tester, 4);
    }
    expect(tester.widget<TextField>(find.byKey(const ValueKey('compose-subject'))).controller!.text, 'รอบแรก');
    expect(find.byKey(const ValueKey('chip-old@cust.test')), findsOneWidget);
  });

  testWidgets('payload unchanged — quotation: every field like the web', (tester) async {
    final a = await open(tester);
    DocEmailHooks.pickFiles = (_) async => [MultipartFile.fromBytes(utf8.encode('x'), filename: 'x.txt')];
    await tester.tap(find.byKey(const ValueKey('compose-add-files')));
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('compose-include-link')));
    await settle(tester, 1);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 20);
    final call = a.calls.lastWhere((c) => c.path == '/api/quotation/7/compose-send');
    expect(call.method, 'POST');
    final form = call.data as FormData;
    expect({for (final e in form.fields) e.key: e.value}, {
      'to': 'buyer@cust.test',
      'cc': 'owner@biz.test',
      'bcc': '',
      'subject': 'ใบเสนอราคา_QT-7',
      'body_html': '<p>เรียน คุณลูกค้า</p><p>ขอส่งเอกสารเลขที่ <strong>QT-7</strong></p>',
      'include_pdf': 'true',
      'include_link': 'true',
      'template_id': 'default',
      'file_ids': '',
    });
    expect(form.files.map((e) => '${e.key}:${e.value.filename}'), ['files:x.txt']);
    expect(result, isTrue);
  });

  testWidgets('payload unchanged — job: job endpoint, no customer link, PDF removed + file', (tester) async {
    final a = await open(tester, kind: 'job');
    expect(find.byKey(const ValueKey('compose-include-link')), findsNothing);
    DocEmailHooks.pickFiles = (_) async => [MultipartFile.fromBytes(utf8.encode('y'), filename: 'y.txt')];
    await tester.tap(find.byKey(const ValueKey('compose-add-files')));
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('compose-include-pdf')));
    await settle(tester, 1);
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await settle(tester, 20);
    final form = a.calls.lastWhere((c) => c.path == '/api/field-service/jobs/5/compose-send').data as FormData;
    expect({for (final e in form.fields) e.key: e.value}, {
      'to': 'buyer@cust.test',
      'cc': 'owner@biz.test',
      'bcc': '',
      'subject': 'ใบสั่งงาน_JOB-5',
      'body_html': '<p>เรียน คุณลูกค้า</p><p>ขอส่งเอกสารเลขที่ <strong>QT-7</strong></p>',
      'include_pdf': 'false',
      'include_link': 'false',
      'template_id': 'default',
      'file_ids': '',
    });
    expect(form.files.map((e) => e.value.filename), ['y.txt']);
    expect(a.callKeys.where((k) => k.startsWith('POST /api/quotation')), isEmpty);
  });

  testWidgets('tablet: centered window, at most 720 wide', (tester) async {
    await open(tester, size: const Size(1280, 900));
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.getSize(find.byType(DocEmailSheet)).width, lessThanOrEqualTo(720));
  });
}
