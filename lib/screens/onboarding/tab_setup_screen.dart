import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/shell_tabs.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_tab_nav.dart';
import '../../widgets/nx_step_header.dart';
import '../../core/i18n.dart';

/// "เมนูของคุณ" — preview and arrange the bottom bar (max [kMaxCustomTabs]
/// + the fixed "เมนู" tab). Used at the end of onboarding and from Settings.
class TabSetupScreen extends StatefulWidget {
  const TabSetupScreen({super.key, this.initial, this.fromSettings = false});

  /// Roles chosen on the previous step (onboarding).
  final ShellTabsConfig? initial;
  final bool fromSettings;

  @override
  State<TabSetupScreen> createState() => _TabSetupScreenState();
}

class _TabSetupScreenState extends State<TabSetupScreen> {
  late ShellTabsConfig _base;
  late List<String> _tabs;
  /// The user changed the list here: later permission updates must not reset it.
  bool _edited = false;
  /// Permissions [_tabs] was worked out with (menus may still be loading when the page opens).
  (bool, Object?)? _resolvedFor;

  bool _allowed(ShellTabDef d) => d.anyMenu.isEmpty || MenuAccess.any(context.read<AppConfig>().session, d.anyMenu);

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    _base = widget.initial ?? config.shellConfig ?? const ShellTabsConfig(roles: ['general']);
    _tabs = _resolve(config);
  }

  List<String> _resolve(AppConfig config) {
    _resolvedFor = (config.session.menusLoaded, config.session.menuKeys);
    return resolveShellTabs(
      roles: _base.roles,
      custom: _base.tabs,
      allowed: (keys) => MenuAccess.any(config.session, keys),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Opened before the menus arrived (cold start straight into this page): work the
    // list out again once they do, unless the user has already changed it.
    final config = context.watch<AppConfig>();
    final now = (config.session.menusLoaded, config.session.menuKeys);
    if (!_edited && _resolvedFor != null && _resolvedFor != now) {
      _tabs = _resolve(config);
    }
  }

  bool get _full => _tabs.length >= kMaxCustomTabs;

  /// Adds or removes [id]. At least one tab stays; when the bar is full the
  /// add controls are disabled and an inline note explains why.
  void _toggle(String id) {
    _edited = true;
    setState(() {
      if (_tabs.contains(id)) {
        if (_tabs.length > 1) _tabs.remove(id);
      } else if (!_full) {
        _tabs.add(id);
      }
    });
  }

  Future<void> _save() async {
    await context.read<AppConfig>().saveShellConfig(_base.copyWith(tabs: List.of(_tabs)));
    if (!mounted) return;
    if (widget.fromSettings) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกเมนูล่างแล้ว'))));
      Navigator.of(context).maybePop();
    }
    // Onboarding: router moves on to the app once roleSetupDone is true.
  }

  void _resetToSuggested() {
    _edited = true;
    setState(() {
      _tabs = resolveShellTabs(
        roles: _base.roles,
        allowed: (keys) => MenuAccess.any(context.read<AppConfig>().session, keys),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final catalog = shellTabCatalog.where(_allowed).toList();
    final shown = catalog;
    return Scaffold(
      appBar: widget.fromSettings
          ? AppBar(
              title: Text(tr('ปรับแต่งเมนูล่าง')),
              actions: [TextButton(key: const ValueKey('tab-setup-reset'), onPressed: _resetToSuggested, child: Text(tr('ค่าแนะนำ')))],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.fromSettings) NxStepHeader(step: 4, total: 4, onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                key: const ValueKey('tab-setup-list'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (!widget.fromSettings) ...[
                    Text(tr('เมนูที่จัดไว้ให้คุณ'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      tr('จากบทบาทที่เลือก ปรับเพิ่ม ลด หรือลากเรียงลำดับได้\nเปลี่ยนได้ตลอดในหน้าตั้งค่า'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TabBarPreview(tabs: _tabs),
                  const SizedBox(height: 20),
                  _SectionTitle(
                    title: 'แท็บที่แสดง',
                    trailing: Container(
                      key: const ValueKey('tab-count'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (_full ? cs.primary : cs.surfaceContainerHighest).withValues(alpha: _full ? 0.14 : 1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${_tabs.length}/$kMaxCustomTabs',
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: _full ? cs.primary : cs.onSurfaceVariant),
                      ),
                    ),
                    hint: 'ลากเพื่อเรียง',
                  ),
                  const SizedBox(height: 8),
                  ReorderableListView(
                    key: const ValueKey('tab-setup-chosen'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, _, anim) => AnimatedBuilder(
                      animation: anim,
                      builder: (_, c) => Transform.scale(
                        scale: 1 + 0.02 * anim.value,
                        child: Material(color: Colors.transparent, elevation: 6 * anim.value, borderRadius: BorderRadius.circular(18), child: c),
                      ),
                      child: child,
                    ),
                    onReorderItem: (from, to) {
                      _edited = true;
                      HapticFeedback.selectionClick();
                      setState(() {
                        final id = _tabs.removeAt(from);
                        _tabs.insert(to, id);
                      });
                    },
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        _ChosenTabRow(
                          key: ValueKey('tab-chosen-${_tabs[i]}'),
                          index: i,
                          def: shellTabById(_tabs[i])!,
                          onRemove: _tabs.length > 1 ? () => _toggle(_tabs[i]) : null,
                        ),
                    ],
                  ),
                  // The fixed "เมนู" tab: always last, can't be moved or removed.
                  Container(
                    key: const ValueKey('tab-menu-row'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Row(children: [
                      Icon(NxI.dotsThreeCircle, size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Text(tr('เมนู'), style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('· ${tr('อยู่ขวาสุดเสมอ')}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      Icon(NxI.lock, size: 16, color: cs.onSurfaceVariant),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'เพิ่มแท็บ'),
                  const SizedBox(height: 10),
                  if (_full) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('tab-full-note'),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(NxI.info, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tr('ครบ $kMaxCustomTabs แท็บแล้ว — เอาออก 1 แท็บก่อนเพิ่มใหม่'),
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(tr('ไม่มีรายการ'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: [
                        for (final d in shown)
                          _TabCapsule(
                            key: ValueKey('tab-option-${d.id}'),
                            def: d,
                            added: _tabs.contains(d.id),
                            // Added: tap removes (unless it's the last one). Not added: tap adds while there's room.
                            onToggle: _tabs.contains(d.id) ? (_tabs.length > 1 ? () => _toggle(d.id) : null) : (_full ? null : () => _toggle(d.id)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: NxHeroCta(label: widget.fromSettings ? 'บันทึก' : 'เริ่มใช้งาน', onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}


class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing, this.hint});
  final String title;
  final Widget? trailing;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      const Spacer(),
      if (hint != null)
        Text(tr(hint!), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

/// The tab's icon in a tinted rounded square, with an optional order badge.
class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.icon, this.order});
  final IconData icon;
  final int? order;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = cs.primary;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: tint),
        ),
        if (order != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 2)),
              child: Text('$order', style: TextStyle(fontSize: 9.5, height: 1, fontWeight: FontWeight.w800, color: cs.onPrimary)),
            ),
          ),
      ]),
    );
  }
}

/// Label + one-line description.
class _TabText extends StatelessWidget {
  const _TabText({required this.def});
  final ShellTabDef def;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(tr(def.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(tr(def.description), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _ChosenTabRow extends StatelessWidget {
  const _ChosenTabRow({super.key, required this.index, required this.def, required this.onRemove});
  final int index;
  final ShellTabDef def;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NxSurfaceCard(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(2, 8, 4, 8),
        child: Row(children: [
          ReorderableDragStartListener(
            key: ValueKey('tab-grip-${def.id}'),
            index: index,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(NxI.grip, size: 20, color: cs.onSurfaceVariant)),
          ),
          _TabIcon(icon: def.icon, order: index + 1),
          const SizedBox(width: 12),
          Expanded(child: _TabText(def: def)),
          IconButton(
            key: ValueKey('tab-remove-${def.id}'),
            tooltip: tr('เอาออก'),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(NxI.circleMinus, size: 20, color: onRemove == null ? cs.outlineVariant : cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

/// "เพิ่มแท็บ" capsule: icon + label. Added = filled with ✓ (tap removes);
/// not added = outlined with + (tap adds); no room = dimmed.
class _TabCapsule extends StatelessWidget {
  const _TabCapsule({super.key, required this.def, required this.added, required this.onToggle});
  final ShellTabDef def;
  final bool added;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final disabled = onToggle == null && !added;
    final fg = added ? cs.primary : (disabled ? cs.onSurfaceVariant : cs.onSurface);
    return Tooltip(
      message: tr(def.description),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: disabled ? 0.45 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('tab-toggle-${def.id}'),
            onTap: onToggle == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onToggle!();
                  },
            customBorder: const StadiumBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
              decoration: ShapeDecoration(
                shape: StadiumBorder(side: BorderSide(color: added ? cs.primary : cs.outlineVariant, width: added ? 1.6 : 1)),
                color: added ? cs.primary.withValues(alpha: 0.10) : cs.surface,
                shadows: added ? null : [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(def.icon, size: 18, color: added ? cs.primary : cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(tr(def.label), style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: added ? FontWeight.w700 : FontWeight.w600)),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Container(
                    key: ValueKey(added),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: added ? cs.primary : cs.primary.withValues(alpha: disabled ? 0.08 : 0.12)),
                    child: Icon(added ? NxI.check : NxI.plus, size: 12, color: added ? cs.onPrimary : (disabled ? cs.onSurfaceVariant : cs.primary)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small mock of the bottom bar.
class TabBarPreview extends StatelessWidget {
  const TabBarPreview({super.key, required this.tabs});
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final id in tabs) shellTabById(id)!,
      const ShellTabDef(id: kMenuTabId, label: 'เมนู', icon: NxI.dotsThreeCircle, selectedIcon: NxI.dotsThreeCircleFill),
    ];
    // Same widget as the live bottom bar, so the preview never drifts.
    return NxTabBarCard(
      selectedIndex: 0,
      destinations: [
        for (final d in items) NxTabDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: d.label),
      ],
    );
  }
}
