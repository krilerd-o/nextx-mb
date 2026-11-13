import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/session_state.dart';

import 'fake_api.dart';

const profileTestSession = SessionState(
  accessToken: 'main-token',
  userId: '7',
  businessId: '1',
  businessName: 'QA Co',
  displayName: 'QA User',
  email: 'qa@example.com',
  menusLoaded: true,
  menuKeys: ['lead', 'calendar'],
);

/// Pumps [home] (or a GoRouter with [routes]) over a [FakeNextxAdapter]
/// with the test session; returns the config and the adapter.
Future<(AppConfig, FakeNextxAdapter)> pumpProfilePage(
  WidgetTester tester,
  Widget home,
  Map<String, Object?> replies, {
  Map<String, int> status = const {},
  Map<String, Map<String, Object?>>? errors,
  Size size = const Size(430, 1800),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Map<String, Widget Function()> routes = const {},
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final config = AppConfig();
  config.debugOverrideSession(profileTestSession);
  final adapter = FakeNextxAdapter(replies, statusFor: status, errorsFor: errors);
  config.apiClient.debugSetHttpAdapter(adapter);
  final theme = AppTheme.themed(brightness: brightness);
  Widget scaled(BuildContext context, Widget? child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!);
  final Widget app;
  if (routes.isEmpty) {
    app = MaterialApp(theme: theme, home: home, builder: scaled);
  } else {
    app = MaterialApp.router(
      theme: theme,
      builder: scaled,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        for (final r in routes.entries) GoRoute(path: r.key, builder: (_, _) => r.value()),
      ]),
    );
  }
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: app));
  if (settle) await tester.pumpAndSettle(const Duration(milliseconds: 100));
  // Start-up may have read an empty session from secure storage → put it back.
  config.debugOverrideSession(profileTestSession);
  await tester.pump();
  return (config, adapter);
}

/// The JSON body a recorded call sent.
Map<String, dynamic> bodyOf(FakeNextxAdapter a, String method, String path) {
  final c = a.calls.lastWhere((c) => c.method.toUpperCase() == method && c.path == path);
  return Map<String, dynamic>.from(c.data as Map);
}

int callCount(FakeNextxAdapter a, String key) => a.callKeys.where((k) => k == key).length;
