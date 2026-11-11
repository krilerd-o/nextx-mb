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
import '../../widgets/nx_surface_card.dart';
import '../calendar/activity_form_screen.dart';

const _violet = Color(0xFF7C3AED);

/// Server time → "11/11/2569 10:05" in Thai time (Buddhist year when the UI is Thai).
String commAiWhen(dynamic raw, {bool withDate = true}) {
  final t = parseThai(raw);
  if (t == null) return '';
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (!withDate) return hm;
  return '${t.day}/${t.month}/${uiYear(t.year)} $hm';
}
const _indigo = Color(0xFF4F46E5);

/// Gradient header line of a summary.
class CommAiHeadline extends StatelessWidget {
  const CommAiHeadline(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
        boxShadow: const [BoxShadow(color: Color(0x336366F1), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(NxI.sparkle, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, height: 1.35))),
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
              decoration: BoxDecoration(color: _indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text('#$n', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _indigo)),
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
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (children.isNotEmpty) Text('${children.length}', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]),
        const SizedBox(height: 8),
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

/// 4 cards (key points / issues / follow-ups / recommendations) + suggestions + source lines.
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if ('${r['headline'] ?? ''}'.isNotEmpty) ...[CommAiHeadline('${r['headline']}'), const SizedBox(height: 10)],
      _Section(icon: NxI.listBullets, color: _indigo, title: tr('ใจความสำคัญ'), children: [for (final t in _strings(r['key_points'])) _bullet(_RefText(t, onRef: _jump))]),
      const SizedBox(height: 10),
      _Section(icon: NxI.chatCircle, color: const Color(0xFFD97706), title: tr('ประเด็นที่เกิดขึ้น'), children: [for (final t in _strings(r['discussion_points'])) _bullet(_RefText(t, onRef: _jump))]),
      const SizedBox(height: 10),
      _Section(icon: NxI.checkSquare, color: const Color(0xFF059669), title: tr('สิ่งที่ต้องทำต่อ'), children: [
        for (final a in actions)
          InkWell(
            onTap: () => setState(() => _done.contains('${a['text']}') ? _done.remove('${a['text']}') : _done.add('${a['text']}')),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_done.contains('${a['text']}') ? NxI.checkSquare : Icons.check_box_outline_blank_rounded, size: 18, color: const Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${a['text']}', style: TextStyle(decoration: _done.contains('${a['text']}') ? TextDecoration.lineThrough : null)),
                    if (a['owner'] != null) TextSpan(text: '  ${a['owner']}', style: TextStyle(fontSize: 12, color: hint)),
                    if (a['due'] != null) TextSpan(text: '  ${a['due']}', style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48))),
                  ])),
                ),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      _Section(icon: NxI.lightning, color: _violet, title: tr('คำแนะนำ'), children: [for (final t in _strings(r['recommendations'])) _bullet(_RefText(t, onRef: _jump))]),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(tr('AI แนะนำให้เปิดงาน'), style: const TextStyle(fontWeight: FontWeight.w700, color: _violet)),
        const SizedBox(height: 8),
        for (final s in suggestions)
          NxSurfaceCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(s['kind'] == 'workspace_task' ? NxI.checkSquare : NxI.calendarPlus, color: _violet),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['kind'] == 'workspace_task' ? tr('งานในทีม (Workspace)') : '${s['activitytype'] ?? 'Task'}${s['due'] != null ? ' · ${s['due']}' : ''}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _violet)),
                  Text('${s['subject']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ('${s['reason'] ?? ''}'.isNotEmpty) Text('${s['reason']}', style: TextStyle(fontSize: 12, color: hint)),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: ValueKey('comm-ai-create-${s['subject']}'),
                style: FilledButton.styleFrom(backgroundColor: _violet, visualDensity: VisualDensity.compact),
                onPressed: () => createFromSuggestion(context, s, sourceNote: widget.sourceNote),
                child: Text(tr('สร้าง')),
              ),
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
                    SizedBox(width: 34, child: Text('#${l['n']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _indigo))),
                    SizedBox(width: 44, child: Text('${l['at'] ?? ''}', style: TextStyle(fontSize: 11, color: hint))),
                    Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '${l['name']}: ', style: const TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: '${l['text']}')]))),
                  ]),
                ),
          ]),
        ),
      ],
    ]);
  }
}

