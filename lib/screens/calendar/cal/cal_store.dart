import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../services/api_client.dart';
import 'cal_birthdays.dart';
import 'cal_model.dart';

/// Activities for the calendar, loaded a month at a time and cached, so
/// moving between views/periods only fetches what is missing.
class CalStore extends ChangeNotifier {
  CalStore(this._api, {String? scope}) : birthdays = CalBirthdays(_api, scope: scope) {
    birthdays.addListener(notifyListeners);
  }

  final ApiClient _api;

  /// Customer birthdays (Lead / Contact / Account) shown alongside activities.
  final CalBirthdays birthdays;

  /// Tapping a birthday anywhere in the calendar opens its card.
  void Function(CalBirthday b, DateTime day, Rect? anchor)? onBirthday;

  void openBirthday(BuildContext context, CalBirthday b, DateTime day) {
    final box = context.findRenderObject() as RenderBox?;
    onBirthday?.call(b, day, box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    birthdays.removeListener(notifyListeners);
    birthdays.dispose();
    busy.dispose();
    super.dispose();
  }

  /// Month loads can finish after the calendar is gone (business switched).
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
  final Map<String, List<CalEvent>> _months = {};
  final Set<String> _loading = {};
  Object? error;

  /// Applied to every view (search / mine / type / status).
  bool Function(CalEvent e)? filter;

  static const cols = 'id,subject,date_start,date_end,status,activitytype,location,checkindate,checkoutdate,'
      'smownerid,account_name,contact_name,related_module,related_id,all_day,due_date';

  static String _mk(DateTime d) => '${d.year}-${d.month}';

  bool get loading => _loading.isNotEmpty;

  /// Months are loading (for a thin progress line). Set after the frame: views
  /// ask for months while they build.
  final ValueNotifier<bool> busy = ValueNotifier(false);

  void _syncBusy() => SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) busy.value = loading;
      });
  bool hasMonth(DateTime d) => _months.containsKey(_mk(d));

  /// Loads every month touching [from]…[to] that is not cached yet.
  Future<void> ensure(DateTime from, DateTime to) async {
    final want = <DateTime>[];
    for (var m = DateTime(from.year, from.month); !m.isAfter(DateTime(to.year, to.month)); m = DateTime(m.year, m.month + 1)) {
      final k = _mk(m);
      if (!_months.containsKey(k) && !_loading.contains(k)) want.add(m);
    }
    if (birthdays.enabled && !birthdays.loaded) birthdays.load(); // once, in the background
    if (want.isEmpty) return;
    for (final m in want) {
      _loading.add(_mk(m));
    }
    _syncBusy();
    // Views call this while building: only notify once data has arrived.
    await Future.wait([for (final m in want) _loadMonth(m)]);
    _syncBusy();
    notifyListeners();
  }

  Future<void> _loadMonth(DateTime m) async {
    final k = _mk(m);
    try {
      final page = await _api.getEntityList('activity', limit: 500, extra: {
        'cols': cols,
        'sort': 'date_start',
        'order': 'asc',
        'calendar_from': calKey(DateTime(m.year, m.month, 1)),
        'calendar_to': calKey(DateTime(m.year, m.month + 1, 0)),
      });
      _months[k] = [for (final r in page.items) ?CalEvent.from(r)];
      error = null;
    } catch (e) {
      error = e;
    } finally {
      _loading.remove(k);
    }
  }

  /// Drops the cache (realtime change / pull to refresh) and reloads [from]…[to].
  Future<void> reload(DateTime from, DateTime to) async {
    _months.clear();
    await Future.wait([ensure(from, to), if (birthdays.enabled) birthdays.load(force: true)]);
  }

  Iterable<CalEvent> get _all sync* {
    final seen = <String>{};
    for (final l in _months.values) {
      for (final e in l) {
        if (e.id.isNotEmpty && !seen.add(e.id)) continue; // a multi-month event appears in each month
        if (filter == null || filter!(e)) yield e;
      }
    }
  }

  /// Events touching [day], all-day first then by start.
  List<CalEvent> on(DateTime day) {
    final l = [for (final e in _all) if (e.on(day)) e];
    l.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
    return l;
  }

  /// Events touching [from, to).
  List<CalEvent> between(DateTime from, DateTime to) {
    final l = [for (final e in _all) if (e.start.isBefore(to) && e.end.isAfter(from)) e];
    l.sort((a, b) => a.start.compareTo(b.start));
    return l;
  }

  /// Number of events per day key in [month].
  Map<String, int> countsIn(DateTime month) {
    final out = <String, int>{};
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 1);
    for (final e in _all) {
      if (!e.start.isBefore(last) || !e.end.isAfter(first)) continue;
      for (var d = calDay(e.start.isBefore(first) ? first : e.start); d.isBefore(last) && d.isBefore(e.end); d = d.add(const Duration(days: 1))) {
        out.update(calKey(d), (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return out;
  }

  /// Optimistic local change (drag / resize) — replaces by id.
  void replace(CalEvent e) {
    for (final l in _months.values) {
      final i = l.indexWhere((x) => x.id == e.id);
      if (i >= 0) l[i] = e;
    }
    notifyListeners();
  }

  void refreshFilter() => notifyListeners();
}
