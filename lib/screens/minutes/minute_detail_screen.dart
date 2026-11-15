import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/minutes/minutes.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'minute_share_sheet.dart';
import 'minutes_widgets.dart';

/// One meeting: player + tabs สรุป · ถอดข้อความ · แปล · ถามไอแซค.
class MinuteDetailScreen extends StatefulWidget {
  const MinuteDetailScreen({super.key, required this.meetingId});
  final String meetingId;

  @override
  State<MinuteDetailScreen> createState() => _MinuteDetailScreenState();
}

class _MinuteDetailScreenState extends State<MinuteDetailScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);
  MinuteMeeting? _m;
  List<MinuteLine> _lines = const [];
  List<MinuteSummary> _summaries = const [];
  Map<String, Map<String, String>> _translations = const {};
  Map<String, String> _trStatus = const {};
  bool _loading = true;
  String? _error;
  StreamSubscription<RealtimeEvent>? _sub;
  bool _summarizing = false;
  String? _viewLang;
  final _player = _MediaPlayer();

  ApiClient get _api => context.read<AppConfig>().apiClient;
  MinuteSummary? get _summary => _summaries.firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = RealtimeService.instance.events.listen(_onEvent);
    _player.addListener(_tick);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabs.dispose();
    _player.removeListener(_tick);
    _player.dispose();
    super.dispose();
  }

  void _tick() => mounted ? setState(() {}) : null;

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final d = await _api.getMinuteMeeting(widget.meetingId);
      if (!mounted) return;
      final trs = <String, Map<String, String>>{};
      final st = <String, String>{};
      for (final t in (d['translations'] as List? ?? const [])) {
        if (t is! Map) continue;
        final lang = '${t['lang']}';
        trs[lang] = {for (final e in ((t['segments'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
        st[lang] = '${t['status'] ?? 'ready'}';
      }
      setState(() {
        _m = MinuteMeeting.fromJson(Map<String, dynamic>.from(d['item'] as Map));
        _lines = [for (final s in (d['segments'] as List? ?? const [])) if (s is Map) MinuteLine.fromJson(Map<String, dynamic>.from(s))];
        _summaries = [for (final s in (d['summaries'] as List? ?? const [])) if (s is Map) MinuteSummary.fromJson(Map<String, dynamic>.from(s))];
        _translations = trs;
        _trStatus = st;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiEnvelopeException ? e.message : 'โหลดการประชุมไม่สำเร็จ';
      });
    }
  }

  void _onEvent(RealtimeEvent e) {
    if ('${e.data['meeting_id']}' != widget.meetingId) return;
    switch (e.type) {
      case 'ai:minute_status':
        final m = _m;
        if (m != null) setState(() => _m = m.copyWith(status: '${e.data['status'] ?? m.status}', progress: (e.data['progress'] as num?)?.toInt(), stage: e.data['stage']?.toString()));
      case 'ai:minute_ready':
      case 'ai:minute_translation':
        _load(quiet: true);
    }
  }

  // ── actions

  Future<void> _summarize({String? template}) async {
    final m = _m;
    if (m == null) return;
    final t = template ?? await _pickTemplate(m.template);
    if (t == null) return;
    setState(() => _summarizing = true);
    try {
      await _api.summarizeMinuteMeeting(m.id, template: t);
      await _load(quiet: true);
    } catch (e) {
      _snack(e is ApiEnvelopeException ? e.message : 'สรุปไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<String?> _pickTemplate(String current) {
    var v = current;
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('สรุปแบบไหนดี'), style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 10),
                MinuteTemplatePicker(value: v, onChanged: (x) => set(() => v = x)),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: FilledButton(key: const ValueKey('minute-summarize-go'), onPressed: () => Navigator.pop(ctx, v), child: Text(tr('สรุปเลย')))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _translate(String lang) async {
    final m = _m;
    if (m == null) return;
    setState(() => _trStatus = {..._trStatus, lang: 'working'});
    try {
      await _api.translateMinuteMeeting(m.id, lang);
      _snack('กำลังแปล — ไอแซคจะแสดงผลเมื่อแปลเสร็จ');
    } catch (e) {
      setState(() => _trStatus = {..._trStatus}..remove(lang));
      _snack(e is ApiEnvelopeException ? e.message : 'แปลไม่สำเร็จ');
    }
  }

  Future<void> _createTasks() async {
    final m = _m;
    if (m == null) return;
    try {
      final res = await _api.createMinuteTasks(m.id);
      final ok = res.where((r) => r['activity_id'] != null).length;
      _snack('สร้างงานแล้ว $ok รายการ');
    } catch (e) {
      _snack(e is ApiEnvelopeException ? e.message : 'สร้างงานไม่สำเร็จ');
    }
  }

  Future<void> _editLine(MinuteLine l) async {
    final text = TextEditingController(text: l.text);
    final speaker = TextEditingController(text: _speaker(l));
    final r = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tr('แก้ไขบรรทัด')} ${minuteClock(l.startMs)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('minute-edit-speaker'), controller: speaker, decoration: InputDecoration(labelText: tr('ผู้พูด'))),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('minute-edit-text'), controller: text, maxLines: 5, minLines: 2, decoration: InputDecoration(labelText: tr('ข้อความ'))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))), FilledButton(onPressed: () => Navigator.pop(ctx, (text.text, speaker.text)), child: Text(tr('บันทึก')))],
      ),
    );
    // After the dialog's closing animation (it still reads them).
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      text.dispose();
      speaker.dispose();
    });
    if (r == null || _m == null) return;
    try {
      if (r.$1.trim() != l.text) await _api.editMinuteSegment(_m!.id, l.seq, text: r.$1.trim());
      final newName = r.$2.trim();
      if (newName.isNotEmpty && newName != _speaker(l)) {
        // Rename this speaker everywhere (the raw label stays; the meeting maps it).
        final raw = l.speaker ?? '';
        if (raw.isNotEmpty) {
          await _api.updateMinuteMeeting(_m!.id, {'speakers': {raw: newName}});
        } else {
          await _api.editMinuteSegment(_m!.id, l.seq, speaker: newName);
        }
      }
      await _load(quiet: true);
    } catch (e) {
      _snack(e is ApiEnvelopeException ? e.message : 'บันทึกไม่สำเร็จ');
    }
  }

  String _speaker(MinuteLine l) {
    final raw = l.speaker ?? '';
    return _m?.speakers[raw] ?? (raw.isEmpty ? tr('ผู้พูด') : raw);
  }

  Future<void> _more() async {
    final m = _m;
    if (m == null) return;
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(NxI.pencilSimple), title: Text(tr('เปลี่ยนชื่อ')), onTap: () => Navigator.pop(ctx, 'rename')),
          if (m.status == 'failed') ListTile(leading: const Icon(NxI.arrowClockwise), title: Text(tr('ประมวลผลใหม่')), onTap: () => Navigator.pop(ctx, 'retry')),
          ListTile(leading: Icon(NxI.trash, color: Theme.of(ctx).colorScheme.error), title: Text(tr('ลบการประชุม')), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'rename':
        final c = TextEditingController(text: m.title);
        final t = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('ชื่อการประชุม')),
            content: TextField(controller: c, autofocus: true),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))), FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('บันทึก')))],
          ),
        );
        Future<void>.delayed(const Duration(milliseconds: 400), c.dispose);
        if (t != null && t.trim().isNotEmpty) {
          await _api.updateMinuteMeeting(m.id, {'title': t.trim()});
          await _load(quiet: true);
        }
      case 'retry':
        await _api.retryMinuteMeeting(m.id);
        await _load(quiet: true);
      case 'delete':
        final ok = await showDeleteConfirm(context, name: m.title, loses: const ['เสียง / วิดีโอ', 'ข้อความที่ถอดไว้', 'สรุปและคำแปล', 'ลิงก์แชร์ทั้งหมด'], note: null);
        if (!ok || !mounted) return;
        await _api.deleteMinuteMeeting(m.id);
        if (mounted) context.pop();
    }
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(t))));

  void _seek(int ms) {
    final m = _m;
    if (m?.mediaUrl == null) return;
    HapticFeedback.selectionClick();
    unawaited(_player.playAt(_api, m!, ms));
  }

  // ── build

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      key: const ValueKey('minute-detail'),
      appBar: AppBar(
        title: Text(m?.title ?? tr('การประชุม'), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (m != null) IconButton(key: const ValueKey('minute-share'), tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork), onPressed: () => showMinuteShareSheet(context, meeting: m, langs: [m.locale, ..._translations.keys])),
          if (m != null) IconButton(tooltip: tr('เพิ่มเติม'), icon: const Icon(NxI.dotsThreeVertical), onPressed: _more),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [Tab(text: tr('สรุป')), Tab(text: tr('ถอดข้อความ')), Tab(text: tr('แปล')), Tab(text: tr('ถามไอแซค'))],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || m == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(tr(_error ?? 'ไม่พบการประชุม')), TextButton(onPressed: _load, child: Text(tr('ลองอีกครั้ง')))]))
          : Column(
              children: [
                if (m.busy || m.status == 'failed' || m.status == 'live') _statusBar(m),
                if (m.mediaUrl != null) _mediaBar(m),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _SummaryTab(meeting: m, summary: _summary, busy: _summarizing, onSummarize: _summarize, onSeek: _seek, onCreateTasks: _createTasks),
                      _TranscriptTab(lines: _lines, speakerOf: _speaker, positionMs: _player.positionMs, onSeek: _seek, onEdit: _editLine),
                      _TranslateTab(
                        meeting: m,
                        lines: _lines,
                        translations: _translations,
                        status: _trStatus,
                        viewLang: _viewLang,
                        onView: (l) => setState(() => _viewLang = l),
                        onTranslate: _translate,
                        speakerOf: _speaker,
                      ),
                      _AskTab(meetingId: m.id, onSeek: _seek, enabled: _lines.isNotEmpty),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusBar(MinuteMeeting m) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('minute-status-bar'),
      width: double.infinity,
      color: m.status == 'failed' ? cs.errorContainer : cs.primaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(m.status == 'failed' ? '${tr('ประมวลผลไม่สำเร็จ')}${m.error != null ? ': ${m.error}' : ''}' : '${tr(minuteStatusLabel(m.status, stage: m.stage))}…', maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (m.status == 'failed') TextButton(onPressed: () async => {await _api.retryMinuteMeeting(m.id), await _load(quiet: true)}, child: Text(tr('ลองใหม่'))),
          ]),
          if (m.busy) Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: m.progress > 0 ? m.progress / 100 : null, borderRadius: BorderRadius.circular(9))),
        ],
      ),
    );
  }

  Widget _mediaBar(MinuteMeeting m) {
    final p = _player;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (m.video && p.video != null && p.video!.value.isInitialized)
          AspectRatio(aspectRatio: p.video!.value.aspectRatio, child: VideoPlayer(p.video!)),
        Container(
          key: const ValueKey('minute-player'),
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)))),
          child: Row(
            children: [
              p.loading
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(key: const ValueKey('minute-play'), icon: Icon(p.playing ? NxI.pause : NxI.play), onPressed: () => p.playing ? p.pause() : p.playAt(_api, m, p.positionMs)),
              Text(minuteClock(p.positionMs), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
              Expanded(
                child: Slider(
                  value: m.durationMs <= 0 ? 0 : (p.positionMs / m.durationMs).clamp(0, 1).toDouble(),
                  onChanged: m.durationMs <= 0 ? null : (v) => _seek((v * m.durationMs).round()),
                ),
              ),
              Text(minuteClock(m.durationMs), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Downloads the meeting media once to the cache, then plays it (audio: audioplayers, video: video_player).
class _MediaPlayer extends ChangeNotifier {
  AudioPlayer? _audio;
  VideoPlayerController? video;
  String? _file;
  bool loading = false;
  bool playing = false;
  int positionMs = 0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stSub;

  Future<String> _ensureFile(ApiClient api, MinuteMeeting m) async {
    if (_file != null) return _file!;
    final dir = await getTemporaryDirectory();
    final ext = (m.mediaMime ?? '').contains('video') ? 'mp4' : (m.mediaMime ?? '').contains('ogg') ? 'ogg' : 'm4a';
    final f = File('${dir.path}/minute-${m.id}.$ext');
    if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(await api.downloadMinuteMedia(m.id), flush: true);
    return _file = f.path;
  }

  Future<void> playAt(ApiClient api, MinuteMeeting m, int ms) async {
    try {
      if (_file == null) {
        loading = true;
        notifyListeners();
        await _ensureFile(api, m);
      }
      if (m.video) {
        if (video == null) {
          final v = VideoPlayerController.file(File(_file!));
          await v.initialize();
          v.addListener(() {
            positionMs = v.value.position.inMilliseconds;
            playing = v.value.isPlaying;
            notifyListeners();
          });
          video = v;
        }
        await video!.seekTo(Duration(milliseconds: ms));
        await video!.play();
      } else {
        if (_audio == null) {
          final a = AudioPlayer();
          _posSub = a.onPositionChanged.listen((d) {
            positionMs = d.inMilliseconds;
            notifyListeners();
          });
          _stSub = a.onPlayerStateChanged.listen((s) {
            playing = s == PlayerState.playing;
            notifyListeners();
          });
          await a.setSource(DeviceFileSource(_file!));
          _audio = a;
        }
        await _audio!.seek(Duration(milliseconds: ms));
        await _audio!.resume();
      }
      positionMs = ms;
    } catch (_) {
      // Not available (e.g. tests / no media): stay paused.
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _audio?.pause();
    await video?.pause();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stSub?.cancel();
    _audio?.dispose();
    video?.dispose();
    super.dispose();
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.meeting, required this.summary, required this.busy, required this.onSummarize, required this.onSeek, required this.onCreateTasks});
  final MinuteMeeting meeting;
  final MinuteSummary? summary;
  final bool busy;
  final Future<void> Function({String? template}) onSummarize;
  final ValueChanged<int> onSeek;
  final VoidCallback onCreateTasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    if (s == null) {
      final canSummarize = meeting.ready;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NxI.sparkle, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(tr(canSummarize ? 'ยังไม่ได้สรุปการประชุมนี้' : 'ไอแซคจะสรุปให้เมื่อประมวลผลเสร็จ'), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              if (canSummarize)
                FilledButton.icon(
                  key: const ValueKey('minute-summarize'),
                  onPressed: busy ? null : () => onSummarize(),
                  icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.sparkle),
                  label: Text(tr(busy ? 'กำลังสรุป…' : 'สรุปตอนนี้')),
                ),
            ],
          ),
        ),
      );
    }
    Widget section(String title, IconData icon, Color color0, List<Widget> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      final color = minuteTint(context, color0);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.18))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700))]),
            const SizedBox(height: 6),
            ...items,
          ],
        ),
      );
    }

    Widget bullet(String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: _TimeLinkText(t, onSeek: onSeek))]),
    );

    return ListView(
      key: const ValueKey('minute-summary'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        Text(s.headline.isEmpty ? meeting.title : s.headline, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Chip(label: Text(tr(minuteTemplateLabel(s.template)), overflow: TextOverflow.ellipsis), visualDensity: VisualDensity.compact)),
          TextButton.icon(key: const ValueKey('minute-resummarize'), onPressed: busy ? null : () => onSummarize(), icon: const Icon(NxI.arrowClockwise, size: 16), label: Text(tr('สรุปใหม่'))),
        ]),
        const SizedBox(height: 6),
        section('ใจความสำคัญ', NxI.listBullets, const Color(0xFF4F46E5), [for (final t in s.keyPoints) bullet(t)]),
        section('มติ / ข้อตกลง', NxI.checkCircle, const Color(0xFF047857), [for (final t in s.decisions) bullet(t)]),
        section('สิ่งที่ต้องทำต่อ', NxI.listChecks, const Color(0xFFB45309), [
          for (final a in s.actions)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(NxI.checkSquare, size: 18),
              title: _TimeLinkText(a.text, onSeek: onSeek),
              subtitle: (a.owner ?? a.due) == null ? null : Text([if (a.owner != null) a.owner!, if (a.due != null) a.due!].join(' · ')),
            ),
          if (s.actions.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(key: const ValueKey('minute-create-tasks'), onPressed: onCreateTasks, icon: const Icon(NxI.calendarPlus, size: 16), label: Text(tr('สร้างเป็นงานใน CRM'))),
            ),
        ]),
        section('ประเด็นที่เกิดขึ้น', NxI.chatCircle, const Color(0xFF0369A1), [for (final t in s.discussion) bullet(t)]),
        section('คำถามที่ยังเปิดอยู่', NxI.question, const Color(0xFFBE123C), [for (final t in s.openQuestions) bullet(t)]),
        section('คำแนะนำ', NxI.sparkle, const Color(0xFF7C3AED), [for (final t in s.recommendations) bullet(t)]),
        section('ลำดับหัวข้อ', NxI.bookmark, const Color(0xFF334155), [
          for (final c in s.chapters)
            InkWell(
              onTap: () => onSeek(c.atMs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(minuteClock(c.atMs), style: TextStyle(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.title)),
                ]),
              ),
            ),
        ]),
        if (s.nextMeeting != null) section('ประชุมครั้งถัดไป', NxI.calendarBlank, const Color(0xFF0F766E), [Text(s.nextMeeting!)]),
        Text(tr('สร้างโดยไอแซค — ตรวจสอบก่อนนำไปใช้'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Text where "[12:05]" is tappable (jump to that moment).
class _TimeLinkText extends StatelessWidget {
  const _TimeLinkText(this.text, {required this.onSeek});
  final String text;
  final ValueChanged<int> onSeek;

  static int? _ms(String t) {
    final p = t.split(':').map(int.tryParse).toList();
    if (p.any((x) => x == null)) return null;
    return p.length == 3 ? ((p[0]! * 60 + p[1]!) * 60 + p[2]!) * 1000 : (p[0]! * 60 + p[1]!) * 1000;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'\[(\d{1,2}(?::\d{2}){1,2})\]').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final ms = _ms(m.group(1)!);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: ms == null ? null : () => onSeek(ms),
          child: Text(' ${m.group(1)} ', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans, style: DefaultTextStyle.of(context).style));
  }
}

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({required this.lines, required this.speakerOf, required this.positionMs, required this.onSeek, required this.onEdit});
  final List<MinuteLine> lines;
  final String Function(MinuteLine) speakerOf;
  final int positionMs;
  final ValueChanged<int> onSeek;
  final ValueChanged<MinuteLine> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lines.isEmpty) return Center(child: Text(tr('ยังไม่มีข้อความถอดเสียง')));
    return ListView.builder(
      key: const ValueKey('minute-transcript'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final l = lines[i];
        final now = positionMs >= l.startMs && (i + 1 >= lines.length || positionMs < lines[i + 1].startMs) && positionMs > 0;
        final showName = i == 0 || speakerOf(lines[i - 1]) != speakerOf(l);
        return InkWell(
          key: ValueKey('minute-line-${l.seq}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSeek(l.startMs),
          onLongPress: () => onEdit(l),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(color: now ? theme.colorScheme.primary.withValues(alpha: 0.08) : null, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 52, child: Text(minuteClock(l.startMs), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showName) Text(speakerOf(l), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(l.text, style: const TextStyle(height: 1.45)),
                      if (l.edited) Text(tr('แก้ไขแล้ว'), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TranslateTab extends StatelessWidget {
  const _TranslateTab({
    required this.meeting,
    required this.lines,
    required this.translations,
    required this.status,
    required this.viewLang,
    required this.onView,
    required this.onTranslate,
    required this.speakerOf,
  });
  final MinuteMeeting meeting;
  final List<MinuteLine> lines;
  final Map<String, Map<String, String>> translations;
  final Map<String, String> status;
  final String? viewLang;
  final ValueChanged<String> onView;
  final ValueChanged<String> onTranslate;
  final String Function(MinuteLine) speakerOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final have = translations.keys.where((k) => k != meeting.locale).toList();
    final lang = viewLang ?? have.firstOrNull;
    final map = lang == null ? null : translations[lang];
    return Column(
      key: const ValueKey('minute-translate'),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            for (final e in kMinuteLangs.entries)
              if (e.key != meeting.locale)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: translations.containsKey(e.key)
                      ? ChoiceChip(key: ValueKey('minute-tr-view-${e.key}'), label: Text(tr(e.value)), selected: lang == e.key, onSelected: (_) => onView(e.key))
                      : ActionChip(
                          key: ValueKey('minute-tr-make-${e.key}'),
                          avatar: status[e.key] == 'working' ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.plus, size: 16),
                          label: Text(tr(e.value)),
                          onPressed: status[e.key] == 'working' || lines.isEmpty ? null : () => onTranslate(e.key),
                        ),
                ),
          ]),
        ),
        Expanded(
          child: map == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(tr('เลือกภาษาด้านบนเพื่อแปลทั้งการประชุม (ข้อความ + สรุป)'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final l = lines[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 52, child: Text(minuteClock(l.startMs), style: theme.textTheme.bodySmall)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(map['${l.seq}'] ?? '…', style: const TextStyle(height: 1.45, fontWeight: FontWeight.w500)),
                            Text(l.text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AskTab extends StatefulWidget {
  const _AskTab({required this.meetingId, required this.onSeek, required this.enabled});
  final String meetingId;
  final ValueChanged<int> onSeek;
  final bool enabled;
  @override
  State<_AskTab> createState() => _AskTabState();
}

class _AskTabState extends State<_AskTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  final _qa = <(String, String?, List<int>)>[];
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static const _suggest = ['สรุปสั้น ๆ 3 บรรทัด', 'ใครรับผิดชอบงานอะไรบ้าง', 'มีตัวเลขหรือวันที่สำคัญอะไรบ้าง', 'ลูกค้ากังวลเรื่องอะไร'];

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _qa.add((q.trim(), null, const []));
      _q.clear();
    });
    try {
      final r = await context.read<AppConfig>().apiClient.askMinuteMeeting(widget.meetingId, q.trim());
      final refs = [for (final x in (r['refs'] as List? ?? const [])) if (x is Map && x['at_ms'] is num) (x['at_ms'] as num).toInt()];
      setState(() => _qa[_qa.length - 1] = (q.trim(), '${r['answer'] ?? ''}', refs));
    } catch (e) {
      setState(() => _qa[_qa.length - 1] = (q.trim(), e is ApiEnvelopeException ? e.message : tr('ถามไม่สำเร็จ'), const []));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('minute-ask'),
      children: [
        Expanded(
          child: _qa.isEmpty
              ? ListView(padding: const EdgeInsets.all(20), children: [
                  Text(tr('ถามไอแซคเกี่ยวกับการประชุมนี้'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final s in _suggest) ActionChip(label: Text(tr(s)), onPressed: widget.enabled ? () => _ask(tr(s)) : null)]),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _qa.length,
                  itemBuilder: (_, i) {
                    final (q, a, refs) = _qa[i];
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6, left: 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                          child: Text(q),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 14, right: 20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
                        child: a == null ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : _TimeLinkText(a, onSeek: widget.onSeek),
                      ),
                    ]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('minute-ask-input'),
                  controller: _q,
                  enabled: widget.enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _ask,
                  decoration: InputDecoration(hintText: tr('พิมพ์คำถาม…'), filled: true, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(key: const ValueKey('minute-ask-send'), onPressed: _busy || !widget.enabled ? null : () => _ask(_q.text), icon: const Icon(NxI.paperPlaneTilt)),
            ]),
          ),
        ),
      ],
    );
  }
}
