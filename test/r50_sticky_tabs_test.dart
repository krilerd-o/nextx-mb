import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/widgets/nx_scroll_tabs.dart';

void main() {
  testWidgets('sticky tabs appear when the real row scrolls under the header; swipe changes tab', (tester) async {
    final ctrl = ScrollController();
    final anchor = GlobalKey();
    var tab = 0;
    late StateSetter set;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, s) {
        set = s;
        Widget tabs() => NxScrollTabs(labels: const ['สรุป', 'ข้อมูล', 'ประวัติ'], index: tab, onChanged: (i) => set(() => tab = i));
        return Scaffold(
          body: Stack(children: [
            NxSwipeTabs(
              index: tab,
              count: 3,
              onChanged: (i) => set(() => tab = i),
              child: ListView(controller: ctrl, children: [
                const SizedBox(height: 300),
                KeyedSubtree(key: anchor, child: tabs()),
                for (var i = 0; i < 60; i++) SizedBox(height: 60, child: Text('row $i')),
              ]),
            ),
            NxStickyTabs(controller: ctrl, anchorKey: anchor, top: 0, child: tabs()),
          ]),
        );
      }),
    ));
    final sticky = find.byKey(const ValueKey('sticky-tabs'));
    double opacity() => tester.widget<AnimatedOpacity>(find.ancestor(of: sticky, matching: find.byType(AnimatedOpacity))).opacity;
    expect(opacity(), 0);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(opacity(), 1, reason: 'pinned under the header after the row scrolled away');
    await tester.drag(find.byType(ListView), const Offset(0, 1400));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.fling(find.text('row 2'), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(tab, 1, reason: 'swipe left → next tab');
    await tester.fling(find.text('row 2'), const Offset(300, 0), 1200);
    await tester.pumpAndSettle();
    expect(tab, 0);
  });

  testWidgets('pinned copy hides when content above the real row grows without any scroll', (tester) async {
    final ctrl = ScrollController();
    final anchor = GlobalKey();
    var above = 300.0;
    late StateSetter set;
    Widget tabs() => NxScrollTabs(labels: const ['สรุป', 'เอกสาร'], index: 0, onChanged: (_) {});
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, s) {
        set = s;
        return Scaffold(
          body: Stack(children: [
            ListView(controller: ctrl, children: [
              SizedBox(height: above),
              KeyedSubtree(key: anchor, child: tabs()),
              for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('row $i')),
            ]),
            NxStickyTabs(controller: ctrl, anchorKey: anchor, top: 0, child: tabs()),
          ]),
        );
      }),
    ));
    final sticky = find.byKey(const ValueKey('sticky-tabs'));
    double opacity() => tester.widget<AnimatedOpacity>(find.ancestor(of: sticky, matching: find.byType(AnimatedOpacity))).opacity;
    ctrl.jumpTo(320);
    await tester.pumpAndSettle();
    expect(opacity(), 1, reason: 'real row is under the header');
    // A late load makes the content above the row taller: the row comes back into view but no
    // scroll event fires.
    set(() => above = 700);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(opacity(), 0, reason: 'real row visible again → no duplicate pinned copy');
    ctrl.dispose();
  });
}
