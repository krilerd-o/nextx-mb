import 'dart:async';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_exceptions.dart';
import '../../services/location_service.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_map_view.dart';

/// Result of the sheet: what was recorded (for the caller to refresh).
class VisitCheckResult {
  const VisitCheckResult({required this.checkIn, required this.at, required this.lat, required this.lng, this.queued = false});
  final bool checkIn;
  final DateTime at;
  final double lat;
  final double lng;
  final bool queued;
}

/// Thai date + time with seconds, e.g. `7 พ.ย. 2569 · 14:05:09`.
String thaiDateTime(DateTime d) {
  const m = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.day} ${m[d.month - 1]} ${d.year + 543} · ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// `2 ชม. 15 นาที` from a check-in time to now.
String stayDuration(DateTime from, DateTime to) {
  final mins = to.difference(from).inMinutes;
  if (mins < 1) return 'ไม่ถึง 1 นาที';
  final h = mins ~/ 60;
  final mm = mins % 60;
  return [if (h > 0) '$h ชม.', if (mm > 0) '$mm นาที'].join(' ');
}

/// Opens the check-in / check-out sheet: map + coordinates + time + photos,
/// the user confirms, then a success screen.
Future<VisitCheckResult?> showVisitCheckSheet(
  BuildContext context, {
  required String activityId,
  required bool checkIn,
  String? placeName,
  DateTime? checkedInAt,
  LocationService? location,
}) {
  return showNxSnapSheet<VisitCheckResult>(
    context: context,
    snaps: const [0.92],
    builder: (ctx, controller) => _VisitCheckBody(
      activityId: activityId,
      checkIn: checkIn,
      placeName: placeName,
      checkedInAt: checkedInAt,
      location: location ?? LocationService(),
      controller: controller,
    ),
  );
}

enum _Step { locating, review, sending, done, failed }

class _VisitCheckBody extends StatefulWidget {
  const _VisitCheckBody({
    required this.activityId,
    required this.checkIn,
    required this.location,
    required this.controller,
    this.placeName,
    this.checkedInAt,
  });

  final String activityId;
  final bool checkIn;
  final String? placeName;
  final DateTime? checkedInAt;
  final LocationService location;
  final ScrollController controller;

  @override
  State<_VisitCheckBody> createState() => _VisitCheckBodyState();
}

class _VisitCheckBodyState extends State<_VisitCheckBody> {
  _Step _step = _Step.locating;
  GeoFix? _fix;
  Map<String, dynamic>? _validate;
  Object? _error;
  final List<XFile> _photos = [];
  DateTime _now = DateTime.now();
  Timer? _clock;
  VisitCheckResult? _result;

