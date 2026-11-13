import 'package:dio/dio.dart';

import 'fake_api.dart';

/// A small NEXTX for the R86 quotation form tests / screenshots: the entity
/// list answers `q` the way `routes/entity.js` does — `search_cols` from the
/// client plus the server's own floor (`MODULE_SEARCH_COLUMNS`), only columns
/// the table really has, `ILIKE '%q%'` — and `sellable=1` keeps only
/// ready-for-sale products / services (`constants/catalogSellable.js`).
/// `legacy: true` is an older server: the floor without the name columns
/// (a client relying on it reproduces the "kas finds nothing" bug) and no
/// `sellable` filter.

/// The server's floor (`backend/src/constants/entitySearchColumns.js`).
const Map<String, List<String>> kServerSearchFloor = {
  'lead': ['lead_no', 'lead_firstname', 'lead_lastname', 'lead_name', 'lead_status', 'company_name', 'mobile_1st', 'email_1st'],
  'contact': ['contact_no', 'contact_firstname', 'contact_lastname', 'contact_name', 'contact_status', 'mobile_1st', 'email_1st', 'email1'],
  'account': ['account_no', 'account_code', 'account_name', 'account_status', 'mobile_1st', 'email_1st', 'accountname', 'name', 'contact_name_1st'],
  'product': ['product_name_th', 'product_name_en', 'product_code', 'product_no'],
  'service': ['service_name_th', 'service_name_en', 'service_code', 'service_no'],
};

/// The floor before the fix: vtiger names that `aicrm_product` does not have.
final Map<String, List<String>> kLegacyServerSearchFloor = {
  ...kServerSearchFloor,
  'product': const ['productname', 'name', 'product_no'],
  'service': const ['servicename', 'name', 'service_no'],
};

/// Server `SELLABLE_CATALOG_STATUSES` (empty status = sellable).
const _kServerSellable = {'active', 'ใช้งาน', 'พร้อมขาย', 'published', 'available'};

/// Columns of the tables (aicrm_product … as created by init-db-full-pg.js).
const kTableColumns = {
  'product': [
    'id', 'product_no', 'product_code', 'product_name_th', 'product_name_en', 'product_description_th', 'product_status', 'product_type',
    'product_category', 'product_unit', 'product_initial_price', 'product_discount', 'product_selling_price', 'picture',
  ],
  'service': [
    'id', 'service_no', 'service_code', 'service_name_th', 'service_name_en', 'service_status', 'service_category', 'service_unit',
    'service_initial_price', 'service_selling_price',
  ],
  'account': ['id', 'account_no', 'account_name', 'account_taxid', 'mobile_1st', 'email_1st', 'address_line1', 'address_district', 'address_province', 'smownerid'],
  'contact': ['id', 'contact_no', 'contact_firstname', 'contact_lastname', 'mobile_1st', 'email_1st', 'account_id', 'account_name_1st', 'smownerid'],
  'lead': ['id', 'lead_no', 'lead_firstname', 'lead_lastname', 'company_name', 'mobile_1st', 'email_1st', 'smownerid'],
};

/// Rows the server would match for `GET /api/entity/:module` with [qp].
List<Map<String, dynamic>> serverEntitySearch(String module, List<Map<String, dynamic>> rows, Map<String, dynamic> qp, {bool legacy = false}) {
  final q = '${qp['q'] ?? ''}'.trim().toLowerCase();
  final have = kTableColumns[module] ?? const <String>[];
  final cols = <String>[];
  for (final c in [...?(legacy ? kLegacyServerSearchFloor : kServerSearchFloor)[module], ...'${qp['search_cols'] ?? ''}'.split(',').map((x) => x.trim())]) {
    if (c.isNotEmpty && have.contains(c) && !cols.contains(c)) cols.add(c);
  }
  var out = [
    for (final r in rows)
      if (q.isEmpty || cols.any((c) => '${r[c] ?? ''}'.toLowerCase().contains(q))) r,
  ];
  final statusCol = {'product': 'product_status', 'service': 'service_status'}[module];
  if (!legacy && statusCol != null && '${qp['sellable'] ?? ''}' == '1') {
    out = [
      for (final r in out)
        if ('${r[statusCol] ?? ''}'.trim().isEmpty || _kServerSellable.contains('${r[statusCol]}'.trim().toLowerCase())) r,
    ];
  }
  qp.forEach((k, v) {
    final m = RegExp(r'^filter\[(\w+)\]$').firstMatch(k);
    if (m == null || m[1] == 'account_id_any') return;
    out = [for (final r in out) if ('${r[m[1]]}' == '$v') r];
  });
  if (qp['filter[account_id_any]'] != null) {
    out = [for (final r in out) if ('${r['account_id']}' == '${qp['filter[account_id_any]']}') r];
  }
  final limit = int.tryParse('${qp['limit'] ?? 20}') ?? 20;
  final page = int.tryParse('${qp['page'] ?? 1}') ?? 1;
  return out.skip((page - 1) * limit).take(limit).toList();
}

