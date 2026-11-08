import 'dart:async';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../services/location_service.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_map_view.dart';
import '../calendar/visit_check_sheet.dart' show CheckInfoRow, CheckPhotoButton, thaiDateTime, stayDuration;

/// What a clock in / out recorded (the caller refreshes its view).
class PunchResult {
  const PunchResult({
    required this.clockIn,
    required this.at,
    required this.lat,
    required this.lng,
    this.address,
    this.queued = false,
    this.photos = 0,
    this.photoError = false,
  });
  final bool clockIn;
  final DateTime at;
  final double lat;
  final double lng;
  final String? address;
  final bool queued;
  final int photos;
  final bool photoError;
}

/// "ลงเวลาเข้า / ออก" window: live map, date-time, coordinates and address,
/// optional photos (camera or gallery), confirm, then a success screen.
/// [clockedInAt] (clocking out) shows how long the user has worked.
Future<PunchResult?> showAttendancePunchSheet(
  BuildContext context, {
  required bool clockIn,
  DateTime? clockedInAt,
  LocationService? location,
}) {
  return showNxSnapSheet<PunchResult>(
    context: context,
    snaps: const [0.92],
    builder: (ctx, controller) => _PunchBody(
      clockIn: clockIn,
      clockedInAt: clockedInAt,
      location: location ?? LocationService(),
      controller: controller,
    ),
  );
}

/// Photos go to Files › หลักฐานลงเวลา › YYYY-MM (NEXTX attendance has no
/// photo column), named date_time_in|out_name so HR can find them.
Future<int> uploadPunchPhotos(ApiClient api, List<XFile> photos, {required bool clockIn, required DateTime at, required String who}) async {
  if (photos.isEmpty) return 0;
  Future<String> folder(String name, String? parent) async {
    final listing = await api.getFolderListing(folderId: parent);
    final hit = listing.folders.where((f) => f['name']?.toString() == name).firstOrNull;
    if (hit != null) return hit['id'].toString();
    final made = await api.createFolder(name, parentId: parent);
    return (made['id'] ?? (made['folder'] is Map ? made['folder']['id'] : null)).toString();
  }

  String two(int v) => v.toString().padLeft(2, '0');
  final root = await folder('หลักฐานลงเวลา', null);
  final month = await folder('${at.year}-${two(at.month)}', root);
  final safe = who.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_');
  final stamp = '${at.year}-${two(at.month)}-${two(at.day)}_${two(at.hour)}${two(at.minute)}';
  final files = <MultipartFile>[
    for (var i = 0; i < photos.length; i++)
      MultipartFile.fromBytes(await photos[i].readAsBytes(), filename: '${stamp}_${clockIn ? 'in' : 'out'}_${safe}_${i + 1}.jpg'),
  ];
  await api.uploadFiles(files, folderId: month);
  return files.length;
}

enum _Step { locating, review, sending, done, failed }

class _PunchBody extends StatefulWidget {
  const _PunchBody({required this.clockIn, required this.location, required this.controller, this.clockedInAt});
  final bool clockIn;
  final DateTime? clockedInAt;
  final LocationService location;
  final ScrollController controller;

  @override
  State<_PunchBody> createState() => _PunchBodyState();
}

class _PunchBodyState extends State<_PunchBody> {
  _Step _step = _Step.locating;
  GeoFix? _fix;
  Object? _error;
  final List<XFile> _photos = [];
  DateTime _now = thaiNow();
  Timer? _clock;
  PunchResult? _result;

