import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_scroll_scaffold.dart';

/// Profile-area page frame: floating header, content under it, centred at
/// [maxWidth] on tablets, optional pull-to-refresh.
class ProfileSubPage extends StatelessWidget {
  const ProfileSubPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.onRefresh,
    this.maxWidth = 720,
    this.controller,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;
  final double maxWidth;
  final ScrollController? controller;

  /// Side padding that keeps content at most [maxWidth] wide.
  static EdgeInsets padding(BuildContext context, {double maxWidth = 720}) {
    final pad = NxBreakpoint.of(context).scrollPadding(context);
    final w = MediaQuery.sizeOf(context).width;
    final h = math.max(pad.left, (w - maxWidth) / 2);
    return EdgeInsets.fromLTRB(h, pad.top + NxScrollScaffold.topInset(context), h, pad.bottom + 16);
  }

  @override
  Widget build(BuildContext context) {
    return NxScrollScaffold(
      insetBody: false,
      header: NxAppHeader(title: title, actions: actions),
      body: Builder(builder: (context) {
        final list = ListView(
          controller: controller,
          padding: padding(context, maxWidth: maxWidth),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: children,
        );
        return onRefresh == null ? list : NxRefresh(onRefresh: onRefresh!, child: list);
      }),
    );
  }
}

/// True for "this server has no such endpoint yet" (plain 404 / Express
/// "Cannot GET", or a NEXTX 404 envelope for a missing route).
bool isMissingEndpoint(Object e) {
  if (e is ApiException) return e.statusCode == 404 || e.statusCode == 405 || e.statusCode == 501;
  if (e is ApiEnvelopeException) return e.statusCode == 404 || e.statusCode == 501 || e.errorCode == 'NOT_MOCKED';
  return false;
}

/// Big hero icon in a soft tinted circle (empty / success states).
class ProfileHeroIcon extends StatelessWidget {
  const ProfileHeroIcon({super.key, required this.icon, required this.color, this.size = 72});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.10)]),
        ),
        child: Icon(icon, size: size * 0.46, color: color),
      ),
    );
  }
}

/// Numbered step pills: `1 ยืนยันตัวตน — 2 ตั้งรหัสใหม่`.
class ProfileSteps extends StatelessWidget {
  const ProfileSteps({super.key, required this.labels, required this.current});
  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget line(bool on, bool show) => Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            height: 2,
            color: !show ? Colors.transparent : (on ? cs.primary : cs.outlineVariant),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Column(children: [
              Row(children: [
                line(i <= current, i > 0),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i <= current ? cs.primary : cs.surfaceContainerHighest),
                  child: i < current
                      ? Icon(NxI.check, size: 15, color: cs.onPrimary)
                      : Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(color: i <= current ? cs.onPrimary : cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                ),
                line(i < current, i < labels.length - 1),
              ]),
              const SizedBox(height: 6),
              Text(
                tr(labels[i]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: i == current ? cs.onSurface : cs.onSurfaceVariant,
                  fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Inline red error line.
class ProfileErrorText extends StatelessWidget {
  const ProfileErrorText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(NxI.warningCircle, size: 16, color: cs.error)),
        const SizedBox(width: 6),
        Expanded(child: Text(tr(text), style: TextStyle(color: cs.error))),
      ]),
    );
  }
}
