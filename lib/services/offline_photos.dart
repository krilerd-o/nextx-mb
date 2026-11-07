import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Check-in photos taken without signal: kept as files in the app's
/// documents folder until the offline queue uploads them.
class OfflinePhotos {
  OfflinePhotos._();

  static Future<String?> save(Uint8List bytes, String name) async {
    if (kIsWeb) return null;
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/offline_photos');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final f = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$safe');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists(String path) async => !kIsWeb && File(path).existsSync();

  static Future<void> delete(Iterable<String> paths) async {
    if (kIsWeb) return;
    for (final p in paths) {
      try {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }
}
