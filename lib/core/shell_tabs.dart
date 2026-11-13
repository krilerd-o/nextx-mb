import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../widgets/nx_icons.dart';
import 'menu_access.dart';

/// A destination the user can pin to the bottom bar.
class ShellTabDef {
  const ShellTabDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.anyMenu = const [],
    this.description = '',
  });

  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Shown only if the user has at least one of these NEXTX menu keys
  /// (empty = always available).
  final List<String> anyMenu;
  final String description;
}

/// Always the last tab: every module + settings, so nothing is unreachable.
const kMenuTabId = 'menu';

/// Bottom-bar slots besides the fixed "เมนู" tab.
const kMaxCustomTabs = 4;

const shellTabCatalog = <ShellTabDef>[
  ShellTabDef(id: 'dashboard', label: 'หน้าหลัก', icon: NxI.house, selectedIcon: NxI.houseFill, description: 'ภาพรวมงานวันนี้'),
  ShellTabDef(id: 'leads', label: 'ผู้มุ่งหวัง', icon: NxI.flag, selectedIcon: NxI.flag, anyMenu: ['lead'], description: 'ผู้มุ่งหวังที่กำลังติดตาม'),
  ShellTabDef(id: 'quotation', label: 'ใบเสนอราคา', icon: NxI.receipt, selectedIcon: NxI.receipt, anyMenu: ['quotation'], description: 'ใบเสนอราคา'),
  ShellTabDef(id: 'crm', label: 'ลูกค้า', icon: NxI.users, selectedIcon: NxI.users, anyMenu: MenuAccess.crmKeys, description: 'CRM ทั้งหมด'),
  ShellTabDef(id: 'cases', label: 'เคส', icon: NxI.headset, selectedIcon: NxI.headsetFill, anyMenu: ['case'], description: 'เคสบริการลูกค้า'),
  ShellTabDef(id: 'calendar', label: 'ปฏิทิน', icon: NxI.calendarBlank, selectedIcon: NxI.calendarCheck, anyMenu: [MenuAccess.calendar, MenuAccess.incoming, MenuAccess.pending], description: 'นัดหมายและเช็คอิน'),
  ShellTabDef(id: 'chat', label: 'แชททีม', icon: NxI.chatCircle, selectedIcon: NxI.chatCircle, anyMenu: [MenuAccess.chat], description: 'แชททีม'),
  ShellTabDef(id: 'mail', label: 'กล่องจดหมาย', icon: NxI.envelope, selectedIcon: NxI.envelope, anyMenu: [MenuAccess.mailbox], description: 'อ่าน เขียน และตอบกลับเมล'),
  ShellTabDef(id: 'workspace', label: 'เวิร์กสเปซ', icon: NxI.kanban, selectedIcon: NxI.kanban, anyMenu: [MenuAccess.workspace], description: 'บอร์ดงาน Workspace'),
  ShellTabDef(id: 'approvals', label: 'รออนุมัติ', icon: NxI.checkCircle, selectedIcon: NxI.checkCircleFill, anyMenu: [MenuAccess.quotation, MenuAccess.leaveManagement, MenuAccess.pendingApprovals], description: 'รายการรออนุมัติ'),
  ShellTabDef(id: 'hr', label: 'HR', icon: NxI.briefcase, selectedIcon: NxI.briefcaseFill, anyMenu: [MenuAccess.attendance, MenuAccess.leave, MenuAccess.leaveManagement], description: 'ลงเวลาและการลา'),
  ShellTabDef(id: 'jobs', label: 'งานช่าง', icon: NxI.wrench, selectedIcon: NxI.wrench, anyMenu: [MenuAccess.job], description: 'งานบริการภาคสนาม'),
  ShellTabDef(id: 'commerce', label: 'ร้านค้า', icon: NxI.package, selectedIcon: NxI.package, anyMenu: [MenuAccess.storeOrders, MenuAccess.storeStock], description: 'ออเดอร์และสต็อก'),
  ShellTabDef(id: 'files', label: 'จัดการไฟล์', icon: NxI.folder, selectedIcon: NxI.folder, anyMenu: [MenuAccess.files], description: 'ไฟล์ของธุรกิจ'),
  ShellTabDef(id: 'ai', label: 'AI', icon: NxI.robot, selectedIcon: NxI.robot, anyMenu: [MenuAccess.ai], description: 'ผู้ช่วย AI'),
  ShellTabDef(id: 'search', label: 'ค้นหา', icon: NxI.magnifyingGlass, selectedIcon: NxI.magnifyingGlassFill, description: 'ค้นหาทุกโมดูล'),
  ShellTabDef(id: 'notifications', label: 'แจ้งเตือน', icon: NxI.bell, selectedIcon: NxI.bellFill, description: 'การแจ้งเตือน'),
];

ShellTabDef? shellTabById(String id) {
  for (final t in shellTabCatalog) {
    if (t.id == id) return t;
  }
  return null;
}

/// "คุณทำงานด้านไหน" — work roles used to suggest a bottom bar.
class WorkRole {
  const WorkRole(this.id, this.label, this.description, this.icon, this.tabs);
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final List<String> tabs;
}

