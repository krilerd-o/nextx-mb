import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import 'call_summary_screen.dart';
import 'comm_ai_history_screen.dart';
import 'comm_ai_isaac.dart';

/// Single hue for every magnitude bar (daily volume, topics) — one series, one colour.
const _barColor = kIsaacIndigo;
const _barActive = Color(0xFF3730A3);

/// /comm-ai/insights — ISAAC dashboard over calls and chat summaries: totals, customer sentiment, frequent topics,
/// open follow-ups (tick them here), daily volume and the busiest people. Admins (who see all conversations)
/// get the whole business; everyone else their own conversations.
class CommAiInsightsScreen extends StatefulWidget {
  const CommAiInsightsScreen({super.key});

  @override
  State<CommAiInsightsScreen> createState() => _CommAiInsightsScreenState();
}

class _CommAiInsightsScreenState extends State<CommAiInsightsScreen> {
  DateTimeRange? _range;
  Map<String, dynamic>? _data;
  String? _error;
  int _req = 0;
  final _ticked = <String>{};
  bool _allActions = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final my = ++_req;
    setState(() => _error = null);
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiInsights(
            from: _range == null ? null : _ymd(_range!.start),
            to: _range == null ? null : _ymd(_range!.end),
          );
      if (my != _req || !mounted) return;
      setState(() {
        _data = r;
        _ticked.clear();
      });
    } catch (e) {
      if (my == _req && mounted) setState(() => _error = formatApiError(e));
    }
  }

  Future<void> _pickRange() async {
    final now = thaiNow();
    final today = DateTime(now.year, now.month, now.day);
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: _range ?? DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
    );
    if (r == null || !mounted) return;
    setState(() => _range = r);
    _load();
  }

  Future<void> _tick(Map<String, dynamic> a) async {
    final key = '${a['summary_id']}:${a['index']}';
    setState(() => _ticked.add(key));
    try {
      await context.read<AppConfig>().apiClient.setCommAiActionDone('${a['summary_id']}', (a['index'] as num).toInt(), true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ticked.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  void _open(String kind, String ref, String summaryId) {
    nxPush<void>(context, kind == 'call' ? CallSummaryScreen(callId: ref) : ChatSummaryDetailScreen(id: summaryId));
  }

  static List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

  String _fmtYmd(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    return d == null ? '${v ?? ''}' : '${d.day}/${d.month}/${uiYear(d.year)}';
  }

  Widget _panel(String title, Widget child, {Key? key, IconData? icon}) => NxSurfaceCard(
        key: key,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: kIsaacIndigo), const SizedBox(width: 6)],
            Expanded(child: Text(tr(title), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _tiles(Map<String, dynamic> t) {
    String n(dynamic v) {
      final x = (v as num?)?.toInt() ?? 0;
      final s = '$x';
      return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    }

    final tiles = [
      (NxI.phone, 'สายโทร', n(t['calls']), 'calls'),
      (NxI.videoCamera, 'วิดีโอคอล', n(t['video_calls']), 'video_calls'),
      (NxI.chatCircle, 'สรุปแชท', n(t['chat_summaries']), 'chat_summaries'),
      (NxI.clock, 'นาทีที่ถอดเสียง', n(t['minutes_transcribed']), 'minutes_transcribed'),
      (NxI.microphone, 'มีเทปเสียง', n(t['with_audio']), 'with_audio'),
      (NxI.checkSquare, 'งานค้างจากการคุย', n(t['open_actions']), 'open_actions'),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 6 : c.maxWidth >= 560 ? 3 : 2;
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      final theme = Theme.of(context);
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (icon, label, value, key) in tiles)
          SizedBox(
            width: w,
            child: NxSurfaceCard(
              key: ValueKey('comm-ai-insights-tile-$key'),
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(color: kIsaacIndigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, size: 15, color: kIsaacIndigo),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr(label), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant))),
                ]),
                const SizedBox(height: 8),
                Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
          ),
      ]);
    });
  }

  Widget _actions(List<Map<String, dynamic>> open) {
    final hint = Theme.of(context).hintColor;
    if (open.isEmpty) {
      return const CommAiIsaacState(mood: 'celebrate', title: 'ไม่มีงานค้าง เยี่ยมมาก!', size: 64);
    }
    final shown = _allActions ? open : open.take(8).toList();
    return Column(key: const ValueKey('comm-ai-insights-actions'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final a in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              key: ValueKey('comm-ai-insights-tick-${a['summary_id']}-${a['index']}'),
              value: false,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => _tick(a),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${a['text']}'),
                    if (a['owner'] != null) TextSpan(text: '  ${a['owner']}', style: TextStyle(fontSize: 12, color: hint)),
                    if (a['due'] != null) TextSpan(text: '  ${a['due']}', style: const TextStyle(fontSize: 12, color: Color(0xFFE11D48))),
                  ])),
                  InkWell(
                    onTap: () => _open('${a['kind']}', '${a['ref']}', '${a['summary_id']}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Icon(a['kind'] == 'call' ? NxI.phone : NxI.chatCircle, size: 13, color: kIsaacIndigo),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text('${(a['headline'] ?? '').toString().isEmpty ? tr('เปิดบทสนทนา') : a['headline']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kIsaacIndigo)),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      if (open.length > 8)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _allActions = !_allActions),
            child: Text(_allActions ? tr('ย่อ') : '${tr('ดูทั้งหมด')} (${open.length})'),
          ),
        ),
    ]);
  }

  Widget _people(List<Map<String, dynamic>> people) {
    final hint = Theme.of(context).hintColor;
    return Column(children: [
      for (final p in people)
        InkWell(
          key: ValueKey('comm-ai-insights-person-${p['user_id']}'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => nxPush<void>(context, CommAiHistoryScreen(initialUserId: '${p['user_id']}')),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(children: [
              Expanded(child: Text('${p['name']}', overflow: TextOverflow.ellipsis)),
              Text('${p['count']} ${tr('สาย')}', style: TextStyle(color: hint, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final theme = Theme.of(context);
    final rows = <Widget>[];
    final scope = d == null ? '' : ' · ${_fmtYmd(d['from'])} – ${_fmtYmd(d['to'])} · ${d['scope'] == 'business' ? tr('ทั้งธุรกิจ') : tr('เฉพาะของฉัน')}';
    rows.add(CommAiHero(
      mood: 'analyzing',
      title: 'แดชบอร์ดไอแซค การสื่อสาร',
      subtitle: '${tr('งานค้างจากการคุย ความรู้สึกลูกค้า และหัวข้อที่ถูกพูดถึงบ่อย')}$scope',
      footer: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          key: const ValueKey('comm-ai-insights-range'),
          avatar: const Icon(NxI.calendarBlank, size: 16),
          label: Text(_range == null ? tr('30 วันล่าสุด') : '${_range!.start.day}/${_range!.start.month} – ${_range!.end.day}/${_range!.end.month}/${uiYear(_range!.end.year)}'),
          selected: _range != null,
          showCheckmark: false,
          onPressed: _pickRange,
          onDeleted: _range == null
              ? null
              : () {
                  setState(() => _range = null);
                  _load();
                },
        ),
      ),
    ));
    rows.add(const SizedBox(height: 12));
    if (_error != null) {
      rows.add(CommAiIsaacState(mood: 'error', title: 'โหลดแดชบอร์ดไม่ได้', message: _error, action: OutlinedButton(onPressed: _load, child: Text(tr('ลองใหม่')))));
    } else if (d == null) {
      rows.add(const NxSkeletonList(rows: 4));
    } else {
      final totals = d['totals'] is Map ? Map<String, dynamic>.from(d['totals'] as Map) : <String, dynamic>{};
      final open = [for (final a in _maps(d['open_actions'])) if (!_ticked.contains('${a['summary_id']}:${a['index']}')) a];
      final sentiment = d['sentiment'] is Map ? Map<String, dynamic>.from(d['sentiment'] as Map) : <String, dynamic>{};
      final negatives = _maps(d['negative_examples']);
      final topics = _maps(d['topics']);
      final people = _maps(d['people']);
      final left = <Widget>[
        _panel('${tr('งานที่ต้องทำต่อที่ยังค้าง')} (${open.length})', _actions(open), icon: NxI.checkSquare),
        _panel('จำนวนการสนทนาต่อวัน', CommAiDailyBars(rows: _maps(d['daily'])), icon: NxI.chartBar),
      ];
      final right = <Widget>[
        _panel(
          'ความรู้สึกลูกค้า',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CommAiSentimentBar(data: sentiment),
            if (negatives.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(tr('ที่ควรติดตาม'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.hintColor)),
              const SizedBox(height: 6),
              for (final n in negatives)
                NxSurfaceCard(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  color: const Color(0xFFE11D48).withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.05),
                  onTap: () => _open('${n['kind']}', '${n['ref']}', '${n['ref']}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${n['headline']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if ('${n['reason'] ?? ''}'.isNotEmpty) Text('${n['reason']}', style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  ]),
                ),
            ],
          ]),
          icon: NxI.smiley,
        ),
        _panel(
          'หัวข้อที่ถูกพูดถึงบ่อย',
          topics.isEmpty
              ? Text(tr('ยังไม่มีหัวข้อ (สรุปใหม่จะมีอัตโนมัติ)'), style: TextStyle(color: theme.hintColor))
              : CommAiTopicBars(topics: topics, onTap: (t) => nxPush<void>(context, CommAiHistoryScreen(initialQuery: t))),
          icon: NxI.hash,
        ),
        if (people.isNotEmpty) _panel(d['scope'] == 'business' ? 'คนที่คุยบ่อย' : 'คนที่คุยด้วยบ่อย', _people(people), icon: NxI.users),
      ];
      rows.add(_tiles(totals));
      rows.add(const SizedBox(height: 12));
      rows.add(LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 900) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 7, child: Column(children: left)),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: Column(children: right)),
          ]);
        }
        return Column(children: [...left, ...right]);
      }));
    }
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'แดชบอร์ดไอแซค',
        subtitle: 'ไอแซคเอไอ',
      ),
      body: NxRefresh(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('comm-ai-insights'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: rows,
        ),
      ),
    );
  }
}

