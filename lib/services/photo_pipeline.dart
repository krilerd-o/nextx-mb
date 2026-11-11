import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show MultipartFile, DioMediaType;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../core/thai_time.dart';
import 'api_client.dart';
import 'geo_address.dart';
import 'location_service.dart';
import 'photo_upload_center.dart';
import 'photo_watermark.dart';

/// Where a batch of photos goes.
class PhotoTarget {
  const PhotoTarget(this.module, this.id, {this.title});
  final String module;
  final String id;
  final String? title;
  String get key => '$module:$id';
}

/// A photo ready to send (resized, oriented, optionally watermarked JPEG).
class PreparedPhoto {
  PreparedPhoto({required this.bytes, required this.filename, required this.clientId, required this.takenAt, this.lat, this.lng});
  final Uint8List bytes;
  final String filename;
  final String clientId;
  final DateTime takenAt;
  final double? lat;
  final double? lng;
  int attempts = 0;
}

/// Sends one prepared photo. Default implementation: [defaultPhotoUploader].
typedef PhotoUploader = Future<Map<String, dynamic>?> Function(PhotoTarget target, PreparedPhoto photo);

/// Job → evidence photos (one file per request, idempotent by client id);
/// activity → visit photos; other modules → file upload (posted as one comment
/// when the batch ends, see [PhotoBatch.commentAttachments]).
PhotoUploader defaultPhotoUploader(ApiClient api) => (target, p) async {
      MultipartFile part() => MultipartFile.fromBytes(p.bytes, filename: p.filename, contentType: DioMediaType('image', 'jpeg'));
      switch (target.module) {
        case 'job':
          return api.uploadJobPhoto(target.id, part(), clientId: p.clientId, takenAt: p.takenAt, lat: p.lat, lng: p.lng);
        case 'activity':
          await api.uploadActivityPhotos(target.id, [part()]);
          return null;
        default:
          final att = await api.uploadCommentAttachments([part()]);
          return att.isEmpty ? null : att.first;
      }
    };

/// Progress of one batch (shown as a floating bar on the record page).
@immutable
class PhotoBatchState {
  const PhotoBatchState({this.total = 0, this.prepared = 0, this.uploaded = 0, this.failed = 0, this.shooting = false, this.locating = false});
  final int total;
  final int prepared;
  final int uploaded;
  final int failed;
  final bool shooting;
  final bool locating;
  bool get busy => shooting || uploaded + failed < total;
  bool get done => !shooting && total > 0 && uploaded + failed >= total;
  double get fraction => total == 0 ? 0 : (uploaded / total).clamp(0, 1);
}

/// One shooting / upload session for a record. Photos are processed and sent
/// **while the user is still shooting**: each shot is resized + watermarked
/// natively (2 at a time) and uploaded right away (3 at a time).
class PhotoBatch extends ValueNotifier<PhotoBatchState> {
  PhotoBatch(
    this.target, {
    required this.withLocation,
    required PhotoUploader uploader,
    LocationService? location,
    this.maxSide = 1920,
    this.quality = 85,
    this.onPhotoUploaded,
    this.onFinished,
    this.persist = true,
  })  : _uploader = uploader,
        super(const PhotoBatchState()) {
    if (withLocation) _fix = _locate(location ?? LocationService());
    PhotoUploadCenter.instance.register(this);
  }

  /// Keep each prepared photo on disk until the server has it (survives app
  /// close / no signal; sent later by [PhotoUploadCenter.drain]).
  final bool persist;

  /// Photos of this batch that are prepared but not yet confirmed.
  final Set<String> _inFlight = {};
  Iterable<String> get clientIds => _inFlight;

  final PhotoTarget target;
  final bool withLocation;
  final int maxSide;
  final int quality;
  final PhotoUploader _uploader;
  final void Function(Map<String, dynamic>? result)? onPhotoUploaded;

  /// Called once when everything was sent (or failed) after [close].
  final void Function(PhotoBatch batch)? onFinished;

  Future<WatermarkInfo?>? _fix;
  final _prepare = _Gate(2);
  final _send = _Gate(3);
  final List<PreparedPhoto> failed = [];

