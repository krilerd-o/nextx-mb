// Manual live check (QA backend on :4000): the document preview downloads the
// real PDFs and shows real pages (rendered with pdftoppm here; the app uses
// the printing plugin). QA_TOKEN_FILE=… SHOTS_DIR=… flutter test test_live/r54_doc_live_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/docs/document_preview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'http://127.0.0.1:4000';
final _out = Platform.environment['SHOTS_DIR'] ?? '/tmp';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
  final got = <String>[];

  setUpAll(() async {
    final pc = '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.1/assets/build_font';
    await _font('GoogleSans', ['assets/fonts/GoogleSans-Regular.ttf', 'assets/fonts/GoogleSans-Medium.ttf', 'assets/fonts/GoogleSans-SemiBold.ttf', 'assets/fonts/GoogleSans-Bold.ttf']);
    await _font('IBMPlexSansThai', ['assets/fonts/IBMPlexSansThai-Regular.ttf', 'assets/fonts/IBMPlexSansThai-Medium.ttf', 'assets/fonts/IBMPlexSansThai-SemiBold.ttf', 'assets/fonts/IBMPlexSansThai-Bold.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide300', ['$pc/LucideVariable-w300.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide500', ['$pc/LucideVariable-w500.ttf']);
    // Real pages: pdftoppm → PNG → image.
    DocPreviewHooks.render = (bytes, dpi) async* {
      final dir = Directory.systemTemp.createTempSync('doc');
      File('${dir.path}/d.pdf').writeAsBytesSync(bytes);
      got.add('${bytes.length}');
      Process.runSync('pdftoppm', ['-r', '110', '-png', '${dir.path}/d.pdf', '${dir.path}/p']);
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
        yield (await codec.getNextFrame()).image;
      }
    };
  });

  for (final dark in [false, true]) {
    testWidgets('document preview live dark=$dark', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      HttpOverrides.global = null;
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      config.debugOverrideSession(SessionState(accessToken: token, userId: '1', businessId: '1', menusLoaded: true, menuKeys: const ['job', 'quotation']));
      await tester.runAsync(() => config.setApiBaseUrl(_base));
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> frames([int n = 30]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
      Future<void> shot(String name) async {
        final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        await tester.runAsync(() async {
          final i = await ro.toImage(pixelRatio: 1.5);
          final b = await i.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/r54_$name${dark ? '_dark' : ''}.png').writeAsBytesSync(b!.buffer.asUint8List());
        });
      }
      Widget app(Widget home) => ChangeNotifierProvider.value(
            value: config,
            child: RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(key: UniqueKey(), theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: home)),
          );

      // Job 19 ([QA]): QA has no BIRT server → standard PDF + notice.
      await tester.pumpWidget(app(DocumentPreviewScreen(source: jobDocumentSource(const {'id': 19, 'job_no': 'JOB-19 [QA]'}))));
      await frames();
      expect(find.byKey(const ValueKey('doc-fallback-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('doc-page-0')), findsOneWidget);
      await shot('doc_job');
      if (dark) {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
        return;
      }

      final center = tester.getCenter(find.byKey(const ValueKey('doc-page-0')));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await frames(8);
      expect(find.text('250%'), findsOneWidget);
      await shot('doc_job_zoom');

      // Quotation 6: template variants (th/en) and English black & white.
      got.clear();
      await tester.pumpWidget(app(DocumentPreviewScreen(source: quotationDocumentSource(const {'id': 6, 'quotation_no': 'QT-6', 'template_id': 1}))));
      await frames();
      expect(find.byKey(const ValueKey('doc-variant-birt-en-bw')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('doc-variant-birt-en-bw')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('doc-variant-birt-en-bw')));
      await frames(45);
      debugPrint('R54 quotation pdf sizes: $got');
      expect(got.length, 2);
      expect(got[0] != got[1], isTrue, reason: 'English B/W differs from Thai colour');
      await shot('doc_qt_en_bw');

      await tester.pumpWidget(app(Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: Center(child: DocumentCard(source: () => quotationDocumentSource(const {'id': 6, 'quotation_no': 'QT-6'})))))));
      await frames(6);
      await shot('doc_card');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }
}
