
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import '../calendar/activity_form_screen.dart';
import 'comm_ai_isaac.dart';

export 'comm_ai_share_sheet.dart';

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
/// Two columns on tablets, like the web. With [summaryId] the follow-up ticks are saved on the summary
/// (everyone who can read it sees the same ticks); the first state comes from `result.action_done`.
class CommAiSummaryView extends StatefulWidget {
  const CommAiSummaryView({super.key, required this.result, this.sourceNote, this.showSource = true, this.summaryId});
  final Map<String, dynamic> result;
  final String? sourceNote;
  final bool showSource;
  final String? summaryId;

  @override
  State<CommAiSummaryView> createState() => _CommAiSummaryViewState();
}

class _CommAiSummaryViewState extends State<CommAiSummaryView> {
  late final Set<int> _done = {
    for (final x in (widget.result['action_done'] is List ? widget.result['action_done'] as List : const [])) ?(x is num ? x.toInt() : int.tryParse('$x')),
  };
  bool _showLines = false;
  int? _focus;

  void _jump(int n) => setState(() {
        _showLines = true;
        _focus = n;
      });

  Future<void> _toggle(int index) async {
    final next = !_done.contains(index);
    setState(() => next ? _done.add(index) : _done.remove(index));
    final id = widget.summaryId;
    if (id == null || id.isEmpty || id == 'null') return;
    try {
      await context.read<AppConfig>().apiClient.setCommAiActionDone(id, index, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => next ? _done.remove(index) : _done.add(index));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

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
        for (final (i, a) in actions.indexed)
          InkWell(
            key: ValueKey('comm-ai-action-$i'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => _toggle(i),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_done.contains(i) ? NxI.checkSquare : Icons.check_box_outline_blank_rounded, size: 18, color: const Color(0xFF059669)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${a['text']}', style: TextStyle(decoration: _done.contains(i) ? TextDecoration.lineThrough : null, color: _done.contains(i) ? hint : null)),
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
        if (r['sentiment'] is Map || _strings(r['topics']).isNotEmpty) ...[CommAiSentimentRow(result: r), const SizedBox(height: 12)],
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

/// Customer sentiment chip + topic chips under the headline (labelled, never colour alone).
class CommAiSentimentRow extends StatelessWidget {
  const CommAiSentimentRow({super.key, required this.result});
  final Map<String, dynamic> result;

  static (String, Color) labelOf(String? label) => switch (label) {
        'positive' => ('😊 ลูกค้าพอใจ', const Color(0xFF047857)),
        'negative' => ('😟 ลูกค้าไม่พอใจ', const Color(0xFFBE123C)),
        _ => ('😐 ปกติ', const Color(0xFF475569)),
      };

  @override
  Widget build(BuildContext context) {
    final s = result['sentiment'] is Map ? Map<String, dynamic>.from(result['sentiment'] as Map) : null;
    final topics = _strings(result['topics']);
    final reason = '${s?['reason'] ?? ''}';
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget pill(String text, Color color, {Key? key}) => Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: dark ? 0.22 : 0.1), borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? Color.lerp(color, Colors.white, 0.55) : color)),
        );
    final (label, color) = labelOf(s?['label']?.toString());
    return Column(key: const ValueKey('comm-ai-sentiment'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (s != null) pill(tr(label), color, key: ValueKey('comm-ai-sentiment-${s['label']}')),
        for (final t in topics) pill('#$t', kIsaacIndigo),
      ]),
      if (reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, left: 2), child: Text(reason, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
    ]);
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
