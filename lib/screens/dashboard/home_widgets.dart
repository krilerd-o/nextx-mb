import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/home_layout.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/session_state.dart';
import '../../widgets/nx_icons.dart';

/// Gallery groups (order shown in the widget gallery).
const kHomeWidgetGroups = <(String, String)>[
  ('general', 'ทั่วไป'),
  ('work', 'งาน'),
  ('sales', 'ขาย'),
  ('customer', 'ลูกค้า'),
  ('service', 'บริการ'),
  ('hr', 'HR'),
];

/// What the Home page and the gallery know about any widget id.
class HomeWidgetInfo {
  const HomeWidgetInfo({
    required this.id,
    required this.title,
    required this.hint,
    required this.icon,
    required this.group,
    required this.color,
    this.route,
  });

  final String id;
  final String title;
  final String hint;
  final IconData icon;
  final String group;
  final Color color;

  /// Opened when the card is tapped (charts).
  final String? route;

  bool get isChart => HomeLayout.isChart(id);
  bool get resizable => HomeLayout.resizable(id);

  static const _sectionStyle = <String, (IconData, String, Color)>{
    'today': (NxI.sun, 'general', Color(0xFFF59E0B)),
    'ai': (NxI.sparkle, 'general', Color(0xFF8B5CF6)),
    'work': (NxI.kanban, 'work', Color(0xFF3B82F6)),
    'pending': (NxI.warningCircle, 'work', Color(0xFFEF4444)),
    'quick': (NxI.lightning, 'general', Color(0xFF0EA5E9)),
    'recent': (NxI.clockCounterClockwise, 'general', Color(0xFF64748B)),
    'sales': (NxI.trendUp, 'sales', Color(0xFF10B981)),
    'cases': (NxI.briefcase, 'service', Color(0xFFF97316)),
    'stats': (NxI.chartBar, 'general', Color(0xFF6366F1)),
    'birthdays': (NxI.cake, 'customer', Color(0xFFEC4899)),
    'upcoming': (NxI.calendarBlank, 'work', Color(0xFF14B8A6)),
  };

  static const _chartStyle = <String, (IconData, Color, String)>{
    'chart_won': (LucideIcons300.trophy, Color(0xFF10B981), '/crm/deal'),
    'chart_winrate': (LucideIcons300.target, Color(0xFF2A78D6), '/crm/deal'),
    'chart_sales_trend': (LucideIcons300.chartLine, Color(0xFF10B981), '/crm/deal'),
    'chart_pipeline': (NxI.funnel, Color(0xFF6250D6), '/crm/deal'),
    'chart_closing': (NxI.calendarClock, Color(0xFFEB6834), '/crm/deal'),
    'chart_quote': (NxI.receipt, Color(0xFF0EA5E9), '/crm/quotation'),
    'chart_lead_source': (LucideIcons300.chartPie, Color(0xFFE87BA4), '/crm/lead'),
    'chart_lead_conv': (LucideIcons300.gauge, Color(0xFF1BAF7A), '/crm/lead'),
    'chart_case_status': (NxI.headset, Color(0xFFF97316), '/crm/case'),
    'chart_case_sla': (NxI.shieldCheck, Color(0xFF1BAF7A), '/crm/case'),
    'chart_activity': (NxI.calendarCheck, Color(0xFF14B8A6), AppRoutes.calendar),
    'chart_work': (NxI.kanban, Color(0xFF3B82F6), AppRoutes.workspaceHome),
    'chart_leave': (NxI.calendarBlank, Color(0xFF8B5CF6), AppRoutes.leaveList),
  };

  static HomeWidgetInfo of(String id) {
    final meta = HomeLayout.chartMeta(id);
    if (meta != null) {
      final (icon, color, route) = _chartStyle[id] ?? (NxI.chartBar, const Color(0xFF6366F1), null);
      return HomeWidgetInfo(id: id, title: meta.title, hint: meta.hint, icon: icon, group: meta.group, color: color, route: route);
    }
    final (label, hint) = HomeLayout.sections[id] ?? (id, '');
    final (icon, group, color) = _sectionStyle[id] ?? (NxI.squaresFour, 'general', const Color(0xFF64748B));
    return HomeWidgetInfo(id: id, title: label, hint: hint, icon: icon, group: group, color: color);
  }
}

