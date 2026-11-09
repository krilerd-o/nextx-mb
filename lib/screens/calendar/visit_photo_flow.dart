import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/geo_address.dart';
import '../../services/location_service.dart';
import '../../services/photo_watermark.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'fast_take_screen.dart';

/// How a photo is saved: with the location watermark, or as it is.
enum PhotoTagMode { withLocation, plain }

/// Where the photos come from.
enum PhotoSource { camera, gallery, fastTake }

const _modePref = 'nx_visit_photo_mode_v1';

/// Asks "พร้อมพิกัด / ภาพเท่านั้น" (last choice highlighted).
Future<PhotoTagMode?> askPhotoTagMode(BuildContext context, {required PhotoSource source, int? count}) async {
  PhotoTagMode? last;
  try {
    final v = (await SharedPreferences.getInstance()).getString(_modePref);
    last = PhotoTagMode.values.where((m) => m.name == v).firstOrNull;
  } catch (_) {}
  if (!context.mounted) return null;
  final upload = source == PhotoSource.gallery;
  final title = switch (source) {
    PhotoSource.camera => 'ถ่ายภาพ',
    PhotoSource.gallery => count == null ? 'อัปโหลดภาพ' : 'อัปโหลด $count ภาพ',
    PhotoSource.fastTake => 'อัปโหลด ${count ?? ''} ภาพที่ถ่าย',
  };
  final picked = await showAppBottomSheet<PhotoTagMode>(
    context: context,
    title: tr(title),
    child: _ModeChooser(upload: upload || source == PhotoSource.fastTake, last: last ?? PhotoTagMode.withLocation),
  );
  if (picked != null) {
    try {
      (await SharedPreferences.getInstance()).setString(_modePref, picked.name);
    } catch (_) {}
  }
  return picked;
}

class _ModeChooser extends StatelessWidget {
  const _ModeChooser({required this.upload, required this.last});

  final bool upload;
  final PhotoTagMode last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget tile(PhotoTagMode m, IconData icon, String label, String hint, Color color) {
      final sel = m == last;
      return Expanded(
        child: Material(
          color: sel ? color.withValues(alpha: 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: sel ? color : Colors.transparent, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('photo-mode-${m.name}'),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context, m);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 16),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(icon, size: 28, color: color),
                  ),
                  const SizedBox(height: 10),
                  Text(tr(label), textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(tr(hint), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile(
          PhotoTagMode.withLocation,
          NxI.mapPinned,
          upload ? 'อัปโหลดพร้อมพิกัด' : 'ถ่ายพร้อมพิกัด',
          'ใส่ลายน้ำวันเวลา พิกัด และสถานที่ทุกภาพ',
          const Color(0xFF16A34A),
        ),
        const SizedBox(width: 12),
        tile(
          PhotoTagMode.plain,
          NxI.image,
          upload ? 'อัปโหลดภาพเท่านั้น' : 'ถ่ายภาพเท่านั้น',
          'ภาพตามจริง ไม่มีลายน้ำ',
          cs.primary,
        ),
      ],
    );
  }
}

/// Progress of a photo run, shown under the photo header.
class PhotoRunProgress {
  const PhotoRunProgress(this.label, this.done, this.total);
  final String label;
  final int done;
  final int total;
}

/// Picks (camera / gallery / Fast Take), asks the watermark mode, stamps every
/// photo, then uploads in batches of [kFastTakeBatch]. Returns how many were
/// uploaded; throws [PhotoUploadIncomplete] when some batches failed.
class VisitPhotoFlow {
  VisitPhotoFlow({
    required this.upload,
    this.onProgress,
    LocationService? location,
    this.pick,
  }) : _location = location ?? LocationService();

  final Future<void> Function(List<MultipartFile> files) upload;
  final void Function(PhotoRunProgress? p)? onProgress;
  final LocationService _location;

  /// Test hook: returns the files instead of opening the camera / gallery.
  final Future<List<XFile>> Function(PhotoSource source)? pick;

  /// Files from a failed batch, for "ลองใหม่".
  List<MultipartFile> pending = const [];

