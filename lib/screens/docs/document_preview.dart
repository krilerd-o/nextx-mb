import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../journey/job_journey.dart' show showPublicLinkSheet;

/// One way to produce the document, e.g. "ตามเทมเพลต · ไทย · สี".
class DocVariant {
  const DocVariant({required this.id, required this.label, required this.fetch, this.fallback, this.birt = true, this.suffix = ''});

  final String id;
  final String label;
  final Future<List<int>> Function(ApiClient api) fetch;

  /// Variant to show instead when this one cannot be built (e.g. the BIRT
  /// report server is down) — the user is told which one they see.
  final String? fallback;
  final bool birt;

  /// Added to the file name (`-th-bw`, `-standard`).
  final String suffix;
}

/// What to preview: title, file name and the variants (first = default).
class DocumentSource {
  DocumentSource({
    required this.title,
    required this.fileBase,
    required this.variants,
    this.subtitle,
    this.templateLabel,
    this.refine,
    this.publicLink,
  });

  final String title;
  final String? subtitle;
  final String fileBase;
  List<DocVariant> variants;
  String? templateLabel;

  /// Loads the template's real options (languages × colours) after opening.
  final Future<({List<DocVariant> variants, String? templateLabel})?> Function(ApiClient api)? refine;

  /// Creates the customer link (job / quotation).
  final Future<Map<String, dynamic>> Function(ApiClient api)? publicLink;
}

/// Hooks for tests (no PDF engine / file dialogs in widget tests).
class DocPreviewHooks {
  static Stream<ui.Image> Function(Uint8List bytes, double dpi)? render;
  static Future<String?> Function(List<int> bytes, String name)? save;
  static Future<void> Function(List<int> bytes, String name)? print;
  static Future<void> Function(List<int> bytes, String name)? share;
}

Stream<ui.Image> _renderPages(Uint8List bytes, double dpi) {
  final hook = DocPreviewHooks.render;
  if (hook != null) return hook(bytes, dpi);
  return Printing.raster(bytes, dpi: dpi).asyncMap((r) => r.toImage());
}

bool _looksLikePdf(List<int> b) => b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46; // %PDF

// ---------------------------------------------------------------- sources

DocumentSource jobDocumentSource(Map<String, dynamic> row) {
  final id = strId(row['id']);
  final no = '${row['job_no'] ?? 'job-$id'}';
  final tk = '${row['template_key'] ?? ''}'.toLowerCase();
  return DocumentSource(
    title: tr('ใบสั่งงาน'),
    subtitle: no,
    fileBase: 'job-$no',
    templateLabel: tk == 'template2' ? tr('เทมเพลต 2') : tr('เทมเพลต 1'),
    variants: [
      DocVariant(id: 'birt', label: tr('ตามเทมเพลต'), fetch: (api) => api.getJobBirtPdf(id), fallback: 'std'),
      DocVariant(id: 'std', label: tr('แบบมาตรฐาน'), birt: false, suffix: '-standard', fetch: (api) => api.getJobStandardPdf(id)),
    ],
    publicLink: (api) => api.jobPublicLink(id),
  );
}

DocumentSource inspectionDocumentSource(String id, {String? no}) => DocumentSource(
  title: tr('ใบตรวจรับ'),
  subtitle: no,
  fileBase: 'inspection-${no ?? id}',
  variants: [
    DocVariant(id: 'birt', label: tr('ตามเทมเพลต'), fetch: (api) => api.getInspectionBirtPdf(id), fallback: 'std'),
    DocVariant(id: 'std', label: tr('แบบมาตรฐาน'), birt: false, suffix: '-standard', fetch: (api) => api.getInspectionPdf(id)),
  ],
);

