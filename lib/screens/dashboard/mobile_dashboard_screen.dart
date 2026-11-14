import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../../core/nx_number.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_500.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/unread_service.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../core/thai_time.dart';
import '../../core/workspace_models.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import 'home_layout_editor.dart';
import '../../core/home_layout.dart';
import '../../core/recent_records.dart';
import '../../widgets/nx_refresh.dart';
import 'home_birthday_box.dart';
import 'home_boxes.dart';
import 'home_charts.dart';
import 'home_edit_mode.dart';
import 'home_hero.dart';
import 'home_isaac.dart';
import 'home_widgets.dart';
import 'widget_gallery_sheet.dart';
import '../hr/attendance_punch_sheet.dart';

/// Thai greeting for the hour of day.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'สวัสดีตอนเช้า';
  if (h < 17) return 'สวัสดีตอนบ่าย';
  return 'สวัสดีตอนเย็น';
}

const _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];
const _thaiDays = [
  'จันทร์',
  'อังคาร',
  'พุธ',
  'พฤหัสบดี',
  'ศุกร์',
  'เสาร์',
  'อาทิตย์',
];

/// Short date for the hero greeting: "พฤ. 12 พ.ย." / "Thu, 12 Nov".
String thaiShortDate(DateTime d) {
  const th = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
  const thM = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const enM = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return L10n.isEn ? '${en[d.weekday - 1]}, ${d.day} ${enM[d.month - 1]}' : '${th[d.weekday - 1]} ${d.day} ${thM[d.month - 1]}';
}

String thaiLongDate(DateTime d) => L10n.isEn
    ? '${tr(_thaiDays[d.weekday - 1])}, ${d.day} ${tr(_thaiMonths[d.month - 1])} ${d.year}'
    : 'วัน${_thaiDays[d.weekday - 1]}ที่ ${d.day} ${_thaiMonths[d.month - 1]} ${uiYear(d.year)}';

