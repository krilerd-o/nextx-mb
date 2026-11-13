import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/docs/document_preview.dart';

import 'support/fake_api.dart';

Uint8List pdf(String tag) => Uint8List.fromList(utf8.encode('%PDF-1.4 $tag'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> rendered;
  late List<String> saved, printed, shared;

  setUp(() {
    rendered = [];
    saved = [];
    printed = [];
    shared = [];
    // Two A4-ish pages per document; remembers which PDF was drawn.
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
  });
  tearDown(() {
    DocPreviewHooks.render = null;
    DocPreviewHooks.save = null;
    DocPreviewHooks.print = null;
    DocPreviewHooks.share = null;
  });

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<FakeNextxAdapter> pump(WidgetTester tester, Widget home, Map<String, Object?> replies, {Map<String, int> status = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter(replies, statusFor: status);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['job', 'quotation']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    await settle(tester, 8);
    return adapter;
  }

  testWidgets('job: template (BIRT) down → clear error, no silent switch; the fallback only when chosen', (tester) async {
    final a = await pump(
      tester,
      DocumentPreviewScreen(source: jobDocumentSource({'id': 19, 'job_no': 'JOB-19', 'template_key': 'template1'})),
      {
        'GET /api/field-service/jobs/19/pdf': pdf('std'),
      },
      status: {'GET /api/field-service/jobs/19/birt-pdf': 503},
    );
    // R68: the document must be the web's template — never another design behind the user's back.
    expect(rendered, isEmpty);
    expect(a.callKeys, isNot(contains('GET /api/field-service/jobs/19/pdf')));
    expect(find.text('เปิดเอกสารไม่สำเร็จ'), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('doc-show-fallback')));
    await settle(tester);
    expect(find.byKey(const ValueKey('doc-fallback-notice')), findsOneWidget);
    expect(rendered, ['%PDF-1.4 std']);
    expect(find.byKey(const ValueKey('doc-page-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-page-1')), findsOneWidget);
    expect(find.text('หน้า 1/2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('doc-print')));
    await settle(tester, 3);
    expect(printed, ['job-JOB-19-standard.pdf']);
    await tester.tap(find.byKey(const ValueKey('doc-share')));
    await settle(tester, 3);
    expect(shared, ['job-JOB-19-standard.pdf']);
    await tester.tap(find.byKey(const ValueKey('doc-download')));
    await settle(tester, 3);
    expect(saved, ['job-JOB-19-standard.pdf:%PDF-1.4 std']);
    expect(find.textContaining('บันทึกแล้ว'), findsOneWidget);
  });

  testWidgets('quotation: only the template report like the web (no language / colour reports that do not exist)', (tester) async {
    final a = await pump(
      tester,
      DocumentPreviewScreen(source: quotationDocumentSource({'id': 7, 'quotation_no': 'QT-7', 'template_key': 'template2', 'template_id': 3})),
      {
        'GET /api/quotation/7/birt-pdf?template=template2': pdf('birt'),
        'GET /api/quotation/templates': {'list': [
          {'id': 3, 'name': '[QA] เทมเพลตหลัก', 'layout_json': {'variants': ['th', 'en'], 'colors': ['bw']}},
        ]},
      },
    );
    expect(rendered.first, '%PDF-1.4 birt');
    expect(find.byKey(const ValueKey('doc-variant-birt-th-bw')), findsNothing);
    expect(find.byKey(const ValueKey('doc-variant-birt-en-bw')), findsNothing);
    expect(find.byKey(const ValueKey('doc-variant-std')), findsNothing);
    expect(find.textContaining('เทมเพลต 2 · [QA] เทมเพลตหลัก'), findsOneWidget);
    expect(a.callKeys.where((k) => k.contains('lang=') || k.contains('color=')), isEmpty);
    expect(find.byKey(const ValueKey('doc-fallback-notice')), findsNothing);
  });

  testWidgets('double tap zooms in and out; pinch zoom is enabled', (tester) async {
    await pump(tester, DocumentPreviewScreen(source: jobDocumentSource({'id': 19, 'job_no': 'JOB-19'})), {
      'GET /api/field-service/jobs/19/birt-pdf': pdf('birt'),
    });
    final viewer = tester.widget<InteractiveViewer>(find.byKey(const ValueKey('doc-viewer')));
    expect(viewer.maxScale, greaterThanOrEqualTo(5));
    expect(viewer.scaleEnabled, isTrue);
    expect(find.text('100%'), findsOneWidget);
    final center = tester.getCenter(find.byKey(const ValueKey('doc-page-0')));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.text('250%'), findsOneWidget);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('not a PDF and no fallback → clear error with retry', (tester) async {
    await pump(tester, DocumentPreviewScreen(source: inspectionDocumentSource('5', no: 'IN-5')), {
      'GET /api/field-service/inspections/5/birt-pdf': Uint8List.fromList(utf8.encode('<html>oops</html>')),
      'GET /api/field-service/inspections/5/pdf': Uint8List.fromList(utf8.encode('nope')),
    });
    expect(find.text('เปิดเอกสารไม่สำเร็จ'), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-retry')), findsOneWidget);
  });

  testWidgets('summary card shares the template document without opening the preview', (tester) async {
    await pump(
      tester,
      Scaffold(body: DocumentCard(source: () => quotationDocumentSource({'id': 7, 'quotation_no': 'QT-7'}))),
      {'GET /api/quotation/7/birt-pdf': pdf('birt')},
    );
    await tester.tap(find.byKey(const ValueKey('doc-card-share')));
    await settle(tester, 4);
    expect(shared, ['QT-7.pdf']);
    await tester.tap(find.byKey(const ValueKey('doc-card')));
    await settle(tester, 6);
    expect(find.byType(DocumentPreviewScreen), findsOneWidget);
  });
}
