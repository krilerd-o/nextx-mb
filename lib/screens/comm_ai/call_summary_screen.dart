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
import 'comm_ai_access.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_widgets.dart';

/// Languages ISAAC can translate a transcript into (same list as the web).
const kCommAiTranslateLangs = <(String, String)>[
  ('en', 'English'),
  ('th', 'ไทย'),
  ('zh', '中文'),
  ('ja', '日本語'),
  ('my', 'မြန်မာ'),
  ('lo', 'ລາວ'),
  ('km', 'ខ្មែរ'),
  ('vi', 'Tiếng Việt'),
];

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
  bool _available = true;
  bool _summarizing = false;
  int? _editingSeq;
  final _editCtl = TextEditingController();
  bool _savingLine = false;
  bool _edited = false;
  String _lang = '';
  final _translated = <String, String>{}; // '$lang:$seq' → text
  bool _translating = false;

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
    CommAiAccess.of(context.read<AppConfig>().apiClient).then((a) {
      if (mounted && !a.available) setState(() => _available = false);
    });
  }

  @override
  void dispose() {
    _editCtl.dispose();
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
      // Summary still being written → check again shortly (a missing one may still be on its way).
      final waiting = s == null || (s is Map && (s['status'] == 'pending' || s['status'] == 'running'));
      final hasTranscript = (d['transcript'] is List) && (d['transcript'] as List).isNotEmpty;
      if (waiting && hasTranscript && _tries < 40 && (s != null || _tries < 20)) {
        _tries++;
        _poll = Timer(const Duration(seconds: 3), _load);
      } else if (_summarizing) {
        setState(() => _summarizing = false);
      }
      _translateMissing();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  /// "ให้ ISAAC สรุปตอนนี้" / "สรุปใหม่" / "ลองสรุปอีกครั้ง" — then follow the new summary until it is done.
  Future<void> _summarize() async {
    setState(() {
      _summarizing = true;
      _edited = false;
      _tab = 'summary';
    });
    try {
      final r = await context.read<AppConfig>().apiClient.summarizeCall(widget.callId);
      if (!mounted) return;
      setState(() => _data = {...?_data, 'summary': {...?(_data?['summary'] as Map?), 'id': r['summary_id'], 'status': r['status'] ?? 'pending'}});
      _tries = 1;
      _poll?.cancel();
      _poll = Timer(const Duration(seconds: 3), _load);
    } catch (e) {
      if (!mounted) return;
      setState(() => _summarizing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  /// Fix a line ISAAC misheard (own lines; admins any).
  Future<void> _saveLine(Map<String, dynamic> x) async {
    final text = _editCtl.text.trim();
    final seq = (x['seq'] as num?)?.toInt();
    if (text.isEmpty || seq == null) return;
    setState(() => _savingLine = true);
    try {
      await context.read<AppConfig>().apiClient.editCallSegment(widget.callId, seq, text);
      if (!mounted) return;
      setState(() {
        _data = {
          ...?_data,
          'transcript': [
            for (final l in _list('transcript')) '${l['seq']}' == '$seq' ? {...l, 'text': text, 'edited': true} : l,
          ],
        };
        _translated.removeWhere((k, _) => k.endsWith(':$seq'));
        _editingSeq = null;
        _edited = true;
      });
      _translateMissing();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _savingLine = false);
    }
  }

  /// Translate the lines not translated yet into [_lang] (30 lines per request, cached on the server).
  Future<void> _translateMissing() async {
    final lang = _lang;
    if (lang.isEmpty || _translating) return;
    final todo = [for (final x in _list('transcript')) if (_translated['$lang:${x['seq']}'] == null && '${x['text'] ?? ''}'.isNotEmpty) x];
    if (todo.isEmpty) return;
    setState(() => _translating = true);
    final api = context.read<AppConfig>().apiClient;
    try {
      for (var i = 0; i < todo.length; i += 30) {
        final batch = todo.sublist(i, (i + 30).clamp(0, todo.length));
        final out = await api.translateCommAi([for (final x in batch) '${x['text']}'], lang);
        if (!mounted || _lang != lang) return;
        setState(() {
          for (var k = 0; k < batch.length; k++) {
            _translated['$lang:${batch[k]['seq']}'] = k < out.length ? out[k] : '';
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _translating = false);
      if (mounted && _lang != lang) _translateMissing();
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
    final status = summary?['status'];
    final busy = _summarizing || status == 'pending' || status == 'running';
    if (result != null && !_summarizing) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_available && transcript.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('call-summary-resummarize'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _summarize,
              icon: const Icon(NxI.arrowsClockwise, size: 16),
              label: Text(tr('ให้ ISAAC สรุปใหม่')),
            ),
          ),
        // New summary → fresh follow-up ticks.
        KeyedSubtree(
          key: ValueKey('call-summary-${summary?['id']}'),
          child: CommAiSummaryView(
            key: const ValueKey('call-summary-view'),
            result: result,
            summaryId: summary?['id']?.toString(),
            sourceNote: '${tr('จากสรุปการโทร')} $when',
            showSource: false,
          ),
        ),
      ]);
    } else if (status == 'failed' && !_summarizing) {
      body = CommAiIsaacState(
        mood: 'error',
        title: 'ISAAC สรุปไม่สำเร็จ',
        message: 'ยังดูบทสนทนาและฟังเสียงได้ตามปกติ',
        action: _available && transcript.isNotEmpty
            ? FilledButton.icon(key: const ValueKey('call-summary-summarize'), onPressed: _summarize, icon: const Icon(NxI.arrowsClockwise, size: 16), label: Text(tr('ลองสรุปอีกครั้ง')))
            : OutlinedButton.icon(onPressed: _load, icon: const Icon(NxI.arrowsClockwise, size: 16), label: Text(tr('ลองโหลดใหม่'))),
      );
    } else if (transcript.isNotEmpty && busy) {
      body = const CommAiIsaacState(key: ValueKey('call-summary-busy'), mood: 'typing', title: 'ISAAC กำลังสรุปการสนทนา…', message: 'ใช้เวลาไม่นาน หน้านี้จะอัปเดตเอง', busy: true);
    } else if (transcript.isNotEmpty) {
      body = CommAiIsaacState(
        mood: 'idea',
        title: 'ยังไม่มีสรุปของสายนี้',
        action: _available
            ? FilledButton.icon(key: const ValueKey('call-summary-summarize'), onPressed: _summarize, icon: const Icon(NxI.sparkle, size: 16), label: Text(tr('ให้ ISAAC สรุปตอนนี้')))
            : null,
      );
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
      if (_edited && _available)
        Container(
          key: const ValueKey('call-transcript-edited-banner'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(color: kIsaacIndigo.withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.07), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(child: Text(tr('แก้บทสนทนาแล้ว — ให้ ISAAC สรุปใหม่จากข้อความที่แก้ไหม?'), style: const TextStyle(fontSize: 13, height: 1.35))),
            const SizedBox(width: 6),
            FilledButton(
              key: const ValueKey('call-transcript-resummarize'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: _summarize,
              child: Text(tr('สรุปใหม่')),
            ),
          ]),
        ),
      Row(children: [
        Expanded(child: NxSearchField(key: const ValueKey('comm-ai-transcript-search'), controller: _search, hint: 'ค้นหาในบทสนทนา')),
        if (_available && transcript.isNotEmpty) ...[
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            key: const ValueKey('comm-ai-transcript-lang'),
            tooltip: tr('แปลบทสนทนา'),
            initialValue: _lang,
            onSelected: (v) {
              setState(() => _lang = v);
              _translateMissing();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: '', child: Text(tr('ไม่แปล'))),
              for (final (code, label) in kCommAiTranslateLangs) PopupMenuItem(key: ValueKey('comm-ai-lang-$code'), value: code, child: Text(label)),
            ],
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _lang.isEmpty ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : kIsaacIndigo.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_translating)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(NxI.languages, size: 18, color: _lang.isEmpty ? hint : kIsaacIndigo),
                const SizedBox(width: 6),
                Text(_lang.isEmpty ? tr('แปล') : _lang.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _lang.isEmpty ? null : kIsaacIndigo)),
              ]),
            ),
          ),
        ],
      ]),
      if (_translating) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('ISAAC กำลังแปล…'), style: TextStyle(fontSize: 12, color: hint))),
      const SizedBox(height: 8),
      if (transcript.isEmpty)
        const CommAiIsaacState(mood: 'shrug', title: 'ยังไม่มีบทสนทนา', size: 72)
      else if (shown.isEmpty)
        const CommAiIsaacState(mood: 'searching', title: 'ไม่พบคำที่ค้นหา', size: 72),
      for (final x in shown) _line(x, ids, recordings, hint),
    ]);
  }

  Widget _line(Map<String, dynamic> x, List<String> ids, List<Map<String, dynamic>> recordings, Color hint) {
    final seq = '${x['seq']}';
    final color = _speakerColors[ids.indexOf('${x['user_id']}').clamp(0, 99) % _speakerColors.length];
    final editing = _editingSeq != null && '$_editingSeq' == seq;
    final translated = _lang.isEmpty ? null : _translated['$_lang:$seq'];
    final canEdit = x['can_edit'] == true && _available && x['seq'] != null;
    final active = _onTape && _posMs >= ((x['start_ms'] as num?) ?? 0) && _posMs <= ((x['end_ms'] as num?) ?? 0) + 400;
    return InkWell(
      key: ValueKey('call-transcript-line-$seq'),
      borderRadius: BorderRadius.circular(12),
      onTap: editing ? null : () => _playLine(x, recordings),
      child: Container(
        decoration: BoxDecoration(color: active ? const Color(0x33F59E0B) : null, borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 42, child: Text(_mmss(x['start_ms'] as num? ?? 0), style: TextStyle(fontSize: 12, color: hint, fontFeatures: const [FontFeature.tabularFigures()]))),
          Container(margin: const EdgeInsets.only(top: 5, right: 8), width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          Expanded(
            child: editing
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${x['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                    const SizedBox(height: 4),
                    TextField(
                      key: const ValueKey('call-transcript-edit'),
                      controller: _editCtl,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveLine(x),
                      decoration: const InputDecoration(isDense: true, counterText: ''),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: _savingLine ? null : () => setState(() => _editingSeq = null), child: Text(tr('ยกเลิก'))),
                      FilledButton(
                        key: const ValueKey('call-transcript-save'),
                        style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: _savingLine ? null : () => _saveLine(x),
                        child: _savingLine ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('บันทึก')),
                      ),
                    ]),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${x['name']}  ', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                      TextSpan(text: '${x['text']}', style: const TextStyle(height: 1.4)),
                      if (x['edited'] == true) TextSpan(text: '  ${tr('(แก้ไขแล้ว)')}', style: TextStyle(fontSize: 11, color: hint)),
                    ])),
                    if (translated != null && translated.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(translated, key: ValueKey('call-transcript-tr-$seq'), style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: kIsaacIndigo, height: 1.35)),
                      ),
                  ]),
          ),
          if (canEdit && !editing)
            IconButton(
              key: ValueKey('call-transcript-edit-btn-$seq'),
              tooltip: tr('แก้ข้อความ'),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: hint,
              icon: const Icon(NxI.pencilSimple),
              onPressed: () => setState(() {
                _editingSeq = (x['seq'] as num).toInt();
                _editCtl.text = '${x['text']}';
              }),
            ),
        ]),
      ),
    );
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
          if (d != null && _available)
            IconButton(
              key: const ValueKey('call-summary-share'),
              tooltip: tr('แชร์'),
              icon: const Icon(NxI.shareNetwork),
              onPressed: () => showCommAiShareSheet(
                context,
                kind: 'call',
                id: widget.callId,
                title: '${result?['headline'] ?? tr('สรุปการสนทนา')}',
                hasAudio: recordings.isNotEmpty || _tape != null,
              ),
            ),
        ],
      ),
      body: body,
    );
  }
}
