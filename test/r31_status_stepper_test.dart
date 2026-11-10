import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/widgets/nx_status_stepper.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));
    await tester.pumpAndSettle();
  }

  testWidgets('room above/below the pills so the current shadow is not cut', (tester) async {
    await pump(tester, const NxStatusStepper(steps: [NxStep(id: 'a', label: 'A'), NxStep(id: 'b', label: 'B')], current: 1));
    final row = tester.getSize(find.byType(NxStatusStepper));
    final pill = tester.getSize(find.byKey(const ValueKey('nx-step-b')));
    expect(pill.height, NxStatusStepper.pillHeight);
    expect(row.height - pill.height, greaterThanOrEqualTo(14));
    final list = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(list.clipBehavior, Clip.none);
  });

  testWidgets('CRM stepper uses the Workspace style: lines between steps, green up to the current', (tester) async {
    await pump(
      tester,
      EntityStatusStepper(
        options: const [(value: 'new', label: 'ใหม่'), (value: 'contacted', label: 'ติดต่อแล้ว'), (value: 'won', label: 'ปิดการขาย')],
        current: 'contacted',
        onSelect: (_) {},
      ),
    );
    final lines = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth == 10 && c.constraints?.maxHeight == 2)
        .toList();
    expect(lines.length, 2);
    expect(lines.first.color, kNxStepPassedGreen.withValues(alpha: 0.7));
    expect(find.byKey(const ValueKey('step-done-new')), findsOneWidget);
  });

  testWidgets('the current step is scrolled into view', (tester) async {
    await pump(
      tester,
      NxStatusStepper(steps: [for (var i = 0; i < 12; i++) NxStep(id: '$i', label: 'สถานะยาว $i')], current: 10),
    );
    final x = tester.getCenter(find.byKey(const ValueKey('nx-step-10'))).dx;
    expect(x, inInclusiveRange(0, 400));
  });
}
