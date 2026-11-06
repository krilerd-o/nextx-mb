import 'session_state.dart';

class MenuAccess {
  MenuAccess._();

  static const lead = 'lead';
  static const contact = 'contact';
  static const account = 'account';
  static const deal = 'deal';
  static const quotation = 'quotation';
  static const caseKey = 'case';
  static const product = 'product';
  static const service = 'service';
  static const calendar = 'calendar';
  static const workspace = 'workspace';
  static const chat = 'community-chat';
  static const ai = 'ai-assistant';
  static const attendance = 'attendance';
  static const leave = 'leave-request';
  static const leaveManagement = 'leave-management';
  static const callLog = 'call-log';
  static const incoming = 'activity-incoming';
  static const pending = 'pending-work';
  static const job = 'job';
  static const inspection = 'inspection';
  static const serviceContract = 'service-contract';
  static const asset = 'asset';
  static const serviceLocation = 'service-location';
  static const skill = 'skill';
  static const mailbox = 'mailbox';
  static const files = 'file-manager';
  static const profile = 'profile';
  static const pendingApprovals = 'pending-approvals';
  static const storeOrders = 'mini-store-orders';
  static const attendanceReport = 'attendance-report';
  static const hrDashboard = 'hr-dashboard';
  static const storeStock = 'mini-store-stock';

  static const crmKeys = [
    lead,
    contact,
    account,
    deal,
    caseKey,
    quotation,
    product,
    service,
  ];

  static const fsmKeys = [
    job,
    inspection,
    serviceContract,
    asset,
    serviceLocation,
    skill,
  ];

  static bool allow(SessionState session, String menuKey) => session.canAccess(menuKey);

  static bool any(SessionState session, Iterable<String> keys) =>
      keys.any((k) => allow(session, k));

  static bool anyCrm(SessionState session) => any(session, crmKeys);

  static bool anyFsm(SessionState session) => any(session, fsmKeys);

  static bool anyHr(SessionState session) =>
      allow(session, attendance) || allow(session, leave);

  static bool anyCalendar(SessionState session) =>
      allow(session, calendar) || allow(session, incoming) || allow(session, pending);
}
