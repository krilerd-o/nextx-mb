import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_hero_cta.dart';
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
  String? _fixLabel;
  String? _address;

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

  Future<void> _clock({required bool inn}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final config = context.read<AppConfig>();
    try {
      final fix = await _location.currentFix();
      _fixLabel = '${fix.latitude.toStringAsFixed(5)}, ${fix.longitude.toStringAsFixed(5)}';
      _address = fix.address;
      final queued = await config.punch(clockIn: inn, lat: fix.latitude, lng: fix.longitude, address: fix.address);
      if (queued) {
        final now = TimeOfDay.now().format(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('ไม่มีอินเทอร์เน็ต — บันทึก${inn ? 'เวลาเข้า' : 'เวลาออก'} $now ไว้ในเครื่องแล้ว จะส่งอัตโนมัติเมื่อออนไลน์')),
          ));
        }
        await _loadPending();
        return;
      }
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(inn ? 'ลงเวลาเข้าแล้ว' : 'ลงเวลาออกแล้ว'))),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clockIn = _summary?['clock_in_at']?.toString();
    final clockOut = _summary?['clock_out_at']?.toString();
    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ลงเวลา'),
      body: _loading
          ? const NxSkeletonForm(fields: 4)
          : NxRefresh(
              color: theme.colorScheme.primary,
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: NxBreakpoint.of(context).scrollPadding(context),
                children: [
                  Text(
                    tr('ใช้ตำแหน่งจากเครื่อง แล้วส่งไป /api/hr/attendance'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  NxSurfaceCard(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('วันนี้'), style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          tr([
                            if (clockIn != null) 'เข้า $clockIn',
                            if (clockOut != null) 'ออก $clockOut',
                            if (clockIn == null) 'ยังไม่ได้ลงเวลาเข้า',
                          ].join('\n')),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_fixLabel != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            tr('พิกัด $_fixLabel'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (_address != null && _address!.isNotEmpty)
                          Text(
                            tr(_address!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
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
                          Text(tr('จะส่งด้วยเวลาตามที่กดในเครื่อง เมื่อมีอินเทอร์เน็ต'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                          Text(tr('ส่งการลงเวลาไม่สำเร็จ: ${_punchLabel(f)}'), style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error)),
                          Text(tr(f['error']?.toString() ?? ''), style: theme.textTheme.bodySmall),
                          Text(tr('แจ้ง HR พร้อมเวลานี้เพื่อแก้ไขในระบบ'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                    Text(tr(formatApiError(_error!)), style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _reload, child: Text(tr('ลองใหม่'))),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(tr('ประวัติเดือนนี้'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final row in _history.take(31))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NxSurfaceCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(thaiDate(row['work_date'], year: uiYear), style: theme.textTheme.titleMedium),
                              Text(
                                tr([
                                  if (row['clock_in_at'] != null) 'เข้า ${_hm(row['clock_in_at'])}${offlinePunchFlags(row).$1 ? ' (ออฟไลน์)' : ''}',
                                  if (row['clock_out_at'] != null) 'ออก ${_hm(row['clock_out_at'])}${offlinePunchFlags(row).$2 ? ' (ออฟไลน์)' : ''}',
                                ].join(' · ')),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  NxHeroCta(
                    label: 'Clock In',
                    busy: _busy,
                    onPressed: _busy ? null : () => _clock(inn: true),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _clock(inn: false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    ),
                    child: Text(tr('Clock Out')),
                  ),
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
  final d = parseThai(raw);
  if (d == null) return '$raw';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
