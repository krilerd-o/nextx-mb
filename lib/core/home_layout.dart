import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Width of a Home widget: half (one column of the grid) or full row.
enum HomeSize { half, full }

/// One widget on the Home page, in the user's order.
@immutable
class HomeEntry {
  const HomeEntry(this.id, {this.size = HomeSize.full, this.period, this.team = false});

  final String id;
  final HomeSize size;

  /// Chart period key (`week`, `month`, `m6`, `d30` …); null = the chart's default.
  final String? period;

  /// Chart scope: false = ของฉัน, true = ทีม (only for users who may see a team).
  final bool team;

  HomeEntry copyWith({HomeSize? size, String? period, bool? team}) =>
      HomeEntry(id, size: size ?? this.size, period: period ?? this.period, team: team ?? this.team);

  Map<String, dynamic> toJson() => {
        'id': id,
        'size': size.name,
        if (period != null) 'period': period,
        if (team) 'team': true,
      };

  static HomeEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    if (!HomeLayout.isKnown(id)) return null;
    final meta = HomeLayout.chartMeta(id);
    var size = raw['size'] == 'half' ? HomeSize.half : HomeSize.full;
    if (meta == null || !meta.resizable) size = HomeLayout.defaultSizeOf(id);
    final p = raw['period'];
    return HomeEntry(id, size: size, period: p == null ? null : '$p', team: raw['team'] == true);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeEntry && other.id == id && other.size == size && other.period == period && other.team == team;

  @override
  int get hashCode => Object.hash(id, size, period, team);

  @override
  String toString() => 'HomeEntry($id, ${size.name}${period == null ? '' : ', $period'}${team ? ', team' : ''})';
}

/// Static facts about a chart widget (no Flutter types: tests and storage use it).
class HomeChartMeta {
  const HomeChartMeta({
    required this.id,
    required this.title,
    required this.hint,
    required this.group,
    required this.defaultSize,
    this.resizable = false,
    this.periods = const ['week', 'month', 'quarter', 'year'],
    this.defaultPeriod = 'month',
    this.teamable = true,
  });

  final String id;
  final String title;
  final String hint;

  /// Gallery group: general, work, sales, customer, service, hr.
  final String group;
  final HomeSize defaultSize;

  /// Half ↔ full allowed (KPI / ring / donut). Line, bar and funnel stay full.
  final bool resizable;
  final List<String> periods;
  final String defaultPeriod;

  /// Has a ของฉัน | ทีม switch (data the server can scope by owner).
  final bool teamable;
}

/// Order, size and settings of the Home widgets — per server + user + business.
class HomeLayout extends ChangeNotifier {
  HomeLayout._();
  static final HomeLayout instance = HomeLayout._();

  /// Classic Home sections → Thai label (translated by tr()) and a short hint.
  static const Map<String, (String, String)> sections = {
    'ai': ('ไอแซคแนะนำ', 'แตะแล้วไอแซคสรุปวันนี้ให้เป็นข้อๆ ตรงนี้เลย'),
    'today': ('ลงเวลา', 'ลงเวลาเข้า-ออก งานเลยกำหนด นัดถัดไป'),
    'work': ('งานวันนี้', 'งาน Workspace ของฉัน (ค่าเริ่มต้นวันนี้)'),
    'pending': ('งานค้าง', 'กิจกรรมค้าง + งาน Workspace ค้าง'),
    'quick': ('ทางลัด', 'ลงเวลา ขอลา แชท ปฏิทิน …'),
    'recent': ('เปิดล่าสุด', 'รายการที่เพิ่งเปิดในเครื่องนี้'),
    'sales': ('ยอดขาย', 'ดีลและใบเสนอราคาของฉัน ตามช่วงเวลา'),
    'cases': ('เคส', 'เคสของฉัน ตามช่วงเวลา'),
    'stats': ('ภาพรวม', 'จำนวนรายการของฉัน + กราฟ 7 วัน'),
    'birthdays': ('วันเกิดลูกค้าวันนี้', 'Lead / Contact / Account ที่เกิดวันนี้และพรุ่งนี้'),
    'upcoming': ('กิจกรรมถัดไป', 'นัดหมายที่กำลังมา'),
  };

  /// Default classic order: ไอแซคแนะนำ (the day summary; only users with the AI
  /// menu see it) · ลงเวลา · งานวันนี้ · งานค้าง · ทางลัด · เปิดล่าสุด · ยอดขาย ·
  /// เคส · ภาพรวม, then birthdays and upcoming activities.
  static const List<String> defaultOrder = [
    'ai', 'today', 'work', 'pending', 'quick', 'recent', 'sales', 'cases', 'stats', 'birthdays', 'upcoming',
  ];

