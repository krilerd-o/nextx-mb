import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/notebook/notebook_studio_meta.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_audio_player_card.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_studio_views.dart' show studioPadding;
import 'notebook_widgets.dart';

/// Audio Overview v2: two hosts talking about the sources ("ผู้ดำเนินรายการ A/B").

/// Colours of the two hosts (A indigo, B coral).
const kHostA = [Color(0xFF6366F1), Color(0xFF8B5CF6)];
const kHostB = [Color(0xFFF97316), Color(0xFFEC4899)];

/// Format + length picked before making an Audio Overview, or null when cancelled.
Future<({String format, String length})?> showAudioOptionsSheet(BuildContext context) =>
    showAppBottomSheet<({String format, String length})>(context: context, title: null, child: const AudioOptionsForm());

class AudioOptionsForm extends StatefulWidget {
  const AudioOptionsForm({super.key});

  @override
  State<AudioOptionsForm> createState() => _AudioOptionsFormState();
}

class _AudioOptionsFormState extends State<AudioOptionsForm> {
  String _format = 'deep_dive';
  String _length = 'default';

  static const _icons = {
    'brief': LucideIcons300.zap,
    'deep_dive': LucideIcons300.audioLines,
    'critique': LucideIcons300.scale,
    'debate': LucideIcons300.messagesSquare,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final label = theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant);
    return Column(key: const ValueKey('notebook-audio-options'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const StudioKindBadge(kind: StudioKind.audio, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ภาพรวมเสียง'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(tr('สองผู้ดำเนินรายการคุยกันจากแหล่งข้อมูลที่เลือก'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      Text(tr('รูปแบบ'), style: label),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 520 ? 4 : 2;
        Widget card(String id, String title, String hint) => _Choice(
              key: ValueKey('audio-format-$id'),
              selected: _format == id,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _format = id);
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_icons[id], size: 20, color: _format == id ? kNotebookAccent : cs.onSurfaceVariant),
                  const Spacer(),
                  if (_format == id) const Icon(NxI.checkCircle, size: 18, color: kNotebookAccent),
                ]),
                const SizedBox(height: 6),
                Text(tr(title), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(tr(hint), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
              ]),
            );
        // Rows of equal-height cards (hints wrap differently per language).
        return Column(children: [
          for (var r = 0; r < kAudioFormats.length; r += cols) ...[
            if (r > 0) const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = r; i < r + cols; i++) ...[
                  if (i > r) const SizedBox(width: 8),
                  Expanded(child: i < kAudioFormats.length ? card(kAudioFormats[i].$1, kAudioFormats[i].$2, kAudioFormats[i].$3) : const SizedBox()),
                ],
              ]),
            ),
          ],
        ]);
      }),
      const SizedBox(height: 16),
      Text(tr('ความยาว'), style: label),
      const SizedBox(height: 8),
      KeyedSubtree(
        key: const ValueKey('audio-length'),
        child: NxSlidingSegmented<String>(
          value: _length,
          options: [for (final (id, l) in kAudioLengths) (id, l, null)],
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _length = v);
          },
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: kNotebookAccent.withValues(alpha: dark ? 0.16 : 0.06), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const _HostAvatar(a: true, size: 26),
          const SizedBox(width: 4),
          const _HostAvatar(a: false, size: 26),
          const SizedBox(width: 10),
          Expanded(child: Text(tr('ใช้เวลาสร้างสักครู่ — ทำงานต่อได้ ไอแซคจะเปิดให้เมื่อเสร็จ'), style: theme.textTheme.bodySmall?.copyWith(height: 1.4))),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const ValueKey('audio-generate'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: kNotebookAccent),
        onPressed: () => Navigator.of(context).pop((format: _format, length: _length)),
        icon: const Icon(LucideIcons300.sparkles, size: 18),
        label: Text(tr('สร้างภาพรวมเสียง')),
      ),
    ]);
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.selected, required this.child, this.onTap});
  final bool selected;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected ? kNotebookAccent.withValues(alpha: dark ? 0.2 : 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? kNotebookAccent : cs.outlineVariant.withValues(alpha: 0.6), width: selected ? 1.5 : 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HostAvatar extends StatelessWidget {
  const _HostAvatar({required this.a, this.size = 34});
  final bool a;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: a ? kHostA : kHostB),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
        ),
        child: Text(a ? 'A' : 'B', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42, height: 1.1)),
      );
}

