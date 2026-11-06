import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../screens/ai/ai_chat_screen.dart';
import '../../screens/app_shell.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/calendar/calendar_home_screen.dart';
import '../../screens/chat/chat_home_screen.dart';
import '../../screens/crm/crm_home_screen.dart';
import '../../screens/fsm/fsm_home_screen.dart';
import '../../screens/crm/field_gallery_screen.dart';
import '../../screens/hub/business_hub_screen.dart';
import '../../screens/hr/attendance_screen.dart';
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

GoRouter createAppRouter(AppConfig config) {
  return GoRouter(
    navigatorKey: appAliceNavigatorKey ?? GlobalKey<NavigatorState>(),
    refreshListenable: Listenable.merge([config, PushNavigation.instance]),
    initialLocation: AppRoutes.splash,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (kDebugMode &&
          (loc == AppRoutes.fieldGallery ||
              state.uri.path == AppRoutes.fieldGallery ||
              state.uri.fragment == AppRoutes.fieldGallery ||
              state.uri.fragment.endsWith('debug/fields'))) {
        return null;
      }
      if (!config.isReady) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }
      if (!config.isLoggedIn) {
        return loc == AppRoutes.login ? null : AppRoutes.login;
      }
      if (!config.hasBusinessContext) {
        return loc == AppRoutes.hub ? null : AppRoutes.hub;
      }
      if (!config.gettingStartedDone) {
        return loc == AppRoutes.gettingStarted ? null : AppRoutes.gettingStarted;
      }
      const gated = [
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.hub,
        AppRoutes.gettingStarted,
      ];
      if (gated.contains(loc)) return AppRoutes.mainShell;
      final pending = PushNavigation.instance.take();
      if (pending != null && pending.isNotEmpty && pending != loc) return pending;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.fieldGallery,
        builder: (_, __) => const FieldGalleryScreen(),
      ),
      GoRoute(
        path: AppRoutes.hub,
        builder: (_, __) => const BusinessHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.gettingStarted,
        builder: (_, __) => const GettingStartedScreen(),
      ),
      GoRoute(
        path: AppRoutes.mainShell,
        builder: (_, __) => const AppShell(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.attendance,
        builder: (_, __) => const AttendanceScreen(),
      ),
      GoRoute(
        path: AppRoutes.leaveList,
        builder: (_, __) => const LeaveScreen(),
      ),
      GoRoute(
        path: AppRoutes.moduleHub,
        builder: (_, __) => const ModuleHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.crmHome,
        builder: (_, __) => const CrmHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.fsmHome,
        builder: (_, __) => const FsmHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.workspaceHome,
        builder: (_, __) => const WorkspaceHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.chatHome,
        builder: (_, __) => const ChatHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.aiChat,
        builder: (_, __) => const AiChatScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (_, __) => const CalendarHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.jobs,
        builder: (_, __) => const MyJobsScreen(),
      ),
      GoRoute(
        path: AppRoutes.globalSearch,
        builder: (_, __) => const GlobalSearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.files,
        builder: (_, __) => const FilesHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.mail,
        builder: (_, __) => const MailHomeScreen(),
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