  /// Upload results for comment-style targets (file meta to attach).
  final List<Map<String, dynamic>> commentAttachments = [];
  bool _closed = false;
  bool _finishedFired = false;
  Object? lastError;

  int _total = 0, _prepared = 0, _uploaded = 0, _failed = 0;
  bool _shooting = false, _locating = false;

  void _emit() {
    value = PhotoBatchState(
      total: _total,
      prepared: _prepared,
      uploaded: _uploaded,
      failed: _failed,
      shooting: _shooting,
      locating: _locating,
    );
    if (_closed && !_finishedFired && _uploaded + _failed >= _total) {
      _finishedFired = true;
      onFinished?.call(this);
      // Failed ones are left to the saved queue (sent later / "ลองใหม่").
      _inFlight.removeAll([for (final p in failed) p.clientId]);
      PhotoUploadCenter.instance.unregister(this);
    }
  }

  set shooting(bool v) {
    _shooting = v;
    _emit();
  }

  Future<WatermarkInfo?> _locate(LocationService loc) async {
    _locating = true;
    _emit();
    try {
      final fix = await loc.currentFix();
      final address = fix.address ?? await GeoAddress.lookup(fix.latitude, fix.longitude);
      return WatermarkInfo(at: thaiNow(), lat: fix.latitude, lng: fix.longitude, address: address);
    } catch (e) {
      lastError = e;
      return WatermarkInfo(at: thaiNow());
    } finally {
      _locating = false;
      _emit();
    }
  }

  /// Adds a shot / picked file; returns immediately.
  void add(XFile file, {bool fresh = true}) {
    _total++;
    _emit();
    unawaited(_process(file, fresh));
  }

  void addAll(Iterable<XFile> files, {bool fresh = false}) {
    for (final f in files) {
      add(f, fresh: fresh);
    }
  }

  /// No more photos will be added; [onFinished] fires when the queue drains.
  void close() {
    _closed = true;
    _shooting = false;
    _emit();
  }

  Future<void> _process(XFile file, bool fresh) async {
    PreparedPhoto? p;
    try {
      p = await _prepare.run(() async {
        final base = await _fix;
        final at = fresh ? thaiNow() : (await _shotTime(file) ?? thaiNow());
        final info = base == null ? null : WatermarkInfo(at: at, lat: base.lat, lng: base.lng, address: base.address);
        final bytes = await preparePhoto(file, info, maxSide: maxSide, quality: quality);
        final name = file.name.isEmpty ? 'photo.jpg' : file.name;
        return PreparedPhoto(
          bytes: bytes,
          filename: name.replaceAll(RegExp(r'\.(png|heic|heif|webp|jpeg)$', caseSensitive: false), '.jpg'),
          clientId: newClientId(),
          takenAt: at,
          lat: base?.lat,
          lng: base?.lng,
        );
      });
      _prepared++;
      _inFlight.add(p!.clientId);
      if (persist) await PhotoUploadCenter.instance.keep(target, p!);
      _emit();
    } catch (e) {
      lastError = e;
      _failed++;
      _emit();
      return;
    }
    await _upload(p!);
  }

  Future<void> _upload(PreparedPhoto p) async {
    await _send.run(() async {
      for (;;) {
        p.attempts++;
        try {
          final r = await _uploader(target, p);
          if (r != null && target.module != 'job' && target.module != 'activity') commentAttachments.add(r);
          _uploaded++;
          _inFlight.remove(p.clientId);
          if (persist) unawaited(PhotoUploadCenter.instance.done(p.clientId));
          onPhotoUploaded?.call(r);
          return;
        } catch (e) {
          lastError = e;
          if (p.attempts >= 3 || !_retryable(e)) {
            failed.add(p);
            _failed++;
            // No signal / server down: the saved copy is sent later by the
            // background queue; refused photos stay marked for "ลองใหม่".
            if (persist && !_retryable(e)) unawaited(PhotoUploadCenter.instance.markFailed(p.clientId));
            return;
          }
          await Future<void>.delayed(Duration(milliseconds: 800 * p.attempts * p.attempts));
        }
      }
    });
    _emit();
  }

