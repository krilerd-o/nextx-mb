/// QR from the web (ตั้งค่า → ความปลอดภัย → เข้าใช้งานแอปมือถือด้วย QR):
/// `moainext://app/qr-login?s=<server>&c=<one-time code>`.
class QrLoginLink {
  const QrLoginLink({required this.server, required this.code});
  final String server;
  final String code;

  /// Null for anything that is not a MOAI NEXT login QR (other QR codes,
  /// bad server URLs, malformed codes).
  static QrLoginLink? parse(String? raw) {
    final uri = Uri.tryParse((raw ?? '').trim());
    if (uri == null) return null;
    final isApp = uri.scheme == 'moainext' && uri.host == 'app' && uri.path.replaceAll(RegExp(r'/+$'), '') == '/qr-login';
    if (!isApp) return null;
    final s = (uri.queryParameters['s'] ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final c = (uri.queryParameters['c'] ?? '').trim();
    final server = Uri.tryParse(s);
    if (server == null || !(server.scheme == 'https' || server.scheme == 'http') || server.host.isEmpty) return null;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(c)) return null;
    return QrLoginLink(server: s, code: c);
  }
}