/// Menu keys behind the "ทางลัด" shortcuts (each shortcut has its own gate
/// on Home; the widget is offered when at least one of them is visible).
const kHomeQuickMenuKeys = <String>[
  MenuAccess.attendance,
  MenuAccess.leave,
  MenuAccess.quotation,
  MenuAccess.leaveManagement,
  MenuAccess.pendingApprovals,
  MenuAccess.chat,
  MenuAccess.calendar,
  MenuAccess.incoming,
  MenuAccess.pending,
  MenuAccess.job,
  MenuAccess.mailbox,
  MenuAccess.ai,
];

/// Modules counted by "ภาพรวม" (menu key = module, except case → 'case').
const kHomeStatMenuKeys = <String>[
  MenuAccess.lead,
  MenuAccess.deal,
  MenuAccess.quotation,
  MenuAccess.account,
  MenuAccess.contact,
  MenuAccess.caseKey,
  MenuAccess.job,
];

/// Lead / Contact / Account — the records "วันเกิดลูกค้าวันนี้" reads.
const kHomeBirthdayMenuKeys = <String>[MenuAccess.lead, MenuAccess.contact, MenuAccess.account];

/// Whether this user may see widget [id] — from their menus (GET /api/me/menus
/// = Package ∩ role permissions; superadmin sees everything). Home, the editor
/// and the gallery all use this, so a widget only appears when the user can
/// open the module(s) it is about. Unknown ids are never allowed.
bool homeWidgetAllowed(SessionState s, String id) {
  switch (id) {
    // Charts — same menus as the web dashboards.
    case 'chart_won':
    case 'chart_winrate':
    case 'chart_sales_trend':
    case 'chart_pipeline':
      return MenuAccess.allow(s, MenuAccess.deal);
    case 'chart_closing':
      return MenuAccess.allow(s, MenuAccess.deal) && s.canAccess('sales-dash-pipeline');
    case 'chart_quote':
      return MenuAccess.allow(s, MenuAccess.quotation);
    case 'chart_lead_source':
    case 'chart_lead_conv':
      return MenuAccess.allow(s, MenuAccess.lead);
    case 'chart_case_status':
    case 'chart_case_sla':
      return MenuAccess.allow(s, MenuAccess.caseKey);
    case 'chart_activity':
      return MenuAccess.anyCalendar(s);
    case 'chart_work':
      return MenuAccess.allow(s, MenuAccess.workspace);
    case 'chart_leave':
      return MenuAccess.allow(s, MenuAccess.leave);
    // Classic sections — what each one actually reads.
    case 'today': // clock-in (attendance) · next appointment (calendar) · work counts (workspace)
      return MenuAccess.allow(s, MenuAccess.attendance) || MenuAccess.anyCalendar(s) || MenuAccess.allow(s, MenuAccess.workspace);
    case 'ai':
      return MenuAccess.allow(s, MenuAccess.ai);
    case 'work':
      return MenuAccess.allow(s, MenuAccess.workspace);
    case 'pending': // overdue activities (calendar / pending-work) + overdue Workspace work
      return MenuAccess.any(s, const [MenuAccess.calendar, MenuAccess.pending, MenuAccess.workspace]);
    case 'quick':
      return MenuAccess.any(s, kHomeQuickMenuKeys);
    case 'recent': // device-local; rows are filtered by module inside
      return true;
    case 'sales':
      return MenuAccess.any(s, const [MenuAccess.deal, MenuAccess.quotation]);
    case 'cases':
      return MenuAccess.allow(s, MenuAccess.caseKey);
    case 'stats':
      return MenuAccess.any(s, kHomeStatMenuKeys);
    case 'birthdays':
      return MenuAccess.any(s, kHomeBirthdayMenuKeys);
    case 'upcoming':
      return MenuAccess.anyCalendar(s);
  }
  return false;
}
