import '../services/api_client.dart';

/// Friendly Thai text for NEXTX auth error codes (backend errorHandler / authLimiter).
String authErrorMessage(Object e) {
  if (e is ApiEnvelopeException) {
    final code = e.errorCode.toUpperCase();
    if (code.contains('PENDING_APPROVAL')) return 'บัญชีของคุณกำลังรอผู้ดูแลระบบอนุมัติ';
    if (code.contains('SUSPENDED')) return 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแลระบบ';
    if (code.contains('RATE_LIMIT') || e.statusCode == 429) return 'ลองหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่';
    if (code.contains('INVALID_CREDENTIALS')) return 'อีเมล/ชื่อผู้ใช้ หรือรหัสผ่านไม่ถูกต้อง';
    if (code.contains('OTP')) return e.message.isNotEmpty ? e.message : 'รหัส OTP ไม่ถูกต้องหรือหมดอายุ';
    return e.message.isNotEmpty ? e.message : 'เข้าสู่ระบบไม่สำเร็จ';
  }
  if (e is ApiException && e.statusCode == 429) return 'ลองหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่';
  if (e is ApiException && e.statusCode == 401) return 'อีเมล/ชื่อผู้ใช้ หรือรหัสผ่านไม่ถูกต้อง';
  return formatApiError(e);
}

/// Thrown when an OTP/LINE sign-in needs the user to confirm linking accounts.
class LinkConfirmRequired implements Exception {
  const LinkConfirmRequired(this.intentToken, {this.method});
  final String intentToken;
  final String? method;
}

/// Thrown when Google sign-in matches an existing account that must be merged.
class GoogleMergeRequired implements Exception {
  const GoogleMergeRequired(this.intentToken);
  final String intentToken;
}
