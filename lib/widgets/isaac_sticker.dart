import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/effects.dart';
import '../core/isaac_states.dart';
import '../core/nx_network.dart';

/// Isaac, the AI's face (web `AiIsaacSticker.jsx`): the still PNG ships with
/// the app; the animated GIF comes from the server (`/ai-isaac/isaac-<state>.gif`,
/// cached) when effects are on. Mood changes cross-fade.
class IsaacSticker extends StatelessWidget {
  const IsaacSticker({super.key, required this.state, this.size = 56, this.animate = true});

  /// sm 40 · md 56 · lg 104 like the web.
  final String state;
  final double size;
  final bool animate;

  static String assetFor(String state) => 'assets/isaac/isaac-${normalizeIsaacState(state)}.png';

  /// Big welcome Isaac (≥ 100) always moves unless effects are off; small
  /// stickers move only with full effects and not on mobile data (each GIF is
  /// about 1 MB) — the still PNG ships with the app.
  static bool shouldAnimate(BuildContext context, {required double size}) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final level = Effects.of(context);
    if (reduced || level == EffectsLevel.off) return false;
    if (size >= 100) return true;
    return level == EffectsLevel.full && !NxNetwork.instance.metered.value;
  }

  /// States the chat shows first (web `ISAAC_PRELOAD_STATES`).
  static const preloadStates = ['hello', 'thinking_dots', 'speaking', 'answer_ready', 'curious', 'error'];

  /// Warm the GIF cache for [preloadStates] when stickers will move.
  static void preload(BuildContext context) {
    if (!shouldAnimate(context, size: 56)) return;
    final api = context.read<AppConfig>().apiClient;
    for (final s in preloadStates) {
      precacheImage(CachedNetworkImageProvider(api.absoluteUrl('/ai-isaac/isaac-$s.gif')), context).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = normalizeIsaacState(state);
    final still = Image.asset(assetFor(s), width: size, height: size, fit: BoxFit.contain, gaplessPlayback: true);
    final moving = animate && shouldAnimate(context, size: size);
    Widget child = still;
    if (moving) {
      final api = context.read<AppConfig>().apiClient;
      final url = api.absoluteUrl('/ai-isaac/isaac-$s.gif');
      child = CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, _) => still,
        errorWidget: (_, _, _) => still,
        fadeInDuration: const Duration(milliseconds: 120),
        fadeOutDuration: Duration.zero,
      );
    }
    return Semantics(
      label: 'Isaac: ${kIsaacLabels[s] ?? s}',
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(s), child: child),
        ),
      ),
    );
  }
}
