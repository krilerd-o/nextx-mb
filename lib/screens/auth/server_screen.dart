import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/server_profile.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../../widgets/nx_step_header.dart';
import '../../core/i18n.dart';

/// "เชื่อมต่อระบบ" — any NEXTX server, verified via /api/health signature.
///
/// Two ways in: "กรอกด้วยตนเอง" (type the address) or "สแกน" (the team's QR of
/// the server address — the scanned text goes into the box, is checked, and
/// only a real MOAI NEXT server continues).
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  /// Tests: replaces the server check (network) and the camera.
  @visibleForTesting
  static Future<ServerCheckResult> Function(String input)? verifyOverride;
  @visibleForTesting
  static Widget Function(ValueChanged<String> onCode)? scannerOverride;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final TextEditingController _url = TextEditingController(
    text: serverLabel(context.read<AppConfig>().pendingInvite?.server ?? context.read<AppConfig>().apiBaseUrl),
  );
  bool _busy = false;
  String? _error;
  bool _scan = false;
  /// Scan tab: a code was read and is being checked (camera ignores more codes).
  bool _scanLocked = false;
  MobileScannerController? _camera;

  @override
  void dispose() {
    _url.dispose();
    _camera?.dispose();
    super.dispose();
  }

  void _setMode(bool scan) {
    if (scan == _scan) return;
    setState(() {
      _scan = scan;
      _error = null;
      _scanLocked = false;
      if (scan) {
        _url.clear();
        _camera ??= ServerScreen.scannerOverride == null ? MobileScannerController(formats: const [BarcodeFormat.qrCode]) : null;
      } else {
        _camera?.dispose();
        _camera = null;
      }
    });
  }

  /// The QR's text goes into the box as-is; a real MOAI NEXT server continues to sign in.
  Future<void> _onScanned(String raw) async {
    final text = raw.trim();
    if (_busy || _scanLocked || text.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _scanLocked = true;
      _url.text = text;
    });
    final ok = await _connect(text, true);
    if (!ok && mounted) setState(() => _scanLocked = false);
  }

  Future<void> _notServerDialog(String text, String? reason) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('server-scan-invalid'),
        icon: const Icon(NxI.warning, size: 32),
        title: Text(tr('QR นี้ไม่ใช่ระบบ MOAI NEXT')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(reason ?? 'ตรวจสอบแล้ว ที่อยู่นี้ไม่ใช่เซิร์ฟเวอร์ MOAI NEXT'), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.bodySmall),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ปิด'))),
          FilledButton(key: const ValueKey('server-scan-clear'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ล้างช่องแล้วสแกนใหม่'))),
        ],
      ),
    );
    if (!mounted) return;
    if (clear == true) {
      setState(() {
        _url.clear();
        _error = null;
      });
    }
  }

  Future<bool> _connect([String? value, bool? fromScanArg]) async {
    final fromScan = fromScanArg ?? false;
    final input = (value ?? _url.text).trim();
    if (input.isEmpty) {
      setState(() => _error = 'กรุณาใส่ที่อยู่เซิร์ฟเวอร์ให้ถูกต้อง');
      return false;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await (ServerScreen.verifyOverride ?? verifyNextxServer)(input);
    if (!mounted) return false;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = fromScan ? null : result.message;
      });
      if (fromScan) await _notServerDialog(input, result.message);
      return false;
    }
    await context.read<AppConfig>().selectServer(result.url);
    if (!mounted) return false;
    setState(() => _busy = false);
    if (result.maintenance) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เซิร์ฟเวอร์อยู่ระหว่างปรับปรุง บางฟังก์ชันอาจใช้ไม่ได้'))));
    }
    context.go(AppRoutes.login);
    return true;
  }

  // System back does the same as the header's back (instead of closing the app).
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) context.go(AppRoutes.welcome);
        },
        child: _buildPage(context),
      );


  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final recent = config.recentServers.where((u) => serverLabel(u) != serverLabel(kDefaultApiBaseUrl)).toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            NxStepHeader(step: 1, total: 2, onBack: () => context.go(AppRoutes.welcome)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22)),
                      child: Icon(NxI.globe, size: 36, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(tr('เชื่อมต่อระบบของคุณ'),
                      textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    tr('ใส่ที่อยู่เซิร์ฟเวอร์ MOAI NEXT ของธุรกิจคุณ\nหรือสแกน QR ที่ทีมของคุณให้มา'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  KeyedSubtree(
                    key: const ValueKey('server-mode'),
                    child: NxSlidingSegmented<bool>(
                      value: _scan,
                      options: const [(false, 'กรอกด้วยตนเอง', NxI.pencilSimple), (true, 'สแกน', NxI.qrCode)],
                      onChanged: _busy ? (_) {} : _setMode,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_scan) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ServerScreen.scannerOverride?.call(_onScanned) ??
                                MobileScanner(
                                  controller: _camera,
                                  onDetect: (cap) {
                                    final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                                    if (v != null) _onScanned(v);
                                  },
                                  errorBuilder: (context, error) => ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          tr('เปิดกล้องไม่ได้ — อนุญาตให้แอปใช้กล้องในการตั้งค่าเครื่อง หรือใช้แท็บ "กรอกด้วยตนเอง"'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            IgnorePointer(
                              child: Center(
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                            if (_busy)
                              const ColoredBox(color: Color(0x88000000), child: Center(child: CircularProgressIndicator(color: Colors.white))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr('สแกน QR ที่อยู่ระบบที่ทีมของคุณให้มา'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                  ] else
                    for (final u in recent) ...[
                      NxChoiceCard(
                        title: serverLabel(u),
                        subtitle: 'ใช้ล่าสุด',
                        icon: NxI.hardDrives,
                        selected: serverLabel(_url.text) == serverLabel(u),
                        onTap: _busy ? null : () => setState(() => _url.text = serverLabel(u)),
                      ),
                      const SizedBox(height: 10),
                    ],
                  TextField(
                    key: const ValueKey('server-url'),
                    controller: _url,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.go,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _connect(),
                    decoration: InputDecoration(
                      labelText: tr(_scan ? 'ที่อยู่จาก QR' : 'ที่อยู่เซิร์ฟเวอร์'),
                      hintText: tr('crm.yourcompany.com'),
                      prefixIcon: const Icon(NxI.link),
                      suffixIcon: _url.text.isEmpty || _busy
                          ? null
                          : IconButton(
                              key: const ValueKey('server-url-clear'),
                              tooltip: tr('ล้างช่อง'),
                              icon: const Icon(NxI.x),
                              onPressed: () => setState(() {
                                _url.clear();
                                _error = null;
                                _scanLocked = false;
                              }),
                            ),
                      filled: true,
                      errorText: trn(_error),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(NxI.shieldCheck, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(tr('แอปตรวจสอบก่อนว่าเป็นระบบ MOAI NEXT จริง'),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: NxHeroCta(label: 'เชื่อมต่อ', busy: _busy, onPressed: _busy ? null : () => _connect()),
            ),
          ],
        ),
      ),
    );
  }
}
