import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/nx_breakpoint.dart';
import 'package:nextx_mobile/screens/onboarding/getting_started_screen.dart';
import 'package:nextx_mobile/widgets/nx_app_header.dart';
import 'package:nextx_mobile/widgets/nx_atmosphere.dart';
import 'package:nextx_mobile/widgets/nx_hero_cta.dart';
import 'package:nextx_mobile/widgets/nx_tab_nav.dart';
import 'package:nextx_mobile/widgets/nx_skeleton.dart';
import 'package:nextx_mobile/widgets/nx_split_view.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';
import 'package:nextx_mobile/widgets/nx_create_fab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<NxBreakpoint> pumpBp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late NxBreakpoint bp;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            bp = NxBreakpoint.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return bp;
  }

  testWidgets('Mini 320 is icon-only bottom nav', (tester) async {
    final bp = await pumpBp(tester, const Size(320, 640));
    expect(bp.size, NxSize.mini);
    expect(bp.iconOnlyNav, isTrue);
    expect(bp.useRail, isFalse);
    expect(bp.twoPane, isFalse);
    expect(bp.gridColumns, 1);
    expect(bp.titleSize, 22);
  });

  testWidgets('Mobile 390 is single pane bottom nav', (tester) async {
    final bp = await pumpBp(tester, const Size(390, 844));
    expect(bp.size, NxSize.mobile);
    expect(bp.useRail, isFalse);
    expect(bp.twoPane, isFalse);
    expect(bp.gridColumns, 2);
    expect(bp.titleSize, 28);
  });

  testWidgets('phone landscape stays compact with bottom nav', (tester) async {
    final bp = await pumpBp(tester, const Size(844, 390));
    expect(bp.useRail, isFalse);
    expect(bp.twoPane, isFalse);
  });

  testWidgets('Tablet 768 is two-pane rail', (tester) async {
    final bp = await pumpBp(tester, const Size(768, 1024));
    expect(bp.size, NxSize.tablet);
    expect(bp.useRail, isTrue);
    expect(bp.twoPane, isTrue);
    expect(bp.gridColumns, 3);
  });

  testWidgets('Desktop 1100 two-pane form cap 640', (tester) async {
    final bp = await pumpBp(tester, const Size(1100, 800));
    expect(bp.size, NxSize.desktop);
    expect(bp.useRail, isTrue);
    expect(bp.formMaxWidth, 640);
  });

  testWidgets('1280 is wide two-pane with form cap 640', (tester) async {
    final bp = await pumpBp(tester, const Size(1280, 800));
    expect(bp.size, NxSize.wide);
    expect(bp.useRail, isTrue);
    expect(bp.formMaxWidth, 640);
  });

  testWidgets('Wide 1600 caps content', (tester) async {
    final bp = await pumpBp(tester, const Size(1600, 900));
    expect(bp.size, NxSize.wide);
    expect(bp.contentMaxWidth, 1120);
    expect(bp.formMaxWidth, 640);
  });

  testWidgets('NxSplitView is row on tablet and list-only on phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NxSplitView(
            list: Text('list-pane'),
            detail: Text('detail-pane'),
          ),
        ),
      ),
    );
    expect(find.text('list-pane'), findsOneWidget);
    expect(find.text('detail-pane'), findsNothing);

    tester.view.physicalSize = const Size(768, 1024);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NxSplitView(
            list: Text('list-pane'),
            detail: Text('detail-pane'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('list-pane'), findsOneWidget);
    expect(find.text('detail-pane'), findsOneWidget);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('NxAppHeader page shows title not large hub chrome', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(appBar: NxAppHeader(title: 'สร้างผู้มุ่งหวัง', subtitle: 'บันทึกใหม่')),
      ),
    );
    expect(find.text('สร้างผู้มุ่งหวัง'), findsOneWidget);
    expect(find.text('บันทึกใหม่'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('NxAppHeader hub shows avatar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(appBar: NxAppHeader.hub()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(NxI.bell), findsOneWidget);
  });

  testWidgets('NxAppHeader page shows back when canPop', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(appBar: NxAppHeader(title: 'รายละเอียด')),
                  ),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียด'), findsOneWidget);
    expect(find.byTooltip('กลับ'), findsOneWidget);
  });

  testWidgets('NxAppHeader page shows action circles not overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          appBar: NxAppHeader(
            title: 'ผู้มุ่งหวัง',
            actions: [
              NxAddButton(onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    expect(find.byIcon(NxI.plus), findsOneWidget);
    expect(find.byTooltip('เพิ่มเติม'), findsNothing);
  });

  testWidgets('NxTabNav shows label only on selected tab', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: NxTabNav(
            destinations: const [
              NxTabDestination(
                icon: NxI.squaresFour,
                selectedIcon: NxI.squaresFourFill,
                label: 'แดชบอร์ด',
              ),
              NxTabDestination(
                icon: NxI.magnifyingGlass,
                selectedIcon: NxI.magnifyingGlassFill,
                label: 'ค้นหา',
              ),
            ],
            selectedIndex: 0,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('แดชบอร์ด'), findsOneWidget);
    expect(find.text('ค้นหา'), findsNothing);
    expect(find.byIcon(NxI.squaresFourFill), findsOneWidget);
  });

  testWidgets('NxTabNav selected label on mobile hides others', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: NxTabNav(
            destinations: const [
              NxTabDestination(
                icon: NxI.squaresFour,
                selectedIcon: NxI.squaresFourFill,
                label: 'แดชบอร์ด',
              ),
              NxTabDestination(
                icon: NxI.magnifyingGlass,
                selectedIcon: NxI.magnifyingGlassFill,
                label: 'ค้นหา',
              ),
            ],
            selectedIndex: 0,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('แดชบอร์ด'), findsOneWidget);
    expect(find.text('ค้นหา'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('atmosphere skeleton and CTA render light and dark', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: NxAtmosphere(
              child: Column(
                children: [
                  SizedBox(height: 160, child: NxSkeletonList(rows: 2)),
                  NxHeroCta(label: 'เข้าสู่ระบบ'),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NxAtmosphere), findsOneWidget);
      expect(find.byType(NxBone), findsWidgets);
      expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    }
  });

  testWidgets('onboarding has three steps and primary CTA', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const GettingStartedScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ยินดีต้อนรับ'), findsOneWidget);
    expect(find.text('ถัดไป'), findsOneWidget);
    await tester.tap(find.text('ถัดไป'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('โทนและการเน้นสี'), findsOneWidget);
    await tester.tap(find.text('ถัดไป'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('เข้าสู่แอป'), findsOneWidget);
    expect(find.text('ข้าม'), findsOneWidget);
  });

  testWidgets('Mini to Wide preview pumps tab nav', (tester) async {
    for (final size in [
      const Size(320, 640),
      const Size(390, 844),
      const Size(768, 1024),
      const Size(1280, 800),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: NxTabNav(
              destinations: const [
                NxTabDestination(
                  icon: NxI.squaresFour,
                  selectedIcon: NxI.squaresFourFill,
                  label: 'แดชบอร์ด',
                ),
                NxTabDestination(
                  icon: NxI.magnifyingGlass,
                  selectedIcon: NxI.magnifyingGlassFill,
                  label: 'ค้นหา',
                ),
              ],
              selectedIndex: 0,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(NxTabNav), findsOneWidget);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
