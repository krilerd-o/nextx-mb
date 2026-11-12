import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../../widgets/nx_surface_card.dart';
import '../calendar/activity_form_screen.dart';
import 'comm_ai_isaac.dart';

/// Server time → "11/11/2569 10:05" in Thai time (Buddhist year when the UI is Thai).
String commAiWhen(dynamic raw, {bool withDate = true}) {
  final t = parseThai(raw);
  if (t == null) return '';
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (!withDate) return hm;
  return '${t.day}/${t.month}/${uiYear(t.year)} $hm';
}

/// ISAAC's one-line answer at the top of a summary.
class CommAiHeadline extends StatelessWidget {
  const CommAiHeadline(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: kIsaacGradient,
        boxShadow: const [BoxShadow(color: Color(0x336366F1), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        const IsaacAvatar(mood: 'answer_ready', size: 40, ring: false, animate: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ISAAC AI', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}

final _refRe = RegExp(r'\[#\s*(\d+(?:\s*,\s*#?\s*\d+)*)\s*\]');

/// Text with small "#n" chips that jump to the source line.
class _RefText extends StatelessWidget {
  const _RefText(this.text, {this.onRef});
  final String text;
  final void Function(int n)? onRef;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _refRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      for (final raw in m.group(1)!.split(',')) {
        final n = int.tryParse(raw.replaceAll(RegExp(r'[^\d]'), ''));
        if (n == null) continue;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: onRef == null ? null : () => onRef!(n),
            child: Container(
              margin: const EdgeInsets.only(left: 3),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: kIsaacIndigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text('#$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kIsaacIndigo)),
            ),
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: const TextStyle(height: 1.45));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.color, required this.title, required this.children});
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NxSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (children.isNotEmpty) Text('${children.length}', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]),
        const SizedBox(height: 10),
        if (children.isEmpty) Text(tr('ไม่มี'), style: TextStyle(color: Theme.of(context).hintColor)) else ...children,
      ]),
    );
  }
}

Widget _bullet(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 8, right: 8), child: CircleAvatar(radius: 2.5, backgroundColor: Color(0xFFCBD5E1))),
        Expanded(child: child),
      ]),
    );

List<String> _strings(dynamic v) => v is List ? [for (final x in v) '$x'] : const [];
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// 4 cards (key points / issues / follow-ups / recommendations) + ISAAC suggestions + source lines.
/// Two columns on tablets, like the web.
class CommAiSummaryView extends StatefulWidget {
  const CommAiSummaryView({super.key, required this.result, this.sourceNote, this.showSource = true});
  final Map<String, dynamic> result;
  final String? sourceNote;
  final bool showSource;

  @override
  State<CommAiSummaryView> createState() => _CommAiSummaryViewState();
}

class _CommAiSummaryViewState extends State<CommAiSummaryView> {
  final _done = <String>{};
  bool _showLines = false;
  int? _focus;

