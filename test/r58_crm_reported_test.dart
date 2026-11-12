import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/screens/calendar/activity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/nx_entity_form.dart';
import 'package:nextx_mobile/widgets/fields/nx_form_field.dart';

import 'support/fake_api.dart';

/// User-reported CRM bugs (Lead / Contact / Account, Activity, Product).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lead / Contact / Account dates', () {
    test('blacklist_datetime is a UTC instant: 03:37Z shows 10:37 Thai', () {
      expect(isWallClockField('blacklist_datetime', module: 'lead'), isFalse);
      expect(isWallClockField('contact_datetime', module: 'contact'), isFalse);
      // Other modules keep the wall-clock rule.
      expect(isWallClockField('plan_datetime', module: 'job'), isTrue);
      expect(formatThaiField('2026-11-11T03:37:00.000Z', 'blacklist_datetime', module: 'account'), '11/11/2026 10:37');
    });

    test('Thai form time goes back as the UTC the server stores (like the web)', () {
      expect(toPartyUtcWall('2026-11-11T10:37:00'), '2026-11-11 03:37:00');
      expect(toPartyUtcWall('2026-11-11 00:30:00'), '2026-11-10 17:30:00');
      expect(toPartyUtcWall('2026-11-11T03:37:00.000Z'), '2026-11-11 03:37:00');
      expect(toPartyUtcWall('1990-11-10'), '1990-11-10');
    });

    test('edit form: untouched birthdate and date-time round-trip unchanged', () {
      final fields = [
        {'name': 'birthdate', 'type': 'Date'},
        {'name': 'blacklist_datetime', 'type': 'DateTime'},
        {'name': 'contact_name', 'type': 'Text'},
      ];
      final row = {
        'birthdate': '1990-11-09T17:00:00.000Z', // DATE 10 Nov via node-pg in Bangkok TZ
        'blacklist_datetime': '2026-11-11T03:37:00.000Z',
        'contact_name': 'QA',
      };
      final values = Map<String, dynamic>.from(row);
      normalizeFormDates(fields, values, module: 'contact');
      expect(values['birthdate'], '1990-11-10');
      expect(values['blacklist_datetime'], '2026-11-11T10:37:00'); // shown / picked in Thai time
      final payload = collectEntityPayload(fields, values, currentRow: row, module: 'contact');
      expect(payload['birthdate'], '1990-11-10');
      expect(payload['blacklist_datetime'], '2026-11-11 03:37:00'); // same instant as stored
    });
  });

  group('price typing', () {
    test('decimals can be typed; comma decimal pads work; junk is refused', () {
      String? c(String s, {bool signed = false}) => NxDecimalInputFormatter.clean(s, signed: signed);
      expect(c('12.'), '12.');
      expect(c('12.50'), '12.50');
      expect(c('.5'), '.5');
      expect(c('12,5'), '12.5');
      expect(c('1,500.25'), '1500.25');
      expect(c('1,500'), '1500');
      expect(c('12.5.'), isNull);
      expect(c('12a'), isNull);
      expect(c('-3'), isNull);
      expect(c('-3.5', signed: true), '-3.5');
    });

    testWidgets('a price field accepts 12.5', (tester) async {
      String? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => NxFormField(
              uiType: FieldUiType.currency,
              label: 'ราคาขาย',
              name: 'product_selling_price',
              value: got,
              onChanged: (v) => setState(() => got = '$v'),
            ),
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), '12.');
      await tester.pump();
      expect(got, '12.');
      await tester.enterText(find.byType(TextField), '12.5');
      await tester.pump();
      expect(got, '12.5');
      await tester.enterText(find.byType(TextField), '12.5.');
      await tester.pump();
      expect(got, '12.5');
      await tester.pump(const Duration(milliseconds: 400)); // focus scroll timer
    });
  });

  testWidgets('history: a changed linked account shows names, not ids', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    SharedPreferences.setMockInitialValues({});
    const contact = {'id': 3, 'firstname': '[QA]', 'lastname': 'ผู้ติดต่อ', 'account_id': 1592};
    final adapter = FakeNextxAdapter({
      'GET /api/fields/contact': {
        'list': [
          {'name': 'firstname', 'label_th': 'ชื่อ'},
          {'name': 'account_id', 'label_th': 'บัญชี'},
        ],
        'picklists': {},
      },
      'GET /api/entity/contact/3': contact,
      'GET /api/entity/contact/3/comments': {'list': []},
      'GET /api/entity/contact/3/timeline': {
        'list': [
          {'type': 'field_change', 'field_name': 'account_id', 'field_label_th': 'บัญชี', 'old_value': '1591', 'new_value': '1592', 'at': '2026-11-11T03:37:00.000Z'},
        ],
      },
      'GET /api/entity/account/1591': {'id': 1591, 'account_name': '[QA] บริษัทเก่า'},
      'GET /api/entity/account/1592': {'id': 1592, 'account_name': '[QA] บริษัทใหม่'},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['contact']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityDetailScreen(module: 'contact', row: contact)),
    ));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.ensureVisible(find.text('ประวัติ').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('ประวัติ').first);
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(adapter.callKeys, contains('GET /api/entity/account/1591'));
    expect(find.textContaining('[QA] บริษัทเก่า → [QA] บริษัทใหม่'), findsOneWidget);
    expect(find.textContaining('1591 → 1592'), findsNothing);
  });

  test('activity export text', () {
    final t = activityExportText(
      {'subject': '[QA] เยี่ยมลูกค้า', 'location': 'สยาม', 'status': 'Planned', 'description': '<p>นำเสนอ</p>', 'account_name': 'บริษัท QA'},
      when: '11 พ.ย. 2569 · 10:00–11:00',
      link: 'https://x.test/modules/activity/view/9',
    );
    expect(t, contains('[QA] เยี่ยมลูกค้า'));
    expect(t, contains('10:00–11:00'));
    expect(t, contains('สยาม'));
    expect(t, contains('บริษัท QA'));
    expect(t, contains('นำเสนอ'));
    expect(t, isNot(contains('<p>')));
    expect(t, endsWith('https://x.test/modules/activity/view/9'));
  });

  group('product edit / duplicate close', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    });

    const product = {
      'id': 7,
      'product_no': 'PD-QA-1',
      'product_name_th': '[QA] สินค้าทดสอบ',
      'product_selling_price': '1500.00',
      'product_status': 'Active',
    };

    Future<void> settle(WidgetTester tester, [int frames = 16]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpList(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'nx_crm_row_actions_hint_v1': true});
      final adapter = FakeNextxAdapter({
        'GET /api/modules': [],
        'GET /api/customviews': {'list': [], 'default_id': null},
        'GET /api/fields/product': {
          'list': [
            {'name': 'product_name_th', 'label_th': 'ชื่อสินค้า'},
            {'name': 'product_selling_price', 'label_th': 'ราคาขาย', 'type': 'Currency'},
            {'name': 'product_status', 'label_th': 'สถานะ', 'uitype': '15'},
          ],
          'picklists': {
            'product_status': [
              {'value': 'Active', 'label': 'ใช้งาน'},
            ],
          },
        },
        'GET /api/entity/product': {'list': [product], 'total': 1},
        'GET /api/entity/product/7': product,
        'GET /api/entity/product/7/comments': {'list': []},
        'GET /api/customviews/meta': {'users': [], 'date_fields': [], 'period_presets': []},
      });
      final config = AppConfig();
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['product']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: EntityListScreen(module: 'product', title: '[QA] สินค้า')),
      ));
      await settle(tester);
    }

    for (final wide in [false, true]) {
      testWidgets('detail → edit → header back returns to the detail (wide: $wide)', (tester) async {
        await pumpList(tester);
        if (wide) {
          tester.view.physicalSize = const Size(1280, 900);
          await settle(tester);
        }
        await tester.tap(find.textContaining('[QA] สินค้าทดสอบ').first);
        await settle(tester, 24);
        await tester.tap(find.byTooltip('แก้ไข').last);
        await settle(tester, 24);
        expect(find.byType(EntityCreateScreen), findsOneWidget);
        await tester.tap(find.byType(TextField).at(1));
        await settle(tester);
        await tester.tap(find.byTooltip('กลับ').last);
        await settle(tester, 24);
        expect(find.byKey(const ValueKey('nx-discard-dialog')), findsNothing);
        expect(find.byType(EntityCreateScreen), findsNothing);
      });
    }

    for (final action in ['edit', 'duplicate']) {
      testWidgets('$action: back after touching a field leaves the form', (tester) async {
        await pumpList(tester);
        await tester.longPress(find.textContaining('[QA] สินค้าทดสอบ').first);
        await settle(tester);
        await tester.tap(find.byKey(ValueKey('row-act-$action')));
        await settle(tester, 24);
        expect(find.byType(EntityCreateScreen), findsOneWidget);
        // Touch the price (first touch = unsaved-changes baseline), change nothing.
        await tester.tap(find.byType(TextField).at(1));
        await settle(tester);
        await tester.binding.handlePopRoute();
        await settle(tester, 24);
        expect(find.byKey(const ValueKey('nx-discard-dialog')), findsNothing);
        expect(find.byType(EntityCreateScreen), findsNothing);
      });
    }
  });
}
