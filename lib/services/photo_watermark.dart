import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// What goes on a location watermark (bottom-right, like a GPS camera).
class WatermarkInfo {
  const WatermarkInfo({required this.at, this.lat, this.lng, this.address});

  /// Thai wall-clock time of the shot.
  final DateTime at;
  final double? lat;
  final double? lng;

  /// Place / address, up to three lines.
  final String? address;

  /// `3/12/2024   13:23:15`, `13.71338…,100.74079…`, then the address lines.
  List<String> get lines {
    String two(int n) => n.toString().padLeft(2, '0');
    return [
      '${at.day}/${at.month}/${at.year}    ${two(at.hour)}:${two(at.minute)}:${two(at.second)}',
      if (lat != null && lng != null) '$lat,$lng',
      for (final l in (address ?? '').split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
  }
}

/// Draws [info] on the photo (longest side ≤ [maxSide]) and returns a JPEG.
Future<Uint8List> watermarkPhoto(
  Uint8List source,
  WatermarkInfo info, {
  int maxSide = 1920,
  int quality = 85,
}) async {
  final probe = await ui.instantiateImageCodec(source);
  final first = (await probe.getNextFrame()).image;
  var w = first.width, h = first.height;
  first.dispose();
  probe.dispose();
  final scale = (w > h ? w : h) > maxSide ? maxSide / (w > h ? w : h) : 1.0;
  w = (w * scale).round();
  h = (h * scale).round();
  final codec = await ui.instantiateImageCodec(source, targetWidth: w, targetHeight: h);
  final photo = (await codec.getNextFrame()).image;
  codec.dispose();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(photo, Offset.zero, Paint());
  paintWatermark(canvas, Size(w.toDouble(), h.toDouble()), info);
  final picture = recorder.endRecording();
  final out = await picture.toImage(w, h);
  photo.dispose();
  final rgba = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  out.dispose();
  return compute(_encodeJpg, (rgba!.buffer.asUint8List(), w, h, quality));
}

Uint8List _encodeJpg((Uint8List, int, int, int) a) {
  final image = img.Image.fromBytes(width: a.$2, height: a.$3, bytes: a.$1.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  return img.encodeJpg(image, quality: a.$4);
}

/// Text block at the bottom-right over a soft shadow band, readable on any photo.
void paintWatermark(Canvas canvas, Size size, WatermarkInfo info) {
  final short = size.shortestSide;
  final fontSize = (short * 0.036).clamp(12.0, 64.0);
  final pad = short * 0.04;
  final style = TextStyle(
    color: const Color(0xFFFFFFFF),
    fontSize: fontSize,
    height: 1.25,
    fontWeight: FontWeight.w600,
    // Bundled app fonts (Latin digits + Thai place names), same as the UI.
    fontFamily: 'GoogleSans',
    fontFamilyFallback: const ['IBMPlexSansThai', 'NotoSansThai'],
    shadows: [Shadow(color: const Color(0xCC000000), blurRadius: fontSize * 0.35, offset: Offset(0, fontSize * 0.06))],
  );
  final painters = [
    for (final l in info.lines)
      TextPainter(text: TextSpan(text: l, style: style), textAlign: TextAlign.right, textDirection: TextDirection.ltr, maxLines: 2)
        ..layout(maxWidth: size.width - pad * 2),
  ];
  final block = painters.fold<double>(0, (s, p) => s + p.height + fontSize * 0.2);
  final band = block + pad * 2.2;
  final rect = Rect.fromLTWH(0, size.height - band, size.width, band);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, const [Color(0x00000000), Color(0x8C000000)]),
  );
  var y = size.height - pad - block;
  for (final p in painters) {
    p.paint(canvas, Offset(size.width - pad - p.width, y));
    y += p.height + fontSize * 0.2;
    p.dispose();
  }
}
