import 'package:dio/dio.dart';

/// Web: null → Dio keeps its default (browser) adapter.
HttpClientAdapter? createTunedHttpAdapter() => null;