String _hhmm(dynamic raw) {
  final d = parseThai(raw?.toString() ?? '');
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Module counts on the home summary that map to an in-app list.
const _statModules = <String, IconData>{
  'lead': NxI.users,
  'deal': NxI.handshake,
  'quotation': NxI.receipt,
  'account': NxI.buildings,
  'contact': NxI.addressBook,
  'case': NxI.headset,
  'job': NxI.wrench,
};

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _attendance;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _work;
  int _whatsNew = 0;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;

  /// Header blur shows once the first widget starts sliding under the pinned header.
  final ValueNotifier<bool> _pastHero = ValueNotifier(false);

  /// Pinned header colours: 0 = on the scene (white), 1 = on the page.
  final ValueNotifier<double> _headerSolid = ValueNotifier(0);
  final GlobalKey _heroKey = GlobalKey(debugLabel: 'home-hero');
  double _heroHeight = 300;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // The hero row may be out of the lazy list's built range: keep its last known height.
    final heroBox = _heroHeight = _heroKey.currentContext?.size?.height ?? _heroHeight;
    final barH = HomeGreetingBar.heightFor(MediaQuery.textScalerOf(context));
    // Where the first widget (it starts one gap below the hero) meets the header's bottom edge.
    final meet = heroBox + kHomeWidgetGap - MediaQuery.paddingOf(context).top - barH;
    final o = _scroll.offset;
    // Quick swap (a long blend passes through grey that reads on neither).
    _headerSolid.value = ((o - (meet - 34)) / 22).clamp(0.0, 1.0);
    _pastHero.value = o > meet - 16;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _restoreCache();
    _load();
    RecentRecords.instance.load(context.read<AppConfig>().businessScope);
    HomeLayout.instance.addListener(_onLayout);
    _wiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  // ─────────── widget layout + edit mode (กดค้างเพื่อจัดวาง) ───────────

  String? _layoutScope;
  late final AnimationController _wiggle;
  final ScrollController _scroll = ScrollController();
  bool _editing = false;
  List<HomeEntry> _draft = const [];
  Timer? _autoScroll;
  Offset? _dragPos;

  void _syncLayoutScope(AppConfig config) {
    final scope = config.businessScope;
    if (scope == _layoutScope) return;
    _layoutScope = scope;
    if (_editing) _stopEditing();
    HomeLayout.instance.load(scope, legacyScope: config.prefsScope);
  }

  void _startEditing() {
    if (_editing) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _editing = true;
      _draft = List.of(HomeLayout.instance.entries);
    });
    if (MediaQuery.maybeDisableAnimationsOf(context) != true) _wiggle.repeat();
  }

  void _stopEditing() {
    _wiggle.stop();
    _autoScroll?.cancel();
    _autoScroll = null;
    if (mounted) setState(() => _editing = false);
  }

  bool get _dirty => !listEquals(_draft, HomeLayout.instance.entries);

  Future<void> _done() async {
    final config = context.read<AppConfig>();
    if (_dirty)
      await HomeLayout.instance.saveEntries(config.businessScope, _draft);
    HapticFeedback.lightImpact();
    _stopEditing();
  }

  void _cancelEditing() => _stopEditing();

  /// Back / tap outside: ask when something changed.
  Future<void> _confirmExit() async {
    if (!_dirty) return _stopEditing();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('บันทึกการจัดวาง?')),
        content: Text(tr('คุณเปลี่ยนการจัดวางหน้าหลัก ต้องการบันทึกไหม')),
        actions: [
          TextButton(
            key: const ValueKey('home-exit-discard'),
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(tr('ไม่บันทึก')),
          ),
          FilledButton(
            key: const ValueKey('home-exit-save'),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(tr('บันทึก')),
          ),
        ],
      ),
    );
    if (r == 'save') {
      await _done();
    } else if (r == 'discard') {
      _cancelEditing();
    }
  }

  void _move(String id, String beforeId) {
    final from = _draft.indexWhere((e) => e.id == id);
    final to = _draft.indexWhere((e) => e.id == beforeId);
    if (from < 0 || to < 0 || from == to) return;
    setState(() {
      final list = List.of(_draft);
      final e = list.removeAt(from);
      list.insert(to, e);
      _draft = list;
    });
  }

  void _hide(String id) {
    final i = _draft.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final removed = _draft[i];
    setState(() => _draft = [..._draft]..removeAt(i));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(tr('ซ่อน "${tr(HomeWidgetInfo.of(id).title)}" แล้ว')),
        action: SnackBarAction(
          label: tr('เลิกทำ'),
          onPressed: () {
            if (!mounted || !_editing || _draft.any((e) => e.id == id)) return;
            setState(
              () =>
                  _draft = [..._draft]
                    ..insert(i.clamp(0, _draft.length), removed),
            );
          },
        ),
      ),
    );
  }

  void _resize(String id) {
    setState(
      () => _draft = [
        for (final e in _draft)
          e.id == id
              ? e.copyWith(
                  size: e.size == HomeSize.half ? HomeSize.full : HomeSize.half,
                )
              : e,
      ],
    );
  }

  Future<void> _addWidget() async {
    final current = _editing ? _draft : HomeLayout.instance.entries;
    final e = await showWidgetGallery(
      context,
      onPage: {for (final x in current) x.id},
    );
    if (e == null || !mounted) return;
    if (!_editing) _startEditing();
    setState(() => _draft = [..._draft.where((x) => x.id != e.id), e]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Chart period / scope changed from the card (outside edit mode → saved now).
  void _entryChanged(HomeEntry e) {
    if (_editing) {
      setState(() => _draft = [for (final x in _draft) x.id == e.id ? e : x]);
    } else {
      HomeLayout.instance.update(context.read<AppConfig>().businessScope, e);
    }
  }

  /// Scroll while a dragged widget is held near the top / bottom edge.
  void _onDragUpdate(Offset global) {
    _dragPos = global;
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final p = _dragPos;
      if (p == null || !_scroll.hasClients) return;
      final h = MediaQuery.sizeOf(context).height;
      const edge = 110.0;
      double dy = 0;
      if (p.dy < edge + 60) dy = -((edge + 60 - p.dy) / edge).clamp(0, 1) * 14;
      if (p.dy > h - edge) dy = ((p.dy - (h - edge)) / edge).clamp(0, 1) * 14;
      if (dy == 0) return;
      final pos = _scroll.position;
      _scroll.jumpTo(
        (pos.pixels + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
    });
  }

  void _onDragEnd() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPos = null;
  }

  void _onLayout() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    HomeLayout.instance.removeListener(_onLayout);
    _scroll.removeListener(_onScroll);
    _pastHero.dispose();
    _headerSolid.dispose();
    _wiggle.dispose();
    _scroll.dispose();
    _autoScroll?.cancel();
    super.dispose();
  }

  Future<void> _openHomeEditor() async {
    await nxPush<bool>(context, const HomeLayoutEditorScreen(), root: true);
  }

  /// Overdue appointments (same query as Calendar → ค้าง), newest-due first.
  List<Map<String, dynamic>> _overdue = const [];
  bool _pendingLoaded = false;
  int _overdueTotal = 0;

  /// Overdue Workspace work (Task / Subtask / Bug / Story only — no Epic or Checklist).
  List<Map<String, dynamic>> _overdueWork = const [];

  /// Overdue activities (calendar / pending menus); null = not asked or failed.
  Future<EntityListPage?> _fetchOverdueActivities(ApiClient api) async {
    try {
      return await api.getEntityList(
        'activity',
        limit: 10,
        extra: const {
          'overdue': '1',
          'sort': 'date_start',
          'order': 'asc',
          'cols':
              'id,subject,date_start,date_end,status,activitytype,location,account_name,contact_name,smownerid',
          'with_total': '1',
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Pending work in one list: overdue activities + open Workspace tasks,
  /// most overdue first.
  List<_PendingItem> _pendingItems() {
    final now = thaiNow();
    final out = <_PendingItem>[
      for (final a in _overdue)
        _PendingItem(
          kind: 'activity',
          title: '${a['subject'] ?? entityTitle(a, module: 'activity')}',
          detail: [
            a['account_name'],
            a['contact_name'],
            a['location'],
          ].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
          due: parseWall(a['date_start']),
          route: a['id'] == null ? null : AppRoutes.activity('${a['id']}'),
        ),
      for (final t in _overdueWork)
        _PendingItem(
          kind: 'task',
          type: wsType(t),
          title: '${t['title'] ?? '—'}',
          detail: [
            if ('${t['board_name'] ?? ''}'.isNotEmpty) '${t['board_name']}',
            if ('${t['board_code'] ?? ''}'.isNotEmpty)
              '${t['board_code']}-${t['item_no'] ?? ''}',
            '${t['status_label_th'] ?? t['status_name'] ?? ''}',
          ].where((e) => e.isNotEmpty).join(' · '),
          due: parseThai(t['due_at']),
          route: t['board_id'] == null || t['id'] == null
              ? null
              : AppRoutes.task('${t['board_id']}', '${t['id']}'),
        ),
    ];
    out.sort((a, b) {
      final ad = a.due ?? now.add(const Duration(days: 3650));
      final bd = b.due ?? now.add(const Duration(days: 3650));
      return ad.compareTo(bd);
    });
    return out;
  }

  int _pendingTotal() => _overdueTotal + _overdueWork.length;

  int _revision =
      0; // bumps on pull-to-refresh → boxes with their own data reload

  /// A live answer arrived: the saved copy must not overwrite it any more.
  bool _live = false;

  /// Saved last Home per Space (stale-while-revalidate: shown at once on a cold start,
  /// then refreshed).
  static const _cacheVersion = 1;
  String _cacheKey(AppConfig c) => 'nx_home_cache_v$_cacheVersion|${c.businessScope}';

  Future<void> _restoreCache() async {
    final config = context.read<AppConfig>();
    final key = _cacheKey(config);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty || !mounted || _live) return;
      final m = jsonDecode(raw);
      if (m is! Map || key != _cacheKey(config)) return;
      Map<String, dynamic>? map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;
      setState(() {
        _attendance = map(m['attendance']);
        _summary = map(m['summary']);
        _work = map(m['work']);
        _overdueWork = extractMapList(m['overdue_work']);
        _overdue = extractMapList(m['overdue']);
        _overdueTotal = (m['overdue_total'] as num?)?.toInt() ?? _overdue.length;
        _pendingLoaded = m['pending_loaded'] == true;
        _whatsNew = (m['whats_new'] as num?)?.toInt() ?? 0;
        final mine = map(m['mine']) ?? const {};
        _mine
          ..clear()
          ..addAll({for (final e in mine.entries) if (e.value is num) e.key: (e.value as num).toInt()});
        final sparks = map(m['sparks']) ?? const {};
        _sparks
          ..clear()
          ..addAll({
            for (final e in sparks.entries)
              if (e.value is List) e.key: [for (final v in e.value as List) (v as num?)?.toInt() ?? 0],
          });
        // Saved data on screen; the live load still runs (thin bar at the top).
        _loading = false;
        _refreshing = true;
      });
    } catch (_) {
      // A bad or old copy: just wait for the live answer.
    }
  }

  void _saveCache() {
    final config = context.read<AppConfig>();
    final key = _cacheKey(config);
    final payload = jsonEncode({
      'attendance': _attendance,
      'summary': _summary,
      'work': _work,
      'overdue_work': _overdueWork,
      'overdue': _overdue,
      'overdue_total': _overdueTotal,
      'pending_loaded': _pendingLoaded,
      'whats_new': _whatsNew,
      'mine': _mine,
      'sparks': _sparks,
    });
    () async {
      try {
        await (await SharedPreferences.getInstance()).setString(key, payload);
      } catch (_) {}
    }();
  }

  /// Only what Home shows of the summary: stats + the next appointments (an older server
  /// sends 150 activity rows; keeping them all would also bloat the saved copy).
  Map<String, dynamic>? _trimSummary(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    final up = raw['upcoming'] is List ? extractMapList(raw['upcoming']) : _futureActivities(extractMapList(raw['activities'])).take(8).toList();
    return {'stats': raw['stats'] is Map ? raw['stats'] : const <String, dynamic>{}, 'upcoming': up};
  }

  static Iterable<Map<String, dynamic>> _futureActivities(Iterable<Map<String, dynamic>> all) {
    final now = thaiNow().subtract(const Duration(hours: 1));
    return all.where((a) {
      final d = parseWall(a['date_start']);
      return d == null || d.isAfter(now);
    });
  }

  Future<void> _load() async {
    _revision++;
    final had = _summary != null || _attendance != null || _work != null;
    setState(() {
      _loading = !had;
      _refreshing = had;
      _error = null;
    });
    final config = context.read<AppConfig>();
    final api = config.apiClient;
    final session = config.session;
    Object? firstError;
    Future<Object?> guard(Future<Object?> f) async {
      try {
        return await f;
      } catch (e) {
        firstError ??= e;
        return null;
      }
    }

    final workspace = MenuAccess.allow(session, MenuAccess.workspace);
    final activities = MenuAccess.any(session, const [MenuAccess.calendar, MenuAccess.pending]);
    // Everything the top of Home needs, side by side; one setState when it is all in.
    // /api/home/work once: its `counts` cover every bucket, its items are the overdue page.
    final results = await Future.wait<Object?>([
      MenuAccess.allow(session, MenuAccess.attendance)
          ? guard(api.getAttendanceSummary())
          : Future<Object?>.value(),
      guard(api.getHomeSummary(fields: const ['stats', 'upcoming'])),
      workspace
          ? guard(api.getHomeWork(bucket: 'overdue', limit: 30))
          : Future<Object?>.value(),
      guard(UnreadNotifications.instance.refresh(api).then((_) => null)),
      activities ? _fetchOverdueActivities(api) : Future<Object?>.value(),
      api.getWhatsNewUnread().then<Object?>((n) => n).catchError((_) => 0),
    ]);
    if (!mounted) return;
    _live = true;
    final work = results[2] as Map<String, dynamic>?;
    final overdue = results[4] as EntityListPage?;
    setState(() {
      _attendance = results[0] as Map<String, dynamic>?;
      _summary = _trimSummary(results[1] as Map<String, dynamic>?);
      _work = work == null ? null : {'counts': work['counts']};
      if (work != null) {
        _overdueWork = extractMapList(work['items'] ?? work['work'])
            .where((e) => e['status_is_done'] != true && isWorkType(e))
            .toList();
      }
      if (overdue != null) {
        _overdue = overdue.items;
        _overdueTotal = overdue.total ?? overdue.items.length;
      }
      // Workspace-only users still get the (empty or task-only) box.
      if (overdue != null || (!activities && workspace)) _pendingLoaded = true;
      _whatsNew = (results[5] as int?) ?? 0;
      _error = (_summary == null && _attendance == null && _work == null)
          ? firstError
          : null;
      _loading = false;
      _refreshing = false;
    });
    _saveCache();
    _loadStats();
  }

  /// New records per day for the last 7 days (Thai days), per stat module.
  final Map<String, List<int>> _sparks = {};

  /// "ภาพรวม" = records I own (smownerid = me), not the whole system the
  /// server lets an admin see. Same filter as the list's "ของฉัน".
  final Map<String, int> _mine = {};

  Map<String, String> _mineFilter() {
    final uid = context.read<AppConfig>().session.userId;
    return {if (uid != null && uid.isNotEmpty) 'filter[smownerid]': uid};
  }

  /// "ภาพรวม" figures: one `home-stats` call on newer servers; otherwise the old per-module
  /// counts (7 totals + 7 × 7 daily counts). One setState per step, not one per request.
  Future<void> _loadStats() async {
    final config = context.read<AppConfig>();
    final session = config.session;
    final api = config.apiClient;
    final modules = [
      for (final m in _statModules.keys)
        if (MenuAccess.allow(session, EntityModules.menuKeyOf(m))) m,
    ];
    if (modules.isEmpty) return;
    Map<String, dynamic>? stats;
    try {
      stats = await api.getHomeStats(days: 7);
    } catch (_) {}
    if (!mounted) return;
    final byModule = stats?['modules'];
    if (byModule is Map) {
      int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      final mine = <String, int>{};
      final sparks = <String, List<int>>{};
      for (final m in modules) {
        final r = byModule[m];
        if (r is! Map) continue;
        final v = n(r['mine']);
        if (v != null) mine[m] = v;
        if (r['spark'] is List) sparks[m] = [for (final d in r['spark'] as List) n(d) ?? 0];
      }
      setState(() {
        _mine
          ..clear()
          ..addAll(mine);
        _sparks
          ..clear()
          ..addAll(sparks);
      });
      _saveCache();
      return;
    }
    final mine = await _fetchMineCounts(api, modules);
    if (!mounted) return;
    setState(() => _mine.addAll(mine));
    final sparks = await _fetchSparks(api, modules);
    if (!mounted) return;
    setState(() => _sparks.addAll(sparks));
    _saveCache();
  }

  /// Older servers: my total per module (limit 1 + with_total).
  Future<Map<String, int>> _fetchMineCounts(ApiClient api, List<String> modules) async {
    final mine = _mineFilter();
    final out = <String, int>{};
    await Future.wait([
      for (final module in modules)
        () async {
          try {
            final page = await api.getEntityList(
              module,
              limit: 1,
              extra: {'with_total': '1', 'cols': 'id', ...mine},
            );
            out[module] = page.total ?? page.items.length;
          } catch (_) {
            // keep the tile out rather than show someone else's total
          }
        }(),
    ]);
    return out;
  }

  /// Older servers: one tiny COUNT per module per day (limit 1 + with_total).
  Future<Map<String, List<int>>> _fetchSparks(ApiClient api, List<String> modules) async {
    final mine = _mineFilter();
    final today = thaiNow();
    final t0 = DateTime(today.year, today.month, today.day);
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final out = <String, List<int>>{};
    await Future.wait([
      for (final module in modules)
        () async {
          try {
            out[module] = await Future.wait([
              for (var i = 6; i >= 0; i--)
                () async {
                  final d = ymd(t0.subtract(Duration(days: i)));
                  final page = await api.getEntityList(
                    module,
                    limit: 1,
                    extra: {
                      'period_field': 'createdtime',
                      'period_preset': 'custom',
                      'period_start': d,
                      'period_end': d,
                      'with_total': '1',
                      'cols': 'id',
                      ...mine,
                    },
                  );
                  return page.total ?? page.items.length;
                }(),
            ]);
          } catch (_) {
            // Sparklines are a nicety; the tile still shows its total.
          }
        }(),
    ]);
    return out;
  }

  int _count(Map<String, dynamic>? m, String key) =>
      int.tryParse(m?[key]?.toString() ?? '') ?? 0;

  List<Map<String, dynamic>> _upcoming() {
    // Appointments are calendar data: none for users without a calendar menu.
    if (!MenuAccess.anyCalendar(context.read<AppConfig>().session)) {
      return const [];
    }
    // `upcoming`: the server's next appointments (newer servers) or the trimmed list;
    // re-filtered so a saved copy never shows appointments that have passed.
    final all = extractMapList(_summary?['upcoming'] ?? _summary?['activities']);
    return _futureActivities(all).take(4).toList();
  }

  /// Short plain-language summary of the day (streamed word by word).
  String _brief(Map<String, dynamic>? counts, dynamic clockIn) {
    final parts = <String>[];
    final overdue = _count(counts, 'overdue');
    final today = _count(counts, 'today');
    final next = _upcoming();
    if (clockIn == null &&
        MenuAccess.allow(
          context.read<AppConfig>().session,
          MenuAccess.attendance,
        )) {
      parts.add('ยังไม่ได้ลงเวลาเข้างาน');
    }
    if (today > 0) parts.add('มีงานครบกำหนดวันนี้ ${nxInt(today)} รายการ');
    if (overdue > 0)
      parts.add('งานเลยกำหนด ${nxInt(overdue)} รายการ ควรเคลียร์ก่อน');
    if (next.isNotEmpty) {
      final a = next.first;
      parts.add(
        'นัดถัดไป "${a['subject'] ?? 'กิจกรรม'}" เวลา ${_hhmm(a['date_start'])}',
      );
    }
    if (parts.isEmpty)
      return 'วันนี้ยังไม่มีงานค้างหรือนัดหมาย — แตะให้ไอแซคช่วยวางแผนวันนี้';
    return parts.join(' · ');
  }

  /// What ISAAC is told about today (from the data Home already loaded):
  /// clock-in, work counts, overdue work and the next appointments — each
  /// record with its route so a bullet about it opens it.
  List<IsaacFact> _isaacFacts(Map<String, dynamic>? counts, dynamic clockIn, dynamic clockOut) {
    final session = context.read<AppConfig>().session;
    final out = <IsaacFact>[];
    if (MenuAccess.allow(session, MenuAccess.attendance)) {
      out.add(IsaacFact(
        clockIn == null
            ? 'ยังไม่ได้ลงเวลาเข้างาน'
            : clockOut == null
                ? 'ลงเวลาเข้างานแล้ว ${_hhmm(clockIn)} (ยังไม่ลงเวลาออก)'
                : 'ลงเวลาเข้า ${_hhmm(clockIn)} ออก ${_hhmm(clockOut)} แล้ว',
        route: clockIn == null || clockOut == null ? AppRoutes.attendance : null,
      ));
    }
    if (counts != null) {
      out.add(IsaacFact('งาน Workspace: ครบกำหนดวันนี้ ${_count(counts, 'today')} · เลยกำหนด ${_count(counts, 'overdue')} · กำลังมา ${_count(counts, 'upcoming')}'));
    }
    final pending = _pendingItems();
    if (pending.isNotEmpty) out.add(IsaacFact('งานค้าง/เลยกำหนดทั้งหมด ${_pendingTotal()} รายการ'));
    for (final p in pending.take(6)) {
      final d = p.due;
      final due = d == null ? '' : ' (กำหนด ${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')})';
      out.add(IsaacFact(
        '${p.kind == 'task' ? 'งานเลยกำหนด' : 'กิจกรรมเลยกำหนด'}: ${p.title}${p.detail.isEmpty ? '' : ' — ${p.detail}'}$due',
        route: p.route,
      ));
    }
    for (final a in _upcoming()) {
      final where = '${a['location'] ?? ''}';
      final who = '${a['account_name'] ?? ''}';
      out.add(IsaacFact(
        'นัดหมาย ${_hhmm(a['date_start'])}: ${a['subject'] ?? entityTitle(a, module: 'activity')}'
        '${where.isEmpty ? '' : ' @ $where'}${who.isEmpty ? '' : ' · $who'}',
        route: a['id'] == null ? null : AppRoutes.activity('${a['id']}'),
      ));
    }
    return out;
  }

  Future<void> _punch(dynamic clockIn) async {
    final r = await showAttendancePunchSheet(
      context,
      clockIn: clockIn == null,
      clockedInAt: parseThai(clockIn),
    );
    if (r != null && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.select((AppConfig c) => c.session);
    final bp = NxBreakpoint.of(context);
    final now = thaiNow();
    _syncLayoutScope(context.read<AppConfig>());
    context.select((AppConfig c) => c.businessScope);

    final clockIn = _attendance?['clock_in_at'] ?? _attendance?['clock_in'];
    final clockOut = _attendance?['clock_out_at'] ?? _attendance?['clock_out'];
    final counts = _work?['counts'] is Map
        ? Map<String, dynamic>.from(_work!['counts'] as Map)
        : null;
    final stats = _summary?['stats'] is Map
        ? Map<String, dynamic>.from(_summary!['stats'] as Map)
        : const <String, dynamic>{};
    final aiAllowed = MenuAccess.allow(session, MenuAccess.ai);

    final quick = <_QuickAction>[
      if (MenuAccess.allow(session, MenuAccess.attendance))
        const _QuickAction(NxI.clock, 'ลงเวลา', AppRoutes.attendance),
      if (MenuAccess.allow(session, MenuAccess.leave))
        const _QuickAction(NxI.calendarCheck, 'ขอลา', AppRoutes.leaveRequest),
      // Same menus as the รออนุมัติ page / tab.
      if (MenuAccess.any(session, const [
        MenuAccess.quotation,
        MenuAccess.leaveManagement,
        MenuAccess.pendingApprovals,
      ]))
        const _QuickAction(NxI.checkCircle, 'รออนุมัติ', AppRoutes.approvals),
      if (MenuAccess.allow(session, MenuAccess.chat))
        const _QuickAction(NxI.chatCircle, 'แชท', AppRoutes.chatHome),
      if (MenuAccess.anyCalendar(session))
        const _QuickAction(NxI.calendarBlank, 'ปฏิทิน', AppRoutes.calendar),
      if (MenuAccess.allow(session, MenuAccess.job))
        const _QuickAction(NxI.wrench, 'งานบริการ', AppRoutes.jobs),
      if (MenuAccess.allow(session, MenuAccess.mailbox))
        const _QuickAction(NxI.envelope, 'เมล', AppRoutes.mail),
      if (aiAllowed) const _QuickAction(NxI.robot, 'AI', AppRoutes.aiChat),
    ];

    final statTiles = [
      for (final e in _statModules.entries)
        if (stats.containsKey(e.key) &&
            MenuAccess.allow(session, EntityModules.menuKeyOf(e.key)))
          (e.key, e.value, _mine[e.key]),
    ];

    // The photo only greets (avatar, greeting + date, search, bell); clock-in
    // stays in the today card.
    final todayAttendance = MenuAccess.allow(session, MenuAccess.attendance);
    final next = _upcoming().isEmpty ? null : _upcoming().first;
    final todayHasRows = todayAttendance || next != null || counts != null;

    final pad = bp.scrollPadding(context, inShell: true);
    const maxContent = 1100.0;
    Widget limit(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContent),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad.left),
          child: child,
        ),
      ),
    );

    final hero = HomeHero(
      key: _heroKey,
      now: now,
      gutter: pad.left,
      maxContentWidth: maxContent,
    );

    // The greeting row is pinned like every list page's header: on the scene
    // at first, its blur shows once the widgets start sliding under it.
    return NxScrollScaffold(
      insetBody: false,
      headerBlur: _pastHero,
      header: HomeGreetingBar(
        greeting: greetingFor(now),
        name: session.displayName,
        date: thaiShortDate(now),
        solid: _headerSolid,
        height: HomeGreetingBar.heightFor(MediaQuery.textScalerOf(context)),
        gutter: pad.left,
        maxContentWidth: maxContent,
      ),
      body: Builder(
        builder: (context) {
          final sections = <String, List<Widget>>{
            'today': [
              if (todayHasRows) ...[
                const SizedBox(height: kHomeWidgetGap),
                _TodayCard(
                  showAttendance: todayAttendance,
                  clockIn: clockIn,
                  clockOut: clockOut,
                  onPunch: (_) => _punch(clockIn),
                  next: next,
                  overdue: _count(counts, 'overdue'),
                  today: _count(counts, 'today'),
                  upcoming: _count(counts, 'upcoming'),
                  hasWork: counts != null,
                ),
              ],
            ],
            'pending': [
              if (_pendingItems().isNotEmpty) ...[
                const SizedBox(height: kHomeWidgetGap),
                _PendingBox(items: _pendingItems(), total: _pendingTotal()),
              ] else if (_pendingLoaded) ...[
                const SizedBox(height: kHomeWidgetGap),
                const _NoPending(),
              ],
            ],
            'birthdays': [HomeBirthdayBox(revision: _revision)],
            // ไอแซคแนะนำ: a normal widget (follows the user's order); tap =
            // ISAAC summarises the day in place. Replaces the old "สรุปวันนี้" box.
            'ai': [
              if (aiAllowed) ...[
                const SizedBox(height: kHomeWidgetGap),
                IsaacBriefCard(
                  key: ValueKey('home-isaac-card|${context.read<AppConfig>().businessScope}'),
                  suggestion: isaacSuggestion(_brief(counts, clockIn)),
                  facts: () => _isaacFacts(counts, clockIn, clockOut),
                ),
              ],
            ],
            'quick': [
              if (quick.isNotEmpty) ...[
                const SizedBox(height: kHomeWidgetGap),
                _QuickGrid(actions: quick),
              ],
            ],
            'work': [
              if (MenuAccess.allow(session, MenuAccess.workspace)) ...[
                const SizedBox(height: kHomeWidgetGap),
                MyWorkBox(revision: _revision),
              ],
            ],
            'upcoming': [
              if (_upcoming().length > 1) ...[
                const SizedBox(height: kHomeWidgetGap),
                _SectionTitle(
                  'กิจกรรมถัดไป',
                  action: 'ปฏิทิน',
                  onAction: () => context.push(AppRoutes.calendar),
                ),
                for (final a in _upcoming().skip(1))
                  _ListRow(
                    icon: NxI.calendarBlank,
                    title:
                        a['subject']?.toString() ??
                        entityTitle(a, module: 'activity'),
                    subtitle: [
                      _hhmm(a['date_start']),
                      a['location']?.toString() ?? '',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    onTap: a['id'] == null
                        ? null
                        : () => context.push(
                            AppRoutes.activity(a['id'].toString()),
                          ),
                  ),
              ],
            ],
            'recent': [const RecentStrip()],
            'stats': [
              if (statTiles.isNotEmpty) ...[
                const SizedBox(height: kHomeWidgetGap),
                const _SectionTitle('ภาพรวม'),
                HomeStatStrip(
                  children: [
                    for (final (module, icon, n) in statTiles)
                      HomeStatCard(
                        key: ValueKey('home-stat-$module'),
                        label: EntityModules.titleOf(module),
                        value: n,
                        icon: icon,
                        color: RecentStrip.colorOf(module),
                        added: _sparks[module]?.fold<int>(0, (a, b) => a + b),
                        onTap: () => context.push(
                          EntityModules.isFsm(module)
                              ? AppRoutes.fsmModule(module)
                              : AppRoutes.crmModule(module),
                        ),
                      ),
                  ],
                ),
              ],
            ],
            'sales': [
              if (MenuAccess.any(session, const ['deal', 'quotation'])) ...[
                const SizedBox(height: kHomeWidgetGap),
                SalesPeriodBox(
                  revision: _revision,
                  onOpen: () => context.push(AppRoutes.crmModule('deal')),
                ),
              ],
            ],
            'cases': [
              if (MenuAccess.allow(session, 'case')) ...[
                const SizedBox(height: kHomeWidgetGap),
                CasePeriodBox(
                  revision: _revision,
                  onOpen: () => context.push(AppRoutes.crmModule('case')),
                ),
              ],
            ],
          };
          final grid = HomeWidgetGrid(
            // Lazy rows while browsing; edit mode needs every cell present to drag.
            sliver: !_editing,
            // Widgets this user may not see stay in the saved layout (they
            // return with the permission) but are never shown.
            entries: [
              for (final e
                  in _editing ? _draft : HomeLayout.instance.entries)
                if (homeWidgetAllowed(session, e.id)) e,
            ],
            editing: _editing,
            wiggle: _wiggle,
            onStartEditing: _startEditing,
            onMove: _move,
            onHide: _hide,
            onResize: _resize,
            onDragUpdate: _onDragUpdate,
            onDragEnd: _onDragEnd,
            build: (e) {
              if (!homeWidgetAllowed(session, e.id)) return null;
              if (HomeLayout.isChart(e.id)) {
                return HomeChartCard(
                  key: ValueKey('chart-${e.id}'),
                  entry: e,
                  revision: _revision,
                  editing: _editing,
                  onEntryChanged: _entryChanged,
                );
              }
              final w = sections[e.id];
              if (w == null || w.isEmpty) return null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: w,
              );
            },
          );
          final top = <Widget>[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr(formatApiError(_error!)),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            if (_whatsNew > 0) ...[
              const SizedBox(height: 12),
              _WhatsNewCard(
                count: _whatsNew,
                onTap: () async {
                  await context.push(AppRoutes.whatsNew);
                  if (mounted) _load();
                },
              ),
            ],
          ];
          final footer = <Widget>[
            if (_editing) HomeAddWidgetCard(onTap: _addWidget),
            const SizedBox(height: 20),
            if (!_editing)
              Center(
                child: Wrap(
                  spacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('home-arrange'),
                      onPressed: _startEditing,
                      icon: const Icon(NxI.squaresFour, size: 18),
                      label: Text(tr('จัดวางหน้าหลัก')),
                    ),
                    TextButton.icon(
                      key: const ValueKey('home-add-widget-link'),
                      onPressed: _addWidget,
                      icon: const Icon(NxI.plus, size: 18),
                      label: Text(tr('เพิ่มวิดเจ็ต')),
                    ),
                    TextButton.icon(
                      onPressed: _openHomeEditor,
                      icon: const Icon(NxI.gear, size: 18),
                      label: Text(tr('ตั้งค่า')),
                    ),
                  ],
                ),
              ),
            if (_editing) const SizedBox(height: 72),
          ];
          // Same centring as [limit], for slivers: content at most 1100 wide, page gutters.
          Widget limitSliver(Widget sliver) => SliverLayoutBuilder(
                builder: (context, c) {
                  final w = c.crossAxisExtent;
                  final side = (w - math.min(w, maxContent)) / 2 + pad.left;
                  return SliverPadding(padding: EdgeInsets.symmetric(horizontal: side), sliver: sliver);
                },
              );
          return PopScope(
            canPop: !_editing,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _editing) _confirmExit();
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: _loading
                      ? ListView(
                          padding: EdgeInsets.only(bottom: pad.bottom),
                          children: [
                            hero,
                            const SizedBox(height: 12),
                            limit(const NxSkeletonKpiGrid()),
                          ],
                        )
                      : NxRefresh(
                          edgeOffset: NxScrollScaffold.topInset(context),
                          color: cs.primary,
                          onRefresh: _load,
                          child: GestureDetector(
                            // Tap on empty space while arranging = leave edit mode.
                            behavior: HitTestBehavior.translucent,
                            onTap: _editing ? _confirmExit : null,
                            // Each Home widget is its own lazy row: the first frame builds only
                            // what is on screen (plus a screen below), not every card.
                            child: CustomScrollView(
                              key: const ValueKey('home-scroll'),
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              cacheExtent: MediaQuery.sizeOf(context).height,
                              slivers: [
                                SliverToBoxAdapter(child: hero),
                                if (top.isNotEmpty) limitSliver(SliverList.list(children: top)),
                                limitSliver(_editing ? SliverToBoxAdapter(child: grid) : grid),
                                limitSliver(SliverList.list(children: footer)),
                                SliverPadding(padding: EdgeInsets.only(bottom: pad.bottom)),
                              ],
                            ),
                          ),
                        ),
                ),
                if (_refreshing)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: NxScrollScaffold.topInset(context),
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  // Top, under the status bar: the undo snackbar uses the bottom.
                  top: NxScrollScaffold.topInset(context) + 6,
                  child: IgnorePointer(
                    ignoring: !_editing,
                    child: AnimatedSlide(
                      offset: _editing ? Offset.zero : const Offset(0, -1.6),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _editing ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: HomeEditBar(
                              onCancel: _cancelEditing,
                              onDone: _done,
                              onAdd: _addWidget,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "มีอะไรใหม่ N รายการ" banner under the hero.
class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _HomeCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(NxI.sparkleFill, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('มีอะไรใหม่ $count รายการ'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// The shared Home card ([homeCardDecoration]) with an optional tap.
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius = kHomeCardRadius,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // The shadow is painted outside the Material: ink drawn on a Material is clipped to its
    // rectangle, which cut the soft shadow into a flat band under the card.
    final deco = homeCardDecoration(context, radius: radius);
    final box = Ink(
      padding: padding,
      decoration: deco.copyWith(boxShadow: const []),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: deco.borderRadius, boxShadow: deco.boxShadow),
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null
            ? box
            : InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTap,
                child: box,
              ),
      ),
    );
  }
}