const workRoles = <WorkRole>[
  WorkRole('sales', 'ทีมขาย', 'ผู้มุ่งหวัง ดีล ใบเสนอราคา นัดลูกค้า', NxI.handshake, ['dashboard', 'leads', 'quotation', 'calendar']),
  WorkRole('service', 'ทีมบริการลูกค้า', 'เคส แชท ติดตามลูกค้า', NxI.headset, ['dashboard', 'cases', 'chat', 'calendar']),
  WorkRole('field', 'ช่างภาคสนาม', 'งานช่าง เช็คอินหน้างาน ลงเวลา', NxI.wrench, ['jobs', 'calendar', 'hr', 'chat']),
  WorkRole('marketing', 'ทีมการตลาด', 'ลูกค้า แคมเปญ เมล', NxI.flag, ['dashboard', 'crm', 'mail', 'chat']),
  WorkRole('online', 'ทีมขายออนไลน์/ร้านค้า', 'ออเดอร์ สต็อก แชทลูกค้า', NxI.package, ['commerce', 'chat', 'notifications', 'dashboard']),
  WorkRole('finance', 'ทีมบัญชี/การเงิน', 'ใบเสนอราคา ออเดอร์ อนุมัติ', NxI.receipt, ['dashboard', 'quotation', 'commerce', 'approvals']),
  WorkRole('hr', 'ทีม HR', 'ลงเวลา การลา อนุมัติ', NxI.briefcase, ['hr', 'approvals', 'calendar', 'chat']),
  WorkRole('manager', 'ผู้บริหาร/หัวหน้าทีม', 'ภาพรวม อนุมัติ ติดตามทีม', NxI.medal, ['dashboard', 'approvals', 'crm', 'chat']),
  WorkRole('general', 'ทั่วไป/ทีมงาน', 'งาน แชท ปฏิทิน', NxI.users, ['dashboard', 'workspace', 'chat', 'calendar']),
];

const kFallbackTabs = ['dashboard', 'calendar', 'chat', 'search', 'notifications'];

/// Picks the bottom-bar tabs (without the fixed "เมนู" tab).
///
/// - [custom] (the user's own arrangement) wins when set; otherwise the
///   chosen [roles] are merged in order.
/// - Tabs the user has no menu permission for are dropped ([allowed]).
/// - Topped up from [kFallbackTabs] so the bar never ends up nearly empty.
List<String> resolveShellTabs({
  required List<String> roles,
  List<String>? custom,
  required bool Function(List<String> anyMenu) allowed,
  int max = kMaxCustomTabs,
}) {
  bool ok(String id) {
    final def = shellTabById(id);
    if (def == null || id == kMenuTabId) return false;
    return def.anyMenu.isEmpty || allowed(def.anyMenu);
  }

  final out = <String>[];
  void add(String id) {
    if (out.length < max && !out.contains(id) && ok(id)) out.add(id);
  }

  if (custom != null) {
    custom.forEach(add);
    if (out.isNotEmpty) return out;
  }
  for (final r in roles) {
    for (final role in workRoles) {
      if (role.id == r) role.tabs.forEach(add);
    }
  }
  if (out.length < 2) kFallbackTabs.forEach(add);
  return out;
}

/// Per-user (server + user) choice of roles and bottom tabs, stored on device.
@immutable
class ShellTabsConfig {
  const ShellTabsConfig({this.roles = const [], this.tabs});

  final List<String> roles;

  /// `null` = follow the roles' suggestion.
  final List<String>? tabs;

  Map<String, dynamic> toJson() => {'roles': roles, if (tabs != null) 'tabs': tabs};

  String encode() => jsonEncode(toJson());

  static ShellTabsConfig? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      List<String>? list(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : null;
      return ShellTabsConfig(roles: list(j['roles']) ?? const [], tabs: list(j['tabs']));
    } catch (_) {
      return null;
    }
  }

  /// `user.mobile_shell` from `GET /api/me`; null when unset or not usable.
  static ShellTabsConfig? fromServer(Object? raw) {
    if (raw is! Map) return null;
    List<String>? list(Object? v) => v is List ? v.map((e) => e.toString()).toList() : null;
    final roles = list(raw['roles']) ?? const [];
    final tabs = list(raw['tabs']);
    if (roles.isEmpty && (tabs == null || tabs.isEmpty)) return null;
    return ShellTabsConfig(roles: roles, tabs: tabs);
  }

  ShellTabsConfig copyWith({List<String>? roles, List<String>? tabs, bool clearTabs = false}) =>
      ShellTabsConfig(roles: roles ?? this.roles, tabs: clearTabs ? null : (tabs ?? this.tabs));
}

/// "ทีมขาย, ทีม HR" — for Settings.
String roleSummary(List<String> ids) {
  final names = [for (final r in workRoles) if (ids.contains(r.id)) r.label];
  return names.isEmpty ? 'ยังไม่ได้เลือก' : names.join(', ');
}

/// Roles pre-ticked on the role step from the chosen NEXTX package.
List<String> suggestedRolesForPackage(String? code) {
  switch (code) {
    case 'next_s':
      return const ['sales'];
    case 'next_h':
      return const ['hr'];
    case 'next_c':
      return const ['marketing'];
    case 'next_o':
      return const ['online'];
    case 'next_t':
      return const ['general'];
    default:
      return const [];
  }
}
