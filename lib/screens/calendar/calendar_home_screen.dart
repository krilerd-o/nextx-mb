import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
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
        final start = DateTime(_selectedDay.year, _selectedDay.month, 1);
        final end = DateTime(_selectedDay.year, _selectedDay.month + 1, 0);
        extra['calendar_from'] = _ymd(start);
        extra['calendar_to'] = _ymd(end);
        break;
    }
    return context.read<AppConfig>().apiClient.getEntityList(
          'activity',
          limit: _mode == _CalMode.agenda ? 80 : 200,
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
        menu: [
          NxHeaderMenuItem(
            label: 'ปฏิทิน',
            icon: NxI.calendarBlank,
            onTap: () => setState(() {
              _mode = _CalMode.agenda;
              _revision++;
            }),
          ),
          if (showIncoming)
            NxHeaderMenuItem(
              label: 'งานใกล้ถึง',
              icon: NxI.clockCountdown,
              onTap: () => setState(() {
                _mode = _CalMode.incoming;
                _revision++;
              }),
            ),
          if (showPending)
            NxHeaderMenuItem(
              label: 'งานค้าง',
              icon: NxI.warningCircle,
              onTap: () => setState(() {
                _mode = _CalMode.pending;
                _revision++;
              }),
            ),
        ],
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
          final visible = _mode == _CalMode.agenda
              ? list.where((row) {
                  final start = row['date_start']?.toString() ?? '';
                  return start.startsWith(dayKey);
                }).toList()
              : list;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_mode == _CalMode.agenda)
                CalendarDatePicker(
                  initialDate: _selectedDay,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  onDateChanged: (d) {
                    final monthChanged =
                        d.month != _selectedDay.month || d.year != _selectedDay.year;
                    setState(() => _selectedDay = d);
                    if (monthChanged) setState(() => _revision++);
                  },
                ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('ไม่มีกิจกรรม')),
                ),
              for (final row in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NxSurfaceCard(
                    color: _tint(row['status']?.toString()).withOpacity(0.14),
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
                                  row['date_start'],
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