  String get _verb => widget.checkIn ? 'เช็คอิน' : 'เช็คเอาท์';

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _step != _Step.done) setState(() => _now = DateTime.now());
    });
    _locate();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() {
      _step = _Step.locating;
      _error = null;
    });
    try {
      final fix = await widget.location.currentFix();
      Map<String, dynamic>? v;
      if (widget.checkIn) {
        try {
          if (!mounted) return;
          v = await context.read<AppConfig>().apiClient.validateCheckin(widget.activityId, lat: fix.latitude, lng: fix.longitude);
        } catch (_) {
          v = null; // Offline: still allow (queued); server re-checks later.
        }
      }
      if (!mounted) return;
      setState(() {
        _fix = fix;
        _validate = v;
        _step = _Step.review;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _step = _Step.failed;
        });
      }
    }
  }

  bool get _blocked {
    final v = _validate;
    if (v == null) return false;
    return v['enforce_range'] == true && (v['allowed'] == false || v['button'] == false);
  }

  Future<void> _addPhoto({required bool camera}) async {
    final picker = ImagePicker();
    if (camera) {
      final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
      if (x != null) setState(() => _photos.add(x));
    } else {
      final xs = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80);
      if (xs.isNotEmpty) setState(() => _photos.addAll(xs));
    }
  }

  Future<void> _confirm() async {
    final fix = _fix;
    if (fix == null) return;
    setState(() => _step = _Step.sending);
    final config = context.read<AppConfig>();
    final api = config.apiClient;
    final at = DateTime.now();
    try {
      String? imagename;
      if (_photos.isNotEmpty) {
        final parts = <MultipartFile>[
          for (final p in _photos) MultipartFile.fromBytes(await p.readAsBytes(), filename: p.name),
        ];
        final saved = await api.uploadActivityPhotos(widget.activityId, parts);
        if (saved.isNotEmpty) imagename = (saved.first['path'] ?? saved.first['name'])?.toString();
      }
      if (widget.checkIn) {
        await api.activityCheckin(widget.activityId, lat: fix.latitude, lng: fix.longitude, imagename: imagename);
      } else {
        await api.activityCheckout(widget.activityId, lat: fix.latitude, lng: fix.longitude);
      }
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _result = VisitCheckResult(checkIn: widget.checkIn, at: at, lat: fix.latitude, lng: fix.longitude);
        _step = _Step.done;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 0) {
        // No signal: keep it with the real time and send when back online.
        await config.queueFieldAction({
          'type': widget.checkIn ? 'checkin' : 'checkout',
          'id': widget.activityId,
          'lat': fix.latitude,
          'lng': fix.longitude,
          'client_time': at.toUtc().toIso8601String(),
        });
        if (!mounted) return;
        setState(() {
          _result = VisitCheckResult(checkIn: widget.checkIn, at: at, lat: fix.latitude, lng: fix.longitude, queued: true);
          _step = _Step.done;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _error = e;
          _step = _Step.review;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _step = _Step.review;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: KeyedSubtree(
        key: ValueKey(_step == _Step.done),
        child: _step == _Step.done ? _success(context) : _review(context),
      ),
    );
  }

  Widget _review(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fix = _fix;
    final v = _validate;
    final distance = (v?['distance'] as num?)?.toDouble();
    final range = (v?['range_meters'] as num?)?.toDouble();
    final hasDest = v?['has_destination'] == true && v?['dest_lat'] != null;
    final dest = hasDest ? LatLng((v!['dest_lat'] as num).toDouble(), (v['dest_lng'] as num).toDouble()) : null;
    final sending = _step == _Step.sending;
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Text('ยืนยัน$_verb', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (widget.placeName != null && widget.placeName!.isNotEmpty)
          Text(widget.placeName!, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        if (_step == _Step.locating)
          Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(strokeWidth: 2.5),
                const SizedBox(height: 12),
                Text('กำลังหาตำแหน่งของคุณ…', style: theme.textTheme.bodyMedium),
              ],
            ),
          )
        else if (_step == _Step.failed || fix == null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                Icon(NxI.warningCircle, color: cs.onErrorContainer, size: 32),
                const SizedBox(height: 8),
                Text(
                  _error is StateError ? (_error as StateError).message : 'หาตำแหน่งไม่สำเร็จ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
                TextButton(onPressed: _locate, child: const Text('ลองอีกครั้ง')),
              ],
            ),
          )
        else
          NxMapView(me: LatLng(fix.latitude, fix.longitude), accuracy: fix.accuracy, dest: dest, rangeMeters: range),
        const SizedBox(height: 14),
        _InfoRow(
          icon: NxI.clock,
          label: 'วันและเวลาที่จะบันทึก',
          value: thaiDateTime(_now),
          strong: true,
        ),
        if (fix != null)
          _InfoRow(
            icon: NxI.crosshair,
            label: 'พิกัด',
            value: '${fix.latitude.toStringAsFixed(6)}, ${fix.longitude.toStringAsFixed(6)}'
                '${fix.accuracy != null ? '  (±${fix.accuracy!.round()} ม.)' : ''}',
          ),
        if (widget.checkIn && v != null)
          _InfoRow(
            icon: NxI.navigationArrow,
            label: 'ระยะจากสถานที่นัด',
            value: hasDest && distance != null
                ? '${distance.round()} ม.${range != null ? ' (อนุญาต ${range.round()} ม.)' : ''}'
                : (v['message']?.toString() ?? 'ไม่ระบุตำแหน่งนัด'),
            color: _blocked ? cs.error : (hasDest ? const Color(0xFF16A34A) : null),
          ),
        if (!widget.checkIn && widget.checkedInAt != null)
          _InfoRow(icon: NxI.timer, label: 'อยู่ในสถานที่', value: stayDuration(widget.checkedInAt!, _now)),
        const SizedBox(height: 10),
        Text('รูปถ่าย$_verb', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _PhotoButton(icon: NxI.camera, label: 'ถ่ายรูป', onTap: sending ? null : () => _addPhoto(camera: true)),
              const SizedBox(width: 8),
              _PhotoButton(icon: NxI.images, label: 'แนบรูป', onTap: sending ? null : () => _addPhoto(camera: false)),
              for (final p in _photos) ...[
                const SizedBox(width: 8),
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: FutureBuilder(
                        future: p.readAsBytes(),
                        builder: (context, snap) => snap.hasData
                            ? Image.memory(snap.data!, width: 84, height: 84, fit: BoxFit.cover, cacheWidth: 252)
                            : Container(width: 84, height: 84, color: cs.surfaceContainerHighest),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: GestureDetector(
                        onTap: sending ? null : () => setState(() => _photos.remove(p)),
                        child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(NxI.x, size: 12, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_error != null && _step == _Step.review) ...[
          const SizedBox(height: 12),
          Text(formatApiError(_error!), style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.onSurface,
            foregroundColor: cs.surface,
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(54),
            textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          onPressed: _step == _Step.review && fix != null && !_blocked ? _confirm : null,
          child: sending
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.surface))
              : Text(_blocked ? 'อยู่นอกระยะ$_verb' : 'ยืนยัน$_verb'),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: const Text('ยกเลิก')),
      ],
    );
  }

  Widget _success(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = _result!;
    const green = Color(0xFF16A34A);
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.elasticOut,
            builder: (context, t, child) => Transform.scale(scale: t, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: r.queued ? cs.tertiary : green,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: (r.queued ? cs.tertiary : green).withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 4)],
              ),
              child: Icon(r.queued ? NxI.cloud : NxI.check, color: Colors.white, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          r.queued ? 'บันทึก$_verbไว้แล้ว' : '$_verbสำเร็จ',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (r.queued)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('ไม่มีสัญญาณ — จะส่งอัตโนมัติเมื่อกลับมาออนไลน์ (ใช้เวลาจริงที่บันทึก)', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: 18),
        _InfoRow(icon: NxI.clock, label: 'เวลา', value: thaiDateTime(r.at), strong: true),
        _InfoRow(icon: NxI.crosshair, label: 'พิกัด', value: '${r.lat.toStringAsFixed(6)}, ${r.lng.toStringAsFixed(6)}'),
        if (_photos.isNotEmpty) _InfoRow(icon: NxI.image, label: 'รูปถ่าย', value: '${_photos.length} รูป'),
        if (!r.checkIn && widget.checkedInAt != null)
          _InfoRow(icon: NxI.timer, label: 'อยู่ในสถานที่', value: stayDuration(widget.checkedInAt!, r.at)),
        const SizedBox(height: 22),
        FilledButton(
          style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.pop(context, r),
          child: const Text('เสร็จสิ้น'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.strong = false, this.color});
  final IconData icon;
  final String label;
  final String value;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  value,
                  style: (strong ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge)?.copyWith(
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 84,
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, color: cs.primary), const SizedBox(height: 4), Text(label, style: TextStyle(color: cs.primary, fontSize: 12))],
          ),
        ),
      ),
    );
  }
}
