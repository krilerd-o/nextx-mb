import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/ai/ai_chat_screen.dart';
import '../../screens/approvals/approvals_screen.dart';
import '../../screens/commerce/commerce_home_screen.dart';
import '../../screens/app_shell.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/calendar/calendar_home_screen.dart';
import '../../screens/chat/chat_home_screen.dart';
import '../../screens/crm/crm_home_screen.dart';
import '../../screens/fsm/fsm_home_screen.dart';
import '../../screens/crm/field_gallery_screen.dart';
import '../../screens/hub/business_hub_screen.dart';
import '../../screens/hr/attendance_screen.dart';
import '../../screens/hr/attendance_report_screen.dart';
import '../../screens/hr/leave_screen.dart';
import '../../screens/jobs/my_jobs_screen.dart';
import '../../screens/module/module_hub_screen.dart';
import '../../screens/notifications/notification_center_screen.dart';
import '../../screens/onboarding/getting_started_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/splash_screen.dart';
import '../../screens/workspace/workspace_home_screen.dart';
import '../../screens/deep_link_loaders.dart';
import '../../screens/files/files_home_screen.dart';
import '../../screens/mail/mail_home_screen.dart';
import '../../screens/search/global_search_screen.dart';
import '../app_alice.dart';
import '../app_config.dart';
import '../push_navigation.dart';
import 'app_routes.dart';
import 'onboarding_redirect.dart';
import '../invite_link.dart';
import '../shell_tabs.dart';
import '../../screens/auth/server_screen.dart';
import '../../screens/auth/welcome_screen.dart';
import '../../screens/hr/hr_home_screen.dart';
import '../../screens/hub/package_picker_screen.dart';
import '../../screens/onboarding/role_setup_screen.dart';
import '../../screens/onboarding/tab_setup_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/settings/diagnostics_screen.dart';
import 'notification_deep_link.dart';
import 'route_access.dart';

