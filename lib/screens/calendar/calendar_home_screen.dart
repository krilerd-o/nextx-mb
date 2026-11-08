import 'dart:async';

import '../../widgets/nx_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../services/realtime_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../crm/entity_detail_parts.dart' show PendingEntityDeletes;
import 'activity_detail_screen.dart';
import 'activity_form_screen.dart';
import 'cal/cal_agenda_view.dart';
import 'cal/cal_birthday_actions.dart';
import 'cal/cal_birthdays.dart';
import 'cal/cal_model.dart';
import 'cal/cal_month_view.dart';
import 'cal/cal_store.dart';
import 'cal/cal_time_grid.dart';
import 'cal/cal_widgets.dart';
import 'cal/cal_year_view.dart';
import '../../widgets/nx_refresh.dart';

export 'cal/cal_model.dart' show groupActivitiesByDay, activityTimeLabel, weekStart, CalView;

/// Activities calendar: year / month / week / 3 days / day / list.
///
/// - The header shows the period ("พ.ย. 2569 ▾"); tap it to jump between
///   year and month.
/// - Switching views zooms (coarser ⇄ finer); a month tapped in the year view
///   grows out of its tile.
/// - Month: scroll the list up and the month folds into the selected week.
/// - Week / 3 days / day: tap a slot to add, long-press to drag, drag the
///   bottom edge to lengthen, "+N" opens the day's card.
class CalendarHomeScreen extends StatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

enum _CalMode { calendar, incoming, pending }

class _CalendarHomeScreenState extends State<CalendarHomeScreen> with SingleTickerProviderStateMixin {
  late final CalStore _store = CalStore(context.read<AppConfig>().apiClient, scope: context.read<AppConfig>().prefsScope);
  late final TabController _tabs = TabController(length: CalView.values.length, vsync: this, initialIndex: CalView.month.index);
  CalView _view = CalView.month;
  CalView _prev = CalView.month;
  DateTime _date = calDay(thaiNow());
  _CalMode _mode = _CalMode.calendar;
  Future<List<CalEvent>>? _special;
  NxListQuery _lq = const NxListQuery();
  Alignment _zoomAt = Alignment.center;
  bool _fromTile = false;
  int _jump = 0; // bumps page-based views back to [_date]
  final _bodyKey = GlobalKey();
  final _search = TextEditingController();
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _debounce;

  String get _prefKey => 'nx_cal_view_${context.read<AppConfig>().prefsScope}';
  String get _bdayKey => 'nx_cal_birthdays_${context.read<AppConfig>().prefsScope}';

