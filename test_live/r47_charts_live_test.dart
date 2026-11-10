// Manual tool (not part of `flutter test`): every Home chart against a local
// NEXTX backend (nextx_qa). Read-only — no records are created or changed.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/home_layout.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/dashboard/home_chart_data.dart';
import 'package:nextx_mobile/services/api_client.dart';

void main() {
  test('all 13 charts load and parse (ของฉัน + ทีม)', () async {
    HttpOverrides.global = null; // real network
    final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
    final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
    const session = SessionState(
      accessToken: 't',
      userId: '2',
      businessId: '1',
      businessRole: 'admin',
      menusLoaded: true,
      menuKeys: ['deal', 'quotation', 'lead', 'case', 'calendar', 'workspace', 'leave-request', 'sales-dash-pipeline', 'sales-dash-activity'],
    );
    for (final team in [false, true]) {
      HomeChartCache.instance.clear();
      for (final c in HomeLayout.charts) {
        final periods = c.periods.isEmpty ? [c.defaultPeriod] : c.periods;
        for (final p in periods) {
          final r = ChartRequest(api: api, session: session, entry: HomeEntry(c.id, period: p, team: team), scope: 'live', now: chartNow());
          final d = await loadChartData(r);
          final summary = switch (d) {
            WonData w => 'won=${w.amount} prev=${w.prevAmount} n=${w.count} trend=${w.trend.length}',
            RateData x => 'rate=${x.rate} ${x.aLabel}=${x.a} ${x.bLabel}=${x.b}',
            SeriesData s => 'labels=${s.labels.length} ${s.series.map((k, v) => MapEntry(k, v.fold<double>(0, (a, b) => a + b)))}',
            SlicesData s => 'slices=${s.slices}',
            List<LeaveRow> l => 'leave=${[for (final x in l) '${x.name} ${x.left}/${x.total}']}',
            _ => '$d',
          };
          print('[${team ? 'team' : 'mine'}] ${c.id} $p → $summary');
        }
      }
    }
  });
}
