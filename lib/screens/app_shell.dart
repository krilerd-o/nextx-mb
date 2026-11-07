import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/nx_breakpoint.dart';
import '../services/offline_queue.dart';
import '../services/unread_service.dart';
import '../widgets/nx_glass.dart';
import '../widgets/nx_icons.dart';
import '../widgets/nx_invite_prompt.dart';
import '../widgets/nx_tab_nav.dart';
import '../core/shell_tabs.dart';
import 'ai/ai_chat_screen.dart';
import 'approvals/approvals_screen.dart';
import 'calendar/calendar_home_screen.dart';
import 'chat/chat_home_screen.dart';
import 'commerce/commerce_home_screen.dart';
import 'crm/crm_home_screen.dart';
import 'crm/entity_list_screen.dart';
import 'dashboard/mobile_dashboard_screen.dart';
import 'files/files_home_screen.dart';
import 'hr/hr_home_screen.dart';
import 'jobs/my_jobs_screen.dart';
import 'mail/mail_home_screen.dart';
import 'module/module_hub_screen.dart';
import 'notifications/notification_center_screen.dart';
import 'search/global_search_screen.dart';
import 'workspace/workspace_home_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

/// Screen for a bottom-bar tab id (see `shellTabCatalog`).
Widget shellTabScreen(String id) {
  switch (id) {
    case 'dashboard':
      return const MobileDashboardScreen();
    case 'leads':
      return const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง');
    case 'quotation':
      return const EntityListScreen(module: 'quotation', title: 'ใบเสนอราคา');
    case 'crm':
      return const CrmHomeScreen();
    case 'cases':
      return const EntityListScreen(module: 'case', title: 'เคส');
    case 'calendar':
      return const CalendarHomeScreen();
    case 'chat':
      return const ChatHomeScreen();
    case 'mail':
      return const MailHomeScreen();
    case 'workspace':
      return const WorkspaceHomeScreen();
    case 'approvals':
      return const ApprovalsScreen();
    case 'hr':
      return const HrHomeScreen();
    case 'jobs':
      return const MyJobsScreen();
    case 'commerce':
      return const CommerceHomeScreen();
    case 'files':
      return const FilesHomeScreen();
    case 'ai':
      return const AiChatScreen();
    case 'search':
      return const GlobalSearchScreen();
    case 'notifications':
      return const NotificationCenterScreen();
    default:
      return const ModuleHubScreen();
  }
}

/// Tabs drawn for the floating bar (content scrolls under it).
const _shellNativeTabs = {'dashboard', 'search', 'hr', kMenuTabId};

class _AppShellState extends State<AppShell> {
  String _current = '';

  /// Tabs opened at least once — others stay unbuilt so launch only loads
  /// the visible tab instead of every tab's API at once.
  final Set<String> _built = {};

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    final config = context.watch<AppConfig>();
    if (config.pendingInvite != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Joined → go pick the new business.
        if (await maybePromptInviteJoin(context)) await config.clearBusiness();
      });
    }
    final ids = [...config.shellTabs, kMenuTabId];
    if (!ids.contains(_current)) {
      // Reopen the tab used last time if it's still allowed.
      final last = config.lastTab;
      _current = last != null && ids.contains(last) ? last : ids.first;
    }
    final selected = ids.indexOf(_current);
    _built
      ..removeWhere((id) => !ids.contains(id))
      ..add(_current);
    final notifIndex = ids.indexOf('notifications');
    final destinations = [
      for (final id in ids)
        if (id == kMenuTabId)
          const NxTabDestination(icon: NxI.dotsThreeCircle, selectedIcon: NxI.dotsThreeCircleFill, label: 'เมนู')
        else
          NxTabDestination(
            icon: shellTabById(id)!.icon,
            selectedIcon: shellTabById(id)!.selectedIcon,
            label: shellTabById(id)!.label,
          ),
    ];
    final nav = ListenableBuilder(
      listenable: UnreadNotifications.instance,
      builder: (context, _) {
        final unread = UnreadNotifications.instance.count;
        return NxTabNav(
      destinations: destinations,
      selectedIndex: selected,
      onSelect: (i) {
        setState(() => _current = ids[i]);
        config.setLastTab(ids[i]);
      },
      rail: bp.useRail,
      badges: {if (notifIndex >= 0 && unread > 0) notifIndex: unread},
        );
      },
    );

    final stack = Column(
      children: [
        const _PendingSyncBanner(),
        Expanded(
          child: IndexedStack(
            index: selected,
            children: [
              for (final id in ids)
                KeyedSubtree(
                  key: ValueKey('tab-$id'),
                  child: _built.contains(id) ? shellTabScreen(id) : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ],
    );

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

    final floating = _shellNativeTabs.contains(_current);
    return Scaffold(
      // Shell-native tabs pad for the floating bar; other pages need it outside.
      extendBody: floating,
      body: floating
          ? Stack(
              children: [
                stack,
                // Content fades into a soft blur behind the floating bar.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 120 + MediaQuery.paddingOf(context).bottom,
                  child: const NxProgressiveBlur(height: double.infinity),
                ),
              ],
            )
          : stack,
      bottomNavigationBar: nav,
    );
  }
}

/// Shown while offline check-ins are waiting to be sent.
class _PendingSyncBanner extends StatelessWidget {
  const _PendingSyncBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: OfflineQueue.pending,
      builder: (context, n, _) {
        if (n <= 0) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: cs.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.cloud_upload_outlined, color: cs.onTertiaryContainer),
              title: Text('มี $n รายการรอส่ง (บันทึกตอนออฟไลน์)', style: TextStyle(color: cs.onTertiaryContainer)),
              trailing: TextButton(
                onPressed: () => context.read<AppConfig>().flushOfflineQueue(),
                child: const Text('ส่งตอนนี้'),
              ),
            ),
          ),
        );
      },
    );
  }
}
