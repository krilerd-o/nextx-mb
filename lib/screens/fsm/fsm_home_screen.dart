import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_modules.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_surface_card.dart';
import '../crm/entity_list_screen.dart';
import '../jobs/my_jobs_screen.dart';

class FsmHomeScreen extends StatefulWidget {
  const FsmHomeScreen({super.key});

  @override
  State<FsmHomeScreen> createState() => _FsmHomeScreenState();
}

class _FsmHomeScreenState extends State<FsmHomeScreen> {
  final _counts = <String, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  Future<void> _loadCounts() async {
    if (!mounted) return;
    final config = context.read<AppConfig>();
    if (!config.isLoggedIn) return;
    final api = config.apiClient;
    const modules = [
      'job',
      'inspection',
      'service_contract',
      'asset',
      'service_location',
      'skill',
    ];
    final allowed = modules.where((m) => MenuAccess.allow(config.session, EntityModules.menuKeyOf(m))).toList();
    // One round-trip per module, all in parallel instead of one after another.
    final results = await Future.wait(allowed.map((m) async {
      try {
        final page = await api.getEntityList(m, limit: 1);
        return MapEntry(m, page.total ?? page.items.length);
      } catch (e) {
        debugPrint('[counts] $m: $e');
        return null;
      }
    }));
    if (!mounted) return;
    setState(() {
      for (final e in results) {
        if (e != null) _counts[e.key] = e.value;
      }
    });
  }

  void _pushList(String module, String title) {
    nxPush<void>(context, EntityListScreen(module: module, title: title));
  }

  void _moduleShortcuts(_FsmModule m) {
    showNxBlurPanel<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(NxI.arrowSquareOut),
              title: const Text('เปิดรายการ'),
              onTap: () {
                Navigator.pop(ctx);
                _pushList(m.key, m.title);
              },
            ),
            ListTile(
              leading: const Icon(NxI.shareNetwork),
              title: const Text('แชร์ลิงก์'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: AppRoutes.fsmModule(m.key)));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกลิงก์โมดูลแล้ว')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.select((AppConfig c) => c.session);
    final bp = NxBreakpoint.of(context);

    final modules = <_FsmModule>[
      if (MenuAccess.allow(session, MenuAccess.job))
        const _FsmModule(key: 'job', title: 'ใบสั่งงาน', icon: NxI.clipboardText),
      if (MenuAccess.allow(session, MenuAccess.inspection))
        const _FsmModule(key: 'inspection', title: 'ใบตรวจรับ', icon: NxI.clipboard),
      if (MenuAccess.allow(session, MenuAccess.serviceContract))
        const _FsmModule(key: 'service_contract', title: 'สัญญาบริการ', icon: NxI.scroll),
      if (MenuAccess.allow(session, MenuAccess.asset))
        const _FsmModule(key: 'asset', title: 'สินทรัพย์', icon: NxI.hardDrives),
      if (MenuAccess.allow(session, MenuAccess.serviceLocation))
        const _FsmModule(key: 'service_location', title: 'พื้นที่บริการ', icon: NxI.mapPin),
      if (MenuAccess.allow(session, MenuAccess.skill))
        const _FsmModule(key: 'skill', title: 'ทักษะ', icon: NxI.medal),
    ];

    return NxScrollScaffold(
      header: const NxAppHeader(
        title: 'FSM',
        subtitle: 'งานบริการภาคสนาม',
      ),
      body: ListView(
        padding: bp.scrollPadding(context),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final cols = bp.gridColumns.clamp(1, 4);
              final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final m in modules)
                    SizedBox(
                      width: w,
                      child: _ModuleCard(
                        title: m.title,
                        icon: m.icon,
                        count: _counts[m.key],
                        onTap: () => _pushList(m.key, m.title),
                        onLongPress: () => _moduleShortcuts(m),
                      ),
                    ),
                ],
              );
            },
          ),
          if (MenuAccess.allow(session, MenuAccess.job)) ...[
            const SizedBox(height: 28),
            Text('เครื่องมือ', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _ToolCard(
              icon: NxI.wrench,
              title: 'งานที่ได้รับ',
              subtitle: 'เช็คอินและใบตรวจจากงานของฉัน',
              onTap: () => nxPush<void>(context, const MyJobsScreen()),
            ),
          ],
          const SizedBox(height: 12),
          _ToolCard(
            icon: NxI.kanban,
            title: 'ไป Workspace งาน',
            subtitle: 'บอร์ดและ worklog',
            onTap: () => context.push(AppRoutes.workspaceHome),
          ),
        ],
      ),
    );
  }
}

class _FsmModule {
  const _FsmModule({required this.key, required this.title, required this.icon});
  final String key;
  final String title;
  final IconData icon;
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.count,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = nxAvatarColor(title);
    return NxSurfaceCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            count == null ? 'เปิดรายการ' : '$count รายการ',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NxSurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.14),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(NxI.caretRight, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
