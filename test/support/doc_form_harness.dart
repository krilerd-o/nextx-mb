import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';

import 'fake_api.dart';

/// Shared harness for the r69 step-form tests.
class DocFormHarness {
  DocFormHarness(this.tester);
  final WidgetTester tester;
  late FakeNextxAdapter adapter;
  late AppConfig config;

  Future<void> settle([int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// [home] gets a context below the providers (e.g. a button that opens the form).
  Future<void> pump(
    Widget home,
    Map<String, Object?> replies, {
    List<String>? menus = const ['quotation', 'job', 'account', 'contact', 'lead', 'product', 'service'],
    Map<String, Object> prefs = const {},
    Size size = const Size(430, 2400),
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    adapter = FakeNextxAdapter(replies);
    config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(SessionState(accessToken: 't', userId: '1', businessId: '1', displayName: 'สมชาย ใจดี', menusLoaded: true, menuKeys: menus));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    await settle(6);
  }

  /// JSON body of the last call to `METHOD path`.
  Map<String, dynamic> body(String method, String path) {
    final c = adapter.calls.lastWhere((c) => c.method.toUpperCase() == method && c.path == path);
    final d = c.data;
    if (d is String) return Map<String, dynamic>.from(jsonDecode(d) as Map);
    return Map<String, dynamic>.from(d as Map);
  }

  bool called(String method, String path) => adapter.callKeys.contains('$method $path');

  Finder field(String name) => find.descendant(of: find.byKey(ValueKey('nx-field-$name')), matching: find.byType(TextField));

  Future<void> type(String name, String text) async {
    await tester.ensureVisible(field(name).first);
    await tester.enterText(field(name).first, text);
    await tester.pump();
  }

  Future<void> tap(Key key, {int settleFrames = 6}) async {
    await tester.ensureVisible(find.byKey(key).first);
    await tester.pump();
    await tester.tap(find.byKey(key).first);
    await settle(settleFrames);
  }

  /// Text inside the widget with [key].
  String textOf(Key key) => tester.widget<Text>(find.byKey(key).first).data ?? '';

  Future<Map<String, String>> prefsNow() async {
    final p = await tester.runAsync(SharedPreferences.getInstance);
    return {for (final k in p!.getKeys()) k: '${p.get(k)}'};
  }
}
