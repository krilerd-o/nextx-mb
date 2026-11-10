import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_config.dart';
import '../../../core/i18n.dart';
import '../../../services/api_client.dart';
import '../../../widgets/isaac_sticker.dart';
import '../../../widgets/nx_icons.dart';
import 'card_capture_screen.dart';
import 'card_ocr.dart';
import 'card_scan_models.dart';
import 'card_scan_review.dart';

/// Camera / gallery → Isaac reads the card (server AI; phone OCR only when
/// there is no AI) → review. Returns what the user kept, or null.
/// Never saves anything.
class CardScanFlow {
  CardScanFlow._();

  /// Test hook: skip the camera.
  @visibleForTesting
  static Future<CardImages?> Function(BuildContext context)? debugCapture;

  /// Fast path first: the photo goes to Isaac at once. Phone OCR runs only
  /// if the server answers `no_ai` (then just its text is sent — no re-upload).
  static Future<CardScanResult> read(ApiClient api, String module, CardImages images) async {
    final first = CardScanResult.from(await api.scanBusinessCard(module, front: images.front, back: images.back));
    if (first.status != 'no_ai') return first;
    final ocr = await CardOcr.read(images.front);
    if (ocr == null || ocr.trim().isEmpty) return first;
    final back = images.back == null ? null : await CardOcr.read(images.back!);
    return CardScanResult.from(await api.scanBusinessCard(module, ocrText: [ocr, ?back].join('\n')));
  }

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

