import '../../core/home_layout.dart';
import '../../core/session_state.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';

/// Data for the Home chart widgets: Thai date ranges, request cache (stale
/// while revalidate) and parsers that turn dashboard JSON into chart numbers.
/// Counts from some endpoints arrive as strings — every number goes through [chartNum].

double chartNum(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.replaceAll(',', '').trim()) ?? 0;
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A date range in Thai calendar days.
class ChartRange {
  const ChartRange(this.from, this.to);
  final DateTime from;
  final DateTime to;
  String get fromYmd => _ymd(from);
  String get toYmd => _ymd(to);
  @override
  String toString() => '$fromYmd..$toYmd';
}

/// Range of a period key that contains [now] (week = Monday–Sunday).
ChartRange chartRange(String period, DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  switch (period) {
    case 'week':
      final mon = d.subtract(Duration(days: d.weekday - 1));
      return ChartRange(mon, mon.add(const Duration(days: 6)));
    case 'quarter':
      final q0 = ((d.month - 1) ~/ 3) * 3 + 1;
      return ChartRange(DateTime(d.year, q0, 1), DateTime(d.year, q0 + 3, 0));
    case 'year':
      return ChartRange(DateTime(d.year, 1, 1), DateTime(d.year, 12, 31));
    case 'm6':
      return ChartRange(DateTime(d.year, d.month - 5, 1), DateTime(d.year, d.month + 1, 0));
    case 'm12':
      return ChartRange(DateTime(d.year, d.month - 11, 1), DateTime(d.year, d.month + 1, 0));
    case 'd7':
    case 'd30':
    case 'd90':
      final n = int.parse(period.substring(1));
      return ChartRange(d.subtract(Duration(days: n - 1)), d);
    case 'month':
    default:
      return ChartRange(DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 0));
  }
}

/// The period just before [period] (last week / last month / …), for ▲▼ %.
ChartRange previousRange(String period, DateTime now) {
  final cur = chartRange(period, now);
  switch (period) {
    case 'week':
      return ChartRange(cur.from.subtract(const Duration(days: 7)), cur.to.subtract(const Duration(days: 7)));
    case 'quarter':
      return ChartRange(DateTime(cur.from.year, cur.from.month - 3, 1), DateTime(cur.from.year, cur.from.month, 0));
    case 'year':
      return ChartRange(DateTime(cur.from.year - 1, 1, 1), DateTime(cur.from.year - 1, 12, 31));
    case 'month':
      return ChartRange(DateTime(cur.from.year, cur.from.month - 1, 1), DateTime(cur.from.year, cur.from.month, 0));
    default:
      final len = cur.to.difference(cur.from).inDays + 1;
      return ChartRange(cur.from.subtract(Duration(days: len)), cur.from.subtract(const Duration(days: 1)));
  }
}

const kChartPeriodLabels = <String, String>{
  'week': 'สัปดาห์นี้',
  'month': 'เดือนนี้',
  'quarter': 'ไตรมาสนี้',
  'year': 'ปีนี้',
  'm6': '6 เดือน',
  'm12': '12 เดือน',
  'd7': '7 วัน',
  'd30': '30 วัน',
  'd90': '90 วัน',
};

/// "ทีม" is offered to owners/admins and to anyone who can see other owners
/// (learned from the pipeline dashboard's owner options).
bool canSeeTeam(SessionState s) => s.isBusinessAdmin || HomeChartCache.instance.teamHint;

// ─────────────────────────── cache ───────────────────────────

class _Hit {
  _Hit(this.value, this.at);
  final Object? value;
  final DateTime at;
}

/// Request cache: same request from several widgets = one call; values stay
/// for instant paint and refresh in the background after [ttl].
class HomeChartCache {
  HomeChartCache._();
  static final HomeChartCache instance = HomeChartCache._();
  static Duration ttl = const Duration(minutes: 5);

  final Map<String, _Hit> _hits = {};
  final Map<String, Future<Object?>> _inflight = {};
  bool teamHint = false;

  /// Test hook: counts real loads.
  int loads = 0;

  Object? peek(String key) => _hits[key]?.value;
  bool has(String key) => _hits.containsKey(key);
  bool isFresh(String key) {
    final h = _hits[key];
    return h != null && DateTime.now().difference(h.at) < ttl;
  }

  Future<T> fetch<T>(String key, Future<T> Function() load, {bool force = false}) {
    if (!force && isFresh(key)) return Future.value(_hits[key]!.value as T);
    final running = _inflight[key];
    if (running != null) return running.then((v) => v as T);
    loads++;
    final f = load().then<Object?>((v) {
      _hits[key] = _Hit(v, DateTime.now());
      return v;
    }).whenComplete(() {
      // Block body: returning the removed future here would make it wait on itself.
      _inflight.remove(key);
    });
    _inflight[key] = f;
    return f.then((v) => v as T);
  }

