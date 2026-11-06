import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_surface_card.dart';
import 'call_log_screen.dart';
import 'entity_list_screen.dart';
import '../../widgets/nx_icons.dart';

class CrmHomeScreen extends StatefulWidget {
  const CrmHomeScreen({super.key});

  @override
  State<CrmHomeScreen> createState() => _CrmHomeScreenState();
}

class _CrmHomeScreenState extends State<CrmHomeScreen> {
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
      'lead',
      'contact',
      'account',
      'deal',
      'case',
      'quotation',
      'product',
      'service',
    ];
    for (final m in modules) {
      try {
        final page = await api.getEntityList(m, limit: 1);
        if (!mounted) return;
        setState(() => _counts[m] = page.total ?? page.items.length);
      } catch (_) {}
    }
  }

  void _pushList(String module, String title) {
    nxPush<void>(context, EntityListScreen(module: module, title: title));
  }

  void _moduleShortcuts(_CrmModule m) {
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
                await Clipboard.setData(ClipboardData(text: AppRoutes.crmModule(m.key)));
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
    final session = context.watch<AppConfig>().session;
    final bp = NxBreakpoint.of(context);

    final customers = <_CrmModule>[
      if (MenuAccess.allow(session, MenuAccess.lead))
        const _CrmModule(key: 'lead', title: 'ผู้มุ่งหวัง', icon: NxI.flag),
      if (MenuAccess.allow(session, MenuAccess.contact))
        const _CrmModule(key: 'contact', title: 'ผู้ติดต่อ', icon: NxI.addressBook),
      if (MenuAccess.allow(session, MenuAccess.account))
        const _CrmModule(key: 'account', title: 'บัญชีลูกค้า', icon: NxI.buildings),
      if (MenuAccess.allow(session, MenuAccess.deal))
        const _CrmModule(key: 'deal', title: 'ดีล', icon: NxI.handshake),
      if (MenuAccess.allow(session, MenuAccess.quotation))
        const _CrmModule(key: 'quotation', title: 'ใบเสนอราคา', icon: NxI.receipt),
      if (MenuAccess.allow(session, MenuAccess.caseKey))
        const _CrmModule(key: 'case', title: 'เคส', icon: NxI.headset),
    ];
    final catalog = <_CrmModule>[
      if (MenuAccess.allow(session, MenuAccess.product))
        const _CrmModule(key: 'product', title: 'สินค้า', icon: NxI.package),
      if (MenuAccess.allow(session, MenuAccess.service))
        const _CrmModule(key: 'service', title: 'บริการ', icon: NxI.wrench),
    ];

    return Scaffold(
      appBar: const NxAppHeader(
        title: 'CRM',
        subtitle: 'ลูกค้าและงานขาย',
      ),
      body: ListView(
        padding: bp.scrollPadding(context),
        children: [
          _moduleGrid(bp, customers),
          if (catalog.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text('สินค้าและบริการ', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _moduleGrid(bp, catalog),
          ],
          if (MenuAccess.allow(session, MenuAccess.callLog)) ...[
            const SizedBox(height: 28),
            Text('เครื่องมือ', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _ToolCard(
              icon: NxI.phoneCall,
              title: 'บันทึกการโทร',
              subtitle: 'ผลลัพธ์การโทรและงานที่เกี่ยวข้อง',
              onTap: () => nxPush<void>(context, const CallLogScreen()),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.workspaceHome),
            icon: const Icon(NxI.arrowRight),
            label: const Text('ไป Workspace งาน'),
          ),
        ],
      ),
    );
  }

  Widget _moduleGrid(NxBreakpoint bp, List<_CrmModule> modules) {
    return LayoutBuilder(
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
    );
  }
}

class _CrmModule {
  const _CrmModule({required this.key, required this.title, required this.icon});
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
