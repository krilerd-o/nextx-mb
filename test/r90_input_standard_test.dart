import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/screens/profile/change_password_screen.dart';
import 'package:nextx_mobile/screens/profile/phone_change_screen.dart';
import 'package:nextx_mobile/screens/profile_edit_screen.dart';
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/nx_field_chrome.dart';
import 'package:nextx_mobile/widgets/fields/nx_form_field.dart';

import 'support/profile_harness.dart';

const _profile = {
  'id': 7,
  'first_name': 'QA',
  'last_name': 'User',
  'first_name_th': 'คิวเอ',
  'last_name_th': 'ผู้ใช้',
  'phone_mobile': '0811111111',
  'phone_work': '',
  'phone_home': '',
  'title': 'Sales',
  'department': 'CRM',
};

/// The decoration a [TextField] is actually drawn with (theme applied).
InputDecoration _effective(WidgetTester tester, Finder field) {
  final f = find.descendant(of: field, matching: find.byType(InputDecorator)).first;
  return tester.widget<InputDecorator>(f).decoration;
}

void _expectStandardBox(InputDecoration d, {String? why}) {
  final enabled = d.enabledBorder;
  expect(enabled, isA<OutlineInputBorder>(), reason: why);
  expect((enabled! as OutlineInputBorder).borderRadius, BorderRadius.circular(NxFieldStyle.radius), reason: why);
  expect(d.focusedBorder, isA<OutlineInputBorder>(), reason: why);
  expect(d.filled, isNot(true), reason: '$why: no filled grey box');
}

void main() {
  for (final b in Brightness.values) {
    test('${b.name}: theme inputDecorationTheme is the Lead form box', () {
      final t = AppTheme.themed(brightness: b);
      final cs = t.colorScheme;
      final it = t.inputDecorationTheme;
      expect(it.filled, isFalse);
      expect(it.isDense, isTrue);
      expect(it.contentPadding, NxFieldStyle.padding());
      for (final border in [it.border, it.enabledBorder, it.focusedBorder, it.errorBorder, it.disabledBorder]) {
        expect(border, isA<OutlineInputBorder>());
        expect((border! as OutlineInputBorder).borderRadius, BorderRadius.circular(NxFieldStyle.radius));
      }
      expect((it.enabledBorder! as OutlineInputBorder).borderSide.color, NxFieldStyle.idleColor(cs));
      expect((it.focusedBorder! as OutlineInputBorder).borderSide.color, cs.primary);
      expect((it.errorBorder! as OutlineInputBorder).borderSide.color, cs.error);
      expect(it.floatingLabelStyle?.color, cs.primary);
    });
  }

  testWidgets('a plain TextField and NxFieldStyle.input match the entity form box and height', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(padding: const EdgeInsets.all(16), children: [
            const NxFormField(uiType: FieldUiType.text, label: 'ชื่อบริษัท', name: 'entity', value: 'ACME', onChanged: _noop),
            TextField(key: const ValueKey('plain'), controller: TextEditingController(text: 'ACME'), decoration: const InputDecoration(labelText: 'ชื่อบริษัท')),
            TextField(
              key: const ValueKey('shared'),
              controller: TextEditingController(text: 'ACME'),
              decoration: NxFieldStyle.input(context, label: 'ชื่อบริษัท', icon: Icons.business, required: true),
            ),
          ]),
        ),
      ),
    ));
    final entity = find.descendant(of: find.byKey(const ValueKey('nx-field-entity')), matching: find.byType(TextField));
    final h = tester.getSize(entity).height;
    for (final k in ['plain', 'shared']) {
      final f = find.byKey(ValueKey(k));
      _expectStandardBox(_effective(tester, f), why: k);
      expect(tester.getSize(f).height, h, reason: '$k is as tall as the Lead form text field');
    }
    expect(find.text('ชื่อบริษัท *'), findsOneWidget, reason: 'required → red * after the label');
  });

  testWidgets('profile edit: outlined boxes with floating labels; มือถือ is the same box with เปลี่ยน', (tester) async {
    await pumpProfilePage(tester, const ProfileEditScreen(), {
      'GET /api/me/profile': {'profile': _profile},
    }, size: const Size(430, 2400));
    for (final k in ['pe-first_name_th', 'pe-last_name_th', 'pe-title', 'pe-department', 'pe-phone_work']) {
      final d = _effective(tester, find.byKey(ValueKey(k)));
      _expectStandardBox(d, why: k);
      expect(d.label, isNotNull, reason: '$k has a floating label');
    }
    expect(find.text('ชื่อ (ไทย) *'), findsOneWidget);
    expect(find.text('ตำแหน่ง'), findsOneWidget);
    final mobile = find.byKey(const ValueKey('pe-mobile'));
    _expectStandardBox(_effective(tester, mobile), why: 'mobile row');
    expect(find.descendant(of: mobile, matching: find.text('081-111-1111')), findsOneWidget);
    expect(find.descendant(of: mobile, matching: find.text('เปลี่ยน')), findsOneWidget);
    expect(find.byType(UnderlineInputBorder), findsNothing);
  });

  testWidgets('change phone + OTP step: outlined boxes with label and icon', (tester) async {
    await pumpProfilePage(tester, const PhoneChangeScreen(currentPhone: '0811111111'), {
      'POST /api/me/phone/otp/request': {'ok': true, 'phone': '0812345678'},
    });
    final phone = _effective(tester, find.byKey(const ValueKey('phone-new')));
    _expectStandardBox(phone, why: 'new phone');
    expect(phone.prefixIcon, isNotNull);
    expect(find.text('เบอร์มือถือใหม่'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('phone-new')), '0812345678');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('phone-request')));
    await tester.pumpAndSettle();
    final code = _effective(tester, find.byKey(const ValueKey('phone-code')));
    _expectStandardBox(code, why: 'otp');
    expect(code.counterText, '');
    expect(find.byKey(const ValueKey('phone-edit')), findsOneWidget, reason: 'edit-number action in the field');
  });

  testWidgets('change password: current-password proof, then new password — outlined boxes + eye toggle', (tester) async {
    await pumpProfilePage(tester, const ChangePasswordScreen(), {
      'GET /api/me/verify/methods': {
        'email': {'available': false},
        'sms': {'available': false},
        'password': {'available': true},
      },
      'POST /api/me/verify/password': {'verify_token': 'vt-pw', 'channel': 'password', 'expires_in': 600},
    });
    await tester.tap(find.byKey(const ValueKey('pw-method-password')));
    await tester.pumpAndSettle();
    _expectStandardBox(_effective(tester, find.byKey(const ValueKey('pw-password'))), why: 'current password');
    await tester.enterText(find.byKey(const ValueKey('pw-password')), 'Old@1234');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pw-confirm')));
    await tester.pumpAndSettle();
    for (final k in ['pw-new', 'pw-confirm']) {
      _expectStandardBox(_effective(tester, find.byKey(ValueKey(k))), why: k);
    }
    expect(find.text('รหัสผ่านใหม่'), findsOneWidget);
    expect(find.byType(NxPasswordToggle), findsWidgets);
  });
}

void _noop(dynamic _) {}
