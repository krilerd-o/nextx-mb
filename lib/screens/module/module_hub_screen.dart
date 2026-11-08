import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/isaac_menu.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_refresh.dart';

class ModuleHubScreen extends StatefulWidget {
  const ModuleHubScreen({super.key});

  @override
  State<ModuleHubScreen> createState() => _ModuleHubScreenState();
}

class _ModuleHubScreenState extends State<ModuleHubScreen> {
  IsaacAccess? _isaac;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIsaac());
  }

  Future<void> _loadIsaac({bool fresh = false}) async {
    final config = context.read<AppConfig>();
    if (!config.isLoggedIn) return;
    final biz = config.session.businessId ?? '';
    final cached = IsaacAccessCache.peek(biz);
    if (cached != null && mounted) setState(() => _isaac = cached);
    final a = await IsaacAccessCache.load(config.apiClient, biz, fresh: fresh);
    if (mounted) setState(() => _isaac = a);
  }

  static IconData _isaacIcon(String key) => switch (key) {
        'ai-assistant' => NxI.sparkle,
        'isaac-notebook' => NxI.bookOpen,
        'ai-minute-auto' => NxI.microphone,
        'isaac-ai-agent' => NxI.robot,
        _ => NxI.eye,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.select((AppConfig c) => c.session);
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
          child: NxRefresh(
            color: theme.colorScheme.primary,
            onRefresh: () => _loadIsaac(fresh: true),
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
                                  Text(tr(item.title), style: theme.textTheme.titleMedium),
                                  Text(
                                    tr(item.subtitle),
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
                // ── ISAAC AI (same group, items and rules as the web menu)
                if ((_isaac?.visibleItems(session) ?? const []).isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Row(children: [
                    Icon(NxI.sparkle, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('ISAAC AI', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  NxSurfaceCard(
                    key: const ValueKey('hub-isaac'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(children: [
                      for (final it in _isaac!.visibleItems(session))
                        ListTile(
                          key: ValueKey('hub-isaac-${it.key}'),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                            child: Icon(_isaacIcon(it.key), size: 20, color: theme.colorScheme.primary),
                          ),
                          title: Text(it.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          subtitle: Text(tr(it.subtitle), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Icon(NxI.caretRight, size: 18, color: theme.colorScheme.onSurfaceVariant),
                          onTap: () => context.push(it.route),
                        ),
                    ]),
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
