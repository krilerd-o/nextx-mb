import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'minutes_widgets.dart';

/// The system share sheet (tests replace it).
Future<void> Function(String path, String name) shareMinuteFile = (path, name) async {
  await Share.shareXFiles([XFile(path)], subject: name);
};

Future<void> Function(String text) shareMinuteText = (text) async {
  await Share.share(text);
};

/// Share a meeting: file (PDF / Word / text / subtitles / the recording), link (expiry, password, what to
/// show, download, who), or e-mail.
Future<void> showMinuteShareSheet(BuildContext context, {required MinuteMeeting meeting, List<String> langs = const []}) {
  return showAppBottomSheet<void>(context: context, title: tr('แชร์การประชุม'), child: MinuteSharePanel(meeting: meeting, langs: langs));
}

class MinuteSharePanel extends StatefulWidget {
  const MinuteSharePanel({super.key, required this.meeting, this.langs = const []});
  final MinuteMeeting meeting;
  final List<String> langs;
  @override
  State<MinuteSharePanel> createState() => _MinuteSharePanelState();
}

class _MinuteSharePanelState extends State<MinuteSharePanel> {
  int _tab = 0;
  late String _lang = widget.meeting.locale;
  final Set<String> _include = {'summary', 'actions'};
  bool _busy = false;
  String? _msg;

  // link
  int _days = 7;
  final _password = TextEditingController();
  bool _download = true;
  final _allowed = TextEditingController();
  List<Map<String, dynamic>> _links = const [];
  String? _newUrl;