  void _jump(int n) => setState(() {
        _showLines = true;
        _focus = n;
      });

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final lines = _maps(r['lines']);
    final actions = _maps(r['action_items']);
    final suggestions = _maps(r['suggestions']);
    final hint = Theme.of(context).hintColor;
    final cards = <Widget>[
      _Section(icon: NxI.listBullets, color: kIsaacIndigo, title: tr('ใจความสำคัญ'), children: [for (final t in _strings(r['key_points'])) _bullet(_RefText(t, onRef: _jump))]),
      _Section(icon: NxI.chatCircle, color: const Color(0xFFD97706), title: tr('ประเด็นที่เกิดขึ้น'), children: [for (final t in _strings(r['discussion_points'])) _bullet(_RefText(t, onRef: _jump))]),
      _Section(icon: NxI.checkSquare, color: const Color(0xFF059669), title: tr('สิ่งที่ต้องทำต่อ'), children: [
        for (final a in actions)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _done.contains('${a['text']}') ? _done.remove('${a['text']}') : _done.add('${a['text']}')),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_done.contains('${a['text']}') ? NxI.checkSquare : Icons.check_box_outline_blank_rounded, size: 18, color: const Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${a['text']}', style: TextStyle(decoration: _done.contains('${a['text']}') ? TextDecoration.lineThrough : null, color: _done.contains('${a['text']}') ? hint : null)),
                    if (a['owner'] != null) TextSpan(text: '  ${a['owner']}', style: TextStyle(fontSize: 12, color: hint)),
                    if (a['due'] != null) TextSpan(text: '  ${a['due']}', style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48))),
                  ])),
                ),
              ]),
            ),
          ),
      ]),
      _Section(icon: NxI.lightning, color: kIsaacViolet, title: tr('คำแนะนำ'), children: [for (final t in _strings(r['recommendations'])) _bullet(_RefText(t, onRef: _jump))]),
    ];
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 620;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if ('${r['headline'] ?? ''}'.isNotEmpty) ...[CommAiHeadline('${r['headline']}'), const SizedBox(height: 12)],
        if (wide)
          for (var i = 0; i < cards.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: cards[i]),
                  const SizedBox(width: 10),
                  Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
                ]),
              ),
            )
        else
          for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kIsaacViolet.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kIsaacViolet.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const IsaacAvatar(mood: 'idea', size: 30, ring: false, animate: false),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('ISAAC แนะนำให้เปิดงาน'), style: const TextStyle(fontWeight: FontWeight.w800, color: kIsaacViolet))),
              ]),
              const SizedBox(height: 10),
              for (final s in suggestions) _SuggestionCard(s: s, sourceNote: widget.sourceNote),
            ]),
          ),
        ],
        if (widget.showSource && lines.isNotEmpty) ...[
          const SizedBox(height: 10),
          NxSurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () => setState(() => _showLines = !_showLines),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    const Icon(NxI.fileText, size: 16, color: kIsaacIndigo),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${tr('ข้อความอ้างอิง')} · ${lines.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text(_showLines ? tr('ซ่อน') : tr('แสดง'), style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ]),
                ),
              ),
              if (_showLines)
                for (final l in lines)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(color: _focus == l['n'] ? const Color(0x33F59E0B) : null, borderRadius: BorderRadius.circular(8)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 34, child: Text('#${l['n']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kIsaacIndigo))),
                      SizedBox(width: 44, child: Text('${l['at'] ?? ''}', style: TextStyle(fontSize: 11, color: hint))),
                      Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '${l['name']}: ', style: const TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: '${l['text']}')]))),
                    ]),
                  ),
            ]),
          ),
        ],
      ]);
    });
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.s, this.sourceNote});
  final Map<String, dynamic> s;
  final String? sourceNote;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final task = s['kind'] == 'workspace_task';
    return NxSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: kIsaacViolet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
          child: Icon(task ? NxI.checkSquare : NxI.calendarPlus, color: kIsaacViolet, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task ? tr('งานในทีม (Workspace)') : '${s['activitytype'] ?? 'Task'}${s['due'] != null ? ' · ${s['due']}' : ''}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kIsaacViolet)),
            Text('${s['subject']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if ('${s['reason'] ?? ''}'.isNotEmpty) Text('${s['reason']}', style: TextStyle(fontSize: 12, color: hint)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: ValueKey('comm-ai-create-${s['subject']}'),
          style: FilledButton.styleFrom(backgroundColor: kIsaacViolet, visualDensity: VisualDensity.compact),
          onPressed: () => createFromSuggestion(context, s, sourceNote: sourceNote),
          child: Text(tr('สร้าง')),
        ),
      ]),
    );
  }
}

/// ISAAC suggestion → prefilled form the user confirms (never created silently).
Future<void> createFromSuggestion(BuildContext context, Map<String, dynamic> s, {String? sourceNote}) async {
  final desc = [s['description'], if ('${s['reason'] ?? ''}'.isNotEmpty) '${tr('เหตุผล')}: ${s['reason']}', sourceNote].where((x) => x != null && '$x'.isNotEmpty).join('\n\n');
  if (s['kind'] == 'workspace_task') {
    await _workspaceTask(context, '${s['subject']}', desc);
    return;
  }
  final due = DateTime.tryParse('${s['due'] ?? ''}');
  await nxPush<bool>(
    context,
    ActivityFormScreen(
      title: tr('สร้างจากคำแนะนำ ISAAC'),
      initial: {'subject': '${s['subject']}', 'description': desc, 'activitytype': '${s['activitytype'] ?? 'Task'}'},
      start: due == null ? null : DateTime(due.year, due.month, due.day, 9),
    ),
  );
}

Future<void> _workspaceTask(BuildContext context, String title, String desc) async {
  final api = context.read<AppConfig>().apiClient;
  final boards = await api.getBoards(writable: true).catchError((_) => <Map<String, dynamic>>[]);
  if (!context.mounted) return;
  if (boards.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ยังไม่มีบอร์ดที่คุณสร้างงานได้'))));
    return;
  }
  final titleCtl = TextEditingController(text: title);
  final descCtl = TextEditingController(text: desc);
  var boardId = '${boards.first['id']}';
  final ok = await showAppBottomSheet<bool>(
    context: context,
    title: tr('สร้างงานใน Workspace'),
    child: StatefulBuilder(
      builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const IsaacTip('ISAAC เติมชื่องานและรายละเอียดจากบทสนทนาให้แล้ว — ตรวจแล้วกดสร้างได้เลย', mood: 'planning'),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: const ValueKey('comm-ai-task-board'),
          initialValue: boardId,
          decoration: InputDecoration(labelText: tr('บอร์ด'), prefixIcon: const Icon(NxI.squaresFour)),
          items: [for (final b in boards) DropdownMenuItem(value: '${b['id']}', child: Text('${b['name'] ?? b['code']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setS(() => boardId = v ?? boardId),
        ),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('comm-ai-task-title'), controller: titleCtl, decoration: InputDecoration(labelText: tr('ชื่องาน'))),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('comm-ai-task-desc'), controller: descCtl, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: tr('รายละเอียด'), alignLabelWithHint: true)),
        const SizedBox(height: 16),
        FilledButton.icon(icon: const Icon(NxI.checkSquare), onPressed: () => Navigator.of(ctx).pop(true), label: Text(tr('สร้างงาน'))),
      ]),
    ),
  );
  if (ok != true || !context.mounted) return;
  if (titleCtl.text.trim().isEmpty) return;
  try {
    await api.postBoardTask(boardId, title: titleCtl.text.trim(), description: descCtl.text);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างงานแล้ว'))));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
  }
}

