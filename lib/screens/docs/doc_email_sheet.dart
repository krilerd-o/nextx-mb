import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_rich_text_editor.dart';
import '../crm/entity_detail_parts.dart' show pickAttachments;
import 'doc_email_parts.dart';
import 'document_preview.dart';

export 'doc_email_parts.dart' show RecipientLine, parseRecipients;

const _recentKey = 'nextx.docCompose.recent';
const kDocEmailMaxFiles = 10;
const kDocEmailMaxFileMb = 15;

/// Test seams (no file dialogs in widget tests).
class DocEmailHooks {
  static Future<List<MultipartFile>> Function(BuildContext context)? pickFiles;
}

String fmtFileSize(int n) => n >= 1048576 ? '${(n / 1048576).toStringAsFixed(1)} MB' : '${(n / 1024).round().clamp(1, 1 << 30)} KB';

/// "ส่งอีเมล" for a quotation or job document — a mail composer like the
/// web's compose window: To / CC / BCC (chips + suggestions), subject, the
/// document PDF attached automatically (built by the server from the BIRT
/// template, like the web) plus extra files, and the rich-text message from
/// the business template.
/// Phone: full-screen page; tablet: a centered window (≤ 720 wide).
/// [kind] 'quotation' | 'job'. [pdfSize] = size of the document already
/// opened in the app (shown on the auto attachment). [prefill] = a sent
/// e-mail from the history (resend). [document] / [prefetched] = the
/// document to preview when the auto attachment is tapped. Returns true
/// when sent.
Future<bool> showDocEmailSheet(
  BuildContext context, {
  required String kind,
  required String id,
  String? docNo,
  int? pdfSize,
  Map<String, dynamic>? prefill,
  DocumentSource? document,
  Map<String, List<int>>? prefetched,
}) async {
  final page = DocEmailSheet(kind: kind, id: id, docNo: docNo, pdfSize: pdfSize, prefill: prefill, document: document, prefetched: prefetched);
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final bool? sent;
  if (wide) {
    sent = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 920),
          child: MediaQuery.removePadding(context: ctx, removeTop: true, removeBottom: true, removeLeft: true, removeRight: true, child: page),
        ),
      ),
    );
  } else {
    sent = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
  }
  return sent == true;
}

class DocEmailSheet extends StatefulWidget {
  const DocEmailSheet({super.key, required this.kind, required this.id, this.docNo, this.pdfSize, this.prefill, this.document, this.prefetched});
  final String kind;
  final String id;
  final String? docNo;
  final int? pdfSize;
  final Map<String, dynamic>? prefill;
  final DocumentSource? document;
  final Map<String, List<int>>? prefetched;

  @override
  State<DocEmailSheet> createState() => _DocEmailSheetState();
}

class _DocEmailSheetState extends State<DocEmailSheet> {
  bool _loading = true;
  Object? _loadError;
  Map<String, dynamic>? _d;
  String _templateId = '';
  final _subject = TextEditingController();
  List<String> _to = [], _cc = [], _bcc = [];
  final _toCtrl = TextEditingController(), _ccCtrl = TextEditingController(), _bccCtrl = TextEditingController();
  bool _ccOpen = false;
  final _body = NxRichTextController();
  final _bodyFocus = FocusNode();
  String _loadedBody = '';
  bool _includePdf = true;
  bool _includeLink = false;
  final List<MultipartFile> _files = [];
  bool _sending = false;
  bool _rechecking = false;
  double? _progress;
  List<double> _fileProgress = const [];
  String? _error;
  ({String title, String who})? _sent;
  Timer? _closeTimer;
  List<String> _recent = const [];
  String _snapshot = '';

  ApiClient get _api => context.read<AppConfig>().apiClient;
  bool get _isJob => widget.kind == 'job';
  bool get _ready => _d?['mail_ready'] != false;
  bool get _busy => _sending || _sent != null;

