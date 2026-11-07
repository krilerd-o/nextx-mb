import 'package:flutter/material.dart';

import '../core/effects.dart';

/// Text that appears word by word with a soft fade (expo-animated-streaming-text).
/// Shows the full text at once when effects are off.
class NxStreamingText extends StatefulWidget {
  const NxStreamingText(
    this.text, {
    super.key,
    this.style,
    this.wordDelay = const Duration(milliseconds: 45),
    this.fade = const Duration(milliseconds: 260),
  });

  final String text;
  final TextStyle? style;
  final Duration wordDelay;
  final Duration fade;

  @override
  State<NxStreamingText> createState() => _NxStreamingTextState();
}

class _NxStreamingTextState extends State<NxStreamingText> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  List<String> _words = const [];

  /// Splits keeping whitespace attached, so Thai (few spaces) streams by
  /// short chunks instead of one long run.
  static List<String> split(String text) {
    final out = <String>[];
    final re = RegExp(r'\S+\s*|\s+');
    for (final m in re.allMatches(text)) {
      final w = m.group(0)!;
      if (w.trim().length > 12) {
        for (var i = 0; i < w.length; i += 6) {
          out.add(w.substring(i, i + 6 > w.length ? w.length : i + 6));
        }
      } else {
        out.add(w);
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
    _reset();
  }

  void _reset() {
    _words = split(widget.text);
    final total = widget.wordDelay * _words.length + widget.fade;
    _c
      ..duration = total
      ..forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant NxStreamingText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.style ?? DefaultTextStyle.of(context).style;
    final style = raw.color == null ? raw.copyWith(color: Theme.of(context).colorScheme.onSurface) : raw;
    if (!Effects.animate(context)) return Text(widget.text, style: style);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final totalMs = _c.duration!.inMicroseconds.toDouble();
        final t = _c.value * totalMs;
        final spans = <TextSpan>[];
        for (var i = 0; i < _words.length; i++) {
          final start = widget.wordDelay.inMicroseconds * i;
          final a = ((t - start) / widget.fade.inMicroseconds).clamp(0.0, 1.0);
          spans.add(TextSpan(text: _words[i], style: style.copyWith(color: style.color!.withValues(alpha: style.color!.a * a))));
        }
        return Text.rich(TextSpan(children: spans), style: style);
      },
    );
  }
}
