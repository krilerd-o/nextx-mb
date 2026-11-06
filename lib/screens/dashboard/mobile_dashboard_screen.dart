import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/unread_service.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen> {
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _attendance;
  int _pending = 0;
  int _unread = 0;
  bool _loading = true;
  bool _refreshing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final had = _health != null || _attendance != null;
    setState(() {
      _loading = !had;
      _refreshing = had;
      _error = null;
    });
    final api = context.read<AppConfig>().apiClient;
    try {
      final health = await api.getHealth();
      Map<String, dynamic>? attendance;
      var pending = 0;
      var unread = 0;
      try {
        attendance = await api.getAttendanceSummary();
      } catch (_) {}
      try {
        final jobs = await api.getMyJobs(limit: 20);
        pending = jobs.length;
      } catch (_) {}
      try {
        await UnreadNotifications.instance.refresh(api);
        unread = UnreadNotifications.instance.count;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _health = health;
        _attendance = attendance;
        _pending = pending;
        _unread = unread;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final bp = NxBreakpoint.of(context);
    final clocked = _attendance?['clock_in_at'] != null;

    return Column(
      children: [
        NxAppHeader.hub(
          actions: [
            IconButton(icon: const Icon(NxI.arrowCounterClockwise), tooltip: 'รีเฟรช', onPressed: _load),
          ],
        ),
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loading
              ? ListView(
                  padding: bp.scrollPadding(context, inShell: true),
                  children: const [NxSkeletonKpiGrid()],
                )
              : RefreshIndicator(
                  color: colorScheme.primary,
                  onRefresh: _load,
                  child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: bp.scrollPadding(context, inShell: true),
                  children: [
                    if (config.session.displayName != null)
                      Text(
                        'สวัสดี ${config.session.displayName}',
                        style: theme.textTheme.headlineMedium,
                      ),
                    if (config.session.businessName != null)
                      Text(
                        config.session.businessName!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 16),
                    _KpiGrid(
                      children: [
                        _KpiCard(
                          label: 'ลงเวลาวันนี้',
                          value: clocked ? 'เข้าแล้ว' : 'ยังไม่เข้า',
                          icon: NxI.clock,
                          color: colorScheme.primary,
                          onTap: () => context.push(AppRoutes.attendance),
                        ),
                        _KpiCard(
                          label: 'งานของฉัน',
                          value: '$_pending',
                          icon: NxI.checkCircle,
                          color: const Color(0xFFF59E0B),
                          onTap: () => context.push(AppRoutes.jobs),
                        ),
                        _KpiCard(
                          label: 'แจ้งเตือน',
                          value: '$_unread',
                          icon: NxI.bellRinging,
                          color: const Color(0xFF14B8A6),
                          onTap: () => context.push(AppRoutes.notifications),
                        ),
                        _KpiCard(
                          label: 'API',
                          value: _health != null ? 'OK' : '—',
                          icon: NxI.cloud,
                          color: colorScheme.outline,
                        ),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          formatApiError(_error!),
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text('ล่าสุด', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    NxSurfaceCard(
                      onTap: () => context.push(AppRoutes.attendance),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(NxI.clock, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(child: Text('ลงเวลา', style: theme.textTheme.titleMedium)),
                          Icon(NxI.caretRight, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    NxSurfaceCard(
                      onTap: () => context.push(AppRoutes.fsmHome),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(NxI.wrench, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 12),
                          Expanded(child: Text('งานภาคสนาม', style: theme.textTheme.titleMedium)),
                          Icon(NxI.caretRight, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    final cols = bp.width >= 340 ? bp.gridColumns.clamp(2, 4) : 1;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final w = cols == 1 ? c.maxWidth : (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NxSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.displayLarge?.copyWith(fontSize: 32, height: 1.05),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
