import '../entity_modules.dart';
import '../isaac_menu.dart';
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
    case 'form':
      if (segs.length >= 2) return [EntityModules.menuKeyOf(segs[1])];
      return null;
    case 'modules':
      // Generic module links (/modules/:module[/...]) follow the same menu rule.
      if (segs.length >= 2) return [EntityModules.menuKeyOf(segs[1])];
      return null;
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
    case 'lead-register':
      return const [MenuAccess.leadRegister];
    case 'call-log':
      return const [MenuAccess.callLog];
    case 'comm-ai':
      if (segs.length >= 2 && segs[1] == 'insights') return const [MenuAccess.commAiInsights];
      return const [MenuAccess.commAi];
    case 'hr':
      if (segs.length >= 2 && segs[1] == 'attendance-report') {
        return const [MenuAccess.attendanceReport, MenuAccess.hrDashboard];
      }
      if (segs.length >= 2 && segs[1] == 'attendance') return const [MenuAccess.attendance];
      if (segs.length >= 2 && segs[1] == 'leave') {
        return const [MenuAccess.leave, MenuAccess.leaveManagement];
      }
      return const [MenuAccess.attendance, MenuAccess.leave, MenuAccess.leaveManagement];
    default:
      return null;
  }
}

/// The ISAAC AI menu item a path opens, or null.
IsaacMenuItem? isaacItemFor(String path) {
  final p = Uri.tryParse(path)?.path ?? path;
  // Native notebook (and the old ISAAC / web notebook links) before the /ai/* Assistant.
  if (p == IsaacMenu.notebook.route || p.startsWith('${IsaacMenu.notebook.route}/') || p == '/isaac' || p == '/ai/notebook' || p.startsWith('/ai/notebook/')) {
    return IsaacMenu.notebook;
  }
  if (p.startsWith('${IsaacMenu.minuteMeeting.route}/')) return IsaacMenu.minuteMeeting;
  // Meeting join links (/m/:code) open AI Minute Meeting.
  if (p.startsWith('/m/')) return IsaacMenu.minuteMeeting;
  for (final item in IsaacMenu.all) {
    if (p == item.route || (item.route == '/ai' && p.startsWith('/ai/'))) return item;
  }
  return null;
}

/// Returns where to send the user instead, or `null` when [path] is allowed.
///
/// Before menus are loaded we let navigation through; screens still fail
/// server-side for records the user cannot read.
String? accessRedirectFor(SessionState session, String path) {
  if (!session.menusLoaded) return null;
  // ISAAC AI pages follow the plugin / AI settings (like the web menu). Uses
  // the last loaded access; before it is known the page itself checks.
  final isaac = isaacItemFor(path);
  // The role permission is known without the ISAAC settings (same rule as the server's requireRoleMenu).
  if (isaac?.key == IsaacMenu.assistant.key && !session.roleAllows(const ['ai-assistant'])) return AppRoutes.mainShell;
  if (isaac?.key == IsaacMenu.notebook.key && !session.roleAllows(const ['isaac-notebook', 'ai-assistant'])) return AppRoutes.mainShell;
  if (isaac != null) {
    // AI Minute Meeting is a NEXTX menu (Package + Role), not an ISAAC plugin item:
    // check it even before the plugin answers are cached.
    if (isaac.key == IsaacMenu.minuteMeeting.key && !session.isSuperadmin && !session.canAccess(isaac.key)) {
      return AppRoutes.mainShell;
    }
    final access = IsaacAccessCache.peek(session.businessId ?? '');
    // The notebook runs on NEXTX AI (`ai_chat`): the Assistant's "Notebook" entry
    // opens it even when the ISAAC plugin menu item is hidden.
    final allowed = access == null ||
        access.visible(isaac, session) ||
        (isaac.key == IsaacMenu.notebook.key && access.visible(IsaacMenu.assistant, session));
    if (!allowed) return AppRoutes.mainShell;
    // The Assistant shows in the menu on `ai_chat` even when a Package list leaves its key out
    // (like the web), so the page it opens must not bounce the user back.
    if (access != null && isaac.key == IsaacMenu.assistant.key) return null;
  }
  final keys = requiredMenusFor(path);
  if (keys == null) return null;
  // Same rule as the store menu: orders, or stock for business admins only.
  final first = Uri.tryParse(path)?.pathSegments.where((x) => x.isNotEmpty).firstOrNull;
  if (first == 'commerce') {
    final ok = MenuAccess.allow(session, MenuAccess.storeOrders) ||
        (MenuAccess.allow(session, MenuAccess.storeStock) && session.isBusinessAdmin);
    return ok ? null : AppRoutes.mainShell;
  }
  if (MenuAccess.any(session, keys)) return null;
  return AppRoutes.mainShell;
}
