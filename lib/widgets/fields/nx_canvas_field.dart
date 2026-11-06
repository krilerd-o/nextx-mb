import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'nx_field_chrome.dart';

class NxCanvasField extends StatefulWidget {
  const NxCanvasField({
    super.key,
    this.value,
    this.onChanged,
    this.signature = false,
    this.enabled = true,
    this.uploadPng,
  });

  final String? value;
  final ValueChanged<String>? onChanged;
  final bool signature;
  final bool enabled;
  final Future<String?> Function(List<int> bytes, String filename)? uploadPng;

  @override
  State<NxCanvasField> createState() => _NxCanvasFieldState();
}

class _NxCanvasFieldState extends State<NxCanvasField> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  final _paintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _strokes.addAll(_decode(widget.value));
  }

  List<List<Offset>> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    if (raw.startsWith('http') || raw.startsWith('{') == false && raw.contains('/')) {
      return [];
    }
    try {
      final j = jsonDecode(raw);
      final strokes = j is Map ? j['strokes'] : j;
      if (strokes is! List) return [];
      return [
        for (final s in strokes)
          if (s is List)
            [
              for (final p in s)
                if (p is List && p.length >= 2)
                  Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            ],
      ];
    } catch (_) {
      return [];
    }
  }

  String _encode() {
    return jsonEncode({
      'strokes': [
        for (final s in _strokes)
          [
            for (final p in s) [p.dx, p.dy],
          ],
      ],
    });
  }

  Future<void> _commit() async {
    if (_strokes.isEmpty) {
      widget.onChanged?.call('');
      return;
    }
    widget.onChanged?.call(_encode());
    final upload = widget.uploadPng;
    if (upload == null) return;
    final bytes = await _exportPng();
    if (bytes == null) return;
    final name = widget.signature ? 'signature.png' : 'drawing.png';
    final url = await upload(bytes, name);
    if (url != null && url.isNotEmpty) {
      widget.onChanged?.call(url);
    }
  }

  Future<Uint8List?> _exportPng() async {
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? Size(320, widget.signature ? 140 : 200);
    if (size.width <= 0 || size.height <= 0) return null;
    final scheme = Theme.of(context).colorScheme;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = scheme.surface);
    _GridPainter(
      strokes: _strokes,
      color: scheme.onSurface,
      grid: scheme.outline.withValues(alpha: 0.25),
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final storedUrl = widget.value != null &&
        (widget.value!.startsWith('http') || widget.value!.startsWith('/'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (storedUrl)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.value!,
                height: 72,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        Container(
          key: _paintKey,
          height: widget.signature ? 140 : 200,
          decoration: NxFieldStyle.box(context),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            onPanStart: widget.enabled
                ? (d) {
                    setState(() {
                      _current = [d.localPosition];
                      _strokes.add(_current);
                    });
                  }
                : null,
            onPanUpdate: widget.enabled
                ? (d) {
                    setState(() => _current.add(d.localPosition));
                  }
                : null,
            onPanEnd: widget.enabled
                ? (_) {
                    _current = [];
                    _commit();
                  }
                : null,
            child: CustomPaint(
              painter: _GridPainter(
                strokes: [
                  ..._strokes,
                  if (_current.isNotEmpty) _current,
                ],
                color: scheme.onSurface,
                grid: scheme.outline.withValues(alpha: 0.25),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.enabled
                ? () {
                    setState(_strokes.clear);
                    _commit();
                  }
                : null,
            child: const Text('ล้าง'),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.strokes, required this.color, required this.grid});
  final List<List<Offset>> strokes;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    const step = 16.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.length == 1) {
          canvas.drawPoints(ui.PointMode.points, stroke, paint..strokeWidth = 3);
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}
