/// Business / package choice rules, mirroring the web Hub
/// (frontend/src/pages/Hub.jsx).
library;

bool _truthy(dynamic v) => v == true || v == 1 || v?.toString() == '1' || v?.toString() == 'true';

/// Drops cancelled and sandbox businesses (`is_sandbox`, code `-SBX`/`_SBX`).
List<Map<String, dynamic>> visibleBusinesses(List<Map<String, dynamic>> all) {
  return all.where((b) {
    final status = (b['status']?.toString() ?? '').toLowerCase();
    if (status == 'cancelled' || status == 'canceled') return false;
    if (_truthy(b['is_sandbox'])) return false;
    final code = (b['business_code']?.toString() ?? '').toUpperCase();
    if (code.endsWith('-SBX') || code.endsWith('_SBX')) return false;
    return true;
  }).toList();
}

/// Default business: `is_default`, else the first one.
Map<String, dynamic>? defaultBusiness(List<Map<String, dynamic>> list) {
  for (final b in list) {
    if (_truthy(b['is_default'])) return b;
  }
  return list.isEmpty ? null : list.first;
}

/// Enabled packages without the hidden `all_package`.
List<Map<String, dynamic>> visiblePackages(List<Map<String, dynamic>> all) {
  return all.where((p) {
    final enabled = p['enabled'];
    if (enabled != null && !_truthy(enabled)) return false;
    return (p['code']?.toString() ?? '') != 'all_package';
  }).toList();
}

/// Package to enter without asking, or null when the user should choose.
/// Order: last used here → user's default → business default → the only one.
Map<String, dynamic>? autoPackage(
  List<Map<String, dynamic>> packages, {
  String? lastCode,
  String? userDefaultId,
  String? businessDefaultId,
}) {
  Map<String, dynamic>? byCode(String? c) {
    if (c == null || c.isEmpty) return null;
    for (final p in packages) {
      if (p['code']?.toString() == c) return p;
    }
    return null;
  }

  Map<String, dynamic>? byId(String? id) {
    if (id == null || id.isEmpty || id == 'null') return null;
    for (final p in packages) {
      if (p['id']?.toString() == id) return p;
    }
    return null;
  }

  return byCode(lastCode) ?? byId(userDefaultId) ?? byId(businessDefaultId) ?? (packages.length == 1 ? packages.first : null);
}
