import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/nx_number.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_boxes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_api.dart';

void main() {
  test('numbers have thousands separators', () {
    expect(nxInt(12294), '12,294');
    expect(nxInt('1965'), '1,965');
    expect(nxInt(999), '999');
    expect(nxInt(-1500), '-1,500');
    expect(nxInt(null), '0');
    expect(nxBaht(10250000), '฿10,250,000');
    expect(nxBaht(3500.4), '฿3,500');
  });

  Future<(AppConfig, FakeNextxAdapter)> setup(Map<String, Object?> routes) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final config = AppConfig()
      ..debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: ['deal', 'case']));
    final adapter = FakeNextxAdapter(routes);
    config.apiClient.debugSetHttpAdapter(adapter);
    return (config, adapter);
  }

  testWidgets('sales box asks for my figures only (userId = me)', (tester) async {
    final (config, adapter) = await setup({
      'GET /api/dashboard/sales': {
        'deal': {'openCount': 1600, 'openAmount': 10250000, 'wonCount': 1, 'wonAmount': 0, 'winRate': 1},
        'quotation': {'awaitingCount': 5, 'totalAmount': 3500},
        'modules': ['deal', 'quotation'],
      },
    });
    final figs = (await tester.runAsync(() => SalesPeriodBox.loadFigures(config.apiClient, '2026-11-01', '2026-11-30', me: '7')))!;
    final call = adapter.calls.singleWhere((c) => c.path == '/api/dashboard/sales');
    expect(call.queryParameters['userId'], '7');
    final shown = [for (final f in figs) (f as dynamic).value as String];
    expect(shown.first, '1,600');
    expect((figs.first as dynamic).hint, '฿10,250,000');
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('case box asks for my cases only (owners = me) and formats counts', (tester) async {
    final (config, adapter) = await setup({
      'GET /api/service-dashboard/case-summary': {
        'kpis': {'opened': 12294, 'open_now': 591, 'closed': 158, 'overdue_now': 536},
        'by_status': [{'key': 'waiting', 'count': 1200}],
      },
      'GET /api/service-dashboard/case-performance': {'kpis': {'sla_pct': 87}},
    });
    final figs = (await tester.runAsync(() => CasePeriodBox.loadFigures(config.apiClient, '2026-11-01', '2026-11-08', me: '7')))!;
    for (final p in ['/api/service-dashboard/case-summary', '/api/service-dashboard/case-performance']) {
      expect(adapter.calls.singleWhere((c) => c.path == p).queryParameters['owners'], '7', reason: p);
    }
    final shown = {for (final f in figs) (f as dynamic).label as String: (f as dynamic).value as String};
    expect(shown['เคสทั้งหมด'], '12,294');
    expect(shown['รอปิด'], '1,200');
    expect(shown['SLA'], '87%');
    await tester.pump(const Duration(minutes: 2));
  });
}
