import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/nx_form_field.dart';
import 'package:nextx_mobile/widgets/fields/nx_pick_option.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';

void noop(dynamic _) {}

void main() {
  const opts = [NxPickOption(value: 'a', label: 'ตัวเลือก A', color: Colors.green)];

  final cases = <String, NxFormField>{
    'text-empty': const NxFormField(uiType: FieldUiType.text, label: 'ชื่อ', name: 'text-empty'),
    'text-filled': const NxFormField(uiType: FieldUiType.text, label: 'ชื่อ', name: 'text-filled', value: 'abc', onChanged: noop),
    'email-filled': const NxFormField(uiType: FieldUiType.email, label: 'อีเมล', name: 'email-filled', value: 'a@b.c', onChanged: noop),
    'pick-empty': const NxFormField(uiType: FieldUiType.picklist, label: 'สถานะ', name: 'pick-empty', options: opts, onChanged: noop),
    'pick-filled': const NxFormField(uiType: FieldUiType.picklist, label: 'สถานะ', name: 'pick-filled', value: 'a', options: opts, onChanged: noop),
    'radio-filled': const NxFormField(uiType: FieldUiType.radioGroup, label: 'แบบ', name: 'radio-filled', value: 'a', options: opts, onChanged: noop),
    'owner-empty': const NxFormField(uiType: FieldUiType.owner, label: 'ผู้รับผิดชอบ', name: 'owner-empty', onChanged: noop),
    'owner-filled': const NxFormField(
        uiType: FieldUiType.owner, label: 'ผู้รับผิดชอบ', name: 'owner-filled', value: {'id': '1', 'label': 'สมชาย'}, onChanged: noop),
    'account-filled': const NxFormField(
        uiType: FieldUiType.accountSelect, label: 'บัญชี', name: 'account-filled', value: {'id': '1', 'label': 'ACME'}, onChanged: noop),
    'date-empty': const NxFormField(uiType: FieldUiType.date, label: 'วันที่', name: 'date-empty', onChanged: noop),
    'date-filled': const NxFormField(uiType: FieldUiType.date, label: 'วันที่', name: 'date-filled', value: '2026-01-02', onChanged: noop),
    'multi-empty': const NxFormField(uiType: FieldUiType.multiSelect, label: 'หลายค่า', name: 'multi-empty', options: opts, onChanged: noop),
    'multi-filled': const NxFormField(uiType: FieldUiType.multiSelect, label: 'หลายค่า', name: 'multi-filled', value: 'a', options: opts, onChanged: noop),
    'color-filled': const NxFormField(uiType: FieldUiType.color, label: 'สี', name: 'color-filled', value: '#22AA55', onChanged: noop),
  };

  Future<Map<String, double>> measure(WidgetTester tester, ThemeData theme, {double scale = 1}) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(420, 2400), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              for (final w in cases.values) Padding(padding: const EdgeInsets.all(4), child: w),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    return {
      for (final k in cases.keys) k: tester.getSize(find.byKey(ValueKey('nx-field-$k'))).height,
    };
  }

  for (final (name, theme, scale) in [
    ('light', AppTheme.light, 1.0),
    ('dark', AppTheme.dark, 1.0),
    ('light, large text', AppTheme.light, 1.3),
  ]) {
    testWidgets('$name: picklist / choice fields with an icon are exactly as tall as a text input', (tester) async {
      final h = await measure(tester, theme, scale: scale);
      final text = h['text-empty']!;
      expect(h['text-filled'], text);
      for (final e in h.entries) {
        expect(e.value, text, reason: '${e.key} = ${e.value}, text input = $text');
      }
    });
  }

  testWidgets('clear (x) sits in the suffix and still clears the value', (tester) async {
    dynamic got = 'unset';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: NxFormField(
          uiType: FieldUiType.picklist,
          label: 'สถานะ',
          name: 'st',
          value: 'a',
          options: opts,
          onChanged: (v) => got = v,
        ),
      ),
    ));
    expect(find.byType(IconButton), findsNothing);
    await tester.tap(find.byIcon(NxI.x));
    expect(got, '');
  });
}
