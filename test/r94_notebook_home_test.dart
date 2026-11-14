import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/notebook/notebook_models.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/comm_ai/comm_ai_isaac.dart';
import 'package:nextx_mobile/screens/notebook/notebook_book_card.dart';
import 'package:nextx_mobile/screens/notebook/notebook_home_screen.dart';
import 'package:nextx_mobile/services/notebook/notebook_controller.dart';

import 'support/fake_api.dart';
import 'support/notebook_fixtures.dart';

/// Notebook home redesign: no hero card, search from the header icon, book cards in each
/// notebook's colour / icon / cover with pinned first, the appearance picker (create / edit /
/// "ปรับแต่งหน้าปก") sending `appearance`, and the device fallback for servers without it.

const _me = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['ai-assistant']);

Map<String, dynamic> _row(int id, String title, Map<String, dynamic>? look, {int userId = 2, String vis = 'private', bool withKey = true}) {
  final r = nbRow(id, title: title, userId: userId, visibility: vis);
  if (withKey) r['appearance'] = look;
  return r;
}

List<Map<String, dynamic>> _v6Library() => [
      _row(3, 'ข้อมูลสินค้าแอร์ 2569', {'color': 'blue', 'icon': 'package', 'cover': 'book', 'pinned': false}),
      _row(4, 'คู่มือบริการลูกค้า', {'color': 'teal', 'icon': 'headset', 'cover': 'gradient', 'pinned': false}, userId: 9, vis: 'business'),
      _row(5, 'แผนการตลาด', {'color': 'orange', 'icon': 'megaphone', 'cover': 'minimal', 'pinned': true}),
      _row(6, 'นโยบายรับประกัน', null),
    ];

Map<String, dynamic> _body(RequestOptions o) =>
    o.data is Map ? Map<String, dynamic>.from(o.data as Map) : (o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : <String, dynamic>{});

RequestOptions _last(FakeNextxAdapter a, String key) => a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);

