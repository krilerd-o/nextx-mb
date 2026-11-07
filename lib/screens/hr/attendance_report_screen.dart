import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../../core/thai_time.dart';
import '../../core/i18n.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String punchTime(dynamic raw) {
  final d = parseThai(raw?.toString() ?? '');
  if (d == null) return '—';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// HR view: who clocked in/out on a day, with location links.
class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _day = thaiNow();
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _dash = {};
  bool _loading = true;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AppConfig>().apiClient;
    try {
      final rows = await api.getAttendanceReport(_ymd(_day));
      Map<String, dynamic> dash = {};
      try {
        dash = await api.getHrDashboard();
      } catch (_) {
        // Optional summary; the report itself is what matters.
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _dash = dash;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDay() async {
    final now = thaiNow();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (d == null) return;
    setState(() => _day = d);
    await _load();
  }

  Future<void> _openMap(dynamic lat, dynamic lng) async {
    final la = num.tryParse('$lat');
    final ln = num.tryParse('$lng');
    if (la == null || ln == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$la,$ln');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = _ymd(_day) == _ymd(thaiNow());
    final needle = _query.trim().toLowerCase();
    final rows = needle.isEmpty
        ? _rows
        : _rows.where((r) => (r['user_name']?.toString() ?? '').toLowerCase().contains(needle)).toList();
    final stillIn = _rows.where((r) => r['clock_in_at'] != null && r['clock_out_at'] == null).length;

    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'รายงานลงเวลา',
        actions: [IconButton(tooltip: tr('เลือกวัน'), icon: const Icon(NxI.calendarBlank), onPressed: _pickDay)],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(NxI.caretLeft),
                  onPressed: () {
                    setState(() => _day = _day.subtract(const Duration(days: 1)));
                    _load();
                  },
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      tr('${today ? 'วันนี้ · ' : ''}${_day.day}/${_day.month}/${uiYear(_day.year)}'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(NxI.caretRight),
                  onPressed: today
                      ? null
                      : () {
                          setState(() => _day = _day.add(const Duration(days: 1)));
                          _load();
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _Stat('ลงเวลาแล้ว', '${_rows.length}', cs.primary)),
                const SizedBox(width: 8),
                Expanded(child: _Stat('ยังไม่ออก', '$stillIn', const Color(0xFFF59E0B))),
                if (today && _dash['pending_leave_count'] != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _Stat('ลารออนุมัติ', '${_dash['pending_leave_count']}', cs.tertiary)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: tr('ค้นหาชื่อพนักงาน'),
                prefixIcon: const Icon(NxI.magnifyingGlass),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            if (_loading) const NxSkeletonList(rows: 5),
            if (_error != null) Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error)),
            if (!_loading && _error == null && rows.isEmpty)
              Padding(padding: EdgeInsets.all(40), child: Center(child: Text(tr('ยังไม่มีใครลงเวลาในวันนี้')))),
            if (!_loading)
              for (final r in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: r['clock_out_at'] == null ? cs.primaryContainer : cs.surfaceContainerHighest,
                      child: Icon(NxI.user, color: r['clock_out_at'] == null ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                    ),
                    title: Text(tr(r['user_name']?.toString() ?? '')),
                    subtitle: Text(
                      tr([
                        'เข้า ${punchTime(r['clock_in_at'])} · ออก ${punchTime(r['clock_out_at'])}',
                        if ((r['clock_in_address']?.toString() ?? '').isNotEmpty) r['clock_in_address'].toString(),
                      ].join('\n')),
                    ),
                    isThreeLine: (r['clock_in_address']?.toString() ?? '').isNotEmpty,
                    trailing: r['clock_in_lat'] == null
                        ? null
                        : IconButton(
                            tooltip: tr('ดูตำแหน่ง'),
                            icon: const Icon(NxI.mapPin),
                            onPressed: () => _openMap(r['clock_in_lat'], r['clock_in_lng']),
                          ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(value), style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
          Text(tr(label), style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
