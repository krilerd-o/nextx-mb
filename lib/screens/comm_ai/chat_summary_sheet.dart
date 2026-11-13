import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../services/realtime_service.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import 'comm_ai_access.dart';
import 'comm_ai_delete_sheet.dart';
import 'comm_ai_errors.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_widgets.dart';

/// ✨ ISAAC summarises a chat room for a Thai-time range. Opens as a tall sheet; the answer streams in.
Future<void> showChatSummarySheet(BuildContext context, {required String roomId, required String roomName}) {
  return showAppBottomSheet<void>(context: context, title: null, child: ChatSummaryPanel(roomId: roomId, roomName: roomName));
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Preset ranges in Thai time → ('YYYY-MM-DD HH:mm', 'YYYY-MM-DD HH:mm')
(String, String) chatSummaryRange(String preset, {DateTime? now}) {
  final n = now ?? thaiNow();
  final today = DateTime(n.year, n.month, n.day);
  switch (preset) {
    case '3h':
      return (_fmt(n.subtract(const Duration(hours: 3))), _fmt(n));
    case 'yesterday':
      final y = today.subtract(const Duration(days: 1));
      return (_fmt(y), _fmt(y.add(const Duration(hours: 23, minutes: 59))));
    case '7d':
      return (_fmt(today.subtract(const Duration(days: 6))), _fmt(n));
    default:
      return (_fmt(today), _fmt(n));
  }
}

/// "2026-11-11 09:05" → "11/11 09:05" (year only when it is not this year; Buddhist year in Thai UI).
String _show(String v) {
  final d = DateTime.tryParse(v.replaceFirst(' ', 'T'));
  if (d == null) return v;
  final y = d.year == thaiNow().year ? '' : '/${uiYear(d.year) % 100}';
  return '${d.day}/${d.month}$y  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Chat message ISAAC posts into the room — same text the web posts: headline, key points, follow-ups.
String chatSummaryPostBody(Map<String, dynamic> r) {
  List<String> list(dynamic v) => v is List ? [for (final x in v) '$x'] : const [];
  final actions = r['action_items'] is List ? [for (final a in r['action_items'] as List) if (a is Map) '${a['text']}'] : const <String>[];
  return ['✨ ${r['headline'] ?? tr('สรุปแชท')}', ...list(r['key_points']).map((x) => '• $x'), ...actions.map((a) => '☐ $a')].join('\n');
}

class ChatSummaryPanel extends StatefulWidget {
  const ChatSummaryPanel({super.key, required this.roomId, required this.roomName});
  final String roomId;
  final String roomName;

  @override
  State<ChatSummaryPanel> createState() => _ChatSummaryPanelState();
}

class _ChatSummaryPanelState extends State<ChatSummaryPanel> {
  String _preset = 'today';
  late (String, String) _range = chatSummaryRange('today');
  String _phase = 'idle'; // idle | loading | streaming | done | empty | error
  String _stage = '';
  final _text = ValueNotifier<String>('');
  Map<String, dynamic>? _done;
  String? _error;
  CancelToken? _cancel;
  List<Map<String, dynamic>> _history = const [];
  bool _posting = false;
  bool _posted = false;
  bool _available = true;

  /// The open summary may be deleted by me (its creator, or an admin) — from GET /summaries/:id.
  bool _canDelete = false;
  StreamSubscription<RealtimeEvent>? _deletedSub;

  @override
  void initState() {
    super.initState();
    _deletedSub = RealtimeService.instance.on('ai:summary_deleted').listen((e) => _forget('${e.data['summary_id']}'));
    CommAiAccess.of(context.read<AppConfig>().apiClient).then((a) {
      if (mounted && !a.available) setState(() => _available = false);
    });
    context.read<AppConfig>().apiClient.getChatSummaries(widget.roomId).then((l) {
      if (mounted) setState(() => _history = l.where((x) => x['status'] == 'done').toList());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _deletedSub?.cancel();
    _cancel?.cancel();
    _text.dispose();
    super.dispose();
  }

  String get _mood => switch (_phase) {
        'loading' => 'reading',
        'streaming' => 'typing',
        'done' => 'answer_ready',
        'empty' => 'searching',
        'error' => 'error',
        _ => 'hello',
      };

  Future<void> _pick(bool from) async {
    final cur = DateTime.tryParse((from ? _range.$1 : _range.$2).replaceFirst(' ', 'T')) ?? thaiNow();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: thaiNow().add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute));
    if (t == null) return;
    final s = _fmt(DateTime(d.year, d.month, d.day, t.hour, t.minute));
    setState(() {
      _preset = 'custom';
      _range = from ? (s, _range.$2) : (_range.$1, s);
    });
  }

  void _setPreset(String k) => setState(() {
        _preset = k;
        if (k != 'custom') _range = chatSummaryRange(k);
      });

  Future<void> _run({bool force = false}) async {
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;
    setState(() {
      _phase = 'loading';
      _stage = '';
      _done = null;
      _error = null;
      _posted = false;
      _canDelete = false;
    });
    _text.value = '';
    var acc = '';
    try {
      await for (final ev in context.read<AppConfig>().apiClient.streamChatSummary(widget.roomId, from: _range.$1, to: _range.$2, force: force, cancel: cancel)) {
        if (!mounted) return;
        switch (ev.type) {
          case 'token':
            acc += ev.token;
            final i = acc.indexOf('```');
            _text.value = (i >= 0 ? acc.substring(0, i) : acc).trim();
            if (_phase != 'streaming') setState(() => _phase = 'streaming');
          case 'status':
            setState(() => _stage = '${ev.data['stage'] ?? ''}');
          case 'done':
            setState(() {
              _done = ev.data;
              _phase = ev.data['empty'] == true ? 'empty' : 'done';
            });
          case 'error':
            setState(() {
              _error = '${ev.data['message'] ?? 'error'}';
              _phase = 'error';
            });
        }
      }
    } catch (e) {
      if (cancel.isCancelled || !mounted) return;
      setState(() {
        _error = commAiErrorText(e);
        _phase = 'error';
      });
    }
  }

  Future<void> _openEarlier(Map<String, dynamic> h) async {
    setState(() {
      _phase = 'loading';
      _stage = '';
    });
    try {
      final s = await context.read<AppConfig>().apiClient.getCommAiSummary('${h['id']}');
      if (!mounted) return;
      final r = s['result'] is Map ? Map<String, dynamic>.from(s['result'] as Map) : null;
      setState(() {
        _done = {'result': r, 'summary_id': s['id'], 'message_count': r?['message_count'] ?? h['message_count'], 'cached': true};
        _phase = r == null ? 'error' : 'done';
        _error = r == null ? tr('เปิดสรุปไม่ได้') : null;
        _posted = false;
        _canDelete = s['can_delete'] == true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = formatApiError(e);
          _phase = 'error';
        });
      }
    }
  }

  /// A summary was deleted (here or on another device): drop it from the list and close it if open.
  void _forget(String id) {
    if (!mounted) return;
    setState(() {
      _history = [for (final h in _history) if ('${h['id']}' != id) h];
      if ('${_done?['summary_id']}' == id) {
        _done = null;
        _phase = 'idle';
        _canDelete = false;
      }
    });
  }

  Future<void> _delete(String id) async {
    final out = await showCommAiDeleteSheet(context, kind: 'chat', id: id);
    if (out == null || !mounted) return;
    _forget(id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ลบสรุปแชทแล้ว'))));
  }

  Future<void> _postToChat(Map<String, dynamic> r) async {
    setState(() => _posting = true);
    try {
      await context.read<AppConfig>().apiClient.postChatMessage(widget.roomId, chatSummaryPostBody(r));
      if (mounted) setState(() => _posted = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Widget _dateField(String label, String value, bool from) {
    return InkWell(
      key: ValueKey(from ? 'chat-summary-from' : 'chat-summary-to'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _pick(from),
      child: InputDecorator(
        decoration: InputDecoration(labelText: tr(label), suffixIcon: const Icon(NxI.calendarBlank, size: 18), isDense: true),
        child: Text(_show(value), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final busy = _phase == 'loading' || _phase == 'streaming';
    final result = _done?['result'] is Map ? Map<String, dynamic>.from(_done!['result'] as Map) : null;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IsaacAvatar(mood: _mood, size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr('ไอแซคสรุปแชท'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const IsaacBadge(),
            ]),
            Text('${widget.roomName} · ${tr('เวลาประเทศไทย')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: hint, fontSize: 12)),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (k, label) in [('3h', '3 ชม.ล่าสุด'), ('today', 'วันนี้'), ('yesterday', 'เมื่อวาน'), ('7d', '7 วัน'), ('custom', 'กำหนดเอง')])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey('chat-summary-preset-$k'),
                label: Text(tr(label)),
                selected: _preset == k,
                showCheckmark: false,
                onSelected: (_) => _setPreset(k),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _dateField('ตั้งแต่', _range.$1, true)),
        const SizedBox(width: 10),
        Expanded(child: _dateField('ถึง', _range.$2, false)),
      ]),
      const SizedBox(height: 12),
      if (!_available)
        const IsaacTip('ธุรกิจนี้ยังไม่ได้เปิดแพ็กเกจไอแซคเอไอ การสื่อสาร — ดูประวัติเดิมได้ แต่สรุปหรือแชร์ใหม่ไม่ได้', mood: 'shrug', key: ValueKey('comm-ai-unavailable'))
      else
        Row(children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: busy ? null : kIsaacGradient, borderRadius: BorderRadius.circular(14)),
              child: FilledButton.icon(
                key: const ValueKey('chat-summary-run'),
                style: FilledButton.styleFrom(backgroundColor: busy ? null : Colors.transparent, shadowColor: Colors.transparent, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: busy ? null : () => _run(),
                icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.sparkle),
                label: Text(busy ? tr('ไอแซคกำลังสรุป…') : tr('ให้ไอแซคสรุปช่วงเวลานี้')),
              ),
            ),
          ),
          if (_phase == 'done') ...[
            const SizedBox(width: 8),
            IconButton.outlined(tooltip: tr('สรุปใหม่'), icon: const Icon(NxI.arrowsClockwise, size: 18), onPressed: () => _run(force: true)),
          ],
        ]),
      const SizedBox(height: 14),
      if (_phase == 'loading')
        CommAiIsaacState(
          mood: 'reading',
          busy: true,
          size: 80,
          title: _stage == 'map' ? 'ข้อความเยอะ ไอแซคกำลังแบ่งอ่านทีละส่วน…' : _stage == 'reduce' ? 'ไอแซคกำลังรวมสรุป…' : 'ไอแซคกำลังอ่านข้อความ…',
        ),
      if (_phase == 'streaming')
        ValueListenableBuilder<String>(
          valueListenable: _text,
          builder: (_, t, _) => Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kIsaacIndigo.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const IsaacAvatar(mood: 'typing', size: 30, ring: false),
              const SizedBox(width: 10),
              Expanded(child: Text('$t ▍', style: const TextStyle(height: 1.45))),
            ]),
          ),
        ),
      if (_phase == 'empty')
        CommAiIsaacState(
          mood: 'searching',
          size: 80,
          title: 'ไอแซคไม่พบข้อความในช่วงเวลานี้',
          action: _preset == '7d'
              ? null
              : OutlinedButton.icon(
                  key: const ValueKey('chat-summary-try-7d'),
                  onPressed: () {
                    _setPreset('7d');
                    _run();
                  },
                  icon: const Icon(NxI.calendarBlank, size: 16),
                  label: Text(tr('ลองดู 7 วันล่าสุด')),
                ),
        ),
      if (_phase == 'error') CommAiIsaacState(mood: 'error', size: 80, title: 'ไอแซคสรุปไม่สำเร็จ', message: _error),
      if (_phase == 'done' && result != null) ...[
        Row(children: [
          Expanded(
            child: Text('${tr('จาก')} ${_done!['message_count'] ?? '-'} ${tr('ข้อความ')}${_done!['cached'] == true ? ' · ${tr('ผลที่บันทึกไว้')}' : ''}', style: TextStyle(fontSize: 12, color: hint)),
          ),
          if (_done!['summary_id'] != null && _canDelete)
            IconButton(
              key: const ValueKey('chat-summary-delete'),
              tooltip: tr('ลบสรุปแชทนี้'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(NxI.trash, size: 18),
              onPressed: () => _delete('${_done!['summary_id']}'),
            ),
          if (_done!['summary_id'] != null && _available)
            TextButton.icon(
              icon: const Icon(NxI.shareNetwork, size: 16),
              label: Text(tr('แชร์')),
              onPressed: () => showCommAiShareSheet(context, kind: 'chat', id: '${_done!['summary_id']}', title: '${result['headline'] ?? ''}'),
            ),
          TextButton.icon(
            key: const ValueKey('chat-summary-post'),
            icon: _posting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_posted ? NxI.check : NxI.paperPlaneTilt, size: 16),
            label: Text(tr(_posted ? 'ส่งแล้ว' : 'ส่งเข้าแชท')),
            onPressed: _posting || _posted ? null : () => _postToChat(result),
          ),
        ]),
        const SizedBox(height: 6),
        CommAiSummaryView(key: ValueKey('chat-summary-view-${_done!['summary_id']}'), result: result, summaryId: _done!['summary_id']?.toString(), sourceNote: '${tr('จากสรุปแชท')}: ${widget.roomName}'),
      ],
      if (_phase == 'idle' && _history.isNotEmpty) ...[
        const CommAiSectionTitle('สรุปก่อนหน้า', icon: NxI.clockCounterClockwise),
        for (final h in _history.take(8))
          NxSurfaceCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            onTap: () => _openEarlier(h),
            child: Row(children: [
              const IsaacAvatar(mood: 'answer_ready', size: 34, ring: false, animate: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h['headline'] ?? tr('สรุปแชท')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${commAiWhen(h['range_from'])} – ${commAiWhen(h['range_to'])}', style: TextStyle(fontSize: 11.5, color: hint)),
                ]),
              ),
              Icon(NxI.caretRight, size: 16, color: hint),
            ]),
          ),
      ],
    ]);
  }
}
