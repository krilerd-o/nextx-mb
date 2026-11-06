import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<File> _writeTempPdf(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> openPdfBytes(List<int> bytes, String filename) async {
  if (kIsWeb) return;
  final file = await _writeTempPdf(bytes, filename);
  await OpenFilex.open(file.path);
}

Future<void> sharePdfBytes(List<int> bytes, String filename) async {
  if (kIsWeb) return;
  final file = await _writeTempPdf(bytes, filename);
  await Share.shareXFiles([XFile(file.path)], text: filename);
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
