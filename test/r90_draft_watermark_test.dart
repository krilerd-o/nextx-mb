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
import 'package:nextx_mobile/screens/docs/document_tab.dart';

import 'support/fake_api.dart';

Uint8List pdf(String tag) => Uint8List.fromList(utf8.encode('%PDF-1.4 $tag'));

const _wm = ValueKey('doc-draft-watermark');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> saved;

  setUp(() {
    saved = [];
    DocPreviewHooks.render = (bytes, dpi) async* {
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
    RecordDocumentTab.clearCache();
  });
  tearDown(() {
    DocPreviewHooks.render = null;
    DocPreviewHooks.save = null;
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

  Map<String, dynamic> qt(String approval, String status) => {'id': 5, 'quotation_no': 'QT-5', 'approval_state': approval, 'quotation_status': status};
  const settingsOn = {
    'config': {
      'document': {'watermark_until_approved': true},
    },
  };

  group('rules = the server (shouldWatermarkQuotation / job report)', () {
    test('quotation: DRAFT until approved; off in the settings → never', () {
      expect(quotationDraftWatermark(qt('none', 'เปิดใบเสนอราคา')), isTrue);
      expect(quotationDraftWatermark(qt('pending', 'เปิดใบเสนอราคา')), isTrue);
      expect(quotationDraftWatermark(qt('rejected', 'เปิดใบเสนอราคา')), isTrue);
      expect(quotationDraftWatermark(qt('approved', 'อนุมัติใบเสนอราคา')), isFalse);
      expect(quotationDraftWatermark(qt('done', 'เปิดใบเสนอราคา')), isFalse);
      expect(quotationDraftWatermark(qt('none', 'ปิดการขาย')), isFalse);
      expect(quotationDraftWatermark(qt('', 'Won')), isFalse);
      expect(quotationDraftWatermark(qt('none', 'เปิดใบเสนอราคา'), settingsOn), isTrue);
      expect(
        quotationDraftWatermark(qt('none', 'เปิดใบเสนอราคา'), {
          'config': {
            'document': {'watermark_until_approved': false},
          },
        }),
        isFalse,
      );
      // No status on the row → unknown, not marked.
      expect(quotationDraftWatermark({'id': 5}), isFalse);
    });

    test('job: Template-2 while Draft only', () {
      expect(jobDraftWatermark({'template_key': 'template2', 'job_status': 'Draft'}), isTrue);
      expect(jobDraftWatermark({'template_key': 'template2', 'job_status': 'Open'}), isFalse);
      expect(jobDraftWatermark({'template_key': 'template1', 'job_status': 'Draft'}), isFalse);
      expect(jobDraftWatermark({'job_status': 'Draft'}), isFalse);
    });
  });

  testWidgets('quotation preview: draft → big DRAFT over every page; the downloaded PDF is the server file', (tester) async {
    await pump(tester, DocumentPreviewScreen(source: quotationDocumentSource(qt('none', 'เปิดใบเสนอราคา'))), {
      'GET /api/quotation/5/birt-pdf': pdf('birt'),
      'GET /api/settings/quotation': settingsOn,
    });
    expect(find.byKey(const ValueKey('doc-page-1')), findsOneWidget);
    expect(find.byKey(_wm), findsNWidgets(2));
    expect(find.descendant(of: find.byKey(const ValueKey('doc-page-0')), matching: find.text('DRAFT')), findsOneWidget);
    final t = tester.widget<Text>(find.byKey(_wm).first);
    expect(t.style?.color, DocDraftWatermark.color);
    await tester.tap(find.byKey(const ValueKey('doc-download')));
    await settle(tester, 3);
    expect(saved, ['QT-5.pdf:%PDF-1.4 birt']);
  });

  testWidgets('quotation preview: approved → no DRAFT', (tester) async {
    final a = await pump(tester, DocumentPreviewScreen(source: quotationDocumentSource(qt('approved', 'อนุมัติใบเสนอราคา'))), {
      'GET /api/quotation/5/birt-pdf': pdf('birt'),
      'GET /api/settings/quotation': settingsOn,
    });
    expect(find.byKey(const ValueKey('doc-page-0')), findsOneWidget);
    expect(find.byKey(_wm), findsNothing);
    // Approved is decided from the row: no settings call needed.
    expect(a.callKeys, isNot(contains('GET /api/settings/quotation')));
  });

  testWidgets('quotation preview: watermark turned off in the quotation settings → no DRAFT', (tester) async {
    await pump(tester, DocumentPreviewScreen(source: quotationDocumentSource(qt('pending', 'เปิดใบเสนอราคา'))), {
      'GET /api/quotation/5/birt-pdf': pdf('birt'),
      'GET /api/settings/quotation': {
        'config': {
          'document': {'watermark_until_approved': false},
        },
      },
    });
    expect(find.byKey(const ValueKey('doc-page-0')), findsOneWidget);
    expect(find.byKey(_wm), findsNothing);
  });

  testWidgets('quotation preview: settings unreadable → the server default (DRAFT on)', (tester) async {
    await pump(tester, DocumentPreviewScreen(source: quotationDocumentSource(qt('none', 'เปิดใบเสนอราคา'))), {
      'GET /api/quotation/5/birt-pdf': pdf('birt'),
    });
    expect(find.byKey(_wm), findsNWidgets(2));
  });

  testWidgets('the built-in fallback PDF draws its own mark → no overlay on it', (tester) async {
    await pump(
      tester,
      DocumentPreviewScreen(source: quotationDocumentSource(qt('none', 'เปิดใบเสนอราคา'))),
      {
        'GET /api/quotation/5/pdf': pdf('std'),
        'GET /api/settings/quotation': settingsOn,
      },
      status: {'GET /api/quotation/5/birt-pdf': 503},
    );
    await tester.tap(find.byKey(const ValueKey('doc-show-fallback')));
    await settle(tester);
    expect(find.byKey(const ValueKey('doc-page-0')), findsOneWidget);
    expect(find.byKey(_wm), findsNothing);
  });

  testWidgets('job preview: Template-2 Draft → DRAFT; Open → none', (tester) async {
    await pump(tester, DocumentPreviewScreen(source: jobDocumentSource({'id': 19, 'job_no': 'JOB-19', 'template_key': 'template2', 'job_status': 'Draft'})), {
      'GET /api/field-service/jobs/19/birt-pdf': pdf('birt'),
    });
    expect(find.byKey(_wm), findsNWidgets(2));

    await pump(tester, DocumentPreviewScreen(key: UniqueKey(), source: jobDocumentSource({'id': 19, 'job_no': 'JOB-19', 'template_key': 'template2', 'job_status': 'Open'})), {
      'GET /api/field-service/jobs/19/birt-pdf': pdf('birt'),
    });
    expect(find.byKey(const ValueKey('doc-page-0')), findsOneWidget);
    expect(find.byKey(_wm), findsNothing);
  });

  testWidgets('เอกสาร tab: draft quotation pages carry DRAFT; approved do not', (tester) async {
    await pump(
      tester,
      Scaffold(body: SingleChildScrollView(child: RecordDocumentTab(module: 'quotation', row: {...qt('none', 'เปิดใบเสนอราคา'), 'id': 7}))),
      {
        'GET /api/quotation/7/birt-pdf': pdf('birt'),
        'GET /api/quotation/7/email-log': {'items': []},
        'GET /api/settings/quotation': settingsOn,
      },
    );
    expect(find.byKey(const ValueKey('doc-tab-page-0')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('doc-tab-page-0')), matching: find.byKey(_wm)), findsOneWidget);

    RecordDocumentTab.clearCache();
    await pump(
      tester,
      Scaffold(body: SingleChildScrollView(child: RecordDocumentTab(key: UniqueKey(), module: 'quotation', row: {...qt('approved', 'อนุมัติใบเสนอราคา'), 'id': 7}))),
      {
        'GET /api/quotation/7/birt-pdf': pdf('birt'),
        'GET /api/quotation/7/email-log': {'items': []},
        'GET /api/settings/quotation': settingsOn,
      },
    );
    expect(find.byKey(const ValueKey('doc-tab-page-0')), findsOneWidget);
    expect(find.byKey(_wm), findsNothing);
  });
}
