import 'package:shared_preferences/shared_preferences.dart';

/// Record detail: show only filled fields (default) or all of them.
/// Remembered on the device so the choice sticks across records/menus.
class DetailFieldsPref {
  DetailFieldsPref._();
  static const _key = 'nx_detail_show_all_fields';
  static bool showAll = false;

  static Future<void> load() async {
    try {
      showAll = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    showAll = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, v);
    } catch (_) {}
  }
}
