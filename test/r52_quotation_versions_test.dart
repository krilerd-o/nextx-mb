import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/journey/quotation_versions.dart';

import 'support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('diff', () {
    final a = [
      {'line_no': 1, 'product_id': 5, 'description': 'กล้อง', 'quantity': 4, 'unit_price': 2500},
      {'line_no': 2, 'description': 'ค่าติดตั้ง', 'quantity': 1, 'unit_price': 3000},
      {'line_no': 3, 'description': 'สายแลน', 'quantity': 10, 'unit_price': 50},
    ];
    final b = [
      {'line_no': 1, 'product_id': 5, 'description': 'กล้อง', 'quantity': 6, 'unit_price': 2400},
      {'line_no': 2, 'description': 'ค่าติดตั้ง', 'quantity': 1, 'unit_price': 3000},
      {'line_no': 3, 'description': 'เครื่องบันทึก', 'quantity': 1, 'unit_price': 9000},
    ];
    test('lines: changed / same / removed / added', () {
      final d = diffQuotationLines(a, b);
      expect(d.map((e) => e.change), [LineChange.changed, LineChange.same, LineChange.removed, LineChange.added]);
      expect(d.first.fields, containsAll(['quantity', 'unit_price', 'amount']));
      expect(lineAmount({'quantity': 2, 'unit_price': 100, 'discount_pct': 10}), 180);
    });
    test('headers', () {
      final h = diffQuotationHeaders({'quotation_no': 'Q1', 'grand_total': 10000}, {'quotation_no': 'Q1-R1', 'grand_total': 12000});
      expect(h.where((x) => x.changed).map((x) => x.key), ['quotation_no', 'grand_total']);
    });
  });

  Future<FakeNextxAdapter> pump(WidgetTester tester, Widget home, Map<String, Object?> replies) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    final adapter = FakeNextxAdapter(replies);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    return adapter;
  }

  testWidgets('compare screen highlights what changed', (tester) async {
    await pump(
      tester,
      const QuotationCompareScreen(versions: [
        {'id': 8, 'quotation_no': 'Q26-0001'},
        {'id': 9, 'quotation_no': 'Q26-0001-R1'},
      ], aId: '8', bId: '9'),
      {
        'GET /api/quotation/8/compare/9': {
          'a': {'header': {'quotation_no': 'Q26-0001', 'grand_total': 10000}, 'lines': [{'description': '[QA] กล้อง', 'quantity': 4, 'unit_price': 2500}]},
          'b': {'header': {'quotation_no': 'Q26-0001-R1', 'grand_total': 14400}, 'lines': [{'description': '[QA] กล้อง', 'quantity': 6, 'unit_price': 2400}]},
        },
      },
    );
    expect(find.text('+4,400.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('cmp-h-grand_total')), findsOneWidget);
    expect(find.text('แก้ไข'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('revise: edit lines first in the step form (reason required), then POST revise with fields + lines', (tester) async {
    final a = await pump(
      tester,
      Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => openQuotationRevise(context, {'id': 9, 'quotation_no': 'Q26-0001', 'title_th': '[QA] กล้อง', 'valid_until': '2026-12-01'}), child: const Text('go'))))),
      {
        'GET /api/entity/quotation/9': {'id': 9, 'quotation_no': 'Q26-0001', 'title_th': '[QA] กล้อง', 'customer_name': '[QA] ลูกค้า', 'valid_until': '2026-12-01', 'quote_date': '2026-11-01', 'smownerid': 2},
        'GET /api/quotation/9/lines': {'list': [{'id': 1, 'product_id': 5, 'description': '[QA] กล้อง', 'quantity': 4, 'unit_price': 2500}]},
        'GET /api/quotation/9/revisions': {'list': <Object>[]},
        'POST /api/quotation/9/revise': {'id': 10, 'quotation_no': 'Q26-0001-R1', 'revision_no': 1},
      },
    );
    Future<void> frames() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Finder input(String name) => find.descendant(of: find.byKey(ValueKey('nx-field-$name')), matching: find.byType(TextField)).first;
    await tester.tap(find.text('go'));
    await frames();
    await tester.tap(find.byKey(const ValueKey('docform-step-1')));
    await frames();
    await tester.enterText(input('qline-0-qty'), '6');
    await tester.pump();
    expect(find.text('฿15,000.00'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('qt-add-text-line')));
    await tester.pump();
    await tester.enterText(input('qline-1-desc'), '[QA] ค่าติดตั้ง');
    await tester.enterText(input('qline-1-price'), '3000');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('docform-step-3')));
    await tester.tap(find.byKey(const ValueKey('docform-step-3')));
    await frames();
    await tester.enterText(input('revision_note'), '[QA] เพิ่มกล้อง + ค่าติดตั้ง');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('docform-save')));
    await frames();
    final call = a.calls.lastWhere((c) => c.path == '/api/quotation/9/revise');
    final body = call.data is String ? jsonDecode(call.data as String) as Map : call.data as Map;
    expect(body['fields']['valid_until'], '2026-12-01');
    expect(body['revision_note'], '[QA] เพิ่มกล้อง + ค่าติดตั้ง');
    final lines = body['lines'] as List;
    expect(lines.length, 2);
    expect([lines[0]['product_id'], lines[0]['quantity'], lines[1]['description'], lines[1]['unit_price']], [5, 6, '[QA] ค่าติดตั้ง', 3000]);
  });
}
