import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/nx_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../screens/ai/assistant/ai_assistant_screen.dart';
import '../../screens/ai/assistant/ai_shared_chat_screen.dart';
import '../../screens/ai/isaac_coming_soon_screen.dart';
import '../../screens/ai/isaac_embed_screen.dart';
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
import '../../screens/module/menu_group_screen.dart';
import '../../screens/crm/call_log_screen.dart';
import '../../screens/notifications/notification_center_screen.dart';
import '../../screens/whats_new/whats_new_screen.dart';
import '../../screens/settings/devices_screen.dart';
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
import '../auth_redirect.dart';
import '../invite_link.dart';
import '../server_profile.dart';
import '../../screens/update_required_screen.dart';
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
import '../qr_login.dart';
import 'route_access.dart';
import '../i18n.dart';
import '../../screens/profile/profile_hub_screen.dart';

GoRouter createAppRouter(AppConfig config) {
  return GoRouter(
    navigatorKey: appAliceNavigatorKey ?? GlobalKey<NavigatorState>(),
    refreshListenable: Listenable.merge([config, PushNavigation.instance]),
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      // LINE started with ?app=1 comes back as moainext://app/login?token=… (or ?error=).
      if (state.uri.path == AppRoutes.login && !config.isLoggedIn) {
        final r = parseAuthRedirect(state.uri.toString());
        if (r != null && (r.token != null || r.error != null || r.mergeIntent != null)) {
          config.handleAuthDeepLink(r);
          // Drop the query so later refreshes don't hand the same link over again.
          return AppRoutes.login;
        }
      }
      // QR from the web scanned with the phone camera → login screen finishes it.
      final qr = state.uri.path == '/qr-login'
          ? QrLoginLink.parse('moainext://app/qr-login?${state.uri.query}')
          : QrLoginLink.parse(state.uri.toString());
      if (qr != null) {
        config.stashQr(qr);
        return config.isLoggedIn ? AppRoutes.mainShell : AppRoutes.login;
      }
      // Server requires a newer app (GET /api/health → mobile.min_version).
      if (config.isReady && config.updateNeed == UpdateNeed.required) {
        return state.matchedLocation == AppRoutes.updateRequired ? null : AppRoutes.updateRequired;
      }
      if (state.matchedLocation == AppRoutes.updateRequired) return AppRoutes.splash;
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
        // A tapped notification opens ON TOP of the app (home stays below),
        // so back returns into the app instead of closing it.
        final target = accessRedirectFor(config.session, pending) ?? pending;
        final router = GoRouter.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) => router.push(target));
        final current = accessRedirectFor(config.session, loc);
        if (loc == AppRoutes.splash) return AppRoutes.mainShell;
        return current;
      }
      return accessRedirectFor(config.session, loc);
    },
    errorBuilder: (context, state) => _RouteNotFoundScreen(location: state.uri.toString()),
    routes: [
      GoRoute(path: AppRoutes.register, redirect: (_, _) => AppRoutes.login),
      GoRoute(path: AppRoutes.updateRequired, builder: (_, _) => const UpdateRequiredScreen()),
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
        // A new business / package = a fresh shell: every tab (Home, calendar,
        // lists, search, notifications) reloads for it instead of keeping the
        // previous business's data.
        builder: (_, _) => Selector<AppConfig, String>(
          selector: (_, c) => '${c.session.businessId}|${c.session.packageCode}',
          builder: (_, scope, _) => AppShell(key: ValueKey('shell-$scope')),
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.devices,
        builder: (_, _) => const DevicesScreen(),
      ),
      GoRoute(
        path: AppRoutes.whatsNew,
        builder: (_, _) => const WhatsNewScreen(),
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
        path: '/menu/:group',
        builder: (_, state) => MenuGroupScreen(groupId: state.pathParameters['group'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.callLog,
        builder: (_, _) => const CallLogScreen(),
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
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return AiAssistantScreen(contextModule: q['ctx_module'], contextId: q['ctx_id'], contextTitle: q['ctx_title']);
        },
      ),
      GoRoute(
        path: '/share/ai/:token',
        builder: (_, state) => AiSharedChatScreen(token: state.pathParameters['token'] ?? ''),
      ),
      // ISAAC AI (same routes as the web menu group).
      GoRoute(path: AppRoutes.isaacNotebook, builder: (_, _) => const IsaacEmbedScreen(menu: 'bot')),
      GoRoute(path: AppRoutes.aiMinuteAuto, builder: (_, _) => const IsaacEmbedScreen(menu: 'minute_auto')),
      GoRoute(path: AppRoutes.isaacAgent, builder: (_, _) => const IsaacComingSoonScreen(product: 'agent')),
      GoRoute(path: AppRoutes.isaacSocialWatch, builder: (_, _) => const IsaacComingSoonScreen(product: 'social_watch')),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileSecurity,
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
      appBar: AppBar(title: Text(tr('ไม่พบหน้า'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(NxI.unlink, size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(tr('ไม่พบหน้าที่ต้องการในแอป'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                tr(location),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.mainShell),
                child: Text(tr('กลับหน้าหลัก')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
