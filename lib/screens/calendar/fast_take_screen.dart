import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../services/shutter_sound.dart';
import '../../widgets/nx_icons.dart';

/// Photos per Fast Take round. Each shot is processed and uploaded while the
/// user keeps shooting, so a round can be long.
const kFastTakeMax = 30;

/// Legacy batch size (activity batches); the new pipeline sends one by one.
const kFastTakeBatch = 5;

/// Test hook: replaces the platform camera.
@visibleForTesting
Future<XFile> Function()? debugFastTakeCapture;

/// Full-screen in-app camera tuned for speed:
/// - every tap is answered at once (shutter sound, white flash, haptic) and queued,
///   so taps are never dropped while the previous picture is still being saved;
/// - the preview never rebuilds (counters live in [ValueNotifier]s);
/// - each saved shot goes to [onShot] right away (resize / watermark / upload in
///   the background); "เสร็จ" returns immediately.
/// Returns the shots (also when [onShot] is used), or null when cancelled.
class FastTakeScreen extends StatefulWidget {
  const FastTakeScreen({super.key, this.max = kFastTakeMax, this.onShot, this.title});

  final int max;
  final void Function(XFile shot)? onShot;
  final String? title;

  @override
  State<FastTakeScreen> createState() => _FastTakeScreenState();
}

