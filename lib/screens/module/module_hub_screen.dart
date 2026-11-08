import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/isaac_menu.dart';
import 'menu_group_screen.dart';
import '../../core/menu_groups.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_split_view.dart';

class ModuleHubScreen extends StatefulWidget {
  const ModuleHubScreen({super.key});

  @override
  State<ModuleHubScreen> createState() => _ModuleHubScreenState();
}

class _ModuleHubScreenState extends State<ModuleHubScreen> {
  IsaacAccess? _isaac;
  final _search = TextEditingController();
  String _q = '';
  String? _selected; // two-pane: group shown on the right

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

  static const _general = <MenuItemDef>[
    MenuItemDef(id: 'search', title: 'ค้นหา', subtitle: 'ค้นหาทุกโมดูล', icon: NxI.magnifyingGlass, route: AppRoutes.globalSearch, menuKeys: []),
    MenuItemDef(id: 'notifications', title: 'แจ้งเตือน', subtitle: 'การแจ้งเตือนทั้งหมด', icon: NxI.bell, route: AppRoutes.notifications, menuKeys: []),
    MenuItemDef(id: 'whats-new', title: 'มีอะไรใหม่', subtitle: 'ประกาศเวอร์ชันและฟีเจอร์ใหม่', icon: NxI.sparkle, route: AppRoutes.whatsNew, menuKeys: []),
    MenuItemDef(id: 'settings', title: 'ตั้งค่า', subtitle: 'ธุรกิจ Package เมนูล่าง ธีม', icon: NxI.gear, route: AppRoutes.settings, menuKeys: []),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.select((AppConfig c) => c.session);
    final bp = NxBreakpoint.of(context);
    final groups = visibleMenuGroups(session, isaac: _isaac);
    final q = _q.trim().toLowerCase();

    Widget searchBox() => TextField(
          key: const ValueKey('menu-search'),
          controller: _search,
          onChanged: (v) => setState(() => _q = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('ค้นหาเมนู'),
            prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    tooltip: tr('ล้าง'),
                    icon: const Icon(NxI.x, size: 18),
                    onPressed: () => setState(() {
                      _search.clear();
                      _q = '';
                    }),
                  ),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        );

    Widget searchResults() {
      final hits = <(MenuItemDef, VisibleMenuGroup?)>[
        for (final g in groups)
          for (final it in g.items)
            if ('${it.title} ${it.subtitle} ${g.def.title}'.toLowerCase().contains(q) || tr(it.title).toLowerCase().contains(q)) (it, g),
        for (final it in _general)
          if ('${it.title} ${it.subtitle}'.toLowerCase().contains(q) || tr(it.title).toLowerCase().contains(q)) (it, null),
      ];
      if (hits.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text(tr('ไม่พบเมนู'), style: TextStyle(color: cs.onSurfaceVariant))),
        );
      }
      return NxSurfaceCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          for (final (it, g) in hits) MenuItemTile(item: it, color: g?.def.color ?? cs.primary, groupTitle: g?.def.title),
        ]),
      );
    }

    Widget groupCard(VisibleMenuGroup g, {bool selected = false, VoidCallback? onTap}) {
      final items = g.items;
      final color = g.def.color;
      return NxSurfaceCard(
        key: ValueKey('menu-group-${g.def.id}'),
        onTap: onTap ?? () => context.push(AppRoutes.menuGroup(g.def.id)),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: DecoratedBox(
          decoration: selected
              ? BoxDecoration(border: Border(left: BorderSide(color: color, width: 3)))
              : const BoxDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                  child: Icon(g.def.icon, color: color, size: 21),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                  child: Text('${items.length}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(tr(g.def.title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                items.take(3).map((i) => tr(i.title)).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    Widget generalList() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
              child: Text(tr('ทั่วไป'), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ),
            NxSurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [for (final it in _general) MenuItemTile(item: it, color: cs.primary)]),
            ),
          ],
        );

    // Tablet / unfolded phone: groups on the left, the chosen group's menus on the right.
    if (bp.twoPane && q.isEmpty && groups.isNotEmpty) {
      final sel = groups.firstWhere((g) => g.def.id == _selected, orElse: () => groups.first);
      final pad = bp.scrollPadding(context, inShell: true);
      return Column(children: [
        const NxAppHeader.hub(),
        Expanded(
          child: NxSplitView(
            list: ListView(
              padding: pad,
              children: [
                searchBox(),
                const SizedBox(height: 14),
                for (final g in groups) ...[
                  groupCard(g, selected: g.def.id == sel.def.id, onTap: () => setState(() => _selected = g.def.id)),
                  const SizedBox(height: 10),
                ],
                generalList(),
              ],
            ),
            detail: ListView(
              key: ValueKey('menu-pane-${sel.def.id}'),
              padding: pad,
              children: [
                Row(children: [
                  Icon(sel.def.icon, color: sel.def.color),
                  const SizedBox(width: 10),
                  Text(tr(sel.def.title), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 12),
                MenuGroupBody(group: sel),
              ],
            ),
          ),
        ),
      ]);
    }

    return Column(
      children: [
        const NxAppHeader.hub(),
        Expanded(
          child: NxRefresh(
            color: cs.primary,
            onRefresh: () => _loadIsaac(fresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: bp.scrollPadding(context, inShell: true),
              children: [
                searchBox(),
                const SizedBox(height: 14),
                if (q.isNotEmpty)
                  searchResults()
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 12.0;
                      final cols = bp.gridColumns.clamp(2, 4);
                      final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [for (final g in groups) SizedBox(width: w, child: groupCard(g))],
                      );
                    },
                  ),
                  generalList(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
