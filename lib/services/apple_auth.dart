import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Sign in with Apple (iOS) → identity token for NEXTX `POST /api/auth/apple`.
///
/// App Store rule: an app that offers Google / LINE sign-in must offer Apple too.
/// The server checks the token with Apple (audience = the app's bundle id).
class AppleAuth {
  AppleAuth._();

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Returns the identity token, or null when the user cancelled.
  static Future<String?> identityToken() async {
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      return c.identityToken;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw const AppleAuthError('เข้าสู่ระบบด้วย Apple ไม่สำเร็จ ลองใหม่อีกครั้ง');
    } on SignInWithAppleNotSupportedException {
      throw const AppleAuthError('เครื่องนี้ใช้ Sign in with Apple ไม่ได้');
    }
  }
}

class AppleAuthError implements Exception {
  const AppleAuthError(this.message);
  final String message;
  @override
  String toString() => message;
}
