import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/menu_access.dart';
import '../../core/shell_tabs.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
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

  void _toggle(String id) {
    setState(() {
      if (_tabs.contains(id)) {
        if (_tabs.length > 1) _tabs.remove(id);
      } else if (_tabs.length < kMaxCustomTabs) {
        _tabs.add(id);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('ใส่ได้สูงสุด $kMaxCustomTabs แท็บ (บวกแท็บ "เมนู") — เอาออกก่อน 1 แท็บ'))),
        );
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
    final available = shellTabCatalog.where((d) => _allowed(d) && !_tabs.contains(d.id)).toList();
    return Scaffold(
      appBar: widget.fromSettings
          ? AppBar(
              title: Text(tr('ปรับแต่งเมนูล่าง')),
              actions: [TextButton(onPressed: _resetToSuggested, child: Text(tr('ค่าแนะนำ')))],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.fromSettings) NxStepHeader(step: 4, total: 4, onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  if (!widget.fromSettings) ...[
                    Text(tr('เมนูที่จัดไว้ให้คุณ'), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      tr('จากบทบาทที่เลือก ปรับเพิ่ม ลด หรือลากเรียงลำดับได้\nเปลี่ยนได้ตลอดในหน้าตั้งค่า'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                  ],
                  _BarPreview(tabs: _tabs),
                  const SizedBox(height: 20),
                  Text(tr('แท็บที่แสดง (ลากเพื่อเรียงลำดับ)'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                    ),
                    child: ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (from, to) => setState(() {
                        if (to > from) to -= 1;
                        final id = _tabs.removeAt(from);
                        _tabs.insert(to, id);
                      }),
                      children: [
                        for (var i = 0; i < _tabs.length; i++)
                          Builder(
                            key: ValueKey(_tabs[i]),
                            builder: (context) {
                              final d = shellTabById(_tabs[i])!;
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: cs.primary,
                                  child: Text(tr('${i + 1}'), style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700)),
                                ),
                                title: Text(tr(d.label)),
                                subtitle: Text(tr(d.description)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: tr('เอาออก'),
                                      icon: const Icon(NxI.circleMinus),
                                      onPressed: _tabs.length > 1 ? () => _toggle(d.id) : null,
                                    ),
                                    ReorderableDragStartListener(index: i, child: const Icon(NxI.grip)),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(NxI.dotsThreeCircle),
                    title: Text(tr('เมนู (ทุกโมดูล + ตั้งค่า)')),
                    subtitle: Text(tr('อยู่ขวาสุดเสมอ')),
                    trailing: const Icon(NxI.lock, size: 18),
                    textColor: cs.onSurfaceVariant,
                    iconColor: cs.onSurfaceVariant,
                  ),
                  if (available.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(tr('เพิ่มแท็บ'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in available)
                          ActionChip(
                            avatar: Icon(d.icon, size: 18),
                            label: Text(tr(d.label)),
                            onPressed: () => _toggle(d.id),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: NxHeroCta(label: widget.fromSettings ? 'บันทึก' : 'เริ่มใช้งาน', onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small mock of the bottom bar.
class _BarPreview extends StatelessWidget {
  const _BarPreview({required this.tabs});
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
