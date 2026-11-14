// Performance round: "เบา" (lite) must be cheap to draw on low-end Android, "เต็ม" keeps the look.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBackdropFilter;
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/screens/dashboard/home_boxes.dart' show homeCardDecoration;
import 'package:nextx_mobile/screens/dashboard/home_hero.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';
import 'package:nextx_mobile/widgets/nx_surface_card.dart';
import 'package:nextx_mobile/widgets/nx_ui_scale.dart';

/// [Effects.preference] is read at build time: tests pump an empty tree in between so the
/// next (often const) tree is really rebuilt.
Future<void> _with(WidgetTester tester, EffectsPreference pref, Future<void> Function() body) async {
  await tester.pumpWidget(const SizedBox());
  final before = Effects.preference.value;
  Effects.preference.value = pref;
  try {
    await body();
  } finally {
    Effects.preference.value = before;
  }
}

void main() {
  group('no live blur in lite', () {
    testWidgets('edge blur (header / tab bar band): wash only in lite, blur ramp in full', (tester) async {
      Future<int> filters(EffectsPreference p) async {
        late int n;
        await _with(tester, p, () async {
          await tester.pumpWidget(const MaterialApp(home: SizedBox(height: 120, child: NxEdgeBlur(fromTop: false, solidFraction: 0.5))));
          n = find.byType(BackdropFilter).evaluate().length;
        });
        return n;
      }

      expect(await filters(EffectsPreference.lite), 0);
      expect(await filters(EffectsPreference.off), 0);
      expect(await filters(EffectsPreference.full), greaterThan(1));
    });

    testWidgets('hero glass buttons: blur only on full, and grouped', (tester) async {
      Widget button() => MaterialApp(
            home: BackdropGroup(child: Scaffold(body: Center(child: HeroGlassButton(icon: Icons.search, onTap: (_) {})))),
          );
      await _with(tester, EffectsPreference.lite, () async {
        await tester.pumpWidget(button());
        expect(find.byType(BackdropFilter), findsNothing);
      });
      await _with(tester, EffectsPreference.full, () async {
        await tester.pumpWidget(button());
        // BackdropFilter.grouped: the render object takes the app's shared BackdropGroup key.
        final ro = tester.renderObject<RenderBackdropFilter>(find.byType(BackdropFilter));
        expect(ro.backdropKey, isNotNull, reason: 'grouped blurs share one backdrop capture');
      });
    });

    testWidgets('hero fades into the page with a gradient overlay, not a ShaderMask', (tester) async {
      for (final p in [EffectsPreference.lite, EffectsPreference.full]) {
        await _with(tester, p, () async {
          await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 420, child: HomeHero(now: DateTime(2026, 11, 14, 9))))));
          expect(find.byType(ShaderMask), findsNothing, reason: '$p');
          expect(find.byKey(const ValueKey('home-hero-fade')), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        });
      }
    });
  });

  group('cheaper cards in lite', () {
    testWidgets('NxSurfaceCard: one small shadow + hard-edge clip in lite; full keeps two + anti-alias', (tester) async {
      Future<BoxDecoration> deco(EffectsPreference p) async {
        late BoxDecoration d;
        await _with(tester, p, () async {
          await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NxSurfaceCard(child: Text('x')))));
          final c = tester.widget<Container>(find.descendant(of: find.byType(NxSurfaceCard), matching: find.byType(Container)).first);
          d = c.decoration! as BoxDecoration;
          expect(c.clipBehavior, p == EffectsPreference.full ? Clip.antiAlias : Clip.hardEdge);
        });
        return d;
      }

      expect((await deco(EffectsPreference.lite)).boxShadow, hasLength(1));
      expect((await deco(EffectsPreference.lite)).boxShadow!.single.blurRadius, lessThanOrEqualTo(8));
      expect((await deco(EffectsPreference.full)).boxShadow, NxSurfaceCard.shadows(false));
    });

    testWidgets('Home card: no 30px shadow in lite', (tester) async {
      late BoxDecoration lite, full;
      Widget probe(void Function(BoxDecoration) out) => MaterialApp(home: Builder(builder: (c) {
            out(homeCardDecoration(c));
            return const SizedBox();
          }));
      await _with(tester, EffectsPreference.lite, () => tester.pumpWidget(probe((d) => lite = d)));
      await _with(tester, EffectsPreference.full, () => tester.pumpWidget(probe((d) => full = d)));
      expect(lite.boxShadow, hasLength(1));
      expect(lite.boxShadow!.every((s) => s.blurRadius <= 10), isTrue);
      expect(full.boxShadow!.any((s) => s.blurRadius >= 30), isTrue, reason: 'full keeps the soft wide shadow');
    });
  });

  group('auto effects level', () {
    EffectsLevel android({int cores = 8, int ram = 8192, int sdk = 34, bool low = false}) =>
        Effects.detect(web: false, platform: TargetPlatform.android, cores: cores, ramMb: ram, androidSdk: sdk, lowRamFlag: low);

    test('Android: lite on ≤ 4 cores, < 6 GB RAM, Android < 12 or the low-RAM flag', () {
      expect(android(), EffectsLevel.full);
      expect(android(cores: 4), EffectsLevel.lite);
      expect(android(ram: 4096), EffectsLevel.lite, reason: 'an 8-core phone with 4 GB RAM still stutters');
      expect(android(ram: 5900), EffectsLevel.lite);
      expect(android(ram: 6 * 1024), EffectsLevel.full);
      expect(android(sdk: 30), EffectsLevel.lite);
      expect(android(low: true), EffectsLevel.lite);
      expect(android(ram: 0, sdk: 0, cores: 0), EffectsLevel.full, reason: 'unknown values never count against the device');
    });

    test('iOS: lite only on 2 GB models; web always lite', () {
      expect(Effects.detect(web: false, platform: TargetPlatform.iOS, ramMb: 2048), EffectsLevel.lite);
      expect(Effects.detect(web: false, platform: TargetPlatform.iOS, ramMb: 4096), EffectsLevel.full);
      expect(Effects.detect(web: true, platform: TargetPlatform.android), EffectsLevel.lite);
    });

    test('init with low-RAM specs → auto resolves to lite; new installs still start on lite', () async {
      await Effects.init(specs: const DeviceSpecs(cores: 8, ramMb: 4096, androidSdk: 33));
      // The host running the tests is not Android; check the rule through detect + resolve.
      final level = Effects.detect(web: false, platform: TargetPlatform.android, cores: 8, ramMb: 4096, androidSdk: 33);
      Effects.deviceDefault = level;
      expect(Effects.resolve(EffectsPreference.auto), EffectsLevel.lite);
      expect(Effects.preference.value, EffectsPreference.lite);
    });
  });

  testWidgets('NxUiScale builds the scaled theme once per (theme, scale), not per MediaQuery change', (tester) async {
    final themes = <ThemeData>[];
    Widget app(EdgeInsets insets) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(viewInsets: insets),
            child: NxUiScale(
              scale: 1.1,
              child: Builder(builder: (c) {
                themes.add(Theme.of(c));
                return const SizedBox();
              }),
            ),
          ),
        );
    await tester.pumpWidget(app(EdgeInsets.zero));
    for (var i = 1; i <= 5; i++) {
      await tester.pumpWidget(app(EdgeInsets.only(bottom: i * 40.0))); // keyboard sliding in
    }
    expect(themes.toSet().length, 1, reason: 'the same ThemeData object every frame');
    expect(themes.first.iconTheme.size, closeTo(24 * 1.1, 1e-9));
  });
}