Future<void> settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<(FakeNextxAdapter, AppConfig)> _pump(
  WidgetTester tester,
  Map<String, Object?> replies, {
  Size size = const Size(412, 900),
  Brightness brightness = Brightness.light,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  config.debugOverrideSession(_me);
  final adapter = FakeNextxAdapter(replies);
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(theme: AppTheme.themed(brightness: brightness), home: const NotebookHomeScreen()),
  ));
  await settle(tester);
  return (adapter, config);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('appearance model', () {
    test('title hash default matches the web (same keys for the same title)', () {
      expect(notebookTitleHash(''), 0);
      expect(notebookTitleHash('abc'), 96354);
      expect(notebookTitleHash('  สมุดงานขาย  '), notebookTitleHash('สมุดงานขาย'));
      expect(NotebookAppearance.forTitle('abc'), const NotebookAppearance(color: 'teal', icon: 'file_text'));
      expect(kNotebookColors, hasLength(10));
      expect(kNotebookIcons, hasLength(24));
      // Different titles give a varied library.
      final looks = {for (final t in ['ขาย', 'บริการ', 'บัญชี', 'HR', 'การตลาด', 'คลังสินค้า']) NotebookAppearance.forTitle(t).color};
      expect(looks.length, greaterThan(2));
    });

    test('tryParse validates against the allow-lists; round-trips', () {
      expect(NotebookAppearance.tryParse(null), isNull);
      expect(NotebookAppearance.tryParse('nope'), isNull);
      expect(NotebookAppearance.tryParse({'color': '#fff', 'icon': 'skull', 'cover': 'leather'}), const NotebookAppearance());
      expect(NotebookAppearance.tryParse({'color': 'Rose', 'icon': 'map-pin', 'cover': 'gradient', 'pinned': 1}),
          const NotebookAppearance(color: 'rose', icon: 'map_pin', cover: 'gradient', pinned: true));
      const a = NotebookAppearance(color: 'sky', icon: 'headset', cover: 'minimal', pinned: true);
      expect(NotebookAppearance.tryParse(a.toJson()), a);
      expect(NotebookAppearance.tryParse(jsonEncode(a.toJson())), a);
    });

    test('server → device → title; pinned first, stable', () {
      final all = [for (final r in _v6Library()) Notebook.fromJson(r)];
      expect(all.every((n) => n.serverHasAppearance), isTrue);
      expect(all[0].look.color, 'blue');
      expect(all[3].look, NotebookAppearance.forTitle('นโยบายรับประกัน'));
      all[3].localAppearance = const NotebookAppearance(color: 'green', pinned: true);
      expect(all[3].look.color, 'green');
      expect(filterNotebooks(all).map((n) => n.id), ['5', '6', '3', '4']);
      final old = Notebook.fromJson(nbRow(7));
      expect(old.serverHasAppearance, isFalse);
      expect(old.appearance, isNull);
    });
  });

  group('home', () {
    testWidgets('hero card gone; header has search + view toggle + ⋮; chips stay', (tester) async {
      await _pump(tester, {'GET /api/ai/notebooks': {'items': _v6Library()}});
      expect(find.text('ถามไอแซคจากเอกสารของคุณ'), findsNothing);
      expect(find.byType(IsaacAvatar), findsNothing);
      expect(find.byTooltip('ค้นหา'), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-layout-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-home-more')), findsOneWidget);
      expect(find.byKey(const ValueKey('nx-list-search')), findsNothing, reason: 'search box opens from the header icon');
      for (final s in ['all', 'mine', 'shared', 'business']) {
        expect(find.byKey(ValueKey('notebook-scope-$s')), findsOneWidget);
      }
    });

    testWidgets('search icon opens the box and filters live; closing clears', (tester) async {
      await _pump(tester, {'GET /api/ai/notebooks': {'items': _v6Library()}});
      await tester.tap(find.byTooltip('ค้นหา'));
      await settle(tester);
      expect(find.byKey(const ValueKey('nx-list-search')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('nx-list-search')), 'ตลาด');
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-card-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-card-3')), findsNothing);
      await tester.tap(find.byTooltip('ปิดค้นหา'));
      await settle(tester);
      expect(find.byKey(const ValueKey('nx-list-search')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-card-3')), findsOneWidget);
    });

    testWidgets('cards: colour, icon, cover, pin mark; pinned first', (tester) async {
      await _pump(tester, {'GET /api/ai/notebooks': {'items': _v6Library()}});
      final cards = tester.widgetList<NotebookBookCard>(find.byType(NotebookBookCard)).toList();
      expect(cards.map((c) => c.key), [const ValueKey('notebook-card-5'), const ValueKey('notebook-card-3'), const ValueKey('notebook-card-4'), const ValueKey('notebook-card-6')]);
      expect(cards.first.info.look, const NotebookAppearance(color: 'orange', icon: 'megaphone', cover: 'minimal', pinned: true));
      expect(cards[2].info.look.cover, 'gradient');
      expect(find.byKey(const ValueKey('notebook-pin-mark')), findsOneWidget);
      // The icon is drawn in the notebook's colour.
      final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('notebook-card-3')), matching: find.byIcon(kNotebookIcons['package']!)));
      expect(icon.color, kNotebookColors.firstWhere((c) => c.key == 'blue').light);
      // Title-hash default for the notebook with no appearance.
      expect(cards.last.info.look, NotebookAppearance.forTitle('นโยบายรับประกัน'));
      // List view keeps the same look.
      await tester.tap(find.byTooltip('แสดงเป็นรายการ'));
      await settle(tester);
      expect(find.byType(NotebookListCard), findsNWidgets(4));
      expect(find.byType(NotebookMiniBook), findsNWidgets(4));
    });

    testWidgets('create sheet: picker updates the preview and create sends appearance', (tester) async {
      final (adapter, _) = await _pump(tester, {
        'GET /api/ai/notebooks': {'items': _v6Library()},
        'POST /api/ai/notebooks': {'item': _row(9, 'คู่มือช่าง', {'color': 'amber', 'icon': 'wrench', 'cover': 'gradient', 'pinned': true})},
        'GET /api/ai/notebooks/9': {'item': _row(9, 'คู่มือช่าง', null)},
      });
      await tester.tap(find.byKey(const ValueKey('notebook-create')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('notebook-title-field')), 'คู่มือช่าง');
      await settle(tester);
      NotebookAppearance preview() => tester.widget<NotebookBookCard>(find.byKey(const ValueKey('notebook-preview-card'))).info.look;
      expect(preview(), NotebookAppearance.forTitle('คู่มือช่าง'), reason: 'new book follows its title until picked');
      await tester.tap(find.byKey(const ValueKey('notebook-color-amber')));
      await settle(tester);
      expect(preview().color, 'amber');
      await tester.ensureVisible(find.byKey(const ValueKey('notebook-icon-wrench')));
      await tester.tap(find.byKey(const ValueKey('notebook-icon-wrench')));
      await settle(tester);
      expect(preview().icon, 'wrench');
      await tester.ensureVisible(find.text('ไล่สี').last);
      await settle(tester);
      await tester.tap(find.text('ไล่สี').last);
      await settle(tester);
      expect(preview().cover, 'gradient');
      await tester.ensureVisible(find.byKey(const ValueKey('notebook-pin-switch')));
      await tester.tap(find.byKey(const ValueKey('notebook-pin-switch')));
      await settle(tester);
      expect(preview(), const NotebookAppearance(color: 'amber', icon: 'wrench', cover: 'gradient', pinned: true));
      await tester.ensureVisible(find.byKey(const ValueKey('notebook-edit-save')));
      await tester.tap(find.byKey(const ValueKey('notebook-edit-save')));
      await settle(tester);
      expect(_body(_last(adapter, 'POST /api/ai/notebooks'))['appearance'], {'color': 'amber', 'icon': 'wrench', 'cover': 'gradient', 'pinned': true});
    });

    testWidgets('long-press → ปรับแต่งหน้าปก → PATCH {appearance}; pin toggle', (tester) async {
      final (adapter, _) = await _pump(tester, {
        'GET /api/ai/notebooks': {'items': _v6Library()},
        'PATCH /api/ai/notebooks/3': {'item': _row(3, 'ข้อมูลสินค้าแอร์ 2569', {'color': 'rose', 'icon': 'package', 'cover': 'book', 'pinned': false})},
      });
      await tester.longPress(find.byKey(const ValueKey('notebook-card-3')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-menu-appearance')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-color-rose')));
      await settle(tester);
      expect(tester.widget<NotebookBookCard>(find.byKey(const ValueKey('notebook-preview-card'))).info.look.color, 'rose');
      await tester.ensureVisible(find.byKey(const ValueKey('notebook-appearance-save')));
      await tester.tap(find.byKey(const ValueKey('notebook-appearance-save')));
      await settle(tester);
      expect(_body(_last(adapter, 'PATCH /api/ai/notebooks/3')), {'appearance': {'color': 'rose', 'icon': 'package', 'cover': 'book', 'pinned': false}});
      expect(tester.widget<NotebookBookCard>(find.byKey(const ValueKey('notebook-card-3'))).info.look.color, 'rose');

      await tester.longPress(find.byKey(const ValueKey('notebook-card-3')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-menu-pin')));
      await settle(tester);
      expect(_body(_last(adapter, 'PATCH /api/ai/notebooks/3'))['appearance'], {'color': 'rose', 'icon': 'package', 'cover': 'book', 'pinned': true});
    });

    testWidgets('read-only shared notebook: no cover / pin items', (tester) async {
      await _pump(tester, {
        'GET /api/ai/notebooks': {
          'items': [{..._row(4, 'คู่มือบริการลูกค้า', null, userId: 9, vis: 'business'), 'can_write': false}],
        },
      });
      await tester.longPress(find.byKey(const ValueKey('notebook-card-4')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-menu-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-menu-appearance')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-menu-pin')), findsNothing);
    });

    testWidgets('old server (no appearance): title default, pick kept on the device and shown after reload', (tester) async {
      final old = [for (final r in nbLibrary()) Map<String, dynamic>.from(r)];
      final (adapter, config) = await _pump(tester, {
        'GET /api/ai/notebooks': {'items': old},
        'PATCH /api/ai/notebooks/6': {'item': nbRow(6, title: 'นโยบายรับประกัน', sources: 1)},
      });
      final card6 = tester.widget<NotebookBookCard>(find.byKey(const ValueKey('notebook-card-6')));
      expect(card6.info.look, NotebookAppearance.forTitle('นโยบายรับประกัน'));

      final c = NotebookLibraryController(config.apiClient, meId: '2', prefsScope: config.businessScope);
      await tester.runAsync(c.load);
      const pick = NotebookAppearance(color: 'green', icon: 'shield', cover: 'minimal', pinned: true);
      await tester.runAsync(() => c.setAppearance(c.items.firstWhere((n) => n.id == '6'), pick));
      expect(_body(_last(adapter, 'PATCH /api/ai/notebooks/6'))['appearance'], pick.toJson(), reason: 'always sent');
      expect(c.items.firstWhere((n) => n.id == '6').look, pick);
      expect(c.visible.first.id, '6', reason: 'pinned on the device → first');
      final stored = await tester.runAsync(() => NotebookAppearanceStore.load(config.businessScope));
      expect(stored!['6'], pick);

      // A fresh controller (app restart) shows the device pick again.
      final again = NotebookLibraryController(config.apiClient, meId: '2', prefsScope: config.businessScope);
      await tester.runAsync(again.load);
      expect(again.items.firstWhere((n) => n.id == '6').look, pick);
      // Another business does not see it.
      final other = await tester.runAsync(() => NotebookAppearanceStore.load('${config.businessScope}x'));
      expect(other, isEmpty);
    });

    testWidgets('v6 server stores it: no device copy kept', (tester) async {
      final (_, config) = await _pump(tester, {
        'GET /api/ai/notebooks': {'items': _v6Library()},
        'PATCH /api/ai/notebooks/6': {'item': _row(6, 'นโยบายรับประกัน', {'color': 'green', 'icon': 'shield', 'cover': 'book', 'pinned': false})},
      });
      final c = NotebookLibraryController(config.apiClient, meId: '2', prefsScope: config.businessScope);
      await tester.runAsync(c.load);
      await tester.runAsync(() => c.setAppearance(c.items.firstWhere((n) => n.id == '6'), const NotebookAppearance(color: 'green', icon: 'shield')));
      final n6 = c.items.firstWhere((n) => n.id == '6');
      expect(n6.appearance?.color, 'green');
      expect(n6.localAppearance, isNull);
      final stored = await tester.runAsync(() => NotebookAppearanceStore.load(config.businessScope));
      expect(stored, isEmpty);
    });

    for (final width in [360.0, 1180.0]) {
      testWidgets('dark mode, ${width.toInt()} px: grid + list + picker without overflow', (tester) async {
        final lib = [
          ..._v6Library(),
          _row(10, 'ชื่อสมุดที่ยาวมาก ๆ เพื่อทดสอบการตัดบรรทัดของการ์ดในโหมดมืดและจอแคบ', {'color': 'slate', 'icon': 'scale', 'cover': 'gradient', 'pinned': true}, vis: 'business'),
        ];
        await _pump(tester, {'GET /api/ai/notebooks': {'items': lib}}, size: Size(width, 800), brightness: Brightness.dark);
        expect(tester.takeException(), isNull);
        expect(find.byType(NotebookBookCard), findsWidgets);
        final y = tester.getTopLeft(find.byKey(const ValueKey('notebook-card-10'))).dy;
        final firstRow = find.byType(NotebookBookCard).evaluate().where((e) => tester.getTopLeft(find.byWidget(e.widget)).dy == y).length;
        expect(firstRow, width > 1000 ? greaterThanOrEqualTo(4) : 2, reason: 'tablet widths show more columns');
        await tester.tap(find.byTooltip('แสดงเป็นรายการ'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('แสดงเป็นกริด'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('notebook-create')));
        await settle(tester);
        expect(find.byType(NotebookAppearancePicker), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