  // email
  final _to = TextEditingController();
  final _note = TextEditingController();
  bool _withLink = false;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    _password.dispose();
    _allowed.dispose();
    _to.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    try {
      final l = await _api.getMinuteLinks(widget.meeting.id);
      if (mounted) setState(() => _links = l);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _msg = e is ApiEnvelopeException ? e.message : tr('ทำรายการไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) => _run(() async {
    final bytes = await _api.downloadMinuteExport(widget.meeting.id, format: format, lang: _lang, include: [..._include, if (format == 'srt' || format == 'vtt') 'transcript']);
    final dir = await getTemporaryDirectory();
    final safe = widget.meeting.title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), ' ').trim();
    final f = File('${dir.path}/${safe.isEmpty ? 'meeting' : safe}.$format');
    await f.writeAsBytes(bytes, flush: true);
    await shareMinuteFile(f.path, widget.meeting.title);
  });

  Future<void> _exportMedia() => _run(() async {
    final bytes = await _api.downloadMinuteMedia(widget.meeting.id);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/meeting-${widget.meeting.id}.${widget.meeting.video ? 'mp4' : 'm4a'}');
    await f.writeAsBytes(bytes, flush: true);
    await shareMinuteFile(f.path, widget.meeting.title);
  });

  Future<void> _createLink() => _run(() async {
    final r = await _api.createMinuteLink(widget.meeting.id, {
      'days': _days,
      if (_password.text.isNotEmpty) 'password': _password.text,
      'include': _include.toList(),
      'allow_download': _download,
      'allowed_emails': _allowed.text,
      'lang': _lang,
    });
    final url = '${r['url'] ?? ''}';
    setState(() => _newUrl = url);
    unawaited(Clipboard.setData(ClipboardData(text: url)).catchError((_) {}));
    if (mounted) setState(() => _msg = tr('สร้างลิงก์และคัดลอกแล้ว'));
    await _loadLinks();
  });

  Future<void> _email() => _run(() async {
    final to = [for (final e in _to.text.split(RegExp(r'[,;\s]+'))) if (e.contains('@')) e.trim()];
    if (to.isEmpty) throw ApiEnvelopeException(400, 'EMAIL', tr('กรุณาใส่อีเมลผู้รับ'));
    await _api.emailMinutes(widget.meeting.id, {'to': to, 'message': _note.text, 'include': _include.toList(), 'lang': _lang, 'format': 'pdf', 'with_link': _withLink});
    if (mounted) setState(() => _msg = '${tr('ส่งอีเมลแล้ว')}: ${to.join(', ')}');
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final langs = {widget.meeting.locale, ...widget.langs}.toList();
    return Column(
      key: const ValueKey('minute-share-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, icon: const Icon(NxI.downloadSimple, size: 16), label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('ไฟล์'), maxLines: 1, softWrap: false))),
            ButtonSegment(value: 1, icon: const Icon(NxI.link, size: 16), label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('ลิงก์'), maxLines: 1, softWrap: false))),
            ButtonSegment(value: 2, icon: const Icon(NxI.envelope, size: 16), label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('อีเมล'), maxLines: 1, softWrap: false))),
            ButtonSegment(value: 3, icon: const Icon(NxI.buildings, size: 16), label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('องค์กร'), maxLines: 1, softWrap: false))),
          ],
          selected: {_tab},
          // Four tabs on a phone: no extra check icon, so the labels stay on one line.
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact, textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13)),
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        if (_tab == 3) MinuteOrgSharePanel(meeting: widget.meeting),
        if (_tab != 3) ...[
        MinuteSectionTitle('สิ่งที่แชร์', icon: NxI.listChecks),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in const [('summary', 'สรุป'), ('actions', 'สิ่งที่ต้องทำ'), ('notes', 'โน้ต · บอร์ด'), ('chat', 'แชทในห้อง'), ('transcript', 'ข้อความถอดเสียง'), ('audio', 'เสียง / วิดีโอ')])
            if ((e.$1 != 'audio' || (_tab == 1 && widget.meeting.mediaUrl != null)) && (e.$1 != 'chat' || widget.meeting.source == 'room'))
              FilterChip(
                key: ValueKey('minute-share-inc-${e.$1}'),
                label: Text(tr(e.$2)),
                selected: _include.contains(e.$1),
                onSelected: (on) => setState(() => on ? _include.add(e.$1) : _include.remove(e.$1)),
              ),
        ]),
        if (langs.length > 1) ...[
          MinuteSectionTitle('ภาษา', icon: NxI.languages),
          Wrap(spacing: 6, children: [
            for (final l in langs) ChoiceChip(label: Text(tr(minuteLangLabel(l))), selected: _lang == l, onSelected: (_) => setState(() => _lang = l)),
          ]),
        ],
        const SizedBox(height: 8),
        if (_tab == 0) ..._fileTab(theme),
        if (_tab == 1) ..._linkTab(theme),
        if (_tab == 2) ..._emailTab(theme),
        ],
        if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, key: const ValueKey('minute-share-msg'), style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  List<Widget> _fileTab(ThemeData theme) => [
    MinuteSectionTitle('ดาวน์โหลด / ส่งต่อเป็นไฟล์', icon: NxI.file),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in const [('pdf', 'PDF', NxI.filePdf), ('docx', 'Word', NxI.fileDoc), ('md', 'Markdown', NxI.fileText), ('txt', 'ข้อความ', NxI.textAlignLeft), ('srt', 'ซับไตเติล SRT', NxI.textT), ('vtt', 'ซับไตเติล VTT', NxI.textT)])
        OutlinedButton.icon(key: ValueKey('minute-export-${f.$1}'), onPressed: _busy ? null : () => _export(f.$1), icon: Icon(f.$3, size: 16), label: Text(tr(f.$2))),
      if (widget.meeting.mediaUrl != null)
        OutlinedButton.icon(key: const ValueKey('minute-export-media'), onPressed: _busy ? null : _exportMedia, icon: Icon(widget.meeting.video ? NxI.videoCamera : NxI.microphone, size: 16), label: Text(tr(widget.meeting.video ? 'ไฟล์วิดีโอ' : 'ไฟล์เสียง'))),
    ]),
  ];

  List<Widget> _linkTab(ThemeData theme) => [
    MinuteSectionTitle('อายุลิงก์', icon: NxI.clockCountdown),
    Wrap(spacing: 6, children: [
      for (final d in const [1, 7, 30, 90]) ChoiceChip(key: ValueKey('minute-link-days-$d'), label: Text(d == 1 ? tr('1 วัน') : '$d ${tr('วัน')}'), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
    ]),
    const SizedBox(height: 10),
    TextField(key: const ValueKey('minute-link-password'), controller: _password, obscureText: true, decoration: InputDecoration(labelText: tr('รหัสผ่าน (ไม่บังคับ)'), border: const OutlineInputBorder(), isDense: true)),
    const SizedBox(height: 8),
    TextField(
      key: const ValueKey('minute-link-allowed'),
      controller: _allowed,
      decoration: InputDecoration(labelText: tr('จำกัดผู้เปิด (อีเมล หรือ @โดเมน, ไม่บังคับ)'), hintText: '@company.com', border: const OutlineInputBorder(), isDense: true),
    ),
    SwitchListTile(contentPadding: EdgeInsets.zero, value: _download, onChanged: (v) => setState(() => _download = v), title: Text(tr('อนุญาตให้ดาวน์โหลด'))),
    SizedBox(width: double.infinity, child: FilledButton.icon(key: const ValueKey('minute-link-create'), onPressed: _busy ? null : _createLink, icon: const Icon(NxI.link), label: Text(tr('สร้างลิงก์')))),
    if (_newUrl != null)
      Card(
        margin: const EdgeInsets.only(top: 10),
        child: ListTile(
          title: Text(_newUrl!, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton(icon: const Icon(NxI.shareNetwork), onPressed: () => shareMinuteText(_newUrl!)),
        ),
      ),
    if (_links.isNotEmpty) ...[
      MinuteSectionTitle('ลิงก์ที่สร้างไว้', icon: NxI.link),
      for (final l in _links)
        ListTile(
          key: ValueKey('minute-link-${l['id']}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(l['revoked'] == true ? NxI.unlink : NxI.link, size: 18),
          title: Text('${tr('หมดอายุ')} ${'${l['expires_at'] ?? ''}'.split('T').first}${l['has_password'] == true ? ' · ${tr('มีรหัสผ่าน')}' : ''}'),
          subtitle: Text('${tr('เปิดดู')} ${l['view_count'] ?? 0} ${tr('ครั้ง')}${l['revoked'] == true ? ' · ${tr('ยกเลิกแล้ว')}' : ''}'),
          trailing: l['revoked'] == true
              ? null
              : TextButton(
                  onPressed: () => _run(() async {
                    await _api.revokeMinuteLink('${l['id']}');
                    await _loadLinks();
                  }),
                  child: Text(tr('ยกเลิกลิงก์')),
                ),
        ),
    ],
  ];

  List<Widget> _emailTab(ThemeData theme) => [
    TextField(key: const ValueKey('minute-email-to'), controller: _to, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('ถึง'), hintText: 'a@company.com, b@company.com', border: const OutlineInputBorder(), isDense: true)),
    const SizedBox(height: 8),
    TextField(controller: _note, maxLines: 3, decoration: InputDecoration(labelText: tr('ข้อความ (ไม่บังคับ)'), border: const OutlineInputBorder(), isDense: true)),
    SwitchListTile(contentPadding: EdgeInsets.zero, value: _withLink, onChanged: (v) => setState(() => _withLink = v), title: Text(tr('แนบลิงก์เปิดดูออนไลน์ (7 วัน)')), subtitle: Text(tr('แนบ PDF ไปด้วยเสมอ'))),
    SizedBox(width: double.infinity, child: FilledButton.icon(key: const ValueKey('minute-email-send'), onPressed: _busy ? null : _email, icon: const Icon(NxI.paperPlaneTilt), label: Text(tr('ส่งอีเมล')))),
  ];
}

/// "ในองค์กร": share with a colleague, a role or everyone in this business (read only).
class MinuteOrgSharePanel extends StatefulWidget {
  const MinuteOrgSharePanel({super.key, required this.meeting});
  final MinuteMeeting meeting;
  @override
  State<MinuteOrgSharePanel> createState() => _MinuteOrgSharePanelState();
}

class _MinuteOrgSharePanelState extends State<MinuteOrgSharePanel> {
  List<Map<String, dynamic>>? _items;
  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _roles = const [];
  String _kind = 'user';
  final _q = TextEditingController();
  Timer? _debounce;
  String? _busy;
  String? _msg;

  ApiClient get _api => context.read<AppConfig>().apiClient;

  @override
  void initState() {
    super.initState();
    _load();
    _search();
    // Roles are listed for admins; others simply do not get the role option.
    _api.getRoles().then((r) {
      if (mounted) setState(() => _roles = r);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _api.getMinuteShares(widget.meeting.id);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() {
        _items = const [];
        _msg = e is ApiEnvelopeException ? e.message : null;
      });
    }
  }

  void _search() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final u = await _api.getUsers(q: _q.text.trim().isEmpty ? null : _q.text.trim(), limit: 20);
        if (mounted) setState(() => _users = u);
      } catch (_) {}
    });
  }

  bool _has(String type, Object? id) => (_items ?? const []).any((s) => s['type'] == type && '${s['target_id']}' == '${id ?? 0}');

  Future<void> _add(String type, [int? id]) async {
    setState(() {
      _busy = '$type:${id ?? 0}';
      _msg = null;
    });
    try {
      await _api.addMinuteShare(widget.meeting.id, type: type, targetId: id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _msg = e is ApiEnvelopeException ? e.message : tr('แชร์ไม่สำเร็จ'));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remove(Map<String, dynamic> s) async {
    setState(() => _busy = 'rm:${s['id']}');
    try {
      await _api.removeMinuteShare(widget.meeting.id, '${s['id']}');
      await _load();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static String _userName(Map<String, dynamic> u) {
    final n = [u['first_name'], u['last_name']].where((x) => x != null && '$x'.trim().isNotEmpty).join(' ').trim();
    return n.isNotEmpty ? n : '${u['user_name'] ?? u['email1'] ?? u['email'] ?? '#${u['id']}'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Column(
      key: const ValueKey('minute-org-share'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(tr('คนที่ได้รับแชร์จะเห็นบันทึกการประชุมนี้ในรายการของตัวเอง (ดูได้อย่างเดียว) — เฉพาะคนในธุรกิจนี้'), style: theme.textTheme.bodySmall),
        MinuteSectionTitle('แชร์ให้', icon: NxI.users),
        Wrap(spacing: 6, children: [
          ChoiceChip(label: Text(tr('เพื่อนร่วมงาน')), selected: _kind == 'user', onSelected: (_) => setState(() => _kind = 'user')),
          if (_roles.isNotEmpty) ChoiceChip(label: Text(tr('ตามบทบาท')), selected: _kind == 'role', onSelected: (_) => setState(() => _kind = 'role')),
          ChoiceChip(key: const ValueKey('minute-org-everyone'), label: Text(tr('ทุกคนในธุรกิจ')), selected: _kind == 'business', onSelected: (_) => setState(() => _kind = 'business')),
        ]),
        const SizedBox(height: 8),
        if (_kind == 'user') ...[
          TextField(controller: _q, onChanged: (_) => _search(), decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาชื่อหรืออีเมล…'), isDense: true)),
          for (final u in _users.take(20))
            ListTile(
              key: ValueKey('minute-org-user-${u['id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(NxI.user, size: 18),
              title: Text(_userName(u), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: _busy == 'user:${u['id']}'
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr(_has('user', u['id']) ? 'แชร์แล้ว' : 'แชร์'), style: TextStyle(color: theme.colorScheme.primary)),
              onTap: _has('user', u['id']) || _busy != null ? null : () => _add('user', int.tryParse('${u['id']}')),
            ),
        ],
        if (_kind == 'role')
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in _roles)
              FilterChip(label: Text('${r['name'] ?? ''}'), selected: _has('role', r['id']), onSelected: _has('role', r['id']) ? null : (_) => _add('role', int.tryParse('${r['id']}'))),
          ]),
        if (_kind == 'business')
          FilledButton.icon(
            key: const ValueKey('minute-org-everyone-share'),
            onPressed: _has('business', 0) || _busy != null ? null : () => _add('business'),
            icon: const Icon(NxI.buildings, size: 16),
            label: Text(tr(_has('business', 0) ? 'แชร์ให้ทุกคนแล้ว' : 'แชร์ให้ทุกคนในธุรกิจ')),
          ),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: theme.colorScheme.error))),
        MinuteSectionTitle('แชร์แล้ว', icon: NxI.checkCircle),
        if (items == null)
          const LinearProgressIndicator()
        else if (items.isEmpty)
          Text(tr('ยังไม่ได้แชร์ให้ใครในองค์กร'), style: theme.textTheme.bodySmall)
        else
          for (final s in items)
            ListTile(
              key: ValueKey('minute-org-share-${s['id']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(s['type'] == 'business' ? NxI.buildings : s['type'] == 'role' ? NxI.shield : NxI.user, size: 18),
              title: Text(s['type'] == 'business' ? tr('ทุกคนในธุรกิจ') : '${s['name'] ?? '#${s['target_id']}'}'),
              trailing: IconButton(tooltip: tr('เลิกแชร์'), icon: const Icon(NxI.trash, size: 18), onPressed: _busy != null ? null : () => _remove(s)),
            ),
      ],
    );
  }
}
