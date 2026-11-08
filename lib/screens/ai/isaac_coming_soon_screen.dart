import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';

/// AI Agent / AI Social Watch teaser — same copy as the web
/// (`pages/isaac/IsaacComingSoonPage.jsx`).
class IsaacComingSoonScreen extends StatelessWidget {
  const IsaacComingSoonScreen({super.key, this.product = 'agent'});

  /// `agent` or `social_watch`.
  final String product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final agent = product != 'social_watch';
    final accent = agent ? const Color(0xFF0EA5E9) : const Color(0xFF10B981);
    final title = agent ? 'AI Agent' : 'AI Social Watch';
    final body = agent
        ? 'เอเจนต์อัจฉริยะที่จะช่วยทำงานบน CRM และ Workspace ให้อัตโนมัติ — กำลังพัฒนา'
        : 'เฝ้าดูแชทโซเชียลและสรุปสัญญาณสำคัญให้อัตโนมัติ — กำลังพัฒนา';
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(bottom: false, child: NxAppHeader(title: title, subtitle: 'ISAAC AI')),
      ),
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent.withValues(alpha: 0.16), cs.primary.withValues(alpha: 0.10), Colors.transparent],
              ),
            ),
          ),
        ),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(NxI.sparkle, size: 12, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(tr('เร็วๆ นี้'), style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                  ]),
                ),
                const SizedBox(height: 22),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                  ),
                  child: Icon(agent ? NxI.robot : NxI.eye, size: 36, color: cs.primary),
                ),
                const SizedBox(height: 18),
                Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(tr(body), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5)),
                const SizedBox(height: 26),
                FilledButton.icon(
                  key: const ValueKey('isaac-soon-cta'),
                  onPressed: () => context.push(AppRoutes.aiChat),
                  icon: const Icon(NxI.sparkle, size: 16),
                  label: Text(tr('ไปที่ ISAAC AI Assistant')),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
