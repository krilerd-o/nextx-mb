import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import 'call_summary_screen.dart';
import 'comm_ai_widgets.dart';

/// Communication → ประวัติ AI การสนทนา: calls / video calls with notes and chat summaries.
class CommAiHistoryScreen extends StatefulWidget {
  const CommAiHistoryScreen({super.key});

  @override
  State<CommAiHistoryScreen> createState() => _CommAiHistoryScreenState();
}

class _CommAiHistoryScreenState extends State<CommAiHistoryScreen> {
  String _type = 'all';
  String _q = '';
  final _items = <Map<String, dynamic>>[];
  String? _next;
  bool _loading = false;
  String? _error;
  int _req = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 && !_loading && _next != null) _load(before: _next);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({String? before}) async {
    final my = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiHistory(type: _type, q: _q, before: before);
      if (my != _req || !mounted) return;
      final list = [for (final x in (r['list'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
      setState(() {
        if (before == null) _items.clear();
        _items.addAll(list);
        _next = r['next_before']?.toString();
      });
    } catch (e) {
      if (my == _req && mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (my == _req && mounted) setState(() => _loading = false);
    }
  }

  void _open(Map<String, dynamic> it) {
    if (it['type'] == 'chat') {
      nxPush<void>(context, _ChatSummaryDetail(id: '${it['id']}'));
    } else {
      nxPush<void>(context, CallSummaryScreen(callId: '${it['id']}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    String? lastDay;
    final children = <Widget>[];
    for (final it in _items) {
      final t = parseThai(it['at']);
      final day = t == null ? '' : '${t.day}/${t.month}/${uiYear(t.year)}';
      if (day != lastDay) {
        lastDay = day;
        final n = thaiNow();
        final label = t != null && t.year == n.year && t.month == n.month && t.day == n.day ? tr('วันนี้') : day;
        children.add(Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: hint, fontSize: 12))));
      }
      final type = '${it['type']}';
      final color = type == 'video' ? const Color(0xFF6366F1) : type == 'chat' ? const Color(0xFFA855F7) : const Color(0xFF10B981);
      final icon = type == 'video' ? NxI.videoCamera : type == 'chat' ? NxI.chatCircle : NxI.phone;
      final people = [for (final p in (it['participants'] as List? ?? const [])) if (p is Map) '${p['name']}'];
      final sub = [
        commAiWhen(it['at'], withDate: false),
        if ('${it['room_name'] ?? ''}'.isNotEmpty) '${it['room_name']}',
        if (type != 'chat' && (it['duration_s'] ?? 0) != 0) '${(it['duration_s'] as num) ~/ 60}:${((it['duration_s'] as num) % 60).toInt().toString().padLeft(2, '0')}',
        if (type == 'chat') '${it['message_count']} ${tr('ข้อความ')}',
        if (it['has_audio'] == true) tr('มีเสียง'),
        if (people.isNotEmpty) people.join(', '),
      ].join(' · ');
      children.add(NxSurfaceCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        onTap: () => _open(it),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${it['headline'] ?? (type == 'chat' ? tr('สรุปแชท') : it['summary_status'] == 'pending' ? tr('กำลังสรุป…') : tr('บทสนทนา (ยังไม่มีสรุป)'))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
            ]),
          ),
          if ((it['action_count'] ?? 0) != 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0x1A10B981), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(NxI.checkSquare, size: 13, color: Color(0xFF059669)), const SizedBox(width: 3), Text('${it['action_count']}', style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w700))]),
            ),
        ]),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('ประวัติ AI การสนทนา'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass), hintText: tr('ค้นหาในบทสนทนาและสรุป…')),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              _q = v.trim();
              _load();
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), children: [
            for (final (k, label) in [('all', 'ทั้งหมด'), ('call', 'โทร'), ('video', 'วิดีโอคอล'), ('chat', 'สรุปแชท')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(tr(label)), selected: _type == k, onSelected: (_) {
                  setState(() => _type = k);
                  _load();
                }),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(controller: _scroll, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
              if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
              ...children,
              if (_loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
              if (!_loading && _items.isEmpty && _error == null)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(tr('ยังไม่มีประวัติ — เปิด "จดบทสนทนา" ตอนโทร หรือกด ✨ ในห้องแชทเพื่อสรุป'), textAlign: TextAlign.center, style: TextStyle(color: hint)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ChatSummaryDetail extends StatelessWidget {
  const _ChatSummaryDetail({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: context.read<AppConfig>().apiClient.getCommAiSummary(id),
      builder: (context, snap) {
        final r = snap.data?['result'] is Map ? Map<String, dynamic>.from(snap.data!['result'] as Map) : null;
        return Scaffold(
          appBar: AppBar(title: Text(tr('สรุปแชท')), actions: [
            if (r != null) IconButton(icon: const Icon(NxI.shareNetwork), onPressed: () => showCommAiShareSheet(context, kind: 'chat', id: id, title: '${r['headline'] ?? ''}')),
          ]),
          body: snap.hasError
              ? Center(child: Text(formatApiError(snap.error!)))
              : r == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(padding: const EdgeInsets.all(14), children: [CommAiSummaryView(result: r)]),
        );
      },
    );
  }
}