GoRouter createAppRouter(AppConfig config) {
  return GoRouter(
    navigatorKey: appAliceNavigatorKey ?? GlobalKey<NavigatorState>(),
    refreshListenable: Listenable.merge([config, PushNavigation.instance]),
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final invite = parseInviteLink(state.uri);
      if (invite != null) {
        config.stashInvite(invite);
        return config.isLoggedIn ? AppRoutes.mainShell : AppRoutes.login;
      }
      final loc = state.matchedLocation;
      if (kDebugMode &&
          (loc == AppRoutes.fieldGallery ||
              state.uri.path == AppRoutes.fieldGallery ||
              state.uri.fragment == AppRoutes.fieldGallery ||
              state.uri.fragment.endsWith('debug/fields'))) {
        return null;
      }
      final step = onboardingRedirect(
        loc: loc,
        ready: config.isReady,
        loggedIn: config.isLoggedIn,
        serverConfirmed: config.serverConfirmed,
        hasBusiness: config.hasBusinessContext,
        hasPackage: config.hasPackage,
        roleSetupDone: config.roleSetupDone,
      );
      if (step != null) return step;
      if (!config.isLoggedIn || !config.hasBusinessContext || !config.hasPackage || !config.roleSetupDone) {
        return null; // still in the sign-in / setup flow
      }
      final pending = PushNavigation.instance.take();
      if (pending != null && pending.isNotEmpty && pending != loc) {
        return accessRedirectFor(config.session, pending) ?? pending;
      }
      return accessRedirectFor(config.session, loc);
    },
    errorBuilder: (context, state) => _RouteNotFoundScreen(location: state.uri.toString()),
    routes: [
      GoRoute(path: AppRoutes.register, redirect: (_, _) => AppRoutes.login),
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.server,
        builder: (_, _) => const ServerScreen(),
      ),
      GoRoute(
        path: AppRoutes.package,
        builder: (_, _) => const PackagePickerScreen(),
      ),
      GoRoute(
        path: AppRoutes.roleSetup,
        builder: (_, _) => const RoleSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.tabSetup,
        builder: (_, state) => TabSetupScreen(initial: state.extra is ShellTabsConfig ? state.extra as ShellTabsConfig : null),
      ),
      GoRoute(
        path: AppRoutes.tabEditor,
        builder: (_, _) => const TabSetupScreen(fromSettings: true),
      ),
      GoRoute(
        path: AppRoutes.roleEditor,
        builder: (_, _) => const RoleSetupScreen(fromSettings: true),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnostics,
        builder: (_, _) => const DiagnosticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.hrHome,
        builder: (_, _) => const HrHomeScreen(standalone: true),
      ),
      GoRoute(
        path: AppRoutes.fieldGallery,
        builder: (_, _) => const FieldGalleryScreen(),
      ),
      GoRoute(
        path: AppRoutes.hub,
        builder: (_, _) => const BusinessHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.gettingStarted,
        builder: (_, _) => const GettingStartedScreen(),
      ),
      GoRoute(
        path: AppRoutes.mainShell,
        builder: (_, _) => const AppShell(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.attendance,
        builder: (_, _) => const AttendanceScreen(),
      ),
      GoRoute(
        path: AppRoutes.leaveList,
        builder: (_, _) => const LeaveScreen(),
      ),
      GoRoute(
        path: AppRoutes.attendanceReport,
        builder: (_, _) => const AttendanceReportScreen(),
      ),
      GoRoute(
        path: AppRoutes.leaveRequest,
        builder: (_, _) => const LeaveScreen(initialTab: 1),
      ),
      GoRoute(
        path: AppRoutes.moduleHub,
        builder: (_, _) => const ModuleHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.crmHome,
        builder: (_, _) => const CrmHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.fsmHome,
        builder: (_, _) => const FsmHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.workspaceHome,
        builder: (_, _) => const WorkspaceHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.chatHome,
        builder: (_, _) => const ChatHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.aiChat,
        builder: (_, _) => const AiChatScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (_, _) => const CalendarHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.jobs,
        builder: (_, _) => const MyJobsScreen(),
      ),
      GoRoute(
        path: AppRoutes.globalSearch,
        builder: (_, _) => const GlobalSearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.files,
        builder: (_, _) => const FilesHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.mail,
        builder: (_, _) => const MailHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.approvals,
        builder: (_, _) => const ApprovalsScreen(),
      ),
      GoRoute(
        path: AppRoutes.commerce,
        builder: (_, _) => const CommerceHomeScreen(),
      ),
      // Web-style URLs (`https://<host>/modules/...`) arriving via Android App Links /
      // iOS Universal Links — reuse the push-payload mapper.
      GoRoute(
        path: '/modules/:module',
        redirect: (_, state) => notificationDeepLink(state.uri.toString()),
      ),
      GoRoute(
        path: '/modules/:module/view/:id',
        redirect: (_, state) => notificationDeepLink(state.uri.toString()),
      ),
      GoRoute(
        path: '/modules/:module/:id',
        redirect: (_, state) => notificationDeepLink(state.uri.toString()),
      ),
      GoRoute(
        path: '/crm/:module/:id',
        builder: (_, state) => EntityByIdLoader(
          module: state.pathParameters['module'] ?? 'lead',
          id: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/crm/:module',
        builder: (_, state) => EntityListRoute(module: state.pathParameters['module'] ?? 'lead'),
      ),
      GoRoute(
        path: '/fsm/:module/:id',
        builder: (_, state) => EntityByIdLoader(
          module: state.pathParameters['module'] ?? 'job',
          id: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/fsm/:module',
        builder: (_, state) => EntityListRoute(module: state.pathParameters['module'] ?? 'job'),
      ),
      GoRoute(
        path: '/calendar/:id',
        builder: (_, state) => ActivityByIdLoader(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/jobs/:id',
        builder: (_, state) => JobByIdLoader(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/workspace/:boardId/:taskId',
        builder: (_, state) => TaskByIdLoader(
          boardId: state.pathParameters['boardId'] ?? '',
          taskId: state.pathParameters['taskId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/workspace/:boardId',
        builder: (_, state) => BoardByIdLoader(boardId: state.pathParameters['boardId'] ?? ''),
      ),
      GoRoute(
        path: '/chat/:roomId',
        builder: (_, state) => ChatByIdLoader(roomId: state.pathParameters['roomId'] ?? ''),
      ),
    ],
  );
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ไม่พบหน้า')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('ไม่พบหน้าที่ต้องการในแอป', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                location,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.mainShell),
                child: const Text('กลับหน้าหลัก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