/// Quotation variants like the web: the template, then its languages ×
/// colours (from the template layout; th/en × color/bw when not set), then
/// the standard PDF.
List<DocVariant> quotationVariants(String id, String? template, {List<String>? langs, List<String>? colors}) {
  final ls = (langs == null || langs.isEmpty) ? const ['th', 'en'] : langs;
  final cs = (colors == null || colors.isEmpty) ? const ['color', 'bw'] : colors;
  String langLabel(String l) => switch (l) {
    'th' => tr('ไทย'),
    'en' => 'English',
    _ => l.toUpperCase(),
  };
  String colorLabel(String c) => switch (c) {
    'color' => tr('สี'),
    'bw' => tr('ขาวดำ'),
    _ => c,
  };
  return [
    DocVariant(id: 'birt', label: tr('ตามเทมเพลต'), fetch: (api) => api.getQuotationBirtPdf(id, template: template), fallback: 'std'),
    for (final l in ls)
      for (final c in cs) ...[
        DocVariant(
          id: 'birt-$l-$c',
          label: '${langLabel(l)} · ${colorLabel(c)}',
          suffix: '-$l${c == 'bw' ? '-bw' : ''}',
          fetch: (api) => api.getQuotationBirtPdf(id, lang: l, color: c, template: template),
          fallback: 'std-$l-$c',
        ),
      ],
    DocVariant(id: 'std', label: tr('แบบมาตรฐาน'), birt: false, suffix: '-standard', fetch: (api) => api.getQuotationStandardPdf(id)),
    // Hidden fallbacks (standard PDF in the same language / colour).
    for (final l in ls)
      for (final c in cs)
        DocVariant(id: 'std-$l-$c', label: '', birt: false, suffix: '-$l${c == 'bw' ? '-bw' : ''}-standard', fetch: (api) => api.getQuotationStandardPdf(id, lang: l, color: c)),
  ];
}

DocumentSource quotationDocumentSource(Map<String, dynamic> row) {
  final id = strId(row['id']);
  final no = '${row['quotation_no'] ?? 'quotation-$id'}';
  final tk = row['template_key']?.toString();
  final template = tk == null || tk.isEmpty ? null : tk;
  final templateId = row['template_id'];
  return DocumentSource(
    title: tr('ใบเสนอราคา'),
    subtitle: no,
    fileBase: no,
    variants: quotationVariants(id, template),
    publicLink: (api) => api.quotationPublicLink(id),
    refine: templateId == null || '$templateId'.isEmpty
        ? null
        : (api) async {
            final list = await api.getQuotationTemplates();
            final t = list.where((x) => '${x['id']}' == '$templateId').firstOrNull;
            if (t == null) return null;
            final lj = t['layout_json'] is Map ? Map<String, dynamic>.from(t['layout_json'] as Map) : const <String, dynamic>{};
            List<String>? strs(Object? v) => v is List ? [for (final e in v) '$e'.toLowerCase()] : null;
            return (variants: quotationVariants(id, template, langs: strs(lj['variants']), colors: strs(lj['colors'])), templateLabel: t['name']?.toString());
          },
  );
}

Future<void> openDocumentPreview(BuildContext context, DocumentSource source) =>
    nxPush<void>(context, DocumentPreviewScreen(source: source));

/// Opens the document of a record (job / quotation / inspection).
Future<void> openRecordDocument(BuildContext context, String module, Map<String, dynamic> row) {
  final source = switch (module) {
    'job' => jobDocumentSource(row),
    'inspection' => inspectionDocumentSource(strId(row['id']), no: row['inspection_no']?.toString()),
    _ => quotationDocumentSource(row),
  };
  return openDocumentPreview(context, source);
}

// ---------------------------------------------------------------- screen

class DocumentPreviewScreen extends StatefulWidget {
  const DocumentPreviewScreen({super.key, required this.source});
  final DocumentSource source;

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> with SingleTickerProviderStateMixin {
  late String _variantId = widget.source.variants.first.id;
  final Map<String, List<int>> _cache = {};

  /// The variant actually shown (differs when we fell back).
  String? _shownId;
  List<int>? _bytes;
  final List<ui.Image> _pages = [];
  bool _loading = true;
  bool _rendering = false;
  Object? _error;
  String? _notice;
  int _token = 0;
  StreamSubscription<ui.Image>? _renderSub;

  final _tc = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  Animation<Matrix4>? _tween;
  Offset _tapAt = Offset.zero;
  Size _viewport = Size.zero;
  List<double> _pageTops = const [];
  double _contentH = 0;
  int _page = 0;
  double _scale = 1;

  static const _gap = 14.0;
  static const _pad = 14.0;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  DocVariant _variant(String id) => widget.source.variants.firstWhere((v) => v.id == id, orElse: () => widget.source.variants.first);

  List<DocVariant> get _choices => [for (final v in widget.source.variants) if (v.label.isNotEmpty) v];

  String get _fileName => '${widget.source.fileBase}${_variant(_shownId ?? _variantId).suffix}.pdf'.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
    _anim.addListener(() {
      final t = _tween;
      if (t != null) _tc.value = t.value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _refine();
    });
  }

