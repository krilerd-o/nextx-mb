import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/unread_service.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/isaac_menu.dart';
import 'menu_group_screen.dart';
import '../../core/menu_groups.dart';
import '../../core/app_theme.dart';
import '../../core/menu_hub_prefs.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_back_handler.dart';
import '../../widgets/nx_overlay_panel.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../widgets/nx_refresh.dart';
import '../../widgets/nx_split_view.dart';

/// The "เมนู" tab: menu groups as cards (long-press + drag to reorder) or as
/// one grouped list; search from the header icon.
class ModuleHubScreen extends StatefulWidget {
  const ModuleHubScreen({super.key});

  @override
  State<ModuleHubScreen> createState() => _ModuleHubScreenState();
}

class _ModuleHubScreenState extends State<ModuleHubScreen> {
  IsaacAccess? _isaac;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _q = '';
  bool _searchOpen = false;
  String? _selected; // two-pane: group shown on the right

  /// Last view per user scope, so coming back to the tab does not flash the default.
  static final Map<String, MenuHubView> _viewCache = {};

  MenuHubView _view = MenuHubView.list;
  List<String> _order = defaultMenuOrder;
  String? _viewScope;
  String? _orderScope;

  // Drag & drop of group cards.
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  List<String>? _dragVisible; // visible group ids while a card is being dragged
  String? _dragId;
  Offset? _dragPos;
  Timer? _autoScroll;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Last known ISAAC access (memory, else the copy saved on the device) on the
    // first frame, so its group does not pop in after the rest.
    final config = context.read<AppConfig>();
    if (config.isLoggedIn) _isaac = IsaacAccessCache.peek(config.session.businessId ?? '');
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

  /// Loads the saved view (per user) and group order (per user + business)
  /// whenever the signed-in user or business changes.
  void _syncPrefs(AppConfig config) {
    final vs = config.prefsScope;
    final os = config.businessScope;
    if (vs != _viewScope) {
      _viewScope = vs;
      final cached = _viewCache[vs] ?? MenuHubPrefs.peekView(vs);
      if (cached != null) _view = cached;
      MenuHubPrefs.loadView(vs).then((v) {
        _viewCache[vs] = v;
        if (mounted && _viewScope == vs && _view != v) setState(() => _view = v);
      });
    }
    if (os != _orderScope) {
      _orderScope = os;
      final saved = MenuHubPrefs.peekOrder(os);
      if (saved != null) _order = saved;
      MenuHubPrefs.loadOrder(os).then((o) {
        if (mounted && _orderScope == os) setState(() => _order = o);
      });
    }
  }

  void _setView(MenuHubView v) {
    if (_view == v) return;
    HapticFeedback.selectionClick();
    setState(() => _view = v);
    final s = _viewScope;
    if (s != null) {
      _viewCache[s] = v;
      MenuHubPrefs.saveView(s, v);
    }
  }

