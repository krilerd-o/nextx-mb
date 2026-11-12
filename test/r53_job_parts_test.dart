import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/journey/job_parts.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<(FakeNextxAdapter, List<int>)> pump(WidgetTester tester, List<Map<String, dynamic>> parts, {Map<String, Object?> extra = const {}, Map<String, int> statusFor = const {}}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter({
      'GET /api/field-service/parts/catalog': {'list': [
        {'product_id': 1, 'name': '[QA] คอมเพรสเซอร์', 'code': 'QA-CP', 'unit': 'ชิ้น', 'unit_cost': '1200.00', 'commercial_product_id': 1, 'stock_qty': '10.0000'},
      ]},
      'POST /api/field-service/jobs/19/parts': {'id': 3},
      'DELETE /api/field-service/jobs/19/parts/2': {'ok': true, 'stock_returned': {'quantity': 3, 'balance_after': 10}},
      ...extra,
    }, statusFor: statusFor);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reloads = <int>[];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: JobPartsSection(jobId: '19', parts: parts, canEdit: true, onChanged: () async => reloads.add(1)),
          ),
        ),
      ),
    ));
    await settle(tester, 4);
    return (adapter, reloads);
  }

  Map<String, dynamic> body(FakeNextxAdapter a) {
    final c = a.calls.lastWhere((c) => c.method == 'POST');
    return c.data is String ? jsonDecode(c.data as String) as Map<String, dynamic> : Map<String, dynamic>.from(c.data as Map);
  }

  testWidgets('optional label; pick a stocked product, qty 2 → POST product_id + quantity', (tester) async {
    final (a, reloads) = await pump(tester, const []);
    expect(find.text('ไม่บังคับ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-part-add')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('job-part-name')), 'คอม');
    await settle(tester, 12);
    expect(find.text('คงเหลือ 10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-part-hit-1')));
    await settle(tester, 4);
    expect(find.text('จะตัดสต็อก (คงเหลือ 10)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-part-plus')));
    await settle(tester, 2);
    await tester.tap(find.byKey(const ValueKey('job-part-save')));
    await settle(tester);
    final b = body(a);
    expect([b['product_id'], b['quantity'], b['unit']], [1, 2, 'ชิ้น']);
    expect(reloads, isNotEmpty);
  });

  testWidgets('free text on an older server (no catalog)', (tester) async {
    final (a, _) = await pump(tester, const [], extra: {'GET /api/field-service/parts/catalog': null}, statusFor: {'GET /api/field-service/parts/catalog': 404});
    await tester.tap(find.byKey(const ValueKey('job-part-add')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('job-part-name')), '[QA] สายไฟ 3 เมตร');
    await settle(tester, 12);
    await tester.tap(find.byKey(const ValueKey('job-part-save')));
    await settle(tester);
    expect(body(a), {'description': '[QA] สายไฟ 3 เมตร', 'quantity': 1});
  });

  testWidgets('list shows who / stock; delete returns stock', (tester) async {
    await pump(tester, const [
      {'id': 2, 'product_name': '[QA] คอมเพรสเซอร์', 'quantity': '3.00', 'unit': 'ชิ้น', 'created_by_name': '[QA] Admin', 'created_at': '2026-11-11T04:25:00Z', 'stock_qty_deducted': '3.00'},
    ]);
    expect(find.text('× 3 ชิ้น'), findsOneWidget);
    expect(find.text('ตัดสต็อกแล้ว'), findsOneWidget);
    expect(find.textContaining('[QA] Admin'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-part-del-2')));
    await settle(tester);
    expect(find.text('จำนวนที่ตัดสต็อกไว้จะถูกคืนเข้าสต็อก'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-part-del-ok')));
    await settle(tester);
    expect(find.text('ลบแล้ว และคืนสต็อกแล้ว'), findsOneWidget);
  });
}