/// AI suggestion → prefilled form the user confirms (never created silently).
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
      title: tr('สร้างจากคำแนะนำ AI'),
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
        DropdownButtonFormField<String>(
          initialValue: boardId,
          decoration: InputDecoration(labelText: tr('บอร์ด')),
          items: [for (final b in boards) DropdownMenuItem(value: '${b['id']}', child: Text('${b['name'] ?? b['code']}'))],
          onChanged: (v) => setS(() => boardId = v ?? boardId),
        ),
        const SizedBox(height: 10),
        TextField(controller: titleCtl, decoration: InputDecoration(labelText: tr('ชื่องาน'))),
        const SizedBox(height: 10),
        TextField(controller: descCtl, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: tr('รายละเอียด'))),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('สร้างงาน'))),
      ]),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await api.postBoardTask(boardId, title: titleCtl.text.trim(), description: descCtl.text);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างงานแล้ว'))));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
  }
}

/// Share / export a conversation: device share (file), e-mail, external link.
Future<void> showCommAiShareSheet(BuildContext context, {required String kind, required String id, String? title}) {
  return showAppBottomSheet<void>(context: context, title: tr('แชร์บทสนทนา'), child: _ShareSheet(kind: kind, id: id, title: title));
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.kind, required this.id, this.title});
  final String kind;
  final String id;
  final String? title;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _include = <String>{'summary', 'actions', 'transcript'};
  String _format = 'pdf';
  String? _busy;
  String? _msg;
  String? _link;
  final _to = TextEditingController();

  Future<void> _run(String what, Future<void> Function() fn) async {
    setState(() {
      _busy = what;
      _msg = null;
    });
    try {
      await fn();
    } catch (e) {
      _msg = formatApiError(e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final inc = _include.toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('รวมอะไรบ้าง'), style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, children: [
        for (final (k, label) in [('summary', 'สรุป 4 หัวข้อ'), ('actions', 'งานที่ต้องทำต่อ'), ('transcript', 'บทสนทนา')])
          FilterChip(
            label: Text(tr(label)),
            selected: _include.contains(k),
            onSelected: (v) => setState(() => v ? _include.add(k) : _include.remove(k)),
          ),
      ]),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'pdf', label: Text('PDF')), ButtonSegment(value: 'docx', label: Text('Word')), ButtonSegment(value: 'txt', label: Text('Text'))],
        selected: {_format},
        onSelectionChanged: (v) => setState(() => _format = v.first),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const ValueKey('comm-ai-share-device'),
        icon: _busy == 'device' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.shareNetwork),
        label: Text(tr('แชร์ผ่านอุปกรณ์ (LINE, อีเมล, Drive…)')),
        onPressed: _busy != null || _include.isEmpty
            ? null
            : () => _run('device', () async {
                  final bytes = await api.exportConversation(widget.kind, widget.id, format: _format, include: inc);
                  final dir = await getTemporaryDirectory();
                  final name = '${(widget.title ?? 'conversation').replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim()}.$_format';
                  final f = File('${dir.path}/$name');
                  await f.writeAsBytes(bytes);
                  await Share.shareXFiles([XFile(f.path)], subject: widget.title);
                }),
      ),
      const Divider(height: 28),
      TextField(controller: _to, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('ส่งอีเมลถึง (คั่นด้วย ,)'))),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: _busy == 'email' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.envelope),
        label: Text(tr('ส่งอีเมล')),
        onPressed: _busy != null || _to.text.trim().isEmpty
            ? null
            : () => _run('email', () async {
                  await api.shareConversationEmail(widget.kind, widget.id, to: _to.text.split(RegExp(r'[,;\s]+')).where((e) => e.isNotEmpty).toList(), include: inc, format: _format);
                  _msg = tr('ส่งอีเมลแล้ว');
                }),
      ),
      const Divider(height: 28),
      OutlinedButton.icon(
        icon: _busy == 'link' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.link),
        label: Text(tr('สร้างลิงก์ภายนอก (7 วัน)')),
        onPressed: _busy != null
            ? null
            : () => _run('link', () async {
                  final r = await api.createConversationLink(widget.kind, widget.id, include: inc, days: 7);
                  final base = api.baseUrl.replaceAll(RegExp(r'/+$'), '');
                  _link = '$base${r['url_path']}';
                }),
      ),
      if (_link != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(child: SelectableText(_link!, maxLines: 2)),
            IconButton(icon: const Icon(NxI.copySimple), onPressed: () => Clipboard.setData(ClipboardData(text: _link!))),
            IconButton(icon: const Icon(NxI.shareNetwork), onPressed: () => Share.share(_link!, subject: widget.title)),
          ]),
        ),
      if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, textAlign: TextAlign.center)),
    ]);
  }
}
