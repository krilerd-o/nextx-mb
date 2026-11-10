import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// On-device text reading (ML Kit, Latin script, bundled model — works
/// without Google Play services). Only a fallback: the server prefers its AI
/// vision, which also reads Thai.
class CardOcr {
  CardOcr._();

  /// Test hook.
  @visibleForTesting
  static Future<String?> Function(Uint8List jpeg)? debugRead;

  static Future<String?> read(Uint8List jpeg) async {
    if (debugRead != null) return debugRead!(jpeg);
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/card_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(jpeg, flush: true);
      final r = await rec.processImage(InputImage.fromFilePath(tmp.path));
      final t = r.text.trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    } finally {
      await rec.close();
      try {
        await tmp?.delete();
      } catch (_) {}
    }
  }
}

/// Upright JPEG, longest side ≤ [maxSide]. [cropToCard] keeps the centre
/// band the camera frame shows (card ratio 90×55 mm, 92% of the width).
Future<Uint8List> prepareCardJpeg(Uint8List bytes, {bool cropToCard = false, int turns = 0, int maxSide = 1600}) {
  return compute(_prepare, (bytes, cropToCard, turns, maxSide));
}

Uint8List _prepare((Uint8List, bool, int, int) a) {
  var im = img.decodeImage(a.$1);
  if (im == null) return a.$1;
  im = img.bakeOrientation(im);
  if (a.$2) {
    final w = (im.width * 0.92).round();
    final h = (w / 1.636).round().clamp(1, im.height);
    im = img.copyCrop(im, x: ((im.width - w) / 2).round(), y: ((im.height - h) / 2).round(), width: w, height: h);
  }
  for (var i = 0; i < a.$3 % 4; i++) {
    im = img.copyRotate(im!, angle: 90);
  }
  final long = im!.width > im.height ? im.width : im.height;
  if (long > a.$4) {
    im = im.width >= im.height ? img.copyResize(im, width: a.$4) : img.copyResize(im, height: a.$4);
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}
