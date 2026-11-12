import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/shell_tabs.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
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
  _TabFilter _filter = _TabFilter.all;

  bool _allowed(ShellTabDef d) => d.anyMenu.isEmpty || MenuAccess.any(context.read<AppConfig>().session, d.anyMenu);

  @override
  void initState() {
    super.initState();
    final config = context.read<AppConfig>();
    _base = widget.initial ?? config.shellConfig ?? const ShellTabsConfig(roles: ['general']);
    _tabs = resolveShellTabs(
      roles: _base.roles,
      custom: _base.tabs,
      allowed: (keys) => MenuAccess.any(config.session, keys),
    );
  }

  bool get _full => _tabs.length >= kMaxCustomTabs;

  /// Adds or removes [id]. At least one tab stays; when the bar is full the
  /// add controls are disabled and an inline note explains why.
  void _toggle(String id) {
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
    final shown = [
      for (final d in catalog)
        if (switch (_filter) {
          _TabFilter.all => true,
          _TabFilter.notAdded => !_tabs.contains(d.id),
          _TabFilter.added => _tabs.contains(d.id),
        })
          d,
    ];
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
                  KeyedSubtree(
                    key: const ValueKey('tab-filter'),
                    child: NxSlidingSegmented<_TabFilter>(
                      value: _filter,
                      options: const [
                        (_TabFilter.all, 'ทั้งหมด', null),
                        (_TabFilter.notAdded, 'ยังไม่เพิ่ม', null),
                        (_TabFilter.added, 'เพิ่มแล้ว', null),
                      ],
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ),
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
                    for (final d in shown)
                      _CatalogTabRow(
                        key: ValueKey('tab-option-${d.id}'),
                        def: d,
                        added: _tabs.contains(d.id),
                        // Added: tap removes (unless it's the last one). Not added: tap adds while there's room.
                        onToggle: _tabs.contains(d.id) ? (_tabs.length > 1 ? () => _toggle(d.id) : null) : (_full ? null : () => _toggle(d.id)),
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

enum _TabFilter { all, notAdded, added }

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
  const _TabIcon({required this.icon, this.order, this.muted = false});
  final IconData icon;
  final int? order;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = muted ? cs.onSurfaceVariant : cs.primary;
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

class _CatalogTabRow extends StatelessWidget {
  const _CatalogTabRow({super.key, required this.def, required this.added, required this.onToggle});
  final ShellTabDef def;
  final bool added;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onToggle == null && !added;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: disabled ? 0.5 : 1,
        child: NxSurfaceCard(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          onTap: onToggle,
          child: Row(children: [
            _TabIcon(icon: def.icon, muted: !added),
            const SizedBox(width: 12),
            Expanded(child: _TabText(def: def)),
            const SizedBox(width: 8),
            Tooltip(
              message: tr(added ? 'เอาออก' : 'เพิ่ม'),
              child: InkResponse(
                key: ValueKey('tab-toggle-${def.id}'),
                onTap: onToggle,
                radius: 22,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: added ? cs.primary : Colors.transparent,
                    border: added ? null : Border.all(color: disabled ? cs.outlineVariant : cs.primary, width: 1.5),
                  ),
                  child: Icon(added ? NxI.check : NxI.plus, size: 16, color: added ? cs.onPrimary : (disabled ? cs.outlineVariant : cs.primary)),
                ),
              ),
            ),
          ]),
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
