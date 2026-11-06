import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../widgets/key_value_card.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';

class ActivityDetailScreen extends StatefulWidget {
  const ActivityDetailScreen({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  final _location = LocationService();
  Map<String, dynamic>? _visit;
  Map<String, dynamic>? _validate;
  bool _busy = false;
  Object? _error;

  String get _id => strId(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _loadVisit();
    _previewValidate();
  }

  Future<void> _previewValidate() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final fix = await _location.currentFix();
      final v = await api.validateCheckin(
        _id,
        lat: fix.latitude,
        lng: fix.longitude,
      );
      if (mounted) setState(() => _validate = v);
    } catch (_) {}
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
    setState(() {
      _busy = true;
      _error = null;
    });
    final config = context.read<AppConfig>();
    try {
      final fix = await _location.currentFix();
      final api = config.apiClient;
      if (inn) {
        final v = await api.validateCheckin(_id, lat: fix.latitude, lng: fix.longitude);
        _validate = v;
        if (v['allowed'] == false || v['button'] == false) {
          throw ApiException(400, v['message']?.toString() ?? 'อยู่นอกระยะเช็คอิน');
        }
        await api.activityCheckin(_id, lat: fix.latitude, lng: fix.longitude);
      } else {
        await api.activityCheckout(_id, lat: fix.latitude, lng: fix.longitude);
      }
      await _loadVisit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(inn ? 'เช็คอินแล้ว' : 'เช็คเอาต์แล้ว')),
        );
      }
    } catch (e) {
      if (inn && e is ApiException && e.statusCode == 0) {
        try {
          final fix = await _location.currentFix();
          await config.queueFieldAction({
            'type': 'checkin',
            'id': _id,
            'lat': fix.latitude,
            'lng': fix.longitude,
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ไม่มีสัญญาณ — คิวเช็คอินไว้แล้ว')),
            );
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final distance = _validate?['distance'];
    final allowed = _validate == null ||
        (_validate!['allowed'] != false && _validate!['button'] != false);
    return Scaffold(
      appBar: NxAppHeader(title: entityTitle(row, module: 'activity')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: NxSurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('เริ่ม', style: theme.textTheme.bodySmall),
                      Text(row['date_start']?.toString() ?? '—', style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NxSurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('จบ', style: theme.textTheme.bodySmall),
                      Text(row['date_end']?.toString() ?? '—', style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if ((row['description']?.toString() ?? '').trim().isNotEmpty) ...[
            NxHtmlView(html: row['description'].toString()),
            const SizedBox(height: 12),
          ],
          KeyValueCard(
            entries: [
              MapEntry('สถานะ', row['status']?.toString() ?? '—'),
              MapEntry('สถานที่', row['location']?.toString() ?? '—'),
            ],
          ),
          if (_visit != null) ...[
            const SizedBox(height: 12),
            Text('เช็คอิน', style: theme.textTheme.titleSmall),
            Text('${_visit!['checkindate'] ?? 'ยังไม่เช็คอิน'}'),
          ],
          if (distance != null) ...[
            const SizedBox(height: 8),
            Text(
              'ระยะจากจุดหมาย $distance ม.${allowed ? '' : ' — นอกระยะ'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: allowed ? theme.colorScheme.primary : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(formatApiError(_error!), style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          NxHeroCta(
            label: 'เช็คอิน',
            busy: _busy,
            onPressed: (_busy || !allowed) ? null : () => _check(inn: true),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _busy ? null : () => _check(inn: false),
            child: const Text('เช็คเอาต์'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickPhotos(camera: true),
            icon: const Icon(NxI.camera),
            label: const Text('ถ่ายรูป'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pickPhotos(camera: false),
            icon: const Icon(NxI.images),
            label: const Text('เลือกจากคลัง'),
          ),
          const SizedBox(height: 16),
          Text('RSVP', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final r in ['accepted', 'tentative', 'declined'])
                ActionChip(label: Text(r), onPressed: _busy ? null : () => _rsvp(r)),
            ],
          ),
        ],
      ),
    );
  }
}
