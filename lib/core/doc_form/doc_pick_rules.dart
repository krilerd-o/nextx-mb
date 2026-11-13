import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../card_layout.dart' show formatMoney;
import '../entity_display.dart';
import 'quotation_math.dart';

/// Search / display rules of the quotation pickers (customer, contact,
/// product / service, document template). Pure, so the tests can pin them.

String _s(Object? v) => v == null ? '' : '$v'.trim();

// ─────────────────────────────────────────────────────────── search columns

/// Columns `GET /api/entity/:module?q=` must search (`search_cols`).
///
/// Older servers' built-in floor for product / service was the legacy vtiger
/// set (`productname`, `name`, `product_no`) — none of the name columns exist
/// in `aicrm_product`, so only the running number was searched and "kas"
/// never found "Kaspersky …". The server floor now names the real columns;
/// sending them anyway keeps older servers working (unknown names are ignored).
const Map<String, List<String>> kPickerSearchCols = {
  'product': ['product_name_th', 'product_name_en', 'product_code', 'product_no'],
  'service': ['service_name_th', 'service_name_en', 'service_code', 'service_no'],
  'account': ['account_name', 'account_no', 'account_code', 'account_taxid', 'mobile_1st', 'email_1st', 'phone'],
  'contact': ['contact_firstname', 'contact_lastname', 'contact_no', 'mobile_1st', 'email_1st', 'account_name_1st'],
  'lead': ['lead_firstname', 'lead_lastname', 'lead_name', 'company_name', 'lead_no', 'mobile_1st', 'email_1st'],
};

/// Sort of the picker lists (the web picker's default: by name).
const Map<String, String> kPickerSort = {
  'product': 'product_name_th',
  'service': 'service_name_th',
  'account': 'account_name',
  'contact': 'contact_firstname',
  'lead': 'lead_firstname',
};

/// Query params for one picker page: `search_cols` with the text, the sort,
/// `with_total` for paging, equality filters (`filter[col]`) and, for the
/// quotation's product / service picker, `sellable=1` (ready-for-sale only —
/// see [isSellableCatalogStatus]).
Map<String, String> pickerQueryParams(String module, {String q = '', Map<String, String> filters = const {}, bool sellableOnly = false}) => {
      if (q.trim().isNotEmpty) 'search_cols': (kPickerSearchCols[module] ?? const []).join(','),
      if (kPickerSort[module] != null) 'sort': kPickerSort[module]!,
      'order': 'asc',
      'with_total': '1',
      if (sellableOnly && kCatalogStatusField.containsKey(module)) 'sellable': '1',
      for (final e in filters.entries)
        if (e.value.trim().isNotEmpty) 'filter[${e.key}]': e.value.trim(),
    };

// ─────────────────────────────────────────────────────────── sellable

/// Status column of a catalog module.
const Map<String, String> kCatalogStatusField = {'product': 'product_status', 'service': 'service_status'};

/// Ready-for-sale statuses (trimmed, lower-case) — the server's
/// `SELLABLE_CATALOG_STATUSES` (backend/src/constants/catalogSellable.js).
/// The picklist is Active (ใช้งาน) · Inactive (ไม่ใช้งาน) · Draft (ฉบับร่าง) ·
/// Discontinued (เลิกผลิต); only Active sells.
const Set<String> kSellableCatalogStatuses = {'active', 'ใช้งาน', 'พร้อมขาย', 'published', 'available'};

/// A product / service with this status can go on a quotation: Active, or no
/// status at all (old / imported rows — the picklist default is Active).
/// Draft / Inactive / Discontinued cannot. Stock does not matter.
bool isSellableCatalogStatus(Object? status) {
  final s = _s(status).toLowerCase();
  return s.isEmpty || kSellableCatalogStatuses.contains(s);
}

bool isSellableCatalogRow(String module, Map<String, dynamic> row) {
  final f = kCatalogStatusField[module];
  return f == null || isSellableCatalogStatus(row[f]);
}

/// Category column of a catalog module.
String catalogCategoryField(String module) => module == 'service' ? 'service_category' : 'product_category';

// ─────────────────────────────────────────────────────────── catalog rows

/// What a product / service row shows in the quotation picker (no stock:
/// a quotation can offer what is not on hand).
class CatalogItemView {
  const CatalogItemView({required this.name, required this.code, required this.unit, required this.price, this.image, this.category = ''});
  final String name;
  final String code;
  final String unit;
  final double price;
  final String? image;
  final String category;

  String get priceText => '฿${formatMoney(price)}${unit.isEmpty ? '' : ' / $unit'}';
}

