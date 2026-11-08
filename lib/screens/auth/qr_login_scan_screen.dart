import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/auth_errors.dart';
import '../../core/i18n.dart';
import '../../core/qr_login.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_icons.dart';

enum _Stage { scanning, redeeming, success, error }

/// "สแกน" login: scan the QR shown on the web (ตั้งค่า → ความปลอดภัย →
/// เข้าใช้งานแอปมือถือด้วย QR), redeem the one-time code, show a short success
/// animation, then open the session. With [initial] (QR opened from the phone's
/// camera app) the camera is skipped.
class QrLoginScanScreen extends StatefulWidget {
  const QrLoginScanScreen({super.key, this.initial});
  final QrLoginLink? initial;

  @override
  State<QrLoginScanScreen> createState() => _QrLoginScanScreenState();
}

class _QrLoginScanScreenState extends State<QrLoginScanScreen> with SingleTickerProviderStateMixin {
  MobileScannerController? _camera;
  late final AnimationController _check = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  _Stage _stage = _Stage.scanning;
  String? _hint;
  String? _error;
  String _name = '';
  String _business = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final first = widget.initial;
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redeem(first));
    } else {
      _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _check.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy || _stage != _Stage.scanning) return;
    for (final b in capture.barcodes) {
      final link = QrLoginLink.parse(b.rawValue);
      if (link != null) {
        _redeem(link);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty && mounted) {
      setState(() => _hint = 'QR นี้ไม่ใช่ QR เข้าสู่ระบบ MOAI NEXT');
    }
  }

  static String _errorText(Object e) {
    final status = e is ApiEnvelopeException ? e.statusCode : (e is ApiException ? e.statusCode : -1);
    if (status == 401 || status == 404 || status == 410) return 'QR หมดอายุหรือถูกใช้แล้ว — สร้าง QR ใหม่บนเว็บแล้วสแกนอีกครั้ง';
    if (status == 0) return 'เชื่อมต่อเซิร์ฟเวอร์ของ QR ไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    return authErrorMessage(e);
  }

  Future<void> _redeem(QrLoginLink link) async {
    if (_busy) return;
    _busy = true;
    final config = context.read<AppConfig>();
    setState(() {
      _stage = _Stage.redeeming;
      _error = null;
      _hint = null;
    });
    unawaited(_camera?.stop());
    try {
      final data = await config.redeemQr(link);
      if (!mounted) return;
      final user = data['user'] is Map ? Map<String, dynamic>.from(data['user'] as Map) : const <String, dynamic>{};
      final biz = data['business'] is Map ? Map<String, dynamic>.from(data['business'] as Map) : const <String, dynamic>{};
      final full = [user['first_name'], user['last_name']].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ');
      setState(() {
        _name = '${user['name'] ?? ''}'.trim().isNotEmpty ? '${user['name']}' : (full.isNotEmpty ? full : '${user['email'] ?? ''}');
        _business = '${biz['name'] ?? biz['business_name'] ?? ''}';
        _stage = _Stage.success;
      });
      unawaited(HapticFeedback.mediumImpact());
      await _check.forward();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      await config.finishQrLogin(link, data);
      if (mounted) Navigator.of(context).maybePop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = _errorText(e);
      });
    } finally {
      _busy = false;
    }
  }

  void _retry() {
    setState(() {
      _stage = _Stage.scanning;
      _error = null;
    });
    if (_camera == null) {
      _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    } else {
      unawaited(_camera!.start());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(tr('สแกน QR เข้าสู่ระบบ')),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && _stage == _Stage.scanning) MobileScanner(controller: camera, onDetect: _onDetect),
          if (_stage == _Stage.scanning) ...[
            const _ScanFrame(),
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hint != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                      child: Text(tr(_hint!), style: TextStyle(color: cs.onErrorContainer)),
                    ),
                  Text(
                    tr('เปิดเว็บ MOAI NEXT → ตั้งค่า → ความปลอดภัย → เข้าใช้งานแอปมือถือด้วย QR แล้วส่องกล้องไปที่ QR'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
          if (_stage != _Stage.scanning)
            ColoredBox(
              color: cs.surface,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: switch (_stage) {
                      _Stage.redeeming => Column(
                          key: const ValueKey('qr-redeeming'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3)),
                            const SizedBox(height: 18),
                            Text(tr('กำลังเข้าสู่ระบบ…'), style: theme.textTheme.titleMedium),
                          ],
                        ),
                      _Stage.success => _SuccessView(key: const ValueKey('qr-success'), progress: _check, name: _name, business: _business),
                      _ => Column(
                          key: const ValueKey('qr-error'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(NxI.warningCircle, size: 56, color: cs.error),
                            const SizedBox(height: 14),
                            Text(tr(_error ?? 'เข้าสู่ระบบไม่สำเร็จ'), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 20),
                            FilledButton.icon(onPressed: _retry, icon: const Icon(NxI.qrCode, size: 18), label: Text(tr('สแกนอีกครั้ง'))),
                            TextButton(onPressed: () => Navigator.of(context).maybePop(false), child: Text(tr('ยกเลิก'))),
                          ],
                        ),
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rounded viewfinder with a dimmed outside.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = (box.biggest.shortestSide * 0.68).clamp(180.0, 320.0);
      return Center(
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.55), spreadRadius: 2000)],
          ),
        ),
      );
    });
  }
}

/// Green circle that pops in, a check that draws itself, then name + business.
class _SuccessView extends StatelessWidget {
  const _SuccessView({super.key, required this.progress, required this.name, required this.business});
  final Animation<double> progress;
  final String name;
  final String business;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF16A34A);
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = progress.value;
        final pop = Curves.elasticOut.transform((t / 0.7).clamp(0.0, 1.0));
        final draw = Curves.easeOut.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));
        final text = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.4 + 0.6 * pop,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: green,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: green.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))],
                ),
                child: CustomPaint(painter: _CheckPainter(draw)),
              ),
            ),
            const SizedBox(height: 22),
            Opacity(
              opacity: text,
              child: Column(
                children: [
                  Text(tr('เข้าสู่ระบบสำเร็จ'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if (name.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(name, style: theme.textTheme.titleMedium),
                  ],
                  if (business.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(business, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final a = Offset(size.width * 0.28, size.height * 0.52);
    final b = Offset(size.width * 0.44, size.height * 0.67);
    final c = Offset(size.width * 0.73, size.height * 0.37);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * t), p);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}
