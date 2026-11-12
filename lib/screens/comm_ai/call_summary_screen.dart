import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_search_field.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../../widgets/nx_surface_card.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_widgets.dart';

const _speakerColors = [Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFF14B8A6)];

/// After a call: ISAAC summary (4 cards + Task / Visit suggestions) and the transcript with audio playback.
/// Phones: two tabs. Tablets: summary and transcript side by side.
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
  String _tab = 'summary';
  final _search = TextEditingController();
  String _q = '';
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  String? _loadedUser;
  String? _loadingUser;
  bool _playing = false;
  int _posMs = 0;
  int? _durMs;
  double _rate = 1;
  String? _tapePath;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  /// Combined "meeting tape" (every shared voice on one timeline); played by the same player as id 'tape'.
  Map<String, dynamic>? get _tape => _data?['tape'] is Map ? {...Map<String, dynamic>.from(_data!['tape'] as Map), 'user_id': 'tape', 'mime': 'audio/mp4'} : null;
  bool get _onTape => _loadedUser == 'tape';

  @override
  void initState() {
    super.initState();
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _posMs = p.inMilliseconds);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted && d.inMilliseconds > 0) setState(() => _durMs = d.inMilliseconds);
    });
    _search.addListener(() {
      final v = _search.text.trim();
      if (v != _q) setState(() => _q = v);
    });
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    try {
      final d = await context.read<AppConfig>().apiClient.getCommAiCall(widget.callId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
      final s = d['summary'];
      final pending = s == null || (s is Map && s['status'] == 'pending');
      final hasTranscript = (d['transcript'] is List) && (d['transcript'] as List).isNotEmpty;
      if (pending && hasTranscript && _tries++ < 40) _poll = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  Future<void> _play(Map<String, dynamic> rec, {int? atMs}) async {
    final uid = '${rec['user_id']}';
    try {
      if (_loadedUser != uid) {
        setState(() => _loadingUser = uid);
        final bytes = await context.read<AppConfig>().apiClient.downloadCallRecording('${rec['url']}');
        final dir = await getTemporaryDirectory();
        final mime = '${rec['mime']}';
        final ext = mime.contains('wav') ? 'wav' : mime.contains('ogg') ? 'ogg' : mime.contains('webm') ? 'webm' : 'm4a';
        final f = File('${dir.path}/rec-${widget.callId.hashCode}-$uid.$ext');
        await f.writeAsBytes(bytes);
        await _player.stop();
        await _player.setSourceDeviceFile(f.path);
        await _player.setPlaybackRate(uid == 'tape' ? _rate : 1);
        _loadedUser = uid;
        _durMs = null;
        if (uid == 'tape') _tapePath = f.path;
      } else if (atMs == null && _playing) {
        await _player.pause();
        return;
      }
      if (atMs != null) await _player.seek(Duration(milliseconds: atMs > 300 ? atMs - 300 : 0));
      await _player.resume();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _loadingUser = null);
    }
  }

  /// Tap a line: the tape plays both sides from there; without a tape only that speaker's own file.
  void _playLine(Map<String, dynamic> x, List<Map<String, dynamic>> recordings) {
    final at = (x['start_ms'] as num?)?.toInt();
    final tape = _tape;
    if (tape != null) {
      _play(tape, atMs: at);
      return;
    }
    final rec = recordings.where((r) => '${r['user_id']}' == '${x['user_id']}').firstOrNull;
    if (rec != null) _play(rec, atMs: at);
  }

  Widget _tapeCard(Map<String, dynamic> tape) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hint = theme.hintColor;
    final dur = (_onTape ? _durMs : null) ?? (tape['duration_ms'] as num?)?.toInt() ?? 0;
    final pos = _onTape ? _posMs.clamp(0, dur > 0 ? dur : _posMs) : 0;
    final voices = [for (final v in (tape['voices'] as List? ?? const [])) if (v is Map) '${v['name']}'];
    final missing = [for (final m in (tape['missing'] as List? ?? const [])) '$m'];
    final playingTape = _onTape && _playing;
    return Container(
      key: const ValueKey('call-tape'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? [const Color(0xFF312E81).withValues(alpha: 0.5), const Color(0xFF4C1D95).withValues(alpha: 0.3)] : [const Color(0xFFEEF2FF), const Color(0xFFF5F3FF)],
        ),
        border: Border.all(color: kIsaacIndigo.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Material(
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: const BoxDecoration(gradient: kIsaacGradient, shape: BoxShape.circle),
              child: InkWell(
                key: const ValueKey('call-tape-play'),
                onTap: () => playingTape ? _player.pause() : _play(tape),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: _loadingUser == 'tape'
                      ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(playingTape ? NxI.pause : NxI.play, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(tr('เทปบันทึกการสนทนา'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: kIsaacIndigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                  child: Text(tr('${voices.length} เสียง'), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: kIsaacIndigo)),
                ),
              ]),
              Text(voices.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
            ]),
          ),
          IsaacAvatar(mood: playingTape ? 'listening' : 'idle', size: 34, ring: false, animate: false),
        ]),
        Row(children: [
          SizedBox(width: 38, child: Text(_mmss(pos), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: hint, fontFeatures: const [FontFeature.tabularFigures()]))),
          Expanded(
            child: Slider(
              key: const ValueKey('call-tape-seek'),
              value: dur > 0 ? pos.toDouble().clamp(0, dur.toDouble()) : 0,
              max: dur > 0 ? dur.toDouble() : 1,
              onChanged: (v) {
                if (_onTape) {
                  setState(() => _posMs = v.round());
                  _player.seek(Duration(milliseconds: v.round()));
                } else {
                  _play(tape, atMs: v.round() + 300);
                }
              },
            ),
          ),
          SizedBox(width: 34, child: Text(_mmss(dur), style: TextStyle(fontSize: 11, color: hint, fontFeatures: const [FontFeature.tabularFigures()]))),
          TextButton(
            key: const ValueKey('call-tape-speed'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(36, 32), padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () {
              const speeds = [1.0, 1.25, 1.5, 2.0];
              final next = speeds[(speeds.indexOf(_rate) + 1) % speeds.length];
              setState(() => _rate = next);
              if (_onTape) _player.setPlaybackRate(next);
            },
            child: Text('${_rate == _rate.roundToDouble() ? _rate.toInt() : _rate}x', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          IconButton(
            tooltip: tr('ย้อน 10 วินาที'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(NxI.arrowCounterClockwise, size: 18),
            onPressed: _onTape ? () => _player.seek(Duration(milliseconds: (_posMs - 10000).clamp(0, 1 << 31))) : null,
          ),
          IconButton(
            tooltip: tr('แชร์เทป'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(NxI.shareNetwork, size: 18),
            onPressed: _tapePath == null ? null : () => Share.shareXFiles([XFile(_tapePath!, mimeType: 'audio/mp4')], subject: tr('เทปบันทึกการสนทนา')),
          ),
        ]),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text('${tr('ไม่มีเสียงของ')} ${missing.join(', ')} ${tr('(ไม่ได้ยินยอมให้บันทึกหรือไม่ได้แชร์ข้อความ)')}', style: TextStyle(fontSize: 11.5, color: hint)),
          ),
      ]),
    );
  }

  String _mmss(num ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _list(String key) => [for (final x in (_data?[key] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

  Widget _summaryPane(Map<String, dynamic>? summary, Map<String, dynamic>? result, List<Map<String, dynamic>> transcript, String when) {
    final Widget body;
    if (result != null) {
      body = CommAiSummaryView(key: const ValueKey('call-summary-view'), result: result, sourceNote: '${tr('จากสรุปการโทร')} $when', showSource: false);
    } else if (summary?['status'] == 'failed') {
      body = CommAiIsaacState(
        mood: 'error',
        title: 'ISAAC สรุปไม่สำเร็จ',
        message: 'ยังดูบทสนทนาและฟังเสียงได้ตามปกติ',
        action: OutlinedButton.icon(onPressed: _load, icon: const Icon(NxI.arrowsClockwise, size: 16), label: Text(tr('ลองโหลดใหม่'))),
      );
    } else if (transcript.isNotEmpty) {
      body = const CommAiIsaacState(mood: 'typing', title: 'ISAAC กำลังสรุปการสนทนา…', message: 'ใช้เวลาไม่นาน หน้านี้จะอัปเดตเอง', busy: true);
    } else {
      body = const CommAiIsaacState(mood: 'shrug', title: 'สายนี้ไม่ได้เปิดให้ ISAAC จดบทสนทนา', message: 'ครั้งหน้ากด "เริ่มจดบทสนทนา" ตอนรับสายหรือระหว่างคุย');
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [body]);
  }

  Widget _transcriptPane(List<Map<String, dynamic>> transcript, List<Map<String, dynamic>> recordings) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final ids = <String>[];
    for (final x in transcript) {
      final id = '${x['user_id']}';
      if (!ids.contains(id)) ids.add(id);
    }
    final q = _q.toLowerCase();
    final shown = q.isEmpty ? transcript : transcript.where((x) => '${x['text']} ${x['name']}'.toLowerCase().contains(q)).toList();
    final tape = _tape;
    final Widget? perPerson = recordings.isEmpty
        ? null
        : NxSurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(NxI.microphone, size: 16, color: kIsaacIndigo),
              const SizedBox(width: 6),
              Text(tr('เสียงที่บันทึก'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            for (final r in recordings)
              ListTile(
                key: ValueKey('call-recording-${r['user_id']}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _speakerColors[(ids.indexOf('${r['user_id']}').clamp(0, 99)) % _speakerColors.length].withValues(alpha: 0.15),
                  child: _loadingUser == '${r['user_id']}'
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_playing && _loadedUser == '${r['user_id']}' ? NxI.pause : NxI.play, size: 18, color: kIsaacIndigo),
                ),
                title: Text('${r['name']}'),
                subtitle: Text(_mmss(r['duration_ms'] as num? ?? 0)),
                onTap: () => _play(r),
              ),
            if (recordings.length < ids.length) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(tr('มีเฉพาะเสียงของคนที่ยินยอมให้บันทึก'), style: TextStyle(fontSize: 11.5, color: hint))),
          ]),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      if (perPerson != null && tape == null) perPerson,
      if (perPerson != null && tape != null)
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('call-recordings-per-person'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(tr('ไฟล์เสียงแยกรายคน'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kIsaacIndigo)),
            children: [perPerson],
          ),
        ),
      NxSearchField(key: const ValueKey('comm-ai-transcript-search'), controller: _search, hint: 'ค้นหาในบทสนทนา'),
      const SizedBox(height: 8),
      if (transcript.isEmpty)
        const CommAiIsaacState(mood: 'shrug', title: 'ยังไม่มีบทสนทนา', size: 72)
      else if (shown.isEmpty)
        const CommAiIsaacState(mood: 'searching', title: 'ไม่พบคำที่ค้นหา', size: 72),
      for (final x in shown)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _playLine(x, recordings),
          child: Container(
            decoration: BoxDecoration(
              color: _onTape && _posMs >= ((x['start_ms'] as num?) ?? 0) && _posMs <= ((x['end_ms'] as num?) ?? 0) + 400 ? const Color(0x33F59E0B) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 42, child: Text(_mmss(x['start_ms'] as num? ?? 0), style: TextStyle(fontSize: 12, color: hint, fontFeatures: const [FontFeature.tabularFigures()]))),
              Container(
                margin: const EdgeInsets.only(top: 5, right: 8),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: _speakerColors[ids.indexOf('${x['user_id']}') % _speakerColors.length], shape: BoxShape.circle),
              ),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${x['name']}  ', style: TextStyle(fontWeight: FontWeight.w700, color: _speakerColors[ids.indexOf('${x['user_id']}') % _speakerColors.length])),
                  TextSpan(text: '${x['text']}', style: const TextStyle(height: 1.4)),
                ])),
              ),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final summary = d?['summary'] is Map ? Map<String, dynamic>.from(d!['summary'] as Map) : null;
    final result = summary?['status'] == 'done' && summary?['result'] is Map ? Map<String, dynamic>.from(summary!['result'] as Map) : null;
    final transcript = _list('transcript');
    final recordings = _list('recordings');
    final isVideo = d?['media'] == 'video';
    final when = commAiWhen(d?['started_at']);
    final people = [for (final p in _list('participants')) '${p['name'] ?? ''}'].where((n) => n.isNotEmpty).join(', ');
    final Widget body;
    if (_error != null) {
      body = Center(
        child: CommAiIsaacState(
          mood: 'error',
          title: 'เปิดสรุปไม่ได้',
          message: _error,
          action: OutlinedButton.icon(onPressed: _load, icon: const Icon(NxI.arrowsClockwise, size: 16), label: Text(tr('ลองใหม่'))),
        ),
      );
    } else if (d == null) {
      body = const Center(child: CommAiIsaacState(mood: 'reading', title: 'ISAAC กำลังเปิดบทสนทนา…', busy: true));
    } else {
      body = LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 900) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 3, child: _summaryPane(summary, result, transcript, when)),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
            Expanded(flex: 2, child: Column(children: [if (_tape != null) _tapeCard(_tape!), Expanded(child: _transcriptPane(transcript, recordings))])),
          ]);
        }
        return Column(children: [
          if (_tape != null) _tapeCard(_tape!),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: NxSlidingSegmented<String>(
              value: _tab,
              options: [('summary', 'สรุป', NxI.sparkle), ('transcript', '${tr('บทสนทนา')}${transcript.isEmpty ? '' : ' (${transcript.length})'}', NxI.fileText)],
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          Expanded(child: IndexedStack(index: _tab == 'summary' ? 0 : 1, children: [_summaryPane(summary, result, transcript, when), _transcriptPane(transcript, recordings)])),
        ]);
      });
    }
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'ISAAC สรุปการสนทนา',
        subtitle: [isVideo ? tr('วิดีโอคอล') : tr('โทร'), if (when.isNotEmpty) when, if (people.isNotEmpty) people].join(' · '),
        actions: [
          if (d != null)
            IconButton(
              key: const ValueKey('call-summary-share'),
              tooltip: tr('แชร์'),
              icon: const Icon(NxI.shareNetwork),
              onPressed: () => showCommAiShareSheet(context, kind: 'call', id: widget.callId, title: '${result?['headline'] ?? tr('สรุปการสนทนา')}'),
            ),
        ],
      ),
      body: body,
    );
  }
}