  Future<List<XFile>> _pick(BuildContext context, PhotoSource source) async {
    if (pick != null) return pick!(source);
    final picker = ImagePicker();
    switch (source) {
      case PhotoSource.camera:
        final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2560);
        return shot == null ? const [] : [shot];
      case PhotoSource.gallery:
        return picker.pickMultiImage(imageQuality: 85, maxWidth: 2560);
      case PhotoSource.fastTake:
        final shots = await Navigator.of(context, rootNavigator: true).push<List<XFile>>(
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => const FastTakeScreen()),
        );
        return shots ?? const [];
    }
  }

  Future<int> run(BuildContext context, PhotoSource source) async {
    // Camera: ask first (the user decides before shooting); others after picking.
    PhotoTagMode? mode;
    if (source == PhotoSource.camera) {
      mode = await askPhotoTagMode(context, source: source);
      if (mode == null || !context.mounted) return 0;
    }
    final files = await _pick(context, source);
    if (files.isEmpty || !context.mounted) return 0;
    mode ??= await askPhotoTagMode(context, source: source, count: files.length);
    if (mode == null) return 0;

    final parts = <MultipartFile>[];
    try {
      WatermarkInfo? base;
      if (mode == PhotoTagMode.withLocation) {
        onProgress?.call(PhotoRunProgress('กำลังหาพิกัด…', 0, files.length));
        final fix = await _location.currentFix();
        final address = fix.address ?? await GeoAddress.lookup(fix.latitude, fix.longitude);
        base = WatermarkInfo(at: thaiNow(), lat: fix.latitude, lng: fix.longitude, address: address);
      }
      for (var i = 0; i < files.length; i++) {
        onProgress?.call(PhotoRunProgress('เตรียมรูป', i, files.length));
        final f = files[i];
        final bytes = await f.readAsBytes();
        final name = f.name.isEmpty ? 'photo_${i + 1}.jpg' : f.name;
        if (base == null) {
          parts.add(MultipartFile.fromBytes(bytes, filename: name));
        } else {
          final shotAt = await _shotTime(f) ?? base.at;
          final out = await watermarkPhoto(bytes, WatermarkInfo(at: shotAt, lat: base.lat, lng: base.lng, address: base.address));
          parts.add(MultipartFile.fromBytes(out, filename: name.replaceAll(RegExp(r'\.(png|heic|heif|webp)$', caseSensitive: false), '.jpg')));
        }
      }
      return await uploadBatches(parts);
    } finally {
      onProgress?.call(null);
    }
  }

  /// Gallery files keep their own time; fresh shots use now.
  Future<DateTime?> _shotTime(XFile f) async {
    try {
      final m = await f.lastModified();
      final age = DateTime.now().difference(m);
      return age.inMinutes.abs() < 2 ? null : toThai(m);
    } catch (_) {
      return null;
    }
  }

  /// Sends [parts] in batches of [kFastTakeBatch]; keeps failures in [pending].
  Future<int> uploadBatches(List<MultipartFile> parts) async {
    var sent = 0;
    final failed = <MultipartFile>[];
    Object? lastError;
    for (var i = 0; i < parts.length; i += kFastTakeBatch) {
      final batch = parts.sublist(i, i + kFastTakeBatch > parts.length ? parts.length : i + kFastTakeBatch);
      onProgress?.call(PhotoRunProgress('กำลังอัปโหลด', sent, parts.length));
      try {
        await upload(batch);
        sent += batch.length;
      } catch (e) {
        lastError = e;
        failed.addAll(batch);
      }
    }
    onProgress?.call(PhotoRunProgress('กำลังอัปโหลด', sent, parts.length));
    pending = failed;
    if (failed.isNotEmpty) throw PhotoUploadIncomplete(sent, failed.length, lastError);
    return sent;
  }

  /// Retries what failed last time (MultipartFile can be sent once: clone).
  Future<int> retryPending() => uploadBatches([for (final f in pending) f.clone()]);
}

class PhotoUploadIncomplete implements Exception {
  PhotoUploadIncomplete(this.sent, this.failed, this.cause);
  final int sent;
  final int failed;
  final Object? cause;

  @override
  String toString() => 'อัปโหลดสำเร็จ $sent รูป ค้าง $failed รูป';
}
