import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'error_reporting.dart';
import 'i18n.dart';
import 'thai_time.dart';

/// Which field shows in each spot of a list card (per menu, per user).
///
/// ```
///  [top]                        [badge]
///  [title]
///  [subtitle]
///  ───────────────────────────────────
///  📅 [date]                 [amount label]
///  👤 [person]               [amount]
/// ```
class CardLayout {
  const CardLayout({
    this.top,
    this.title,
    this.subtitle,
    this.date,
    this.person,
    this.amount,
    this.badge,
    this.subtitleMode = 'diff',
  });

  final String? top;
  final String? title;
  final String? subtitle;
  final String? date;
  final String? person;
  final String? amount;
  final String? badge;

  /// `diff` = only when it differs from the title, `always`, `never`.
  final String subtitleMode;

  static const slots = ['top', 'title', 'subtitle', 'date', 'person', 'amount', 'badge'];

  String? slot(String s) => switch (s) {
        'top' => top,
        'title' => title,
        'subtitle' => subtitle,
        'date' => date,
        'person' => person,
        'amount' => amount,
        'badge' => badge,
        _ => null,
      };

  CardLayout withSlot(String s, String? field) => CardLayout(
        top: s == 'top' ? field : top,
        title: s == 'title' ? field : title,
        subtitle: s == 'subtitle' ? field : subtitle,
        date: s == 'date' ? field : date,
        person: s == 'person' ? field : person,
        amount: s == 'amount' ? field : amount,
        badge: s == 'badge' ? field : badge,
        subtitleMode: subtitleMode,
      );

  CardLayout withSubtitleMode(String m) => CardLayout(
        top: top,
        title: title,
        subtitle: subtitle,
        date: date,
        person: person,
        amount: amount,
        badge: badge,
        subtitleMode: m,
      );

  /// Drops slots pointing at fields a card must not show (heavy or hidden).
  CardLayout sanitized(CardFieldContext ctx) {
    var l = this;
    for (final s in slots) {
      final f = l.slot(s);
      if (f != null && !ctx.isCardSafe(f)) l = l.withSlot(s, null);
    }
    return l;
  }

  Map<String, dynamic> toJson() => {
        for (final s in slots) s: slot(s) ?? '',
        'subtitle_mode': subtitleMode,
      };

  factory CardLayout.fromJson(Map<String, dynamic> j) {
    String? v(String k) {
      final x = j[k]?.toString() ?? '';
      return x.isEmpty ? null : x;
    }

    return CardLayout(
      top: v('top'),
      title: v('title'),
      subtitle: v('subtitle'),
      date: v('date'),
      person: v('person'),
      amount: v('amount'),
      badge: v('badge'),
      subtitleMode: const ['diff', 'always', 'never'].contains(j['subtitle_mode']) ? j['subtitle_mode'] as String : 'diff',
    );
  }

  /// Same starting layout for everyone, picked from the module's fields.
  static CardLayout defaults(String module, List<Map<String, dynamic>> fields, {String? statusKey}) {
    final names = [for (final f in fields) f['name']?.toString() ?? ''];
    final types = {for (final f in fields) f['name']?.toString() ?? '': '${f['type'] ?? ''}'};
    String? first(Iterable<String> c) => c.where(names.contains).firstOrNull;

    final top = first(['${module}_no', '${module}_code', 'quotation_no', 'deal_no', 'case_no', 'job_no', 'lead_no']) ??
        names.where((n) => types[n] == 'Counter').firstOrNull;
    // Documents (quotation/order) lead with the customer; records with their own name.
    final title = first([
      if (module == 'quotation' || module == 'order' || module == 'invoice') ...['customer_name', 'account_name'],
      '${module}_name', 'lead_name', 'deal_name', 'account_name', 'contact_name', 'case_name',
      'subject', 'title', 'product_name', 'service_name', 'activity_name', 'customer_name', 'name',
    ]);
    final subtitle = first([
      'title_th', '${module}_title', 'quotation_name', 'deal_name', 'company_name', 'contact_name', 'email_1st', 'subject',
    ].where((n) => n != title));
    // A document date when the module has one; otherwise last modified (always set).
    final date = first(['quote_date', '${module}_date', 'close_date', 'expected_close_date', 'date_start', 'due_date']) ??
        'modifiedtime';
    // The owner is always filled in; assign_to often isn't.
    const person = 'smownerid';
    final amount = first(['grand_total', 'amount', 'total_amount', 'expected_revenue', 'price']);
    return CardLayout(
      top: top,
      title: title,
      subtitle: subtitle,
      date: date,
      person: person,
      amount: amount,
      badge: statusKey,
    );
  }
}

/// Per-user card layouts (local to the device, keyed by server + user).
class CardLayoutStore {
  static String _key(String module, String scope) => 'nx_card_${module}_$scope';

  static Future<CardLayout?> load(String module, String scope) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(module, scope));
      if (raw == null) return null;
      return CardLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, s) {
      ErrorReporting.report(e, s);
      return null;
    }
  }

  static Future<void> save(String module, String scope, CardLayout layout) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key(module, scope), jsonEncode(layout.toJson()));
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
  }

  static Future<void> reset(String module, String scope) async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key(module, scope));
    } catch (_) {}
  }
}