  @override
  void initState() {
    super.initState();
    _readRecent();
    _bodyFocus.addListener(_rebuild);
    for (final c in [_toCtrl, _ccCtrl, _bccCtrl, _subject]) {
      c.addListener(_rebuild);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _subject.dispose();
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _bccCtrl.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _readRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = (p.getStringList(_recentKey) ?? const []).where(docEmailRe.hasMatch).take(20).toList();
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _saveRecent(List<String> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      final next = {...list, ...(p.getStringList(_recentKey) ?? const <String>[])}.take(20).toList();
      await p.setStringList(_recentKey, next);
    } catch (_) {}
  }

  static List<String> _strs(Object? v) => v is List ? [for (final e in v) '$e'] : const [];

  // ------------------------------------------------------------ draft state

  String _snap() => jsonEncode([
    _subject.text,
    _to,
    _cc,
    _bcc,
    _toCtrl.text,
    _ccCtrl.text,
    _bccCtrl.text,
    _body.toHtml(),
    _includePdf,
    _includeLink,
    _templateId,
    [for (final f in _files) '${f.filename}:${f.length}'],
  ]);

  /// The user changed something since the defaults / template were loaded.
  bool get _dirty => _d != null && _snap() != _snapshot;

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final d = await _api.getDocComposeDefaults(widget.kind, widget.id);
      if (!mounted) return;
      _apply(d, reset ? null : widget.prefill);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  /// Fills the composer from the defaults [d], or from a sent e-mail [pre].
  void _apply(Map<String, dynamic> d, Map<String, dynamic>? pre) {
    final src = pre ?? d;
    setState(() {
      _d = d;
      _templateId = '${pre?['template_id'] ?? d['template_id'] ?? ''}';
      _subject.text = '${src['subject'] ?? ''}';
      _to = _strs(src['to']);
      _cc = _strs(src['cc']);
      _bcc = _strs(src['bcc']);
      _toCtrl.clear();
      _ccCtrl.clear();
      _bccCtrl.clear();
      _ccOpen = _cc.isNotEmpty || _bcc.isNotEmpty;
      _loadedBody = '${src['body_html'] ?? ''}';
      _body.setHtml(_loadedBody);
      final atts = pre?['attachments'];
      _includePdf = pre != null && atts is List ? atts.any((a) => a is Map && '${a['source'] ?? ''}'.startsWith('pdf')) || d['attach_pdf'] == true : d['attach_pdf'] != false;
      _includeLink = d['include_link'] == true;
      _files.clear();
      _error = null;
      _loading = false;
    });
    _snapshot = _snap();
  }

  /// Mail settings changed on the web? Ask again without losing the draft.
  Future<void> _recheck() async {
    if (!_dirty) return _load();
    setState(() => _rechecking = true);
    try {
      final d = await _api.getDocComposeDefaults(widget.kind, widget.id);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = tr(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _rechecking = false);
    }
  }

  Future<bool> _confirm(String title, String body, String ok, {bool destructive = false, Key? okKey}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(key: const ValueKey('compose-confirm-cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text(tr('แก้ต่อ'))),
            FilledButton(
              key: okKey ?? const ValueKey('compose-confirm-ok'),
              style: destructive ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ok),
            ),
          ],
        );
      },
    );
    return r == true;
  }

  Future<void> _resetTemplate() async {
    if (_dirty && !await _confirm(tr('โหลดข้อความตั้งต้นใหม่?'), tr('หัวข้อ ผู้รับ ข้อความ และไฟล์แนบที่แก้ไว้จะถูกแทนที่ด้วยค่าตั้งต้น'), tr('โหลดใหม่'))) return;
    if (mounted) await _load(reset: true);
  }

  Future<void> _close() async {
    if (_sending) return;
    if (_sent == null && _dirty) {
      final ok = await _confirm(tr('ทิ้งอีเมลนี้?'), tr('ผู้รับ ข้อความ และไฟล์แนบที่แก้ไว้จะหายไป'), tr('ทิ้ง'), destructive: true, okKey: const ValueKey('compose-discard-ok'));
      if (!ok || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop(_sent != null);
  }

  // ------------------------------------------------------------ templates / history

  List<Map<String, dynamic>> get _templates => [
    for (final t in (_d?['templates'] as List?) ?? const [])
      if (t is Map) Map<String, dynamic>.from(t),
  ];

  Future<void> _pickTemplate() async {
    final list = _templates;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('เทมเพลตอีเมล'), style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final t in list)
              ListTile(
                key: ValueKey('compose-template-${t['id']}'),
                leading: Icon('${t['id']}' == _templateId ? NxI.radioOn : NxI.radioOff, color: '${t['id']}' == _templateId ? Theme.of(ctx).colorScheme.primary : null),
                title: Text('${t['name']}'),
                subtitle: t['is_default'] == true ? Text(tr('ค่าเริ่มต้น')) : null,
                onTap: () => Navigator.pop(ctx, '${t['id']}'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (id != null && mounted) await _switchTemplate(id);
  }

  Future<void> _switchTemplate(String id) async {
    final t = _templates.where((x) => '${x['id']}' == id).firstOrNull;
    if (t == null || id == _templateId) return;
    final dirty = _body.toHtml() != NxRichTextController(html: _loadedBody).toHtml();
    if (dirty && !await _confirm(tr('เปลี่ยนเทมเพลต?'), tr('เปลี่ยนเทมเพลตจะแทนที่หัวข้อและข้อความที่แก้ไว้ ต้องการเปลี่ยนหรือไม่?'), tr('เปลี่ยน'))) return;
    if (!mounted) return;
    setState(() {
      _templateId = id;
      _subject.text = '${t['subject'] ?? ''}';
      _loadedBody = '${t['body_html'] ?? ''}';
      _body.setHtml(_loadedBody);
    });
  }

  Future<void> _openHistory() async {
    final m = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child: _EmailHistory(api: _api, kind: widget.kind, id: widget.id),
      ),
    );
    if (m == null || !mounted || _d == null) return;
    if (_dirty && !await _confirm(tr('ใช้อีเมลที่เคยส่ง?'), tr('ผู้รับ หัวข้อ และข้อความในหน้านี้จะถูกแทนที่ด้วยอีเมลที่เลือก'), tr('ใช้อีเมลนี้'))) return;
    if (mounted) _apply(_d!, m);
  }

  // ------------------------------------------------------------ attachments

  Future<void> _addFiles() async {
    setState(() => _error = null);
    final picked = await (DocEmailHooks.pickFiles ?? pickAttachments)(context);
    if (picked.isEmpty || !mounted) return;
    String? err;
    final next = [..._files];
    for (final f in picked) {
      if (f.length > kDocEmailMaxFileMb * 1024 * 1024) {
        err = '${tr('ไฟล์ใหญ่เกิน')} $kDocEmailMaxFileMb MB: ${f.filename ?? ''}';
        continue;
      }
      if (next.length >= kDocEmailMaxFiles) {
        err = tr('แนบไฟล์ได้สูงสุด 10 ไฟล์');
        break;
      }
      if (!next.any((x) => x.filename == f.filename && x.length == f.length)) next.add(f);
    }
    HapticFeedback.selectionClick();
    setState(() {
      _files
        ..clear()
        ..addAll(next);
      _error = err;
    });
  }

  Map<String, dynamic> get _docInfo => Map<String, dynamic>.from((_d?[_isJob ? 'job' : 'quotation'] as Map?) ?? const {});
  String get _docNo => '${_docInfo[_isJob ? 'job_no' : 'quotation_no'] ?? widget.docNo ?? ''}';
  String get _pdfName => '${(_d?['attachment'] as Map?)?['name'] ?? (_isJob ? 'job.pdf' : 'quotation.pdf')}';

  void _previewPdf() {
    final row = {..._docInfo, 'id': widget.id, if (_docNo.isNotEmpty) (_isJob ? 'job_no' : 'quotation_no'): _docNo};
    final src = widget.document ?? (_isJob ? jobDocumentSource(row) : quotationDocumentSource(row));
    openDocumentPreview(context, src, prefetched: widget.prefetched);
  }

  // ------------------------------------------------------------ send

  List<String> _merge(List<String> chips, TextEditingController c) => [
    ...chips,
    for (final p in parseRecipients(c.text))
      if (!chips.contains(p)) p,
  ];

  String? get _validation {
    final all = [..._merge(_to, _toCtrl), ..._merge(_cc, _ccCtrl), ..._merge(_bcc, _bccCtrl)];
    final bad = all.where((e) => !docEmailRe.hasMatch(e)).toList();
    if (_subject.text.trim().isEmpty) return tr('กรุณาระบุหัวข้อ');
    if (all.isEmpty) return tr('กรุณาระบุผู้รับอย่างน้อย 1 คน');
    if (bad.isNotEmpty) return '${tr('อีเมลไม่ถูกต้อง')}: ${bad.join(', ')}';
    if (!_includePdf && _files.isEmpty) return tr('กรุณาแนบไฟล์อย่างน้อย 1 ไฟล์');
    return null;
  }

  bool get _canSend => _d != null && !_loading && !_busy && _ready && _validation == null;

  /// Tap on the (disabled) send button: say why.
  void _explain() {
    if (_d == null || _loading || _busy) return;
    HapticFeedback.lightImpact();
    // Not set up: the banner at the top already says so.
    if (_ready) setState(() => _error = _validation);
  }

  void _onProgress(int sent, int total) {
    if (!mounted || total <= 0) return;
    final lens = [for (final f in _files) f.length];
    var start = total - lens.fold<int>(0, (a, b) => a + b);
    final per = <double>[];
    for (final l in lens) {
      per.add(l <= 0 ? 1.0 : ((sent - start) / l).clamp(0.0, 1.0));
      start += l;
    }
    setState(() {
      _progress = sent >= total ? null : sent / total;
      _fileProgress = per;
    });
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    // Text still in a recipient field counts as typed.
    _to = _merge(_to, _toCtrl);
    _cc = _merge(_cc, _ccCtrl);
    _bcc = _merge(_bcc, _bccCtrl);
    for (final c in [_toCtrl, _ccCtrl, _bccCtrl]) {
      c.clear();
    }
    final v = _validation;
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() {
      _sending = true;
      _progress = _files.isEmpty ? null : 0;
      _fileProgress = [for (final _ in _files) 0.0];
      _error = null;
    });
    try {
      final r = await _api.sendDocCompose(
        widget.kind,
        widget.id,
        to: _to,
        cc: _cc,
        bcc: _bcc,
        subject: _subject.text.trim(),
        bodyHtml: _body.toHtml(),
        includePdf: _includePdf,
        includeLink: !_isJob && _includeLink,
        templateId: _templateId,
        files: [for (final f in _files) f.clone()],
        onSendProgress: _files.isEmpty ? null : _onProgress,
      );
      await _saveRecent([..._to, ..._cc, ..._bcc]);
      HapticFeedback.mediumImpact();
      final queued = r.data['queued'] == true;
      final whoList = [..._strs(r.data['to']), ..._strs(r.data['cc'])];
      final names = {
        for (final x in _suggestions)
          if (x.label.isNotEmpty) x.email: x.label,
      };
      final who = [
        for (final e in whoList.isEmpty ? [..._to, ..._cc] : whoList) names[e] ?? e,
      ].join(', ');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = (title: tr(queued ? 'ส่งเข้าคิวแล้ว' : 'ส่งแล้ว'), who: who);
      });
      final toast = queued ? tr('ส่งเข้าคิวแล้ว ระบบจะจัดส่งภายใน 1–2 นาที') : '${tr('ส่งอีเมลเรียบร้อย')}${whoList.isEmpty ? '' : ' · ${whoList.join(', ')}'}';
      _closeTimer = Timer(const Duration(milliseconds: 1400), () {
        messenger?.showSnackBar(SnackBar(key: const ValueKey('compose-sent-toast'), content: Text(toast)));
        if (mounted) nav.pop(true);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
          _fileProgress = const [];
          _error = tr(formatApiError(e));
        });
      }
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final toolbar = _d != null && _bodyFocus.hasFocus && !_busy;
    return PopScope(
      canPop: !_sending && (_sent != null || !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: !toolbar || !keyboard,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  _topBar(theme, cs),
                  SizedBox(
                    height: 2,
                    child: _sending
                        ? LinearProgressIndicator(key: const ValueKey('compose-progress'), value: _progress, minHeight: 2, backgroundColor: Colors.transparent)
                        : Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.7)),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _content(theme, cs)),
                        if (_sent != null) Positioned.fill(child: _sentView(theme, cs)),
                      ],
                    ),
                  ),
                  if (toolbar) _formatBar(cs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(ThemeData theme, ColorScheme cs) {
    final no = _docNo;
    final customer = '${_docInfo['customer'] ?? ''}';
    final canSend = _canSend;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
      child: Row(
        children: [
          IconButton(key: const ValueKey('compose-close'), tooltip: tr('ปิด'), onPressed: _sending ? null : _close, icon: const Icon(NxI.x)),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('ส่งอีเมล'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
                ),
                if (no.isNotEmpty || customer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LayoutBuilder(
                      builder: (context, box) => Row(
                        children: [
                          if (no.isNotEmpty)
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: (box.maxWidth - (customer.isEmpty ? 0 : 40)).clamp(0, 150)),
                              child: Container(
                                key: const ValueKey('compose-doc-chip'),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_isJob ? NxI.wrench : NxI.fileText, size: 12, color: cs.primary),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        no,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (customer.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                customer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Narrow screen with large text: the attachment row's "add" tile is enough.
          if (MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) >= 330)
            IconButton(
              key: const ValueKey('compose-attach'),
              tooltip: tr('แนบไฟล์'),
              onPressed: _d == null || _busy || _files.length >= kDocEmailMaxFiles ? null : _addFiles,
              icon: const Icon(NxI.paperclip),
            ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: canSend ? null : _explain,
            child: FilledButton.icon(
              key: const ValueKey('compose-send'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16), shape: const StadiumBorder()),
              onPressed: canSend ? _send : null,
              icon: _sending ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface.withValues(alpha: 0.5))) : const Icon(NxI.paperPlaneTilt, size: 18),
              label: Text(tr('ส่ง')),
            ),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('compose-menu'),
            tooltip: tr('เพิ่มเติม'),
            enabled: _d != null && !_busy,
            icon: const Icon(NxI.dotsThreeVertical),
            position: PopupMenuPosition.under,
            onSelected: (v) => switch (v) {
              'template' => _pickTemplate(),
              'refresh' => _resetTemplate(),
              'history' => _openHistory(),
              'discard' => _close(),
              _ => null,
            },
            itemBuilder: (_) {
              final t = _templates.where((x) => '${x['id']}' == _templateId).firstOrNull;
              PopupMenuItem<String> item(String value, IconData icon, String label, {String? sub, Color? color}) => PopupMenuItem<String>(
                key: ValueKey('compose-$value'),
                value: value,
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: color ?? cs.onSurfaceVariant),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
                          if (sub != null)
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              return [
                if (_templates.length > 1) item('template', NxI.note, tr('เทมเพลตอีเมล'), sub: t == null ? null : '${t['name']}'),
                item('refresh', NxI.arrowCounterClockwise, tr('โหลดข้อความตั้งต้นใหม่')),
                item('history', NxI.clockCounterClockwise, tr('ประวัติการส่ง')),
                const PopupMenuDivider(),
                item('discard', NxI.trash, tr('ทิ้งอีเมลนี้'), color: composeErrorColor(context)),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _banner({required Key key, required Color bg, required Color fg, required IconData icon, required Widget text, Widget? action}) => Container(
    key: key,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: EdgeInsets.fromLTRB(12, 8, action == null ? 12 : 4, 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: fg),
            child: text,
          ),
        ),
        ?action,
      ],
    ),
  );

  Widget _banners(ThemeData theme, ColorScheme cs) {
    final dark = theme.brightness == Brightness.dark;
    final amberFg = dark ? const Color(0xFFFCD34D) : const Color(0xFF8A5A00);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_ready)
          _banner(
            key: const ValueKey('compose-mail-not-ready'),
            bg: const Color(0xFFF59E0B).withValues(alpha: dark ? 0.16 : 0.14),
            fg: amberFg,
            icon: NxI.warning,
            text: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: tr('ยังไม่ได้ตั้งค่าการส่งอีเมลของธุรกิจ'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '\n${tr('ผู้ดูแลตั้งค่าได้ที่ ตั้งค่า › การส่งอีเมล บนเว็บ')}'),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: amberFg),
            ),
            action: TextButton(
              key: const ValueKey('compose-recheck'),
              style: TextButton.styleFrom(foregroundColor: amberFg, visualDensity: VisualDensity.compact),
              onPressed: _rechecking || _loading ? null : _recheck,
              child: _rechecking ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: amberFg)) : Text(tr('ตรวจอีกครั้ง')),
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : _banner(
                  key: const ValueKey('compose-error'),
                  bg: composeErrorColor(context).withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08),
                  fg: composeErrorColor(context),
                  icon: NxI.warningCircle,
                  text: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: composeErrorColor(context), fontWeight: FontWeight.w500),
                  ),
                  action: IconButton(
                    key: const ValueKey('compose-error-close'),
                    tooltip: tr('ปิด'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _error = null),
                    icon: Icon(NxI.x, size: 16, color: composeErrorColor(context)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _content(ThemeData theme, ColorScheme cs) {
    if (_loading && _d == null) return _skeleton(cs);
    if (_loadError != null && _d == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NxI.warning, size: 36, color: cs.error),
              const SizedBox(height: 10),
              Text(tr(formatApiError(_loadError!)), key: const ValueKey('compose-load-error'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(key: const ValueKey('compose-load-retry'), onPressed: _load, icon: const Icon(NxI.arrowClockwise, size: 18), label: Text(tr('ลองใหม่'))),
            ],
          ),
        ),
      );
    }
    final suggestions = _suggestions;
    final enabled = !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _banners(theme, cs),
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RecipientLine(
                      key: const ValueKey('compose-to'),
                      label: tr('ถึง'),
                      values: _to,
                      controller: _toCtrl,
                      suggestions: suggestions,
                      enabled: enabled,
                      onChanged: (v) => setState(() {
                        _to = v;
                        _error = null;
                      }),
                      trailing: _ccOpen
                          ? null
                          : TextButton(
                              key: const ValueKey('compose-show-bcc'),
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: cs.onSurfaceVariant),
                              onPressed: enabled ? () => setState(() => _ccOpen = true) : null,
                              child: Text(tr('สำเนา/ลับ')),
                            ),
                    ),
                    if (_ccOpen) ...[
                      RecipientLine(
                        key: const ValueKey('compose-cc'),
                        label: tr('สำเนา'),
                        values: _cc,
                        controller: _ccCtrl,
                        suggestions: suggestions,
                        enabled: enabled,
                        onChanged: (v) => setState(() {
                          _cc = v;
                          _error = null;
                        }),
                      ),
                      RecipientLine(
                        key: const ValueKey('compose-bcc'),
                        label: tr('สำเนาลับ'),
                        values: _bcc,
                        controller: _bccCtrl,
                        suggestions: suggestions,
                        enabled: enabled,
                        onChanged: (v) => setState(() {
                          _bcc = v;
                          _error = null;
                        }),
                      ),
                    ],
                    ComposeLine(
                      label: tr('หัวข้อ'),
                      child: TextField(
                        key: const ValueKey('compose-subject'),
                        controller: _subject,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.next,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _bodyFocus.requestFocus(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: tr('หัวข้ออีเมล'),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                        ),
                      ),
                    ),
                    _attachments(theme, cs, enabled),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: NxRichTextEditor(
                  controller: _body,
                  focusNode: _bodyFocus,
                  fieldKey: const ValueKey('compose-body'),
                  bordered: false,
                  showToolbar: false,
                  enabled: enabled,
                  minLines: 8,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                  contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  hint: 'พิมพ์ข้อความถึงลูกค้า…',
                ),
              ),
              // Empty space under the letter: tap to keep writing.
              SliverFillRemaining(
                hasScrollBody: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled
                      ? () {
                          _body.selection = TextSelection.collapsed(offset: _body.text.length);
                          _bodyFocus.requestFocus();
                        }
                      : null,
                  child: const SizedBox(height: 40),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attachments(ThemeData theme, ColorScheme cs, bool enabled) {
    final total = _files.fold<int>(0, (a, f) => a + f.length) + (_includePdf ? (widget.pdfSize ?? 0) : 0);
    final count = (_includePdf ? 1 : 0) + _files.length;
    final cards = <Widget>[
      if (_includePdf)
        AttachmentCard(
          key: const ValueKey('compose-pdf-card'),
          name: _pdfName,
          badge: tr('แนบอัตโนมัติ'),
          meta: widget.pdfSize != null ? fmtFileSize(widget.pdfSize!) : tr('สร้างตอนส่ง'),
          metaKey: const ValueKey('compose-pdf-meta'),
          onTap: _previewPdf,
          removeKey: const ValueKey('compose-include-pdf'),
          onRemove: enabled
              ? () => setState(() {
                  _includePdf = false;
                  _error = null;
                })
              : null,
        )
      else
        AddAttachmentTile(
          key: const ValueKey('compose-restore-pdf'),
          icon: NxI.filePdf,
          label: '${tr('แนบ')} ${_docNo.isEmpty ? _pdfName : _docNo}',
          onTap: enabled
              ? () => setState(() {
                  _includePdf = true;
                  _error = null;
                })
              : null,
        ),
      for (var i = 0; i < _files.length; i++)
        AttachmentCard(
          key: ValueKey('compose-file-$i'),
          name: _files[i].filename ?? 'file',
          meta: fmtFileSize(_files[i].length),
          progress: _sending && i < _fileProgress.length ? _fileProgress[i] : null,
          removeKey: ValueKey('compose-file-remove-$i'),
          onRemove: enabled ? () => setState(() => _files.removeAt(i)) : null,
        ),
      AddAttachmentTile(key: const ValueKey('compose-add-files'), label: tr('เพิ่มไฟล์'), onTap: enabled && _files.length < kDocEmailMaxFiles ? _addFiles : null),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(NxI.paperclip, size: 15, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ['${tr('ไฟล์แนบ')} $count', if (total > 0) fmtFileSize(total), if (_files.isNotEmpty) tr('สูงสุด 10 ไฟล์ · ไฟล์ละไม่เกิน 15 MB')].join(' · '),
                      key: const ValueKey('compose-attach-summary'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 58 * MediaQuery.textScalerOf(context).scale(14).clamp(14, 28) / 14,
              child: ListView.separated(
                key: const ValueKey('compose-attachments'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: cards.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => cards[i],
              ),
            ),
            if (count == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  tr('ยังไม่มีไฟล์แนบ — แนบเอกสารหรือไฟล์อย่างน้อย 1 ไฟล์'),
                  key: const ValueKey('compose-no-attachment'),
                  style: theme.textTheme.bodySmall?.copyWith(color: composeErrorColor(context)),
                ),
              ),
            if (!_isJob)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                child: Row(
                  children: [
                    Icon(NxI.link, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('แนบลิงก์ดูใบเสนอราคาออนไลน์'), style: theme.textTheme.bodyMedium),
                          Text(tr('ลูกค้ากดยอมรับ/ลงนามได้'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(key: const ValueKey('compose-include-link'), value: _includeLink, onChanged: enabled ? (v) => setState(() => _includeLink = v) : null),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<DocEmailSuggestion> get _suggestions {
    final base = [
      for (final s in (_d?['suggestions'] as List?) ?? const [])
        if (s is Map && '${s['email'] ?? ''}'.isNotEmpty) (email: '${s['email']}', label: '${s['label'] ?? ''}', source: '${s['source'] ?? ''}'),
    ];
    return [
      ...base,
      for (final e in _recent)
        if (!base.any((s) => s.email == e)) (email: e, label: '', source: 'recent'),
    ];
  }

  Widget _formatBar(ColorScheme cs) => DecoratedBox(
    key: const ValueKey('compose-format-bar'),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
    ),
    child: Row(
      children: [
        Expanded(
          child: NxRichToolbar(controller: _body, focusNode: _bodyFocus, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
        ),
        IconButton(tooltip: tr('ซ่อนแป้นพิมพ์'), visualDensity: VisualDensity.compact, onPressed: () => _bodyFocus.unfocus(), icon: const Icon(NxI.caretDown, size: 20)),
        const SizedBox(width: 4),
      ],
    ),
  );

  Widget _skeleton(ColorScheme cs) {
    Widget bar(double w, {double h = 12}) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(6)),
    );
    Widget line(double w) => Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Row(children: [bar(40), const SizedBox(width: 14), bar(w)]),
    );
    return Column(
      key: const ValueKey('compose-loading'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(180),
        line(140),
        line(240),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [bar(200, h: 52), const SizedBox(width: 8), bar(80, h: 52)]),
        ),
        for (final w in [260.0, 300.0, 220.0, 280.0, 160.0]) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: bar(w)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Row(
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
              const SizedBox(width: 10),
              Text(tr('กำลังเตรียมค่าเริ่มต้น…'), style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sentView(ThemeData theme, ColorScheme cs) => ColoredBox(
    key: const ValueKey('compose-success'),
    color: cs.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SentCheck(),
            const SizedBox(height: 20),
            Text(_sent!.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (_sent!.who.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${tr('ถึง')} ${_sent!.who}',
                key: const ValueKey('compose-success-who'),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// "ประวัติการส่ง": e-mails sent from this document; pick one to reuse it.
class _EmailHistory extends StatefulWidget {
  const _EmailHistory({required this.api, required this.kind, required this.id});
  final ApiClient api;
  final String kind;
  final String id;

  @override
  State<_EmailHistory> createState() => _EmailHistoryState();
}

class _EmailHistoryState extends State<_EmailHistory> {
  List<Map<String, dynamic>>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final l = await widget.api.getDocEmailLog(widget.kind, widget.id);
      if (mounted) setState(() => _items = l);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static String _fmt(Object? v) {
    final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${uiYear(d.year)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    List<String> strs(Object? v) => v is List ? [for (final e in v) '$e'] : const [];
    const status = {'sent': 'ส่งแล้ว', 'queued': 'เข้าคิว', 'failed': 'ไม่สำเร็จ'};
    final items = _items;
    return Column(
      key: const ValueKey('compose-history-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(tr('ประวัติการส่ง'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr(formatApiError(_error!)), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
                    ],
                  ),
                )
              : items == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
              : items.isEmpty
              ? Center(
                  child: Text(tr('ยังไม่เคยส่งอีเมลจากเอกสารนี้'), style: TextStyle(color: cs.onSurfaceVariant)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final failed = m['status'] == 'failed';
                    final who = [...strs(m['to']), ...strs(m['cc'])];
                    final by = (m['sent_by'] as Map?)?['name'];
                    return Material(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        key: ValueKey('compose-history-${m['id']}'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, m),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Row(
                            children: [
                              RecipientAvatar(email: who.isEmpty ? '?' : who.first, size: 36),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${m['subject'] ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                                          decoration: BoxDecoration(color: (failed ? cs.error : Colors.green).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                          child: Text(tr(status[m['status']] ?? '${m['status'] ?? ''}'), style: theme.textTheme.labelSmall),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${tr('ถึง')} ${who.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                                    Text(
                                      [_fmt(m['sent_at']), if (by != null && '$by'.isNotEmpty) '$by'].where((x) => x.isNotEmpty).join(' · '),
                                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Tooltip(
                                message: tr('ใช้ซ้ำ'),
                                child: Icon(NxI.reply, size: 18, color: cs.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