  Future<void> _resetOrder() async {
    setState(() => _order = defaultMenuOrder);
    final s = _orderScope;
    if (s != null) await MenuHubPrefs.resetOrder(s);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('รีเซ็ตลำดับเมนูแล้ว'))));
  }

  // ── search ─────────────────────────────────────────────────────────────

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searchOpen = false;
      _search.clear();
      _q = '';
    });
  }

  void _toggleSearch() => _searchOpen && _q.isEmpty ? _closeSearch() : _openSearch();

  // ── drag & drop ────────────────────────────────────────────────────────

  void _startDrag(String id, List<VisibleMenuGroup> groups) {
    HapticFeedback.mediumImpact();
    setState(() {
      _dragId = id;
      _dragVisible = [for (final g in groups) g.def.id];
    });
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
  }

  void _dragOver(String dragged, String target) {
    final list = _dragVisible;
    if (list == null || dragged == target) return;
    final from = list.indexOf(dragged);
    final to = list.indexOf(target);
    if (from < 0 || to < 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      list.removeAt(from);
      list.insert(to, dragged);
    });
  }

  void _endDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPos = null;
    final list = _dragVisible;
    if (list == null) return;
    final next = applyVisibleMenuOrder(_order, list);
    setState(() {
      _order = next;
      _dragVisible = null;
      _dragId = null;
    });
    final s = _orderScope;
    if (s != null) MenuHubPrefs.saveOrder(s, next);
  }

  /// Scrolls the page while a dragged card is held near its top / bottom edge.
  void _autoScrollTick() {
    final pos = _dragPos;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (pos == null || box == null || !box.hasSize || !_scroll.hasClients) return;
    final local = box.globalToLocal(pos);
    const edge = 72.0;
    final h = box.size.height;
    double delta = 0;
    if (local.dy < edge) {
      delta = -(edge - local.dy.clamp(0, edge)) / edge * 14 - 2;
    } else if (local.dy > h - edge) {
      delta = (local.dy.clamp(h - edge, h) - (h - edge)) / edge * 14 + 2;
    }
    if (delta == 0) return;
    final p = _scroll.position;
    final next = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (next != p.pixels) _scroll.jumpTo(next);
  }

  static const _general = <MenuItemDef>[
    MenuItemDef(id: 'search', title: 'ค้นหา', subtitle: 'ค้นหาทุกโมดูล', icon: NxI.magnifyingGlass, route: AppRoutes.globalSearch, menuKeys: []),
    MenuItemDef(id: 'notifications', title: 'แจ้งเตือน', subtitle: 'การแจ้งเตือนทั้งหมด', icon: NxI.bell, route: AppRoutes.notifications, menuKeys: []),
    MenuItemDef(id: 'whats-new', title: 'มีอะไรใหม่', subtitle: 'ประกาศเวอร์ชันและฟีเจอร์ใหม่', icon: NxI.sparkle, route: AppRoutes.whatsNew, menuKeys: []),
    MenuItemDef(id: 'settings', title: 'ตั้งค่า', subtitle: 'ข้อมูลในเครื่อง เกี่ยวกับแอป ช่วยเหลือ', icon: NxI.gear, route: AppRoutes.settings, menuKeys: []),
  ];

  Future<void> _openMore() async {
    await showNxBlurPanel<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final custom = !isDefaultMenuOrder(_order);
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final v in MenuHubView.values)
              ListTile(
                key: ValueKey('menu-view-${v.name}'),
                leading: Icon(v == MenuHubView.groups ? NxI.squaresFour : NxI.listBullets),
                title: Text(tr(v == MenuHubView.groups ? 'มุมมองกลุ่ม' : 'มุมมองรายการ')),
                trailing: _view == v ? Icon(NxI.check, color: cs.primary) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _setView(v);
                },
              ),
            const Divider(height: 8),
            ListTile(
              key: const ValueKey('menu-reset-order'),
              enabled: custom,
              leading: const Icon(NxI.arrowCounterClockwise),
              title: Text(tr('รีเซ็ตลำดับ')),
              subtitle: Text(tr(custom ? 'กลับไปใช้ลำดับกลุ่มเริ่มต้น' : 'กดค้างที่การ์ดกลุ่มแล้วลากเพื่อจัดเรียง')),
              onTap: () {
                Navigator.pop(ctx);
                _resetOrder();
              },
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final session = context.select((AppConfig c) => c.session);
    _syncPrefs(context.read<AppConfig>());
    final bp = NxBreakpoint.of(context);
    final allowed = orderMenuGroups(visibleMenuGroups(session, isaac: _isaac), _order);
    final drag = _dragVisible;
    final groups = drag == null
        ? allowed
        : [
            for (final id in drag)
              ...allowed.where((g) => g.def.id == id),
            ...allowed.where((g) => !drag.contains(g.def.id)),
          ];
    final q = _q.trim().toLowerCase();
    final listMode = _view == MenuHubView.list;

    final header = NxAppHeader.hub(
      actions: [
        IconButton(
          tooltip: tr('ค้นหาเมนู'),
          icon: const Icon(NxI.magnifyingGlass),
          onPressed: _toggleSearch,
        ),
        IconButton(
          tooltip: tr(listMode ? 'มุมมองกลุ่ม' : 'มุมมองรายการ'),
          icon: Icon(listMode ? NxI.squaresFour : NxI.listBullets),
          onPressed: () => _setView(listMode ? MenuHubView.groups : MenuHubView.list),
        ),
        IconButton(
          tooltip: tr('เพิ่มเติม'),
          icon: const Icon(NxI.dotsThreeCircle),
          onPressed: _openMore,
        ),
      ],
    );

    Widget searchBox() => Padding(
          padding: EdgeInsets.fromLTRB(bp.twoPane ? 24 : 16, 4, bp.twoPane ? 24 : 16, 8),
          child: TextField(
            key: const ValueKey('menu-search'),
            controller: _search,
            focusNode: _searchFocus,
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('ค้นหาเมนู'),
              prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
              suffixIcon: _q.isEmpty
                  ? IconButton(
                      key: const ValueKey('menu-search-close'),
                      tooltip: tr('ปิดค้นหา'),
                      icon: const Icon(NxI.x, size: 18),
                      onPressed: _closeSearch,
                    )
                  : IconButton(
                      key: const ValueKey('menu-search-clear'),
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
          ),
        );

    Widget searchResults() {
      final hits = <(MenuItemDef, VisibleMenuGroup?)>[
        for (final g in groups)
          for (final it in g.items)
            if ('${it.title} ${it.subtitle} ${g.def.title}'.toLowerCase().contains(q) ||
                tr(it.title).toLowerCase().contains(q) ||
                tr(g.def.title).toLowerCase().contains(q))
              (it, g),
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

    Widget groupCard(VisibleMenuGroup g, {bool selected = false, VoidCallback? onTap, bool interactive = true}) {
      final items = g.items;
      final color = g.def.color;
      return NxSurfaceCard(
        key: interactive ? ValueKey('menu-group-${g.def.id}') : null,
        onTap: interactive ? (onTap ?? () => context.push(AppRoutes.menuGroup(g.def.id))) : null,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        // Two-pane: the open group is tinted in its colour (a side line used to run over the text).
        color: selected ? Color.alphaBlend(color.withValues(alpha: 0.16), NxAtmosphereTokens.of(context).cardElevated) : null,
        child: KeyedSubtree(
          key: selected && interactive ? ValueKey('menu-group-selected-${g.def.id}') : null,
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
                if (items.any((i) => i.id == 'approvals'))
                  ListenableBuilder(
                    listenable: PendingApprovals.instance,
                    builder: (context, _) {
                      final n = PendingApprovals.instance.count;
                      if (n <= 0) return const SizedBox.shrink();
                      return Container(
                        key: interactive ? const ValueKey('group-approvals-badge') : null,
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(999)),
                        child: Text(tr('รออนุมัติ $n'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onError, fontWeight: FontWeight.w800)),
                      );
                    },
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                  child: Text('${items.length}', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Text(tr(g.def.title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              // Always 2 lines tall, so every card in the grid has the same height.
              Builder(builder: (context) {
                final st = theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4);
                final line = MediaQuery.textScalerOf(context).scale(st?.fontSize ?? 12) * 1.4;
                return SizedBox(
                  height: line * 2 + 1,
                  child: Text(
                    items.take(3).map((i) => tr(i.title)).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: st,
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }

    /// Long-press a card, then drag it over another card to move it there.
    Widget reorderable(VisibleMenuGroup g, double width, Widget card) {
      final id = g.def.id;
      return DragTarget<String>(
        key: ValueKey('menu-drop-$id'),
        onWillAcceptWithDetails: (d) {
          _dragOver(d.data, id);
          return true;
        },
        onAcceptWithDetails: (_) => _endDrag(),
        builder: (context, _, _) => LongPressDraggable<String>(
          data: id,
          hapticFeedbackOnStart: false,
          onDragStarted: () => _startDrag(id, groups),
          onDragUpdate: (d) => _dragPos = d.globalPosition,
          onDragEnd: (_) => _endDrag(),
          feedback: SizedBox(
            key: ValueKey('menu-drag-feedback-$id'),
            width: width,
            child: Transform.scale(
              scale: 1.04,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.55 : 0.22), blurRadius: 28, offset: const Offset(0, 14)),
                  ],
                ),
                child: Material(type: MaterialType.transparency, child: groupCard(g, interactive: false)),
              ),
            ),
          ),
          // Same tree while dragging (only faded): the card's press listener
          // must stay mounted until the finger lifts.
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _dragId == id ? 0.28 : 1,
            child: card,
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

    Widget page(Widget body) => NxBackHandler(
          active: _searchOpen,
          onBack: _closeSearch,
          child: Column(children: [
            header,
            if (_searchOpen) searchBox(),
            Expanded(child: body),
          ]),
        );

    Widget scrollList(List<Widget> children, {EdgeInsets? padding}) => NxRefresh(
          color: cs.primary,
          onRefresh: () => _loadIsaac(fresh: true),
          child: ListView(
            key: _viewportKey,
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding ?? bp.scrollPadding(context, inShell: true),
            children: children,
          ),
        );

    // Search results (any view).
    if (q.isNotEmpty) {
      return page(scrollList([searchResults()]));
    }

    // List view: every menu as rows, grouped like Android Settings.
    if (listMode) {
      return page(scrollList([
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: MenuHubListView(groups: groups, general: _general),
          ),
        ),
      ]));
    }

    // Tablet / unfolded phone: groups on the left, the chosen group's menus on the right.
    if (bp.twoPane && groups.isNotEmpty) {
      final sel = groups.firstWhere((g) => g.def.id == _selected, orElse: () => groups.first);
      final pad = bp.scrollPadding(context, inShell: true);
      return page(NxSplitView(
        list: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth - pad.horizontal;
            return ListView(
              key: _viewportKey,
              controller: _scroll,
              padding: pad,
              children: [
                for (final g in groups)
                  Padding(
                    key: ValueKey('menu-slot-${g.def.id}'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: reorderable(
                      g,
                      w,
                      groupCard(g, selected: g.def.id == sel.def.id, onTap: () => setState(() => _selected = g.def.id)),
                    ),
                  ),
                generalList(),
              ],
            );
          },
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
      ));
    }

    return page(scrollList([
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final cols = bp.gridColumns.clamp(2, 4);
          final w = (constraints.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final g in groups)
                SizedBox(
                  key: ValueKey('menu-slot-${g.def.id}'),
                  width: w,
                  child: reorderable(g, w, groupCard(g)),
                ),
            ],
          );
        },
      ),
      generalList(),
    ]));
  }
}

/// Every menu the user can open, as rows in rounded sections (one per group,
/// in the user's group order) — like Android Settings.
class MenuHubListView extends StatelessWidget {
  const MenuHubListView({super.key, required this.groups, this.general = const []});

  final List<VisibleMenuGroup> groups;

  /// "ทั่วไป" menus shown last (search, notifications, settings…).
  final List<MenuItemDef> general;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, g) in groups.indexed)
          _Section(
            key: ValueKey('menu-list-group-${g.def.id}'),
            title: g.def.title,
            first: i == 0,
            rows: [for (final it in g.items) (it, g.def.color)],
          ),
        if (general.isNotEmpty)
          _Section(
            key: const ValueKey('menu-list-group-general'),
            title: 'ทั่วไป',
            first: groups.isEmpty,
            rows: [for (final it in general) (it, cs.primary)],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.rows, this.first = false});
  final String title;
  final List<(MenuItemDef, Color)> rows;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, first ? 4 : 22, 16, 8),
          child: Text(
            tr(title),
            style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ),
        NxSurfaceCard(
          radius: 22,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final (j, (it, color)) in rows.indexed) ...[
              if (j > 0) Divider(height: 1, thickness: 1, indent: 68, color: cs.outlineVariant.withValues(alpha: 0.45)),
              _Row(item: it, color: color),
            ],
          ]),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.color});
  final MenuItemDef item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      key: ValueKey('menu-row-${item.id}'),
      onTap: () => context.push(item.route),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: dark ? Color.lerp(color, Colors.black, 0.15) : color, shape: BoxShape.circle),
              child: Icon(item.icon, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                tr(item.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (item.id == 'approvals')
              ListenableBuilder(
                listenable: PendingApprovals.instance,
                builder: (context, _) {
                  final n = PendingApprovals.instance.count;
                  if (n <= 0) return const SizedBox.shrink();
                  return Container(
                    key: const ValueKey('menu-row-badge-approvals'),
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(99)),
                    child: Text(n > 99 ? '99+' : '$n', style: theme.textTheme.labelMedium?.copyWith(color: cs.onError, fontWeight: FontWeight.w800)),
                  );
                },
              ),
            const SizedBox(width: 6),
            Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