  @override
  void initState() {
    super.initState();
    _store.filter = _passes;
    _store.onBirthday = _openBirthday;
    PendingEntityDeletes.instance.addListener(_store.refreshFilter);
    final key = _prefKey;
    final bdayKey = _bdayKey;
    SharedPreferences.getInstance().then((p) {
      if (p.getBool(bdayKey) == false) _store.birthdays.setEnabled(false);
      final saved = CalView.values.where((v) => v.name == p.getString(key)).firstOrNull;
      if (saved != null && mounted && saved != _view) {
        setState(() {
          _view = _prev = saved;
          _tabs.index = saved.index;
        });
      }
    }).catchError((_) {});
    // Changed anywhere in the business (web, other phones) → reload.
    _live = RealtimeService.instance.on('calendar:activity_upsert').listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), _reload);
    });
  }

  @override
  void dispose() {
    PendingEntityDeletes.instance.removeListener(_store.refreshFilter);
    _live?.cancel();
    _debounce?.cancel();
    _tabs.dispose();
    _search.dispose();
    _store.dispose();
    super.dispose();
  }

  // ── filtering
  bool _passes(CalEvent e) {
    if (PendingEntityDeletes.instance.isPending('activity', e.id)) return false;
    final q = _lq.q.trim().toLowerCase();
    if (q.isNotEmpty) {
      final r = e.raw;
      final hay = '${e.title} ${e.location} ${r['account_name'] ?? ''} ${r['contact_name'] ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    if (_lq.has('scope', 'mine') && '${e.raw['smownerid'] ?? ''}' != (context.read<AppConfig>().session.userId ?? '')) return false;
    final types = _lq.values('type');
    if (types.isNotEmpty && !types.contains(e.type)) return false;
    final statuses = _lq.values('status');
    if (statuses.isNotEmpty && !statuses.contains(e.status)) return false;
    final ci = _lq.values('checkin');
    if (ci.isNotEmpty && !((ci.contains('done') && e.checkedIn) || (ci.contains('not') && !e.checkedIn))) return false;
    return true;
  }

  Future<void> _openFilter() async {
    final all = _store.between(DateTime(1900), DateTime(2200));
    final types = {for (final e in all) if (e.type.isNotEmpty) e.type}.toList()..sort();
    final statuses = {for (final e in all) if (e.status.isNotEmpty) e.status}.toList()..sort();
    final next = await showNxFilterSheet(context, query: _lq, groups: [
      const NxFilterGroup(key: 'scope', label: 'ขอบเขต', multi: false, options: [NxFilterOption('mine', 'ของฉัน')]),
      if (types.isNotEmpty) NxFilterGroup(key: 'type', label: 'ประเภท', options: [for (final t in types) NxFilterOption(t, t)]),
      if (statuses.isNotEmpty) NxFilterGroup(key: 'status', label: 'สถานะ', options: [for (final t in statuses) NxFilterOption(t, t)]),
      const NxFilterGroup(key: 'checkin', label: 'เช็คอิน', multi: false, options: [
        NxFilterOption('done', 'เช็คอินแล้ว'),
        NxFilterOption('not', 'ยังไม่เช็คอิน'),
      ]),
    ]);
    if (next == null || !mounted) return;
    setState(() => _lq = next.copyWith(q: _lq.q));
    _store.refreshFilter();
  }

  // ── navigation between views
  void _setView(CalView v, {Rect? from}) {
    if (v == _view && _mode == _CalMode.calendar) return;
    HapticFeedback.selectionClick();
    var at = Alignment.center;
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (from != null && box != null && box.hasSize) {
      final c = box.globalToLocal(from.center);
      at = Alignment((c.dx / box.size.width) * 2 - 1, (c.dy / box.size.height) * 2 - 1);
    }
    setState(() {
      _prev = _view;
      _view = v;
      _zoomAt = at;
      _fromTile = from != null;
      _mode = _CalMode.calendar;
    });
    if (_tabs.index != v.index) _tabs.animateTo(v.index);
    final key = _prefKey;
    SharedPreferences.getInstance().then((p) => p.setString(key, v.name)).catchError((_) => false);
  }

  void _goToday() {
    HapticFeedback.selectionClick();
    setState(() {
      _date = calDay(thaiNow());
      _jump++;
    });
  }

  bool get _showsToday {
    final t = calDay(thaiNow());
    switch (_view) {
      case CalView.year:
        return _date.year == t.year;
      case CalView.week:
        return sameDay(weekStart(_date), weekStart(t));
      case CalView.threeDay:
        return !t.isBefore(_date) && t.isBefore(_date.add(const Duration(days: 3)));
      case CalView.month:
      case CalView.day:
      case CalView.list:
        return sameDay(_date, t);
    }
  }

  (DateTime, DateTime) get _range {
    final d = _date;
    return switch (_view) {
      CalView.year => (DateTime(d.year, 1, 1), DateTime(d.year, 12, 31)),
      _ => (DateTime(d.year, d.month - 1, 20), DateTime(d.year, d.month + 2, 10)),
    };
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final (a, b) = _range;
    await _store.reload(a, b);
    if (mounted && _mode != _CalMode.calendar) setState(() => _special = _fetchSpecial(_mode));
  }

  // ── upcoming / overdue (same API flags as before)
  Future<List<CalEvent>> _fetchSpecial(_CalMode m) async {
    final page = await context.read<AppConfig>().apiClient.getEntityList('activity', limit: 200, extra: {
      'cols': CalStore.cols,
      'sort': 'date_start',
      'order': m == _CalMode.pending ? 'desc' : 'asc',
      if (m == _CalMode.incoming) 'involved': '1',
      if (m == _CalMode.pending) 'overdue': '1',
    });
    return [for (final r in page.items) ?CalEvent.from(r)];
  }

  void _setMode(_CalMode m) {
    setState(() {
      _mode = m;
      _special = m == _CalMode.calendar ? null : _fetchSpecial(m);
      if (m != _CalMode.calendar) {
        _prev = _view;
        _view = CalView.list;
        _tabs.animateTo(CalView.list.index);
      }
    });
  }

  // ── actions on appointments
  DateTime _defaultStart(DateTime day) {
    final now = thaiNow();
    if (sameDay(day, now)) return DateTime(now.year, now.month, now.day, (now.hour + 1).clamp(0, 23));
    return DateTime(day.year, day.month, day.day, 9);
  }

  /// Birthday card → call / email / open the customer / plan a greeting.
  void _openBirthday(CalBirthday b, DateTime day, Rect? anchor) {
    openCalBirthday(context, b, day, anchor: anchor, onChanged: () {
      if (mounted) _reload();
    });
  }

  Future<void> _toggleBirthdays() async {
    final on = !_store.birthdays.enabled;
    _store.birthdays.setEnabled(on);
    if (on) _store.birthdays.load();
    final key = _bdayKey;
    try {
      (await SharedPreferences.getInstance()).setBool(key, on);
    } catch (_) {}
  }

  Future<void> _create(DateTime at) async {
    await nxPush<void>(
      context,
      ActivityFormScreen(start: at),
    );
    if (mounted) _reload();
  }

  Future<void> _open(CalEvent e) async {
    await nxPush<void>(context, ActivityDetailScreen(row: e.raw));
    if (mounted) _reload();
  }

  /// Drag / resize in the time grid: shown at once, saved, undo for 5 s.
  Future<void> _reschedule(CalEvent e, DateTime start, DateTime end) async {
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    _store.replace(e.copyWith(start: start, end: end));
    try {
      await api.putEntity('activity', e.id, {'date_start': ymdhm(start), 'date_end': ymdhm(end)});
      HapticFeedback.lightImpact();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        key: const ValueKey('cal-moved-snack'),
        behavior: SnackBarBehavior.floating,
        content: Text(tr('${e.title}: ${start.day} ${monthShort(start.month)} ${hm(start)}–${hm(end)}')),
// Actions make snackbars persist by default; these must time out.
        persist: false,
        action: SnackBarAction(
          label: tr('เลิกทำ'),
          onPressed: () async {
            _store.replace(e);
            try {
              await api.putEntity('activity', e.id, {'date_start': ymdhm(e.start), 'date_end': ymdhm(e.end)});
            } catch (err) {
              messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(err)))));
            }
          },
        ),
      ));
    } catch (err) {
      _store.replace(e);
      HapticFeedback.heavyImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr('ย้ายไม่สำเร็จ: ${formatApiError(err)}'))));
    }
  }

  /// Long-press: duplicate or delete (with undo).
  Future<void> _eventMenu(CalEvent e) async {
    final row = e.raw;
    final id = e.id;
    if (id.isEmpty) return;
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.of(context);
    final title = entityTitle(row, module: 'activity');
    final pick = await showNxBlurPanel<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            title: Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text(e.allDay ? tr('ทั้งวัน') : '${hm(e.start)}–${hm(e.end)}'),
          ),
          ListTile(leading: const Icon(NxI.copySimple), title: Text(tr('ทำซ้ำ')), onTap: () => Navigator.pop(context, 'dup')),
          ListTile(leading: const Icon(NxI.trash), title: Text(tr('ลบ')), onTap: () => Navigator.pop(context, 'del')),
        ],
      ),
    );
    if (!mounted) return;
    if (pick == 'dup') {
      try {
        final newId = await api.duplicateEntity('activity', id);
        if (!mounted) return;
        _reload();
        if (newId.isNotEmpty) nxPush<void>(context, ActivityDetailScreen(row: {'id': newId}));
      } catch (err) {
        messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(err)))));
      }
    } else if (pick == 'del') {
      PendingEntityDeletes.instance.schedule(
        messenger: messenger,
        module: 'activity',
        ids: [id],
        label: title,
        commit: () async {
          await api.deleteEntity('activity', id);
          if (mounted) _reload();
        },
      );
    }
  }

  // ── build
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.select((AppConfig c) => c.session);
    final showIncoming = MenuAccess.allow(session, MenuAccess.incoming);
    final showPending = MenuAccess.allow(session, MenuAccess.pending);
    final filterCount = _lq.activeFilterCount;
    final title = switch (_mode) {
      _CalMode.incoming => 'งานใกล้ถึง',
      _CalMode.pending => 'งานค้าง',
      _CalMode.calendar => periodLabel(_view, _date),
    };
    return NxScrollScaffold(
      header: NxAppHeader(
        title: title,
        largeTitle: true,
        onTitleTap: _mode != _CalMode.calendar ? null : () => _setView(_view == CalView.year ? CalView.month : CalView.year),
        actions: [
          IconButton(
            tooltip: tr('ค้นหา'),
            icon: const Icon(NxI.magnifyingGlass),
            onPressed: () => _setView(CalView.list),
          ),
          IconButton(
            tooltip: filterCount > 0 ? tr('ตัวกรอง ($filterCount)') : tr('ตัวกรอง'),
            icon: const Icon(NxI.funnel),
            onPressed: _openFilter,
          ),
        ],
        menu: [
          if (_mode != _CalMode.calendar) NxHeaderMenuItem(label: 'ปฏิทิน', icon: NxI.calendarBlank, onTap: () => _setMode(_CalMode.calendar)),
          if (showIncoming && _mode != _CalMode.incoming) NxHeaderMenuItem(label: 'งานใกล้ถึง', icon: NxI.clockCountdown, onTap: () => _setMode(_CalMode.incoming)),
          if (showPending && _mode != _CalMode.pending) NxHeaderMenuItem(label: 'งานค้าง', icon: NxI.warningCircle, onTap: () => _setMode(_CalMode.pending)),
          NxHeaderMenuItem(
            label: _store.birthdays.enabled ? 'ซ่อนวันเกิดลูกค้า' : 'แสดงวันเกิดลูกค้า',
            icon: NxI.cake,
            onTap: () {
              _toggleBirthdays();
              setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: _showsToday || _mode != _CalMode.calendar
                ? const SizedBox.shrink()
                : Padding(padding: const EdgeInsets.only(bottom: 12, right: 6), child: CalTodayButton(onTap: _goToday)),
          ),
          NxCreateFab(onPressed: () => _create(_defaultStart(_date))),
        ],
      ),
      body: Column(
        children: [
          // View tabs with a sliding underline (ปี เดือน สัปดาห์ 3 วัน วัน รายการ).
          SizedBox(
            height: 42,
            // All seven fit the width (no sideways scrolling to reach "วัน" / "รายการ").
            child: TabBar(
              controller: _tabs,
              isScrollable: false,
              labelPadding: EdgeInsets.zero,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              unselectedLabelStyle: theme.textTheme.labelLarge,
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurfaceVariant,
              onTap: (i) => _setView(CalView.values[i]),
              tabs: [for (final v in CalView.values) Tab(key: ValueKey('cal-tab-${v.name}'), text: tr(v.label))],
            ),
          ),
          Expanded(
            key: _bodyKey,
            child: ClipRect(
              // Pull down at the top of any view to reload (no refresh button).
              child: NxRefresh(
                notificationPredicate: (n) => n.depth <= 2,
                onRefresh: _reload,
                child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(children: [...previous, ?current]),
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(_viewKey);
                  final finer = _view.index > _prev.index;
                  final begin = incoming ? (_fromTile ? 0.35 : (finer ? 0.92 : 1.08)) : (finer ? 1.08 : 0.92);
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      alignment: incoming ? _zoomAt : Alignment.center,
                      scale: Tween<double>(begin: begin, end: 1).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(key: ValueKey(_viewKey), child: _buildView()),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _viewKey => '${_view.name}-${_mode.name}-$_jump';

  Widget _buildView() {
    switch (_view) {
      case CalView.year:
        return CalYearView(
          store: _store,
          anchor: _date,
          onAnchor: (d) => setState(() => _date = d),
          onOpenMonth: (m, r) {
            final t = thaiNow();
            _date = m.year == t.year && m.month == t.month ? calDay(t) : m;
            _setView(CalView.month, from: r);
          },
        );
      case CalView.month:
        return CalMonthView(
          store: _store,
          selected: _date,
          onSelect: (d) => setState(() => _date = calDay(d)),
          onOpen: _open,
          onEventMenu: _eventMenu,
          onCreate: (d) => _create(_defaultStart(d)),
        );
      case CalView.week:
      case CalView.threeDay:
      case CalView.day:
        return CalTimeGrid(
          store: _store,
          view: _view,
          anchor: _date,
          onAnchor: (d) => setState(() => _date = calDay(d)),
          onOpen: _open,
          onCreateAt: (at, {bool allDay = false}) => _create(at),
          onReschedule: _reschedule,
          onOpenDay: (d) {
            _date = d;
            _setView(CalView.day);
          },
        );
      case CalView.list:
        final searchBox = Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            key: const ValueKey('cal-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              setState(() => _lq = _lq.copyWith(q: v.trim()));
              _store.refreshFilter();
            },
            decoration: InputDecoration(
              hintText: tr('ค้นหาชื่อนัด / สถานที่ / ลูกค้า'),
              prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
              isDense: true,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(NxI.x, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _lq = _lq.copyWith(q: ''));
                        _store.refreshFilter();
                      },
                    ),
            ),
          ),
        );
        if (_mode == _CalMode.calendar) {
          return CalAgendaView(store: _store, anchor: _date, onOpen: _open, onEventMenu: _eventMenu, header: searchBox);
        }
        return FutureBuilder<List<CalEvent>>(
          future: _special,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text(tr(formatApiError(snap.error!))));
            if (!snap.hasData) return const NxSkeletonCalendar();
            return CalAgendaView(
              store: _store,
              anchor: _date,
              events: [for (final e in snap.data!) if (_passes(e)) e],
              onOpen: _open,
              onEventMenu: _eventMenu,
              header: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: Icon(_mode == _CalMode.incoming ? NxI.clockCountdown : NxI.warningCircle, size: 16),
                    label: Text(tr(_mode == _CalMode.incoming ? 'งานใกล้ถึง' : 'งานค้าง')),
                    onDeleted: () => _setMode(_CalMode.calendar),
                  ),
                ),
              ),
            );
          },
        );
    }
  }
}
