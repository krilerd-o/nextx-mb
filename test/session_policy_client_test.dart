import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/session_ended.dart';
import 'package:nextx_mobile/services/api_client.dart';

/// Replies with a fixed status / body / headers to every request.
class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.status, this.body, [this.headers = const {}]);
  final int status;
  final Map<String, dynamic> body;
  final Map<String, List<String>> headers;
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...headers,
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_FixedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://crm.example.test'));
  dio.httpClientAdapter = adapter;
  final api = ApiClient(dio: dio);
  api.attachSession(baseUrl: 'https://crm.example.test', accessToken: 'staff-jwt', userId: '9', businessId: '5');
  return api;
}

void main() {
  test('401 with a usage-mode reason keeps why the session ended', () async {
    final info = Uri.encodeComponent(jsonEncode({'reason': 'limit', 'limit': 2, 'client': 'mobile', 'at': '2026-11-18T10:00:00Z'}));
    final api = _client(_FixedAdapter(401, {'status': 'E', 'error_code': 'AUTH_401_REQUIRED', 'message': 'x'}, {
      'x-session-revoked': ['limit'],
      'x-session-revoked-info': [info],
    }));
    var unauthorized = 0;
    api.setOnUnauthorized(() => unauthorized++);
    await expectLater(api.getUsers(), throwsA(anything));
    expect(unauthorized, 1);
    expect(api.lastUnauthorizedRevoked, isTrue);
    expect(api.lastSessionEnded?.reason, 'limit');
    expect(api.lastSessionEnded?.limit, 2);
  });

  test('plain expired token is not reported as revoked', () async {
    final api = _client(_FixedAdapter(401, {'status': 'E', 'error_code': 'AUTH_401_REQUIRED', 'message': 'x'}));
    api.setOnUnauthorized(() {});
    await expectLater(api.getUsers(), throwsA(anything));
    expect(api.lastUnauthorizedRevoked, isFalse);
    expect(api.lastSessionEnded, isNull);
  });

  test('a business security rule (403 IP_NOT_ALLOWED) ends the session with its message', () async {
    final api = _client(_FixedAdapter(403, {'status': 'E', 'error_code': 'IP_NOT_ALLOWED', 'message': 'ใช้งานได้จากเครือข่ายบริษัทเท่านั้น'}));
    SessionEnded? got;
    api.setOnSessionEnded((e) => got = e);
    await expectLater(api.getUsers(), throwsA(anything));
    expect(got?.reason, 'policy:IP_NOT_ALLOWED');
    expect(got?.message, 'ใช้งานได้จากเครือข่ายบริษัทเท่านั้น');
  });

  test('login-config: methods for this domain, null on older servers', () async {
    final adapter = _FixedAdapter(200, {
      'status': 'S',
      'data': {'scope': 'business', 'methods': ['password', 'qr'], 'allow_signup': false},
    });
    final ok = _client(adapter);
    final cfg = await ok.getLoginConfig();
    expect(cfg?['methods'], ['password', 'qr']);
    expect(adapter.calls.single.queryParameters['host'], 'crm.example.test');
    final old = _client(_FixedAdapter(404, {'status': 'E', 'message': 'not found'}));
    expect(await old.getLoginConfig(), isNull);
  });
}
