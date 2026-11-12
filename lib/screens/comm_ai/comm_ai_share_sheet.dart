import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/fields/nx_entity_picker_sheet.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/fields/nx_picker_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../deep_link_loaders.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_widgets.dart';

/// CRM records a conversation can be saved on (same list as the web share dialog).
const kCommAiCrmModules = <(String, String)>[
  ('account', 'ลูกค้า (บัญชี)'),
  ('contact', 'ผู้ติดต่อ'),
  ('lead', 'ผู้มุ่งหวัง (Lead)'),
  ('case', 'เคส'),
  ('quotation', 'ใบเสนอราคา'),
];

/// Share / export a conversation: device share (file), e-mail (recipient quick picks, call tape, CRM log),
/// external link (expiry, password, revoke), direct message to colleagues, or an Activity on a CRM record.
Future<void> showCommAiShareSheet(BuildContext context, {required String kind, required String id, String? title, bool hasAudio = false}) {
  return showAppBottomSheet<void>(context: context, title: tr('แชร์บทสนทนา'), child: CommAiShareSheet(kind: kind, id: id, title: title, hasAudio: hasAudio));
}

/// A chosen CRM record: module + the picked row.
typedef CommAiCrmPick = ({String module, NxPickOption? record});

/// Module dropdown + record picker (the app's standard entity search sheet).
class CommAiCrmRecordPicker extends StatelessWidget {
  const CommAiCrmRecordPicker({super.key, required this.value, required this.onChanged, this.keyPrefix = 'comm-ai-crm'});
  final CommAiCrmPick value;
  final ValueChanged<CommAiCrmPick> onChanged;
  final String keyPrefix;

  Future<void> _pick(BuildContext context) async {
    final api = context.read<AppConfig>().apiClient;
    final module = value.module;
    final picked = await showNxEntityPickerSheet(
      context: context,
      title: tr('เลือกรายการ'),
      current: value.record,
      search: (q) async {
        final page = await api.getEntityList(module, limit: 30, q: q);
        return [
          for (final r in page.items)
            if (strId(r['id']).isNotEmpty) NxPickOption(value: strId(r['id']), label: entityTitle(r, module: module), subtitle: entitySubtitle(r, module: module)),
        ];
      },
    );
    if (picked != null && picked.value.isNotEmpty) onChanged((module: module, record: picked));
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 150,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$keyPrefix-module'),
          isExpanded: true,
          initialValue: value.module,
          decoration: InputDecoration(labelText: tr('ประเภท')),
          items: [for (final (m, label) in kCommAiCrmModules) DropdownMenuItem(value: m, child: Text(tr(label), overflow: TextOverflow.ellipsis))],
          onChanged: (m) {
            if (m != null && m != value.module) onChanged((module: m, record: null));
          },
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: InkWell(
          key: ValueKey('$keyPrefix-record'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pick(context),
          child: InputDecorator(
            decoration: InputDecoration(labelText: tr('รายการ'), prefixIcon: const Icon(NxI.buildings, size: 18)),
            child: Text(
              value.record?.label ?? tr('เลือกรายการ…'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: value.record == null ? TextStyle(color: hint) : null,
            ),
          ),
        ),
      ),
    ]);
  }
}

class CommAiShareSheet extends StatefulWidget {
  const CommAiShareSheet({super.key, required this.kind, required this.id, this.title, this.hasAudio = false});
  final String kind;
  final String id;
  final String? title;

  /// The call has recorded audio (offers "attach tape" and audio in a ZIP).
  final bool hasAudio;

  @override
  State<CommAiShareSheet> createState() => _CommAiShareSheetState();
}

class _CommAiShareSheetState extends State<CommAiShareSheet> {
  String _tab = 'device';
  final _include = <String>{'summary', 'actions', 'transcript'};
  String _format = 'pdf';
  String _lang = 'th';
  String? _busy;
  String? _msg;
  bool _msgError = false;
  String? _link;
  int _days = 7;
  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _links = const [];
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _note = TextEditingController();
  final _password = TextEditingController();
  // e-mail extras
  List<Map<String, dynamic>>? _recipients;
  bool _attachAudio = false;
  CommAiCrmPick? _logTo;
  // to colleagues
  final _mates = <String, String>{}; // user id → name
  final _chatNote = TextEditingController();
  // to CRM
  CommAiCrmPick _crm = (module: 'account', record: null);
  late String _crmType = widget.kind == 'call' ? 'Call' : 'Meeting';
  final _crmNote = TextEditingController();
  String? _activityId;

