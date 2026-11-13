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

final _emailRe = RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$');
const _recentKey = 'nextx.docCompose.recent';
const kDocEmailMaxFiles = 10;
const kDocEmailMaxFileMb = 15;

/// Test seams (no file dialogs in widget tests).
class DocEmailHooks {
  static Future<List<MultipartFile>> Function(BuildContext context)? pickFiles;
}

String fmtFileSize(int n) => n >= 1048576 ? '${(n / 1048576).toStringAsFixed(1)} MB' : '${(n / 1024).round().clamp(1, 1 << 30)} KB';

/// "ส่งอีเมล" for a quotation or job document — the web's compose window:
/// subject, To / CC / BCC (chips + suggestions), rich-text message from the
/// business template, the document PDF attached automatically (built by the
/// server from the BIRT template, like the web) plus extra files.
/// [kind] 'quotation' | 'job'. [pdfSize] = size of the document already
/// opened in the app (shown next to the auto attachment). [prefill] = a sent
/// e-mail from the history (resend). Returns true when sent.
Future<bool> showDocEmailSheet(BuildContext context, {required String kind, required String id, String? docNo, int? pdfSize, Map<String, dynamic>? prefill}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: DocEmailSheet(kind: kind, id: id, docNo: docNo, pdfSize: pdfSize, prefill: prefill),
    ),
  );
  return sent == true;
}

class DocEmailSheet extends StatefulWidget {
  const DocEmailSheet({super.key, required this.kind, required this.id, this.docNo, this.pdfSize, this.prefill});
  final String kind;
  final String id;
  final String? docNo;
  final int? pdfSize;
  final Map<String, dynamic>? prefill;

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
  bool _showBcc = false;
  final _body = NxRichTextController();
  String _loadedBody = '';
  bool _includePdf = true;
  bool _includeLink = false;
  final List<MultipartFile> _files = [];
  bool _sending = false;
  String? _error;
  List<String> _recent = const [];

  ApiClient get _api => context.read<AppConfig>().apiClient;
  bool get _isJob => widget.kind == 'job';

