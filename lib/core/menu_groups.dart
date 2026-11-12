import 'package:flutter/material.dart';

import '../widgets/nx_icons.dart';
import 'isaac_menu.dart';
import 'menu_access.dart';
import 'navigation/app_routes.dart';
import 'session_state.dart';

/// The app's "เมนู" page grouped like the web's left icon rail
/// (`frontend/src/constants/navRailConfig.js` → `NAV_RAILS`): same groups,
/// same order, same section titles. Only menus that have an app screen are
/// listed; the user's NEXTX menu permissions decide what shows.
class MenuItemDef {
  const MenuItemDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.menuKeys,
    this.extra,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;

  /// Visible when the user has any of these web menu keys.
  final List<String> menuKeys;

  /// Extra rule on top of [menuKeys] (e.g. store stock needs an admin).
  final bool Function(SessionState s)? extra;

  bool visibleFor(SessionState s) => extra != null ? extra!(s) : MenuAccess.any(s, menuKeys);
}

class MenuSectionDef {
  const MenuSectionDef({this.title, required this.items});
  final String? title;
  final List<MenuItemDef> items;
}

class MenuGroupDef {
  const MenuGroupDef({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.sections = const [],
    this.isaac = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final List<MenuSectionDef> sections;

  /// Items come from [IsaacAccess] (plugin + AI settings), like the web.
  final bool isaac;
}

/// A group after permission filtering; sections without items are dropped.
class VisibleMenuGroup {
  const VisibleMenuGroup(this.def, this.sections);
  final MenuGroupDef def;
  final List<MenuSectionDef> sections;

  List<MenuItemDef> get items => [for (final s in sections) ...s.items];
}

bool _store(SessionState s) =>
    MenuAccess.allow(s, MenuAccess.storeOrders) || (MenuAccess.allow(s, MenuAccess.storeStock) && s.isBusinessAdmin);

const kMenuGroups = <MenuGroupDef>[
  MenuGroupDef(
    id: 'work',
    title: 'งานของฉัน',
    icon: NxI.clipboardText,
    color: Color(0xFF6366F1),
    sections: [
      MenuSectionDef(items: [
        MenuItemDef(id: 'workspace', title: 'Workspace', subtitle: 'บอร์ดและงานของทีม', icon: NxI.kanban, route: AppRoutes.workspaceHome, menuKeys: [MenuAccess.workspace]),
        MenuItemDef(
          id: 'approvals',
          title: 'รออนุมัติ',
          subtitle: 'ใบเสนอราคา การลา คำขอเข้าร่วม',
          icon: NxI.checkCircle,
          route: AppRoutes.approvals,
          menuKeys: [MenuAccess.quotation, MenuAccess.leaveManagement, MenuAccess.pendingApprovals],
        ),
      ]),
      MenuSectionDef(title: 'กิจกรรม', items: [
        MenuItemDef(
          id: 'calendar',
          title: 'ปฏิทิน',
          subtitle: 'นัดหมาย งานค้าง และเช็คอิน',
          icon: NxI.calendarBlank,
          route: AppRoutes.calendar,
          menuKeys: [MenuAccess.calendar, MenuAccess.incoming, MenuAccess.pending],
        ),
      ]),
    ],
  ),
  MenuGroupDef(
    id: 'customers',
    title: 'ลูกค้า',
    icon: NxI.users,
    color: Color(0xFFF97316),
    sections: [
      MenuSectionDef(items: [
        MenuItemDef(id: 'lead', title: 'ผู้มุ่งหวัง', subtitle: 'ลูกค้าที่กำลังติดตาม', icon: NxI.flag, route: '/crm/lead', menuKeys: [MenuAccess.lead]),
        MenuItemDef(id: 'account', title: 'บัญชีลูกค้า', subtitle: 'บริษัทและองค์กร', icon: NxI.buildings, route: '/crm/account', menuKeys: [MenuAccess.account]),
        MenuItemDef(id: 'contact', title: 'ผู้ติดต่อ', subtitle: 'รายชื่อบุคคล', icon: NxI.addressBook, route: '/crm/contact', menuKeys: [MenuAccess.contact]),
      ]),
    ],
  ),
  MenuGroupDef(
    id: 'sales',
    title: 'งานขาย',
    icon: NxI.handshake,
    color: Color(0xFF10B981),
    sections: [
      MenuSectionDef(items: [
        MenuItemDef(id: 'deal', title: 'ดีล', subtitle: 'โอกาสการขาย', icon: NxI.handshake, route: '/crm/deal', menuKeys: [MenuAccess.deal]),
        MenuItemDef(id: 'quotation', title: 'ใบเสนอราคา', subtitle: 'เสนอราคาและติดตาม', icon: NxI.receipt, route: '/crm/quotation', menuKeys: [MenuAccess.quotation]),
      ]),
    ],
  ),
  MenuGroupDef(
    id: 'service',
    title: 'งานบริการ',
    icon: NxI.briefcase,
    color: Color(0xFFEF4444),
    sections: [
      MenuSectionDef(title: 'งานบริการ', items: [
        MenuItemDef(id: 'case', title: 'เคส', subtitle: 'แจ้งปัญหาและบริการลูกค้า', icon: NxI.headset, route: '/crm/case', menuKeys: [MenuAccess.caseKey]),
        MenuItemDef(id: 'job', title: 'ใบสั่งงาน', subtitle: 'ใบสั่งงานทั้งหมดของทีม — สร้าง มอบหมาย ติดตาม', icon: NxI.wrench, route: '/fsm/job', menuKeys: [MenuAccess.job]),
        MenuItemDef(id: 'my-jobs', title: 'งานช่างของฉัน', subtitle: 'งานที่มอบหมายให้ฉัน — วันนี้ เดินทาง เช็คอิน ปิดงาน', icon: NxI.hammer, route: AppRoutes.jobs, menuKeys: [MenuAccess.job]),
        MenuItemDef(id: 'inspection', title: 'ใบตรวจรับ', subtitle: 'ตรวจรับงาน', icon: NxI.clipboard, route: '/fsm/inspection', menuKeys: [MenuAccess.inspection]),
      ]),
      MenuSectionDef(title: 'สัญญา', items: [
        MenuItemDef(id: 'service-contract', title: 'สัญญาบริการ', subtitle: 'สัญญาและรอบบริการ', icon: NxI.scroll, route: '/fsm/service_contract', menuKeys: [MenuAccess.serviceContract]),
      ]),
    ],
  ),
  MenuGroupDef(
    id: 'comms',
    title: 'สื่อสาร',
    icon: NxI.chatCircle,
    color: Color(0xFF8B5CF6),
    sections: [
      MenuSectionDef(title: 'คุยกับลูกค้า', items: [
        MenuItemDef(id: 'mail', title: 'เมล', subtitle: 'อ่าน เขียน และตอบกลับ', icon: NxI.envelope, route: AppRoutes.mail, menuKeys: [MenuAccess.mailbox]),
        MenuItemDef(id: 'call-log', title: 'บันทึกการโทร', subtitle: 'ผลการโทรและงานที่เกี่ยวข้อง', icon: NxI.phoneCall, route: AppRoutes.callLog, menuKeys: [MenuAccess.callLog]),
      ]),
      MenuSectionDef(title: 'คุยในทีม', items: [
        MenuItemDef(id: 'chat', title: 'แชท', subtitle: 'แชททีมแบบเรียลไทม์', icon: NxI.chatCircle, route: AppRoutes.chatHome, menuKeys: [MenuAccess.chat]),
        MenuItemDef(id: 'comm-ai', title: 'ประวัติ AI การสนทนา', subtitle: 'บทสนทนา เสียง และสรุปจากการโทรและแชท', icon: NxI.sparkle, route: AppRoutes.commAi, menuKeys: [MenuAccess.commAi]),
      ]),
    ],
  ),
  MenuGroupDef(id: 'ai', title: 'ISAAC AI', icon: NxI.sparkle, color: Color(0xFFEC4899), isaac: true),
  MenuGroupDef(
    id: 'apps',
    title: 'แอปอื่น',
    icon: NxI.squaresFour,
    color: Color(0xFF0EA5E9),
    sections: [
      MenuSectionDef(title: 'HR', items: [
        MenuItemDef(
          id: 'hr',
          title: 'หน้า HR',
          subtitle: 'ภาพรวมลงเวลาและการลา',
          icon: NxI.briefcase,
          route: AppRoutes.hrHome,
          menuKeys: [MenuAccess.attendance, MenuAccess.leave, MenuAccess.leaveManagement],
        ),
        MenuItemDef(id: 'attendance', title: 'ลงเวลา', subtitle: 'เข้างาน / ออกงาน', icon: NxI.clock, route: AppRoutes.attendance, menuKeys: [MenuAccess.attendance]),
        MenuItemDef(id: 'leave', title: 'การลา', subtitle: 'ขอลาและดูสถานะ', icon: NxI.calendarCheck, route: AppRoutes.leaveList, menuKeys: [MenuAccess.leave, MenuAccess.leaveManagement]),
        MenuItemDef(
          id: 'attendance-report',
          title: 'รายงานลงเวลา',
          subtitle: 'สรุปเวลาเข้าออกของทีม',
          icon: NxI.chartBar,
          route: AppRoutes.attendanceReport,
          menuKeys: [MenuAccess.attendanceReport, MenuAccess.hrDashboard],
        ),
      ]),
      MenuSectionDef(title: 'คลังข้อมูล', items: [
        MenuItemDef(id: 'product', title: 'สินค้า', subtitle: 'รายการสินค้า', icon: NxI.package, route: '/crm/product', menuKeys: [MenuAccess.product]),
        MenuItemDef(id: 'service-item', title: 'บริการ', subtitle: 'รายการบริการ', icon: NxI.wrench, route: '/crm/service', menuKeys: [MenuAccess.service]),
        MenuItemDef(id: 'asset', title: 'สินทรัพย์', subtitle: 'เครื่องและอุปกรณ์ของลูกค้า', icon: NxI.hardDrives, route: '/fsm/asset', menuKeys: [MenuAccess.asset]),
        MenuItemDef(id: 'service-location', title: 'พื้นที่บริการ', subtitle: 'สถานที่ให้บริการ', icon: NxI.mapPin, route: '/fsm/service_location', menuKeys: [MenuAccess.serviceLocation]),
        MenuItemDef(id: 'skill', title: 'ทักษะ', subtitle: 'ทักษะช่าง', icon: NxI.medal, route: '/fsm/skill', menuKeys: [MenuAccess.skill]),
        MenuItemDef(id: 'files', title: 'ไฟล์', subtitle: 'กล้องและอัปโหลด', icon: NxI.folder, route: AppRoutes.files, menuKeys: [MenuAccess.files]),
      ]),
      MenuSectionDef(title: 'ร้านค้า', items: [
        MenuItemDef(
          id: 'store',
          title: 'ร้านค้า',
          subtitle: 'ออเดอร์และสต็อก',
          icon: NxI.package,
          route: AppRoutes.commerce,
          menuKeys: [MenuAccess.storeOrders, MenuAccess.storeStock],
          extra: _store,
        ),
      ]),
    ],
  ),
];

IconData isaacMenuIcon(String key) => switch (key) {
      'ai-assistant' => NxI.sparkle,
      'isaac-notebook' => NxI.bookOpen,
      'ai-minute-auto' => NxI.microphone,
      'isaac-ai-agent' => NxI.robot,
      _ => NxI.eye,
    };

/// Groups the user can open, in the web's order; empty groups are left out.
List<VisibleMenuGroup> visibleMenuGroups(SessionState s, {IsaacAccess? isaac}) {
  final out = <VisibleMenuGroup>[];
  for (final g in kMenuGroups) {
    if (g.isaac) {
      final items = isaac?.visibleItems(s) ?? const <IsaacMenuItem>[];
      if (items.isEmpty) continue;
      out.add(VisibleMenuGroup(g, [
        MenuSectionDef(items: [
          for (final it in items)
            MenuItemDef(id: it.key, title: it.label, subtitle: it.subtitle, icon: isaacMenuIcon(it.key), route: it.route, menuKeys: [it.key]),
        ]),
      ]));
      continue;
    }
    final sections = <MenuSectionDef>[
      for (final sec in g.sections)
        if (sec.items.where((i) => i.visibleFor(s)).isNotEmpty)
          MenuSectionDef(title: sec.title, items: [for (final i in sec.items) if (i.visibleFor(s)) i]),
    ];
    if (sections.isNotEmpty) out.add(VisibleMenuGroup(g, sections));
  }
  return out;
}
