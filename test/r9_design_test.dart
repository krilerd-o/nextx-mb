import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/core/entity_display.dart';
import 'package:nextx_mobile/widgets/app_bottom_sheet.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';
import 'package:nextx_mobile/widgets/nx_streaming_text.dart';
import 'package:nextx_mobile/widgets/nx_tab_nav.dart';

void main() {
  test('effects level follows preference and reduce-motion', () {
    expect(Effects.resolve(EffectsPreference.full), EffectsLevel.full);
    expect(Effects.resolve(EffectsPreference.lite), EffectsLevel.lite);
    expect(Effects.resolve(EffectsPreference.full, reduceMotion: true), EffectsLevel.off);
  });

  test('theme is built once per brightness + accent (no rebuild on notify)', () {
    final a = AppTheme.themed(brightness: Brightness.light, accent: const Color(0xFF6366F1));
    final b = AppTheme.themed(brightness: Brightness.light, accent: const Color(0xFF6366F1));
    expect(identical(a, b), isTrue);
    expect(identical(a, AppTheme.themed(brightness: Brightness.dark, accent: const Color(0xFF6366F1))), isFalse);
  });

  test('unnamed lead shows its running number', () {
    expect(entityTitle({'id': 1, 'lead_no': 'L26110700001'}, module: 'lead'), 'L26110700001');
  });

  testWidgets('streaming text ends with the full sentence', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: NxStreamingText('มีงานวันนี้ 3 รายการ')),
    ));
    await tester.pumpAndSettle();
    final rich = tester.widget<Text>(find.byType(Text).first);
    expect(rich.textSpan!.toPlainText(), 'มีงานวันนี้ 3 รายการ');
  });

  testWidgets('tab bar card is non-interactive in preview mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Center(
          child: NxTabBarCard(selectedIndex: 0, destinations: [
            NxTabDestination(icon: NxI.squaresFour, selectedIcon: NxI.squaresFourFill, label: 'หน้าหลัก'),
            NxTabDestination(icon: NxI.handshake, selectedIcon: NxI.handshake, label: 'ลีด/ดีล'),
          ]),
        ),
      ),
    ));
    expect(find.text('หน้าหลัก'), findsOneWidget);
    expect(find.text('ลีด/ดีล'), findsOneWidget);
  });

  testWidgets('app bottom sheet opens with title and closes on barrier', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAppBottomSheet<void>(context: context, title: 'ตัวเลือก', child: const Text('เนื้อหา')),
            child: const Text('เปิด'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    expect(find.text('ตัวเลือก'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('ตัวเลือก'), findsNothing);
  });
}
