/// Result of watching the LINE login WebView.
class AuthRedirect {
  const AuthRedirect({this.token, this.error, this.linked = false, this.mergeIntent});
  final String? token;
  /// Google browser sign-in found an existing account to merge (`?merge_intent=`).
  final String? mergeIntent;
  final String? error;
  final bool linked;
}

/// NEXTX's LINE (and Google redirect) callback always ends on the web SPA:
/// `{frontend}/login?token=JWT` or `/login?error=line_not_linked`
/// (backend/src/routes/auth.js). Returns null for any other URL so the
/// WebView keeps navigating (LINE's own pages).
AuthRedirect? parseAuthRedirect(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (!path.endsWith('/login')) return null;
  final q = uri.queryParameters;
  final token = q['token'];
  if (token != null && token.isNotEmpty) return AuthRedirect(token: token);
  final merge = q['merge_intent'];
  if (merge != null && merge.isNotEmpty) return AuthRedirect(mergeIntent: merge);
  final error = q['error'];
  if (error != null && error.isNotEmpty) return AuthRedirect(error: error);
  if (q['blocked'] == 'suspended') return const AuthRedirect(error: 'blocked_suspended');
  if (q['line'] == 'linked') return const AuthRedirect(linked: true);
  return null;
}

/// Thai text for `?error=` codes from the NEXTX OAuth callbacks.
String authRedirectErrorText(String code) {
  switch (code) {
    case 'line_not_linked':
      return 'บัญชี LINE นี้ยังไม่ได้ผูกกับผู้ใช้ในระบบ — เข้าสู่ระบบด้วยอีเมลแล้วผูก LINE จากหน้าโปรไฟล์บนเว็บก่อน';
    case 'line_cancelled':
    case 'access_denied':
      return 'ยกเลิกการเข้าสู่ระบบด้วย LINE';
    case 'line_not_configured':
      return 'เซิร์ฟเวอร์นี้ยังไม่ได้ตั้งค่า LINE Login';
    case 'google_denied':
      return 'ยกเลิกการเข้าสู่ระบบด้วย Google';
    case 'google_not_configured':
      return 'เซิร์ฟเวอร์นี้ยังไม่ได้ตั้งค่า Google Sign-In';
    case 'google_email_not_verified':
      return 'อีเมล Google ยังไม่ได้ยืนยัน';
    case 'blocked_suspended':
      return 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแลระบบ';
    default:
      return code.startsWith('line') ? 'เข้าสู่ระบบด้วย LINE ไม่สำเร็จ ($code)' : 'เข้าสู่ระบบไม่สำเร็จ ($code)';
  }
}
