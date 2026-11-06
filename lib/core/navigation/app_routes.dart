/// Named routes for [GoRouter]
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String hub = '/hub';
  static const String gettingStarted = '/getting-started';
  static const String mainShell = '/main';

  static const String globalSearch = '/search';
  static const String notifications = '/notifications';
  static const String attendance = '/hr/attendance';
  static const String leaveList = '/hr/leave';
  static const String leaveRequest = '/hr/leave/request';

  static const String moduleHub = '/module-hub';
  static const String crmHome = '/crm';
  static const String fsmHome = '/fsm';
  static const String fieldGallery = '/debug/fields';
  static const String workspaceHome = '/workspace';
  static const String chatHome = '/chat';
  static const String aiChat = '/ai';
  static const String profile = '/profile';
  static const String calendar = '/calendar';
  static const String jobs = '/jobs';
  static const String files = '/files';
  static const String mail = '/mail';

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