  @override
  void dispose() {
    _renderSub?.cancel();
    for (final p in _pages) {
      p.dispose();
    }
    _tc.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _refine() async {
    final r = widget.source.refine;
    if (r == null) return;
    try {
      final next = await r(_api);
      if (next == null || !mounted) return;
      setState(() {
        widget.source.variants = next.variants;
        widget.source.templateLabel = next.templateLabel ?? widget.source.templateLabel;
        if (!next.variants.any((v) => v.id == _variantId)) _variantId = next.variants.first.id;
      });
    } catch (_) {
      // Keep the default options.
    }
  }

  Future<List<int>> _fetch(DocVariant v) async {
    final hit = _cache[v.id];
    if (hit != null) return hit;
    final b = await v.fetch(_api);
    if (!_looksLikePdf(b)) throw StateError(tr('เซิร์ฟเวอร์ไม่ได้ส่งไฟล์ PDF กลับมา'));
    _cache[v.id] = b;
    return b;
  }

  Future<void> _load() async {
    final token = ++_token;
    final want = _variant(_variantId);
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    List<int>? bytes;
    String shown = want.id;
    String? notice;
    try {
      bytes = await _fetch(want);
    } catch (e) {
      final fb = want.fallback;
      if (fb != null) {
        try {
          bytes = await _fetch(_variant(fb));
          shown = fb;
          notice = tr('เทมเพลตเอกสาร (BIRT) ยังสร้างไม่ได้ตอนนี้ — แสดงแบบมาตรฐานแทน');
        } catch (_) {
          if (token == _token && mounted) setState(() => _error = e);
        }
      } else if (token == _token && mounted) {
        setState(() => _error = e);
      }
    }
    if (token != _token || !mounted) return;
    if (bytes == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _bytes = bytes;
      _shownId = shown;
      _notice = notice;
      _loading = false;
    });
    _render(bytes, token);
  }

  void _render(List<int> bytes, int token) {
    _renderSub?.cancel();
    final old = List<ui.Image>.of(_pages);
    setState(() {
      _pages.clear();
      _rendering = true;
      _page = 0;
    });
    for (final p in old) {
      p.dispose();
    }
    _tc.value = Matrix4.identity();
    final mq = MediaQuery.of(context);
    // Sharp at 2× zoom, capped so big documents stay light on memory.
    final targetPx = (mq.size.width * mq.devicePixelRatio * 1.6).clamp(900.0, 1600.0);
    final dpi = targetPx / 8.27; // A4 width in inches
    _renderSub = _renderPages(Uint8List.fromList(bytes), dpi).listen(
      (img) {
        if (token != _token || !mounted) {
          img.dispose();
          return;
        }
        setState(() => _pages.add(img));
      },
      onError: (Object e) {
        if (token == _token && mounted) {
          setState(() {
            _rendering = false;
            if (_pages.isEmpty) _error = e;
          });
        }
      },
      onDone: () {
        if (token == _token && mounted) setState(() => _rendering = false);
      },
    );
  }

  void _pick(String id) {
    if (id == _variantId) return;
    HapticFeedback.selectionClick();
    setState(() => _variantId = id);
    _load();
  }

  // ------------------------------------------------------------- zoom/pages