  void clear() {
    _hits.clear();
    _inflight.clear();
    teamHint = false;
    loads = 0;
  }
}

// ─────────────────────────── parsed shapes ───────────────────────────

class ChartSlice {
  const ChartSlice(this.label, this.value, {this.amount = 0});
  final String label;
  final double value;
  final double amount;
  @override
  String toString() => '$label=$value';
}

class WonData {
  const WonData({required this.amount, required this.prevAmount, required this.count, required this.trend, this.target});
  final double amount;
  final double prevAmount;
  final double count;
  final List<double> trend;

  /// Sales target of the period when the server sends one (else null).
  final double? target;

  /// 0..1 towards [target]; null without a target.
  double? get progress => target == null || target! <= 0 ? null : (amount / target!).clamp(0, 1).toDouble();

  /// % change vs the previous period; null when there is nothing to compare.
  double? get deltaPct => prevAmount <= 0 ? null : (amount - prevAmount) / prevAmount * 100;
}

class RateData {
  const RateData({required this.rate, required this.a, required this.b, this.aLabel = '', this.bLabel = ''});

  /// 0..1, or null when nothing to measure.
  final double? rate;
  final double a;
  final double b;
  final String aLabel;
  final String bLabel;
}

class SeriesData {
  const SeriesData({required this.labels, required this.series});
  final List<String> labels;

  /// Series name → one value per label.
  final Map<String, List<double>> series;
  bool get isEmpty => series.values.every((s) => s.every((v) => v == 0));
}

class SlicesData {
  const SlicesData(this.slices);
  final List<ChartSlice> slices;
  double get total => slices.fold(0, (a, s) => a + s.value);
  bool get isEmpty => total <= 0;
}

class LeaveRow {
  const LeaveRow(this.name, this.total, this.used);
  final String name;
  final double total;
  final double used;
  double get left => (total - used).clamp(0, double.infinity).toDouble();
}

// ─────────────────────────── parsers ───────────────────────────