/// Share / export a conversation: device share (file), e-mail, external link (with expiry, password, revoke).
Future<void> showCommAiShareSheet(BuildContext context, {required String kind, required String id, String? title}) {
  return showAppBottomSheet<void>(context: context, title: tr('แชร์บทสนทนา'), child: CommAiShareSheet(kind: kind, id: id, title: title));
}

class CommAiShareSheet extends StatefulWidget {
  const CommAiShareSheet({super.key, required this.kind, required this.id, this.title});
  final String kind;
  final String id;
  final String? title;

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
    super.dispose();
  }

  Future<void> _loadLinks() async {
    try {
      final list = await context.read<AppConfig>().apiClient.listConversationLinks(widget.kind, widget.id);
      if (mounted) setState(() => _links = list);
    } catch (_) {}
  }

  bool get _emailOn => _settings?['share_email_enabled'] != false;
  bool get _linkOn => _settings?['share_link_enabled'] != false;
  int get _maxDays => (_settings?['share_link_max_days'] as num?)?.toInt() ?? 30;

  List<String> _emails(String s) => s.split(RegExp(r'[,;\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

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

  Widget _spin() => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final theme = Theme.of(context);
    final inc = _include.toList();
    final tabs = <(String, String, IconData?)>[
      ('device', 'แชร์ไฟล์', NxI.shareNetwork),
      if (_emailOn) ('email', 'อีเมล', NxI.envelope),
      if (_linkOn) ('link', 'ลิงก์', NxI.link),
    ];
    if (!tabs.any((t) => t.$1 == _tab)) _tab = 'device';
    final includeOptions = [('summary', 'สรุป 4 หัวข้อ'), ('actions', 'งานที่ต้องทำต่อ'), ('transcript', 'บทสนทนา'), if (_tab == 'link' && widget.kind == 'call') ('audio', 'เสียง (ในลิงก์)')];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const IsaacTip('ISAAC แนะนำ: แชร์ให้ลูกค้าเลือกแค่ "สรุป" และ "งานที่ต้องทำต่อ" — บทสนทนาเต็มเก็บไว้ใช้ภายในทีม'),
      const SizedBox(height: 14),
      NxSlidingSegmented<String>(value: _tab, options: tabs, onChanged: (v) => setState(() {
            _tab = v;
            _msg = null;
            if (v != 'link') _include.remove('audio');
          })),
      const SizedBox(height: 14),
      Text(tr('รวมอะไรบ้าง'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, label) in includeOptions)
          FilterChip(
            label: Text(tr(label)),
            selected: _include.contains(k),
            onSelected: (v) => setState(() => v ? _include.add(k) : _include.remove(k)),
          ),
      ]),
      if (_tab != 'link') ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _format,
              decoration: InputDecoration(labelText: tr('รูปแบบไฟล์')),
              items: const [
                DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                DropdownMenuItem(value: 'docx', child: Text('Word (.docx)')),
                DropdownMenuItem(value: 'md', child: Text('Markdown')),
                DropdownMenuItem(value: 'txt', child: Text('Text')),
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
          onPressed: _busy != null || _include.isEmpty
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
      if (_tab == 'email') ...[
        TextField(
          key: const ValueKey('comm-ai-share-to'),
          controller: _to,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: tr('ถึง'), helperText: tr('คั่นหลายอีเมลด้วย ,'), prefixIcon: const Icon(NxI.envelope)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('comm-ai-share-cc'), controller: _cc, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'CC')),
        const SizedBox(height: 10),
        TextField(key: const ValueKey('comm-ai-share-note'), controller: _note, minLines: 2, maxLines: 5, decoration: InputDecoration(labelText: tr('ข้อความถึงผู้รับ'), hintText: tr('ไม่บังคับ'), alignLabelWithHint: true)),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('comm-ai-share-email'),
          icon: _busy == 'email' ? _spin() : const Icon(NxI.paperPlaneTilt),
          label: Text(tr('ส่งอีเมล')),
          onPressed: _busy != null || _emails(_to.text).isEmpty || _include.isEmpty
              ? null
              : () => _run('email', () async {
                    await api.shareConversationEmail(widget.kind, widget.id, to: _emails(_to.text), cc: _emails(_cc.text), message: _note.text.trim(), include: inc, format: _format, lang: _lang);
                    return tr('ส่งอีเมลแล้ว');
                  }),
        ),
      ],
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
          onPressed: _busy != null || _include.isEmpty
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
      if (_msg != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_msg!, textAlign: TextAlign.center, style: TextStyle(color: _msgError ? theme.colorScheme.error : const Color(0xFF059669), fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}
