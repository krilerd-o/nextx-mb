import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/services/api_client.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.replies);
  final Map<String, Map<String, dynamic>> replies;
  final calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final key = '${options.method.toUpperCase()} ${options.path}';
    final body = replies[key] ??
        {
          'status': 'E',
          'error_code': 'NOT_MOCKED',
          'message': key,
        };
    final httpStatus = body['status'] == 'E' ? 400 : 200;
    return ResponseBody.fromString(
      jsonEncode(body),
      httpStatus,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://moainext.moai-crm.com'));
  dio.httpClientAdapter = adapter;
  return ApiClient(dio: dio);
}

void main() {
  test('login posts /api/auth/login and returns token data', () async {
    final adapter = _RecordingAdapter({
      'POST /api/auth/login': {
        'status': 'S',
        'data': {'token': 'jwt-1', 'user': {'id': 9}},
      },
    });
    final api = _client(adapter);
    final data = await api.login(email: 'a@b.c', password: 'secret');
    expect(data['token'], 'jwt-1');
    expect(adapter.calls.single.path, '/api/auth/login');
    expect(adapter.calls.single.method, 'POST');
    expect(adapter.calls.single.headers['Authorization'], isNull);
  });

  test('entity list sends Bearer and X-Business-Id, not X-User-Id', () async {
    final adapter = _RecordingAdapter({
      'GET /api/entity/lead': {
        'status': 'S',
        'data': {
          'list': [
            {'id': 1, 'lastname': 'Lead'}
          ],
          'total': 1,
        },
      },
    });
    final api = _client(adapter);
    api.attachSession(
      baseUrl: 'https://moainext.moai-crm.com',
      accessToken: 'staff-jwt',
      userId: '99',
      businessId: '12',
    );
    final page = await api.getEntityList('lead', limit: 30, page: 1);
    expect(page.items.single['id'], 1);
    final headers = adapter.calls.single.headers;
    expect(headers['Authorization'], 'Bearer staff-jwt');
    expect(headers['X-Business-Id'], '12');
    expect(headers.containsKey('X-User-Id'), isFalse);
  });

  test('checkin posts location string', () async {
    final adapter = _RecordingAdapter({
      'POST /api/activity/7/checkin': {
        'status': 'S',
        'data': {'ok': true},
      },
    });
    final api = _client(adapter);
    await api.activityCheckin('7', lat: 13.7, lng: 100.5);
    expect(adapter.calls.single.data, {'location': '13.7,100.5'});
  });

  test('getUsers hits /api/users', () async {
    final adapter = _RecordingAdapter({
      'GET /api/users': {
        'status': 'S',
        'data': {
          'list': [
            {'id': 1, 'first_name': 'สมชาย', 'last_name': 'ใจดี'},
          ],
        },
      },
    });
    final api = _client(adapter);
    api.attachSession(
      baseUrl: 'https://moainext.moai-crm.com',
      accessToken: 'jwt',
      businessId: '12',
    );
    final users = await api.getUsers(q: 'สม');
    expect(users.single['id'], 1);
    expect(adapter.calls.single.path, '/api/users');
    expect(adapter.calls.single.queryParameters['q'], 'สม');
  });

  test('clock-in posts GPS payload', () async {
    final adapter = _RecordingAdapter({
      'POST /api/hr/attendance/clock-in': {
        'status': 'S',
        'data': {'clock_in_at': '2026-10-28T09:00:00'},
      },
    });
    final api = _client(adapter);
    final data = await api.clockIn(latitude: 13.1, longitude: 100.2, address: 'BKK');
    expect(data['clock_in_at'], isNotEmpty);
    expect(adapter.calls.single.data['latitude'], 13.1);
    expect(adapter.calls.single.data['longitude'], 100.2);
  });
}
