/// Named routes for [GoRouter]
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String welcome = '/welcome';
  static const String server = '/server';
  static const String register = '/register';
  static const String lineLogin = '/login/line';
  static const String linkConfirm = '/login/link';
  static const String package = '/package';
  static const String roleSetup = '/setup/role';
  static const String tabSetup = '/setup/tabs';
  static const String tabEditor = '/settings/tabs';
  static const String roleEditor = '/settings/role';
  static const String settings = '/settings';
  static const String diagnostics = '/settings/diagnostics';
  static const String updateRequired = '/update-required';
  static const String hrHome = '/hr';
  static const String gettingStartedEdit = '/settings/appearance';
  static const String hub = '/hub';
  static const String gettingStarted = '/getting-started';
  static const String mainShell = '/main';

  static const String globalSearch = '/search';
  static const String notifications = '/notifications';
  static const String whatsNew = '/whats-new';
  static const String devices = '/devices';
  static const String attendance = '/hr/attendance';
  static const String leaveList = '/hr/leave';
  static const String leaveRequest = '/hr/leave/request';
  static const String attendanceReport = '/hr/attendance-report';

  static const String moduleHub = '/module-hub';
  static const String crmHome = '/crm';
  static const String fsmHome = '/fsm';
  static const String fieldGallery = '/debug/fields';
  static const String workspaceHome = '/workspace';
  static const String chatHome = '/chat';
  static const String aiChat = '/ai';
  static const String profile = '/profile';
  static const String profileSecurity = '/profile/security';
  static const String calendar = '/calendar';
  static const String jobs = '/jobs';
  static const String files = '/files';
  static const String mail = '/mail';
  static const String approvals = '/approvals';
  static const String commerce = '/commerce';

  static String crmModule(String module) => '/crm/$module';
  static String crmRecord(String module, String id) => '/crm/$module/$id';
  static String fsmModule(String module) => '/fsm/$module';
  static String fsmRecord(String module, String id) => '/fsm/$module/$id';
  static String activity(String id) => '/calendar/$id';
  static String job(String id) => '/jobs/$id';
  static String board(String id) => '/workspace/$id';
  static String task(String boardId, String taskId) => '/workspace/$boardId/$taskId';
  static String chatRoom(String id) => '/chat/$id';
}