  String get _verb => widget.clockIn ? 'ลงเวลาเข้า' : 'ลงเวลาออก';

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _step != _Step.done) setState(() => _now = thaiNow());
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
      if (mounted) {
        setState(() {
          _fix = fix;
          _step = _Step.review;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _step = _Step.failed;
        });
      }
    }
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
    setState(() {
      _step = _Step.sending;
      _error = null;
    });
    final config = context.read<AppConfig>();
    final at = DateTime.now();
    try {
      final queued = await config.punch(clockIn: widget.clockIn, lat: fix.latitude, lng: fix.longitude, address: fix.address);
      // Time is recorded first; photos follow (a failed upload never loses the punch).
      var sent = 0;
      var photoError = false;
      if (!queued && _photos.isNotEmpty) {
        try {
          sent = await uploadPunchPhotos(config.apiClient, _photos,
              clockIn: widget.clockIn, at: toThai(at), who: config.session.displayName ?? config.session.email ?? 'user');
        } catch (_) {
          photoError = true;
        }
      }
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _result = PunchResult(
          clockIn: widget.clockIn,
          at: at,
          lat: fix.latitude,
          lng: fix.longitude,
          address: fix.address,
          queued: queued,
          photos: sent,
          photoError: photoError || (queued && _photos.isNotEmpty),
        );
        _step = _Step.done;
      });
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
    final sending = _step == _Step.sending;
    final accent = widget.clockIn ? const Color(0xFF16A34A) : const Color(0xFFEA580C);
    return ListView(
      key: const ValueKey('punch-sheet'),
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(widget.clockIn ? NxI.signIn : NxI.signOut, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('ยืนยัน$_verb'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 14),
        if (_step == _Step.locating)
          Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(strokeWidth: 2.5),
              const SizedBox(height: 12),
              Text(tr('กำลังหาตำแหน่งของคุณ…'), style: theme.textTheme.bodyMedium),
            ]),
          )
        else if (_step == _Step.failed || fix == null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(22)),
            child: Column(children: [
              Icon(NxI.warningCircle, color: cs.onErrorContainer, size: 32),
              const SizedBox(height: 8),
              Text(
                tr(_error is StateError ? (_error as StateError).message : 'หาตำแหน่งไม่สำเร็จ — เปิด GPS แล้วลองใหม่'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onErrorContainer),
              ),
              TextButton(onPressed: _locate, child: Text(tr('ลองอีกครั้ง'))),
            ]),
          )
        else
          NxMapView(me: LatLng(fix.latitude, fix.longitude), accuracy: fix.accuracy),
        const SizedBox(height: 14),
        CheckInfoRow(icon: NxI.clock, label: 'วันและเวลาที่จะบันทึก', value: thaiDateTime(_now), strong: true),
        if (fix != null) ...[
          CheckInfoRow(
            icon: NxI.crosshair,
            label: 'พิกัด',
            value: '${fix.latitude.toStringAsFixed(6)}, ${fix.longitude.toStringAsFixed(6)}'
                '${fix.accuracy != null ? '  (±${fix.accuracy!.round()} ม.)' : ''}',
          ),
          if ((fix.address ?? '').isNotEmpty) CheckInfoRow(icon: NxI.mapPin, label: 'สถานที่', value: fix.address!),
        ],
        if (!widget.clockIn && widget.clockedInAt != null)
          CheckInfoRow(icon: NxI.timer, label: 'ทำงานไปแล้ว', value: stayDuration(widget.clockedInAt!, _now)),
        const SizedBox(height: 10),
        Row(children: [
          Text(tr('รูปถ่าย'), style: theme.textTheme.titleSmall),
          const SizedBox(width: 6),
          Text(tr('(ไม่บังคับ)'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              CheckPhotoButton(icon: NxI.camera, label: 'ถ่ายรูป', onTap: sending ? null : () => _addPhoto(camera: true)),
              const SizedBox(width: 8),
              CheckPhotoButton(icon: NxI.images, label: 'แนบรูป', onTap: sending ? null : () => _addPhoto(camera: false)),
              for (final p in _photos) ...[
                const SizedBox(width: 8),
                Stack(children: [
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
                ]),
              ],
            ],
          ),
        ),
        if (_error != null && _step == _Step.review) ...[
          const SizedBox(height: 12),
          Text(tr(formatApiError(_error!)), key: const ValueKey('punch-error'), style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('punch-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            minimumSize: const Size.fromHeight(54),
            textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          onPressed: _step == _Step.review && fix != null ? _confirm : null,
          child: sending
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(tr('ยืนยัน$_verb')),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
      ],
    );
  }

  Widget _success(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = _result!;
    final color = r.queued ? cs.tertiary : (r.clockIn ? const Color(0xFF16A34A) : const Color(0xFFEA580C));
    return ListView(
      key: const ValueKey('punch-done'),
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
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 4)],
              ),
              child: Icon(r.queued ? NxI.cloud : NxI.check, color: Colors.white, size: 48),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          tr(r.queued ? 'บันทึก$_verbไว้แล้ว' : '$_verbสำเร็จ'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (r.queued)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('ไม่มีสัญญาณ — จะส่งอัตโนมัติเมื่อกลับมาออนไลน์ (ใช้เวลาจริงที่บันทึก)'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: 18),
        CheckInfoRow(icon: NxI.clock, label: 'เวลา', value: thaiDateTime(toThai(r.at)), strong: true),
        CheckInfoRow(icon: NxI.crosshair, label: 'พิกัด', value: '${r.lat.toStringAsFixed(6)}, ${r.lng.toStringAsFixed(6)}'),
        if ((r.address ?? '').isNotEmpty) CheckInfoRow(icon: NxI.mapPin, label: 'สถานที่', value: r.address!),
        if (!r.clockIn && widget.clockedInAt != null)
          CheckInfoRow(icon: NxI.timer, label: 'รวมเวลาทำงาน', value: stayDuration(widget.clockedInAt!, toThai(r.at))),
        if (r.photos > 0) CheckInfoRow(icon: NxI.image, label: 'รูปถ่าย', value: '${r.photos} รูป · เก็บใน ไฟล์ › หลักฐานลงเวลา'),
        if (r.photoError)
          CheckInfoRow(
            icon: NxI.warningCircle,
            label: 'รูปถ่าย',
            value: r.queued ? 'บันทึกเวลาแล้ว ส่งรูปไม่ได้ขณะออฟไลน์' : 'บันทึกเวลาแล้ว แต่ส่งรูปไม่สำเร็จ',
            color: cs.error,
          ),
        const SizedBox(height: 22),
        FilledButton(
          key: const ValueKey('punch-finish'),
          style: FilledButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.pop(context, r),
          child: Text(tr('เสร็จสิ้น')),
        ),
      ],
    );
  }
}
