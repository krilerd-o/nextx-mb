import '../entity_modules.dart';
import '../menu_access.dart';
import '../session_state.dart';
import 'app_routes.dart';

/// Menu keys that grant access to [path]. `null` means the route is not gated.
///
/// Used by the router redirect so that deep links and push taps cannot open
/// a module the user's NEXTX menus exclude.
List<String>? requiredMenusFor(String path) {
  final segs = Uri.tryParse(path)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
  if (segs.isEmpty) return null;
  switch (segs.first) {
    case 'crm':
      if (segs.length >= 2) return [EntityModules.menuKeyOf(segs[1])];
      return MenuAccess.crmKeys;
    case 'fsm':
      if (segs.length >= 2) return [EntityModules.menuKeyOf(segs[1])];
      return MenuAccess.fsmKeys;
    case 'calendar':
      return const [MenuAccess.calendar, MenuAccess.incoming, MenuAccess.pending];
    case 'jobs':
      return const [MenuAccess.job];
    case 'workspace':
      return const [MenuAccess.workspace];
    case 'chat':
      return const [MenuAccess.chat];
    case 'ai':
      return const [MenuAccess.ai];
    case 'approvals':
      return const [MenuAccess.quotation, MenuAccess.leaveManagement, MenuAccess.pendingApprovals];
    case 'commerce':
      return const [MenuAccess.storeOrders, MenuAccess.storeStock];
    case 'mail':
      return const [MenuAccess.mailbox];
    case 'files':
      return const [MenuAccess.files];
    case 'hr':
      if (segs.length >= 2 && segs[1] == 'attendance') return const [MenuAccess.attendance];
      if (segs.length >= 2 && segs[1] == 'leave') {
        return const [MenuAccess.leave, MenuAccess.leaveManagement];
      }
      return const [MenuAccess.attendance, MenuAccess.leave, MenuAccess.leaveManagement];
    default:
      return null;
  }
}

/// Returns where to send the user instead, or `null` when [path] is allowed.
///
/// Before menus are loaded we let navigation through; screens still fail
/// server-side for records the user cannot read.
String? accessRedirectFor(SessionState session, String path) {
  if (!session.menusLoaded) return null;
  final keys = requiredMenusFor(path);
  if (keys == null) return null;
  if (MenuAccess.any(session, keys)) return null;
  return AppRoutes.mainShell;
}