  @override
  void initState() {
    super.initState();
    final api = context.read<AppConfig>().apiClient;
    api.getCommAiSettings().then((r) {
      if (mounted && r['settings'] is Map) setState(() => _settings = Map<String, dynamic>.from(r['settings'] as Map));
    }).catchError((_) {});
    _loadLinks();
  }

  @override
  void dispose() {
    _to.dispose();
    _cc.dispose();
    _note.dispose();
    _password.dispose();
    _chatNote.dispose();
    _crmNote.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    try {
      final list = await context.read<AppConfig>().apiClient.listConversationLinks(widget.kind, widget.id);
      if (mounted) setState(() => _links = list);
    } catch (_) {}
  }

  Future<void> _loadRecipients() async {
    if (_recipients != null) return;
    _recipients = const [];
    try {
      final list = await context.read<AppConfig>().apiClient.getShareRecipients(widget.kind, widget.id);
      if (mounted) setState(() => _recipients = list);
    } catch (_) {}
  }

  bool get _emailOn => _settings?['share_email_enabled'] != false;
  bool get _linkOn => _settings?['share_link_enabled'] != false;
  int get _maxDays => (_settings?['share_link_max_days'] as num?)?.toInt() ?? 30;
  bool get _isCall => widget.kind == 'call';

  List<String> _emails(String s) => s.split(RegExp(r'[,;\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  void _addRecipient(String email) {
    final list = _emails(_to.text);
    if (list.contains(email)) return;
    _to.text = [...list, email].join(', ');
    setState(() {});
  }

  Future<void> _run(String what, Future<String?> Function() fn) async {
    setState(() {
      _busy = what;
      _msg = null;
    });
    try {
      final m = await fn();
      if (mounted) {
        setState(() {
          _msg = m;
          _msgError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = formatApiError(e);
          _msgError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickMates() async {
    final api = context.read<AppConfig>().apiClient;
    final me = context.read<AppConfig>().session.userId;
    Future<List<NxPickOption>> search(String q) async {
      final rows = await api.getUsers(q: q.isEmpty ? null : q, limit: 60);
      return [for (final o in rows.map(NxPickOption.fromMap)) if (o.value.isNotEmpty && o.value != me) o];
    }

    final opts = await search('').catchError((Object _) => <NxPickOption>[]);
    if (!mounted) return;
    final known = {for (final o in opts) o.value: o.label, ..._mates};
    final picked = await showNxMultiPickerSheet(
      context: context,
      title: tr('ส่งให้'),
      options: [
        ...opts,
        for (final e in _mates.entries)
          if (!opts.any((o) => o.value == e.key)) NxPickOption(value: e.key, label: e.value),
      ],
      values: _mates.keys.toSet(),
      onSearch: (q) async {
        final rows = await search(q);
        for (final o in rows) {
          known[o.value] = o.label;
        }
        return rows;
      },
      users: true,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _mates
        ..clear()
        ..addAll({for (final id in picked) id: known[id] ?? id});
    });
  }

  Widget _spin() => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(tr(text), style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      );

  List<Widget> _emailTab(List<String> inc) {
    final api = context.read<AppConfig>().apiClient;
    final picks = [for (final r in _recipients ?? const <Map<String, dynamic>>[]) if ('${r['email'] ?? ''}'.contains('@')) r];
    return [
      TextField(
        key: const ValueKey('comm-ai-share-to'),
        controller: _to,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: tr('ถึง'), helperText: tr('คั่นหลายอีเมลด้วย ,'), prefixIcon: const Icon(NxI.envelope)),
        onChanged: (_) => setState(() {}),
      ),
      if (picks.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr('คนในการสนทนา:'), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          for (final r in picks)
            ActionChip(
              key: ValueKey('comm-ai-share-recipient-${r['user_id']}'),
              avatar: const Icon(NxI.userPlus, size: 14),
              visualDensity: VisualDensity.compact,
              label: Text('${r['name']}'),
              onPressed: _emails(_to.text).contains('${r['email']}') ? null : () => _addRecipient('${r['email']}'),
            ),
        ]),
      ],
      const SizedBox(height: 10),
      TextField(key: const ValueKey('comm-ai-share-cc'), controller: _cc, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'CC')),
      const SizedBox(height: 10),
      TextField(key: const ValueKey('comm-ai-share-note'), controller: _note, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('ข้อความถึงผู้รับ'), hintText: tr('ไม่บังคับ'), alignLabelWithHint: true)),
      if (_isCall && widget.hasAudio && _format != 'zip')
        CheckboxListTile(
          key: const ValueKey('comm-ai-share-attach-audio'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _attachAudio,
          onChanged: (v) => setState(() => _attachAudio = v ?? false),
          title: Text(tr('แนบเทปเสียงการสนทนา'), style: const TextStyle(fontSize: 14)),
          subtitle: Text(tr('ไฟล์ใหญ่จะส่งเป็นลิงก์ 7 วัน'), style: const TextStyle(fontSize: 12)),
        ),
      CheckboxListTile(
        key: const ValueKey('comm-ai-share-log-crm'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _logTo != null,
        onChanged: (v) => setState(() => _logTo = v == true ? (module: 'account', record: null) : null),
        title: Text(tr('บันทึกการส่งเป็น Activity "Email" ในลูกค้า'), style: const TextStyle(fontSize: 14)),
      ),
      if (_logTo != null) ...[
        CommAiCrmRecordPicker(keyPrefix: 'comm-ai-email-crm', value: _logTo!, onChanged: (v) => setState(() => _logTo = v)),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const ValueKey('comm-ai-share-email'),
        icon: _busy == 'email' ? _spin() : const Icon(NxI.paperPlaneTilt),
        label: Text(tr('ส่งอีเมล')),
        onPressed: _busy != null || _emails(_to.text).isEmpty || inc.isEmpty || (_logTo != null && _logTo!.record == null)
            ? null
            : () => _run('email', () async {
                  final log = _logTo;
                  final r = await api.shareConversationEmail(
                    widget.kind,
                    widget.id,
                    to: _emails(_to.text),
                    cc: _emails(_cc.text),
                    message: _note.text.trim(),
                    include: inc,
                    format: _format,
                    lang: _lang,
                    attachAudio: _attachAudio && _isCall && widget.hasAudio && _format != 'zip',
                    logTo: log?.record == null ? null : {'module': log!.module, 'record_id': int.tryParse(log.record!.value) ?? log.record!.value},
                  );
                  final activity = r['activity'] is Map ? r['activity'] as Map : null;
                  return [
                    tr('ส่งอีเมลแล้ว'),
                    if (r['audio'] == 'attached') tr('แนบไฟล์เสียงแล้ว'),
                    if (r['audio'] == 'link') tr('เสียงไฟล์ใหญ่ ส่งเป็นลิงก์'),
                    if (activity?['activity_id'] != null) tr('บันทึกเป็น Activity ในลูกค้าแล้ว'),
                    if (activity?['error'] != null) '${tr('บันทึกลง CRM ไม่สำเร็จ')}: ${activity!['error']}',
                  ].join(' · ');
                }),
      ),
    ];
  }

  List<Widget> _chatTab() {
    final api = context.read<AppConfig>().apiClient;
    return [
      _label('ส่งให้'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in _mates.entries)
          InputChip(
            key: ValueKey('comm-ai-share-mate-${e.key}'),
            label: Text(e.value),
            onDeleted: () => setState(() => _mates.remove(e.key)),
          ),
        ActionChip(
          key: const ValueKey('comm-ai-share-pick-mates'),
          avatar: const Icon(NxI.userPlus, size: 16),
          label: Text(tr(_mates.isEmpty ? 'เลือกเพื่อนร่วมทีม…' : 'เพิ่ม / แก้ไข')),
          onPressed: _pickMates,
        ),
      ]),
      const SizedBox(height: 10),
      TextField(
        key: const ValueKey('comm-ai-share-chat-note'),
        controller: _chatNote,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(labelText: tr('ข้อความ'), hintText: tr('เช่น ฝากดูงานที่ต้องทำต่อ'), alignLabelWithHint: true),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('comm-ai-share-chat'),
        icon: _busy == 'chat' ? _spin() : const Icon(NxI.chatCircle),
        label: Text(tr('ส่งในแชทส่วนตัว')),
        onPressed: _busy != null || _mates.isEmpty
            ? null
            : () => _run('chat', () async {
                  final ids = [for (final id in _mates.keys) ?int.tryParse(id)];
                  final r = await api.shareConversationToChat(widget.kind, widget.id, userIds: ids, message: _chatNote.text.trim());
                  final n = r['sent'] is List ? (r['sent'] as List).length : ids.length;
                  _mates.clear();
                  _chatNote.clear();
                  return tr('ส่งให้ $n คนในแชทแล้ว');
                }),
      ),
    ];
  }

