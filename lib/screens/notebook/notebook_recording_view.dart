import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/notebook/notebook_recording.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_audio_player_card.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_markdown.dart';
import '../../widgets/nx_skeleton.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_note_viewer.dart';
import 'notebook_sources_pane.dart' show showSourceViewer;
import 'notebook_widgets.dart';

/// Opens a `recording` source: the tape, the transcript with time stamps (tap → play from there),
/// bookmarks and the summary note.
Future<void> openRecordingSource(BuildContext context, NotebookController c, NotebookSource s) => nxPush<void>(context, NotebookRecordingSourceScreen(c: c, source: s));

class NotebookRecordingSourceScreen extends StatefulWidget {
  const NotebookRecordingSourceScreen({super.key, required this.c, required this.source});
  final NotebookController c;
  final NotebookSource source;

  @override
  State<NotebookRecordingSourceScreen> createState() => _NotebookRecordingSourceScreenState();
}

class _NotebookRecordingSourceScreenState extends State<NotebookRecordingSourceScreen> {
  final _player = NxAudioPlayerController();
  NotebookRecording? _r;
  bool _loading = true;
  String? _error;

  NotebookSource get _s => widget.source;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
    _load();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _player.dispose();
    super.dispose();
  }

  int _lastLine = -1;
  void _onPlayer() {
    // Rebuild only when the highlighted line changes.
    final i = _lineAt(_player.positionMs);
    if (i != _lastLine && mounted) setState(() => _lastLine = i);
  }

  int _lineAt(int ms) {
    final segs = (_r?.segments.isNotEmpty ?? false) ? _r!.segments : parseTranscriptLines(_s.body);
    if (!_player.playing && _player.lastSeekMs == null) return -1;
    for (var i = segs.length - 1; i >= 0; i--) {
      if (segs[i].startMs <= ms) return i;
    }
    return -1;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.c.recordingForSource(_s);
      if (!mounted) return;
      setState(() => _r = r);
    } catch (e) {
      if (mounted) setState(() => _error = notebookError(e).text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _noteId => _r?.noteId ?? widget.c.recordingNotes[_r?.id] ?? _str(_s.config['note_id']);

  static String? _str(Object? v) {
    final s = v?.toString();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }

  Future<void> _openSummary() async {
    final nid = _noteId;
    if (nid == null) return;
    var note = widget.c.noteById(nid);
    if (note == null) {
      await widget.c.load(quiet: true);
      note = widget.c.noteById(nid);
    }
    if (note == null) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('ยังไม่พบโน้ตสรุป — ลองอีกครั้งในอีกสักครู่'))));
      return;
    }
    if (mounted) await openNotebookNote(context, widget.c, note);
  }

  void _seek(int ms) {
    HapticFeedback.selectionClick();
    _player.seekTo(ms);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final dur = r?.durationMs ?? 0;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: NxAppHeader(
            title: _s.displayTitle,
            subtitle: dur > 0 ? '${tr('บันทึกเสียง')} · ${recordingClock(dur)}' : 'บันทึกเสียง',
            actions: [
              IconButton(
                key: const ValueKey('notebook-recording-text'),
                tooltip: tr('ข้อความทั้งหมด'),
                icon: const Icon(LucideIcons300.fileText),
                onPressed: () => showSourceViewer(context, widget.c, _s),
              ),
            ],
          ),
        ),
      ),
      body: NotebookBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = _r;
    final pad = EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom);
    if (_loading && r == null) return const SingleChildScrollView(child: NxSkeletonList(rows: 4));
    // Older / whisper-only recordings: the source text holds `[mm:ss] text` lines.
    final segs = (r?.segments.isNotEmpty ?? false) ? r!.segments : parseTranscriptLines(_s.body);
    final children = <Widget>[];
    if (r != null) {
      children.add(
        NxAudioPlayerCard(
          key: const ValueKey('notebook-recording-player'),
          title: r.displayTitle,
          subtitle: tr('เสียงต้นฉบับ'),
          fileName: 'recording-${r.id}.m4a',
          mime: 'audio/mp4',
          sniffType: true,
          durationMs: r.durationMs > 0 ? r.durationMs : null,
          controller: _player,
          load: () => widget.c.api.downloadNotebookRecordingAudio(widget.c.id, r.id),
          trailing: const IsaacAvatar(mood: 'listening', size: 34, ring: false, animate: false),
        ),
      );
    } else {
      children.add(
        NotebookCard(
          child: Row(
            children: [
              const IsaacAvatar(mood: 'shrug', size: 44, ring: false, animate: false),
              const SizedBox(width: 12),
              Expanded(child: Text(tr(_error ?? 'ไม่พบไฟล์เสียงของแหล่งนี้ — อ่านข้อความด้านล่างได้'))),
              if (_error != null) TextButton(onPressed: _load, child: Text(tr('ลองอีกครั้ง'))),
            ],
          ),
        ),
      );
    }
    children.add(const SizedBox(height: 12));
    children.add(
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('notebook-recording-summary'),
              style: FilledButton.styleFrom(backgroundColor: kNotebookAccent, minimumSize: const Size.fromHeight(46)),
              onPressed: _noteId == null ? null : _openSummary,
              icon: const Icon(LucideIcons300.sparkles, size: 18),
              label: Text(tr(_noteId == null ? (r?.status == RecordingStatus.failed ? 'สรุปไม่สำเร็จ' : 'กำลังสรุป…') : 'ดูสรุป')),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: tr('คัดลอกข้อความ'),
            onPressed: () {
              final text = segs.isEmpty ? _s.body : segs.map((x) => '[${recordingClock(x.startMs)}] ${x.text}').join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('คัดลอกแล้ว'))));
            },
            icon: const Icon(NxI.copySimple, size: 18),
          ),
        ],
      ),
    );
    final cfgBm = _s.config['bookmarks'];
    final bookmarks = (r?.bookmarks.isNotEmpty ?? false)
        ? r!.bookmarks
        : [
            for (final b in (cfgBm is List ? cfgBm : const []))
              if (b is Map) RecordingBookmark.fromJson(Map<String, dynamic>.from(b)),
          ];
    if (bookmarks.isNotEmpty) {
      children.add(const NotebookSectionLabel('คั่นเวลา'));
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, b) in bookmarks.indexed)
              NotebookPill(
                key: ValueKey('notebook-recording-bookmark-$i'),
                leading: const Icon(LucideIcons300.bookmark, size: 15, color: Color(0xFFD97706)),
                label: b.label == null ? recordingClock(b.atMs) : '${recordingClock(b.atMs)} · ${b.label}',
                onTap: () => _seek(b.atMs),
              ),
          ],
        ),
      );
    }
    children.add(NotebookSectionLabel(segs.isEmpty ? 'ข้อความ' : 'ข้อความถอดเสียง · ${segs.length}'));
    if (segs.isEmpty) {
      children.add(
        NotebookCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: _s.body.trim().isEmpty ? Text(tr('ยังไม่มีข้อความ'), style: TextStyle(color: cs.onSurfaceVariant)) : NxMarkdown(data: _s.body),
        ),
      );
    } else {
      final bmAt = {for (final b in bookmarks) b.atMs};
      children.add(
        NotebookCard(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, s) in segs.indexed)
                _TranscriptLine(
                  key: ValueKey('notebook-recording-line-$i'),
                  s: s,
                  active: i == _lastLine,
                  marked: bmAt.any((t) => t >= s.startMs && (s.endMs <= s.startMs || t < s.endMs)),
                  onTap: () => _seek(s.startMs),
                ),
            ],
          ),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            tr('แตะบรรทัดเพื่อฟังจากตรงนั้น'),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(key: const ValueKey('notebook-recording-view'), padding: pad, children: children),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({super.key, required this.s, required this.active, required this.marked, required this.onTap});
  final RecordingSegment s;
  final bool active;
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: active ? kNotebookAccent.withValues(alpha: dark ? 0.2 : 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // At least 50 wide so lines align; grows for h:mm:ss or large text.
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 50),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        recordingClock(s.startMs),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: active ? kNotebookAccent : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (marked)
                        const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(LucideIcons300.bookmark, size: 11, color: Color(0xFFD97706)),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.speaker != null)
                      Text(
                        s.speaker!,
                        style: theme.textTheme.labelSmall?.copyWith(color: kIsaacIndigo, fontWeight: FontWeight.w800),
                      ),
                    Text(s.text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