  @override
  void initState() {
    super.initState();
    _readRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _readRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = (p.getStringList(_recentKey) ?? const []).where(_emailRe.hasMatch).take(20).toList();
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

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final d = await _api.getDocComposeDefaults(widget.kind, widget.id);
      if (!mounted) return;
      final pre = reset ? null : widget.prefill;
      final src = pre ?? d;
      setState(() {
        _d = d;
        _templateId = '${pre?['template_id'] ?? d['template_id'] ?? ''}';
        _subject.text = '${src['subject'] ?? ''}';
        _to = _strs(src['to']);
        _cc = _strs(src['cc']);
        _bcc = _strs(src['bcc']);
        _showBcc = _bcc.isNotEmpty;
        _loadedBody = '${src['body_html'] ?? ''}';
        _body.setHtml(_loadedBody);
        final atts = pre?['attachments'];
        _includePdf = pre != null && atts is List ? atts.any((a) => a is Map && '${a['source'] ?? ''}'.startsWith('pdf')) || d['attach_pdf'] == true : d['attach_pdf'] != false;
        _includeLink = d['include_link'] == true;
        _files.clear();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _templates => [
    for (final t in (_d?['templates'] as List?) ?? const [])
      if (t is Map) Map<String, dynamic>.from(t),
  ];

  List<({String email, String label, String source})> get _suggestions {
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

  Future<void> _switchTemplate(String id) async {
    final t = _templates.where((x) => '${x['id']}' == id).firstOrNull;
    if (t == null || id == _templateId) return;
    final dirty = _body.toHtml() != NxRichTextController(html: _loadedBody).toHtml();
    if (dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(tr('เปลี่ยนเทมเพลตจะแทนที่หัวข้อและข้อความที่แก้ไว้ ต้องการเปลี่ยนหรือไม่?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('เปลี่ยน'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _templateId = id;
      _subject.text = '${t['subject'] ?? ''}';
      _loadedBody = '${t['body_html'] ?? ''}';
      _body.setHtml(_loadedBody);
    });
  }

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
    setState(() {
      _files
        ..clear()
        ..addAll(next);
      _error = err;
    });
  }

  String? get _validation {
    final all = [..._to, ..._cc, ..._bcc];
    final bad = all.where((e) => !_emailRe.hasMatch(e)).toList();
    if (_subject.text.trim().isEmpty) return tr('กรุณาระบุหัวข้อ');
    if (all.isEmpty) return tr('กรุณาระบุผู้รับอย่างน้อย 1 คน');
    if (bad.isNotEmpty) return '${tr('อีเมลไม่ถูกต้อง')}: ${bad.join(', ')}';
    if (!_includePdf && _files.isEmpty) return tr('กรุณาแนบไฟล์อย่างน้อย 1 ไฟล์');
    return null;
  }

  Future<void> _send() async {
    final v = _validation;
    if (v != null) {
      setState(() => _error = v);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() {
      _sending = true;
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
      );
      await _saveRecent([..._to, ..._cc, ..._bcc]);
      HapticFeedback.mediumImpact();
      final queued = r.data['queued'] == true;
      final who = [..._strs(r.data['to']), ..._strs(r.data['cc'])].join(', ');
      messenger?.showSnackBar(
        SnackBar(key: const ValueKey('compose-sent-toast'), content: Text(queued ? tr('ส่งเข้าคิวแล้ว ระบบจะจัดส่งภายใน 1–2 นาที') : '${tr('ส่งอีเมลเรียบร้อย')}${who.isEmpty ? '' : ' · $who'}')),
      );
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = tr(formatApiError(e));
        });
      }
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dd = _d ?? const <String, dynamic>{};
    final doc = (dd[_isJob ? 'job' : 'quotation'] as Map?) ?? const {};
    final noKey = _isJob ? 'job_no' : 'quotation_no';
    final subtitle = [doc[noKey] ?? widget.docNo, doc['customer']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    final ready = _d?['mail_ready'] != false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(_isJob ? 'ส่งอีเมลใบสั่งงาน' : 'ส่งอีเมลใบเสนอราคา'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              IconButton(tooltip: tr('ปิด'), onPressed: _sending ? null : () => Navigator.pop(context, false), icon: const Icon(NxI.x)),
            ],
          ),
        ),
        Expanded(child: _content(theme, cs, ready)),
        if (_d != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Problems stay in view next to the send button (the form scrolls).
                    if (_error != null)
                      Container(
                        key: const ValueKey('compose-error'),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                        child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onErrorContainer)),
                      ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('compose-refresh'),
                          onPressed: _sending || _loading ? null : () => _load(reset: true),
                          icon: const Icon(NxI.arrowClockwise, size: 18),
                          label: Text(tr('รีเฟรช')),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey('compose-send'),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: _sending || _loading || !ready ? null : _send,
                            icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.paperPlaneTilt, size: 18),
                            label: Text(tr(_sending ? 'กำลังส่ง…' : 'ส่งรายงาน')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _content(ThemeData theme, ColorScheme cs, bool ready) {
    if (_loading && _d == null) {
      return Center(
        key: const ValueKey('compose-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.4),
            const SizedBox(height: 12),
            Text(tr('กำลังเตรียมค่าเริ่มต้น…'), style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
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
              FilledButton.icon(onPressed: _load, icon: const Icon(NxI.arrowClockwise, size: 18), label: Text(tr('ลองใหม่'))),
            ],
          ),
        ),
      );
    }
    final pdfName = '${(_d?['attachment'] as Map?)?['name'] ?? (_isJob ? 'job.pdf' : 'quotation.pdf')}';
    final label = theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (!ready)
          Container(
            key: const ValueKey('compose-mail-not-ready'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(NxI.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('ยังไม่ได้ตั้งค่าการส่งอีเมลของธุรกิจ — ผู้ดูแลตั้งค่าได้ที่ ตั้งค่า › การส่งอีเมล (บนเว็บ) แล้วกดรีเฟรช'), style: theme.textTheme.bodySmall)),
              ],
            ),
          ),
        if (_templates.length > 1) ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('compose-template'),
            initialValue: _templates.any((t) => '${t['id']}' == _templateId) ? _templateId : null,
            decoration: InputDecoration(labelText: tr('เทมเพลตอีเมล')),
            items: [
              for (final t in _templates)
                DropdownMenuItem(
                  value: '${t['id']}',
                  child: Text(t['is_default'] == true ? '${t['name']} (${tr('ค่าเริ่มต้น')})' : '${t['name']}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => v == null ? null : _switchTemplate(v),
          ),
          const SizedBox(height: 12),
        ],
        Text(tr('หัวข้อ'), style: label),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('compose-subject'),
          controller: _subject,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(hintText: tr('หัวข้ออีเมล')),
        ),
        const SizedBox(height: 14),
        RecipientField(
          key: const ValueKey('compose-to'),
          label: tr('ถึง'),
          values: _to,
          suggestions: _suggestions,
          onChanged: (v) => setState(() {
            _to = v;
            _error = null;
          }),
          trailing: _showBcc ? null : TextButton(key: const ValueKey('compose-show-bcc'), onPressed: () => setState(() => _showBcc = true), child: Text(tr('สำเนาลับ'))),
        ),
        const SizedBox(height: 12),
        RecipientField(key: const ValueKey('compose-cc'), label: tr('สำเนา'), values: _cc, suggestions: _suggestions, onChanged: (v) => setState(() => _cc = v)),
        if (_showBcc) ...[
          const SizedBox(height: 12),
          RecipientField(key: const ValueKey('compose-bcc'), label: tr('สำเนาลับ'), values: _bcc, suggestions: _suggestions, onChanged: (v) => setState(() => _bcc = v)),
        ],
        const SizedBox(height: 14),
        Text(tr('ข้อความ'), style: label),
        const SizedBox(height: 6),
        NxRichTextEditor(controller: _body, fieldKey: const ValueKey('compose-body'), minLines: 7, hint: 'พิมพ์ข้อความถึงลูกค้า…'),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(tr('ไฟล์แนบ'), style: label),
            const SizedBox(width: 6),
            Text('(${(_includePdf ? 1 : 0) + _files.length})', style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          child: CheckboxListTile(
            key: const ValueKey('compose-include-pdf'),
            value: _includePdf,
            onChanged: (v) => setState(() {
              _includePdf = v ?? false;
              _error = null;
            }),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.only(left: 4, right: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            secondary: const Icon(NxI.filePdf, color: Color(0xFFE5484D)),
            title: Text(
              pdfName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(decoration: _includePdf ? null : TextDecoration.lineThrough),
            ),
            subtitle: Text(
              '${tr('แนบอัตโนมัติจากรายงาน')} · ${widget.pdfSize != null ? fmtFileSize(widget.pdfSize!) : tr('สร้างตอนส่ง')}',
              key: const ValueKey('compose-pdf-meta'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        for (var i = 0; i < _files.length; i++)
          ListTile(
            key: ValueKey('compose-file-$i'),
            contentPadding: const EdgeInsets.only(left: 12),
            leading: const Icon(NxI.paperclip),
            title: Text(_files[i].filename ?? 'file', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(fmtFileSize(_files[i].length)),
            trailing: IconButton(key: ValueKey('compose-file-remove-$i'), tooltip: tr('ลบไฟล์'), onPressed: () => setState(() => _files.removeAt(i)), icon: const Icon(NxI.x, size: 18)),
          ),
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('compose-add-files'),
          borderRadius: BorderRadius.circular(14),
          onTap: _files.length >= kDocEmailMaxFiles || _sending ? null : _addFiles,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant, width: 1.4),
            ),
            child: Column(
              children: [
                Icon(NxI.uploadSimple, color: cs.primary),
                const SizedBox(height: 6),
                Text(tr('แตะเพื่อแนบไฟล์เพิ่ม'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(tr('สูงสุด 10 ไฟล์ · ไฟล์ละไม่เกิน 15 MB'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        if (!_isJob)
          CheckboxListTile(
            key: const ValueKey('compose-include-link'),
            value: _includeLink,
            onChanged: (v) => setState(() => _includeLink = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(tr('แนบลิงก์ดูใบเสนอราคาออนไลน์ (ลูกค้ากดยอมรับ/ลงนามได้)'), style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// E-mail chips + typing field with suggestions (Enter / , / space adds).
class RecipientField extends StatefulWidget {
  const RecipientField({super.key, required this.label, required this.values, required this.onChanged, this.suggestions = const [], this.trailing});
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<({String email, String label, String source})> suggestions;
  final Widget? trailing;

  @override
  State<RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<RecipientField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  static const _sourceLabel = {
    'contact': 'ผู้ติดต่อ',
    'customer': 'ลูกค้า',
    'account': 'บัญชีลูกค้า',
    'owner': 'ผู้รับผิดชอบ',
    'authorizer': 'ผู้มีอำนาจลงนาม',
    'engineer': 'ช่าง',
    'sales': 'ฝ่ายขาย',
    'me': 'ฉัน',
    'user': 'ผู้ใช้',
    'recent': 'ล่าสุด',
  };

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _emailRe.hasMatch(_ctrl.text.trim())) _add(_ctrl.text);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final parts = raw.split(RegExp(r'[,;\s]+')).map((x) => x.trim().replaceAll(RegExp(r'^.*<|>$'), '').toLowerCase()).where((x) => x.isNotEmpty);
    final next = [...widget.values];
    for (final p in parts) {
      if (!next.contains(p)) next.add(p);
    }
    _ctrl.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
    setState(() {});
  }

  List<({String email, String label, String source})> get _matches {
    final q = _ctrl.text.trim().toLowerCase();
    final list = widget.suggestions.where((s) => !widget.values.contains(s.email));
    if (q.isEmpty) return list.take(5).toList();
    return list.where((s) => s.email.contains(q) || s.label.toLowerCase().contains(q)).take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final matches = _focus.hasFocus ? _matches : const <({String email, String label, String source})>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _focus.hasFocus ? cs.primary : cs.outlineVariant, width: _focus.hasFocus ? 1.6 : 1),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final e in widget.values)
                  InputChip(
                    key: ValueKey('chip-$e'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: _emailRe.hasMatch(e) ? null : cs.errorContainer,
                    label: Text(() {
                      final name = widget.suggestions.where((s) => s.email == e && s.label.isNotEmpty).firstOrNull?.label;
                      return name == null ? e : '$name · $e';
                    }(), overflow: TextOverflow.ellipsis),
                    deleteIcon: const Icon(NxI.x, size: 14),
                    onDeleted: () => widget.onChanged([...widget.values]..remove(e)),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 140),
                  child: IntrinsicWidth(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintText: widget.values.isEmpty ? tr('พิมพ์อีเมล หรือเลือกจากรายการ') : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      ),
                      onChanged: (v) {
                        if (RegExp(r'[,;\s]$').hasMatch(v)) {
                          _add(v);
                        } else {
                          setState(() {});
                        }
                      },
                      onSubmitted: (v) {
                        final m = _matches;
                        if (v.trim().isNotEmpty && !_emailRe.hasMatch(v.trim()) && m.isNotEmpty) {
                          _add(m.first.email);
                        } else {
                          _add(v);
                        }
                        _focus.requestFocus();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (matches.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final s in matches)
                  ListTile(
                    key: ValueKey('suggest-${s.email}'),
                    dense: true,
                    title: Text(s.label.isEmpty ? s.email : s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: s.label.isEmpty ? null : Text(s.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tr(_sourceLabel[s.source] ?? s.source), style: theme.textTheme.labelSmall),
                    ),
                    onTap: () {
                      _add(s.email);
                      _focus.requestFocus();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
