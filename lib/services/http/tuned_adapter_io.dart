import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Parallel requests per host (Home / detail screens fire several at once).
const kMaxConnectionsPerHost = 6;

/// How long an idle keep-alive connection is kept for the next request.
const kIdleKeepAlive = Duration(seconds: 30);

/// Android / iOS: one pooled HttpClient — up to [kMaxConnectionsPerHost] sockets per
/// host, kept alive for [kIdleKeepAlive] so the next burst skips the TCP + TLS handshake.
HttpClientAdapter? createTunedHttpAdapter() => IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..maxConnectionsPerHost = kMaxConnectionsPerHost
        ..idleTimeout = kIdleKeepAlive,
    );
