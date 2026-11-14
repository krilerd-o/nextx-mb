import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_place_panel.dart';
import '../calendar/visit_check_sheet.dart' show thaiDateTime, stayDuration;
import 'attendance_punch_sheet.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../core/error_reporting.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_refresh.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _location = LocationService();
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _history = [];
  bool _busy = false;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadPending();
  }

  List<Map<String, dynamic>> _pending = const [];

  Future<void> _loadPending() async {
    final config = context.read<AppConfig>();
    await config.flushOfflineQueue();
    final list = await config.pendingPunches();
    if (mounted) setState(() => _pending = list);
  }

  static String _punchLabel(Map<String, dynamic> p) {
    final at = parseThai(p['at']?.toString() ?? '');
    final t = at == null ? '' : '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return '${p['dir'] == 'out' ? 'ออก' : 'เข้า'} $t';
  }

  Future<void> _reload() async {
    final had = _summary != null || _history.isNotEmpty;
    if (!had) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final api = context.read<AppConfig>().apiClient;
      final summary = await api.getAttendanceSummary();
      final now = thaiNow();
      final from = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final to =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      var history = <Map<String, dynamic>>[];
      try {
        history = await api.getAttendance(dateFrom: from, dateTo: to);
      } catch (e, s) {
      ErrorReporting.report(e, s);
    }
      if (mounted) {
        setState(() {
          _summary = summary;
          _history = history;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Opens the clock in / out window (map, time, place, optional photos).
  Future<void> _clock({required bool inn}) async {
    final r = await showAttendancePunchSheet(context, clockIn: inn, clockedInAt: parseThai(_summary?['clock_in_at']), location: _location);
    if (r == null || !mounted) return;
    if (r.queued) {
      await _loadPending();
    } else {
      await _reload();
    }
  }

  /// Where a punch was made: small map + coordinates + address.
  void _showPlace(String title, DateTime? at, Object? lat, Object? lng, Object? address) {
    showNxPlacePanel(context, title: title, at: at, lat: lat, lng: lng, address: address);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = _summary;
    final inAt = parseThai(s?['clock_in_at']);
    final outAt = parseThai(s?['clock_out_at']);
    const green = Color(0xFF16A34A), orange = Color(0xFFEA580C);
    final state = inAt == null ? 0 : (outAt == null ? 1 : 2);
    final now = thaiNow();
    final stateColor = [cs.onSurfaceVariant, green, cs.primary][state];

    Widget punchRow(String label, DateTime at, Object? lat, Object? lng, Object? address, Color color, IconData icon) => InkWell(
          key: ValueKey('att-$label'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showPlace(label, at, lat, lng, address),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr(label)}  ${_hm(at)}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    (address?.toString() ?? '').isNotEmpty
                        ? address.toString()
                        : (lat != null ? '${double.tryParse('$lat')?.toStringAsFixed(5)}, ${double.tryParse('$lng')?.toStringAsFixed(5)}' : tr('ไม่มีพิกัด')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
              Icon(NxI.mapPin, size: 18, color: cs.outline),
            ]),
          ),
        );

    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ลงเวลา'),
      body: _loading
          ? const _AttendanceSkeleton()
          : NxRefresh(
              color: cs.primary,
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: NxBreakpoint.of(context).scrollPadding(context),
                children: [
                  // Today: state, both punches (tap for map), and the one action.
                  Container(
                    key: const ValueKey('att-today'),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color.alphaBlend(stateColor.withValues(alpha: 0.12), cs.surfaceContainerHighest), cs.surfaceContainerHighest],
                      ),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(thaiDateTime(now).split(' · ').first, style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: stateColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(state == 0 ? NxI.clock : NxI.checkCircle, size: 14, color: stateColor),
                            const SizedBox(width: 4),
                            Text(
                              tr(['ยังไม่ได้ลงเวลา', 'เข้างานแล้ว', 'ลงเวลาครบแล้ว'][state]),
                              key: const ValueKey('att-state'),
                              style: theme.textTheme.labelMedium?.copyWith(color: stateColor, fontWeight: FontWeight.w800),
                            ),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        state == 0
                            ? tr('ยังไม่ได้ลงเวลาเข้า')
                            : state == 1
                                ? tr('ทำงานไปแล้ว ${stayDuration(inAt!, now)}')
                                : tr('รวมเวลาทำงาน ${stayDuration(inAt!, outAt!)}'),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (inAt != null) ...[
                        const SizedBox(height: 8),
                        punchRow('เข้างาน', inAt, s?['clock_in_lat'], s?['clock_in_lng'], s?['clock_in_address'], green, NxI.signIn),
                      ],
                      if (outAt != null) punchRow('ออกงาน', outAt, s?['clock_out_lat'], s?['clock_out_lng'], s?['clock_out_address'], orange, NxI.signOut),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('att-action'),
                        onPressed: _busy || state == 2 ? null : () => _clock(inn: state == 0),
                        style: FilledButton.styleFrom(
                          backgroundColor: state == 0 ? green : orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(54),
                          shape: const StadiumBorder(),
                          textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        icon: Icon(state == 0 ? NxI.signIn : (state == 1 ? NxI.signOut : NxI.checkCircle)),
                        label: Text(tr(['ลงเวลาเข้า', 'ลงเวลาออก', 'ลงเวลาครบวันนี้แล้ว'][state])),
                      ),
                    ]),
                  ),
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    NxSurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('รอส่ง (ลงเวลาตอนออฟไลน์)'), style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(tr(_pending.map(_punchLabel).join(' · ')), style: theme.textTheme.bodySmall),
                          Text(tr('จะส่งด้วยเวลาตามที่กดในเครื่อง เมื่อมีอินเทอร์เน็ต'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          TextButton(onPressed: _loadPending, child: Text(tr('ส่งตอนนี้'))),
                        ],
                      ),
                    ),
                  ],
                  for (final f in context.select((AppConfig c) => c.failedPunches)) ...[
                    const SizedBox(height: 12),
                    NxSurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('ส่งการลงเวลาไม่สำเร็จ: ${_punchLabel(f)}'), style: theme.textTheme.titleSmall?.copyWith(color: cs.error)),
                          Text(tr(f['error']?.toString() ?? ''), style: theme.textTheme.bodySmall),
                          Text(tr('แจ้ง HR พร้อมเวลานี้เพื่อแก้ไขในระบบ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.read<AppConfig>().dismissFailedPunch(f),
                              child: Text(tr('แจ้ง HR แล้ว')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _reload, child: Text(tr('ลองใหม่'))),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(tr('ประวัติเดือนนี้'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    NxSurfaceCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Column(children: [
                        for (final (i, row) in _history.take(31).indexed) ...[
                          if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                          Builder(builder: (context) {
                            final a = parseThai(row['clock_in_at']), b = parseThai(row['clock_out_at']);
                            final (offIn, offOut) = offlinePunchFlags(row);
                            return InkWell(
                              onTap: a == null ? null : () => _showPlace('เข้างาน', a, row['clock_in_lat'], row['clock_in_lng'], row['clock_in_address']),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(children: [
                                  SizedBox(
                                    width: 92,
                                    child: Text(thaiDate(row['work_date'], year: uiYear), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (a != null) '${tr('เข้า')} ${_hm(a)}${offIn ? '*' : ''}',
                                        if (b != null) '${tr('ออก')} ${_hm(b)}${offOut ? '*' : ''}',
                                      ].join('  ·  '),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  if (a != null && b != null)
                                    Text(stayDuration(a, b), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                                ]),
                              ),
                            );
                          }),
                        ],
                      ]),
                    ),
                    if (_history.any((r) => offlinePunchFlags(r).$1 || offlinePunchFlags(r).$2))
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Text(tr('* ลงเวลาตอนออฟไลน์ ส่งภายหลัง'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

/// (clock-in, clock-out) sent later from the app without network — the server
/// flags them (`clock_*_offline`, `source = app_offline`).
(bool, bool) offlinePunchFlags(Map<String, dynamic> row) {
  bool on(Object? v) => v == true || v?.toString() == '1';
  return (
    row['clock_in_at'] != null && (on(row['clock_in_offline']) || row['source'] == 'app_offline'),
    row['clock_out_at'] != null && on(row['clock_out_offline']),
  );
}

String _hm(dynamic raw) {
  final d = raw is DateTime ? raw : parseThai(raw);
  if (d == null) return '$raw';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Attendance while loading: the gradient today card (date, state pill,
/// headline, the 54 px clock button) and this month's history rows.
class _AttendanceSkeleton extends StatelessWidget {
  const _AttendanceSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NxSkeleton(
      key: const ValueKey('att-skeleton'),
      child: NxSkeletonListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(cs.primary.withValues(alpha: 0.08), cs.surfaceContainerHighest), cs.surfaceContainerHighest],
              ),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [NxBone(width: 120, height: 13), Spacer(), NxBone(width: 104, height: 24, radius: 12)]),
              SizedBox(height: 14),
              NxBoneLine(0.62, height: 24, radius: 10),
              SizedBox(height: 18),
              NxBone(height: 54, radius: 27),
            ]),
          ),
          const SizedBox(height: 18),
          const NxBone(width: 110, height: 15),
          const SizedBox(height: 10),
          NxSkeletonCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) Divider(height: 0.5, thickness: 0.5, color: cs.outlineVariant.withValues(alpha: 0.5)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    const NxBone(width: 64, height: 12),
                    const Spacer(),
                    NxBone(width: i.isEven ? 92 : 76, height: 12),
                  ]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
