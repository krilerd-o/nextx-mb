import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/activity_guests.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/calendar/activity_detail_screen.dart';
import 'package:nextx_mobile/screens/calendar/activity_form_screen.dart';
import 'package:nextx_mobile/screens/calendar/activity_outcome_notes.dart';
import 'package:nextx_mobile/widgets/nx_scroll_tabs.dart';

import 'support/fake_api.dart';

List<Map<String, dynamic>> _photos(int n) => [
      for (var i = 0; i < n; i++) {'id': 'p$i', 'name': 'p$i.jpg', 'path': 'b/1/activity/5/p$i.jpg', 'url': '/uploads/b/1/activity/5/p$i.jpg', 'mime': 'image/jpeg'},
    ];

AppConfig _config(FakeNextxAdapter adapter) {
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['calendar']));
  config.apiClient.debugSetHttpAdapter(adapter);
  return config;
}

Future<void> _open(WidgetTester tester, FakeNextxAdapter adapter, Widget home) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: _config(adapter), child: MaterialApp(home: home)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

FakeNextxAdapter _adapter({Map<String, dynamic> row = const {}, int photos = 8}) => FakeNextxAdapter({
      'GET /api/entity/activity/5': {'id': 5, 'subject': '[QA] นัดลูกค้า', 'status': 'In Progress', 'activitytype': 'Visit', ...row},
      'GET /api/entity/activity/5/comments': {'list': []},
      'GET /api/activity/5/visit': {'checked_in': false, 'photos': _photos(photos)},
      'DELETE /api/activity/5/photos/p0': {'list': _photos(photos).skip(1).toList()},
      'DELETE /api/activity/5/photos/p2': {'list': [for (final p in _photos(photos)) if (p['id'] != 'p2') p]},
      'PUT /api/entity/activity/5': {'id': 5},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Visit is "เข้าพบ"; statuses use the web Thai labels', () {
    expect(activityTypeLabel('Visit'), 'เข้าพบลูกค้า');
    expect(activityStatusLabel('In Progress'), 'กำลังดำเนินการ');
    expect(activityStatusLabel('Planned'), 'วางแผน');
    expect(activityStatusLabel('Completed'), 'เสร็จสิ้น');
    expect(activityStatusLabel('Cancelled'), 'ยกเลิก');
    expect(activityStatusLabel('in progress'), 'กำลังดำเนินการ');
    expect(activityStatusLabel('Whatever'), 'Whatever');
    L10n.set('en');
    addTearDown(() => L10n.set('th'));
    expect(activityStatusLabel('In Progress'), 'In Progress');
    expect(tr('เข้าพบลูกค้า'), 'Visit');
    expect(tr('การเข้าพบ'), 'Visit');
  });

  testWidgets('detail: "การเข้าพบ" header, Thai status, 5 photos per row', (tester) async {
    final adapter = _adapter();
    await _open(tester, adapter, const ActivityDetailScreen(row: {'id': 5}));
    expect(find.text('การเข้าพบ'), findsOneWidget);
    expect(find.text('การเยี่ยม'), findsNothing);
    expect(find.text('กำลังดำเนินการ'), findsOneWidget);
    expect(find.text('In Progress'), findsNothing);
    expect(find.text('รูปถ่าย (8)'), findsOneWidget);
    final y0 = tester.getTopLeft(find.byKey(const ValueKey('visit-photo-0'))).dy;
    final y4 = tester.getTopLeft(find.byKey(const ValueKey('visit-photo-4'))).dy;
    final y5 = tester.getTopLeft(find.byKey(const ValueKey('visit-photo-5'))).dy;
    expect(y4, y0, reason: '5 thumbnails share the first row');
    expect(y5, greaterThan(y0), reason: 'the 6th starts the second row');
  });

  testWidgets('long-press a photo → ลบรูป → confirm → DELETE; cancel keeps it', (tester) async {
    final adapter = _adapter();
    await _open(tester, adapter, const ActivityDetailScreen(row: {'id': 5}));
    await tester.longPress(find.byKey(const ValueKey('visit-photo-0')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('visit-photo-action-delete')));
    await _settle(tester);
    expect(find.text('ลบรูปนี้?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('visit-photo-delete-cancel')));
    await _settle(tester);
    expect(adapter.callKeys.where((k) => k.startsWith('DELETE')), isEmpty);

    await tester.longPress(find.byKey(const ValueKey('visit-photo-0')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('visit-photo-action-delete')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('visit-photo-delete-confirm')));
    await _settle(tester);
    expect(adapter.callKeys, contains('DELETE /api/activity/5/photos/p0'));
    expect(find.text('รูปถ่าย (7)'), findsOneWidget);
    expect(find.text('ลบรูปแล้ว'), findsOneWidget);
  });

  testWidgets('full-screen viewer has a trash button that deletes the shown photo', (tester) async {
    final adapter = _adapter();
    await _open(tester, adapter, const ActivityDetailScreen(row: {'id': 5}));
    await tester.tap(find.byKey(const ValueKey('visit-photo-2')));
    await _settle(tester);
    expect(find.text('3 / 8'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('image-delete')));
    await _settle(tester);
    expect(find.text('ลบรูปนี้?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('visit-photo-delete-confirm')));
    await _settle(tester);
    expect(adapter.callKeys, contains('DELETE /api/activity/5/photos/p2'));
    expect(find.text('3 / 7'), findsOneWidget, reason: 'the viewer drops the deleted photo');
  });

  testWidgets('outcome chips: tap → input card → auto-save → card; chip goes away', (tester) async {
    final adapter = _adapter(photos: 0);
    await _open(tester, adapter, const ActivityDetailScreen(row: {'id': 5}));
    for (final f in ['outcome_summary', 'next_step', 'remark']) {
      expect(find.byKey(ValueKey('outcome-chip-$f')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('outcome-chip-outcome_summary')));
    await _settle(tester, 4);
    expect(find.text('ลูกค้าสนใจอะไร ตกลงอะไรกันบ้าง'), findsOneWidget);
    expect(find.byKey(const ValueKey('outcome-chip-outcome_summary')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('outcome-field-outcome_summary')), 'ลูกค้าสนใจแพ็กเกจ B');
    await tester.pump(const Duration(milliseconds: 300));
    expect(adapter.callKeys.where((k) => k.startsWith('PUT')), isEmpty, reason: 'waits until typing stops');
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester, 4);
    final put = adapter.calls.lastWhere((c) => c.method == 'PUT' && c.path == '/api/entity/activity/5');
    expect(Map<String, dynamic>.from(put.data as Map), {'outcome_summary': 'ลูกค้าสนใจแพ็กเกจ B'});
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('outcome-done-outcome_summary')));
    await _settle(tester, 4);
    expect(find.byKey(const ValueKey('outcome-card-outcome_summary')), findsOneWidget);
    expect(find.text('ลูกค้าสนใจแพ็กเกจ B'), findsOneWidget);
    expect(find.byKey(const ValueKey('outcome-chip-outcome_summary')), findsNothing);
    expect(find.byKey(const ValueKey('outcome-chip-next_step')), findsOneWidget);
  });

  testWidgets('typing then leaving the overview tab still saves the text', (tester) async {
    final adapter = _adapter(photos: 0);
    await _open(tester, adapter, const ActivityDetailScreen(row: {'id': 5}));
    await tester.tap(find.byKey(const ValueKey('outcome-chip-remark')));
    await _settle(tester, 4);
    await tester.enterText(find.byKey(const ValueKey('outcome-field-remark')), 'ระวังที่จอดรถ');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('detail-tab-1')).first);
    await _settle(tester);
    final put = adapter.calls.lastWhere((c) => c.method == 'PUT' && c.path == '/api/entity/activity/5');
    expect(Map<String, dynamic>.from(put.data as Map), {'remark': 'ระวังที่จอดรถ'});
    await tester.tap(find.byKey(const ValueKey('detail-tab-0')).first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('outcome-card-remark')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a filled next step shows as a card with "สร้างนัดหมายต่อ" → prefilled form', (tester) async {
    final adapter = _adapter(photos: 0, row: {
      'next_step': 'ส่งใบเสนอราคา\nภายในศุกร์นี้',
      'remark': 'ติดต่อคุณเอ',
      'related_module': 'lead',
      'related_id': 7,
      'customer_name': '[QA] Lead',
      'location': 'สยาม',
    });
    await _open(tester, adapter, const ActivityDetailScreen(row: {'id': 5}));
    expect(find.byKey(const ValueKey('outcome-card-next_step')), findsOneWidget);
    expect(find.byKey(const ValueKey('outcome-card-remark')), findsOneWidget);
    expect(find.byKey(const ValueKey('outcome-chip-next_step')), findsNothing);
    expect(find.byKey(const ValueKey('outcome-chip-outcome_summary')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('outcome-followup')));
    await _settle(tester);
    expect(find.byType(ActivityFormScreen), findsOneWidget);
    expect(find.text('สร้างนัดหมายต่อ'), findsWidgets);
    expect(find.widgetWithText(TextField, 'ส่งใบเสนอราคา'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'สยาม'), findsOneWidget);
  });

  test('follow-up seed keeps customer and place, titles with the first line', () {
    final seed = activityFollowUpSeed({'subject': 'นัดแรก', 'related_module': 'lead', 'related_id': 7, 'location': 'สยาม', 'status': 'Completed', 'id': 5}, 'โทรตาม\nรายละเอียด');
    expect(seed['subject'], 'โทรตาม');
    expect(seed['related_id'], 7);
    expect(seed['location'], 'สยาม');
    expect(seed.containsKey('id'), isFalse);
    expect(seed.containsKey('status'), isFalse);
    expect(seed['description'], contains('ต่อจากนัด: นัดแรก'));
  });

  testWidgets('tab bar keeps 44 px but gives the selected pill room for its shadow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: NxScrollTabs(labels: const ['ภาพรวม', 'คอมเม้นท์', 'ไฟล์', 'ประวัติ'], index: 0, onChanged: (_) {})),
      ),
    ));
    expect(tester.getSize(find.byType(NxScrollTabs)).height, NxScrollTabs.height);
    expect(tester.getSize(find.byKey(const ValueKey('nx-tabs-track'))).height, NxScrollTabs.height);
    // The TabBar (and its clipping scroll view) reaches past the track.
    final bar = tester.getRect(find.byType(TabBar));
    final track = tester.getRect(find.byKey(const ValueKey('nx-tabs-track')));
    expect(bar.top, lessThan(track.top - 6));
    expect(bar.bottom, greaterThan(track.bottom + 6));
    // The pill itself stays inside the track (4 px inset).
    final tab = tester.getRect(find.byKey(const ValueKey('nx-tab-0')));
    expect(tab.top, greaterThanOrEqualTo(track.top + 4 - 0.01));
    expect(tab.bottom, lessThanOrEqualTo(track.bottom - 4 + 0.01));
    var tapped = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: NxScrollTabs(labels: const ['ภาพรวม', 'คอมเม้นท์'], index: 0, onChanged: (i) => tapped = i)),
      ),
    ));
    await tester.tap(find.text('คอมเม้นท์'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