CatalogItemView catalogItemView(String module, Map<String, dynamic> r, {bool th = true}) {
  final p = module == 'service' ? 'service' : 'product';
  final nameTh = _s(r['${p}_name_th']), nameEn = _s(r['${p}_name_en']);
  var name = th ? (nameTh.isNotEmpty ? nameTh : nameEn) : (nameEn.isNotEmpty ? nameEn : nameTh);
  if (name.isEmpty) name = _s(r['${p}_name']).isNotEmpty ? _s(r['${p}_name']) : (_s(r['name']).isNotEmpty ? _s(r['name']) : '#${r['id']}');
  final code = _s(r['${p}_code']).isNotEmpty ? _s(r['${p}_code']) : _s(r['${p}_no']);
  final sell = r['${p}_selling_price'];
  final price = qNum(sell == null || '$sell'.trim().isEmpty ? r['${p}_initial_price'] : sell);
  final img = _s(r['picture']).isNotEmpty ? _s(r['picture']) : _s(r['image_url']);
  return CatalogItemView(
    name: name,
    code: code,
    unit: _s(r['${p}_unit']),
    price: price,
    image: img.isEmpty ? null : img,
    category: _s(r[catalogCategoryField(p)]),
  );
}

// ─────────────────────────────────────────────────────────── customer rows

const Map<String, String> kCustomerKindLabel = {'account': 'บัญชีลูกค้า', 'contact': 'ผู้ติดต่อ', 'lead': 'ผู้มุ่งหวัง'};

/// Second line of a customer row: company / phone / e-mail / tax id.
String customerRowSubtitle(String module, Map<String, dynamic> r) {
  final parts = <String>[];
  void add(Object? v) {
    final t = _s(v);
    if (t.isNotEmpty && t != 'null' && !parts.contains(t)) parts.add(t);
  }

  switch (module) {
    case 'account':
      add(r['account_no'] ?? r['account_code']);
    case 'contact':
      add(r['account_name_1st'] ?? r['account_name']);
    case 'lead':
      add(r['company_name']);
  }
  add(r['mobile_1st'] ?? r['phone'] ?? r['mobile']);
  add(r['email_1st'] ?? r['email1'] ?? r['email']);
  if (module == 'account' && _s(r['account_taxid']).isNotEmpty) add('เลขภาษี ${r['account_taxid']}');
  return parts.join(' · ');
}

String customerRowTitle(String module, Map<String, dynamic> r) => entityTitle(r, module: module);

// ─────────────────────────────────────────────────────── document template

/// Web `LAYOUT_LABELS` (QuotationFormSidePanel.jsx).
String quotationLayoutLabel(String key, {bool th = true}) => switch (key) {
      'template2' => th ? 'Template-2 · ฟอร์มตาราง' : 'Template-2 · Table form',
      _ => th ? 'Template-1 · มาตรฐาน' : 'Template-1 · Standard',
    };

bool isDefaultQuotationTemplate(Map<String, dynamic> t) {
  final j = t['layout_json'];
  return j is Map && (j['is_default'] == true || '${j['is_default']}' == '1');
}

/// A template's name as the web shows it (`name (ค่าเริ่มต้น)`), never a bare
/// code: a template named / coded "default" reads "ค่าเริ่มต้น".
String quotationTemplateLabel(Map<String, dynamic> t, {bool th = true}) {
  final defWord = th ? 'ค่าเริ่มต้น' : 'Default';
  var name = _s(t['name']);
  final code = _s(t['code']);
  bool isDefaultWord(String s) => RegExp(r'^(default|ค่าเริ่มต้น)$', caseSensitive: false).hasMatch(s);
  if (name.isEmpty || isDefaultWord(name)) name = code.isNotEmpty && !isDefaultWord(code) ? code : defWord;
  if (name == defWord) return name;
  return isDefaultQuotationTemplate(t) ? '$name ($defWord)' : name;
}

/// Label of "no template" (`template_id` empty): the business letterhead.
const kQuotationNoTemplateLabel = 'หัวกระดาษเริ่มต้นของธุรกิจ';

/// User-facing label without the storage hint ("เงื่อนไข (HTML)" → "เงื่อนไข").
String cleanFieldLabel(String label) => label.replaceAll(RegExp(r'\s*\(\s*html\s*\)\s*$', caseSensitive: false), '').trim();

// ─────────────────────────────────────────────────────────── recent picks

/// Recently picked customers per business (newest first, a few kept).
class DocRecentPicks {
  DocRecentPicks._();
  static const max = 8;

  static String key(String kind, String? businessId) => 'nx.docform.recent.$kind.${businessId ?? '-'}';

  static Future<List<Map<String, dynamic>>> read(String kind, String? businessId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key(kind, businessId));
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw);
      return list is List ? [for (final x in list) if (x is Map) Map<String, dynamic>.from(x)] : const [];
    } catch (_) {
      return const [];
    }
  }

  /// [entry]: `{module, id, title, subtitle}`.
  static Future<void> add(String kind, String? businessId, Map<String, dynamic> entry) async {
    try {
      final p = await SharedPreferences.getInstance();
      final now = await read(kind, businessId);
      final next = [
        entry,
        for (final e in now)
          if (!(_s(e['module']) == _s(entry['module']) && _s(e['id']) == _s(entry['id']))) e,
      ].take(max).toList();
      await p.setString(key(kind, businessId), jsonEncode(next));
    } catch (_) {}
  }
}