/// `[{name, value}]` → slices (no zeros), biggest first, top [max] + "อื่นๆ".
List<ChartSlice> parseSlices(Object? raw, {String nameKey = 'name', String valueKey = 'value', int max = 5}) {
  final rows = <ChartSlice>[];
  for (final r in extractMapList(raw)) {
    final v = chartNum(r[valueKey] ?? r['count']);
    if (v <= 0) continue;
    var name = '${r[nameKey] ?? r['key'] ?? ''}'.trim();
    if (name.isEmpty || name == '—' || name == '__none__' || name == 'none') name = 'ไม่ระบุ';
    final i = rows.indexWhere((x) => x.label == name);
    if (i >= 0) {
      rows[i] = ChartSlice(name, rows[i].value + v, amount: rows[i].amount + chartNum(r['amount']));
    } else {
      rows.add(ChartSlice(name, v, amount: chartNum(r['amount'])));
    }
  }
  rows.sort((a, b) => b.value.compareTo(a.value));
  if (rows.length <= max) return rows;
  final rest = rows.skip(max - 1).fold<double>(0, (a, s) => a + s.value);
  return [...rows.take(max - 1), ChartSlice('อื่นๆ', rest)];
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

WonData parseWon(Map<String, dynamic> cur, Map<String, dynamic>? prev, {Map<String, dynamic>? trend}) {
  final d = _map(cur['deal']);
  final p = _map(prev?['deal']);
  final t = extractMapList((trend ?? cur)['trend']);
  // Target only when the payload has one (deal.targetAmount / deal.target / target).
  final rawTarget = d['targetAmount'] ?? d['target_amount'] ?? d['target'] ?? cur['targetAmount'] ?? cur['target'];
  final target = rawTarget == null ? 0.0 : chartNum(rawTarget);
  return WonData(
    amount: chartNum(d['wonAmount']),
    prevAmount: chartNum(p['wonAmount']),
    count: chartNum(d['wonCount']),
    trend: [for (final r in t) chartNum(r['won_amount'])],
    target: target > 0 ? target : null,
  );
}

RateData parseWinRate(Map<String, dynamic> sales) {
  final d = _map(sales['deal']);
  final won = chartNum(d['wonCount']);
  final lost = chartNum(d['lostCount']);
  double? rate;
  if (d['winRate'] != null) {
    final r = chartNum(d['winRate']);
    rate = r > 1 ? r / 100 : r;
  } else if (won + lost > 0) {
    rate = won / (won + lost);
  }
  return RateData(rate: rate, a: won, b: lost, aLabel: 'ปิดได้', bLabel: 'ไม่สำเร็จ');
}

const _monthsTh = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

/// "2026-03" → "มี.ค."; "2026-11-09" → "9/11".
String chartKeyLabel(String key) {
  final p = key.split('-');
  if (p.length == 2) {
    final m = int.tryParse(p[1]) ?? 1;
    return _monthsTh[(m - 1).clamp(0, 11)];
  }
  if (p.length >= 3) return '${int.tryParse(p[2]) ?? p[2]}/${int.tryParse(p[1]) ?? p[1]}';
  return key;
}

SeriesData parseSalesTrend(Map<String, dynamic> sales) {
  final t = extractMapList(sales['trend']);
  return SeriesData(
    labels: [for (final r in t) chartKeyLabel('${r['month'] ?? r['key'] ?? ''}')],
    series: {'ยอดปิดการขาย': [for (final r in t) chartNum(r['won_amount'])]},
  );
}

/// Open pipeline by stage (closed stages left out), keeping the server order.
List<ChartSlice> parsePipeline(Map<String, dynamic> sales) {
  final out = <ChartSlice>[];
  for (final r in extractMapList(_map(sales['deal'])['byStage'])) {
    final name = '${r['name'] ?? r['key'] ?? ''}';
    if (name.toLowerCase().startsWith('closed')) continue;
    out.add(ChartSlice(name.isEmpty || name == '—' ? 'ไม่ระบุ' : name, chartNum(r['value'] ?? r['count']), amount: chartNum(r['amount'])));
  }
  return out;
}

const kCloseWindowLabels = {
  'overdue': 'เลยกำหนด',
  'd0_7': '≤ 7 วัน',
  'd8_30': '8–30 วัน',
  'd31_90': '31–90 วัน',
  'd90p': '> 90 วัน',
};

List<ChartSlice> parseCloseWindow(Map<String, dynamic> pipeline) {
  final rows = {for (final r in extractMapList(pipeline['close_window'])) '${r['key']}': r};
  return [
    for (final e in kCloseWindowLabels.entries)
      ChartSlice(e.value, chartNum(rows[e.key]?['count']), amount: chartNum(rows[e.key]?['amount'])),
  ];
}

RateData parseLeadConversion(Map<String, dynamic> customer) {
  final k = _map(_map(customer['lead'])['kpis']);
  final created = chartNum(k['created']);
  final converted = chartNum(k['converted']);
  double? rate;
  if (k['conversion_rate'] != null) {
    final r = chartNum(k['conversion_rate']);
    rate = r > 1 ? r / 100 : r;
  } else if (created > 0) {
    rate = converted / created;
  }
  return RateData(rate: created <= 0 && converted <= 0 ? null : rate, a: converted, b: created, aLabel: 'แปลงแล้ว', bLabel: 'Lead ใหม่');
}

RateData parseSla(Map<String, dynamic> sla) {
  final c = _map(sla['counts']);
  final met = chartNum(c['met']);
  final missed = chartNum(c['missed']);
  double? rate;
  if (sla['compliance_pct'] != null) {
    rate = chartNum(sla['compliance_pct']) / 100;
  } else if (met + missed > 0) {
    rate = met / (met + missed);
  }
  return RateData(rate: rate, a: met, b: missed, aLabel: 'ทันเวลา', bLabel: 'เกินเวลา');
}

/// `/sales-dashboard/activity` trend `[{key, counts{done, missed, upcoming}}]`.
SeriesData parseActivityTrend(Map<String, dynamic> act) {
  final t = extractMapList(act['trend']);
  List<double> col(String k) => [for (final r in t) chartNum(_map(r['counts'])[k] ?? r[k])];
  return SeriesData(
    labels: [for (final r in t) chartKeyLabel('${r['key'] ?? ''}')],
    series: {'เสร็จ': col('done'), 'พลาด': col('missed'), 'กำลังมา': col('upcoming')},
  );
}

/// `/home/work?scope=insights` → created vs cleared per week.
SeriesData parseWorkWeeks(Map<String, dynamic> ins) {
  final t = extractMapList(ins['work_weeks']);
  return SeriesData(
    labels: [for (final r in t) chartKeyLabel('${r['week'] ?? ''}')],
    series: {
      'สร้าง': [for (final r in t) chartNum(r['created'])],
      'เคลียร์': [for (final r in t) chartNum(r['cleared'])],
    },
  );
}

List<LeaveRow> parseLeave(List<Map<String, dynamic>> list) => [
      for (final r in list)
        if (chartNum(r['total_days']) > 0)
          LeaveRow('${r['leave_type_name'] ?? r['leave_type_code'] ?? '—'}', chartNum(r['total_days']), chartNum(r['used_days'])),
    ];

// ─────────────────────────── loader ───────────────────────────

/// What a chart needs to load: api, signed-in user, period, scope.
class ChartRequest {
  const ChartRequest({required this.api, required this.session, required this.entry, required this.scope, required this.now});
  final ApiClient api;
  final SessionState session;
  final HomeEntry entry;

  /// Cache namespace (server + user + business).
  final String scope;
  final DateTime now;

  String get period => entry.period ?? HomeLayout.chartMeta(entry.id)?.defaultPeriod ?? 'month';

  /// `userId` / `owners` for "ของฉัน"; null for "ทีม" (the server limits it to who the user may see).
  String? get owner {
    final me = session.userId;
    if (entry.team && canSeeTeam(session)) return null;
    return me == null || me.isEmpty ? null : me;
  }
}

/// Cache key of a chart (for instant paint before the request).
String chartCacheKey(ChartRequest r) => '${r.scope}|${r.entry.id}|${r.period}|${r.owner ?? 'team'}';

Future<Map<String, dynamic>> _sales(ChartRequest r, ChartRange range, {bool force = false}) =>
    HomeChartCache.instance.fetch('${r.scope}|sales|$range|${r.owner}',
        () => r.api.getSalesDashboard(dateFrom: range.fromYmd, dateTo: range.toYmd, userId: r.owner),
        force: force);

/// Load and parse the data of one chart widget.
Future<Object> loadChartData(ChartRequest r, {bool force = false}) async {
  final c = HomeChartCache.instance;
  final range = chartRange(r.period, r.now);
  switch (r.entry.id) {
    case 'chart_won':
      final cur = await _sales(r, range, force: force);
      final prev = await _sales(r, previousRange(r.period, r.now), force: force);
      return parseWon(cur, prev);
    case 'chart_winrate':
      return parseWinRate(await _sales(r, range, force: force));
    case 'chart_sales_trend':
      return parseSalesTrend(await _sales(r, range, force: force));
    case 'chart_pipeline':
      return SlicesData(parsePipeline(await _sales(r, range, force: force)));
    case 'chart_quote':
      return SlicesData(parseSlices(_map((await _sales(r, range, force: force))['quotation'])['byStatus']));
    case 'chart_closing':
      final p = await c.fetch('${r.scope}|pipeline|$range|${r.owner}',
          () => r.api.getSalesPipeline(dateFrom: range.fromYmd, dateTo: range.toYmd, owner: r.owner),
          force: force);
      final owners = extractMapList(_map(p['options'])['owners']);
      if (owners.length > 1) c.teamHint = true;
      return SlicesData(parseCloseWindow(p));
    case 'chart_lead_source':
    case 'chart_lead_conv':
      final cu = await c.fetch('${r.scope}|customer|$range|${r.owner}',
          () => r.api.getCustomerDashboard(dateFrom: range.fromYmd, dateTo: range.toYmd, userId: r.owner),
          force: force);
      return r.entry.id == 'chart_lead_conv'
          ? parseLeadConversion(cu)
          : SlicesData(parseSlices(_map(cu['lead'])['bySource']));
    case 'chart_case_status':
      final cs = await c.fetch('${r.scope}|case|$range|${r.owner}',
          () => r.api.getCaseDashboard(dateFrom: range.fromYmd, dateTo: range.toYmd, userId: r.owner),
          force: force);
      return SlicesData(parseSlices(cs['byStatus']));
    case 'chart_case_sla':
      final days = int.tryParse(r.period.substring(1)) ?? 30;
      return parseSla(await c.fetch('${r.scope}|sla|$days', () => r.api.getCaseSlaSummary(days: days), force: force));
    case 'chart_activity':
      if (r.session.canAccess('sales-dash-activity')) {
        try {
          final a = await c.fetch('${r.scope}|sact|$range|${r.owner}',
              () => r.api.getSalesActivity(dateFrom: range.fromYmd, dateTo: range.toYmd, owner: r.owner),
              force: force);
          return parseActivityTrend(a);
        } catch (_) {
          // No sales dashboard access on this server → status breakdown below.
        }
      }
      final a = await c.fetch('${r.scope}|act|$range|${r.owner}',
          () => r.api.getActivityDashboard(dateFrom: range.fromYmd, dateTo: range.toYmd, userId: r.owner),
          force: force);
      return SlicesData(parseSlices(a['byStatus'], max: 6));
    case 'chart_work':
      final days = int.tryParse(r.period.substring(1)) ?? 30;
      return parseWorkWeeks(await c.fetch('${r.scope}|work|$days', () => r.api.getHomeWorkInsights(days: days), force: force));
    case 'chart_leave':
      final y = r.now.year;
      return parseLeave(await c.fetch('${r.scope}|leave|$y', () => r.api.getLeaveBalance(year: y), force: force));
  }
  throw StateError('unknown chart ${r.entry.id}');
}

/// Thai "now" for charts (overridable in tests).
DateTime Function() chartNow = thaiNow;
