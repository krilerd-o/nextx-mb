import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/build_target.dart';

/// Native Google Sign-In → ID token for NEXTX `POST /api/auth/google/one-tap`.
///
/// The server checks the token's audience against its web client id, so the
/// app passes that id (from `/api/auth/google/one-tap-config`) as
/// `serverClientId`. google_sign_in may only be initialized once per run.
class GoogleAuth {
  GoogleAuth._();

  static String? _initializedWith;

  static bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Returns the ID token, or null when the user cancelled.
  static Future<String?> idToken(String serverClientId) async {
    final gs = GoogleSignIn.instance;
    if (_initializedWith == null) {
      try {
        await gs.initialize(serverClientId: serverClientId);
      } catch (e) {
        // Huawei phones without GBox / microG have no Google services at all.
        if (isHuaweiBuild || '$e'.toLowerCase().contains('google play services')) throw const GoogleAuthError(noGoogleServicesMessage);
        rethrow;
      }
      _initializedWith = serverClientId;
    } else if (_initializedWith != serverClientId) {
      throw StateError('เปลี่ยนเซิร์ฟเวอร์แล้ว กรุณาปิดและเปิดแอปใหม่ก่อนเข้าสู่ระบบด้วย Google');
    }
    try {
      final account = await gs.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      // Every account marked "unusable" / config errors = Google does not know
      // this app build (package + signing SHA-1 not registered for the
      // server's Google project). See docs/GOOGLE_SIGNIN.md.
      if (looksLikeNoGoogleServices(e)) throw const GoogleAuthError(noGoogleServicesMessage);
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw GoogleAuthError(
          'เข้าสู่ระบบด้วย Google ไม่ได้ เพราะแอปเวอร์ชันนี้ยังไม่ได้ลงทะเบียนกับ Google ของเซิร์ฟเวอร์ — แจ้งผู้ดูแลระบบ (รหัส: ${e.code.name})',
        );
      }
      throw GoogleAuthError('เข้าสู่ระบบด้วย Google ไม่สำเร็จ (${e.code.name}) ลองอีกครั้ง หรือใช้อีเมล/OTP');
    }
  }
}

/// Shown when the phone has no Google services (e.g. Huawei without GBox /
/// microG). The Google button stays visible on every Android build because
/// those apps can make Google sign-in work.
const noGoogleServicesMessage =
    'เครื่องนี้ไม่มีบริการ Google — ติดตั้ง GBox หรือ microG หรือเข้าสู่ระบบด้วย LINE / OTP';

/// Errors that mean "no Google services on this device" rather than a
/// misconfigured app: Credential Manager has no Google provider, or the
/// error text mentions Play services. On a Huawei build any provider error
/// is treated this way.
bool looksLikeNoGoogleServices(GoogleSignInException e) {
  final text = '${e.description ?? ''}'.toLowerCase();
  if (text.contains('play services') || text.contains('no provider') || text.contains('providerconfiguration')) return true;
  return isHuaweiBuild &&
      (e.code == GoogleSignInExceptionCode.providerConfigurationError || e.code == GoogleSignInExceptionCode.uiUnavailable);
}

/// Readable Google sign-in failure (shown as is on the login screen).
class GoogleAuthError implements Exception {
  const GoogleAuthError(this.message);
  final String message;
  @override
  String toString() => message;
}
