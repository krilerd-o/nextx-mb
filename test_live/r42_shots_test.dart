// Manual tools (not part of `flutter test`); they use the same test-only hooks as test/.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Screenshots of the Subtask list sort + bulk dock (manual): SHOTS_DIR=… flutter test test_live/r42_shots_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/workspace/task_detail_screen.dart';

import '../test/support/fake_api.dart';

final _out = Platform.environment['SHOTS_DIR'] ?? '/tmp';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

void main() {
  setUpAll(() async {
    final pc = '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.1/assets/build_font';
    await _font('GoogleSans', ['assets/fonts/GoogleSans-Regular.ttf', 'assets/fonts/GoogleSans-Medium.ttf', 'assets/fonts/GoogleSans-SemiBold.ttf', 'assets/fonts/GoogleSans-Bold.ttf']);
    await _font('IBMPlexSansThai', ['assets/fonts/IBMPlexSansThai-Regular.ttf', 'assets/fonts/IBMPlexSansThai-Medium.ttf', 'assets/fonts/IBMPlexSansThai-SemiBold.ttf', 'assets/fonts/IBMPlexSansThai-Bold.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide300', ['$pc/LucideVariable-w300.ttf']);
    await _font('packages/lucide_icons_flutter/Lucide500', ['$pc/LucideVariable-w500.ttf']);
  });

  testWidgets('shots', (tester) async {
    for (final dark in [false, true]) {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final task = {'id': 1, 'board_id': 1, 'board_code': 'QAR', 'board_name': '[QA] R42 Bulk', 'item_no': 2, 'title': '[QA] Task ค', 'type': 'task', 'status_id': 1};
      final adapter = FakeNextxAdapter({
        'GET /api/boards/1/tasks': {
          'list': [
            task,
            {'id': 39, 'item_no': 9, 'title': '[QA] Subtask 2 (สำเนา)', 'type': 'subtask', 'parent_id': 1, 'status_id': 1, 'assignee_id': 5, 'due_date': '2026-11-23'},
            {'id': 36, 'item_no': 6, 'title': '[QA] Subtask 1', 'type': 'subtask', 'parent_id': 1, 'status_id': 2, 'assignee_id': 5, 'due_date': '2026-11-26'},
            {'id': 37, 'item_no': 7, 'title': '[QA] Subtask 2', 'type': 'subtask', 'parent_id': 1, 'status_id': 3, 'due_date': '2026-11-26'},
            {'id': 38, 'item_no': 8, 'title': '[QA] Subtask 1 (สำเนา)', 'type': 'subtask', 'parent_id': 1, 'status_id': 1},
          ],
        },
        'GET /api/boards/1/statuses': [
          {'id': 1, 'label_th': 'รอทำ', 'sequence': 1, 'is_initial': 1, 'color': '#3B82F6'},
          {'id': 2, 'label_th': 'กำลังทำ', 'sequence': 2, 'color': '#F97316'},
          {'id': 3, 'label_th': 'เสร็จแล้ว', 'sequence': 3, 'is_done': 1, 'color': '#22C55E'},
        ],
        'GET /api/boards/1/epics': {'list': []},
        'GET /api/users': {
          'list': [
            {'id': 5, 'first_name': '[QA]', 'last_name': 'Second'},
          ],
        },
        'GET /api/boards/1/items/task/1/watchers': {'list': []},
        'GET /api/boards/1/items/task/1/links': {'list': []},
        'GET /api/boards/1/items/task/1/smart-checklist': {'items': []},
        'GET /api/boards/1/tasks/1/comments': {'list': []},
        'GET /api/boards/1/tasks/1/worklogs': {'list': []},
        'GET /api/boards/1/activity': {'list': []},
      });
      final config = AppConfig();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      config.debugOverrideSession(const SessionState(accessToken: 't', userId: '5', businessId: '1', menusLoaded: true, menuKeys: ['workspace']));
      config.apiClient.debugSetHttpAdapter(adapter);
      tester.view.physicalSize = const Size(400, 1500);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: config,
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: MaterialApp(theme: dark ? AppTheme.dark : AppTheme.light, debugShowCheckedModeBanner: false, home: TaskDetailScreen(task: task)),
        ),
      ));
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.longPress(find.byKey(const ValueKey('ws-child-36')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('ws-child-38')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      final ws = tester.widget<Scrollable>(find.byType(Scrollable).first);
      ws.controller?.jumpTo(ws.controller!.position.maxScrollExtent * 0.0);
      await tester.dragUntilVisible(find.byKey(const ValueKey('ws-child-39')), find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pump(const Duration(milliseconds: 300));
      final ro = tester.firstRenderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/r42_app_dock${dark ? '_dark' : ''}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    }
  });
}
