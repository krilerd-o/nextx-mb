import 'package:flutter/material.dart';
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
      final now = DateTime.now();
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
    final api = context.read<AppConfig>().apiClient;
    try {
      final fix = await _location.currentFix();
      _fixLabel = '${fix.latitude.toStringAsFixed(5)}, ${fix.longitude.toStringAsFixed(5)}';
      _address = fix.address;
      if (inn) {
        await api.clockIn(latitude: fix.latitude, longitude: fix.longitude, address: fix.address);
      } else {
        await api.clockOut(latitude: fix.latitude, longitude: fix.longitude, address: fix.address);
      }
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(inn ? 'ลงเวลาเข้าแล้ว' : 'ลงเวลาออกแล้ว')),
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
    return Scaffold(
      appBar: const NxAppHeader(title: 'ลงเวลา'),
      body: _loading
          ? const NxSkeletonForm(fields: 4)
          : RefreshIndicator(
              color: theme.colorScheme.primary,
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: NxBreakpoint.of(context).scrollPadding(context),
                children: [
                  Text(
                    'ใช้ตำแหน่งจากเครื่อง แล้วส่งไป /api/hr/attendance',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  NxSurfaceCard(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('วันนี้', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (clockIn != null) 'เข้า $clockIn',
                            if (clockOut != null) 'ออก $clockOut',
                            if (clockIn == null) 'ยังไม่ได้ลงเวลาเข้า',
                          ].join('\n'),
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_fixLabel != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'พิกัด $_fixLabel',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (_address != null && _address!.isNotEmpty)
                          Text(
                            _address!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(formatApiError(_error!), style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _reload, child: const Text('ลองใหม่')),
                  ],
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('ประวัติเดือนนี้', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final row in _history.take(31))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NxSurfaceCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row['work_date']?.toString() ?? '', style: theme.textTheme.titleMedium),
                              Text(
                                [
                                  if (row['clock_in_at'] != null) 'เข้า ${row['clock_in_at']}',
                                  if (row['clock_out_at'] != null) 'ออก ${row['clock_out_at']}',
                                ].join(' · '),
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
                    child: const Text('Clock Out'),
                  ),
                ],
              ),
            ),
    );
  }
}
