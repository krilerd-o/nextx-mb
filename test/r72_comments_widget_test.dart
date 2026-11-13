import 'dart:convert';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_parts.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/widgets/comments/nx_comment_composer.dart';

import 'support/fake_api.dart';

Map<String, dynamic> _data(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is String ? jsonDecode(d) as Map<String, dynamic> : Map<String, dynamic>.from(d as Map);
}

String _ts(int min) => '2026-11-13T03:${min.toString().padLeft(2, '0')}:00Z';

final _thread = <Map<String, dynamic>>[
  {'id': 1, 'user_id': 9, 'user_name': 'เพื่อน', 'body': 'เริ่มคุยกัน', 'created_at': _ts(1), 'parent_id': null},
  {'id': 2, 'user_id': 2, 'user_name': 'ฉัน', 'body': 'ตอบ 1', 'created_at': _ts(2), 'parent_id': 1},
  {'id': 3, 'user_id': 9, 'user_name': 'เพื่อน', 'body': 'ตอบ 2', 'created_at': _ts(3), 'parent_id': 1},
  {'id': 4, 'user_id': 5, 'user_name': 'Ann', 'body': 'ตอบ 3', 'created_at': _ts(4), 'parent_id': 1},
  {'id': 5, 'user_id': 2, 'user_name': 'ฉัน', 'body': 'ของฉันเอง https://example.com/quote', 'created_at': _ts(5), 'parent_id': null},
];

