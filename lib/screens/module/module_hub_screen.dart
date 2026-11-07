import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../core/error_reporting.dart';

class ModuleHubScreen extends StatefulWidget {
  const ModuleHubScreen({super.key});

  @override
  State<ModuleHubScreen> createState() => _ModuleHubScreenState();
}

class _ModuleHubScreenState extends State<ModuleHubScreen> {
  List<Map<String, dynamic>> _recent = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecent());
  }

  Future<void> _loadRecent() async {
    if (!mounted) return;
    final config = context.read<AppConfig>();
    if (!config.isLoggedIn) return;
    final api = config.apiClient;
    final next = <Map<String, dynamic>>[];
    try {
      final jobs = await api.getMyJobs(limit: 5);
      for (final row in jobs.take(5)) {
        next.add({'module': 'job', 'row': row});
      }
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
    try {
      final page = await api.getEntityList('activity', limit: 5);
      for (final row in page.items.take(5)) {
        next.add({'module': 'activity', 'row': row});
      }
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
    if (!mounted) return;
    setState(() => _recent = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<AppConfig>().session;
    final bp = NxBreakpoint.of(context);

    final items = <_HubItem>[
      if (MenuAccess.allow(session, MenuAccess.quotation) ||
          MenuAccess.allow(session, MenuAccess.leaveManagement) ||
          MenuAccess.allow(session, MenuAccess.pendingApprovals))
        const _HubItem(NxI.checkCircle, 'รออนุมัติ', 'ใบเสนอราคา การลา คำขอเข้าร่วม', AppRoutes.approvals),
      if (MenuAccess.anyCrm(session))
        const _HubItem(NxI.users, 'CRM', 'ลูกค้า สินค้า และงานขาย', AppRoutes.crmHome),
      if (MenuAccess.anyCalendar(session))
        const _HubItem(NxI.calendarBlank, 'ปฏิทิน', 'กิจกรรมและเช็คอิน', AppRoutes.calendar),
      if (MenuAccess.anyFsm(session))
        const _HubItem(NxI.wrench, 'FSM', 'งานบริการภาคสนาม', AppRoutes.fsmHome),
      if (MenuAccess.allow(session, MenuAccess.workspace))
        const _HubItem(NxI.kanban, 'Workspace', 'บอร์ดและ worklog', AppRoutes.workspaceHome),
      if (MenuAccess.allow(session, MenuAccess.chat))
        const _HubItem(NxI.chatCircle, 'แชท', 'ทีมเรียลไทม์', AppRoutes.chatHome),
      if (MenuAccess.allow(session, MenuAccess.ai))
        const _HubItem(NxI.robot, 'AI', 'ผู้ช่วย', AppRoutes.aiChat),
      if (MenuAccess.allow(session, MenuAccess.files))
        const _HubItem(NxI.folder, 'ไฟล์', 'กล้องและอัปโหลด', AppRoutes.files),
      if (MenuAccess.allow(session, MenuAccess.storeOrders) ||
          (MenuAccess.allow(session, MenuAccess.storeStock) && session.isBusinessAdmin))
        const _HubItem(NxI.package, 'ร้านค้า', 'ออเดอร์และสต็อก', AppRoutes.commerce),
      if (MenuAccess.allow(session, MenuAccess.mailbox))
        const _HubItem(NxI.envelope, 'เมล', 'อ่าน เขียน และตอบกลับ', AppRoutes.mail),
      if (MenuAccess.anyHr(session) || MenuAccess.allow(session, MenuAccess.leaveManagement))
        const _HubItem(NxI.briefcase, 'HR', 'ลงเวลาและการลา', AppRoutes.hrHome),
      if (MenuAccess.allow(session, MenuAccess.job))
        const _HubItem(NxI.wrench, 'งานช่าง', 'งานบริการที่ได้รับมอบหมาย', AppRoutes.jobs),
      const _HubItem(NxI.magnifyingGlass, 'ค้นหา', 'ค้นหาทุกโมดูล', AppRoutes.globalSearch),
      const _HubItem(NxI.bell, 'แจ้งเตือน', 'การแจ้งเตือนทั้งหมด', AppRoutes.notifications),
      const _HubItem(NxI.sparkle, 'มีอะไรใหม่', 'ประกาศเวอร์ชันและฟีเจอร์ใหม่', AppRoutes.whatsNew),
      const _HubItem(NxI.gear, 'ตั้งค่า', 'ธุรกิจ Package เมนูล่าง ธีม', AppRoutes.settings),
    ];

    return Column(
      children: [
        const NxAppHeader.hub(),
        Expanded(
          child: RefreshIndicator(
            color: theme.colorScheme.primary,
            onRefresh: _loadRecent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: bp.scrollPadding(context, inShell: true),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 12.0;
                    final cols = bp.gridColumns.clamp(2, 4);
                    final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final item in items)
                          SizedBox(
                            width: w,
                            child: NxSurfaceCard(
                              onTap: () => context.push(item.route),
                              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: nxAvatarColor(item.title).withValues(alpha: 0.16),
                                    child: Icon(item.icon, color: nxAvatarColor(item.title), size: 20),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(item.title, style: theme.textTheme.titleMedium),
                                  Text(
                                    item.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (_recent.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('ล่าสุด', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  for (final item in _recent)
                    DenseCardTile(
                      title: entityTitle(
                        Map<String, dynamic>.from(item['row'] as Map),
                        module: item['module']?.toString(),
                      ),
                      subtitle: item['module']?.toString(),
                      onTap: () {
                        final module = item['module']?.toString();
                        final row = Map<String, dynamic>.from(item['row'] as Map);
                        final id = strId(row['id']);
                        if (module == 'job' && id.isNotEmpty) {
                          context.push(AppRoutes.job(id));
                        } else if (module == 'activity' && id.isNotEmpty) {
                          context.push(AppRoutes.activity(id));
                        } else if (module == 'job') {
                          context.push(AppRoutes.jobs);
                        } else {
                          context.push(AppRoutes.calendar);
                        }
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HubItem {
  const _HubItem(this.icon, this.title, this.subtitle, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}
