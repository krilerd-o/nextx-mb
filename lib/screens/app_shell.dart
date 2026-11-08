import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/nx_breakpoint.dart';
import '../services/offline_queue.dart';
import '../services/unread_service.dart';
import '../widgets/nx_scroll_scaffold.dart';
import '../widgets/nx_back_handler.dart';
import '../widgets/nx_icons.dart';
import '../widgets/nx_invite_prompt.dart';
import '../widgets/nx_tab_nav.dart';
import '../core/shell_tabs.dart';
import '../core/nx_page_route.dart';
import 'ai/assistant/ai_assistant_screen.dart';
import 'auth/qr_login_scan_screen.dart';
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
import '../core/i18n.dart';

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
      return const AiAssistantScreen();
    case 'search':
      return const GlobalSearchScreen();
    case 'notifications':
      return const NotificationCenterScreen();
    default:
      return const ModuleHubScreen();
  }
}

/// Tabs that draw their own header (no NxScrollScaffold).
const _hubTabs = {kMenuTabId};

class _AppShellState extends State<AppShell> {
  String _current = '';

  /// Tabs opened at least once — others stay unbuilt so launch only loads
  /// the visible tab instead of every tab's API at once.
  final Set<String> _built = {};
  bool _prewarmStarted = false;

  /// After the first tab is on screen and idle, build the other tabs one at a
  /// time so the first tap on them doesn't build + fetch in the same frame.
  void _prewarm(List<String> ids) {
    if (_prewarmStarted) return;
    _prewarmStarted = true;
    Future<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      for (final id in ids) {
        if (!mounted) return;
        if (_built.contains(id)) continue;
        setState(() => _built.add(id));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bp = NxBreakpoint.of(context);
    // Only the tab list and invite matter here; a full watch rebuilt every
    // open tab on each AppConfig notify (session refresh, unread, queue…).
    context.select((AppConfig c) => (c.shellTabs.join(','), c.pendingInvite, c.hasPendingQr));
    final config = context.read<AppConfig>();
    if (config.pendingInvite != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Joined → go pick the new business.
        if (await maybePromptInviteJoin(context)) await config.clearBusiness();
      });
    }
    if (config.hasPendingQr) {
      // QR from the web opened with the phone camera while signed in → add that Space.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final qr = mounted ? config.takePendingQr() : null;
        if (qr != null) nxPush<bool>(context, QrLoginScanScreen(initial: qr));
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
    _prewarm(ids);
    final notifIndex = ids.indexOf('notifications');
    final destinations = [
      for (final id in ids)
        if (id == kMenuTabId)
          const NxTabDestination(icon: NxI.dotsThreeCircle, selectedIcon: NxI.dotsThreeCircleFill, label: 'เมนู')
        else
          NxTabDestination(icon: shellTabById(id)!.icon, selectedIcon: shellTabById(id)!.selectedIcon, label: shellTabById(id)!.label),
    ];
    final nav = ListenableBuilder(
      listenable: UnreadNotifications.instance,
      builder: (context, _) {
        final unread = UnreadNotifications.instance.count;
        return NxTabNav(
          destinations: destinations,
          selectedIndex: selected,
          onSelect: (i) {
            // A new tab starts with its tools and the bar showing.
            NxChromeBus.reset();
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
                  child: NxShellTabScope(tabId: id, child: _built.contains(id) ? shellTabScreen(id) : const SizedBox.shrink()),
                ),
            ],
          ),
        ),
      ],
    );

    final Widget page;
    if (bp.useRail) {
      page = Scaffold(
        body: Row(
          children: [
            nav,
            Expanded(child: stack),
          ],
        ),
      );
    }
    // Every tab scrolls under the floating glass bar; content dissolves into a
    // progressive blur toward the bottom edge (pages pad via MediaQuery).
    else {
      page = Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            stack,
            // Tabs built on NxScrollScaffold blur under their own FAB; the hub
            // tabs (own header, no FAB) get the band from here.
            if (_hubTabs.contains(_current))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // Ends at about the middle of the floating tab bar (bar ≈ 76 + 10 margin).
                height: 48 + MediaQuery.viewPaddingOf(context).bottom,
                child: const NxEdgeBlur(fromTop: false, solidFraction: 0.5),
              ),
          ],
        ),
        // Slides away while reading down a page (or while dragging a card, so
        // the drop dock has the bottom edge); a small scroll back brings it in.
        // Its layout height stays, so pages don't jump.
        bottomNavigationBar: ListenableBuilder(
          listenable: Listenable.merge([NxChromeBus.hidden, NxChromeBus.dragging]),
          child: nav,
          builder: (context, child) {
            final away = NxChromeBus.hidden.value || NxChromeBus.dragging.value;
            return IgnorePointer(
              ignoring: away,
              child: AnimatedSlide(
                offset: away ? const Offset(0, 1.5) : Offset.zero,
                duration: const Duration(milliseconds: 280),
                curve: away ? Curves.easeInCubic : Curves.easeOutCubic,
                child: AnimatedOpacity(opacity: away ? 0 : 1, duration: const Duration(milliseconds: 220), child: child),
              ),
            );
          },
        ),
      );
    }
    // System back on the shell: close what the tab has open (search, a
    // selected row, a sub-folder) → back to the first tab → press twice to exit.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack(ids);
      },
      child: page,
    );
  }

  DateTime? _lastBack;

  void _onBack(List<String> ids) {
    if (NxShellBack.instance.handle(_current)) return;
    if (_current != ids.first) {
      NxChromeBus.reset();
      setState(() => _current = ids.first);
      context.read<AppConfig>().setLastTab(ids.first);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(key: const ValueKey('shell-exit-hint'), content: Text(tr('กดย้อนกลับอีกครั้งเพื่อออกจากแอป')), duration: const Duration(seconds: 2)),
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
              leading: Icon(NxI.cloud, color: cs.onTertiaryContainer),
              title: Text(tr('มี $n รายการรอส่ง (บันทึกตอนออฟไลน์)'), style: TextStyle(color: cs.onTertiaryContainer)),
              trailing: TextButton(onPressed: () => context.read<AppConfig>().flushOfflineQueue(), child: Text(tr('ส่งตอนนี้'))),
            ),
          ),
        );
      },
    );
  }
}
