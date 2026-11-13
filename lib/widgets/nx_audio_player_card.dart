import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/i18n.dart';
import '../services/api_exceptions.dart';
import 'nx_icons.dart';

/// ISAAC tape player look (from the call summary "เทปบันทึกการสนทนา"), as a
/// shared card: play / pause, seek, 10 s back, speed 1–2×, share. The file is
/// fetched by [load] on the first play (authenticated downloads), kept in a
/// temp file, and played with a media audio context that keeps going when the
/// screen locks (Android wake lock; iOS playback category + background audio).
class NxAudioPlayerCard extends StatefulWidget {
  const NxAudioPlayerCard({
    super.key,
    required this.title,
    required this.load,
    this.subtitle,
    this.fileName = 'audio.mp3',
    this.mime = 'audio/mpeg',
    this.durationMs,
    this.trailing,
  });

  final String title;
  final String? subtitle;

  /// Bytes of the audio file (called once, on the first play or share).
  final Future<List<int>> Function() load;
  final String fileName;
  final String mime;

  /// Length known before loading (shown until the player reports it).
  final int? durationMs;

  /// Top-right widget (e.g. ISAAC avatar).
  final Widget? trailing;

  /// Tests: replaces the platform player.
  @visibleForTesting
  static AudioPlayer Function()? playerFactory;

  static const speeds = [1.0, 1.25, 1.5, 2.0];

  @override
  State<NxAudioPlayerCard> createState() => _NxAudioPlayerCardState();
}

