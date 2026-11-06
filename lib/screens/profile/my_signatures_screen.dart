import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';

/// "ลายเซ็นของฉัน" — TH / EN signature used on quotations and documents
/// (`/api/me/signatures` + `POST /api/uploads/signature`).
class MySignaturesScreen extends StatefulWidget {
  const MySignaturesScreen({super.key});

  @override
  State<MySignaturesScreen> createState() => _MySignaturesScreenState();
}

class _MySignaturesScreenState extends State<MySignaturesScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  String? _busySlot;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.getMySignatures();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String? _url(String slot) {
    final own = _data?['upload_signature_$slot']?.toString();
    if (own == null || own.isEmpty) return null;
    final u = _data?[slot == 'th' ? 'signatureUrlTh' : 'signatureUrlEn']?.toString();
    return u == null || u.isEmpty ? null : _api.absoluteUrl(u);
  }

  Future<void> _save(String slot, List<int> bytes, String filename) async {
    setState(() => _busySlot = slot);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await _api.uploadSignatureImage(bytes, filename);
      await _api.saveMySignatures(th: slot == 'th' ? path : null, en: slot == 'en' ? path : null);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('บันทึกลายเซ็นแล้ว')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Future<void> _draw(String slot) async {
    final png = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const SignaturePadScreen()),
    );
    if (png != null && mounted) await _save(slot, png, 'signature_$slot.png');
  }

  Future<void> _pick(String slot) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 90);
    if (x == null || !mounted) return;
    await _save(slot, await x.readAsBytes(), x.name);
  }

  Future<void> _clear(String slot) async {
    setState(() => _busySlot = slot);
    try {
      await _api.saveMySignatures(clearTh: slot == 'th', clearEn: slot == 'en');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Widget _slot(String slot, String title) {
    final theme = Theme.of(context);
    final url = _url(slot);
    final busy = _busySlot == slot;
    return NxSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 12),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            alignment: Alignment.center,
            child: url == null
                ? Text('ยังไม่มีลายเซ็น', style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54))
                : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(NxI.image)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: _busySlot != null ? null : () => _draw(slot),
              icon: const Icon(NxI.pencilSimple, size: 18),
              label: const Text('เซ็นบนจอ'),
            ),
            OutlinedButton.icon(
              onPressed: _busySlot != null ? null : () => _pick(slot),
              icon: const Icon(NxI.image, size: 18),
              label: const Text('เลือกรูป'),
            ),
            if (url != null)
              TextButton(onPressed: _busySlot != null ? null : () => _clear(slot), child: const Text('ลบ')),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NxAppHeader(title: 'ลายเซ็นของฉัน'),
      body: _data == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(padding: const EdgeInsets.all(24), child: Text(formatApiError(_error!), textAlign: TextAlign.center)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('ใช้แสดงบนใบเสนอราคาและเอกสารที่ออกจากระบบ', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                _slot('th', 'ลายเซ็น (ภาษาไทย)'),
                const SizedBox(height: 12),
                _slot('en', 'Signature (English)'),
              ],
            ),
    );
  }
}

/// Full-screen pad; pops PNG bytes (transparent background, black ink).
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final _strokes = <List<Offset>>[];
  final _key = GlobalKey();
  bool _saving = false;

  Future<void> _done() async {
    if (_strokes.isEmpty) return;
    setState(() => _saving = true);
    final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final image = await boundary?.toImage(pixelRatio: 2);
    final data = await image?.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.of(context).pop(data?.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เซ็นชื่อ'),
        actions: [
          TextButton(onPressed: _strokes.isEmpty || _saving ? null : () => setState(_strokes.clear), child: const Text('ล้าง')),
          TextButton(onPressed: _strokes.isEmpty || _saving ? null : _done, child: const Text('บันทึก')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                  onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                  child: RepaintBoundary(
                    key: _key,
                    child: CustomPaint(painter: _InkPainter(_strokes), size: Size.infinite),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('เซ็นในกรอบด้านบน', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.5, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
