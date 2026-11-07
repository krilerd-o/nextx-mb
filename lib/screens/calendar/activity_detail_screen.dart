import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../crm/entity_detail_parts.dart' show AttachmentStrip;
import 'visit_check_sheet.dart';

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  final _location = LocationService();
  Map<String, dynamic>? _visit;
  bool _busy = false;
  Object? _error;

  String get _id => strId(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _loadVisit();
  }

  Future<void> _loadVisit() async {
    try {
      final visit = await context.read<AppConfig>().apiClient.getActivityVisit(_id);
      if (mounted) setState(() => _visit = visit);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _check({required bool inn}) async {
    final checkedAt = DateTime.tryParse(_visit?['checkindate']?.toString().replaceFirst(' ', 'T') ?? '');
    final r = await showVisitCheckSheet(
      context,
      activityId: _id,
      checkIn: inn,
      placeName: widget.row['location']?.toString(),
      checkedInAt: checkedAt,
      location: _location,
    );
    if (r == null || !mounted) return;
    await _loadVisit();
  }

  Future<void> _pickPhotos({required bool camera}) async {
    final api = context.read<AppConfig>().apiClient;
    final picker = ImagePicker();
    final files = <XFile>[];
    if (camera) {
      final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
      if (shot != null) files.add(shot);
    } else {
      files.addAll(await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600));
    }
    if (!mounted || files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final parts = <MultipartFile>[];
      for (final f in files) {
        final bytes = await f.readAsBytes();
        parts.add(MultipartFile.fromBytes(bytes, filename: f.name));
      }
      await api.uploadActivityPhotos(_id, parts);
      await _loadVisit();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rsvp(String response) async {
    setState(() => _busy = true);
    try {
      await context.read<AppConfig>().apiClient.activityRsvp(_id, response);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('RSVP: $response')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _rsvpLabels = {'accepted': 'เข้าร่วม', 'tentative': 'ไม่แน่ใจ', 'declined': 'ไม่เข้าร่วม'};

  String _when(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString().replaceFirst(' ', 'T') ?? '');
    if (d == null) return raw?.toString() ?? '—';
    return thaiDateTime(d.toLocal()).replaceFirst(RegExp(r':\d\d$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = widget.row;
    final checkedIn = _visit?['checked_in'] == true || (_visit?['checkindate']?.toString().isNotEmpty ?? false);
    final checkedOut = _visit?['checked_out'] == true || (_visit?['checkoutdate']?.toString().isNotEmpty ?? false);
    final photos = extractMapList(_visit?['photos']);
    return Scaffold(
      appBar: NxAppHeader(title: entityTitle(row, module: 'activity')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          NxSurfaceCard(
            radius: 26,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entityTitle(row, module: 'activity'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _line(context, NxI.calendarBlank, '${_when(row['date_start'])}  →  ${_when(row['date_end'])}'),
                if ((row['location']?.toString() ?? '').isNotEmpty) _line(context, NxI.mapPin, row['location'].toString()),
                if ((row['status']?.toString() ?? '').isNotEmpty) _line(context, NxI.flag, row['status'].toString()),
              ],
            ),
          ),
          if ((row['description']?.toString() ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            NxSurfaceCard(padding: const EdgeInsets.all(16), child: NxHtmlView(html: row['description'].toString())),
          ],
          const SizedBox(height: 16),
          Text('การเยี่ยม', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          NxSurfaceCard(
            radius: 24,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _stepRow(context, done: checkedIn, title: 'เช็คอิน', value: checkedIn ? _when(_visit?['checkindate']) : 'ยังไม่เช็คอิน'),
                _stepRow(context, done: checkedOut, title: 'เช็คเอาท์', value: checkedOut ? _when(_visit?['checkoutdate']) : 'ยังไม่เช็คเอาท์', last: true),
                const SizedBox(height: 12),
                if (!checkedIn)
                  NxHeroCta(label: 'เช็คอิน', busy: _busy, onPressed: _busy ? null : () => _check(inn: true))
                else if (!checkedOut)
                  NxHeroCta(label: 'เช็คเอาท์', busy: _busy, onPressed: _busy ? null : () => _check(inn: false))
                else
                  Text('เยี่ยมเสร็จแล้ว', style: theme.textTheme.titleSmall?.copyWith(color: const Color(0xFF16A34A))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('รูปถ่าย (${photos.length})', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'ถ่ายรูป', icon: const Icon(NxI.camera), onPressed: _busy ? null : () => _pickPhotos(camera: true)),
              IconButton(tooltip: 'แนบรูป', icon: const Icon(NxI.images), onPressed: _busy ? null : () => _pickPhotos(camera: false)),
            ],
          ),
          if (photos.isEmpty)
            Text('ยังไม่มีรูป', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          else
            AttachmentStrip(items: [
              for (final p in photos)
                {'url': (p['url'] ?? '/uploads/${p['path']}').toString(), 'name': p['name'], 'mime': p['mime'] ?? 'image/jpeg'},
            ]),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(formatApiError(_error!), style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 20),
          Text('ตอบรับนัด', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final e in _rsvpLabels.entries)
                ActionChip(label: Text(e.value), onPressed: _busy ? null : () => _rsvp(e.key)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _stepRow(BuildContext context, {required bool done, required String title, required String value, bool last = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const green = Color(0xFF16A34A);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: done ? green : cs.surfaceContainerHighest, shape: BoxShape.circle),
                child: Icon(done ? NxI.check : NxI.circle, size: 14, color: done ? Colors.white : cs.onSurfaceVariant),
              ),
              if (!last) Expanded(child: Container(width: 2, color: done ? green : cs.outlineVariant)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: done ? null : cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
