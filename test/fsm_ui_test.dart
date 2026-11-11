import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/entity_modules.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/screens/deep_link_loaders.dart';
import 'package:nextx_mobile/screens/fsm/fsm_home_screen.dart';
import 'package:nextx_mobile/screens/jobs/job_inspection_screen.dart';
import 'package:nextx_mobile/screens/module/module_hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FSM module titles', () {
    expect(EntityModules.titleOf('job'), 'ใบสั่งงาน');
    expect(EntityModules.titleOf('service-contract'), 'สัญญาบริการ');
    expect(EntityModules.isFsm('inspection'), isTrue);
    expect(EntityModules.isFsm('product'), isFalse);
  });

  testWidgets('FSM home lists operational modules', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: config,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const FsmHomeScreen(),
        ),
      ),
    );
    await tester.pump();
    config.debugOverrideSession(
      const SessionState(
        menusLoaded: true,
        menuKeys: [
          'job',
          'inspection',
          'service-contract',
          'asset',
          'service-location',
          'skill',
        ],
      ),
    );
    await tester.pump();
    expect(find.text('ใบสั่งงาน'), findsOneWidget);
    expect(find.text('ใบตรวจรับ'), findsOneWidget);
    expect(find.text('สัญญาบริการ'), findsOneWidget);
    expect(find.text('สินทรัพย์'), findsOneWidget);
    expect(find.text('พื้นที่บริการ'), findsOneWidget);
    expect(find.text('ทักษะ'), findsOneWidget);
    expect(find.text('งานที่ได้รับ'), findsOneWidget);
    expect(find.text('ไป Workspace งาน'), findsOneWidget);
    await tester.tap(find.text('ใบสั่งงาน'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(EntityListScreen), findsOneWidget);
  });

  testWidgets('hub shows web groups for matching keys, not files', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(home: Scaffold(body: ModuleHubScreen())),
      ),
    );
    await tester.pump();
    config.debugOverrideSession(
      const SessionState(
        menusLoaded: true,
        menuKeys: ['quotation', 'job'],
      ),
    );
    await tester.pump();
    // Grouped like the web nav rail: quotation → งานขาย, job → งานบริการ.
    expect(find.text('งานขาย'), findsOneWidget);
    expect(find.text('งานบริการ'), findsOneWidget);
    expect(find.text('ลูกค้า'), findsNothing);
    expect(find.text('แอปอื่น'), findsNothing);
    expect(find.text('ไฟล์'), findsNothing);
    expect(find.text('โปรไฟล์'), findsNothing);
  });

  testWidgets('job detail offers inspection CTA when allowed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final config = AppConfig();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: config,
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'job',
            row: {'id': '11', 'job_no': 'JOB-11', 'job_status': 'Open'},
          ),
        ),
      ),
    );
    await tester.pump();
    config.debugOverrideSession(
      const SessionState(
        menusLoaded: true,
        menuKeys: ['job', 'inspection'],
      ),
    );
    await tester.pump();
    expect(find.text('JOB-11'), findsWidgets);
    expect(find.text('ใบตรวจรับของงานนี้'), findsOneWidget);
    expect(find.text('PDF ใบสั่งงาน'), findsOneWidget);
    expect(find.text('นัดหมาย'), findsOneWidget);
    expect(find.text('ทักษะงาน'), findsOneWidget);
    expect(find.text('อะไหล่ / ชิ้นส่วน'), findsOneWidget);
  });

  testWidgets('asset and contract extras', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'asset',
            row: {'id': '8', 'serial_no': 'SN-8'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('สร้างใบสั่งงานจากสินทรัพย์'), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'service_contract',
            row: {'id': '4', 'contract_no': 'SC-4'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('สร้างใบสั่งงานจากสัญญา'), findsOneWidget);
    expect(find.text('สมุด manday'), findsOneWidget);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'case',
            row: {'id': '6', 'case_name': 'แอร์เสีย'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('สร้างใบสั่งงานจากเคส'), findsOneWidget);
    expect(find.text('สร้างนัดหมายจากเคส'), findsOneWidget);
    expect(find.text('Manday ของเคส'), findsOneWidget);
  });

  testWidgets('JobByIdLoader opens job entity not inspection-only', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: JobByIdLoader(id: '11'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(EntityDetailScreen), findsOneWidget);
    expect(find.byType(JobInspectionScreen), findsNothing);
  });

  testWidgets('job lookup shows related account chip', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const MaterialApp(
          home: EntityDetailScreen(
            module: 'job',
            row: {
              'id': '11',
              'job_name': 'ติดตั้งแอร์',
              'related_account_id': 9,
              'related_account_id_name': 'Acme Co',
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Acme Co'), findsWidgets);
  });
}