/// Positive / neutral / negative as one stacked bar: 2px gaps between segments, every segment named in the
/// legend with its count and share (never colour alone). Tap a segment or a legend row to read its value.
class CommAiSentimentBar extends StatefulWidget {
  const CommAiSentimentBar({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  State<CommAiSentimentBar> createState() => _CommAiSentimentBarState();
}

class _CommAiSentimentBarState extends State<CommAiSentimentBar> {
  String? _focus;

  static const parts = [
    ('positive', 'พอใจ', Color(0xFF059669)),
    ('neutral', 'ปกติ', Color(0xFF94A3B8)),
    ('negative', 'ไม่พอใจ', Color(0xFFE11D48)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int v(String k) => (widget.data[k] as num?)?.toInt() ?? 0;
    final total = parts.fold<int>(0, (s, p) => s + v(p.$1));
    if (total == 0) {
      return Text(tr('ยังไม่มีข้อมูลความรู้สึก (สรุปใหม่จะมีอัตโนมัติ)'), style: TextStyle(color: theme.hintColor));
    }
    int pct(int n) => (n * 100 / total).round();
    final focus = _focus == null ? null : parts.firstWhere((p) => p.$1 == _focus);
    final shown = [for (final p in parts) if (v(p.$1) > 0) p];
    return Column(key: const ValueKey('comm-ai-insights-sentiment'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 18,
        child: Text(
          focus == null ? '${tr('ทั้งหมด')} $total' : '${tr(focus.$2)}: ${v(focus.$1)} (${pct(v(focus.$1))}%)',
          key: const ValueKey('comm-ai-insights-sentiment-value'),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      const SizedBox(height: 4),
      Semantics(
        label: [for (final p in parts) '${tr(p.$2)} ${v(p.$1)}'].join(', '),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (final (i, p) in shown.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: v(p.$1),
                  child: GestureDetector(
                    key: ValueKey('comm-ai-insights-sentiment-${p.$1}'),
                    onTap: () => setState(() => _focus = _focus == p.$1 ? null : p.$1),
                    child: Container(color: _focus == null || _focus == p.$1 ? p.$3 : p.$3.withValues(alpha: 0.35)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final p in parts)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _focus = _focus == p.$1 ? null : p.$1),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(tr(p.$2), style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text('${v(p.$1)} · ${pct(v(p.$1))}%', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ]),
    ]);
  }
}

/// Conversations per day — one series, one hue; tap a bar to read its date and value.
class CommAiDailyBars extends StatefulWidget {
  const CommAiDailyBars({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  State<CommAiDailyBars> createState() => _CommAiDailyBarsState();
}

class _CommAiDailyBarsState extends State<CommAiDailyBars> {
  int? _hover;

  String _day(dynamic v) {
    final d = DateTime.tryParse('$v');
    return d == null ? '$v' : '${d.day}/${d.month}/${uiYear(d.year)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = widget.rows;
    if (rows.isEmpty) return Text(tr('ไม่มีข้อมูลในช่วงนี้'), style: TextStyle(color: theme.hintColor));
    int c(Map<String, dynamic> r) => (r['count'] as num?)?.toInt() ?? 0;
    final max = rows.map(c).fold<int>(1, (a, b) => b > a ? b : a);
    final h = _hover == null ? null : rows[_hover!];
    final caption = h == null ? '${tr('สูงสุด')} $max ${tr('รายการ/วัน')}' : '${_day(h['date'])} · ${c(h)} ${tr('รายการ')}';
    return Column(key: const ValueKey('comm-ai-insights-daily'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(caption, key: const ValueKey('comm-ai-insights-daily-value'), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 8),
      Container(
        height: 120,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < rows.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('comm-ai-insights-day-${rows[i]['date']}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _hover = _hover == i ? null : i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: (c(rows[i]) / max).clamp(0.04, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _hover == i ? _barActive : _barColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Text(_day(rows.first['date']), style: TextStyle(fontSize: 11, color: theme.hintColor)),
        const Spacer(),
        Text(_day(rows.last['date']), style: TextStyle(fontSize: 11, color: theme.hintColor)),
      ]),
    ]);
  }
}

/// Frequent topics: horizontal bars in one hue with the count at the end; tap → history search for the topic.
class CommAiTopicBars extends StatelessWidget {
  const CommAiTopicBars({super.key, required this.topics, this.onTap});
  final List<Map<String, dynamic>> topics;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int c(Map<String, dynamic> r) => (r['count'] as num?)?.toInt() ?? 0;
    final max = topics.map(c).fold<int>(1, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final t in topics)
        InkWell(
          key: ValueKey('comm-ai-insights-topic-${t['topic']}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap == null ? null : () => onTap!('${t['topic']}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 110, child: Text('${t['topic']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (c(t) / max).clamp(0.03, 1.0),
                    child: Container(height: 8, decoration: BoxDecoration(color: _barColor, borderRadius: BorderRadius.circular(4))),
                  ),
                ),
              ),
              SizedBox(width: 32, child: Text('${c(t)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]))),
            ]),
          ),
        ),
    ]);
  }
}
