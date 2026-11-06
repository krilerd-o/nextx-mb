import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/menu_access.dart';
import '../core/nx_breakpoint.dart';
import '../widgets/nx_icons.dart';
import '../widgets/nx_tab_nav.dart';
import 'dashboard/mobile_dashboard_screen.dart';
import 'hr/hr_home_screen.dart';
import 'module/module_hub_screen.dart';
import 'search/global_search_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    final session = context.watch<AppConfig>().session;
    final showHr = MenuAccess.anyHr(session);
    final screens = <Widget>[
      const MobileDashboardScreen(),
      const GlobalSearchScreen(),
      const ModuleHubScreen(),
      if (showHr) const HrHomeScreen(),
      const SettingsScreen(),
    ];
    final destinations = <NxTabDestination>[
      const NxTabDestination(
        icon: NxI.squaresFour,
        selectedIcon: NxI.squaresFourFill,
        label: 'แดชบอร์ด',
      ),
      const NxTabDestination(
        icon: NxI.magnifyingGlass,
        selectedIcon: NxI.magnifyingGlassFill,
        label: 'ค้นหา',
      ),
      const NxTabDestination(
        icon: NxI.buildings,
        selectedIcon: NxI.buildingsFill,
        label: 'ธุรกิจ',
      ),
      if (showHr)
        const NxTabDestination(
          icon: NxI.briefcase,
          selectedIcon: NxI.briefcaseFill,
          label: 'HR',
        ),
      const NxTabDestination(
        icon: NxI.gear,
        selectedIcon: NxI.gearFill,
        label: 'ตั้งค่า',
      ),
    ];
    final selected = _index.clamp(0, screens.length - 1).toInt();
    final nav = NxTabNav(
      destinations: destinations,
      selectedIndex: selected,
      onSelect: _select,
      rail: bp.useRail,
    );

    final stack = IndexedStack(index: selected, children: screens);

    if (bp.useRail) {
      return Scaffold(
        body: Row(
          children: [
            nav,
            Expanded(child: stack),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: stack,
      bottomNavigationBar: nav,
    );
  }
}
