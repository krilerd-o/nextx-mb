import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Order and visibility of the Home sections, per server + user.
class HomeLayout extends ChangeNotifier {
  HomeLayout._();
  static final HomeLayout instance = HomeLayout._();

  /// Section keys → Thai label (translated by tr()) and a short hint.
  static const Map<String, (String, String)> sections = {
    'today': ('ลงเวลา', 'ลงเวลาเข้า-ออก งานเลยกำหนด นัดถัดไป'),
    'ai': ('สรุปโดย AI', 'สรุปวันนี้แบบสั้นๆ'),
    'work': ('งานวันนี้', 'งาน Workspace ของฉัน (ค่าเริ่มต้นวันนี้)'),
    'pending': ('งานค้าง', 'กิจกรรมค้าง + งาน Workspace ค้าง'),
    'quick': ('ทางลัด', 'ลงเวลา ขอลา แชท ปฏิทิน …'),
    'recent': ('เปิดล่าสุด', 'รายการที่เพิ่งเปิดในเครื่องนี้'),
    'sales': ('ยอดขาย', 'ดีลและใบเสนอราคาของฉัน ตามช่วงเวลา'),
    'cases': ('เคส', 'เคสของฉัน ตามช่วงเวลา'),
    'stats': ('ภาพรวม', 'จำนวนรายการของฉัน + กราฟ 7 วัน'),
    'birthdays': ('วันเกิดลูกค้าวันนี้', 'Lead / Contact / Account ที่เกิดวันนี้และพรุ่งนี้'),
    'upcoming': ('กิจกรรมถัดไป', 'นัดหมายที่กำลังมา'),
  };

  /// Default Home: ลงเวลา · สรุป AI · งานวันนี้ · งานค้าง · ทางลัด · เปิดล่าสุด ·
  /// ยอดขาย · เคส · ภาพรวม, then birthdays and upcoming activities.
  static const List<String> defaultOrder = [
    'today', 'ai', 'work', 'pending', 'quick', 'recent', 'sales', 'cases', 'stats', 'birthdays', 'upcoming',
  ];

  List<String> _order = List.of(defaultOrder);
  Set<String> _hidden = {};
  String? _scope;

  List<String> get order => List.unmodifiable(_order);
  Set<String> get hidden => Set.unmodifiable(_hidden);
  List<String> get visibleOrder => [for (final k in _order) if (!_hidden.contains(k)) k];

  String _key(String scope) => 'nx_home_layout_$scope';

  Future<void> load(String scope) async {
    if (_scope == scope) return;
    _scope = scope;
    _order = List.of(defaultOrder);
    _hidden = {};
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(scope));
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final saved = [for (final k in (j['order'] as List? ?? const [])) '$k'].where(sections.containsKey).toList();
        // New sections added in later versions go where the default puts them.
        for (final k in defaultOrder) {
          if (!saved.contains(k)) saved.insert(defaultOrder.indexOf(k).clamp(0, saved.length), k);
        }
        _order = saved;
        _hidden = {for (final k in (j['hidden'] as List? ?? const [])) '$k'};
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save(String scope, List<String> order, Set<String> hidden) async {
    _scope = scope;
    _order = List.of(order);
    _hidden = Set.of(hidden);
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance())
          .setString(_key(scope), jsonEncode({'order': _order, 'hidden': _hidden.toList()}));
    } catch (_) {}
  }
}