class _FastTakeScreenState extends State<FastTakeScreen> with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;
  Object? _error;

  final List<XFile> _shots = [];
  final _count = ValueNotifier<int>(0); // saved + queued
  final _flashUi = ValueNotifier<bool>(false);
  final _thumbs = ValueNotifier<int>(0);
  int _queued = 0;
  bool _draining = false;
  Timer? _flashTimer;

  bool get _testMode => debugFastTakeCapture != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ShutterSound.instance.preload());
    if (_testMode) return;
    _init();
  }

  Future<void> _init() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) throw StateError('ไม่พบกล้อง');
      _camIndex = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_camIndex < 0) _camIndex = 0;
      await _open();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open() async {
    final old = _ctrl;
    // 1080p: sharp enough for evidence, quick to save (sent as ≤1920px anyway).
    final c = CameraController(_cams[_camIndex], ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _ctrl = c;
    await old?.dispose();
    await c.initialize();
    try {
      await c.setFlashMode(_flash);
      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_testMode) return;
    // Keep the camera through short interruptions (notification shade = inactive);
    // release only when the app really goes to the background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      final c = _ctrl;
      _ctrl = null;
      c?.dispose();
    } else if (state == AppLifecycleState.resumed && _ctrl == null && _cams.isNotEmpty) {
      _open();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashTimer?.cancel();
    _ctrl?.dispose();
    _count.dispose();
    _flashUi.dispose();
    _thumbs.dispose();
    super.dispose();
  }

  bool get _full => _count.value >= widget.max;

  void _shoot() {
    final c = _ctrl;
    if (!_testMode && (c == null || !c.value.isInitialized)) return;
    if (_full) return;
    // Instant feedback, before the camera has finished.
    ShutterSound.instance.play();
    HapticFeedback.lightImpact();
    _flashUi.value = true;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 90), () => _flashUi.value = false);
    _queued++;
    _count.value = _shots.length + _queued;
    if (_full) HapticFeedback.mediumImpact();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queued > 0 && mounted) {
        try {
          final XFile f;
          final hook = debugFastTakeCapture;
          if (hook != null) {
            f = await hook();
          } else {
            final c = _ctrl;
            if (c == null || !c.value.isInitialized) break;
            f = await c.takePicture();
          }
          _shots.add(f);
          widget.onShot?.call(f);
          _thumbs.value = _shots.length;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('ถ่ายไม่สำเร็จ')}: $e')));
          }
        } finally {
          _queued--;
          if (mounted) _count.value = _shots.length + _queued;
        }
      }
    } finally {
      _queued = _queued < 0 ? 0 : _queued;
      _draining = false;
    }
  }

  Future<void> _switchCam() async {
    if (_cams.length < 2) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    await _open();
  }

  Future<void> _toggleFlash() async {
    _flash = _flash == FlashMode.off ? FlashMode.auto : (_flash == FlashMode.auto ? FlashMode.always : FlashMode.off);
    try {
      await _ctrl?.setFlashMode(_flash);
    } catch (_) {}
    setState(() {});
  }

  /// Shots already handed to [onShot] are uploading — leaving keeps them.
  Future<bool> _confirmDiscard() async {
    if (_shots.isEmpty || widget.onShot != null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ทิ้งรูปที่ถ่ายไว้?')),
        content: Text(tr('ถ่ายไว้ ${_shots.length} รูป ยังไม่ได้อัปโหลด')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ถ่ายต่อ'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ทิ้งรูป'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _finish() async {
    // Let shots still being saved land first (usually a few hundred ms).
    while (_draining || _queued > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
    }
    if (mounted) Navigator.of(context).pop(List<XFile>.of(_shots));
  }

  void _removeShot(int i) {
    if (widget.onShot != null) return; // already uploading
    _shots.removeAt(i);
    _thumbs.value = _shots.length;
    _count.value = _shots.length + _queued;
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final streaming = widget.onShot != null;
    return PopScope(
      canPop: _shots.isEmpty || streaming,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr('ปิด'),
                      color: Colors.white,
                      icon: const Icon(NxI.x),
                      onPressed: () async {
                        if (streaming) return _finish();
                        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
                    ValueListenableBuilder<int>(
                      valueListenable: _count,
                      builder: (context, n, _) => Container(
                        key: const ValueKey('fast-take-count'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: n >= widget.max ? const Color(0xFFF59E0B) : Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('$n/${widget.max}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: tr('แฟลช'),
                      color: Colors.white,
                      icon: Icon(_flash == FlashMode.off ? NxI.flashOff : NxI.lightning),
                      onPressed: c == null ? null : _toggleFlash,
                    ),
                    IconButton(
                      tooltip: tr('สลับกล้อง'),
                      color: Colors.white,
                      icon: const Icon(NxI.cameraRotate),
                      onPressed: _cams.length < 2 ? null : _switchCam,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('${tr('เปิดกล้องไม่ได้')}: $_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        ),
                      )
                    else if (c != null && c.value.isInitialized)
                      RepaintBoundary(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: c.value.previewSize?.height ?? 1080,
                              height: c.value.previewSize?.width ?? 1920,
                              child: CameraPreview(c),
                            ),
                          ),
                        ),
                      )
                    else if (!_testMode)
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                    IgnorePointer(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _flashUi,
                        builder: (context, on, _) => AnimatedOpacity(
                          opacity: on ? 0.55 : 0,
                          duration: const Duration(milliseconds: 70),
                          child: const ColoredBox(color: Colors.white),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _count,
                      builder: (context, n, _) => n < widget.max
                          ? const SizedBox.shrink()
                          : Positioned(
                              left: 16,
                              right: 16,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                                child: Text(
                                  tr('ครบ ${widget.max} รูปต่อรอบแล้ว — กด "เสร็จ" แล้วถ่ายรอบใหม่ได้'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                    ),
                    if (streaming)
                      Positioned(
                        left: 12,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(NxI.uploadSimple, size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(tr('อัปโหลดอัตโนมัติขณะถ่าย'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 76,
                child: ValueListenableBuilder<int>(
                  valueListenable: _thumbs,
                  builder: (context, n, _) => ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemCount: n,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, j) {
                      final i = n - 1 - j; // newest first, next to the shutter
                      return GestureDetector(
                        key: ValueKey('fast-take-thumb-$i'),
                        onTap: streaming ? null : () => _removeShot(i),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _testMode
                                  ? const SizedBox(width: 60, height: 60, child: ColoredBox(color: Colors.white24))
                                  : Image.file(File(_shots[i].path), width: 60, height: 60, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
                            ),
                            if (!streaming)
                              const Positioned(
                                right: 2,
                                top: 2,
                                child: CircleAvatar(radius: 9, backgroundColor: Colors.black54, child: Icon(NxI.x, size: 12, color: Colors.white)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    ValueListenableBuilder<int>(
                      valueListenable: _count,
                      builder: (context, n, _) {
                        final full = n >= widget.max;
                        return Listener(
                          // onPointerDown: fires on touch, no tap-recognizer delay.
                          onPointerDown: full ? null : (_) => _shoot(),
                          child: Container(
                            key: const ValueKey('fast-take-shutter'),
                            width: 78,
                            height: 78,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                            child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: full ? Colors.white30 : Colors.white)),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ValueListenableBuilder<int>(
                          valueListenable: _count,
                          builder: (context, n, _) => FilledButton.icon(
                            key: const ValueKey('fast-take-done'),
                            icon: const Icon(NxI.check, size: 18),
                            label: Text(tr('เสร็จ ($n)')),
                            onPressed: n == 0 ? null : _finish,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