String _mmss(int ms) {
  final s = (ms / 1000).floor();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0'), ss = r.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

class _NxAudioPlayerCardState extends State<NxAudioPlayerCard> {
  AudioPlayer? _player;
  String? _path;
  bool _loading = false;
  bool _playing = false;
  int _posMs = 0;
  int? _durMs;
  double _rate = 1;
  String? _error;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    final p = _player;
    if (p != null) unawaited(p.dispose().catchError((_) {}));
    super.dispose();
  }

  Future<String> _file() async {
    final hit = _path;
    if (hit != null) return hit;
    final bytes = await widget.load();
    final dir = await getTemporaryDirectory();
    final safe = widget.fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._\-ก-๙]'), '_');
    final f = File('${dir.path}/nx-audio-${widget.load.hashCode}-$safe');
    await f.writeAsBytes(bytes, flush: true);
    return _path = f.path;
  }

  Future<AudioPlayer> _ensurePlayer(String path) async {
    final existing = _player;
    if (existing != null) return existing;
    final p = (NxAudioPlayerCard.playerFactory ?? AudioPlayer.new)();
    _player = p;
    try {
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(stayAwake: true, contentType: AndroidContentType.speech, usageType: AndroidUsageType.media, audioFocus: AndroidAudioFocus.gain),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ));
    } catch (_) {}
    _subs
      ..add(p.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }))
      ..add(p.onPositionChanged.listen((d) {
        if (mounted) setState(() => _posMs = d.inMilliseconds);
      }))
      ..add(p.onDurationChanged.listen((d) {
        if (mounted) setState(() => _durMs = d.inMilliseconds);
      }))
      ..add(p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _posMs = 0);
      }));
    await p.setSourceDeviceFile(path);
    await p.setPlaybackRate(_rate);
    return p;
  }

  Future<void> _toggle() async {
    if (_loading) return;
    HapticFeedback.selectionClick();
    final p = _player;
    if (p != null && _playing) {
      await p.pause();
      return;
    }
    setState(() {
      _loading = p == null;
      _error = null;
    });
    try {
      final player = await _ensurePlayer(await _file());
      await player.resume();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seek(int ms) async {
    setState(() => _posMs = ms);
    final p = _player;
    if (p != null) {
      await p.seek(Duration(milliseconds: ms));
    }
  }

  void _speed() {
    const speeds = NxAudioPlayerCard.speeds;
    final next = speeds[(speeds.indexOf(_rate) + 1) % speeds.length];
    HapticFeedback.selectionClick();
    setState(() => _rate = next);
    _player?.setPlaybackRate(next);
  }

  Future<void> _share() async {
    try {
      final path = await _file();
      await Share.shareXFiles([XFile(path, mimeType: widget.mime)], subject: widget.title);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hint = theme.hintColor;
    const indigo = Color(0xFF4F46E5);
    final dur = _durMs ?? widget.durationMs ?? 0;
    final pos = dur > 0 ? _posMs.clamp(0, dur) : _posMs;
    final frac = dur > 0 ? pos / dur : 0.0;
    final speedLabel = '${_rate == _rate.roundToDouble() ? _rate.toInt() : _rate}x';
    return Container(
      key: const ValueKey('nx-audio-card'),
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? [const Color(0xFF312E81).withValues(alpha: 0.55), const Color(0xFF4C1D95).withValues(alpha: 0.32)] : const [Color(0xFFEEF2FF), Color(0xFFF5F3FF)],
        ),
        border: Border.all(color: indigo.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Semantics(
            button: true,
            label: tr(_playing ? 'หยุดชั่วคราว' : 'เล่น'),
            child: Material(
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]), shape: BoxShape.circle),
                child: InkWell(
                  key: const ValueKey('nx-audio-play'),
                  onTap: _toggle,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: _loading
                        ? const Padding(padding: EdgeInsets.all(15), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_playing ? NxI.pause : NxI.play, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (widget.subtitle != null)
                Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: hint)),
            ]),
          ),
          ?widget.trailing,
          const SizedBox(width: 6),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: dur > 0 ? (d) => _seek((d.localPosition.dx / c.maxWidth * dur).round().clamp(0, dur)) : null,
              onHorizontalDragUpdate: dur > 0 ? (d) => _seek((d.localPosition.dx / c.maxWidth * dur).round().clamp(0, dur)) : null,
              child: CustomPaint(
                key: const ValueKey('nx-audio-wave'),
                size: Size(c.maxWidth, 34),
                painter: _WavePainter(seed: widget.title.hashCode, progress: frac.toDouble(), active: indigo, idle: indigo.withValues(alpha: dark ? 0.28 : 0.2)),
              ),
            ),
          ),
        ),
        Row(children: [
          Text(_mmss(pos), style: TextStyle(fontSize: 11.5, color: hint, fontFeatures: const [FontFeature.tabularFigures()])),
          const Spacer(),
          IconButton(
            tooltip: tr('ย้อน 10 วินาที'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(NxI.arrowCounterClockwise, size: 18),
            onPressed: _player == null ? null : () => _seek(math.max(0, _posMs - 10000)),
          ),
          TextButton(
            key: const ValueKey('nx-audio-speed'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(40, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: _speed,
            child: Text(speedLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          IconButton(
            key: const ValueKey('nx-audio-share'),
            tooltip: tr('แชร์ไฟล์เสียง'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(NxI.shareNetwork, size: 18),
            onPressed: _share,
          ),
          const SizedBox(width: 4),
          Text(dur > 0 ? _mmss(dur) : '--:--', style: TextStyle(fontSize: 11.5, color: hint, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 8, 8),
            child: Text(tr(_error!), style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
          ),
      ]),
    );
  }
}

/// Decorative waveform; bars left of [progress] take the active colour.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.seed, required this.progress, required this.active, required this.idle});
  final int seed;
  final double progress;
  final Color active;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.0, gap = 2.5;
    final n = (size.width / (barW + gap)).floor();
    final rnd = math.Random(seed);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final t = i / math.max(1, n - 1);
      final env = 0.35 + 0.65 * math.sin(math.pi * (0.1 + 0.8 * t)).abs();
      final h = (0.18 + rnd.nextDouble() * 0.82) * env * size.height;
      final x = i * (barW + gap) + barW / 2;
      paint
        ..color = t <= progress && progress > 0 ? active : idle
        ..strokeWidth = barW;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress || old.seed != seed || old.active != active || old.idle != idle;
}