final kasperskyRow = <String, dynamic>{
  'id': 31,
  'product_no': 'PRD-00031',
  'product_code': 'KES-B-1Y',
  'product_name_th': 'Kaspersky Endpoint Security for Business Select (1 ปี / 1 เครื่อง)',
  'product_name_en': 'Kaspersky Endpoint Security for Business Select 1Y',
  'product_category': 'Software',
  'product_unit': 'License',
  'product_initial_price': 1450,
  'product_selling_price': 1290,
  'product_status': 'Active',
};

final fakeProducts = <Map<String, dynamic>>[
  kasperskyRow,
  {
    'id': 32, 'product_no': 'PRD-00032', 'product_code': 'FG-60F', 'product_name_th': 'Fortinet FortiGate 60F Firewall', 'product_category': 'Network',
    'product_unit': 'เครื่อง', 'product_initial_price': 28900, 'product_selling_price': 26500, 'product_status': 'Active',
  },
  {
    'id': 33, 'product_no': 'PRD-00033', 'product_code': 'HIK-2CD', 'product_name_th': 'กล้อง IP Hikvision 4MP Dome', 'product_category': 'CCTV',
    'product_unit': 'ตัว', 'product_initial_price': 2400, 'product_selling_price': 2150, 'product_status': 'Active',
  },
  {
    'id': 34, 'product_no': 'PRD-00034', 'product_code': 'UTP-C6', 'product_name_th': 'สาย LAN CAT6 UTP (ม้วน 305 ม.)', 'product_category': 'Network',
    'product_unit': 'ม้วน', 'product_initial_price': 3900, 'product_selling_price': 3600, 'product_status': 'Active',
  },
  {
    'id': 35, 'product_no': 'PRD-00035', 'product_code': 'DELL-OP7010', 'product_name_th': 'Dell OptiPlex 7010 i5 / 16GB / 512GB', 'product_category': 'Hardware',
    'product_unit': 'เครื่อง', 'product_initial_price': 25900, 'product_selling_price': 24500, 'product_status': 'Active',
  },
  // Not ready for sale — never listed in the quotation picker.
  {
    'id': 36, 'product_no': 'PRD-00036', 'product_code': 'KSOS-DRAFT', 'product_name_th': 'Kaspersky Small Office Security (ร่าง)', 'product_category': 'Software',
    'product_unit': 'License', 'product_selling_price': 990, 'product_status': 'Draft',
  },
  {
    'id': 37, 'product_no': 'PRD-00037', 'product_code': 'KTS-2019', 'product_name_th': 'Kaspersky Total Security 2019', 'product_category': 'Software',
    'product_unit': 'License', 'product_selling_price': 700, 'product_status': 'Inactive',
  },
  {
    'id': 38, 'product_no': 'PRD-00038', 'product_code': 'KAV-2015', 'product_name_th': 'Kaspersky Anti-Virus 2015', 'product_category': 'Software',
    'product_unit': 'License', 'product_selling_price': 500, 'product_status': 'Discontinued',
  },
];

final fakeServices = <Map<String, dynamic>>[
  {'id': 51, 'service_no': 'SRV-00051', 'service_code': 'INS-CCTV', 'service_name_th': 'ค่าติดตั้งกล้องวงจรปิด (ต่อจุด)', 'service_category': 'Installation', 'service_unit': 'จุด', 'service_selling_price': 850},
  {'id': 52, 'service_no': 'SRV-00052', 'service_code': 'MA-1Y', 'service_name_th': 'MA รายปี ระบบเครือข่าย', 'service_category': 'Maintenance', 'service_unit': 'ปี', 'service_selling_price': 18000},
  {'id': 53, 'service_no': 'SRV-00053', 'service_code': 'MA-OLD', 'service_name_th': 'MA รายปี (แพ็กเกจเก่า)', 'service_category': 'Maintenance', 'service_unit': 'ปี', 'service_selling_price': 15000, 'service_status': 'Inactive'},
];

