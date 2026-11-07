import 'package:flutter/material.dart';
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
        const SectionHeader('HR'),
        if (tiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('ไม่มีเมนู HR ที่เข้าถึงได้')),
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
                          Text(t.title, style: theme.textTheme.titleMedium),
                          Text(t.subtitle, style: theme.textTheme.bodySmall),
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
