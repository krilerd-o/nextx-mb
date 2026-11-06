import 'package:alice/alice.dart';
import 'package:alice/model/alice_configuration.dart';
import 'package:alice_dio/alice_dio_adapter.dart';
import 'package:alice_http/alice_http_adapter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// เปิดเมื่อ debug หรือ build ด้วย `--dart-define=ENABLE_ALICE=true` (ดู API แบบเดียวกับแอป Alice)
bool get _aliceEnabled =>
    kDebugMode || const bool.fromEnvironment('ENABLE_ALICE', defaultValue: false);

/// ใช้ key ตัวเดียวกับ [MaterialApp.navigatorKey] และ Alice — ลดโอกาส getContext() เป็น null
final GlobalKey<NavigatorState> _aliceNavigatorKey = GlobalKey<NavigatorState>();

Alice? _alice;
AliceHttpAdapter? _httpAdapter;
AliceDioAdapter? _dioAdapter;

/// เรียกครั้งเดียวจาก `main()` ก่อน `runApp`
void initAppAlice() {
  if (!_aliceEnabled) return;
  if (kIsWeb) return;
  _httpAdapter = AliceHttpAdapter();
  _dioAdapter = AliceDioAdapter();
  _alice = Alice(
    configuration: AliceConfiguration(
      navigatorKey: _aliceNavigatorKey,
      showNotification: true,
      showInspectorOnShake: true,
    ),
  );
  _alice!.addAdapter(_httpAdapter!);
  _alice!.addAdapter(_dioAdapter!);
}

AliceHttpAdapter? get appAliceHttpAdapter => _httpAdapter;

Interceptor? get appAliceDioInterceptor => _aliceEnabled ? _dioAdapter : null;

bool get appAliceActive => _alice != null;

GlobalKey<NavigatorState>? get appAliceNavigatorKey =>
    _aliceEnabled ? _aliceNavigatorKey : null;

void showAliceInspector() {
  final a = _alice;
  if (a == null) return;
  // รอให้ Navigator / Overlay พร้อม (Alice ใช้ overlay.context)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    a.showInspector();
  });
}
