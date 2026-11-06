/// Parse MOAI NEXT API envelope: { status, messagestatus, data?, error_code?, message? }
class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  String get userMessage {
    if (statusCode == 0) return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้';
    if (statusCode == 401) return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    if (body.trim().isEmpty) return 'API $statusCode';
    return 'API $statusCode';
  }

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiEnvelopeException implements Exception {
  ApiEnvelopeException(this.statusCode, this.errorCode, this.message);
  final int statusCode;
  final String errorCode;
  final String message;

  @override
  String toString() => '$errorCode: $message';
}

String formatApiError(Object e) {
  if (e is ApiEnvelopeException) return e.message;
  if (e is ApiException) return e.userMessage;
  return e.toString();
}
