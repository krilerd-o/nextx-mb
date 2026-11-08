import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:nextx_mobile/core/build_target.dart';
import 'package:nextx_mobile/core/auth_errors.dart';
import 'package:nextx_mobile/services/google_auth.dart';

void main() {
  test('default build targets Play Store / iOS', () {
    expect(kStore, 'google');
    expect(isHuaweiBuild, isFalse);
  });

  test('no Google services (Huawei without GBox/microG) reads as a clear hint', () {
    const e = GoogleSignInException(code: GoogleSignInExceptionCode.unknownError, description: 'Google Play services not available');
    expect(looksLikeNoGoogleServices(e), isTrue);
    expect(authErrorMessage(const GoogleAuthError(noGoogleServicesMessage)), contains('GBox'));
    const config = GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError, description: 'Developer console is not set up correctly.');
    expect(looksLikeNoGoogleServices(config), isFalse, reason: 'a wrong SHA-1 is an app setup problem, not a missing Google');
  });
}
