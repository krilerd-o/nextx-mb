import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/isaac_menu.dart';
import '../../core/menu_groups.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_surface_card.dart';

/// One menu group (like a web nav-rail panel): section titles as on the web,
/// each with its menus.
class MenuGroupScreen extends StatefulWidget {
  const MenuGroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  State<MenuGroupScreen> createState() => _MenuGroupScreenState();
}

class _MenuGroupScreenState extends State<MenuGroupScreen> {
  IsaacAccess? _isaac;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    final biz = config.session.businessId ?? '';
    _isaac = IsaacAccessCache.peek(biz);
    if (widget.groupId == 'ai') {
      IsaacAccessCache.load(config.apiClient, biz).then((a) {
        if (mounted) setState(() => _isaac = a);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.select((AppConfig c) => c.session);
    final groups = visibleMenuGroups(session, isaac: _isaac);
    final group = groups.where((g) => g.def.id == widget.groupId).firstOrNull;
    final def = group?.def ?? kMenuGroups.where((g) => g.id == widget.groupId).firstOrNull;
    return NxScrollScaffold(
      header: NxAppHeader(title: def?.title ?? 'เมนู'),
      body: Builder(
        builder: (context) => group == null
            ? Center(child: Text(tr('ไม่มีเมนูในกลุ่มนี้')))
            : ListView(
                padding: EdgeInsets.fromLTRB(16, 8 + NxScrollScaffold.topInset(context), 16, 32),
                children: [MenuGroupBody(group: group)],
              ),
      ),
    );
  }
}

/// The sections and menus of [group]; used by the group page and by the
/// right pane of the menu page on tablets / unfolded phones.
class MenuGroupBody extends StatelessWidget {
  const MenuGroupBody({super.key, required this.group});
  final VisibleMenuGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = group.def.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, sec) in group.sections.indexed) ...[
          if (sec.title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(6, i == 0 ? 4 : 18, 6, 8),
              child: Text(
                tr(sec.title!),
                key: ValueKey('menu-section-${sec.title}'),
                style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.3),
              ),
            )
          else if (i > 0)
            const SizedBox(height: 14),
          NxSurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final (j, it) in sec.items.indexed) ...[
                if (j > 0) Divider(height: 1, indent: 66, color: cs.outlineVariant.withValues(alpha: 0.5)),
                MenuItemTile(item: it, color: color),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}

class MenuItemTile extends StatelessWidget {
  const MenuItemTile({super.key, required this.item, required this.color, this.groupTitle});
  final MenuItemDef item;
  final Color color;

  /// Shown under the title in search results ("ลูกค้า · …").
  final String? groupTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      key: ValueKey('menu-item-${item.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
        child: Icon(item.icon, size: 20, color: color),
      ),
      title: Text(tr(item.title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Text(
        groupTitle != null ? '${tr(groupTitle!)} · ${tr(item.subtitle)}' : tr(item.subtitle),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
      onTap: () => context.push(item.route),
    );
  }
}
