import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/widgets/nx_app_header.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

void main() {
  testWidgets('content runs under the floating header; topInset covers status bar + header', (tester) async {
    double? inset;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(top: 24)),
        child: NxScrollScaffold(
          insetBody: false,
          header: const NxAppHeader(title: 'หัว'),
          body: Builder(builder: (context) {
            inset = NxScrollScaffold.topInset(context);
            return ListView(padding: EdgeInsets.only(top: inset!), children: const [Text('แถวแรก')]);
          }),
        ),
      ),
    ));
    // 24 status bar + 56 header.
    expect(inset, 80);
    expect(tester.getTopLeft(find.text('แถวแรก')).dy, greaterThanOrEqualTo(80));
    // Header has no solid fill when floating.
    final m = tester.widget<Material>(find.descendant(of: find.byType(NxAppHeader), matching: find.byType(Material)).first);
    expect(m.color, Colors.transparent);
  });

  testWidgets('inset mode keeps body below the header without extra padding', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const NxScrollScaffold(header: NxAppHeader(title: 'หัว'), body: Text('เนื้อหา')),
    ));
    expect(tester.getTopLeft(find.text('เนื้อหา')).dy, greaterThanOrEqualTo(56));
  });

  testWidgets('motion blur is off below the full effects level', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() => Effects.setPreference(EffectsPreference.lite));
    await tester.pumpWidget(const MaterialApp(home: NxMotionBlur(child: SizedBox())));
    expect(find.byType(ImageFiltered), findsNothing);
    await tester.runAsync(() => Effects.setPreference(EffectsPreference.auto));
  });
}
