import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'menu_groups.dart';

/// How the "เมนู" page shows its groups.
enum MenuHubView {
  /// Group cards in a grid.
  groups,

  /// Every menu as rows, grouped in rounded sections (Android Settings style). Default.
  list,
}

/// Per-user view and per-user+business group order of the "เมนู" page.
///
/// [scope] for the view is `AppConfig.prefsScope` (server + user); the order
/// uses `AppConfig.businessScope` (server + user + business), like the Home layout.
class MenuHubPrefs {
  MenuHubPrefs._();

  static String viewKey(String scope) => 'nx_menu_view_$scope';
  static String orderKey(String businessScope) => 'nx_menu_order_v1_$businessScope';

  /// Preferences opened at startup ([attach]): the page reads its view and
  /// order before its first frame (no list → grid / order flash on cold start).
  static SharedPreferences? _prefs;
  static void attach(SharedPreferences prefs) => _prefs = prefs;

  /// The saved view, without waiting; null until [attach] ran.
  static MenuHubView? peekView(String scope) {
    final p = _prefs;
    if (p == null) return null;
    return p.getString(viewKey(scope)) == 'groups' ? MenuHubView.groups : MenuHubView.list;
  }

  /// The saved group order, without waiting; null until [attach] ran.
  static List<String>? peekOrder(String businessScope) {
    final p = _prefs;
    if (p == null) return null;
    try {
      final raw = p.getString(orderKey(businessScope));
      if (raw == null) return defaultMenuOrder;
      final j = jsonDecode(raw);
      return normalizeMenuOrder([for (final e in (j is List ? j : const [])) '$e']);
    } catch (_) {
      return defaultMenuOrder;
    }
  }

  static Future<MenuHubView> loadView(String scope) async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(viewKey(scope));
      return v == 'groups' ? MenuHubView.groups : MenuHubView.list;
    } catch (_) {
      return MenuHubView.list;
    }
  }

  static Future<void> saveView(String scope, MenuHubView view) async {
    try {
      await (await SharedPreferences.getInstance()).setString(viewKey(scope), view.name);
    } catch (_) {}
  }

  /// Saved full group order (all known group ids), or the default one.
  static Future<List<String>> loadOrder(String businessScope) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(orderKey(businessScope));
      if (raw == null) return defaultMenuOrder;
      final j = jsonDecode(raw);
      return normalizeMenuOrder([for (final e in (j is List ? j : const [])) '$e']);
    } catch (_) {
      return defaultMenuOrder;
    }
  }

  static Future<void> saveOrder(String businessScope, List<String> order) async {
    try {
      final p = await SharedPreferences.getInstance();
      final full = normalizeMenuOrder(order);
      if (_same(full, defaultMenuOrder)) {
        await p.remove(orderKey(businessScope));
      } else {
        await p.setString(orderKey(businessScope), jsonEncode(full));
      }
    } catch (_) {}
  }

  static Future<void> resetOrder(String businessScope) async {
    try {
      await (await SharedPreferences.getInstance()).remove(orderKey(businessScope));
    } catch (_) {}
  }
}

/// The web's group order (ids of [kMenuGroups]).
List<String> get defaultMenuOrder => [for (final g in kMenuGroups) g.id];

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool isDefaultMenuOrder(List<String> order) => _same(normalizeMenuOrder(order), defaultMenuOrder);

/// Known ids of [saved] in their saved order; groups added later are put
/// where the default order has them.
List<String> normalizeMenuOrder(List<String>? saved) {
  final known = defaultMenuOrder;
  final out = <String>[
    for (final id in saved ?? const <String>[])
      if (known.contains(id)) id,
  ];
  // Drop duplicates, keep the first.
  final seen = <String>{};
  out.retainWhere(seen.add);
  for (final (i, id) in known.indexed) {
    if (!out.contains(id)) out.insert(i.clamp(0, out.length), id);
  }
  return out;
}

/// [groups] (already permission-filtered) sorted by [order].
List<VisibleMenuGroup> orderMenuGroups(List<VisibleMenuGroup> groups, List<String> order) {
  final full = normalizeMenuOrder(order);
  final out = [...groups];
  out.sort((a, b) => full.indexOf(a.def.id).compareTo(full.indexOf(b.def.id)));
  return out;
}

/// New full order after the user rearranged the groups they can see
/// ([visible], in their new order): hidden groups keep their slots.
List<String> applyVisibleMenuOrder(List<String> order, List<String> visible) {
  final full = normalizeMenuOrder(order);
  final slots = [for (final (i, id) in full.indexed) if (visible.contains(id)) i];
  final next = [...full];
  final moved = [for (final id in visible) if (full.contains(id)) id];
  for (var i = 0; i < slots.length && i < moved.length; i++) {
    next[slots[i]] = moved[i];
  }
  return next;
}
