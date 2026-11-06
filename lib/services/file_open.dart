import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openPdfBytes(List<int> bytes, String filename) async {
  if (kIsWeb) return;
  final dir = await getTemporaryDirectory();
  final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path);
}

Future<bool> openFileRecord(Map<String, dynamic> file) async {
  for (final key in ['url', 'download_url', 'file_url', 'preview_url']) {
    final v = file[key]?.toString();
    if (v == null || v.isEmpty) continue;
    if (v.startsWith('http://') || v.startsWith('https://')) {
      final uri = Uri.tryParse(v);
      if (uri != null && await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
  final path = file['path']?.toString();
  if (!kIsWeb && path != null && path.isNotEmpty) {
    await OpenFilex.open(path);
    return true;
  }
  return false;
}
