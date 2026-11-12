import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/entity_form_rules.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/services/geo_address.dart';
import 'package:nextx_mobile/widgets/fields/nx_entity_form.dart';
import 'package:nextx_mobile/widgets/fields/nx_thai_address_set.dart';

import 'support/fake_api.dart';

const _bkkZip10110 = [
  {'subdistrict': 'คลองเตย', 'district': 'คลองเตย', 'province': 'กรุงเทพมหานคร', 'postal_code': '10110'},
  {'subdistrict': 'คลองตัน', 'district': 'คลองเตย', 'province': 'กรุงเทพมหานคร', 'postal_code': '10110'},
];
const _bkkZip10330 = [
  {'subdistrict': 'ลุมพินี', 'district': 'ปทุมวัน', 'province': 'กรุงเทพมหานคร', 'postal_code': '10330'},
  {'subdistrict': 'รองเมือง', 'district': 'ปทุมวัน', 'province': 'กรุงเทพมหานคร', 'postal_code': '10330'},
];

Map<String, dynamic> _f(String name, String label) => {'name': name, 'label_th': label, 'uitype': '1'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detect / match', () {
    test('finds the web address set (ADDRESS_FIELD_MAP) and its pin / street columns', () {
      final sets = detectThaiAddressSets([
        'lead_firstname', 'address_line1', 'address_province', 'address_district', 'address_sub_district', 'address_postal_code', 'lead_locationmap',
      ]);
      expect(sets, hasLength(1));
      final s = sets.single;
      expect(s.province, 'address_province');
      expect(s.district, 'address_district');
      expect(s.subdistrict, 'address_sub_district');
      expect(s.postal, 'address_postal_code');
      expect(s.line, 'address_line1');
      expect(s.latLng, 'lead_locationmap');
      // Prefixed sets (billing_ / shipping_) are separate.
      final two = detectThaiAddressSets(['billing_province', 'billing_postal_code', 'shipping_province', 'shipping_zipcode', 'other_province']);
      expect(two.map((e) => e.province), ['billing_province', 'shipping_province']);
      expect(two.last.postal, 'shipping_zipcode');
    });

    test('geocoder names match the NEXTX lists', () {
      expect(matchThaiArea(['กรุงเทพมหานคร', 'เชียงใหม่'], 'Bangkok'), 'กรุงเทพมหานคร');
      expect(matchThaiArea(['กรุงเทพมหานคร', 'เชียงใหม่'], 'จังหวัดเชียงใหม่'), 'เชียงใหม่');
      expect(matchThaiArea(['ปทุมวัน', 'บางรัก'], 'เขตปทุมวัน'), 'ปทุมวัน');
      expect(matchThaiArea(['เมืองเชียงใหม่', 'สารภี'], 'อำเภอเมืองเชียงใหม่'), 'เมืองเชียงใหม่');
      expect(matchThaiArea(['ลุมพินี'], 'แขวงลุมพินี'), 'ลุมพินี');
      expect(matchThaiArea(['ลุมพินี'], ''), isNull);
    });
  });

  group('address set in the create form', () {
    late FakeNextxAdapter adapter;
    late Map<String, dynamic> values;

    Future<void> pumpForm(
      WidgetTester tester, {
      Map<String, Object?> replies = const {},
      Map<String, dynamic> initial = const {},
      bool withPin = false,
    }) async {
      adapter = FakeNextxAdapter({
        'GET /api/thai-address/provinces': {'provinces': ['กรุงเทพมหานคร', 'เชียงใหม่']},
        'GET /api/thai-address/districts': {'districts': ['ปทุมวัน', 'คลองเตย']},
        'GET /api/thai-address/subdistricts': {
          'subdistricts': [
            {'name': 'ลุมพินี', 'postal_code': '10330'},
            {'name': 'รองเมือง', 'postal_code': '10330'},
          ],
        },
        ...replies,
      }..removeWhere((k, v) => v == null));
      final config = AppConfig();
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      values = {...initial};
      final fields = [
        _f('lead_firstname', 'ชื่อ'),
        _f('address_line1', 'ที่อยู่'),
        _f('address_province', 'จังหวัด'),
        _f('address_district', 'อำเภอ/เขต'),
        _f('address_sub_district', 'ตำบล/แขวง'),
        _f('address_postal_code', 'รหัสไปรษณีย์'),
        if (withPin) _f('lead_locationmap', 'พิกัด'),
      ];
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => ListView(padding: const EdgeInsets.all(16), children: [
                NxEntityForm(
                  fields: fields,
                  values: values,
                  api: config.apiClient,
                  module: 'lead',
                  sectionOf: (n) => formSectionOf('lead', n),
                  sections: kFormSections,
                  sectionOrder: kFormSectionOrder,
                  onChanged: (n, v) => setState(() => values[n] = v),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester, [int frames = 12]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pickFromSheet(WidgetTester tester, String fieldKey, String option) async {
      await tester.ensureVisible(find.byKey(ValueKey(fieldKey)));
      await tester.tap(find.byKey(ValueKey(fieldKey)));
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, option));
      await settle(tester);
    }

    testWidgets('one group replaces the 4 plain inputs, with Thai hints', (tester) async {
      await pumpForm(tester);
      expect(find.byKey(const ValueKey('addr-set-address_province')), findsOneWidget);
      expect(find.byKey(const ValueKey('nx-field-address_province')), findsNothing);
      expect(find.byKey(const ValueKey('addr-map')), findsOneWidget);
      expect(find.text('ปักหมุดบนแผนที่'), findsOneWidget);
      expect(find.text('ค้นจากรหัสไปรษณีย์'), findsOneWidget);
      expect(find.byKey(const ValueKey('addr-hint')), findsOneWidget);
      expect(find.text('แตะเพื่อเลือกจังหวัด'), findsOneWidget);
      // District / sub-district wait for the level above.
      expect(find.text('เลือกจังหวัดก่อน'), findsNWidgets(2));
      expect(find.text('เช่น 10110 — พิมพ์ 5 หลักเพื่อค้นพื้นที่'), findsOneWidget);
      // The street line stays an ordinary field.
      expect(find.byKey(const ValueKey('nx-field-address_line1')), findsOneWidget);
    });

    testWidgets('จังหวัด → อำเภอ → ตำบล cascade fills the postcode', (tester) async {
      await pumpForm(tester);
      await pickFromSheet(tester, 'addr-address_province', 'กรุงเทพมหานคร');
      expect(values['address_province'], 'กรุงเทพมหานคร');
      expect(find.text('แตะเพื่อเลือกอำเภอ/เขต'), findsOneWidget);
      expect(find.text('เลือกอำเภอ/เขตก่อน'), findsOneWidget);

      await pickFromSheet(tester, 'addr-address_district', 'ปทุมวัน');
      expect(values['address_district'], 'ปทุมวัน');
      final d = adapter.calls.lastWhere((c) => c.path == '/api/thai-address/districts');
      expect(d.queryParameters['province'], 'กรุงเทพมหานคร');

      await pickFromSheet(tester, 'addr-address_sub_district', 'ลุมพินี');
      expect(values['address_sub_district'], 'ลุมพินี');
      expect(values['address_postal_code'], '10330');
      final s = adapter.calls.lastWhere((c) => c.path == '/api/thai-address/subdistricts');
      expect(s.queryParameters, {'province': 'กรุงเทพมหานคร', 'district': 'ปทุมวัน'});
      expect(find.text('10330'), findsOneWidget);

      // Changing the province clears what is below it.
      await pickFromSheet(tester, 'addr-address_province', 'เชียงใหม่');
      expect(values['address_province'], 'เชียงใหม่');
      expect(values['address_district'], '');
      expect(values['address_sub_district'], '');
      expect(values['address_postal_code'], '');
    });

    testWidgets('type a postcode → pick a suggested area → all fields filled', (tester) async {
      await pumpForm(tester, replies: {'GET /api/thai-address/by-postal-code': {'options': _bkkZip10110}});
      await tester.ensureVisible(find.byKey(const ValueKey('addr-address_postal_code')));
      await tester.enterText(find.byKey(const ValueKey('addr-address_postal_code')), '10110');
      await settle(tester);
      final call = adapter.calls.lastWhere((c) => c.path == '/api/thai-address/by-postal-code');
      expect(call.queryParameters['postalCode'], '10110');
      expect(find.byKey(const ValueKey('addr-zip-suggestions')), findsOneWidget);
      expect(find.textContaining('พบ 2 พื้นที่ของรหัส 10110'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('addr-zip-opt-1')));
      await tester.tap(find.byKey(const ValueKey('addr-zip-opt-1')));
      await settle(tester);
      expect(values['address_province'], 'กรุงเทพมหานคร');
      expect(values['address_district'], 'คลองเตย');
      expect(values['address_sub_district'], 'คลองตัน');
      expect(values['address_postal_code'], '10110');
      expect(find.byKey(const ValueKey('addr-zip-suggestions')), findsNothing);
    });

    testWidgets('unknown postcode says so', (tester) async {
      await pumpForm(tester, replies: {'GET /api/thai-address/by-postal-code': {'options': []}});
      await tester.ensureVisible(find.byKey(const ValueKey('addr-address_postal_code')));
      await tester.enterText(find.byKey(const ValueKey('addr-address_postal_code')), '99999');
      await settle(tester);
      expect(find.byKey(const ValueKey('addr-zip-none')), findsOneWidget);
      expect(find.text('ไม่พบพื้นที่สำหรับรหัสไปรษณีย์นี้'), findsOneWidget);
    });

    testWidgets('pin on the map → reverse geocode fills province / district / sub-district / postcode / street', (tester) async {
      GeoAddress.debugLookupParts = (lat, lng) async => const GeoAddressParts(
            street: '99 ถนนพระรามที่ 4',
            subdistrict: 'แขวงลุมพินี',
            district: 'เขตปทุมวัน',
            province: 'Bangkok',
            postalCode: '10330',
          );
      addTearDown(() => GeoAddress.debugLookupParts = null);
      await pumpForm(
        tester,
        withPin: true,
        initial: {'lead_locationmap': '13.7300,100.5400'},
        replies: {'GET /api/thai-address/by-postal-code': {'options': _bkkZip10330}},
      );
      await tester.tap(find.byKey(const ValueKey('addr-map')));
      await settle(tester);
      expect(find.text('ปักหมุดตำแหน่งที่อยู่'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pin-done')));
      await settle(tester, 20);
      expect(values['lead_locationmap'], '13.730000,100.540000');
      expect(values['address_province'], 'กรุงเทพมหานคร');
      expect(values['address_district'], 'ปทุมวัน');
      expect(values['address_sub_district'], 'ลุมพินี');
      expect(values['address_postal_code'], '10330');
      expect(values['address_line1'], '99 ถนนพระรามที่ 4');
      expect(find.text('เติมที่อยู่จากหมุดแล้ว — ตรวจสอบอีกครั้งก่อนบันทึก'), findsOneWidget);
    });

    testWidgets('address lists unreachable → plain text inputs still work', (tester) async {
      await pumpForm(tester, replies: {'GET /api/thai-address/provinces': null});
      await tester.tap(find.byKey(const ValueKey('addr-address_province')));
      await settle(tester);
      expect(find.text('โหลดรายชื่อจังหวัด/อำเภอไม่ได้ — พิมพ์ที่อยู่เองได้เลย'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('addr-address_province')), 'ภูเก็ต');
      await tester.pump();
      expect(values['address_province'], 'ภูเก็ต');
    });
  });
}
