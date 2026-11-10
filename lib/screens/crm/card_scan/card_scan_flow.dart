import 'dart:typed_data';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_config.dart';
import '../../../core/i18n.dart';
import '../../../services/api_client.dart';
import '../../../widgets/nx_icons.dart';
import 'card_capture_screen.dart';
import 'card_ocr.dart';
import 'card_scan_models.dart';
import 'card_scan_review.dart';

/// Camera / gallery → read (server AI, phone OCR fallback) → review.
/// Returns what the user kept, or null. Never saves anything.
class CardScanFlow {
  CardScanFlow._();

  /// Test hook: skip the camera.
  @visibleForTesting
  static Future<CardImages?> Function(BuildContext context)? debugCapture;

  static Future<CardScanApply?> run(
    BuildContext context, {
    required String module,
    required Map<String, String> formFields,
    Map<String, dynamic> currentValues = const {},
  }) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final api = context.read<AppConfig>().apiClient;
    final images = debugCapture != null
        ? await debugCapture!(context)
        : await nav.push<CardImages>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CardCaptureScreen()));
    if (images == null || !context.mounted) return null;

    CardScanResult? result;
    Object? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => _ReadingDialog(
        image: images.front,
        work: () async {
          try {
            final ocr = await CardOcr.read(images.front);
            final data = await api.scanBusinessCard(module, front: images.front, back: images.back, ocrText: ocr);
            result = CardScanResult.from(data);
          } catch (e) {
            error = e;
          }
        },
      ),
    );
    if (!context.mounted) return null;
    final r = result;
    if (r == null || r.status != 'ok') {
      final msg = error != null
          ? formatApiError(error!)
          : r?.status == 'no_ai'
              ? 'ยังอ่านนามบัตรไม่ได้: ยังไม่ได้ตั้งค่า AI ใน NEXTX และเครื่องนี้อ่านข้อความจากรูปไม่ได้ — ตั้งค่าคีย์ AI ที่ NEXTX › ตั้งค่า › AI'
              : 'อ่านนามบัตรไม่ออก ลองถ่ายใหม่ให้ชัดขึ้น แสงพอดี ไม่สะท้อน';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(NxI.warning),
          title: Text(tr('สแกนนามบัตรไม่สำเร็จ')),
          content: Text(tr(msg)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ตกลง')))],
        ),
      );
      return null;
    }
    return nav.push<CardScanApply>(MaterialPageRoute(
      builder: (_) => CardScanReviewScreen(module: module, result: r, images: images, formFields: formFields, currentValues: currentValues),
    ));
  }

  /// After the record is saved: card photo(s) as an attachment comment.
  static Future<void> attachToRecord(ApiClient api, {required String module, required String id, required CardImages images}) async {
    final files = [
      MultipartFile.fromBytes(images.front, filename: 'business_card_front.jpg'),
      if (images.back != null) MultipartFile.fromBytes(images.back!, filename: 'business_card_back.jpg'),
    ];
    final atts = await api.uploadCommentAttachments(files);
    await api.postEntityComment(module, id, tr('นามบัตร (สแกน)'), attachments: atts);
  }
}

/// "กำลังอ่านนามบัตร…" with a scan line sweeping over the photo.
class _ReadingDialog extends StatefulWidget {
  const _ReadingDialog({required this.image, required this.work});
  final Uint8List image;
  final Future<void> Function() work;

  @override
  State<_ReadingDialog> createState() => _ReadingDialogState();
}

class _ReadingDialogState extends State<_ReadingDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    widget.work().whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      key: const ValueKey('card-reading'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.636,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(widget.image, fit: BoxFit.cover),
                      AnimatedBuilder(
                        animation: _a,
                        builder: (_, _) => Positioned(
                          left: 0,
                          right: 0,
                          top: _a.value * (box.maxHeight - 4),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.6), blurRadius: 14, spreadRadius: 2)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(tr('กำลังอ่านนามบัตร…'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(tr('ตรวจชื่อ เบอร์ อีเมล และที่อยู่ให้ตรงกับบนบัตร'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