  void _onTransform() {
    final m = _tc.value;
    final s = m.getMaxScaleOnAxis();
    final ty = -m.getTranslation().y;
    final center = (ty + _viewport.height / 3) / s;
    var p = 0;
    for (var i = 0; i < _pageTops.length; i++) {
      if (center >= _pageTops[i]) p = i;
    }
    if (p != _page || (s - _scale).abs() > 0.01) {
      setState(() {
        _page = p;
        _scale = s;
      });
    }
  }

  Matrix4 _matrix(double s, double tx, double ty) {
    final maxX = 0.0, minX = _viewport.width - _viewport.width * s;
    final minY = (_viewport.height - _contentH * s).clamp(double.negativeInfinity, 0.0);
    return Matrix4.translationValues(tx.clamp(minX, maxX), ty.clamp(minY, 0.0), 0)..multiply(Matrix4.diagonal3Values(s, s, 1));
  }

  void _animateTo(Matrix4 to) {
    _tween = Matrix4Tween(begin: _tc.value, end: to).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  void _zoomAt(Offset p, double s) {
    final m = _tc.value;
    final cur = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    final cx = (p.dx - t.x) / cur, cy = (p.dy - t.y) / cur;
    _animateTo(_matrix(s, p.dx - cx * s, p.dy - cy * s));
  }

  void _toggleZoom() {
    HapticFeedback.lightImpact();
    _zoomAt(_tapAt, _scale > 1.05 ? 1.0 : 2.5);
  }

  void _zoomBy(double f) => _zoomAt(Offset(_viewport.width / 2, _viewport.height / 2), (_scale * f).clamp(1.0, 6.0));

  void _goPage(int i) {
    if (i < 0 || i >= _pageTops.length) return;
    final s = _scale;
    final tx = _tc.value.getTranslation().x;
    _animateTo(_matrix(s, tx, -(_pageTops[i] - _pad / 2) * s));
  }

  // ---------------------------------------------------------------- actions

  Future<void> _run(Future<void> Function(List<int> b) fn) async {
    final b = _bytes;
    if (b == null) return;
    try {
      await fn(b);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _download() => _run((b) async {
    final save = DocPreviewHooks.save ?? savePdfToDevice;
    final path = await save(b, _fileName);
    if (!mounted || path == null) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('บันทึกแล้ว')} · $_fileName')));
  });

  Future<void> _share() => _run((b) => (DocPreviewHooks.share ?? sharePdfBytes)(b, _fileName));

  Future<void> _print() => _run((b) async {
    final hook = DocPreviewHooks.print;
    if (hook != null) return hook(b, _fileName);
    await Printing.layoutPdf(name: _fileName, onLayout: (_) async => Uint8List.fromList(b));
  });

  Future<void> _openExternal() => _run((b) => openPdfBytes(b, _fileName));

  Future<void> _customerLink() async {
    final fn = widget.source.publicLink;
    if (fn == null) return;
    final api = _api;
    try {
      final r = await fn(api);
      if (!mounted) return;
      await showPublicLinkSheet(context, api.absoluteUrl('${r['path'] ?? ''}'), pdf: r['pdf_path'] == null ? null : api.absoluteUrl('${r['pdf_path']}'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  void _thumbnails() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.62),
            itemCount: _pages.length,
            itemBuilder: (_, i) => InkWell(
              key: ValueKey('doc-thumb-$i'),
              onTap: () {
                Navigator.pop(ctx);
                _goPage(i);
              },
              child: Column(children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: i == _page ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.outlineVariant, width: i == _page ? 2 : 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RawImage(image: _pages[i], fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${i + 1}', style: Theme.of(ctx).textTheme.labelMedium),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final src = widget.source;
    final shown = _variant(_shownId ?? _variantId);
    final ready = _bytes != null && !_loading;
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF15171C) : const Color(0xFFE9EBEF),
      appBar: NxAppHeader(
        title: src.title,
        subtitle: [src.subtitle, if (src.templateLabel != null) src.templateLabel].whereType<String>().join(' · '),
        actions: [
          IconButton(tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork), onPressed: ready ? _share : null),
        ],
        menu: [
          if (ready) NxHeaderMenuItem(label: 'เปิดด้วยแอปอื่น', icon: NxI.arrowSquareOut, onTap: _openExternal),
          if (src.publicLink != null) NxHeaderMenuItem(label: 'ลิงก์ให้ลูกค้า', icon: NxI.link, onTap: _customerLink),
          NxHeaderMenuItem(label: 'โหลดใหม่', icon: NxI.arrowClockwise, onTap: () {
            _cache.clear();
            _load();
          }),
        ],
      ),
      body: Column(
        children: [
          if (_choices.length > 1)
            SizedBox(
              height: 52,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(children: [
                  for (final v in _choices)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('doc-variant-${v.id}'),
                        avatar: Icon(v.birt ? NxI.fileText : NxI.file, size: 16),
                        label: Text(v.label),
                        selected: v.id == _variantId,
                        onSelected: (_) => _pick(v.id),
                      ),
                    ),
                ]),
              ),
            ),
          if (_notice != null)
            Container(
              key: const ValueKey('doc-fallback-notice'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(NxI.info, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_notice!, style: theme.textTheme.bodySmall)),
              ]),
            ),
          Expanded(child: _viewer(theme)),
          _bottomBar(theme, cs, ready, shown),
        ],
      ),
    );
  }

  Widget _viewer(ThemeData theme) {
    if (_error != null && _pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(NxI.warning, size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(tr('เปิดเอกสารไม่สำเร็จ'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_error is StateError ? (_error as StateError).message : tr(formatApiError(_error!)), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              FilledButton.icon(key: const ValueKey('doc-retry'), onPressed: () {
                _cache.remove(_variantId);
                _load();
              }, icon: const Icon(NxI.arrowClockwise, size: 18), label: Text(tr('ลองใหม่'))),
              if (_bytes != null) OutlinedButton.icon(onPressed: _openExternal, icon: const Icon(NxI.arrowSquareOut, size: 18), label: Text(tr('เปิดด้วยแอปอื่น'))),
            ]),
          ]),
        ),
      );
    }
    if (_loading || (_pages.isEmpty && _rendering)) {
      return Center(
        key: const ValueKey('doc-loading'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 150,
            height: 212,
            decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(blurRadius: 18, color: Color(0x22000000))]),
            alignment: Alignment.center,
            child: const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
          ),
          const SizedBox(height: 16),
          Text(_loading ? tr('กำลังสร้างเอกสารตามเทมเพลต…') : tr('กำลังแสดงหน้าเอกสาร…'), style: theme.textTheme.bodyMedium),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      _viewport = Size(c.maxWidth, c.maxHeight);
      final pageW = c.maxWidth - _pad * 2;
      final tops = <double>[];
      var y = _pad;
      for (final p in _pages) {
        tops.add(y);
        y += pageW * p.height / p.width + _gap;
      }
      _pageTops = tops;
      _contentH = y - _gap + _pad + (_rendering ? 80 : 0);
      return GestureDetector(
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          key: const ValueKey('doc-viewer'),
          transformationController: _tc,
          constrained: false,
          minScale: 1,
          maxScale: 6,
          boundaryMargin: EdgeInsets.zero,
          child: SizedBox(
            width: c.maxWidth,
            child: Padding(
              padding: const EdgeInsets.all(_pad),
              child: Column(children: [
                for (var i = 0; i < _pages.length; i++) ...[
                  if (i > 0) const SizedBox(height: _gap),
                  Container(
                    key: ValueKey('doc-page-$i'),
                    decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(blurRadius: 14, offset: Offset(0, 3), color: Color(0x26000000))]),
                    child: AspectRatio(aspectRatio: _pages[i].width / _pages[i].height, child: RawImage(image: _pages[i], fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                  ),
                ],
                if (_rendering) const Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(strokeWidth: 2.4)),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _bottomBar(ThemeData theme, ColorScheme cs, bool ready, DocVariant shown) {
    final n = _pages.length;
    Widget action(String key, IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: onTap == null ? cs.outline : cs.onSurface),
            const SizedBox(height: 3),
            Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: onTap == null ? cs.outline : null)),
          ]),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              ActionChip(
                key: const ValueKey('doc-pages'),
                avatar: const Icon(NxI.squaresFour, size: 16),
                label: Text(n == 0 ? '—' : '${tr('หน้า')} ${_page + 1}/$n'),
                onPressed: n > 1 ? _thumbnails : null,
              ),
              const Spacer(),
              IconButton(tooltip: tr('ย่อ'), onPressed: n == 0 || _scale <= 1.01 ? null : () => _zoomBy(1 / 1.5), icon: const Icon(NxI.magnifyingGlassMinus)),
              GestureDetector(
                onTap: _scale > 1.01 ? () => _animateTo(_matrix(1, 0, _tc.value.getTranslation().y / _scale)) : null,
                child: SizedBox(width: 52, child: Text('${(_scale * 100).round()}%', key: const ValueKey('doc-zoom'), textAlign: TextAlign.center, style: theme.textTheme.labelLarge)),
              ),
              IconButton(tooltip: tr('ขยาย'), onPressed: n == 0 || _scale >= 5.9 ? null : () => _zoomBy(1.5), icon: const Icon(NxI.magnifyingGlassPlus)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              action('doc-download', NxI.downloadSimple, 'ดาวน์โหลด', ready ? _download : null),
              action('doc-share', NxI.shareNetwork, 'แชร์', ready ? _share : null),
              action('doc-print', NxI.printer, 'พิมพ์', ready ? _print : null),
              action('doc-open', NxI.arrowSquareOut, 'แอปอื่น', ready ? _openExternal : null),
              if (widget.source.publicLink != null) action('doc-link', NxI.link, 'ลิงก์ลูกค้า', _customerLink),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// "เอกสาร" card for summary tabs: open the preview, or share / download
/// the default document straight away (template first, standard if needed).
class DocumentCard extends StatefulWidget {
  const DocumentCard({super.key, required this.source});
  final DocumentSource Function() source;

  @override
  State<DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<DocumentCard> {
  String? _busy;

  Future<void> _quick(String what) async {
    final src = widget.source();
    final api = context.read<AppConfig>().apiClient;
    setState(() => _busy = what);
    try {
      final v = src.variants.first;
      List<int> b;
      var used = v;
      try {
        b = await v.fetch(api);
        if (!_looksLikePdf(b)) throw StateError('not pdf');
      } catch (_) {
        final fb = v.fallback == null ? null : src.variants.where((x) => x.id == v.fallback).firstOrNull;
        if (fb == null) rethrow;
        b = await fb.fetch(api);
        used = fb;
      }
      final name = '${src.fileBase}${used.suffix}.pdf'.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
      if (what == 'share') {
        await (DocPreviewHooks.share ?? sharePdfBytes)(b, name);
      } else {
        final path = await (DocPreviewHooks.save ?? savePdfToDevice)(b, name);
        if (path != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('บันทึกแล้ว')} · $name')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final src = widget.source();
    Widget busyOr(String id, IconData icon) => _busy == id ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 20);
    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('doc-card'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => openDocumentPreview(context, widget.source()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Mini A4 page.
            Container(
              width: 46,
              height: 62,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x22000000))]),
              padding: const EdgeInsets.fromLTRB(6, 7, 6, 6),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 5, width: 20, color: cs.primary),
                const SizedBox(height: 5),
                for (final w in const [32.0, 26.0, 30.0, 18.0]) ...[Container(height: 3, width: w, color: const Color(0xFFD5D8DE)), const SizedBox(height: 4)],
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(src.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tr('ดูตัวอย่างตามเทมเพลต ซูมได้ · ดาวน์โหลด · พิมพ์'), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(key: const ValueKey('doc-card-share'), tooltip: tr('แชร์'), onPressed: _busy == null ? () => _quick('share') : null, icon: busyOr('share', NxI.shareNetwork)),
            IconButton(key: const ValueKey('doc-card-download'), tooltip: tr('ดาวน์โหลด'), onPressed: _busy == null ? () => _quick('download') : null, icon: busyOr('download', NxI.downloadSimple)),
          ]),
        ),
      ),
    );
  }
}
