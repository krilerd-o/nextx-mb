import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/approvals/approvals_screen.dart';
import 'package:nextx_mobile/screens/commerce/commerce_home_screen.dart';
import 'package:nextx_mobile/screens/mail/mail_home_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/fake_api.dart';

Future<AppConfig> _pump(
  WidgetTester tester,
  Widget screen,
  SessionState session,
  FakeNextxAdapter adapter,
) async {
  SharedPreferences.setMockInitialValues({});
  final config = AppConfig();
  config.debugOverrideSession(session);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(home: screen),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('approvals shows only quotations waiting for me, plus leave', (tester) async {
    final adapter = FakeNextxAdapter({
      'GET /api/entity/quotation': {
        'list': [
          {'id': 1, 'quotation_no': 'QT-MINE', 'approval_state': 'pending', 'approval_level': 1, 'approver_1_user_id': 7},
          {'id': 2, 'quotation_no': 'QT-OTHER', 'approval_state': 'pending', 'approval_level': 1, 'approver_1_user_id': 99},
        ],
      },
      'GET /api/hr/leave-requests': {
        'list': [
          {'id': 5, 'user_name': 'สมหญิง', 'status': 'Pending', 'leave_type_name': 'ลาป่วย', 'start_date': '2026-11-10', 'end_date': '2026-11-11'},
        ],
      },
    });
    await _pump(
      tester,
      const ApprovalsScreen(),
      const SessionState(
        accessToken: 't',
        userId: '7',
        businessId: '1',
        menusLoaded: true,
        menuKeys: ['quotation', 'leave-management'],
      ),
      adapter,
    );
    expect(find.textContaining('QT-MINE'), findsOneWidget);
    expect(find.textContaining('QT-OTHER'), findsNothing);
    expect(find.text('สมหญิง'), findsOneWidget);
    expect(adapter.calls.first.queryParameters['filter_approval_state'], 'pending');
  });

  testWidgets('commerce hides stock tab and mark-paid for members', (tester) async {
    final adapter = FakeNextxAdapter({
      'GET /api/commercial/orders': {
        'list': [
          {'id': 3, 'order_number': 'SO-3', 'grand_total': 1500, 'payment_status': 'unpaid'},
        ],
        'meta': {'queue_counts': {'new_today': 1}},
      },
    });
    await _pump(
      tester,
      const CommerceHomeScreen(),
      const SessionState(
        accessToken: 't',
        userId: '7',
        businessId: '1',
        menusLoaded: true,
        menuKeys: ['mini-store-orders', 'mini-store-stock'],
        businessRole: 'member',
      ),
      adapter,
    );
    expect(find.text('สต็อก'), findsNothing);
    expect(find.text('SO-3'), findsOneWidget);
    expect(find.text('฿1,500.00'), findsOneWidget);
    expect(find.text('รับชำระ'), findsNothing);
    expect(adapter.callKeys.where((k) => k.contains('/stock/')), isEmpty);
  });

  testWidgets('commerce shows stock tab for owners', (tester) async {
    final adapter = FakeNextxAdapter({
      'GET /api/commercial/orders': {'list': [], 'meta': {}},
    });
    await _pump(
      tester,
      const CommerceHomeScreen(),
      const SessionState(
        accessToken: 't',
        userId: '7',
        businessId: '1',
        menusLoaded: true,
        menuKeys: ['mini-store-orders', 'mini-store-stock'],
        businessRole: 'owner',
      ),
      adapter,
    );
    expect(find.text('สต็อก'), findsOneWidget);
  });

  testWidgets('mail inbox marks unread and has compose button', (tester) async {
    final adapter = FakeNextxAdapter({
      'GET /api/mail': {
        'list': [
          {'id': 1, 'subject': 'ประชุม', 'from_first_name': 'Ann', 'read_at': null},
          {'id': 2, 'subject': 'อ่านแล้ว', 'from_first_name': 'Bob', 'read_at': '2026-11-01'},
        ],
        'box': 'inbox',
      },
    });
    await _pump(
      tester,
      const MailHomeScreen(),
      const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['mailbox']),
      adapter,
    );
    expect(find.text('ประชุม'), findsOneWidget);
    expect(find.text('อ่านแล้ว'), findsOneWidget);
    expect(find.byKey(const ValueKey('mail-unread-dot')), findsOneWidget);
    // Wide test surface → header compose button instead of the FAB.
    expect(find.byTooltip('เขียนเมล'), findsOneWidget);
    expect(adapter.calls.firstWhere((c) => c.path == '/api/mail').queryParameters['box'], 'inbox');
  });

  test('401 on a normal call triggers logout callback; login 401 does not', () async {
    var logouts = 0;
    final api = ApiClient(onUnauthorized: () => logouts++, dio: Dio(BaseOptions(baseUrl: 'https://x.test')));
    api.debugSetHttpAdapter(FakeNextxAdapter(
      {},
      statusFor: {'GET /api/me': 401, 'POST /api/auth/login': 401, 'POST /api/auth/otp/email/verify': 401},
    ));
    await expectLater(api.getMe(), throwsA(anything));
    expect(logouts, 1);
    await expectLater(api.login(email: 'a', password: 'b'), throwsA(anything));
    await expectLater(api.verifyEmailOtp(email: 'a', code: '1'), throwsA(anything));
    expect(logouts, 1);
  });
}
