import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/i18n.dart';
import '../../widgets/fields/nx_lift_sheet.dart';
import '../../widgets/nx_icons.dart';

/// Test seams for the step forms (camera, file picker, map pin).
class DocFormHooks {
  DocFormHooks._();
  static Future<String?> Function(BuildContext context)? scanBarcode;
  static Future<List<MultipartFile>> Function(BuildContext context)? pickFiles;
  static Future<({double lat, double lng})?> Function(BuildContext context)? pickPin;
  static Future<String?> Function(double lat, double lng)? reverseGeocode;

  static void reset() {
    scanBarcode = null;
    pickFiles = null;
    pickPin = null;
    reverseGeocode = null;
  }
}

/// Barcode / QR of a product (same scanner package as QR login): the code, or null.
Future<String?> scanProductBarcode(BuildContext context) {
  final hook = DocFormHooks.scanBarcode;
  if (hook != null) return hook(context);
  return showNxLiftSheet<String>(context: context, builder: (ctx, _) => const _BarcodeSheet());
}

class _BarcodeSheet extends StatefulWidget {
  const _BarcodeSheet();
  @override
  State<_BarcodeSheet> createState() => _BarcodeSheetState();
}

class _BarcodeSheetState extends State<_BarcodeSheet> {
  final _camera = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture c) {
    if (_done) return;
    final code = c.barcodes.map((b) => b.rawValue ?? '').firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    if (code.isEmpty) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            const Icon(NxI.scanLine),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('สแกนบาร์โค้ดสินค้า'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(tooltip: tr('ปิด'), onPressed: () => Navigator.pop(context), icon: const Icon(NxI.x)),
          ]),
        ),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: MobileScanner(controller: _camera, onDetect: _onDetect),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('เล็งบาร์โค้ดหรือ QR บนสินค้าให้อยู่ในกรอบ'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