  bool _retryable(Object e) {
    final code = e is ApiException ? e.statusCode : e is ApiEnvelopeException ? e.statusCode : 0;
    return code == 0 || code == 408 || code == 429 || code >= 500;
  }

  /// Sends the failed photos again (same client id → no duplicates on the server).
  Future<void> retryFailed() async {
    PhotoUploadCenter.instance.register(this);
    final again = List.of(failed);
    _inFlight.addAll([for (final p in again) p.clientId]);
    failed.clear();
    _failed -= again.length;
    _finishedFired = false;
    _emit();
    await Future.wait([
      for (final p in again) (p..attempts = 0).let(_upload),
    ]);
  }

  static Future<DateTime?> _shotTime(XFile f) async {
    try {
      final m = await f.lastModified();
      return DateTime.now().difference(m).inMinutes.abs() < 2 ? null : toThai(m);
    } catch (_) {
      return null;
    }
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Simple concurrency limit.
class _Gate {
  _Gate(this.max);
  final int max;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= max) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}

final _rand = Random.secure();

/// UUID-like id for idempotent uploads.
String newClientId() {
  String hex(int n) => List.generate(n, (_) => _rand.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
}

/// JPEG size from the header (SOF marker), without decoding. null if unknown.
(int, int)? jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final m = b[i + 1];
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    if ((m >= 0xC0 && m <= 0xC3) || (m >= 0xC5 && m <= 0xC7) || (m >= 0xC9 && m <= 0xCB) || (m >= 0xCD && m <= 0xCF)) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return (w, h);
    }
    i += 2 + len;
  }
  return null;
}

/// Native resize + EXIF orientation + JPEG encode (fast, off the Dart thread).
/// null when the plugin is not available (tests / web).
@visibleForTesting
Future<Uint8List?> Function(Uint8List src, int maxSide, int quality)? debugNativeJpeg;

Future<Uint8List?> _nativeJpeg(Uint8List src, int maxSide, int quality, {(int, int)? knownSize}) async {
  final hook = debugNativeJpeg;
  if (hook != null) return hook(src, maxSide, quality);
  if (kIsWeb) return null;
  final size = knownSize ?? jpegSize(src);
  var minSide = maxSide;
  if (size != null) {
    final long = max(size.$1, size.$2), short = min(size.$1, size.$2);
    minSide = long <= maxSide ? short : (maxSide * short / long).round();
  } else {
    minSide = (maxSide * 0.75).round();
  }
  try {
    return await FlutterImageCompress.compressWithList(src, minWidth: minSide, minHeight: minSide, quality: quality);
  } on MissingPluginException {
    return null;
  } catch (e) {
    debugPrint('[photo] native compress failed: $e');
    return null;
  }
}

/// Reads [file] and returns a JPEG ≤ [maxSide] with the watermark when [info] is set.
/// Fast path: native resize/encode, one decode, PNG → native JPEG; falls back
/// to the pure-Dart [watermarkPhoto] when the native encoder is missing.
Future<Uint8List> preparePhoto(XFile file, WatermarkInfo? info, {int maxSide = 1920, int quality = 85}) async {
  final src = await file.readAsBytes();
  final base = await _nativeJpeg(src, maxSide, quality);
  if (info == null) return base ?? src;
  if (base == null) return watermarkPhoto(src, info, maxSide: maxSide, quality: quality);
  final codec = await ui.instantiateImageCodec(base);
  final photo = (await codec.getNextFrame()).image;
  codec.dispose();
  final w = photo.width, h = photo.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(photo, Offset.zero, Paint());
  paintWatermark(canvas, Size(w.toDouble(), h.toDouble()), info);
  final out = await recorder.endRecording().toImage(w, h);
  photo.dispose();
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  final jpg = await _nativeJpeg(png!.buffer.asUint8List(), maxSide, quality, knownSize: (w, h));
  return jpg ?? watermarkPhoto(base, info, maxSide: maxSide, quality: quality);
}
