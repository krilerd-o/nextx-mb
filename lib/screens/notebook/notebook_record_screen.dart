import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_recording.dart';
import '../../services/notebook/notebook_recorder.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_widgets.dart' show kRecordRed;

/// Full-screen recorder: big timer, live waveform, live transcript, bookmarks, pause / resume, stop,
/// minimise (the floating bubble takes over). Driven only by the app-wide [NotebookRecorder].
class NotebookRecordScreen extends StatefulWidget {
  const NotebookRecordScreen({super.key, required this.recorder});
  final NotebookRecorder recorder;

  @override
  State<NotebookRecordScreen> createState() => _NotebookRecordScreenState();
}

class _NotebookRecordScreenState extends State<NotebookRecordScreen> {
  NotebookRecorder get r => widget.recorder;
  Timer? _tick;
  bool _closing = false;

  /// Own messenger: "คั่นเวลาที่ …" stays on this screen (it does not follow the user back to the notebook).
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    r.screenShown();
    r.addListener(_onChange);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    r.removeListener(_onChange);
    _hide();
    super.dispose();
  }

  bool _hidden = false;

  /// The bubble takes over as soon as the screen starts leaving (not only once its route is gone).
  void _hide() {
    if (_hidden) return;
    _hidden = true;
    r.screenHidden();
  }

  void _onChange() {
    if (!mounted) return;
    // Finished (here, from the bubble or the notification): leave the recorder.
    if (!r.active && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    setState(() {});
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: r.title);
    final t = await showAppBottomSheet<String>(
      context: context,
      title: 'ชื่อบันทึกเสียง',
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(key: const ValueKey('notebook-record-title-field'), controller: ctl, autofocus: true, textInputAction: TextInputAction.done, onSubmitted: (v) => Navigator.pop(ctx, v)),
            const SizedBox(height: 16),
            FilledButton(key: const ValueKey('notebook-record-title-save'), onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('บันทึก'))),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (t != null) r.rename(t);
  }

  Future<void> _stop() async {
    HapticFeedback.mediumImpact();
    final ok = await showAppBottomSheet<bool>(
      context: context,
      title: null,
      child: Builder(
        builder: (ctx) => Column(
          key: const ValueKey('notebook-record-stop-confirm'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: IsaacAvatar(mood: 'organize_data', size: 64, animate: false)),
            const SizedBox(height: 12),
            Text(
              tr('จบการบันทึก?'),
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              tr('${recordingClock(r.elapsed.inMilliseconds)} · เสียงจะเก็บเป็นแหล่งข้อมูลในสมุดนี้ แล้วไอแซคจะสรุปให้'),
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('notebook-record-stop-ok'),
              style: FilledButton.styleFrom(backgroundColor: kRecordRed, minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(NxI.stop, size: 18),
              label: Text(tr('จบและให้ไอแซคสรุป'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('บันทึกต่อ'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _closing = true;
    // The app-wide recorder finishes on its own (closing the file, queueing the stop); leave now.
    unawaited(r.stop());
    Navigator.of(context).maybePop();
  }

  void _bookmark() {
    HapticFeedback.selectionClick();
    final b = r.addBookmark();
    final m = _messenger.currentState;
    m?.hideCurrentSnackBar();
    // Floats above the controls (their labels stay visible).
    m?.showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(48, 0, 48, 136 + MediaQuery.paddingOf(context).bottom),
        content: Row(
          children: [
            const Icon(LucideIcons300.bookmark, size: 16, color: Color(0xFFFBBF24)),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('คั่นเวลาที่ ${recordingClock(b.atMs)}'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final paused = r.paused;
    final live = r.recording;
    final pad = MediaQuery.paddingOf(context);
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _hide();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: ScaffoldMessenger(
          key: _messenger,
          child: Scaffold(
            key: const ValueKey('notebook-record-screen'),
            backgroundColor: dark ? const Color(0xFF0E0E13) : const Color(0xFFF7F6FA),
            body: Stack(
              children: [
                // Soft red glow at the top while recording, grey when paused.
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -1.05),
                        radius: 1.15,
                        colors: [
                          (paused ? const Color(0xFF94A3B8) : kRecordRed).withValues(alpha: dark ? 0.22 : 0.13),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(context),
                      const SizedBox(height: 6),
                      _Timer(ms: r.elapsed.inMilliseconds, paused: paused),
                      const SizedBox(height: 8),
                      Center(
                        child: _StatusLine(paused: paused, live: r.live, recording: live),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: ValueListenableBuilder<List<double>>(
                          valueListenable: r.levels,
                          builder: (_, levels, _) => _Waveform(levels: levels, paused: paused, dark: dark),
                        ),
                      ),
                      ValueListenableBuilder<String?>(
                        valueListenable: r.notice,
                        builder: (_, n, _) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: n == null
                              ? const SizedBox(height: 12)
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                  child: _Notice(text: n, onClose: () => r.notice.value = null),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _TranscriptCard(recorder: r),
                        ),
                      ),
                      _controls(context, cs),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 0),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('notebook-record-minimise'),
            tooltip: tr('ย่อเป็นหน้าต่างลอย'),
            icon: const Icon(LucideIcons300.chevronDown, size: 26),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('notebook-record-title'),
              borderRadius: BorderRadius.circular(12),
              onTap: _rename,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    if ((r.notebookTitle ?? '').isNotEmpty)
                      Text(
                        r.notebookTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.2),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(NxI.pencilSimple, size: 14, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          _LivePill(state: r.live),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context, ColorScheme cs) {
    final paused = r.paused;
    final busy = r.phase == RecorderPhase.starting || r.phase == RecorderPhase.finishing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SideButton(
            key: const ValueKey('notebook-record-bookmark'),
            icon: LucideIcons300.bookmarkPlus,
            label: r.bookmarks.isEmpty ? 'คั่นเวลา' : 'คั่นเวลา (${r.bookmarks.length})',
            onTap: busy ? null : _bookmark,
          ),
          Column(
            children: [
              _MainButton(
                paused: paused,
                busy: busy,
                onTap: busy
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        r.togglePause();
                      },
              ),
              const SizedBox(height: 8),
              Text(tr(paused ? 'อัดต่อ' : 'หยุดชั่วคราว'), style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          _SideButton(key: const ValueKey('notebook-record-stop'), icon: NxI.stop, label: 'จบ', color: kRecordRed, filledIcon: true, onTap: busy ? null : _stop),
        ],
      ),
    );
  }
}

class _Timer extends StatelessWidget {
  const _Timer({required this.ms, required this.paused});
  final int ms;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: paused ? 0.55 : 1,
      child: Text(
        recordingClock(ms),
        key: const ValueKey('notebook-record-timer'),
        textAlign: TextAlign.center,
        style: theme.textTheme.displayMedium?.copyWith(fontSize: 60, fontWeight: FontWeight.w300, letterSpacing: 1, height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.paused, required this.live, required this.recording});
  final bool paused;
  final LiveState live;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = paused ? theme.colorScheme.onSurfaceVariant : kRecordRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paused) Icon(LucideIcons300.pause, size: 13, color: color) else _PulseDot(color: color),
          const SizedBox(width: 7),
          Text(
            tr(paused ? 'หยุดชั่วคราว' : (recording ? 'กำลังบันทึก' : 'กำลังเริ่ม…')),
            key: const ValueKey('notebook-record-status'),
            style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// ถอดสด / กำลังเชื่อมต่อ / ถอดภายหลัง.
class _LivePill extends StatelessWidget {
  const _LivePill({required this.state});
  final LiveState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color color, IconData icon) = switch (state) {
      LiveState.live => ('ถอดสด', const Color(0xFF059669), LucideIcons300.captions),
      LiveState.paused => ('ถอดสด', theme.colorScheme.onSurfaceVariant, LucideIcons300.captions),
      LiveState.connecting || LiveState.reconnecting => ('กำลังเชื่อมต่อ', const Color(0xFFD97706), LucideIcons300.loaderCircle),
      LiveState.offline => ('ออฟไลน์', const Color(0xFF64748B), LucideIcons300.wifiOff),
      LiveState.unavailable => ('ถอดภายหลัง', const Color(0xFF64748B), LucideIcons300.captionsOff),
    };
    return Container(
      key: ValueKey('notebook-record-live-${state.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            tr(label),
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, this.size = 9});
  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _a.stop();
      _a.value = 1;
    } else if (!_a.isAnimating) {
      _a.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_a),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Public for the floating bubble.
class NotebookRecordDot extends StatelessWidget {
  const NotebookRecordDot({super.key, this.paused = false, this.size = 9});
  final bool paused;
  final double size;

  @override
  Widget build(BuildContext context) => paused
      ? Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Color(0xFF94A3B8), shape: BoxShape.circle),
        )
      : _PulseDot(color: kRecordRed, size: size);
}

/// Mirrored bars of the recent microphone levels, newest on the right.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.levels, required this.paused, required this.dark});
  final List<double> levels;
  final bool paused;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: CustomPaint(
        key: const ValueKey('notebook-record-wave'),
        size: const Size(double.infinity, 76),
        painter: _WavePainter(levels: levels, color: paused ? (dark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)) : kRecordRed, idle: dark ? Colors.white12 : const Color(0x14000000)),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.levels, required this.color, required this.idle});
  final List<double> levels;
  final Color color;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.2, gap = 2.6;
    final n = (size.width / (barW + gap)).floor();
    final mid = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    for (var i = 0; i < n; i++) {
      final li = levels.length - n + i;
      final v = li >= 0 ? levels[li] : 0.0;
      final h = math.max(3.0, v * size.height * 0.92);
      final x = i * (barW + gap) + barW / 2;
      // Older bars fade a little.
      final age = (n - i) / n;
      paint.color = li >= 0 && v > 0.02 ? color.withValues(alpha: (1 - age * 0.55).clamp(0.3, 1.0)) : idle;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.levels != levels || old.color != color;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFD97706);
    return Container(
      key: const ValueKey('notebook-record-notice'),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons300.info, size: 17, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(text),
              style: TextStyle(fontSize: 12.5, height: 1.35, color: dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E), fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(visualDensity: VisualDensity.compact, tooltip: tr('ปิด'), icon: const Icon(NxI.x, size: 16), onPressed: onClose),
        ],
      ),
    );
  }
}

/// Live transcript: newest at the bottom, follows new lines unless the user scrolled up.
class _TranscriptCard extends StatefulWidget {
  const _TranscriptCard({required this.recorder});
  final NotebookRecorder recorder;

  @override
  State<_TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<_TranscriptCard> {
  final _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    widget.recorder.segments.addListener(_onLines);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final atEnd = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
      if (atEnd != _follow) setState(() => _follow = atEnd);
    });
  }

  @override
  void dispose() {
    widget.recorder.segments.removeListener(_onLines);
    _scroll.dispose();
    super.dispose();
  }

  void _onLines() {
    if (!_follow) {
      setState(() {});
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd(animate: true));
  }

  void _toEnd({bool animate = false}) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      _scroll.animateTo(end, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final r = widget.recorder;
    return Container(
      key: const ValueKey('notebook-record-transcript'),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF17171F) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.3 : 0.45)),
        boxShadow: dark ? null : const [BoxShadow(color: Color(0x0D0F172A), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: ValueListenableBuilder<List<RecordingSegment>>(
        valueListenable: r.segments,
        builder: (context, lines, _) {
          final items = <(int, Object)>[for (final l in lines) (l.startMs, l), for (final b in r.bookmarks) (b.atMs, b)]..sort((a, b) => a.$1.compareTo(b.$1));
          return Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 6),
                    child: Row(
                      children: [
                        const Icon(LucideIcons300.captions, size: 16, color: kIsaacIndigo),
                        const SizedBox(width: 7),
                        Text(tr('ข้อความถอดสด'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        if (lines.isNotEmpty) Text(tr('${lines.where((l) => !l.partial).length} ประโยค'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? _empty(context)
                        : ListView.builder(
                            key: const ValueKey('notebook-record-lines'),
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final it = items[i].$2;
                              if (it is RecordingBookmark) return _BookmarkRow(b: it);
                              return _Line(s: it as RecordingSegment);
                            },
                          ),
                  ),
                ],
              ),
              if (!_follow && items.isNotEmpty)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ActionChip(
                      key: const ValueKey('notebook-record-latest'),
                      avatar: const Icon(LucideIcons300.arrowDown, size: 15),
                      label: Text(tr('ข้อความล่าสุด')),
                      onPressed: () {
                        setState(() => _follow = true);
                        _toEnd(animate: true);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.recorder;
    final later = r.live == LiveState.offline || r.live == LiveState.unavailable;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IsaacAvatar(mood: later ? 'thinking' : 'listening', size: 58, ring: false, animate: false),
            const SizedBox(height: 10),
            Text(
              tr(later ? 'ยังบันทึกเสียงอยู่ — ไอแซคจะถอดข้อความจากไฟล์ให้หลังจบ' : 'เริ่มพูดได้เลย ข้อความจะขึ้นที่นี่'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.s});
  final RecordingSegment s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      key: ValueKey('notebook-record-line-${s.seq}'),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                recordingClock(s.startMs),
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), fontFeatures: const [FontFeature.tabularFigures()]),
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
                Text(
                  s.partial ? '${s.text} …' : s.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                    fontSize: 15,
                    color: s.partial ? cs.onSurfaceVariant.withValues(alpha: 0.75) : cs.onSurface,
                    fontStyle: s.partial ? FontStyle.italic : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkRow extends StatelessWidget {
  const _BookmarkRow({required this.b});
  final RecordingBookmark b;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFD97706);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const SizedBox(width: 46, child: Icon(LucideIcons300.bookmark, size: 15, color: amber)),
          Expanded(child: Container(height: 1, color: amber.withValues(alpha: 0.3))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${tr('คั่นเวลา')} ${recordingClock(b.atMs)}${b.label == null ? '' : ' · ${b.label}'}',
              style: const TextStyle(color: amber, fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Container(height: 1, color: amber.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  const _MainButton({required this.paused, required this.busy, required this.onTap});
  final bool paused;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr(paused ? 'อัดต่อ' : 'หยุดชั่วคราว'),
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: Colors.transparent,
        child: Ink(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: paused ? const [Color(0xFFF43F5E), Color(0xFFBE123C)] : const [Color(0xFF334155), Color(0xFF0F172A)],
            ),
            boxShadow: [BoxShadow(color: (paused ? kRecordRed : const Color(0xFF0F172A)).withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: InkWell(
            key: const ValueKey('notebook-record-toggle'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: busy
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Icon(paused ? NxI.microphone : LucideIcons300.pause, size: 34, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({super.key, required this.icon, required this.label, required this.onTap, this.color, this.filledIcon = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool filledIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final c = color ?? theme.colorScheme.onSurface;
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Material(
            color: dark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
            shape: CircleBorder(side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 60,
                height: 60,
                child: Center(
                  child: filledIcon
                      ? Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                        )
                      : Icon(icon, size: 24, color: c),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
