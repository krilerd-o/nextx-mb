import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/realtime_service.dart';
import '../../core/entity_display.dart';
import '../../core/menu_access.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_create_fab.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../crm/entity_create_screen.dart';
import 'activity_detail_screen.dart';
import '../../widgets/nx_icons.dart';

class CalendarHomeScreen extends StatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  State<CalendarHomeScreen> createState() => _CalendarHomeScreenState();
}

enum _CalMode { agenda, incoming, pending }

class _CalendarHomeScreenState extends State<CalendarHomeScreen> {
  var _revision = 0;
  _CalMode _mode = _CalMode.agenda;
  DateTime _selectedDay = DateTime.now();
  bool _weekView = false;
  StreamSubscription<RealtimeEvent>? _live;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Activity created/changed anywhere in the business → refresh.
    _live = RealtimeService.instance.on('calendar:activity_upsert').listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _revision++);
      });
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _title {
    switch (_mode) {
      case _CalMode.incoming:
        return 'งานใกล้ถึง';
      case _CalMode.pending:
        return 'งานค้าง';
      case _CalMode.agenda:
        return 'ปฏิทิน';
    }
  }

  Color _tint(String? status) {
    switch (status?.toLowerCase()) {
      case 'held':
      case 'completed':
        return const Color(0xFF10B981);
      case 'planned':
      case 'not started':
        return const Color(0xFF0EA5E9);
      case 'cancelled':
        return const Color(0xFFF97316);
      default:
        return const Color(0xFFEC4899);
    }
  }

  Future<List<Map<String, dynamic>>> _fetch() {
    final extra = <String, String>{
      'sort': 'date_start',
      'order': _mode == _CalMode.pending ? 'desc' : 'asc',
    };
    switch (_mode) {
      case _CalMode.incoming:
        extra['involved'] = '1';
        break;
      case _CalMode.pending:
        extra['overdue'] = '1';
        break;
      case _CalMode.agenda:
        // Month range; in week view widen it when the week crosses a month edge.
        final ws = weekStart(_selectedDay);
        var start = DateTime(_selectedDay.year, _selectedDay.month, 1);
        var end = DateTime(_selectedDay.year, _selectedDay.month + 1, 0);
        if (_weekView) {
          if (ws.isBefore(start)) start = ws;
          final we = ws.add(const Duration(days: 6));
          if (we.isAfter(end)) end = we;
        }
        extra['calendar_from'] = _ymd(start);
        extra['calendar_to'] = _ymd(end);
        break;
    }
    return context.read<AppConfig>().apiClient.getEntityList(
          'activity',
          limit: 200,
          extra: extra,
        ).then((p) => p.items);
  }

  Future<void> _openCreate() async {
    await nxPush<void>(
      context,
      const EntityCreateScreen(module: 'activity', title: 'นัดหมายใหม่'),
    );
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final twoPane = NxBreakpoint.of(context).twoPane;
    final session = context.watch<AppConfig>().session;
    final showIncoming = MenuAccess.allow(session, MenuAccess.incoming);
    final showPending = MenuAccess.allow(session, MenuAccess.pending);
    return Scaffold(
      appBar: NxAppHeader(
        title: _title,
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: () => setState(() => _revision++),
          ),
          if (twoPane) NxAddButton(tooltip: 'นัดหมาย', onPressed: _openCreate),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: _fetch,
        skeleton: const NxSkeletonList(),
        builder: (context, list) {
          final dayKey = _ymd(_selectedDay);
          final byDay = groupActivitiesByDay(list);
          final visible = _mode == _CalMode.agenda ? (byDay[dayKey] ?? const <Map<String, dynamic>>[]) : list;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_CalMode>(
                segments: [
                  const ButtonSegment(value: _CalMode.agenda, label: Text('ปฏิทิน'), icon: Icon(NxI.calendarBlank)),
                  if (showIncoming)
                    const ButtonSegment(value: _CalMode.incoming, label: Text('ใกล้ถึง'), icon: Icon(NxI.clockCountdown)),
                  if (showPending)
                    const ButtonSegment(value: _CalMode.pending, label: Text('ค้าง'), icon: Icon(NxI.warningCircle)),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  _mode = v.first;
                  _revision++;
                }),
              ),
              const SizedBox(height: 12),
              if (_mode == _CalMode.agenda) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _weekView = !_weekView;
                      _revision++;
                    }),
                    icon: Icon(_weekView ? NxI.calendarBlank : NxI.listBullets, size: 18),
                    label: Text(_weekView ? 'ดูรายเดือน' : 'ดูรายสัปดาห์'),
                  ),
                ),
                if (_weekView)
                  NxWeekStrip(
                    selected: _selectedDay,
                    counts: {for (final e in byDay.entries) e.key: e.value.length},
                    onSelect: (d) {
                      final monthChanged = d.month != _selectedDay.month || d.year != _selectedDay.year;
                      setState(() {
                        _selectedDay = d;
                        if (monthChanged) _revision++;
                      });
                    },
                  )
                else
                NxMonthGrid(
                  month: DateTime(_selectedDay.year, _selectedDay.month),
                  selected: _selectedDay,
                  counts: {for (final e in byDay.entries) e.key: e.value.length},
                  onSelect: (d) => setState(() => _selectedDay = d),
                  onMonthChange: (m) => setState(() {
                    final now = DateTime.now();
                    _selectedDay = (m.year == now.year && m.month == now.month) ? now : m;
                    _revision++;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_selectedDay.day}/${_selectedDay.month}/${_selectedDay.year + 543} · ${visible.length} กิจกรรม',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
              ],
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('ไม่มีกิจกรรม')),
                ),
              for (final row in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NxSurfaceCard(
                    color: _tint(row['status']?.toString()).withValues(alpha: 0.14),
                    onTap: () {
                      nxPush<void>(context, ActivityDetailScreen(row: row))
                          .then((_) => setState(() => _revision++));
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _tint(row['status']?.toString()),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entityTitle(row, module: 'activity'),
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                [
                                  activityTimeLabel(row),
                                  row['status'],
                                  row['location'],
                                ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: NxCreateFab(
        label: 'นัดหมาย',
        onPressed: _openCreate,
      ),
    );
  }
}

/// Local `yyyy-MM-dd` → activities starting that day (server sends UTC ISO).
Map<String, List<Map<String, dynamic>>> groupActivitiesByDay(List<Map<String, dynamic>> rows) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final raw = r['date_start']?.toString() ?? '';
    final d = DateTime.tryParse(raw);
    final key = d == null
        ? (raw.length >= 10 ? raw.substring(0, 10) : raw)
        : _ymdOf(raw.length <= 10 ? d : d.toLocal());
    if (key.isEmpty) continue;
    (out[key] ??= []).add(r);
  }
  return out;
}