Future<(FakeNextxAdapter, int Function())> _pump(WidgetTester tester, {List<Map<String, dynamic>>? comments, Map<String, Object?> extra = const {}}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
  SharedPreferences.setMockInitialValues({});
  final adapter = FakeNextxAdapter({
    'POST /api/entity/lead/5/comments': {'id': 50, 'body': '', 'attachments': [], 'parent_id': null},
    'PUT /api/entity/lead/5/comments/5': {'id': 5},
    'DELETE /api/entity/lead/5/comments/5': {'id': 5, 'deleted_ids': [5]},
    'GET /api/chat/unfurl': {'url': 'https://example.com/quote', 'title': 'ใบเสนอราคาตัวอย่าง', 'description': 'รายละเอียด', 'image': null, 'siteName': 'Example'},
    'GET /api/users': {
      'list': [
        {'id': 7, 'first_name': 'Somchai', 'last_name': 'Jaidee', 'email1': 'somchai@demo.local'},
        {'id': 8, 'first_name': 'Wipa', 'email1': 'wipa@demo.local'},
      ],
    },
    'POST /api/files/upload': {
      'list': [
        {'id': 31, 'storage_path': 'files/1/site.png', 'file_name': 'site.png', 'mime_type': 'image/png', 'file_size': 2048},
      ],
    },
    ...extra,
  });
  final config = AppConfig();
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  var reloads = 0;
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EntityCommentsPanel(module: 'lead', id: '5', comments: comments ?? _thread, onChanged: () async => reloads++),
        ),
      ),
    ),
  ));
  await _settle(tester);
  return (adapter, () => reloads);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  tearDown(() => debugCommentFilePicker = null);

  testWidgets('R72 threads: long threads collapse to "ดูการตอบกลับ N รายการ" and expand', (tester) async {
    await _pump(tester);
    expect(find.text('เริ่มคุยกัน'), findsOneWidget);
    expect(find.text('ตอบ 1'), findsNothing, reason: '3 replies → collapsed');
    expect(find.text('ดูการตอบกลับ 3 รายการ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comment-thread-toggle-1')));
    await tester.pump();
    expect(find.text('ตอบ 1'), findsOneWidget);
    expect(find.text('ตอบ 3'), findsOneWidget);
    expect(find.text('ซ่อนการตอบกลับ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comment-thread-toggle-1')));
    await tester.pump();
    expect(find.text('ตอบ 1'), findsNothing);
  });

  testWidgets('R72 reply: quote bar, parent_id; replying to a reply mentions its author', (tester) async {
    final (adapter, reloads) = await _pump(tester);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('comment-send'))).onPressed, isNull, reason: 'send off while empty');

    await tester.tap(find.byKey(const ValueKey('comment-reply-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-reply-bar')), findsOneWidget);
    expect(find.text('ตอบกลับ เพื่อน'), findsOneWidget);
    expect(find.text('ตอบ 1'), findsOneWidget, reason: 'replying opens the thread');
    await tester.enterText(find.byKey(const ValueKey('comment-input')), 'รับทราบครับ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('comment-send')));
    await _settle(tester);
    final body = _data(adapter, 'POST /api/entity/lead/5/comments');
    expect(body['parent_id'], 1);
    expect(body['body'], 'รับทราบครับ');
    expect(reloads(), 1);
    expect(find.byKey(const ValueKey('comment-reply-bar')), findsNothing);

    // Reply to Ann's reply (id 4): parent is that reply, the text starts with @Ann.
    await tester.tap(find.byKey(const ValueKey('comment-reply-4')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('comment-input')), '${(tester.widget<TextField>(find.byKey(const ValueKey('comment-input')))).controller!.text}ขอบคุณ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('comment-send')));
    await _settle(tester);
    final b2 = _data(adapter, 'POST /api/entity/lead/5/comments');
    expect(b2['parent_id'], 4);
    expect(b2['body'], '<span data-type="mention" data-id="5" class="moai-mention">@Ann</span> ขอบคุณ');
  });

  testWidgets('R72 edit / delete own comment (confirm); others are read-only', (tester) async {
    final (adapter, reloads) = await _pump(tester);
    expect(find.byKey(const ValueKey('comment-edit-1')), findsNothing);
    expect(find.byKey(const ValueKey('comment-delete-1')), findsNothing);
    expect(find.byKey(const ValueKey('comment-edit-5')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('comment-edit-5')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('comment-edit-field')), 'แก้แล้ว');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('comment-edit-save')));
    await _settle(tester);
    expect(_data(adapter, 'PUT /api/entity/lead/5/comments/5')['body'], 'แก้แล้ว');
    expect(reloads(), 1);

    await tester.tap(find.byKey(const ValueKey('comment-delete-5')));
    await tester.pumpAndSettle();
    expect(find.text('ลบคอมเม้นท์นี้?'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก').last);
    await tester.pumpAndSettle();
    expect(adapter.callKeys, isNot(contains('DELETE /api/entity/lead/5/comments/5')));
    await tester.tap(find.byKey(const ValueKey('comment-delete-5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comment-delete-confirm')));
    await _settle(tester);
    expect(adapter.callKeys, contains('DELETE /api/entity/lead/5/comments/5'));
    expect(reloads(), 2);
  });

  testWidgets('R72 attachments: tray with thumbnails, upload, retry on failure, payload like the web', (tester) async {
    final png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    debugCommentFilePicker = (source) async => [(name: 'site.png', bytes: png, mime: 'image/png')];
    final (adapter, _) = await _pump(tester, comments: const []);
    adapter.errorsFor['POST /api/files/upload'] = {'error_code': 'UPLOAD_FAILED', 'message': 'อัปโหลดไม่สำเร็จ'};

    await tester.tap(find.byKey(const ValueKey('comment-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comment-attach-gallery')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('comment-upload-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-upload-retry-0')), findsOneWidget, reason: 'failed upload offers retry');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('comment-send'))).onPressed, isNull);

    adapter.errorsFor.remove('POST /api/files/upload');
    await tester.tap(find.byKey(const ValueKey('comment-upload-retry-0')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('comment-upload-retry-0')), findsNothing);
    final upload = adapter.calls.lastWhere((c) => c.path == '/api/files/upload');
    expect(upload.data, isA<FormData>());
    expect((upload.data as FormData).files.single.value.filename, 'site.png');

    await tester.tap(find.byKey(const ValueKey('comment-send')));
    await _settle(tester);
    final body = _data(adapter, 'POST /api/entity/lead/5/comments');
    expect(body['body'], '');
    expect(body['attachments'], [
      {'url': '/uploads/files/1/site.png', 'name': 'site.png', 'mime': 'image/png', 'size': 2048, 'file_id': 31},
    ]);
    expect(find.byKey(const ValueKey('comment-upload-0')), findsNothing, reason: 'tray clears after send');

    // Remove before send.
    await tester.tap(find.byKey(const ValueKey('comment-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('comment-attach-camera')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('comment-upload-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comment-upload-remove-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-upload-0')), findsNothing);
  });

  testWidgets('R72 link preview card: in comments and for a pasted link in the composer', (tester) async {
    final (adapter, _) = await _pump(tester);
    await _settle(tester);
    expect(adapter.callKeys, contains('GET /api/chat/unfurl'));
    final q = adapter.calls.firstWhere((c) => c.path == '/api/chat/unfurl').queryParameters;
    expect(q['url'], 'https://example.com/quote');
    expect(find.byKey(const ValueKey('link-preview-https://example.com/quote')), findsOneWidget);
    expect(find.text('ใบเสนอราคาตัวอย่าง'), findsWidgets);
    expect(find.text('Example'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('comment-input')), 'ดูนี่ https://example.com/quote');
    await _settle(tester);
    expect(find.byKey(const ValueKey('link-preview-close')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('link-preview-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('link-preview-close')), findsNothing);
  });

  testWidgets('R72 mention picker: @ lists business users, chip in text, span payload', (tester) async {
    final (adapter, _) = await _pump(tester, comments: const []);
    await tester.enterText(find.byKey(const ValueKey('comment-input')), 'ช่วยดู @so');
    await _settle(tester);
    expect(adapter.callKeys, contains('GET /api/users'));
    expect(find.byKey(const ValueKey('mention-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('mention-option-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('mention-option-8')), findsNothing, reason: 'filtered by "so"');
    await tester.tap(find.byKey(const ValueKey('mention-option-7')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const ValueKey('comment-input')));
    expect(field.controller!.text, 'ช่วยดู @Somchai Jaidee ');
    expect(find.byKey(const ValueKey('mention-picker')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('comment-input')), '${field.controller!.text}หน่อย');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('comment-send')));
    await _settle(tester);
    expect(
      _data(adapter, 'POST /api/entity/lead/5/comments')['body'],
      'ช่วยดู <span data-type="mention" data-id="7" class="moai-mention">@Somchai Jaidee</span> หน่อย',
    );

    // The @ button types "@" and opens the picker.
    await tester.tap(find.byKey(const ValueKey('comment-mention')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('mention-option-8')), findsOneWidget);
  });

  testWidgets('R72 mention picker lists only people who can open the record (server list)', (tester) async {
    final (adapter, _) = await _pump(tester, comments: const [], extra: {
      'GET /api/entity/lead/5/mention-users': {'list': [{'id': 8, 'first_name': 'Wipa'}]},
    });
    await tester.enterText(find.byKey(const ValueKey('comment-input')), '@');
    await _settle(tester);
    expect(adapter.callKeys, contains('GET /api/entity/lead/5/mention-users'));
    expect(adapter.callKeys, isNot(contains('GET /api/users')));
    expect(find.byKey(const ValueKey('mention-option-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('mention-option-7')), findsNothing);
  });

  testWidgets('R72 mentions render as chips; stored HTML is not shown as tags', (tester) async {
    await _pump(tester, comments: [
      {'id': 1, 'user_id': 9, 'user_name': 'เพื่อน', 'body': 'ดู <span data-type="mention" data-id="2" class="moai-mention">@ฉัน</span> ด้วย', 'created_at': _ts(1)},
    ]);
    final rich = tester.widget<Text>(find.byKey(const ValueKey('comment-rich')));
    final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
    final chip = spans.firstWhere((s) => s.text!.contains('@ฉัน'));
    expect(chip.style?.background, isNotNull);
    expect(rich.textSpan!.toPlainText(), isNot(contains('<span')));
  });

  testWidgets('R72 deep link: record opens on comments, highlights the comment, composer sticky at the bottom', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async => null);
    SharedPreferences.setMockInitialValues({});
    final adapter = FakeNextxAdapter({
      'GET /api/entity/lead/5': {'id': 5, 'lead_no': 'L1', 'lead_name': 'คุณเอ', 'lead_status': 'New'},
      'GET /api/entity/lead/5/comments': {'list': _thread},
      'GET /api/entity/lead/5/tags': {'list': []},
      'GET /api/tags': {'list': []},
      'GET /api/fields/lead': {'fields': [{'name': 'lead_name', 'label_th': 'ชื่อ'}], 'picklists': {}},
      'GET /api/users': {'list': []},
    });
    final config = AppConfig();
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead']));
    config.apiClient.debugSetHttpAdapter(adapter);
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: const MaterialApp(home: EntityDetailScreen(module: 'lead', row: {'id': 5}, initialTab: 'comments', focusCommentId: '3')),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final scaffold = tester.widgetList<Scaffold>(find.byType(Scaffold)).firstWhere((s) => s.bottomNavigationBar != null);
    expect(scaffold.bottomNavigationBar, isA<NxCommentComposer>());
    expect((scaffold.bottomNavigationBar! as NxCommentComposer).sticky, isTrue);
    // The highlighted reply sits in a collapsed thread: it is opened and marked.
    expect(find.text('ตอบ 2'), findsOneWidget);
    final box = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('comment-bubble-3')));
    expect((box.decoration! as BoxDecoration).border, isNotNull);
    // The highlight fades after a few seconds.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('comment-bubble-3')));
    expect((after.decoration! as BoxDecoration).border, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
