import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/entity_display.dart';
import 'package:nextx_mobile/core/entity_modules.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/search/search_modules.dart';
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/nx_field_value.dart';
import 'package:nextx_mobile/widgets/fields/nx_pick_option.dart';
import 'package:nextx_mobile/screens/crm/crm_home_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/widgets/nx_avatar.dart';
import 'package:nextx_mobile/widgets/nx_entity_row.dart';
import 'package:nextx_mobile/widgets/nx_filter_chips.dart';
import 'package:nextx_mobile/widgets/nx_search_field.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entity display helpers', () {
    final row = {
      'firstname': 'สมชาย',
      'lastname': 'ใจดี',
      'email': 'somchai@example.com',
      'status': 'New',
      'modifiedtime': '2026-10-28T09:05:00Z',
    };
    expect(entityTitle(row, module: 'lead'), 'สมชาย ใจดี');
    expect(
      entityTitle({'quotation_no': 'QT-4', 'customer_name': 'Acme', 'id': 4}, module: 'quotation'),
      'QT-4 · Acme',
    );
    expect(entityTitle({'quotation_no': 'QT-21'}, module: 'quotation'), 'QT-21');
    expect(entityTitle({'deal_no': 'D-1', 'deal_name': 'ปิดงบ'}, module: 'deal'), 'D-1 · ปิดงบ');
    expect(entityTitle({'account_name': 'บริษัท เอ'}, module: 'account'), 'บริษัท เอ');
    expect(entityTitle({'lead_name': 'ลีดใหม่'}, module: 'lead'), 'ลีดใหม่');
    expect(entityTitle({'contract_name': 'สัญญาปีนี้', 'contract_no': 'SC-1'}, module: 'service_contract'), 'สัญญาปีนี้');
    expect(entityInitials('สมชาย ใจดี'), isNotEmpty);
    expect(entityStatus(row), 'New');
    expect(entityWhen(row), isNotNull);
    expect(entityPeopleLine(row), contains('somchai@example.com'));
    expect(entityTitle({'productname': 'ปั๊มน้ำ'}, module: 'product'), 'ปั๊มน้ำ');
    expect(entityTitle({'servicename': 'ล้างแอร์'}, module: 'service'), 'ล้างแอร์');
    expect(entityTitle({'inspection_no': 'IN-1'}, module: 'inspection'), 'IN-1');
    expect(entityStatus({'job_status': 'Open'}), 'Open');
    expect(
      entityTitle({'id': 4, 'product_name_th': 'ปั๊มน้ำไทย', 'name': 'Pump'}, module: 'product'),
      'ปั๊มน้ำไทย',
    );
    expect(entityTitle({'id': 4, 'product_name_th': 'ปั๊มน้ำไทย'}, module: 'product'), isNot(contains('product #')));
    expect(entityTitle({'service_name_th': 'ล้างแอร์รายปี'}, module: 'service'), 'ล้างแอร์รายปี');
    expect(entityTitle({'job_name': 'ติดตั้งแอร์', 'id': 9}, module: 'job'), 'ติดตั้งแอร์');
    expect(entityTitle({'location_name': 'อาคาร A'}, module: 'service_location'), 'อาคาร A');
    expect(entityTitle({'serial_no': 'SN-88'}, module: 'asset'), 'SN-88');
    expect(entityTitle({'case_name': 'แอร์เสีย'}, module: 'case'), 'แอร์เสีย');
    expect(lookupRecordId({'id': 12, 'name': 'Acme'}), '12');
    expect(pickRecordId({'service_contract_id': 77}, ['service_contract_id', 'id']), '77');
  });

  testWidgets('Nx widgets render in light and dark', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ListView(
              children: [
                NxSearchField(controller: controller, hint: 'ค้นหา'),
                NxFilterChips(
                  value: NxEntityFilter.all,
                  onChanged: (_) {},
                ),
                const NxEntityRow(
                  title: 'Acme Lead',
                  subtitle: 'new · acme@example.com',
                  meta: '09:05',
                ),
                const NxAvatar(label: 'Acme Lead'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('ค้นหา'), findsOneWidget);
      expect(find.text('ทั้งหมด'), findsOneWidget);
      expect(find.text('ของฉัน'), findsOneWidget);
      expect(find.text('ล่าสุด'), findsOneWidget);
      expect(find.text('Acme Lead'), findsWidgets);
      expect(find.text('09:05'), findsOneWidget);
      controller.dispose();
    }
  });

  testWidgets('CRM home has no API path in light and dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppConfig(),
          child: MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            home: const CrmHomeScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ลูกค้าและงานขาย'), findsOneWidget);
      expect(find.textContaining('/api/entity'), findsNothing);
      expect(
        tester.element(find.byType(CrmHomeScreen)).read<AppConfig>().themeMode,
        ThemeMode.system,
      );
    }
  });

  testWidgets('entity list inbox chrome in light and dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppConfig(),
          child: MaterialApp(
            theme: theme,
            home: const EntityListScreen(module: 'lead', title: 'ผู้มุ่งหวัง'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('ผู้มุ่งหวัง'), findsWidgets);
      expect(find.byType(NxSearchField), findsOneWidget);
      expect(find.text('ทั้งหมด'), findsOneWidget);
      expect(find.text('ล่าสุด'), findsOneWidget);
      expect(find.byIcon(NxI.plus), findsOneWidget);
      expect(find.textContaining('ยังไม่มี'), findsOneWidget);
    }
  });

  testWidgets('entity detail header uses avatar and status chip', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppConfig(),
          child: MaterialApp(
            theme: theme,
            home: const EntityDetailScreen(
              module: 'lead',
              row: {
                'id': '1',
                'lastname': 'ทดสอบ',
                'email': 'a@b.com',
                'status': 'Qualified',
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('ทดสอบ'), findsWidgets);
      expect(find.byType(NxAvatar), findsWidgets);
      expect(find.text('Qualified'), findsWidgets);
      expect(find.byType(Chip), findsOneWidget);
    }
  });

  testWidgets('CRM home shows product service and quotation when allowed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(
          home: CrmHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    config.debugOverrideSession(
      const SessionState(
        menusLoaded: true,
        menuKeys: ['product', 'service', 'quotation'],
      ),
    );
    await tester.pump();
    expect(find.text('สินค้า'), findsOneWidget);
    expect(find.text('บริการ'), findsOneWidget);
    expect(find.text('ใบเสนอราคา'), findsOneWidget);
    expect(find.text('สินค้าและบริการ'), findsOneWidget);
    expect(find.text('บันทึกการโทร'), findsNothing);
    await tester.tap(find.text('ใบเสนอราคา'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(EntityListScreen), findsOneWidget);
  });

  test('light scaffold uses atmosphere wash and primary CTA', () {
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFF6F7FB));
    expect(AppTheme.light.colorScheme.onSurface, const Color(0xFF1C1C1E));
    expect(AppTheme.light.textTheme.bodyLarge?.fontWeight, FontWeight.w400);
    expect(AppTheme.light.textTheme.titleLarge?.fontWeight, FontWeight.w600);
    expect(
      AppTheme.light.filledButtonTheme.style?.backgroundColor?.resolve({}),
      AppTheme.primary,
    );
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF16161D));
    expect(AppTheme.dark.colorScheme.onSurface, const Color(0xFFF5F5F7));
    expect(AppTheme.dark.cardTheme.elevation, 0);
    expect(AppTheme.light.cardTheme.elevation, 0);
  });

  test('search modules are gated by menu access', () {
    expect(EntityModules.menuKeyOf('service_contract'), 'service-contract');
    expect(EntityModules.menuKeyOf('service_location'), 'service-location');
    expect(EntityModules.menuKeyOf('activity'), 'calendar');
    final none = globalSearchModulesFor(const SessionState(menusLoaded: true, menuKeys: []));
    expect(none, isEmpty);
    final gated = globalSearchModulesFor(
      const SessionState(menusLoaded: true, menuKeys: ['product', 'job', 'service-contract']),
    );
    expect(gated, containsAll(['product', 'job', 'service_contract']));
    expect(gated, isNot(contains('lead')));
    expect(gated, isNot(contains('account')));
  });

  testWidgets('quotation detail can edit lines and convert', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'quotation',
            row: {'id': '21', 'quotation_no': 'QT-21'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('QT-21'), findsWidgets);
    expect(find.text('บรรทัด'), findsOneWidget);
    expect(find.text('บันทึกบรรทัด'), findsOneWidget);
    expect(find.text('แปลงเป็นออเดอร์'), findsOneWidget);
    expect(find.text('แปลงเป็นสัญญาบริการ'), findsOneWidget);
    expect(find.text('ส่งอีเมลใบเสนอราคา'), findsOneWidget);
    expect(find.text('ส่งขออนุมัติ'), findsOneWidget);
  });

  testWidgets('lead detail offers convert', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'lead',
            row: {'id': '3', 'lastname': 'ใจดี', 'status': 'Qualified'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('แปลงลีด'), findsOneWidget);
  });

  testWidgets('lookup chip is tappable', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NxFieldValueView(
            uiType: FieldUiType.accountSelect,
            label: 'บัญชี',
            value: '9',
            options: const [NxPickOption(value: '9', label: 'Acme Co')],
            onOpen: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Acme Co'));
    expect(opened, isTrue);
  });
}