String _ymdOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "09:30–10:30" (local) or the raw value when it cannot be parsed.
String activityTimeLabel(Map<String, dynamic> row) {
  String hm(dynamic v) {
    final raw = v?.toString() ?? '';
    final d = DateTime.tryParse(raw);
    if (d == null || raw.length <= 10) return '';
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  final a = hm(row['date_start']);
  final b = hm(row['due_date'] ?? row['date_end']);
  if (a.isEmpty) return row['date_start']?.toString() ?? '';
  return b.isEmpty ? a : '$a–$b';
}

const _thMonths = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
const _thWeek = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

/// Month grid (Mon-first) with a dot per day that has activities.
class NxMonthGrid extends StatelessWidget {
  const NxMonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.counts,
    required this.onSelect,
    required this.onMonthChange,
  });

  final DateTime month;
  final DateTime selected;
  final Map<String, int> counts;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final now = DateTime.now();
    final cells = <Widget>[
      for (final w in _thWeek)
        Center(child: Text(w, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        Builder(builder: (context) {
          final d = DateTime(month.year, month.month, day);
          final isSel = d.year == selected.year && d.month == selected.month && d.day == selected.day;
          final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
          final n = counts[_ymdOf(d)] ?? 0;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(d),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isSel ? cs.primary : (isToday ? cs.primaryContainer : null),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSel ? cs.onPrimary : null,
                      fontWeight: isToday || isSel ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: n == 0 ? Colors.transparent : (isSel ? cs.onPrimary : cs.primary),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(NxI.caretLeft),
                  onPressed: () => onMonthChange(DateTime(month.year, month.month - 1)),
                ),
                Expanded(
                  child: Center(
                    child: Text('${_thMonths[month.month - 1]} ${month.year + 543}', style: theme.textTheme.titleMedium),
                  ),
                ),
                TextButton(onPressed: () => onMonthChange(DateTime(now.year, now.month)), child: const Text('วันนี้')),
                IconButton(
                  icon: const Icon(NxI.caretRight),
                  onPressed: () => onMonthChange(DateTime(month.year, month.month + 1)),
                ),
              ],
            ),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.05,
              children: cells,
            ),
          ],
        ),
      ),
    );
  }
}

/// Monday of the week containing [d].
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 7-day strip (Mon–Sun) with prev/next week and a dot per busy day.
class NxWeekStrip extends StatelessWidget {
  const NxWeekStrip({super.key, required this.selected, required this.counts, required this.onSelect});

  final DateTime selected;
  final Map<String, int> counts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final start = weekStart(selected);
    final now = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            IconButton(icon: const Icon(NxI.caretLeft), onPressed: () => onSelect(selected.subtract(const Duration(days: 7)))),
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Builder(builder: (context) {
                  final d = start.add(Duration(days: i));
                  final isSel = d.year == selected.year && d.month == selected.month && d.day == selected.day;
                  final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
                  final n = counts[_ymdOf(d)] ?? 0;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel ? cs.primary : (isToday ? cs.primaryContainer : null),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(_thWeek[i], style: theme.textTheme.labelSmall?.copyWith(color: isSel ? cs.onPrimary : cs.onSurfaceVariant)),
                          Text('${d.day}', style: theme.textTheme.titleMedium?.copyWith(color: isSel ? cs.onPrimary : null)),
                          Text(
                            n == 0 ? ' ' : '$n',
                            style: theme.textTheme.labelSmall?.copyWith(color: isSel ? cs.onPrimary : cs.primary, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            IconButton(icon: const Icon(NxI.caretRight), onPressed: () => onSelect(selected.add(const Duration(days: 7)))),
          ],
        ),
      ),
    );
  }
}

