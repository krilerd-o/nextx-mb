import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import 'comm_ai_widgets.dart';

/// After a call: AI summary (4 cards + Task/Visit suggestions) and the transcript with audio playback.
class CallSummaryScreen extends StatefulWidget {
  const CallSummaryScreen({super.key, required this.callId});
  final String callId;

  @override
  State<CallSummaryScreen> createState() => _CallSummaryScreenState();
}

class _CallSummaryScreenState extends State<CallSummaryScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _poll;
  int _tries = 0;
  String _q = '';
  final _player = AudioPlayer();
  String? _playingUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AppConfig>().apiClient.getCommAiCall(widget.callId);
      if (!mounted) return;
      setState(() => _data = d);
      final s = d['summary'];
      final pending = s == null || (s is Map && s['status'] == 'pending');
      final hasTranscript = (d['transcript'] is List) && (d['transcript'] as List).isNotEmpty;
      if (pending && hasTranscript && _tries++ < 20) _poll = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  Future<void> _play(Map<String, dynamic> rec, {int? atMs}) async {
    final uid = '${rec['user_id']}';
    if (_playingUser != uid) {
      final bytes = await context.read<AppConfig>().apiClient.downloadCallRecording('${rec['url']}');
      final dir = await getTemporaryDirectory();
      final ext = '${rec['mime']}'.contains('wav') ? 'wav' : '${rec['mime']}'.contains('ogg') ? 'ogg' : 'm4a';
      final f = File('${dir.path}/rec-${widget.callId}-$uid.$ext');
      await f.writeAsBytes(bytes);
      await _player.setSourceDeviceFile(f.path);
      _playingUser = uid;
    }
    if (atMs != null) await _player.seek(Duration(milliseconds: atMs > 300 ? atMs - 300 : 0));
    await _player.resume();
  }

  String _mmss(num ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final summary = d?['summary'] is Map ? Map<String, dynamic>.from(d!['summary'] as Map) : null;
    final result = summary?['status'] == 'done' && summary?['result'] is Map ? Map<String, dynamic>.from(summary!['result'] as Map) : null;
    final transcript = [for (final x in (d?['transcript'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final recordings = [for (final x in (d?['recordings'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final isVideo = d?['media'] == 'video';
    final when = commAiWhen(d?['started_at']);
    final shown = _q.isEmpty ? transcript : transcript.where((x) => '${x['text']} ${x['name']}'.toLowerCase().contains(_q.toLowerCase())).toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('สรุปการสนทนา')),
            if (when.isNotEmpty) Text('${isVideo ? tr('วิดีโอคอล') : tr('โทร')} · $when', style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            if (d != null)
              IconButton(
                key: const ValueKey('call-summary-share'),
                tooltip: tr('แชร์'),
                icon: const Icon(NxI.shareNetwork),
                onPressed: () => showCommAiShareSheet(context, kind: 'call', id: widget.callId, title: '${result?['headline'] ?? tr('สรุปการสนทนา')}'),
              ),
          ],
          bottom: TabBar(tabs: [Tab(text: tr('สรุป')), Tab(text: '${tr('บทสนทนา')}${transcript.isEmpty ? '' : ' (${transcript.length})'}')]),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : d == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    ListView(padding: const EdgeInsets.all(14), children: [
                      if (result != null)
                        CommAiSummaryView(result: result, sourceNote: '${tr('จากสรุปการโทร')} $when')
                      else if (summary?['status'] == 'failed')
                        Text(tr('สรุปไม่สำเร็จ — ยังดูบทสนทนาได้ในแท็บถัดไป'))
                      else if (transcript.isNotEmpty)
                        Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text(tr('AI กำลังสรุปการสนทนา…'))])
                      else
                        Text(tr('สายนี้ไม่ได้เปิดจดบทสนทนา')),
                    ]),
                    ListView(padding: const EdgeInsets.all(14), children: [
                      if (recordings.isNotEmpty)
                        NxSurfaceCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tr('เสียงที่บันทึก'), style: const TextStyle(fontWeight: FontWeight.w700)),
                            for (final r in recordings)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(NxI.play),
                                title: Text('${r['name']}'),
                                subtitle: Text(_mmss(r['duration_ms'] as num? ?? 0)),
                                onTap: () => _play(r),
                              ),
                          ]),
                        ),
                      TextField(
                        decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass), hintText: tr('ค้นหาในบทสนทนา')),
                        onChanged: (v) => setState(() => _q = v.trim()),
                      ),
                      const SizedBox(height: 8),
                      for (final x in shown)
                        InkWell(
                          onTap: () {
                            final rec = recordings.where((r) => '${r['user_id']}' == '${x['user_id']}').firstOrNull;
                            if (rec != null) _play(rec, atMs: (x['start_ms'] as num?)?.toInt());
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(width: 44, child: Text(_mmss(x['start_ms'] as num? ?? 0), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor))),
                              Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '${x['name']}  ', style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: '${x['text']}')]))),
                            ]),
                          ),
                        ),
                    ]),
                  ]),
      ),
    );
  }
}
