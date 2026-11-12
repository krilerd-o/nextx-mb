import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Replies to `"METHOD /path"` with a NEXTX S/E envelope; records every call.
class FakeNextxAdapter implements HttpClientAdapter {
  FakeNextxAdapter(this.replies, {this.statusFor = const {}, this.headersFor = const {}, this.sseFor = const {}, Set<String>? offline})
      : offline = offline ?? <String>{};

  /// `METHOD /path` that fail like a lost connection (no response). Mutable.
  final Set<String> offline;

  final Map<String, Object?> replies;
  final Map<String, int> statusFor;

  /// Extra response headers per `METHOD /path` (e.g. `x-session-token`).
  final Map<String, Map<String, String>> headersFor;
  /// Raw `text/event-stream` bodies per `METHOD /path` (AI chat stream).
  final Map<String, String> sseFor;
  final calls = <RequestOptions>[];

  /// Optional: runs before each reply (tests can change [replies] per call).
  void Function(RequestOptions options)? onRequest;

  List<String> get callKeys => [for (final c in calls) '${c.method.toUpperCase()} ${c.path}'];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    onRequest?.call(options);
    final key = '${options.method.toUpperCase()} ${options.path}';
    if (offline.contains(key)) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'offline');
    }
    final code = statusFor[key];
    if (sseFor.containsKey(key)) {
      return ResponseBody.fromString(sseFor[key]!, code ?? 200, headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      });
    }
    final raw = replies[key];
    if (raw is Uint8List) {
      // Binary reply (PDF downloads).
      return ResponseBody.fromBytes(raw, code ?? 200, headers: {
        Headers.contentTypeHeader: ['application/pdf'],
      });
    }
    final Object body;
    if (replies.containsKey(key)) {
      body = {'status': 'S', 'messagestatus': 'Success', 'data': replies[key]};
    } else {
      body = {'status': 'E', 'error_code': 'NOT_MOCKED', 'message': key};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      code ?? (replies.containsKey(key) ? 200 : 404),
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in (headersFor[key] ?? const <String, String>{}).entries) e.key: [e.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
