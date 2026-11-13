import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_icons.dart';
import 'doc_email_sheet.dart';
import 'document_preview.dart';

/// "เอกสาร" tab of a quotation / job: the document the web serves — the
/// BIRT report of the record's template (Template-1 / Template-2 chosen per
/// Business / Package when the record was created) — shown first, full
/// width; tap a page for full-screen zoom. Then download / share / print /
/// e-mail, and the e-mails sent from the document.
class RecordDocumentTab extends StatefulWidget {
  const RecordDocumentTab({super.key, required this.module, required this.row, this.canEmail = false});

  /// 'quotation' | 'job'
  final String module;
  final Map<String, dynamic> row;

  /// The user may send the document (row is editable for them; the server checks too).
  final bool canEmail;

  /// Bytes of recently opened documents, so switching tabs does not rebuild
  /// the report each time (key changes when the record is saved).
  static final Map<String, List<int>> _memo = {};

  static void clearCache() => _memo.clear();

  @override
  State<RecordDocumentTab> createState() => _RecordDocumentTabState();
}

class _RecordDocumentTabState extends State<RecordDocumentTab> {
  late final DocumentSource _src = _source();
  List<int>? _bytes;
  DocVariant? _shown;
  final List<ui.Image> _pages = [];
  bool _loading = true;
  bool _rendering = false;
  Object? _error;
  int _token = 0;
  StreamSubscription<ui.Image>? _sub;
  String? _busy;

  /// Draft document → DRAFT over the template pages, like the web.
  bool _draft = false;

  List<Map<String, dynamic>>? _log;
  bool _logFailed = false;

  bool get _isJob => widget.module == 'job';
  String get _id => strId(widget.row['id']);
  ApiClient get _api => context.read<AppConfig>().apiClient;
  String _memoKey(DocVariant v) => '${widget.module}:$_id:${widget.row['modifiedtime'] ?? ''}:${v.id}';