String _clock(int ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Player + transcript of a v2 Audio Overview; the line being played is
/// highlighted and tapping a line seeks there. Without voice (TTS error or no
/// timings) the script is shown on its own with a note.
class AudioOverviewView extends StatefulWidget {
  const AudioOverviewView({super.key, required this.c, required this.note, required this.overview});
  final NotebookController c;
  final NotebookNote note;
  final AudioOverview overview;

  @override
  State<AudioOverviewView> createState() => _AudioOverviewViewState();
}

class _AudioOverviewViewState extends State<AudioOverviewView> {
  final _player = NxAudioPlayerController();
  late final List<GlobalKey> _keys = List.generate(widget.overview.turns.length, (_) => GlobalKey());
  int _current = -1;

  AudioOverview get _o => widget.overview;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _player.dispose();
    super.dispose();
  }

  void _onPlayer() {
    final i = (!_player.playing && _player.lastSeekMs == null) ? -1 : _o.turnAt(_player.positionMs);
    if (i == _current || !mounted) return;
    setState(() => _current = i);
    // Keep the line being played in view while listening.
    if (i >= 0 && _player.playing) {
      final ctx = _keys[i].currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.3, alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
    }
  }

  bool get _canSeek => _o.timed && widget.note.downloadUrl != null;

  void _seek(int i) {
    final t = _o.turns[i];
    if (!_canSeek || t.startMs == null) return;
    HapticFeedback.selectionClick();
    _player.seekTo(t.startMs!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final n = widget.note;
    final url = n.downloadUrl;
    final o = _o;
    final noVoice = !o.timed || url == null;
    final dur = o.durationMs ?? (o.turns.lastOrNull?.endMs);
    final children = <Widget>[
      if (!noVoice)
        NxAudioPlayerCard(
          key: const ValueKey('audio-overview-player'),
          title: n.displayTitle,
          subtitle: '${tr(audioFormatLabel(o.format))} · ${tr(audioLengthLabel(o.length))} · ${tr('2 ผู้ดำเนินรายการ')}',
          fileName: n.fileName,
          durationMs: dur,
          controller: _player,
          load: () => widget.c.downloadExport(url),
          trailing: const IsaacAvatar(mood: 'speaking', size: 34, ring: false, animate: false),
        )
      else
        Container(
          key: const ValueKey('audio-overview-no-voice'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: dark ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const IsaacAvatar(mood: 'shrug', size: 44, ring: false, animate: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(LucideIcons300.volumeX, size: 16, color: dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr('สร้างเสียงพูดไม่สำเร็จ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 4),
                Text(tr('ไอแซคเขียนบทสนทนาไว้ให้แล้ว อ่านได้ด้านล่าง — ลองสร้างใหม่ภายหลังเพื่อฟังเป็นเสียง'), style: theme.textTheme.bodySmall?.copyWith(height: 1.45, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(context, LucideIcons300.audioLines, audioFormatLabel(o.format), key: 'audio-overview-format'),
        _chip(context, LucideIcons300.timer, audioLengthLabel(o.length)),
        if (!noVoice && dur != null && dur > 0) _chip(context, LucideIcons300.clock, _clock(dur)),
        _chip(context, LucideIcons300.messageSquareText, tr('${o.turns.length} ช่วง')),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _hostLegend(context, true)),
        const SizedBox(width: 8),
        Expanded(child: _hostLegend(context, false)),
      ]),
      NotebookSectionLabel(
        'บทสนทนา',
        trailing: _canSeek ? Text(tr('แตะประโยคเพื่อฟังตรงนั้น'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)) : null,
      ),
      for (final (i, t) in o.turns.indexed) _turn(context, i, t),
    ];
    return ListView(key: const ValueKey('notebook-audio-overview'), padding: studioPadding(context), children: children);
  }

  Widget _chip(BuildContext context, IconData icon, String text, {String? key}) {
    final theme = Theme.of(context);
    return Container(
      key: key == null ? null : ValueKey(key),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(tr(text), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _hostLegend(BuildContext context, bool a) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = a ? kHostA : kHostB;
    final voice = _o.voices.length > (a ? 0 : 1) ? _o.voices[a ? 0 : 1] : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(color: colors.first.withValues(alpha: dark ? 0.18 : 0.08), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        _HostAvatar(a: a, size: 30),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(a ? 'ผู้ดำเนินรายการ A' : 'ผู้ดำเนินรายการ B'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (voice != null) Text(tr('เสียง $voice'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  Widget _turn(BuildContext context, int i, AudioTurn t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final a = t.isA;
    final colors = a ? kHostA : kHostB;
    final current = i == _current;
    final bubble = current ? colors.first.withValues(alpha: dark ? 0.28 : 0.12) : (dark ? const Color(0xFF1C1D26) : Colors.white);
    return Padding(
      key: _keys[i],
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: _HostAvatar(a: a, size: 32)),
        const SizedBox(width: 10),
        Expanded(
          child: Material(
            color: bubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('audio-turn-$i'),
              onTap: _canSeek ? () => _seek(i) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: current ? colors.first.withValues(alpha: 0.7) : cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45), width: current ? 1.5 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        tr(a ? 'ผู้ดำเนินรายการ A' : 'ผู้ดำเนินรายการ B'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: dark ? colors.first.withValues(alpha: 0.95) : colors.last),
                      ),
                    ),
                    if (t.startMs != null && _o.timed) ...[
                      const SizedBox(width: 6),
                      Text(_clock(t.startMs!), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                    const Spacer(),
                    if (current)
                      Row(key: const ValueKey('audio-turn-current'), mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons300.audioWaveform, size: 14, color: colors.first),
                        const SizedBox(width: 4),
                        Text(tr('กำลังเล่น'), style: theme.textTheme.labelSmall?.copyWith(color: colors.first, fontWeight: FontWeight.w800)),
                      ]),
                  ]),
                  const SizedBox(height: 3),
                  Text(t.text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55, fontWeight: current ? FontWeight.w600 : null)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
