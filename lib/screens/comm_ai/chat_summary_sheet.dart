import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'comm_ai_widgets.dart';

/// ✨ Summarise a chat room for a Thai-time range. Opens as a tall sheet; the answer streams in.
Future<void> showChatSummarySheet(BuildContext context, {required String roomId, required String roomName}) {
  return showAppBottomSheet<void>(context: context, title: tr('สรุปแชทด้วย AI'), child: ChatSummaryPanel(roomId: roomId, roomName: roomName));
}

/// Preset ranges in Thai time → ('YYYY-MM-DD HH:mm', 'YYYY-MM-DD HH:mm')
(String, String) chatSummaryRange(String preset, {DateTime? now}) {
  final n = now ?? thaiNow();
  String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final today = DateTime(n.year, n.month, n.day);
  switch (preset) {
    case '3h':
      return (fmt(n.subtract(const Duration(hours: 3))), fmt(n));
    case 'yesterday':
      final y = today.subtract(const Duration(days: 1));
      return (fmt(y), fmt(y.add(const Duration(hours: 23, minutes: 59))));
    case '7d':
      return (fmt(today.subtract(const Duration(days: 6))), fmt(n));
    default:
      return (fmt(today), fmt(n));
  }
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

  @override
  void dispose() {
    _cancel?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool from) async {
    final cur = DateTime.tryParse((from ? _range.$1 : _range.$2).replaceFirst(' ', 'T')) ?? thaiNow();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: thaiNow().add(const Duration(days: 1)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: from ? 0 : 23, minute: from ? 0 : 59));
    if (t == null) return;
    final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    final s = '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')} ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
    setState(() {
      _preset = 'custom';
      _range = from ? (s, _range.$2) : (_range.$1, s);
    });
  }

  Future<void> _run({bool force = false}) async {
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;
    setState(() {
      _phase = 'loading';
      _stage = '';
      _done = null;
      _error = null;
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
        _error = formatApiError(e);
        _phase = 'error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == 'loading' || _phase == 'streaming';
    final result = _done?['result'] is Map ? Map<String, dynamic>.from(_done!['result'] as Map) : null;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${widget.roomName} · ${tr('เวลาประเทศไทย')}', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, label) in [('3h', '3 ชม.ล่าสุด'), ('today', 'วันนี้'), ('yesterday', 'เมื่อวาน'), ('7d', '7 วัน')])
          ChoiceChip(
            label: Text(tr(label)),
            selected: _preset == k,
            onSelected: (_) => setState(() {
              _preset = k;
              _range = chatSummaryRange(k);
            }),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => _pickDate(true), child: Text(_range.$1, overflow: TextOverflow.ellipsis))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
        Expanded(child: OutlinedButton(onPressed: () => _pickDate(false), child: Text(_range.$2, overflow: TextOverflow.ellipsis))),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(
        key: const ValueKey('chat-summary-run'),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6D28D9), padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: busy ? null : () => _run(),
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(NxI.sparkle),
        label: Text(busy ? tr('กำลังสรุป…') : tr('สรุปช่วงเวลานี้')),
      ),
      const SizedBox(height: 12),
      if (_phase == 'loading')
        Text(_stage == 'map' ? tr('ข้อความเยอะ กำลังแบ่งสรุปทีละส่วน…') : _stage == 'reduce' ? tr('กำลังรวมสรุป…') : tr('กำลังอ่านข้อความ…'), style: TextStyle(color: Theme.of(context).hintColor)),
      if (_phase == 'streaming')
        ValueListenableBuilder<String>(
          valueListenable: _text,
          builder: (_, t, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
            child: Text('$t ▍'),
          ),
        ),
      if (_phase == 'empty') Center(child: Text(tr('ไม่มีข้อความในช่วงเวลานี้'))),
      if (_phase == 'error') Text(_error ?? '', style: const TextStyle(color: Colors.red)),
      if (_phase == 'done' && result != null) ...[
        Row(children: [
          Expanded(child: Text('${tr('จาก')} ${_done!['message_count']} ${tr('ข้อความ')}${_done!['cached'] == true ? ' · ${tr('ผลที่บันทึกไว้')}' : ''}', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
          if (_done!['summary_id'] != null)
            TextButton.icon(
              icon: const Icon(NxI.shareNetwork, size: 16),
              label: Text(tr('แชร์')),
              onPressed: () => showCommAiShareSheet(context, kind: 'chat', id: '${_done!['summary_id']}', title: '${result['headline'] ?? ''}'),
            ),
          IconButton(tooltip: tr('สรุปใหม่'), icon: const Icon(NxI.arrowsClockwise, size: 18), onPressed: () => _run(force: true)),
        ]),
        CommAiSummaryView(result: result, sourceNote: '${tr('จากสรุปแชท')}: ${widget.roomName}'),
      ],
    ]);
  }
}
