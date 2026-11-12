import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_list_toolbar.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../widgets/nx_surface_card.dart';
import 'call_summary_screen.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_widgets.dart';

/// Communication → ประวัติ AI การสนทนา: every call ISAAC took notes on and every chat summary.
/// Search inside transcripts and summaries, filter by type and Thai date range. Tablets: list + detail.
class CommAiHistoryScreen extends StatefulWidget {
  const CommAiHistoryScreen({super.key});

  @override
  State<CommAiHistoryScreen> createState() => _CommAiHistoryScreenState();
}

const _typeGroup = NxFilterGroup(key: 'type', label: 'ประเภท', multi: false, options: [
  NxFilterOption('call', 'โทร'),
  NxFilterOption('video', 'วิดีโอคอล'),
  NxFilterOption('chat', 'สรุปแชท'),
]);

class _CommAiHistoryScreenState extends State<CommAiHistoryScreen> {
  NxListQuery _query = const NxListQuery();
  DateTimeRange? _range;
  final _items = <Map<String, dynamic>>[];
  String? _next;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int _req = 0;
  Map<String, dynamic>? _selected;

  String get _type => _query.single('type') ?? 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load({String? before}) async {
    final my = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiHistory(
            type: _type,
            q: _query.q,
            from: _range == null ? null : _ymd(_range!.start),
            to: _range == null ? null : _ymd(_range!.end),
            before: before,
          );
      if (my != _req || !mounted) return;
      final list = [for (final x in (r['list'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      setState(() {
        if (before == null) _items.clear();
        _items.addAll(list);
        _next = r['next_before']?.toString();
        _loaded = true;
      });
    } catch (e) {
      if (my == _req && mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (my == _req && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final now = thaiNow();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range ?? DateTimeRange(start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)), end: DateTime(now.year, now.month, now.day)),
    );
    if (r == null || !mounted) return;
    setState(() => _range = r);
    _load();
  }

  void _open(Map<String, dynamic> it) {
    if (NxBreakpoint.of(context).twoPane) {
      setState(() => _selected = it);
      return;
    }
    nxPush<void>(context, _detailFor(it));
  }

  Widget _detailFor(Map<String, dynamic> it) => it['type'] == 'chat' ? ChatSummaryDetailScreen(id: '${it['id']}') : CallSummaryScreen(callId: '${it['id']}');

  Widget _tile(Map<String, dynamic> it, Color hint) {
    final type = '${it['type']}';
    final color = type == 'video' ? const Color(0xFF6366F1) : type == 'chat' ? const Color(0xFFA855F7) : const Color(0xFF10B981);
    final icon = type == 'video' ? NxI.videoCamera : type == 'chat' ? NxI.chatCircle : NxI.phone;
    final people = [for (final p in (it['participants'] as List? ?? const [])) if (p is Map) '${p['name']}'];
    final dur = (it['duration_s'] as num?) ?? 0;
    final sub = [
      commAiWhen(it['at'], withDate: false),
      if ('${it['room_name'] ?? ''}'.isNotEmpty) '${it['room_name']}',
      if (type != 'chat' && dur != 0) '${dur ~/ 60}:${(dur % 60).toInt().toString().padLeft(2, '0')}',
      if (type == 'chat') '${it['message_count'] ?? 0} ${tr('ข้อความ')}',
      if (it['has_audio'] == true) '🎙 ${tr('มีเสียง')}',
    ].join(' · ');
    final selected = _selected != null && '${_selected!['type']}:${_selected!['id']}' == '$type:${it['id']}';
    final pending = it['summary_status'] == 'pending';
    return NxSurfaceCard(
      key: ValueKey('comm-ai-history-$type-${it['id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      onTap: () => _open(it),
      child: Container(
        decoration: selected ? const BoxDecoration(border: Border(left: BorderSide(color: kIsaacIndigo, width: 3))) : null,
        padding: selected ? const EdgeInsets.only(left: 8) : null,
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.12)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${it['headline'] ?? (type == 'chat' ? tr('สรุปแชท') : pending ? tr('ISAAC กำลังสรุป…') : tr('บทสนทนา (ยังไม่มีสรุป)'))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
              ),
              const SizedBox(height: 3),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
              if (people.isNotEmpty) Text(people.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: hint)),
            ]),
          ),
          if ((it['action_count'] ?? 0) != 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0x1A10B981), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(NxI.checkSquare, size: 13, color: Color(0xFF059669)),
                const SizedBox(width: 3),
                Text('${it['action_count']}', style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w700)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final rows = <Widget>[
      const CommAiHero(
        mood: 'organize_data',
        title: 'ประวัติ AI การสนทนา',
        subtitle: 'ทุกสายที่ ISAAC จดไว้ และทุกสรุปแชท — ค้นหาได้ทั้งในบทสนทนาและในสรุป',
      ),
      const SizedBox(height: 8),
    ];
    String? lastDay;
    for (final it in _items) {
      final t = parseThai(it['at']);
      final day = t == null ? '' : '${t.day}/${t.month}/${uiYear(t.year)}';
      if (day != lastDay) {
        lastDay = day;
        final n = thaiNow();
        final y = n.subtract(const Duration(days: 1));
        final label = t != null && t.year == n.year && t.month == n.month && t.day == n.day
            ? tr('วันนี้')
            : t != null && t.year == y.year && t.month == y.month && t.day == y.day
                ? tr('เมื่อวาน')
                : day;
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 6), child: Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))));
      }
      rows.add(_tile(it, hint));
    }
    if (_error != null) {
      rows.add(CommAiIsaacState(mood: 'error', title: 'โหลดประวัติไม่ได้', message: _error, action: OutlinedButton(onPressed: _load, child: Text(tr('ลองใหม่')))));
    } else if (_loading && _items.isEmpty) {
      rows.add(const NxSkeletonList(rows: 5));
    } else if (_loading) {
      rows.add(const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
    } else if (_loaded && _items.isEmpty) {
      final filtered = _query.q.isNotEmpty || _range != null || _type != 'all';
      rows.add(CommAiIsaacState(
        mood: filtered ? 'searching' : 'sleepy',
        title: filtered ? 'ISAAC ไม่พบรายการที่ตรงกัน' : 'ยังไม่มีประวัติ',
        message: filtered ? 'ลองเปลี่ยนคำค้นหรือช่วงวันที่' : 'เปิด "จดบทสนทนา" ตอนโทร หรือกด ✨ ในห้องแชทเพื่อให้ ISAAC สรุป',
        action: filtered
            ? OutlinedButton(
                onPressed: () {
                  setState(() {
                    _query = const NxListQuery();
                    _range = null;
                  });
                  _load();
                },
                child: Text(tr('ล้างตัวกรอง')),
              )
            : null,
      ));
    }
    return Column(children: [
      NxListToolbar(
        query: _query,
        searchHint: 'ค้นหาในบทสนทนาและสรุป เช่น ชื่อลูกค้า สินค้า',
        groups: const [_typeGroup],
        quickGroup: 'type',
        allowSavedViews: false,
        leading: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InputChip(
              key: const ValueKey('comm-ai-history-range'),
              avatar: const Icon(NxI.calendarBlank, size: 16),
              label: Text(_range == null ? tr('ทุกวันที่') : '${_range!.start.day}/${_range!.start.month} – ${_range!.end.day}/${_range!.end.month}/${uiYear(_range!.end.year)}'),
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
        ],
        onChanged: (q) {
          final reload = q.q != _query.q || q.single('type') != _query.single('type');
          setState(() => _query = q);
          if (reload) _load();
        },
      ),
      Expanded(
        child: NxRefresh(
          onRefresh: () => _load(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 400 && !_loading && _next != null && _error == null) _load(before: _next);
              return false;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: rows,
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'ประวัติ AI การสนทนา',
        subtitle: 'ISAAC AI',
        actions: [
          IconButton(
            key: const ValueKey('comm-ai-open-settings'),
            tooltip: tr('ตั้งค่า ISAAC AI การสื่อสาร'),
            icon: const Icon(NxI.gear),
            onPressed: () => context.push(AppRoutes.commAiSettings),
          ),
        ],
      ),
      body: NxSplitView(
        onClose: () => setState(() => _selected = null),
        empty: const Center(child: CommAiIsaacState(mood: 'reading', title: 'เลือกรายการทางซ้าย', message: 'ISAAC จะแสดงสรุปและบทสนทนาตรงนี้')),
        detail: _selected == null
            ? null
            : NxPaneHost(
                key: ValueKey('comm-ai-pane-${_selected!['type']}-${_selected!['id']}'),
                onPopRoot: () => setState(() => _selected = null),
                child: _detailFor(_selected!),
              ),
        list: _list(context),
      ),
    );
  }
}

/// One saved chat summary (from history or a shared link inside the app).
class ChatSummaryDetailScreen extends StatelessWidget {
  const ChatSummaryDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: context.read<AppConfig>().apiClient.getCommAiSummary(id),
      builder: (context, snap) {
        final r = snap.data?['result'] is Map ? Map<String, dynamic>.from(snap.data!['result'] as Map) : null;
        final range = snap.data == null ? '' : '${commAiWhen(snap.data!['range_from'])} – ${commAiWhen(snap.data!['range_to'])}';
        return NxScrollScaffold(
          header: NxAppHeader(
            title: 'ISAAC สรุปแชท',
            subtitle: range,
            actions: [
              if (r != null)
                IconButton(
                  key: const ValueKey('chat-summary-share'),
                  tooltip: tr('แชร์'),
                  icon: const Icon(NxI.shareNetwork),
                  onPressed: () => showCommAiShareSheet(context, kind: 'chat', id: id, title: '${r['headline'] ?? ''}'),
                ),
            ],
          ),
          body: snap.hasError
              ? Center(child: CommAiIsaacState(mood: 'error', title: 'เปิดสรุปไม่ได้', message: formatApiError(snap.error!)))
              : r == null
                  ? const Center(child: CommAiIsaacState(mood: 'reading', title: 'ISAAC กำลังเปิดสรุป…', busy: true))
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [CommAiSummaryView(result: r)]),
        );
      },
    );
  }
}
