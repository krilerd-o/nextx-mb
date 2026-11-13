import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/auth_errors.dart';
import 'package:nextx_mobile/services/api_client.dart';

import 'support/profile_harness.dart';

void main() {
  test('signing in to a closed (Inactive) account shows the server\'s message', () {
    final e = ApiEnvelopeException(403, 'AUTH_403_ACCOUNT_SUSPENDED', 'บัญชีนี้ถูกปิดใช้งาน ติดต่อผู้ดูแลระบบ', details: {'status': 'Inactive'});
    expect(authErrorMessage(e), 'บัญชีนี้ถูกปิดใช้งาน ติดต่อผู้ดูแลระบบ');
    expect(authErrorMessage(ApiEnvelopeException(403, 'AUTH_403_ACCOUNT_SUSPENDED', '')), 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแลระบบ');
  });

  testWidgets('after closing the account the login screen shows the notice once', (tester) async {
    final (config, _) = await pumpProfilePage(tester, const SizedBox(), const {'POST /api/auth/logout': {}});
    await tester.runAsync(() => config.signOutDeletedAccount(notice: 'ปิดบัญชีแล้ว — ติดต่อผู้ดูแลระบบหากต้องการเปิดใช้งานอีกครั้ง'));
    expect(config.isLoggedIn, isFalse);
    expect(config.loginNotice, isNotNull);
    final notice = config.takeLoginNotice();
    expect(notice, 'ปิดบัญชีแล้ว — ติดต่อผู้ดูแลระบบหากต้องการเปิดใช้งานอีกครั้ง');
    expect(config.takeLoginNotice(), isNull, reason: 'shown once');
  });
}