final fakeAccounts = <Map<String, dynamic>>[
  {
    'id': 5, 'account_no': 'ACC-0005', 'account_name': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'account_taxid': '0105561000123', 'mobile_1st': '021234567',
    'email_1st': 'purchase@siamtech.co.th', 'address_line1': '99/9 ถนนพระราม 9', 'address_district': 'ห้วยขวาง', 'address_province': 'กรุงเทพมหานคร', 'smownerid': 1,
  },
  {'id': 6, 'account_no': 'ACC-0006', 'account_name': 'บริษัท กรีนเอนเนอร์ยี่ จำกัด (มหาชน)', 'account_taxid': '0107559000456', 'mobile_1st': '028889999', 'email_1st': 'it@green.co.th', 'smownerid': 2},
  {'id': 7, 'account_no': 'ACC-0007', 'account_name': 'โรงพยาบาลสมิติเวช สาขาศรีราชา', 'mobile_1st': '038320300', 'smownerid': 1},
];

final fakeContacts = <Map<String, dynamic>>[
  {'id': 71, 'contact_no': 'CON-071', 'contact_firstname': 'สมศรี', 'contact_lastname': 'ใจงาม', 'mobile_1st': '0899999999', 'email_1st': 'somsri@siamtech.co.th', 'account_id': 5, 'account_name_1st': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'smownerid': 1},
  {'id': 72, 'contact_no': 'CON-072', 'contact_firstname': 'วิชัย', 'contact_lastname': 'ศรีสุข', 'mobile_1st': '0812223333', 'email_1st': 'wichai@siamtech.co.th', 'account_id': 5, 'account_name_1st': 'บริษัท สยามเทค โซลูชั่น จำกัด', 'smownerid': 1},
  {'id': 73, 'contact_no': 'CON-073', 'contact_firstname': 'Kasem', 'contact_lastname': 'Boonma', 'mobile_1st': '0865554444', 'email_1st': 'kasem@green.co.th', 'account_id': 6, 'account_name_1st': 'บริษัท กรีนเอนเนอร์ยี่ จำกัด (มหาชน)', 'smownerid': 2},
];

final fakeLeads = <Map<String, dynamic>>[
  {'id': 91, 'lead_no': 'LEAD-091', 'lead_firstname': 'ปกรณ์', 'lead_lastname': 'แสงทอง', 'company_name': 'ร้านกาแฟ คาซ่า', 'mobile_1st': '0901112222', 'smownerid': 1},
];

const fakeQuoteFields = [
  {'name': 'quotation_no', 'type': 'Counter', 'readonly': true, 'presence': 1, 'label_th': 'เลขที่'},
  {'name': 'quote_date', 'type': 'Date', 'presence': 1, 'label_th': 'วันที่'},
  {'name': 'valid_until', 'type': 'Date', 'presence': 1, 'label_th': 'ยืนราคาถึง'},
  {'name': 'delivery_date', 'type': 'Date', 'presence': 1, 'label_th': 'วันส่งมอบ'},
  {'name': 'title_th', 'type': 'Text', 'presence': 1, 'label_th': 'ชื่อเรื่อง'},
  {'name': 'customer_name', 'type': 'Text', 'presence': 1, 'label_th': 'ชื่อลูกค้า'},
  {'name': 'related_account_id', 'type': 'AccountSelect', 'presence': 1, 'label_th': 'บัญชีลูกค้า'},
  {'name': 'related_contact_id', 'type': 'ContactSelect', 'presence': 1, 'label_th': 'ผู้ติดต่อ'},
  {'name': 'customer_address', 'type': 'LongText', 'presence': 1, 'label_th': 'ที่อยู่ลูกค้า'},
  {'name': 'customer_taxid', 'type': 'Text', 'presence': 1, 'label_th': 'เลขประจำตัวผู้เสียภาษี'},
  {'name': 'contact_name', 'type': 'Text', 'presence': 1, 'label_th': 'ชื่อผู้ติดต่อ'},
  {'name': 'customer_mobile', 'type': 'Phone', 'presence': 1, 'label_th': 'มือถือ'},
  {'name': 'customer_email', 'type': 'Email', 'presence': 1, 'label_th': 'อีเมล'},
  {'name': 'customer_phone', 'type': 'Phone', 'presence': 1, 'label_th': 'โทรศัพท์'},
  {'name': 'header_discount_type', 'type': 'Enum', 'presence': 1, 'label_th': 'ประเภทส่วนลดหัวบิล'},
  {'name': 'header_discount_value', 'type': 'Number', 'presence': 1, 'label_th': 'ค่าส่วนลดหัวบิล'},
  {'name': 'tax_type', 'type': 'Enum', 'presence': 1, 'label_th': 'ภาษี'},
  {'name': 'tax_rate', 'type': 'Number', 'presence': 1, 'label_th': 'อัตราภาษี'},
  {'name': 'smownerid', 'type': 'PicklistUser', 'presence': 1, 'label_th': 'ผู้รับผิดชอบ'},
  {'name': 'terms_conditions', 'type': 'LongText', 'presence': 1, 'label_th': 'เงื่อนไข (HTML)', 'section': 'Terms'},
  {'name': 'quote_termcondition', 'type': 'LongText', 'presence': 1, 'label_th': 'ท้ายเอกสาร (HTML)', 'section': 'Terms'},
  {'name': 'payment_details', 'type': 'LongText', 'presence': 1, 'label_th': 'การชำระเงิน'},
  {'name': 'validity_days', 'type': 'Number', 'presence': 1, 'label_th': 'ยืนราคา (วัน)'},
];