    final outcome = await showGeneralDialog<({CardScanResult? result, Object? error})>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)), child: child),
      ),
      pageBuilder: (ctx, _, _) => IsaacReadingDialog(image: images.front, read: () => read(api, module, images)),
    );
    if (!context.mounted || outcome == null) return null;
    final r = outcome.result;
    if (r == null || r.status != 'ok') {
      final msg = outcome.error != null
          ? formatApiError(outcome.error!)
          : r?.status == 'no_ai'
              ? 'ยังอ่านนามบัตรไม่ได้: ยังไม่ได้ตั้งค่า AI ใน NEXTX และเครื่องนี้อ่านข้อความจากรูปไม่ได้ — ตั้งค่าคีย์ AI ที่ NEXTX › ตั้งค่า › AI'
              : 'อ่านนามบัตรไม่ออก ลองถ่ายใหม่ให้ชัดขึ้น แสงพอดี ไม่สะท้อน';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const IsaacSticker(state: 'confused', size: 72),
          title: Text(tr('สแกนนามบัตรไม่สำเร็จ')),
          content: Text(tr(msg)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ตกลง')))],
        ),
      );
      return null;
    }
    return nav.push<CardScanApply>(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => CardScanReviewScreen(module: module, result: r, images: images, formFields: formFields, currentValues: currentValues),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
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

/// Isaac reading the card: his sticker changes with each step, a scan line
/// sweeps the photo and the steps tick off. The last step only completes when
/// the answer is really back; then a short "done in 2.1 s · 9 fields".
class IsaacReadingDialog extends StatefulWidget {
  const IsaacReadingDialog({super.key, required this.image, required this.read});
  final Uint8List image;
  final Future<CardScanResult> Function() read;

  @override
  State<IsaacReadingDialog> createState() => _IsaacReadingDialogState();
}

class _IsaacReadingDialogState extends State<IsaacReadingDialog> with TickerProviderStateMixin {
  static const _steps = [
    (state: 'uploading', label: 'ส่งรูปนามบัตรให้ Isaac', after: 0),
    (state: 'reading', label: 'Isaac กำลังอ่านข้อความบนบัตร', after: 700),
    (state: 'analyzing', label: 'วิเคราะห์ชื่อ ตำแหน่ง บริษัท เบอร์ อีเมล', after: 2200),
    (state: 'checking', label: 'ตรวจกับข้อมูลบนบัตร + หารายการซ้ำ', after: 4000),
  ];

  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  final _clock = Stopwatch()..start();
  Timer? _tick;
  int _step = 0;
  CardScanResult? _result;
  Object? _error;

  bool get _done => _result != null || _error != null;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_done) return;
      final ms = _clock.elapsedMilliseconds;
      var s = 0;
      for (var i = 0; i < _steps.length; i++) {
        if (ms >= _steps[i].after) s = i;
      }
      if (s != _step && mounted) setState(() => _step = s);
    });
    widget.read().then((r) => _finish(r, null), onError: (Object e) => _finish(null, e));
  }

  Future<void> _finish(CardScanResult? r, Object? e) async {
    _clock.stop();
    if (!mounted) return;
    setState(() {
      _result = r;
      _error = e;
      _step = _steps.length;
    });
    final ok = r != null && r.status == 'ok';
    if (ok) HapticFeedback.mediumImpact();
    // Let the success / error moment be seen, briefly.
    await Future<void>.delayed(Duration(milliseconds: ok ? 850 : 400));
    if (mounted) Navigator.of(context).pop((result: r, error: e));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scan.dispose();
    _bob.dispose();
    super.dispose();
  }

  String get _isaacState {
    if (_error != null || (_result != null && _result!.status != 'ok')) return 'confused';
    if (_result != null) return 'success';
    return _steps[_step.clamp(0, _steps.length - 1)].state;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ok = _result != null && _result!.status == 'ok';
    final secs = (_clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
          key: const ValueKey('card-reading'),
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Isaac, gently bobbing; his pose follows the step.
                    AnimatedBuilder(
                      animation: _bob,
                      builder: (_, child) => Transform.translate(offset: Offset(0, -4 * Curves.easeInOut.transform(_bob.value)), child: child),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                        child: IsaacSticker(key: ValueKey(_isaacState), state: _isaacState, size: 96),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        ok
                            ? tr('Isaac อ่านเสร็จใน $secs วินาที · พบ ${_result!.fields.length} ช่อง')
                            : _done
                                ? tr('Isaac อ่านบัตรนี้ไม่ได้')
                                : tr('Isaac กำลังอ่านนามบัตร…'),
                        key: ValueKey('$ok$_done'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Card with a sweeping scan line.
                    AspectRatio(
                      aspectRatio: 1.636,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: LayoutBuilder(
                          builder: (context, box) => Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(widget.image, fit: BoxFit.cover, gaplessPlayback: true),
                              if (!_done)
                                AnimatedBuilder(
                                  animation: _scan,
                                  builder: (_, _) {
                                    final y = Curves.easeInOut.transform(_scan.value) * (box.maxHeight - 40);
                                    return Positioned(
                                      left: 0,
                                      right: 0,
                                      top: y,
                                      height: 40,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [cs.primary.withValues(alpha: 0), cs.primary.withValues(alpha: 0.35), cs.primary.withValues(alpha: 0)],
                                          ),
                                        ),
                                        child: Center(child: Container(height: 2.5, color: cs.primary)),
                                      ),
                                    );
                                  },
                                )
                              else
                                AnimatedOpacity(
                                  opacity: 1,
                                  duration: const Duration(milliseconds: 200),
                                  child: ColoredBox(
                                    color: (ok ? const Color(0xFF16A34A) : cs.error).withValues(alpha: 0.22),
                                    child: Center(
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0.4, end: 1),
                                        duration: const Duration(milliseconds: 380),
                                        curve: Curves.elasticOut,
                                        builder: (_, v, c) => Transform.scale(scale: v, child: c),
                                        child: CircleAvatar(
                                          radius: 30,
                                          backgroundColor: ok ? const Color(0xFF16A34A) : cs.error,
                                          child: Icon(ok ? NxI.check : NxI.x, color: Colors.white, size: 32),
                                        ),
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
                    for (var i = 0; i < _steps.length; i++) _stepRow(theme, i),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepRow(ThemeData theme, int i) {
    final cs = theme.colorScheme;
    final passed = i < _step || (_done && _result?.status == 'ok');
    final active = i == _step && !_done;
    final visible = i <= _step;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: visible ? 1 : 0.35,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: passed
                    ? const CircleAvatar(key: ValueKey('ok'), radius: 11, backgroundColor: Color(0xFF16A34A), child: Icon(NxI.check, size: 14, color: Colors.white))
                    : active
                        ? CircularProgressIndicator(key: const ValueKey('run'), strokeWidth: 2.4, color: cs.primary)
                        : Icon(NxI.circle, key: const ValueKey('wait'), size: 18, color: cs.outline),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr(_steps[i].label),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: visible ? null : cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
