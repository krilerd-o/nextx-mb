import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/workspace_models.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/screens/workspace/ws_detail_parts.dart';
import 'package:nextx_mobile/widgets/nx_status_stepper.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget w, {double width = 400}) async {
    tester.view.physicalSize = Size(width, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));
    await tester.pumpAndSettle();
  }

  Color bgOf(WidgetTester tester, String key) =>
      tester.widget<Material>(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(Material)).first).color!;

  testWidgets('web-style bar: joined arrow steps that share the width, numbered', (tester) async {
    await pump(tester, const NxStatusStepper(steps: [NxStep(id: 'a', label: 'A'), NxStep(id: 'b', label: 'B'), NxStep(id: 'c', label: 'C')], current: 1));
    final a = tester.getRect(find.byKey(const ValueKey('nx-step-a')));
    final b = tester.getRect(find.byKey(const ValueKey('nx-step-b')));
    final c = tester.getRect(find.byKey(const ValueKey('nx-step-c')));
    expect(a.height, NxStatusStepper.pillHeight);
    expect(b.left, closeTo(a.right - NxStatusStepper.overlap, 0.5), reason: 'steps overlap into one bar');
    final bar = tester.getRect(find.byKey(const ValueKey('nx-status-bar')));
    expect(c.right, closeTo(bar.right - 4 - 1, 1.5), reason: 'fills the width when it fits');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(ClipPath), findsNWidgets(3));
  });

  testWidgets('passed green, current blue, later grey; done status green; tap calls onPick', (tester) async {
    int? picked;
    await pump(
      tester,
      EntityStatusStepper(
        options: const [(value: 'new', label: 'ใหม่'), (value: 'contacted', label: 'ติดต่อแล้ว'), (value: 'won', label: 'ปิดการขาย')],
        current: 'contacted',
        onSelect: (v) => picked = v == 'won' ? 2 : 0,
      ),
    );
    expect(bgOf(tester, 'step-new'), const Color(0xFFD1FAE5));
    expect(bgOf(tester, 'step-contacted'), const Color(0xFFDBEAFE));
    expect(bgOf(tester, 'step-won'), const Color(0xFFF1F5F9));
    expect(find.byKey(const ValueKey('step-done-new')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-done-contacted')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('step-won')));
    expect(picked, 2);
    // The last (final) status as current reads as finished.
    await pump(
      tester,
      EntityStatusStepper(
        options: const [(value: 'new', label: 'ใหม่'), (value: 'won', label: 'ปิดการขาย')],
        current: 'won',
        onSelect: (_) {},
      ),
    );
    expect(bgOf(tester, 'step-won'), const Color(0xFFD1FAE5));
  });

  testWidgets('ยกเลิก is a red capsule pinned after the bar; cancelled turns the bar red', (tester) async {
    final statuses = [
      for (final r in [
        {'id': 1, 'name': 'in_progress', 'label_th': 'กำลังทำ', 'sequence': 1},
        {'id': 2, 'name': 'review', 'label_th': 'รอประเมิน', 'sequence': 2},
        {'id': 3, 'name': 'done', 'label_th': 'เสร็จแล้ว', 'sequence': 3, 'is_done': 1},
        {'id': 4, 'name': 'cancelled', 'label_th': 'ยกเลิก', 'sequence': 4},
      ])
        WsStatus(r),
    ];
    WsStatus? picked;
    await pump(tester, WsStatusStepper(statuses: statuses, current: '1', onPick: (s) => picked = s));
    expect(find.byType(NxCancelStage), findsOneWidget);
    final cancel = tester.getRect(find.byKey(const ValueKey('ws-step-4')));
    final steps = tester.getRect(find.byType(SingleChildScrollView));
    expect(cancel.left, greaterThan(steps.right), reason: 'set apart after the bar');
    expect(cancel.right, lessThanOrEqualTo(400), reason: 'always in view');
    await tester.tap(find.byKey(const ValueKey('ws-step-4')));
    expect(picked?.id, '4', reason: 'tapping still goes through the caller (confirm sheet)');

    await pump(tester, WsStatusStepper(statuses: statuses, current: '4', onPick: (_) {}));
    expect(bgOf(tester, 'ws-step-1'), const Color(0xFFFEF2F2));
    expect(tester.widget<NxCancelStage>(find.byType(NxCancelStage)).active, isTrue);
  });

  test('cancel statuses are recognised', () {
    expect(isCancelStatus('Cancelled', 'ยกเลิก'), isTrue);
    expect(isCancelStatus('cancel', 'Cancel'), isTrue);
    expect(isCancelStatus('Closed', 'ปิดเคส'), isFalse);
    expect(isCancelStatus('Cancellation Review', 'ตรวจสอบ'), isFalse);
  });

  testWidgets('too many steps: the bar scrolls and the current step is brought into view; capsule stays visible', (tester) async {
    await pump(
      tester,
      NxStatusStepper(steps: [for (var i = 0; i < 12; i++) NxStep(id: '$i', label: 'สถานะยาว $i'), const NxStep(id: 'x', label: 'ยกเลิก', isCancel: true)], current: 10),
    );
    final x = tester.getCenter(find.byKey(const ValueKey('nx-step-10'))).dx;
    expect(x, inInclusiveRange(0, 400));
    final cap = tester.getRect(find.byKey(const ValueKey('nx-step-x')));
    expect(cap.right, lessThanOrEqualTo(400));
  });
}