  DocumentSource _source() => _isJob ? jobDocumentSource(widget.row) : quotationDocumentSource(widget.row);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      _loadLog();
      _refine();
      _checkDraft();
    });
  }

  Future<void> _checkDraft() async {
    final fn = _src.draftWatermark;
    if (fn == null) return;
    try {
      final d = await fn(_api);
      if (mounted && d != _draft) setState(() => _draft = d);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final p in _pages) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _refine() async {
    final r = _src.refine;
    if (r == null) return;
    try {
      final next = await r(_api);
      if (next != null && mounted) setState(() => _src.templateLabel = next.templateLabel ?? _src.templateLabel);
    } catch (_) {}
  }

  DocVariant? _variant(String id) => _src.variants.where((v) => v.id == id).firstOrNull;

  Future<void> _load({bool fallback = false, bool fresh = false}) async {
    final token = ++_token;
    final main = _src.variants.first;
    final v = fallback ? (_variant(main.fallback ?? '') ?? main) : main;
    _sub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    final key = _memoKey(v);
    if (fresh) RecordDocumentTab._memo.remove(key);
    try {
      var b = RecordDocumentTab._memo[key];
      if (b == null) {
        b = await v.fetch(_api);
        if (!looksLikePdf(b)) throw StateError(tr('เซิร์ฟเวอร์ไม่ได้ส่งไฟล์ PDF กลับมา'));
        if (RecordDocumentTab._memo.length > 6) RecordDocumentTab._memo.remove(RecordDocumentTab._memo.keys.first);
        RecordDocumentTab._memo[key] = b;
      }
      if (token != _token || !mounted) return;
      setState(() {
        _bytes = b;
        _shown = v;
        _loading = false;
      });
      _render(b, token);
    } catch (e) {
      if (token != _token || !mounted) return;
      for (final p in _pages) {
        p.dispose();
      }
      setState(() {
        _pages.clear();
        _bytes = null;
        _shown = null;
        _error = e;
        _loading = false;
      });
    }
  }

  void _render(List<int> bytes, int token) {
    final old = List<ui.Image>.of(_pages);
    setState(() {
      _pages.clear();
      _rendering = true;
    });
    for (final p in old) {
      p.dispose();
    }
    final mq = MediaQuery.of(context);
    final dpi = (mq.size.width * mq.devicePixelRatio * 1.4).clamp(800.0, 1500.0) / 8.27; // A4 width in inches
    _sub = renderDocumentPages(Uint8List.fromList(bytes), dpi).listen(
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

  Future<void> _loadLog() async {
    try {
      final l = await _api.getDocEmailLog(widget.module, _id);
      if (mounted) setState(() => _log = l);
    } catch (_) {
      if (mounted) setState(() => _logFailed = true);
    }
  }

  String get _fileName => _shown == null ? '${_src.fileBase}.pdf' : docFileName(_src, _shown!);

  Future<void> _act(String what, Future<void> Function(List<int> b) fn) async {
    final b = _bytes;
    if (b == null || _busy != null) return;
    setState(() => _busy = what);
    try {
      await fn(b);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(docErrorText(e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _download() => _act('download', (b) async {
    final path = await (DocPreviewHooks.save ?? savePdfToDevice)(b, _fileName);
    if (path == null || !mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('บันทึกแล้ว')} · $_fileName')));
  });

  Future<void> _share() => _act('share', (b) => (DocPreviewHooks.share ?? sharePdfBytes)(b, _fileName));

  Future<void> _print() => _act('print', (b) => printDocumentBytes(b, _fileName));

  Future<void> _email({Map<String, dynamic>? prefill}) async {
    final sent = await showDocEmailSheet(
      context,
      kind: widget.module,
      id: _id,
      docNo: '${widget.row[_isJob ? 'job_no' : 'quotation_no'] ?? ''}',
      // Size of the template document the server will attach (not the fallback).
      pdfSize: _shown?.birt == true ? _bytes?.length : null,
      prefill: prefill,
      // Tap the auto attachment → the same document, no second report build.
      document: _source()..templateLabel = _src.templateLabel,
      prefetched: _bytes == null || _shown == null ? null : {_shown!.id: _bytes!},
    );
    if (sent && mounted) _loadLog();
  }

  void _fullScreen() {
    final b = _bytes, v = _shown;
    openDocumentPreview(
      context,
      _source()..templateLabel = _src.templateLabel,
      prefetched: b == null || v == null ? null : {v.id: b},
      onEmail: widget.canEmail ? _email : null,
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ready = _bytes != null && !_loading;
    final no = '${widget.row[_isJob ? 'job_no' : 'quotation_no'] ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(NxI.fileText, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                tr(_isJob ? 'รายงานใบสั่งงาน' : 'รายงานใบเสนอราคา'),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                [if (no.isNotEmpty) no, if (_src.templateLabel != null) _src.templateLabel!].join(' · '),
                key: const ValueKey('doc-tab-template'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ]),
          ),
          IconButton(key: const ValueKey('doc-tab-full'), tooltip: tr('เต็มจอ'), onPressed: ready ? _fullScreen : null, icon: const Icon(NxI.cornersOut)),
          IconButton(
            key: const ValueKey('doc-tab-reload'),
            tooltip: tr('โหลดใหม่'),
            onPressed: _loading ? null : () => _load(fresh: true, fallback: _shown != null && !_shown!.birt),
            icon: const Icon(NxI.arrowClockwise),
          ),
        ]),
        const SizedBox(height: 10),
        _actions(theme, cs, ready),
        if (_shown != null && !_shown!.birt)
          Container(
            key: const ValueKey('doc-tab-fallback-notice'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(NxI.info, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('แสดงแบบสำรอง (ไม่ใช่เทมเพลตเอกสาร) เพราะเซิร์ฟเวอร์รายงาน (BIRT) สร้างเอกสารไม่ได้'), style: theme.textTheme.bodySmall)),
              TextButton(onPressed: () => _load(), child: Text(tr('ลองเทมเพลตอีกครั้ง'))),
            ]),
          ),
        const SizedBox(height: 12),
        _viewer(theme, cs),
        const SizedBox(height: 18),
        _history(theme, cs),
      ],
    );
  }

  Widget _actions(ThemeData theme, ColorScheme cs, bool ready) {
    Widget action(String key, IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _busy == key.replaceFirst('doc-tab-', '')
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, size: 21, color: onTap == null ? cs.outline : cs.primary),
              const SizedBox(height: 4),
              Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: onTap == null ? cs.outline : null)),
            ]),
          ),
        ),
      ),
    );
    const gap = SizedBox(width: 8);
    return Row(children: [
      action('doc-tab-download', NxI.downloadSimple, 'ดาวน์โหลด', ready ? _download : null),
      gap,
      action('doc-tab-share', NxI.shareNetwork, 'แชร์', ready ? _share : null),
      gap,
      action('doc-tab-print', NxI.printer, 'พิมพ์', ready ? _print : null),
      if (widget.canEmail) ...[
        gap,
        action('doc-tab-email', NxI.envelope, 'ส่งอีเมล', () => _email()),
      ],
    ]);
  }

  Widget _viewer(ThemeData theme, ColorScheme cs) {
    if (_error != null && _pages.isEmpty) {
      final fb = _src.variants.first.fallback != null;
      return Container(
        key: const ValueKey('doc-tab-error'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant)),
        child: Column(children: [
          Icon(NxI.warning, size: 36, color: cs.error),
          const SizedBox(height: 10),
          Text(tr('สร้างเอกสารตามเทมเพลตไม่สำเร็จ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(docErrorText(_error!), key: const ValueKey('doc-tab-error-text'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              key: const ValueKey('doc-tab-retry'),
              onPressed: () => _load(fresh: true),
              icon: const Icon(NxI.arrowClockwise, size: 18),
              label: Text(tr('ลองใหม่')),
            ),
            if (fb)
              OutlinedButton.icon(
                key: const ValueKey('doc-tab-fallback'),
                onPressed: () => _load(fallback: true),
                icon: const Icon(NxI.file, size: 18),
                label: Text(tr('ดูแบบสำรอง')),
              ),
          ]),
        ]),
      );
    }
    if (_loading || (_pages.isEmpty && _rendering)) {
      return Container(
        key: const ValueKey('doc-tab-loading'),
        height: 420,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(blurRadius: 14, color: Color(0x1F000000))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(height: 14),
          Text(tr(_loading ? 'กำลังสร้างเอกสารตามเทมเพลต…' : 'กำลังแสดงหน้าเอกสาร…'), style: theme.textTheme.bodyMedium),
        ]),
      );
    }
    return Column(children: [
      for (var i = 0; i < _pages.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        GestureDetector(
          key: ValueKey('doc-tab-page-$i'),
          onTap: _fullScreen,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(blurRadius: 14, offset: Offset(0, 3), color: Color(0x26000000))]),
            child: docPageImage(_pages[i], draft: _draft && _shown?.birt == true),
          ),
        ),
      ],
      if (_rendering) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2.4)),
      if (_pages.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${_pages.length} ${tr('หน้า')} · ${tr('แตะหน้าเอกสารเพื่อซูม')}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
    ]);
  }

  Widget _history(ThemeData theme, ColorScheme cs) {
    final items = _log ?? const <Map<String, dynamic>>[];
    if (_logFailed || items.isEmpty) return const SizedBox.shrink();
    String fmt(Object? v) {
      final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
      if (d == null) return '';
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.day}/${d.month}/${d.year + (L10n.isEn ? 0 : 543)} ${two(d.hour)}:${two(d.minute)}';
    }

    List<String> strs(Object? v) => v is List ? [for (final e in v) '$e'] : const [];
    const status = {'sent': 'ส่งแล้ว', 'queued': 'เข้าคิว', 'failed': 'ไม่สำเร็จ'};
    return Column(
      key: const ValueKey('doc-tab-email-log'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(NxI.envelope, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Text(tr('อีเมลที่ส่งแล้ว'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        for (final m in items.take(5))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${m['subject'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (m['status'] == 'failed' ? cs.error : Colors.green).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(tr(status[m['status']] ?? '${m['status'] ?? ''}'), style: theme.textTheme.labelSmall),
                ),
              ]),
              const SizedBox(height: 2),
              Text('${tr('ถึง')} ${[...strs(m['to']), ...strs(m['cc'])].join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              Row(children: [
                Expanded(
                  child: Text(
                    [fmt(m['sent_at']), if ((m['sent_by'] as Map?)?['name'] != null && '${(m['sent_by'] as Map)['name']}'.isNotEmpty) '${(m['sent_by'] as Map)['name']}', if ((m['attachments'] as List?)?.isNotEmpty == true) '📎 ${(m['attachments'] as List).length}']
                        .where((x) => x.isNotEmpty)
                        .join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                if (widget.canEmail)
                  TextButton(key: ValueKey('doc-tab-resend-${m['id']}'), onPressed: () => _email(prefill: m), child: Text(tr('ส่งซ้ำ'))),
              ]),
            ]),
          ),
      ],
    );
  }
}
