import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../widgets/nx_icons.dart';

/// Photos per Fast Take round: quick to shoot without waiting, ~3–5 MB per
/// round on 4G, uploaded in batches of [kFastTakeBatch].
const kFastTakeMax = 10;
const kFastTakeBatch = 5;

/// Full-screen in-app camera: keep tapping the shutter, review the strip, then
/// "เสร็จ" returns all shots at once. Returns null when cancelled.
class FastTakeScreen extends StatefulWidget {
  const FastTakeScreen({super.key, this.max = kFastTakeMax});

  final int max;

  @override
  State<FastTakeScreen> createState() => _FastTakeScreenState();
}

class _FastTakeScreenState extends State<FastTakeScreen> with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;
  final List<XFile> _shots = [];
  bool _taking = false;
  bool _flashUi = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final c = CameraController(_cams[_camIndex], ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _ctrl = c;
    await old?.dispose();
    await c.initialize();
    try {
      await c.setFlashMode(_flash);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _ctrl = null;
    } else if (state == AppLifecycleState.resumed) {
      _open();
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
    if (c == null || !c.value.isInitialized || _taking || _shots.length >= widget.max) return;
    setState(() {
      _taking = true;
      _flashUi = true;
    });
    HapticFeedback.lightImpact();
    try {
      final f = await c.takePicture();
      if (!mounted) return;
      setState(() => _shots.add(f));
      if (_shots.length == widget.max) HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ถ่ายไม่สำเร็จ: $e'))));
    } finally {
      if (mounted) setState(() => _taking = false);
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _flashUi = false);
      });
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

  Future<bool> _confirmDiscard() async {
    if (_shots.isEmpty) return true;
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

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final full = _shots.length >= widget.max;
    return PopScope(
      canPop: _shots.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar: close, counter, flash, switch.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr('ปิด'),
                      color: Colors.white,
                      icon: const Icon(NxI.x),
                      onPressed: () async {
                        if (await _confirmDiscard() && context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
                    Container(
                      key: const ValueKey('fast-take-count'),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: full ? const Color(0xFFF59E0B) : Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_shots.length}/${widget.max}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
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
                          child: Text(tr('เปิดกล้องไม่ได้: $_error'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        ),
                      )
                    else if (c != null && c.value.isInitialized)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: c.value.previewSize?.height ?? 1080,
                            height: c.value.previewSize?.width ?? 1920,
                            child: CameraPreview(c),
                          ),
                        ),
                      )
                    else
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                    IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _flashUi ? 0.6 : 0,
                        duration: const Duration(milliseconds: 90),
                        child: const ColoredBox(color: Colors.white),
                      ),
                    ),
                    if (full)
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 12,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                          child: Text(
                            tr('ครบ ${widget.max} รูปต่อรอบแล้ว — กด "เสร็จ" เพื่ออัปโหลด แล้วถ่ายรอบใหม่ได้'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Thumbnails (tap to remove).
              SizedBox(
                height: 76,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: _shots.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => GestureDetector(
                    key: ValueKey('fast-take-thumb-$i'),
                    onTap: () => setState(() => _shots.removeAt(i)),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(File(_shots[i].path), width: 60, height: 60, fit: BoxFit.cover, cacheWidth: 120),
                        ),
                        const Positioned(
                          right: 2,
                          top: 2,
                          child: CircleAvatar(radius: 9, backgroundColor: Colors.black54, child: Icon(NxI.x, size: 12, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    GestureDetector(
                      key: const ValueKey('fast-take-shutter'),
                      onTap: full ? null : _shoot,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 78,
                        height: 78,
                        padding: EdgeInsets.all(_taking ? 9 : 5),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                        child: DecoratedBox(
                          decoration: BoxDecoration(shape: BoxShape.circle, color: full ? Colors.white30 : Colors.white),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: const ValueKey('fast-take-done'),
                          icon: const Icon(NxI.check, size: 18),
                          label: Text(tr('เสร็จ (${_shots.length})')),
                          onPressed: _shots.isEmpty ? null : () => Navigator.of(context).pop(List<XFile>.of(_shots)),
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