  List<Widget> _crmTab() {
    final api = context.read<AppConfig>().apiClient;
    return [
      Text(tr('ISAAC จะบันทึกสรุปและงานที่ต้องทำต่อเป็น Activity บนไทม์ไลน์ของรายการที่เลือก'), style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
      const SizedBox(height: 12),
      CommAiCrmRecordPicker(value: _crm, onChanged: (v) => setState(() => _crm = v)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('comm-ai-crm-type'),
        isExpanded: true,
        initialValue: _crmType,
        decoration: InputDecoration(labelText: tr('บันทึกเป็น')),
        items: [
          DropdownMenuItem(value: 'Call', child: Text(tr('การโทร'))),
          DropdownMenuItem(value: 'Meeting', child: Text(tr('ประชุม'))),
          const DropdownMenuItem(value: 'Email', child: Text('Email')),
          const DropdownMenuItem(value: 'Task', child: Text('Task')),
        ],
        onChanged: (v) => setState(() => _crmType = v ?? _crmType),
      ),
      const SizedBox(height: 10),
      TextField(key: const ValueKey('comm-ai-crm-note'), controller: _crmNote, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('หมายเหตุ'), hintText: tr('ไม่บังคับ'), alignLabelWithHint: true)),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('comm-ai-share-crm'),
        icon: _busy == 'crm' ? _spin() : const Icon(NxI.buildings),
        label: Text(tr('บันทึกลง CRM')),
        onPressed: _busy != null || _crm.record == null
            ? null
            : () => _run('crm', () async {
                  final r = await api.shareConversationToCrm(widget.kind, widget.id, module: _crm.module, recordId: _crm.record!.value, activityType: _crmType, note: _crmNote.text.trim());
                  _activityId = r['activity_id']?.toString();
                  return tr('บันทึกลงไทม์ไลน์ลูกค้าแล้ว');
                }),
      ),
      if (_activityId != null && _activityId!.isNotEmpty)
        TextButton.icon(
          key: const ValueKey('comm-ai-crm-open-activity'),
          onPressed: () => nxPush<void>(context, ActivityByIdLoader(id: _activityId!)),
          icon: const Icon(NxI.arrowRight, size: 16),
          label: Text(tr('เปิด Activity ที่สร้าง')),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final theme = Theme.of(context);
    final tabs = <(String, String, IconData?)>[
      ('device', 'ไฟล์', NxI.shareNetwork),
      if (_emailOn) ('email', 'อีเมล', NxI.envelope),
      if (_linkOn) ('link', 'ลิงก์', NxI.link),
      ('chat', 'ทีม', NxI.chatCircle),
      ('crm', 'CRM', NxI.buildings),
    ];
    if (!tabs.any((t) => t.$1 == _tab)) _tab = 'device';
    final audioOk = _isCall && (_tab == 'link' || (widget.hasAudio && _format == 'zip' && _tab != 'chat' && _tab != 'crm'));
    final includeOptions = [
      ('summary', 'สรุป 4 หัวข้อ'),
      ('actions', 'งานที่ต้องทำต่อ'),
      ('transcript', 'บทสนทนา'),
      if (audioOk) ('audio', _tab == 'link' ? 'เสียง (ในลิงก์)' : 'เสียง (ใน ZIP)'),
    ];
    final inc = [for (final (k, _) in includeOptions) if (_include.contains(k)) k];
    final showInclude = _tab == 'device' || _tab == 'email' || _tab == 'link';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const IsaacTip('ISAAC แนะนำ: แชร์ให้ลูกค้าเลือกแค่ "สรุป" และ "งานที่ต้องทำต่อ" — บทสนทนาเต็มเก็บไว้ใช้ภายในทีม'),
      const SizedBox(height: 14),
      NxSlidingSegmented<String>(
          value: _tab,
          options: tabs,
          onChanged: (v) {
            setState(() {
              _tab = v;
              _msg = null;
            });
            if (v == 'email') _loadRecipients();
          }),
      const SizedBox(height: 14),
      if (showInclude) ...[
        _label('รวมอะไรบ้าง'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (k, label) in includeOptions)
            FilterChip(
              key: ValueKey('comm-ai-share-include-$k'),
              label: Text(tr(label)),
              selected: _include.contains(k),
              onSelected: (v) => setState(() => v ? _include.add(k) : _include.remove(k)),
            ),
        ]),
      ],
      if (_tab == 'device' || _tab == 'email') ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const ValueKey('comm-ai-share-format'),
              isExpanded: true,
              initialValue: _format,
              decoration: InputDecoration(labelText: tr('รูปแบบไฟล์')),
              items: [
                const DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                const DropdownMenuItem(value: 'docx', child: Text('Word (.docx)')),
                const DropdownMenuItem(value: 'md', child: Text('Markdown')),
                const DropdownMenuItem(value: 'txt', child: Text('Text')),
                DropdownMenuItem(value: 'zip', child: Text(tr('ZIP (PDF + Word + ข้อความ + เสียง)'), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _lang,
              decoration: InputDecoration(labelText: tr('ภาษาหัวข้อ')),
              items: const [DropdownMenuItem(value: 'th', child: Text('ไทย')), DropdownMenuItem(value: 'en', child: Text('English'))],
              onChanged: (v) => setState(() => _lang = v ?? _lang),
            ),
          ),
        ]),
      ],
      const SizedBox(height: 14),
      if (_tab == 'device')
        FilledButton.icon(
          key: const ValueKey('comm-ai-share-device'),
          icon: _busy == 'device' ? _spin() : const Icon(NxI.shareNetwork),
          label: Text(tr('แชร์ผ่านอุปกรณ์ (LINE, อีเมล, Drive…)')),
          onPressed: _busy != null || inc.isEmpty
              ? null
              : () => _run('device', () async {
                    final bytes = await api.exportConversation(widget.kind, widget.id, format: _format, include: inc, lang: _lang);
                    final dir = await getTemporaryDirectory();
                    final name = '${(widget.title ?? 'conversation').replaceAll(RegExp(r'[\\/:*?"<>|\n]'), ' ').trim()}.$_format';
                    final f = File('${dir.path}/${name.length > 80 ? '${name.substring(0, 76)}.$_format' : name}');
                    await f.writeAsBytes(bytes);
                    await Share.shareXFiles([XFile(f.path)], subject: widget.title);
                    return null;
                  }),
        ),
      if (_tab == 'email') ..._emailTab(inc),
      if (_tab == 'link') ...[
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _days.clamp(1, _maxDays),
              decoration: InputDecoration(labelText: tr('หมดอายุใน')),
              items: [for (final d in {1, 3, 7, 14, 30, _maxDays}.where((d) => d <= _maxDays).toList()..sort()) DropdownMenuItem(value: d, child: Text('$d ${tr('วัน')}'))],
              onChanged: (v) => setState(() => _days = v ?? _days),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('comm-ai-share-password'),
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('รหัสผ่าน'), hintText: tr('ไม่บังคับ')),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('comm-ai-share-link'),
          icon: _busy == 'link' ? _spin() : const Icon(NxI.link),
          label: Text(tr('สร้างลิงก์ภายนอก')),
          onPressed: _busy != null || inc.isEmpty
              ? null
              : () => _run('link', () async {
                    final r = await api.createConversationLink(widget.kind, widget.id, include: inc, days: _days, password: _password.text.trim());
                    final base = api.baseUrl.replaceAll(RegExp(r'/+$'), '');
                    _link = '$base${r['url_path']}';
                    await _loadLinks();
                    return null;
                  }),
        ),
        if (_link != null)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: SelectableText(_link!, key: const ValueKey('comm-ai-share-url'), maxLines: 2, style: const TextStyle(fontSize: 12.5))),
              IconButton(
                tooltip: tr('คัดลอก'),
                icon: const Icon(NxI.copySimple),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _link!));
                  setState(() => _msg = tr('คัดลอกลิงก์แล้ว'));
                },
              ),
              IconButton(tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork), onPressed: () => Share.share(_link!, subject: widget.title)),
            ]),
          ),
        if (_links.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('ลิงก์ที่เคยสร้าง'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          for (final l in _links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(l['revoked'] == true ? NxI.x : NxI.link, color: l['revoked'] == true ? theme.hintColor : kIsaacIndigo, size: 18),
              title: Text('${tr('หมดอายุ')} ${commAiWhen(l['expires_at'])}${l['has_password'] == true ? ' · ${tr('มีรหัสผ่าน')}' : ''}'),
              subtitle: Text('${tr('เปิดดู')} ${l['view_count'] ?? 0} ${tr('ครั้ง')}${l['revoked'] == true ? ' · ${tr('ยกเลิกแล้ว')}' : ''}'),
              trailing: l['revoked'] == true
                  ? null
                  : TextButton(
                      onPressed: () async {
                        try {
                          await api.revokeConversationLink((l['id'] as num).toInt());
                          await _loadLinks();
                        } catch (e) {
                          if (mounted) setState(() => _msg = formatApiError(e));
                        }
                      },
                      child: Text(tr('ยกเลิกลิงก์'), style: const TextStyle(color: Color(0xFFE11D48))),
                    ),
            ),
        ],
      ],
      if (_tab == 'chat') ..._chatTab(),
      if (_tab == 'crm') ..._crmTab(),
      if (_msg != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_msg!, key: const ValueKey('comm-ai-share-msg'), textAlign: TextAlign.center, style: TextStyle(color: _msgError ? theme.colorScheme.error : const Color(0xFF059669), fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}
