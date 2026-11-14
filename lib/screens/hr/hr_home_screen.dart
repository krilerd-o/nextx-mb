import 'package:flutter/material.dart';
import '../../core/nx_swr_cache.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_cached_future.dart';

class HrHomeScreen extends StatelessWidget {
  const HrHomeScreen({super.key, this.standalone = false});

  /// Opened from the "เมนู" tab (own page with back button) vs. as a bottom tab.
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    if (standalone) {
      return const NxScrollScaffold(
        header: NxAppHeader(title: 'HR'),
        body: _HrShortcuts(),
      );
    }
    return const Column(
      children: [
        NxAppHeader.hub(),
        Expanded(child: _HrShortcuts()),
      ],
    );
  }
}

class _HrTile {
  const _HrTile(this.icon, this.title, this.subtitle, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _HrShortcuts extends StatelessWidget {
  const _HrShortcuts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bp = NxBreakpoint.of(context);
    final session = context.select((AppConfig c) => c.session);
    final tiles = <_HrTile>[
      if (MenuAccess.allow(session, MenuAccess.attendance))
        const _HrTile(NxI.clock, 'ลงเวลา', 'เข้า-ออกงานด้วย GPS', AppRoutes.attendance),
      if (MenuAccess.allow(session, MenuAccess.leave))
        const _HrTile(NxI.calendarCheck, 'ยื่นลา', 'ขอลาใหม่', AppRoutes.leaveRequest),
      if (MenuAccess.allow(session, MenuAccess.leave) || MenuAccess.allow(session, MenuAccess.leaveManagement))
        const _HrTile(NxI.note, 'การลาของฉัน', 'สิทธิ์คงเหลือและสถานะ', AppRoutes.leaveList),
      if (MenuAccess.allow(session, MenuAccess.leaveManagement))
        const _HrTile(NxI.checkCircle, 'อนุมัติการลา', 'คำขอที่รอคุณอนุมัติ', AppRoutes.approvals),
      if (MenuAccess.any(session, const [MenuAccess.attendanceReport, MenuAccess.hrDashboard]))
        const _HrTile(NxI.clipboardText, 'รายงานลงเวลา', 'ใครเข้า-ออกงานวันนี้', AppRoutes.attendanceReport),
    ];
    return ListView(
      padding: bp.scrollPadding(context, inShell: true),
      children: [
        _HrTodayCard(
          showAttendance: MenuAccess.allow(session, MenuAccess.attendance),
          showLeave: MenuAccess.allow(session, MenuAccess.leave),
          showApprovals: MenuAccess.allow(session, MenuAccess.leaveManagement),
        ),
        const SectionHeader('HR'),
        if (tiles.isEmpty)
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text(tr('ไม่มีเมนู HR ที่เข้าถึงได้'))),
          ),
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final cols = c.maxWidth >= 640 ? 4 : 2;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles)
                  SizedBox(
                    width: w,
                    child: NxSurfaceCard(
                      onTap: () => context.push(t.route),
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: nxAvatarColor(t.title).withValues(alpha: 0.16),
                            child: Icon(t.icon, color: nxAvatarColor(t.title)),
                          ),
                          const SizedBox(height: 12),
                          Text(tr(t.title), style: theme.textTheme.titleMedium),
                          Text(tr(t.subtitle), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Today at a glance: clock-in status, leave days left per type, requests waiting for me.
class _HrTodayCard extends StatelessWidget {
  const _HrTodayCard({required this.showAttendance, required this.showLeave, required this.showApprovals});
  final bool showAttendance;
  final bool showLeave;
  final bool showApprovals;

  @override
  Widget build(BuildContext context) {
    if (!showAttendance && !showLeave && !showApprovals) return const SizedBox.shrink();
    final api = context.read<AppConfig>().apiClient;
    return NxCachedFuture<Map<String, dynamic>>(
      key: const ValueKey('hr-today'),
      load: () async {
        final r = await Future.wait<dynamic>([
          showAttendance ? api.getAttendanceSummary().catchError((_) => null) : Future.value(null),
          showLeave ? api.getLeaveBalance().catchError((_) => <Map<String, dynamic>>[]) : Future.value(<Map<String, dynamic>>[]),
          showApprovals
              ? api.getLeaveRequests(all: true, status: 'Pending').catchError((_) => <Map<String, dynamic>>[])
              : Future.value(<Map<String, dynamic>>[]),
        ]);
        return {'att': r[0], 'balance': r[1], 'pending': r[2]};
      },
      // The last copy shows at once on the next visit (refreshes underneath).
      cacheKey: NxSwrCache.key('/api/hr/today', query: {'a': showAttendance ? 1 : 0, 'l': showLeave ? 1 : 0, 'p': showApprovals ? 1 : 0}),
      // The today card itself: caption, stat columns, leave chips.
      skeleton: NxSkeleton(
        key: const ValueKey('hr-today-skeleton'),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NxSkeletonCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const NxBone(width: 44, height: 13),
              const SizedBox(height: 12),
              Row(children: [
                for (var i = 0; i < ((showAttendance ? 1 : 0) + (showApprovals ? 1 : 0)).clamp(1, 2); i++)
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      NxBone(width: 18, height: 18, radius: 5),
                      SizedBox(height: 8),
                      NxBone(width: 56, height: 18),
                      SizedBox(height: 6),
                      NxBone(width: 84, height: 10),
                    ]),
                  ),
              ]),
              if (showLeave) ...[
                const SizedBox(height: 14),
                const NxBone(width: 90, height: 11),
                const SizedBox(height: 10),
                const Row(children: [
                  NxBone(width: 96, height: 32, radius: 10),
                  SizedBox(width: 6),
                  NxBone(width: 84, height: 32, radius: 10),
                  SizedBox(width: 6),
                  NxBone(width: 72, height: 32, radius: 10),
                ]),
              ],
            ]),
          ),
        ),
      ),
      builder: (context, d) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final att = d['att'] is Map ? Map<String, dynamic>.from(d['att'] as Map) : null;
        final balance = (d['balance'] as List).cast<Map<String, dynamic>>();
        final pending = (d['pending'] as List).length;
        String hm(dynamic v) {
          final t = parseThai(v);
          return t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        }
        final inAt = hm(att?['clock_in_at']);
        final outAt = hm(att?['clock_out_at']);
        String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
        Widget stat(IconData icon, String title, String value, Color color, {VoidCallback? onTap, Key? key}) => Expanded(
              child: InkWell(
                key: key,
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(height: 6),
                    Text(tr(value), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(tr(title), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NxSurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('วันนี้'), style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(children: [
                if (showAttendance)
                  stat(
                    NxI.clock,
                    inAt.isEmpty ? 'ยังไม่ลงเวลาเข้า' : (outAt.isEmpty ? 'เข้างานแล้ว' : 'ออกงาน $outAt'),
                    inAt.isEmpty ? 'ลงเวลา' : inAt,
                    inAt.isEmpty ? const Color(0xFFF59E0B) : const Color(0xFF16A34A),
                    key: const ValueKey('hr-today-attendance'),
                    onTap: () => context.push(AppRoutes.attendance),
                  ),
                if (showApprovals)
                  stat(NxI.checkCircle, 'รออนุมัติการลา', '$pending', pending > 0 ? cs.error : cs.outline,
                      key: const ValueKey('hr-today-pending'), onTap: () => context.push(AppRoutes.approvals)),
              ]),
              if (showLeave && balance.isNotEmpty) ...[
                const Divider(height: 18),
                Text(tr('สิทธิ์ลาคงเหลือ'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final b in balance)
                    ActionChip(
                      key: ValueKey('hr-balance-${b['leave_type_id']}'),
                      label: Text(tr('${b['leave_type_name'] ?? ''} ${n((num.tryParse('${b['total_days']}') ?? 0) - (num.tryParse('${b['used_days']}') ?? 0))} วัน')),
                      onPressed: () => context.push(AppRoutes.leaveRequest),
                    ),
                ]),
              ],
            ]),
          ),
        );
      },
    );
  }
}
