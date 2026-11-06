import 'package:dio/dio.dart';

/// A NEXTX (MOAI NEXT) server the app can sign in to.
///
/// The app is not tied to moainext.moai-crm.com: any host whose
/// `GET /api/health` answers `{app: 'MOAI NEXT API', signature: 'aisystem'}`
/// (backend/src/index.js) is accepted.
class ServerCheckResult {
  const ServerCheckResult({required this.url, required this.ok, this.message, this.maintenance = false});

  final String url;
  final bool ok;
  final String? message;
  final bool maintenance;
}

const kNextxAppName = 'MOAI NEXT API';
const kNextxSignature = 'aisystem';

/// `moainext.example.com` / `https://x.com/` / `https://x.com/api` → `https://x.com`.
/// Keeps an explicit `http://` (local dev) and any port.
String normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return '';
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return '';
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.toLowerCase().endsWith('/api')) path = path.substring(0, path.length - 4);
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port$path';
}

/// Short label for chips: host only (`moainext.moai-crm.com`).
String serverLabel(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// True when a `/api/health` envelope identifies a NEXTX server.
bool isNextxHealth(Object? body) {
  if (body is! Map) return false;
  final data = body['data'];
  if (body['status'] != 'S' || data is! Map) return false;
  return data['app'] == kNextxAppName && data['signature'] == kNextxSignature;
}

/// Calls `{url}/api/health` and checks the NEXTX signature.
Future<ServerCheckResult> verifyNextxServer(String input, {Dio? dio}) async {
  final url = normalizeServerUrl(input);
  if (url.isEmpty) {
    return const ServerCheckResult(url: '', ok: false, message: 'กรุณาใส่ที่อยู่เซิร์ฟเวอร์ให้ถูกต้อง');
  }
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (_) => true,
      ));
  try {
    final res = await client.get<dynamic>('$url/api/health');
    final body = res.data;
    if (isNextxHealth(body)) {
      final data = (body as Map)['data'] as Map;
      return ServerCheckResult(url: url, ok: true, maintenance: data['maintenance'] == true);
    }
    return ServerCheckResult(url: url, ok: false, message: 'เซิร์ฟเวอร์นี้ไม่ใช่ระบบ MOAI NEXT');
  } on DioException catch (e) {
    final msg = switch (e.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => 'เชื่อมต่อเซิร์ฟเวอร์ไม่ทันเวลา',
      DioExceptionType.badCertificate => 'ใบรับรอง SSL ของเซิร์ฟเวอร์ไม่ถูกต้อง',
      _ => 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบที่อยู่และอินเทอร์เน็ต',
    };
    return ServerCheckResult(url: url, ok: false, message: msg);
  } catch (_) {
    return ServerCheckResult(url: url, ok: false, message: 'เซิร์ฟเวอร์นี้ไม่ใช่ระบบ MOAI NEXT');
  }
}

/// Most-recent-first list of distinct servers, capped.
List<String> pushRecentServer(List<String> recent, String url, {int max = 5}) {
  final u = normalizeServerUrl(url);
  if (u.isEmpty) return recent;
  return [u, ...recent.where((e) => e != u)].take(max).toList();
}