/// One card for "today": attendance, next appointment and work counts.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.showAttendance,
    required this.clockIn,
    required this.clockOut,
    required this.next,
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.hasWork,
    this.onPunch,
  });

  /// Opens the clock in / out window (true = clock in).
  final void Function(bool clockIn)? onPunch;

  final bool showAttendance;
  final dynamic clockIn;
  final dynamic clockOut;
  final Map<String, dynamic>? next;
  final int overdue;
  final int today;
  final int upcoming;
  final bool hasWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inAt = _hhmm(clockIn);
    final outAt = _hhmm(clockOut);
    final String status;
    final String cta;
    if (clockIn == null) {
      status = 'ยังไม่ได้ลงเวลาเข้างาน';
      cta = 'ลงเวลาเข้า';
    } else if (clockOut == null) {
      status = 'เข้างาน $inAt';
      cta = 'ลงเวลาออก';
    } else {
      status = 'เข้า $inAt · ออก $outAt';
      cta = 'ประวัติ';
    }
    final rows = <Widget>[];
    if (showAttendance) {
      rows.add(
        Row(
          children: [
            clockIn == null
                ? _dot(cs.primary, NxI.clock, cs)
                : _dot(const Color(0xFF16A34A), NxI.checkCircle, cs),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('ลงเวลาวันนี้'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    tr(status),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.onSurface,
                foregroundColor: cs.surface,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: const Size(0, 40),
              ),
              key: const ValueKey('home-punch'),
              onPressed: () => clockOut != null || onPunch == null
                  ? context.push(AppRoutes.attendance)
                  : onPunch!(clockIn == null),
              child: Text(tr(cta)),
            ),
          ],
        ),
      );
    }
    final n = next;
    if (n != null) {
      if (rows.isNotEmpty) rows.add(const Divider(height: 24));
      rows.add(
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: n['id'] == null
              ? null
              : () => context.push(AppRoutes.activity(n['id'].toString())),
          child: Row(
            children: [
              _dot(const Color(0xFFF59E0B), NxI.calendarBlank, cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('นัดถัดไป · ${_hhmm(n['date_start'])}'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      tr(
                        n['subject']?.toString() ??
                            entityTitle(n, module: 'activity'),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((n['location']?.toString() ?? '').isNotEmpty)
                      Text(
                        tr(n['location'].toString()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      );
    }
    if (hasWork) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(
        Row(
          children: [
            Expanded(child: _CountPill('เลยกำหนด', overdue, cs.error)),
            const SizedBox(width: 8),
            Expanded(
              child: _CountPill('วันนี้', today, const Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 8),
            Expanded(child: _CountPill('กำลังมา', upcoming, cs.primary)),
          ],
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeBoxHeader(
            icon: NxI.sun,
            title: 'วันนี้',
            color: Color(0xFFF59E0B),
          ),
          const SizedBox(height: 14),
          ...rows,
        ],
      ),
    );
  }

  static Widget _dot(Color c, IconData icon, ColorScheme cs) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: c, size: 20),
  );
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final String route;

  /// Bolder stroke + own colour so shortcuts read clearly in light mode.
  static const Map<String, (IconData, Color)> _styles = {
    'ลงเวลา': (LucideIcons500.clock, Color(0xFF6366F1)),
    'ขอลา': (LucideIcons500.calendarCheck, Color(0xFF0D9488)),
    'รออนุมัติ': (LucideIcons500.circleCheck, Color(0xFF16A34A)),
    'แชท': (LucideIcons500.messageCircle, Color(0xFF0284C7)),
    'ปฏิทิน': (LucideIcons500.calendar, Color(0xFFD97706)),
    'งานบริการ': (LucideIcons500.wrench, Color(0xFFEA580C)),
    'เมล': (LucideIcons500.mail, Color(0xFFE11D48)),
    'AI': (LucideIcons500.bot, Color(0xFF7C3AED)),
  };

  IconData get boldIcon => _styles[label]?.$1 ?? icon;
  Color colorIn(ColorScheme cs) => _styles[label]?.$2 ?? cs.primary;
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.actions});
  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _HomeCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: HomeBoxHeader(
              icon: NxI.lightning,
              title: 'ทางลัด',
              color: Color(0xFF0EA5E9),
            ),
          ),
          const SizedBox(height: 8),
          _grid(theme, cs),
        ],
      ),
    );
  }

  Widget _grid(ThemeData theme, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 8 : 4;
        final w = c.maxWidth / cols;
        return Wrap(
          children: [
            for (final a in actions)
              SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push(a.route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: a
                                .colorIn(cs)
                                .withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.22
                                      : 0.12,
                                ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: a.colorIn(cs).withValues(alpha: 0.18),
                            ),
                          ),
                          child: Icon(
                            a.boldIcon,
                            size: 24,
                            color: a.colorIn(cs),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(a.label),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr(title),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(tr(action!))),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('$value'),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(tr(label), style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _HomeCard(
        onTap: onTap,
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      tr(subtitle!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                NxI.caretRight,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingItem {
  const _PendingItem({
    required this.kind,
    required this.title,
    this.detail = '',
    this.due,
    this.route,
    this.type,
  });
  final String kind; // activity | task
  final String? type; // workspace item type (task / subtask / bug / story)
  final String title;
  final String detail;
  final DateTime? due;
  final String? route;
}

/// "งานค้าง": overdue activities + open Workspace tasks in one card, with a
/// red/amber rail per item and how late it is.
class _PendingBox extends StatefulWidget {
  const _PendingBox({required this.items, required this.total});
  final List<_PendingItem> items;
  final int total;

  @override
  State<_PendingBox> createState() => _PendingBoxState();
}

class _PendingBoxState extends State<_PendingBox> {
  String _kind = 'all';
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    () async {
      final saved = await HomePrefs.get(context, 'pending_collapsed');
      if (mounted && saved == '1') setState(() => _collapsed = true);
    }();
  }

  String _late(DateTime? due) {
    if (due == null) return tr('ไม่กำหนดส่ง');
    final now = thaiNow();
    final d0 = DateTime(now.year, now.month, now.day);
    final dd = DateTime(due.year, due.month, due.day);
    final days = d0.difference(dd).inDays;
    if (days > 0) return tr('เลยกำหนด $days วัน');
    if (days == 0) return tr('ครบกำหนดวันนี้');
    return tr('อีก ${-days} วัน');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final acts = widget.items.where((e) => e.kind == 'activity').length;
    final tasks = widget.items.where((e) => e.kind == 'task').length;
    final shown = widget.items
        .where((e) => _kind == 'all' || e.kind == _kind)
        .take(5)
        .toList();
    final now = thaiNow();
    Widget chip(String k, String label, int n) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('${tr(label)} $n'),
        selected: _kind == k,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _kind = k),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: homeCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeBoxHeader(
            key: const ValueKey('pending-header'),
            icon: NxI.warningCircle,
            title: 'งานค้าง',
            color: cs.error,
            count: widget.total,
            collapsed: _collapsed,
            onToggle: () {
              setState(() => _collapsed = !_collapsed);
              HomePrefs.set(
                context,
                'pending_collapsed',
                _collapsed ? '1' : '0',
              );
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            chip('all', 'ทั้งหมด', widget.items.length),
                            if (acts > 0) chip('activity', 'กิจกรรม', acts),
                            if (tasks > 0) chip('task', 'Workspace', tasks),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        alignment: Alignment.topCenter,
                        child: Column(
                          children: [
                            for (final it in shown)
                              InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: it.route == null
                                    ? null
                                    : () => context.push(it.route!),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color:
                                              it.due != null &&
                                                  it.due!.isBefore(
                                                    DateTime(
                                                      now.year,
                                                      now.month,
                                                      now.day,
                                                    ),
                                                  )
                                              ? cs.error
                                              : const Color(0xFFF59E0B),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        it.kind == 'activity'
                                            ? NxI.calendarBlank
                                            : wsTypeStyle(
                                                it.type ?? 'task',
                                              ).icon,
                                        size: 18,
                                        color: it.kind == 'activity'
                                            ? cs.onSurfaceVariant
                                            : wsTypeStyle(
                                                it.type ?? 'task',
                                              ).color,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              it.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall,
                                            ),
                                            Text(
                                              [
                                                _late(it.due),
                                                if (it.detail.isNotEmpty)
                                                  it.detail,
                                              ].join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        NxI.caretRight,
                                        size: 16,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (acts > 0)
                            TextButton(
                              onPressed: () => context.push(AppRoutes.calendar),
                              child: Text(tr('กิจกรรมค้างทั้งหมด')),
                            ),
                          if (tasks > 0)
                            TextButton(
                              onPressed: () =>
                                  context.push(AppRoutes.workspaceHome),
                              child: Text(tr('งาน Workspace')),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Empty state of the pending box: nothing overdue.
class _NoPending extends StatelessWidget {
  const _NoPending();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: homeCardDecoration(context),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(NxI.checkCircle, color: green, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('ไม่มีงานค้าง — เคลียร์ครบแล้ว'),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