final fakeQuoteContext = {
  'layouts': {'allowed_layouts': ['template1', 'template2'], 'default_layout': 'template1', 'line_discount_mode': 'per_unit'},
  'new_defaults': {'validity_days': 30, 'payment_details': 'เครดิต 30 วัน', 'tax_type': 'exclude', 'tax_rate': 7},
  'templates': [
    {'id': 1, 'name': 'default', 'code': 'default', 'layout_key': 'template1', 'layout_json': {'is_default': true}},
    {'id': 3, 'name': 'หัวกระดาษ สาขาชลบุรี', 'code': 'cb', 'layout_key': 'template1', 'layout_json': {}},
    {'id': 2, 'name': 'Service Report', 'layout_key': 'template2', 'layout_json': {'is_default': true}},
  ],
  'users': [
    {'id': 1, 'label': 'สมชาย ใจดี'},
    {'id': 2, 'label': 'วิภา รักงาน'},
  ],
};

/// Replies of the R86 fake (plus [extra]); the entity lists are answered by
/// [installQuoteFakeServer].
Map<String, Object?> quoteFakeReplies({Map<String, Object?> extra = const {}}) => {
      'GET /api/fields/quotation': {
        'list': fakeQuoteFields,
        'picklists': {
          'tax_type': [{'value': 'exclude', 'is_default': 1}, {'value': 'include'}],
        },
      },
      'GET /api/fields/product': {
        'list': const [],
        'picklists': {
          'product_category': [{'value': 'CCTV'}, {'value': 'Hardware'}, {'value': 'Network'}, {'value': 'Software'}],
        },
      },
      'GET /api/fields/service': {
        'list': const [],
        'picklists': {
          'service_category': [{'value': 'Installation'}, {'value': 'Maintenance'}],
        },
      },
      'GET /api/quotation/context': fakeQuoteContext,
      'GET /api/quotation/text-templates/defaults/resolve': {
        'terms': {'html': '<p><strong>ยืนราคา 30 วัน</strong></p><ul><li>ชำระเงินภายใน 30 วันหลังส่งมอบ</li><li>รับประกันสินค้า 1 ปี</li></ul>'},
        'footer': {'html': '<p>ขอบคุณที่ไว้วางใจ บริษัท เน็กซ์เอ็กซ์ จำกัด</p>'},
      },
      // Stock (job parts) — the quotation picker must not ask for it.
      'GET /api/field-service/parts/catalog': {
        'list': [
          {'product_id': 31, 'name': kasperskyRow['product_name_th'], 'stock_qty': 42},
          {'product_id': 33, 'name': 'กล้อง IP Hikvision 4MP Dome', 'stock_qty': 0},
        ],
      },
      for (final r in fakeAccounts) 'GET /api/entity/account/${r['id']}': r,
      for (final r in fakeContacts) 'GET /api/entity/contact/${r['id']}': r,
      for (final r in fakeLeads) 'GET /api/entity/lead/${r['id']}': r,
      for (final r in fakeProducts) 'GET /api/entity/product/${r['id']}': r,
      for (final r in fakeServices) 'GET /api/entity/service/${r['id']}': r,
      'POST /api/quotation/save': {'id': 50, 'quotation': {'id': 50, 'quotation_no': 'QT26-0050', 'modifiedtime': '2026-11-13T03:00:00.000Z'}},
      ...extra,
    };

/// Answers the entity lists like the real server (see [serverEntitySearch]).
void installQuoteFakeServer(FakeNextxAdapter adapter, {bool legacy = false}) {
  final tables = {'product': fakeProducts, 'service': fakeServices, 'account': fakeAccounts, 'contact': fakeContacts, 'lead': fakeLeads};
  adapter.onRequest = (RequestOptions o) {
    final m = RegExp(r'^/api/entity/(\w+)$').firstMatch(o.path);
    if (m == null || o.method.toUpperCase() != 'GET') return;
    final rows = tables[m[1]];
    if (rows == null) return;
    final list = serverEntitySearch(m[1]!, rows, o.queryParameters, legacy: legacy);
    final all = serverEntitySearch(m[1]!, rows, {...o.queryParameters, 'limit': '100000', 'page': '1'}, legacy: legacy);
    adapter.replies['GET ${o.path}'] = {'list': list, 'meta': {'total': all.length}};
  };
}
