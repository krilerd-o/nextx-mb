// Manual tool: screenshot of the Lead status steps (SHOTS_DIR=… flutter test test_live/r45_shots_test.dart)
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';

final _out = Platform.environment['SHOTS_DIR'] ?? '/tmp';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  testWidgets('lead steps', (tester) async {
    await tester.runAsync(() async {
      await _font('GoogleSans', ['assets/fonts/GoogleSans-Regular.ttf', 'assets/fonts/GoogleSans-SemiBold.ttf', 'assets/fonts/GoogleSans-Bold.ttf']);
      await _font('IBMPlexSansThai', ['assets/fonts/IBMPlexSansThai-Regular.ttf', 'assets/fonts/IBMPlexSansThai-SemiBold.ttf', 'assets/fonts/IBMPlexSansThai-Bold.ttf']);
    });
    const raw = [
      (value: 'New', label: 'ใหม่'),
      (value: 'Contacted', label: 'ติดต่อแล้ว'),
      (value: 'Qualified', label: 'มีศักยภาพ'),
      (value: 'Unqualified', label: 'ไม่มีศักยภาพ'),
      (value: 'Converted', label: 'แปลงเป็นลูกค้าแล้ว'),
      (value: 'Potentials', label: 'มีโอกาส'),
      (value: 'No Potentials', label: 'ไม่มีโอกาส'),
      (value: 'Wait for Convert', label: 'รอแปลง'),
    ];
    tester.view.physicalSize = const Size(1100, 330);
    tester.view.devicePixelRatio = 1;
    for (final dark in [false, true]) {
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ก่อน: ลำดับดิบจาก picklist (สถานะ ติดต่อแล้ว)'),
                EntityStatusStepper(options: raw, current: 'Contacted', onSelect: (_) {}),
                const SizedBox(height: 14),
                const Text('หลัง: สถานะ ติดต่อแล้ว'),
                EntityStatusStepper(options: orderStatusOptions('lead', raw, current: 'Contacted'), current: 'Contacted', onSelect: (_) {}),
                const SizedBox(height: 14),
                const Text('หลัง: แปลงเป็นลูกค้าแล้ว (สถานะสุดท้าย)'),
                EntityStatusStepper(options: orderStatusOptions('lead', raw, current: 'Converted'), current: 'Converted', onSelect: null),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 1.5);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/r45_lead_steps${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