  /// Chart widgets (gallery order).
  static const List<HomeChartMeta> charts = [
    HomeChartMeta(id: 'chart_won', title: 'ยอดปิดการขาย', hint: 'ยอดที่ปิดได้ เทียบกับช่วงก่อนหน้า', group: 'sales', defaultSize: HomeSize.half, resizable: true),
    HomeChartMeta(id: 'chart_winrate', title: 'Win rate', hint: 'สัดส่วนดีลที่ปิดได้ต่อดีลที่ปิดทั้งหมด', group: 'sales', defaultSize: HomeSize.half, resizable: true),
    HomeChartMeta(id: 'chart_sales_trend', title: 'ยอดขายรายเดือน', hint: 'ยอดปิดการขายแต่ละเดือน', group: 'sales', defaultSize: HomeSize.full, periods: ['m6', 'm12', 'year'], defaultPeriod: 'm6'),
    HomeChartMeta(id: 'chart_pipeline', title: 'Pipeline ตามขั้น', hint: 'จำนวนและมูลค่าดีลแต่ละขั้น', group: 'sales', defaultSize: HomeSize.full, defaultPeriod: 'year'),
    HomeChartMeta(id: 'chart_closing', title: 'ดีลใกล้ปิด', hint: 'ดีลที่เปิดอยู่ ตามวันที่คาดว่าจะปิด', group: 'sales', defaultSize: HomeSize.full, periods: [], defaultPeriod: 'year'),
    HomeChartMeta(id: 'chart_quote', title: 'ใบเสนอราคาตามสถานะ', hint: 'จำนวนใบเสนอราคาแต่ละสถานะ', group: 'sales', defaultSize: HomeSize.half, resizable: true),
    HomeChartMeta(id: 'chart_lead_source', title: 'Lead ตามแหล่งที่มา', hint: 'Lead ใหม่มาจากช่องทางไหน', group: 'customer', defaultSize: HomeSize.half, resizable: true),
    HomeChartMeta(id: 'chart_lead_conv', title: 'Conversion rate', hint: 'Lead ที่แปลงเป็นลูกค้าแล้ว', group: 'customer', defaultSize: HomeSize.half, resizable: true),
    HomeChartMeta(id: 'chart_case_status', title: 'เคสตามสถานะ', hint: 'เคสแต่ละสถานะในช่วงนี้', group: 'service', defaultSize: HomeSize.half, resizable: true),
    HomeChartMeta(id: 'chart_case_sla', title: 'SLA เคส', hint: 'เคสที่ปิดทันเวลา (ของฉัน)', group: 'service', defaultSize: HomeSize.half, resizable: true, periods: ['d7', 'd30', 'd90'], defaultPeriod: 'd30', teamable: false),
    HomeChartMeta(id: 'chart_activity', title: 'กิจกรรม / เข้าพบลูกค้า', hint: 'เสร็จ · พลาด · กำลังมา รายวัน', group: 'work', defaultSize: HomeSize.full, periods: ['week', 'month'], defaultPeriod: 'week'),
    HomeChartMeta(id: 'chart_work', title: 'งาน: สร้าง vs เคลียร์', hint: 'งาน Workspace ของฉัน รายสัปดาห์', group: 'work', defaultSize: HomeSize.full, periods: ['d30', 'd90'], defaultPeriod: 'd30', teamable: false),
    HomeChartMeta(id: 'chart_leave', title: 'วันลาคงเหลือ', hint: 'สิทธิ์ลาที่เหลือปีนี้ แต่ละประเภท', group: 'hr', defaultSize: HomeSize.half, resizable: true, periods: [], defaultPeriod: 'year', teamable: false),
  ];

  /// Charts added to a new (or migrated) Home, after "เคส".
  static const List<String> defaultCharts = ['chart_won', 'chart_winrate', 'chart_pipeline', 'chart_work'];

  static HomeChartMeta? chartMeta(String id) {
    for (final c in charts) {
      if (c.id == id) return c;
    }
    return null;
  }

  static bool isChart(String id) => chartMeta(id) != null;
  static bool isKnown(String id) => sections.containsKey(id) || isChart(id);
  static HomeSize defaultSizeOf(String id) => chartMeta(id)?.defaultSize ?? HomeSize.full;
  static bool resizable(String id) => chartMeta(id)?.resizable ?? false;

  static List<HomeEntry> defaultEntries() {
    final out = [for (final k in defaultOrder) HomeEntry(k)];
    final at = out.indexWhere((e) => e.id == 'cases') + 1;
    out.insertAll(at, [for (final c in defaultCharts) HomeEntry(c, size: defaultSizeOf(c))]);
    return out;
  }

  List<HomeEntry> _entries = defaultEntries();
  String? _scope;

  /// Visible widgets, in order (hidden ones are simply not in the list).
  List<HomeEntry> get entries => List.unmodifiable(_entries);

