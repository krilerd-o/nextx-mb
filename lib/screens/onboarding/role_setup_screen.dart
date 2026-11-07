import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/shell_tabs.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_step_header.dart';

/// "คุณทำงานด้านไหน" — pick one or more roles; the bottom bar is suggested
/// from them (and can be changed on the next step or later in Settings).
class RoleSetupScreen extends StatefulWidget {
  const RoleSetupScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  State<RoleSetupScreen> createState() => _RoleSetupScreenState();
}

class _RoleSetupScreenState extends State<RoleSetupScreen> {
  late final Set<String> _roles = () {
    final config = context.read<AppConfig>();
    final saved = config.shellConfig?.roles;
    if (saved != null && saved.isNotEmpty) return {...saved};
    // First time: pre-tick roles that fit the package (NEXT S → ทีมขาย …).
    return {...suggestedRolesForPackage(config.session.packageCode)};
  }();

  Future<void> _next() async {
    final config = context.read<AppConfig>();
    final prev = config.shellConfig;
    // New roles → new suggestion (drop the old custom arrangement).
    final sameRoles = prev != null && prev.roles.toSet().length == _roles.length && _roles.containsAll(prev.roles);
    final next = ShellTabsConfig(roles: _roles.toList(), tabs: sameRoles ? prev.tabs : null);
    if (widget.fromSettings) {
      await config.saveShellConfig(next);
      if (mounted) context.pushReplacement(AppRoutes.tabEditor);
      return;
    }
    if (mounted) context.push(AppRoutes.tabSetup, extra: next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            NxStepHeader(
              step: 3,
              total: 4,
              onBack: widget.fromSettings ? () => Navigator.of(context).maybePop() : () => context.read<AppConfig>().clearPackage(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                children: [
                  Text('คุณทำงานด้านไหน?', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'เลือกได้มากกว่า 1 ข้อ เราจะจัดเมนูด้านล่างให้เหมาะกับงานของคุณ',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  for (final r in workRoles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NxChoiceCard(
                        icon: r.icon,
                        title: r.label,
                        subtitle: r.description,
                        dense: true,
                        selected: _roles.contains(r.id),
                        onTap: () => setState(() => _roles.contains(r.id) ? _roles.remove(r.id) : _roles.add(r.id)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: NxHeroCta(label: _roles.isEmpty ? 'เลือกอย่างน้อย 1 ข้อ' : 'ถัดไป', onPressed: _roles.isEmpty ? null : _next),
            ),
          ],
        ),
      ),
    );
  }
}
