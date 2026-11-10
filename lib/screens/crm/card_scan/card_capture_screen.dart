import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n.dart';
import '../../../widgets/nx_icons.dart';
import 'card_ocr.dart';
import 'card_scan_models.dart';

/// Full-screen camera with a business-card frame: shoot the front, then
/// optionally the back; or pick from the gallery. Returns the prepared JPEGs.
class CardCaptureScreen extends StatefulWidget {
  const CardCaptureScreen({super.key, this.cameraFactory});

  /// Test hook: no real camera in widget tests.
  final Future<List<CameraDescription>> Function()? cameraFactory;

  @override
  State<CardCaptureScreen> createState() => _CardCaptureScreenState();
}

class _CardCaptureScreenState extends State<CardCaptureScreen> with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = const [];
  Object? _error;
  bool _busy = false;
  bool _torch = false;
  Uint8List? _front;

  /// Shooting the back after the front.
  bool get _backStep => _front != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      _cams = await (widget.cameraFactory ?? availableCameras)();
      final back = _cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull ?? _cams.firstOrNull;
      if (back == null) throw StateError(tr('ไม่พบกล้อง'));
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      _ctrl = c;
      await c.initialize();
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      final x = await c.takePicture();
      final jpeg = await prepareCardJpeg(await x.readAsBytes(), cropToCard: true);
      await _got(jpeg);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ถ่ายไม่สำเร็จ: $e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 92);
    if (x == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _got(await prepareCardJpeg(await x.readAsBytes()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _got(Uint8List jpeg) async {
    if (!_backStep) {
      _front = jpeg;
      if (!mounted) return;
      final wantBack = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(jpeg, height: 150, fit: BoxFit.cover)),
                const SizedBox(height: 14),
                Text(tr('มีข้อมูลด้านหลังนามบัตรไหม?'), style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tr('เช่น ชื่อภาษาอังกฤษ ที่อยู่ หรือเบอร์เพิ่มเติม'), style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('card-skip-back'),
                  icon: const Icon(NxI.sparkle),
                  label: Text(tr('อ่านนามบัตรเลย')),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('card-shoot-back'),
                  icon: const Icon(NxI.camera),
                  label: Text(tr('ถ่ายด้านหลังด้วย')),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (wantBack == true) {
        setState(() {});
        return;
      }
      if (wantBack == null) {
        // Dismissed: shoot the front again.
        setState(() => _front = null);
        return;
      }
      Navigator.of(context).pop(CardImages(front: _front!));
      return;
    }
    Navigator.of(context).pop(CardImages(front: _front!, back: jpeg));
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(tooltip: tr('ปิด'), color: Colors.white, icon: const Icon(NxI.x), onPressed: () => Navigator.of(context).pop()),
                  Expanded(
                    child: Text(
                      tr(_backStep ? 'ถ่ายด้านหลังนามบัตร' : 'สแกนนามบัตร'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('ไฟฉาย'),
                    color: Colors.white,
                    icon: Icon(_torch ? NxI.lightning : NxI.flashOff),
                    onPressed: c == null
                        ? null
                        : () async {
                            _torch = !_torch;
                            try {
                              await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
                            } catch (_) {}
                            setState(() {});
                          },
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final fw = box.maxWidth * 0.92;
                  final fh = fw / 1.636;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_error != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tr('เปิดกล้องไม่ได้: $_error'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                                const SizedBox(height: 12),
                                FilledButton.icon(icon: const Icon(NxI.images), label: Text(tr('เลือกรูปนามบัตรจากคลังภาพ')), onPressed: _pickGallery),
                              ],
                            ),
                          ),
                        )
                      else if (c != null && c.value.isInitialized)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: c.value.previewSize?.height ?? 1080,
                            height: c.value.previewSize?.width ?? 1920,
                            child: CameraPreview(c),
                          ),
                        )
                      else
                        const Center(child: CircularProgressIndicator(color: Colors.white)),
                      // Dim outside the card frame.
                      IgnorePointer(
                        child: CustomPaint(painter: _FramePainter(Size(fw, fh))),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        top: (box.maxHeight + fh) / 2 + 14,
                        child: Text(
                          tr(_backStep ? 'วางด้านหลังนามบัตรให้อยู่ในกรอบ' : 'วางนามบัตรให้อยู่ในกรอบ แสงพอดี ไม่สะท้อน'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton.filledTonal(
                        key: const ValueKey('card-gallery'),
                        tooltip: tr('เลือกจากคลังภาพ'),
                        iconSize: 26,
                        icon: const Icon(NxI.images),
                        onPressed: _busy ? null : _pickGallery,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('card-shutter'),
                    onTap: _busy ? null : _shoot,
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      child: const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                    ),
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame);
  final Size frame;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: size.center(Offset.zero), width: frame.width, height: frame.height),
      const Radius.circular(16),
    );
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawRRect(r, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    // Corner accents.
    final p = Paint()
      ..color = const Color(0xFF22C55E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    final o = r.outerRect;
    for (final (c, dx, dy) in [(o.topLeft, 1.0, 1.0), (o.topRight, -1.0, 1.0), (o.bottomLeft, 1.0, -1.0), (o.bottomRight, -1.0, -1.0)]) {
      canvas.drawLine(c, c + Offset(l * dx, 0), p);
      canvas.drawLine(c, c + Offset(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.frame != frame;
}