  HomeEntry? entry(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Classic sections: shown ones in Home order, then hidden ones where the default puts them.
  List<String> get order {
    final out = [for (final e in _entries) if (sections.containsKey(e.id)) e.id];
    for (final k in defaultOrder) {
      if (!out.contains(k)) out.insert(defaultOrder.indexOf(k).clamp(0, out.length), k);
    }
    return List.unmodifiable(out);
  }

  /// Classic sections the user switched off.
  Set<String> get hidden => {for (final k in defaultOrder) if (entry(k) == null) k};

  /// All visible widget ids (classic sections and charts) in order.
  List<String> get visibleOrder => [for (final e in _entries) e.id];

  static String _v2Key(String scope) => 'nx_home_layout_v2_$scope';
  static String _v1Key(String scope) => 'nx_home_layout_$scope';

  /// [scope] = where v2 is kept (per business); [legacyScope] = where the old
  /// per-user order/hidden lived (moved over once, then left alone).
  Future<void> load(String scope, {String? legacyScope, bool force = false}) async {
    if (_scope == scope && !force) return;
    _scope = scope;
    _entries = defaultEntries();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_v2Key(scope));
      if (raw != null) {
        final j = jsonDecode(raw);
        var list = <HomeEntry>[];
        for (final r in (j is Map ? j['entries'] : j) as List? ?? const []) {
          final e = HomeEntry.fromJson(r);
          if (e != null && !list.any((x) => x.id == e.id)) list.add(e);
        }
        if (!(j is Map && j[_isaacFlag] == true)) {
          // Saved before ISAAC became a widget: put it on top once (it used to
          // sit on the hero), then the user's own choice wins.
          list = isaacFirst(list);
          await prefs.setString(_v2Key(scope), _encode(list));
        }
        if (_scope == scope) _entries = list;
      } else {
        final v1 = prefs.getString(_v1Key(legacyScope ?? scope));
        if (v1 != null) _entries = migrateV1(jsonDecode(v1) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (_scope == scope) notifyListeners();
  }

  /// v1 `{order, hidden}` → v2 entries: the saved order stays, sections added
  /// later go where the default puts them, hidden ones are left out, the
  /// default charts come after "เคส" (or at the end), and "ไอแซคแนะนำ" goes on top.
  static List<HomeEntry> migrateV1(Map<String, dynamic> j) {
    final saved = [for (final k in (j['order'] as List? ?? const [])) '$k'].where(sections.containsKey).toList();
    for (final k in defaultOrder) {
      if (!saved.contains(k)) saved.insert(defaultOrder.indexOf(k).clamp(0, saved.length), k);
    }
    final hidden = {for (final k in (j['hidden'] as List? ?? const [])) '$k'};
    final out = [for (final k in saved) if (!hidden.contains(k)) HomeEntry(k)];
    final i = out.indexWhere((e) => e.id == 'cases');
    out.insertAll(i < 0 ? out.length : i + 1, [for (final c in defaultCharts) HomeEntry(c, size: defaultSizeOf(c))]);
    return isaacFirst(out);
  }

  /// Marks a saved v2 layout that already had "ไอแซคแนะนำ" placed (see [isaacFirst]).
  static const String _isaacFlag = 'isaac';

  /// "ไอแซคแนะนำ" (`ai`, which also replaced the old "สรุปโดย AI" box) moved
  /// or added to the top — done once for layouts saved before it was a widget.
  static List<HomeEntry> isaacFirst(List<HomeEntry> entries) => [
        entries.firstWhere((e) => e.id == 'ai', orElse: () => const HomeEntry('ai')),
        ...entries.where((e) => e.id != 'ai'),
      ];

  static String _encode(List<HomeEntry> entries) =>
      jsonEncode({'v': 2, _isaacFlag: true, 'entries': [for (final e in entries) e.toJson()]});

  Future<void> saveEntries(String scope, List<HomeEntry> entries) async {
    _scope = scope;
    final seen = <String>{};
    _entries = [for (final e in entries) if (isKnown(e.id) && seen.add(e.id)) e];
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString(_v2Key(scope), _encode(_entries));
    } catch (_) {}
  }

  /// Change one widget (size / period / scope) and save right away.
  Future<void> update(String scope, HomeEntry e) async {
    final list = [for (final x in _entries) x.id == e.id ? e : x];
    await saveEntries(scope, list);
  }

  /// Classic API (order + hidden of the sections); charts keep their place.
  Future<void> save(String scope, List<String> order, Set<String> hidden) async {
    final charts = [for (final e in _entries) if (isChart(e.id)) e];
    final list = [
      for (final k in order)
        if (sections.containsKey(k) && !hidden.contains(k)) entry(k) ?? HomeEntry(k),
      ...charts,
    ];
    await saveEntries(scope, list);
  }
}