/// Field metadata + lookups needed to turn raw row values into card text.
class CardFieldContext {
  CardFieldContext({
    required List<Map<String, dynamic>> fields,
    this.picklists = const {},
    this.users = const {},
  }) : fields = {
          // Same rule as the record view: hidden / disabled fields never show.
          for (final f in fields)
            if (f['access'] != 'hidden' && '${f['presence'] ?? 1}' != '0') f['name']?.toString() ?? '': f,
        };

  final Map<String, Map<String, dynamic>> fields;
  final Map<String, List<Map<String, dynamic>>> picklists;

  /// user id → display name.
  final Map<String, String> users;

  static const metaLabels = {
    'smownerid': ('เจ้าของ', 'Owner'),
    'smcreatorid': ('สร้างโดย', 'Created by'),
    'modifiedby': ('แก้ไขโดย', 'Modified by'),
    'createdtime': ('วันที่สร้าง', 'Created'),
    'modifiedtime': ('วันที่แก้ไข', 'Modified'),
  };

  String label(String name) {
    final f = fields[name];
    if (f != null) {
      final v = L10n.isEn ? (f['label_en'] ?? f['label']) : (f['label_th'] ?? f['label']);
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    final m = metaLabels[name];
    if (m != null) return L10n.isEn ? m.$2 : m.$1;
    return name;
  }

  String type(String name) {
    if (name == 'createdtime' || name == 'modifiedtime') return 'DateTime';
    if (name == 'smownerid' || name == 'smcreatorid' || name == 'modifiedby') return 'PicklistUser';
    return '${fields[name]?['type'] ?? ''}';
  }

  // NEXTX field types (case-sensitive: `Text` is short, Postgres `text` is long).
  static const _heavyTypes = {
    'LongText', 'RichText', 'Html', 'Json', 'Image', 'Video', 'File', 'Files', 'Media', 'Post', 'Drawing',
    'Signature', 'Canvas', 'AddressMap', 'Address', 'LatLong', 'XY', 'App', 'Tag',
    'text', 'json', 'jsonb', 'bytea', '19', '21', '69',
  };
  static final _heavyNames = RegExp(
      r'description|remark|note|detail|comment|body|content|html|json|signature|attendees|photos|images|files|'
      r'score_factors|health_flags|_log$|address_line|locationmap|image_url|avatar|attachment|recurrence|history');

  /// Fields a list card may show: short values only. Long text, rich text,
  /// JSON, files/images, maps and addresses would make every row heavy.
  bool isCardSafe(String name) {
    if (metaLabels.containsKey(name)) return true;
    final f = fields[name];
    if (f == null) return false;
    if (_heavyTypes.contains(type(name))) return false;
    if (_heavyNames.hasMatch(name.toLowerCase())) return false;
    return true;
  }

  bool isUser(String name) => type(name) == 'PicklistUser' || type(name) == '53';
  bool isDate(String name) => const ['Date', 'DateTime', '5', '6', '23', '70'].contains(type(name));
  bool isNumber(String name) => const ['Number', 'Currency', 'Decimal', 'Integer', '7', '71', '72'].contains(type(name));

  /// Picklist option map for a stored value (for its label and colour).
  Map<String, dynamic>? option(String name, String value) =>
      (picklists[name] ?? const []).where((o) => '${o['value']}' == value || '${o['value_th']}' == value).firstOrNull;

  /// Text for [name] on [row], formatted by the field's type.
  String text(Map<String, dynamic> row, String? name, {bool money = false}) {
    if (name == null || name.isEmpty) return '';
    // A slot saved earlier for a field the user may no longer see (or a heavy
    // field) stays empty.
    if (!isCardSafe(name)) return '';
    final raw = row[name];
    if (raw == null) return '';
    var s = raw is List ? raw.join(', ') : '$raw'.trim();
    if (s.isEmpty || s == 'null') return '';
    if (isUser(name)) {
      return s.split(',').map((id) => users[id.trim()] ?? row['${name}_name']?.toString() ?? id.trim()).join(', ');
    }
    if (isDate(name)) {
      final d = parseThai(s);
      if (d == null) return s;
      final dd = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${uiYear(d.year)}';
      return type(name) == 'DateTime' && name != 'createdtime' && name != 'modifiedtime'
          ? '$dd ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
          : dd;
    }
    final opt = option(name, s);
    if (opt != null) {
      return '${(L10n.isEn ? opt['value_en'] : opt['value_th']) ?? opt['value'] ?? s}';
    }
    if (money || isNumber(name)) {
      final n = num.tryParse(s.replaceAll(',', ''));
      if (n != null) return money ? '฿ ${formatMoney(n)}' : formatMoney(n, decimals: n % 1 == 0 ? 0 : 2);
    }
    // Relation fields: prefer the joined display name when the row has one.
    final joined = row['${name.replaceAll(RegExp(r'_id$'), '')}_name'];
    if (joined != null && '$joined'.isNotEmpty && name.endsWith('_id')) return '$joined';
    return s;
  }
}

/// `1234567.5` → `1,234,567.50`.
String formatMoney(num n, {int decimals = 2}) {
  final neg = n < 0;
  final fixed = n.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final buf = StringBuffer();
  final int0 = parts[0];
  for (var i = 0; i < int0.length; i++) {
    if (i > 0 && (int0.length - i) % 3 == 0) buf.write(',');
    buf.write(int0[i]);
  }
  return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}
