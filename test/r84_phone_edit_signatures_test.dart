import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/profile/my_signatures_screen.dart';
import 'package:nextx_mobile/screens/profile/phone_change_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_manage_screen.dart';
import 'package:nextx_mobile/screens/profile_edit_screen.dart';

import 'support/profile_harness.dart';

const _profile = {
  'id': 7,
  'user_name': 'qa',
  'first_name': 'QA',
  'last_name': 'User',
  'first_name_th': 'คิวเอ',
  'last_name_th': 'ผู้ใช้',
  'email1': 'qa@example.com',
  'phone_mobile': '0811111111',
  'phone_work': '',
  'phone_home': '',
  'title': 'Sales',
  'department': 'CRM',
  'description': '',
  'signature': '',
  'address_street': '',
  'address_city': '',
  'address_state': '',
  'address_country': '',
  'address_postalcode': '',
  'user_language': 'th',
  'hour_format': '24',
  'weekstart': 0,
};

void main() {
  group('เปลี่ยนเบอร์โทรศัพท์', () {
    testWidgets('current number, request OTP for the new one, verify → success with the new number', (tester) async {
      final (_, api) = await pumpProfilePage(tester, const PhoneChangeScreen(currentPhone: '0811111111'), {
        'POST /api/me/phone/otp/request': {'ok': true, 'phone': '0812345678'},
        'POST /api/me/phone/otp/verify': {'ok': true, 'phone_mobile': '0812345678', 'replaced': true, 'message': 'เปลี่ยนเบอร์โทรศัพท์แล้ว'},
      });
      expect(find.text('081-111-1111'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('phone-new')), '081-234-5678');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('phone-request')));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'POST', '/api/me/phone/otp/request'), {'phone': '0812345678'});
      expect(find.text('ขอรหัสใหม่ได้ใน 60 วินาที'), findsOneWidget, reason: 'resend countdown');
      await tester.pump(const Duration(seconds: 61));
      expect(find.text('ส่งรหัสอีกครั้ง'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('phone-code')), '123456');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('phone-verify')));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'POST', '/api/me/phone/otp/verify'), {'phone': '0812345678', 'code': '123456'});
      expect(find.text('เปลี่ยนเบอร์โทรศัพท์แล้ว'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const ValueKey('phone-done-number'))).data, '081-234-5678');
    });

    testWidgets('a number in use (409) and a bad number', (tester) async {
      final (_, api) = await pumpProfilePage(tester, const PhoneChangeScreen(currentPhone: '0811111111'), const {}, status: {'POST /api/me/phone/otp/request': 409}, errors: {
        'POST /api/me/phone/otp/request': {'error_code': 'VALIDATION', 'message': 'เบอร์นี้ถูกใช้กับบัญชีอื่นแล้ว'},
      });
      await tester.enterText(find.byKey(const ValueKey('phone-new')), '12');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('phone-request')));
      await tester.pump();
      expect(find.text('เบอร์มือถือไม่ถูกต้อง (เช่น 0812345678)'), findsOneWidget);
      expect(api.calls.where((c) => c.path == '/api/me/phone/otp/request'), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('phone-new')), '0899999999');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('phone-request')));
      await tester.pumpAndSettle();
      expect(find.text('เบอร์นี้ถูกใช้กับบัญชีอื่นแล้ว'), findsOneWidget);
    });

    testWidgets('wrong code (NEXTX answers 401) shows the error and does not sign out', (tester) async {
      final (config, _) = await pumpProfilePage(tester, const PhoneChangeScreen(currentPhone: '0811111111'), {
        'POST /api/me/phone/otp/request': {'ok': true},
      }, status: {'POST /api/me/phone/otp/verify': 401}, errors: {
        'POST /api/me/phone/otp/verify': {'error_code': 'AUTH_INVALID_CREDENTIALS', 'message': 'เบอร์หรือรหัสยืนยันไม่ถูกต้อง'},
      });
      await tester.enterText(find.byKey(const ValueKey('phone-new')), '0812345678');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('phone-request')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('phone-code')), '000000');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('phone-verify')));
      await tester.pumpAndSettle();
      expect(find.text('เบอร์หรือรหัสยืนยันไม่ถูกต้อง'), findsOneWidget);
      expect(config.isLoggedIn, isTrue);
      await tester.pump(const Duration(seconds: 61));
    });
  });

  group('จัดการโปรไฟล์ / แก้ไขโปรไฟล์', () {
    testWidgets('manage page shows my data and the account menu', (tester) async {
      await pumpProfilePage(tester, const ProfileManageScreen(), {'GET /api/me/profile': {'profile': _profile}}, size: const Size(430, 2400));
      expect(find.text('คิวเอ ผู้ใช้'), findsWidgets);
      expect(find.text('QA User'), findsWidgets);
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('081-111-1111'), findsWidgets);
      expect(find.byKey(const ValueKey('pm-change-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('pm-delete-account')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pm-change-phone')));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneChangeScreen), findsOneWidget);
    });

    testWidgets('edit: only changed fields are PUT (text + choice)', (tester) async {
      final (_, api) = await pumpProfilePage(tester, const ProfileEditScreen(), {
        'GET /api/me/profile': {'profile': _profile},
        'PUT /api/me/profile': _profile,
        'GET /api/me': {},
      }, size: const Size(430, 3000));
      expect(find.byKey(const ValueKey('pe-address_street')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pe-title')), 'Manager');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('pe-weekstart')), matching: find.text('จันทร์')));
      await tester.pump();
      expect(find.text('แก้ไขแล้ว 2 ช่อง · ยังไม่ได้บันทึก'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pe-save')));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/profile'), {'title': 'Manager', 'weekstart': 1});
    });

    testWidgets('edit: validation blocks the save; unsaved changes ask before leaving', (tester) async {
      final (_, api) = await pumpProfilePage(
          tester,
          Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                key: const ValueKey('open-edit'),
                onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const ProfileEditScreen())),
                child: const Text('open'),
              ),
            ),
          ),
          {'GET /api/me/profile': {'profile': _profile}},
          size: const Size(430, 3000));
      await tester.tap(find.byKey(const ValueKey('open-edit')));
      await tester.pumpAndSettle();
      // First touch sets the "unchanged" baseline (like a real user).
      await tester.tap(find.byKey(const ValueKey('pe-first_name_th')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('pe-first_name_th')), '');
      await tester.enterText(find.byKey(const ValueKey('pe-first_name')), '');
      await tester.enterText(find.byKey(const ValueKey('pe-phone_work')), 'abc');
      await tester.tap(find.byKey(const ValueKey('pe-save')));
      await tester.pumpAndSettle();
      expect(find.text('กรุณาใส่ชื่ออย่างน้อยหนึ่งภาษา'), findsOneWidget);
      expect(find.text('เบอร์โทรไม่ถูกต้อง'), findsOneWidget);
      expect(api.callKeys, isNot(contains('PUT /api/me/profile')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nx-discard-dialog')), findsOneWidget);
    });

    testWidgets('edit: fields the server does not return are hidden', (tester) async {
      await pumpProfilePage(tester, const ProfileEditScreen(), {
        'GET /api/me/profile': {'profile': {'first_name': 'QA', 'last_name': 'User', 'title': ''}},
      });
      expect(find.byKey(const ValueKey('pe-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('pe-address_street')), findsNothing);
      expect(find.byKey(const ValueKey('pe-weekstart')), findsNothing);
    });
  });

  group('จัดการลายเซ็น', () {
    testWidgets('เซ็นใหม่ → the signing page PNG is uploaded and saved for that language', (tester) async {
      String? title;
      final (_, api) = await pumpProfilePage(
        tester,
        MySignaturesScreen(padLauncher: (_, t) async {
          title = t;
          return [137, 80, 78, 71];
        }),
        {
          'GET /api/me/signatures': {'upload_signature_th': null, 'upload_signature_en': null},
          'POST /api/uploads/signature': {'path': 'signatures/s1.png'},
          'PUT /api/me/signatures': {},
        },
      );
      expect(tester.widget<Text>(find.byKey(const ValueKey('sig-status-th'))).data, 'ยังไม่มี');
      await tester.tap(find.byKey(const ValueKey('sig-draw-th')));
      await tester.pumpAndSettle();
      expect(title, 'ลายเซ็นภาษาไทย');
      expect(api.callKeys, containsAllInOrder(['POST /api/uploads/signature', 'PUT /api/me/signatures']));
      expect(bodyOf(api, 'PUT', '/api/me/signatures'), {'upload_signature_th': 'signatures/s1.png'});
    });

    testWidgets('replace asks first; clear asks first; copy to the other language', (tester) async {
      var opened = 0;
      final (_, api) = await pumpProfilePage(
        tester,
        MySignaturesScreen(padLauncher: (_, _) async {
          opened++;
          return null;
        }),
        {
          'GET /api/me/signatures': {'upload_signature_th': 'signatures/th.png', 'signatureUrlTh': '/uploads/signatures/th.png', 'upload_signature_en': null},
          'PUT /api/me/signatures': {},
        },
      );
      expect(tester.widget<Text>(find.byKey(const ValueKey('sig-status-th'))).data, 'บันทึกแล้ว');
      await tester.tap(find.byKey(const ValueKey('sig-draw-th')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sig-replace-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sig-replace-ok')));
      await tester.pumpAndSettle();
      expect(opened, 1);

      await tester.tap(find.byKey(const ValueKey('sig-copy-en')));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/signatures'), {'upload_signature_en': 'signatures/th.png'});

      await tester.tap(find.byKey(const ValueKey('sig-clear-th')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();
      expect(bodyOf(api, 'PUT', '/api/me/signatures'), {'clear_th': true});
    });
  });

  test('phone helpers', () {
    expect(normalizePhone('+66 81 234 5678'), '0812345678');
    expect(phoneProblem('0811111111', current: '081-111-1111'), 'เป็นเบอร์เดิมอยู่แล้ว');
    expect(phoneProblem('0812345678'), isNull);
    expect(formatPhone('0812345678'), '081-234-5678');
  });
}
