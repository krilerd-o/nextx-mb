import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/isaac_menu.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/core/navigation/route_access.dart';
import 'package:nextx_mobile/core/notebook/notebook_models.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart' show aiInAppRoute;
import 'package:nextx_mobile/screens/notebook/notebook_home_screen.dart';
import 'package:nextx_mobile/screens/notebook/notebook_note_viewer.dart';
import 'package:nextx_mobile/screens/notebook/notebook_screen.dart';
import 'package:nextx_mobile/screens/notebook/notebook_share_sheet.dart';
import 'package:nextx_mobile/screens/notebook/notebook_sources_pane.dart';
import 'package:nextx_mobile/services/notebook/notebook_controller.dart';
import 'package:nextx_mobile/widgets/nx_audio_player_card.dart';

import 'support/fake_api.dart';
import 'support/notebook_fixtures.dart';

const _me = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

/// Reads the request body like a real network, so Dio reports upload progress.
class _StreamingAdapter extends FakeNextxAdapter {
  _StreamingAdapter(super.replies, {super.sseFor, super.statusFor, super.errorsFor});

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (requestStream != null) await requestStream.drain<void>();
    return super.fetch(options, requestStream, cancelFuture);
  }
}

Map<String, dynamic> _body(RequestOptions o) => o.data is Map ? Map<String, dynamic>.from(o.data as Map) : (o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : <String, dynamic>{});

RequestOptions _last(FakeNextxAdapter a, String key) => a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);

Map<String, Object?> _replies({bool conversation = true}) => {
      'GET /api/ai/notebooks': {'items': nbLibrary()},
      'GET /api/ai/notebooks/3': {'item': nbDetail(withConversation: conversation)},
      'GET /api/ai/notebooks/3/guide': nbGuide(),
      'GET /api/ai/conversations/9': {'id': 9, 'messages': []},
      'POST /api/ai/conversations/9/messages': {'id': 77},
      'GET /api/ai/jobs-status': {'enabled': false},
    };

/// Taps the inline `[n]` link inside rendered markdown.
bool _tapInlineCitation(WidgetTester tester, int n) {
  final spans = <InlineSpan>[
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) rt.text,
    for (final st in tester.widgetList<SelectableText>(find.byType(SelectableText))) ?st.textSpan,
  ];
  for (final root in spans) {
    var hit = false;
    root.visitChildren((span) {
      if (span is TextSpan && span.text == '[$n]' && span.recognizer is TapGestureRecognizer) {
        (span.recognizer! as TapGestureRecognizer).onTap?.call();
        hit = true;
        return false;
      }
      return true;
    });
    if (hit) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NotebookController.pollEvery = const Duration(milliseconds: 10);
  });

  group('models', () {
    test('library filters: mine / shared / business + search', () {
      final all = [for (final r in nbLibrary()) Notebook.fromJson(r)];
      expect(filterNotebooks(all, scope: NotebookScope.mine, meId: '2').map((n) => n.id), ['3', '6']);
      expect(filterNotebooks(all, scope: NotebookScope.business, meId: '2').map((n) => n.id), ['4']);
      expect(filterNotebooks(all, scope: NotebookScope.shared, meId: '2').map((n) => n.id), ['5']);
      expect(filterNotebooks(all, query: 'ประกัน').map((n) => n.id), ['6']);
      expect(notebookCover('3').colors, notebookCover('3').colors);
    });

    test('inline citations become links; code and real links stay', () {
      expect(linkCitations('ราคา [1] และ [2, 3]'), r'ราคา [\[1\]](nxcite:1) และ [\[2\]](nxcite:2)[\[3\]](nxcite:3)');
      expect(linkCitations('[ดู](https://x.y) ```[1]```'), '[ดู](https://x.y) ```[1]```');
      expect(linkCitations('อ้าง [9]', known: {1, 2}), 'อ้าง [9]');
      expect(citationFromHref('nxcite:4'), 4);
      expect(citationFromHref('https://a'), isNull);
      final q = findQuote('ก ข\n\nรับประกัน   5 ปี ค', 'รับประกัน 5 ปี');
      expect(q, isNotNull);
      expect(q!.start, 5);
    });

    test('studio parsers: flashcards, quiz (index or text answer), mind maps', () {
      expect(parseFlashcards('```json\n$nbFlashcards\n```').length, 3);
      final qs = parseQuiz(jsonEncode({
        'questions': [
          {'prompt': 'a', 'options': ['x', 'y'], 'answer': 'y'},
          {'prompt': 'b', 'options': ['x', 'y'], 'answer': 0},
        ],
      }));
      expect([for (final q in qs) q.answer], [1, 0]);
      expect(quizScore(qs, {0: 1, 1: 1}), 1);
      final mind = parseMindmap(nbMindmap)!;
      expect(mind.label, 'แอร์ 2569');
      expect(mind.children.map((c) => c.label), ['ราคา', 'บริการ', 'รับประกัน']);
      expect(mind.children.first.children.length, 2);
      final graph = parseMindmap('```mermaid\ngraph TD\n  A[ราก] --> B[กิ่ง 1]\n  A --> C(กิ่ง 2)\n  B --> D[ใบ]\n```')!;
      expect(graph.label, 'ราก');
      expect(graph.children.map((c) => c.label), ['กิ่ง 1', 'กิ่ง 2']);
      expect(graph.children.first.children.single.label, 'ใบ');
    });

    test('sources: status, YouTube, fetch errors, reorder ids, url check', () {
      final nb = Notebook.fromJson(nbDetail());
      final s = nb.sources!;
      expect(s.first.status, NotebookSourceStatus.ready);
      expect(s.last.isYoutube, isTrue);
      expect(s.last.status, NotebookSourceStatus.error);
      expect(s.last.error, 'หน้าเว็บตอบช้าเกินไป');
      expect(NotebookSource.fromJson(nbSource(1, 'file', 'x', '', config: {'extract_status': 'pending'})).status, NotebookSourceStatus.processing);
      expect(reorderedIds(s, 0, 2), ['12', '13', '11', '14']);
      expect(normalizeWebUrl('example.com/a'), 'https://example.com/a');
      expect(normalizeWebUrl('not a url'), isNull);
      expect(nb.notes!.firstWhere((n) => n.kind == 'report').downloadUrl, '/api/ai/exports/rep');
    });

    test('citations: n from loc, quote kept; guide fallback', () {
      final c = NotebookCitation.fromJson({'source_id': 11, 'loc': '[2]', 'quote': 'ข้อความ'}, 0);
      expect(c.n, 2);
      expect(c.quote, 'ข้อความ');
      final g = NotebookGuide.fallbackFor([NotebookSource.fromJson(nbSource(1, 'manual', 'A', 'x'))]);
      expect(g.fallback, isTrue);
      expect(g.topics, ['A']);
      expect(g.questions, isNotEmpty);
    });
  });

  Future<(FakeNextxAdapter, AppConfig)> pump(WidgetTester tester, Widget screen, Map<String, Object?> replies,
      {Map<String, String> sse = const {}, Map<String, int> status = const {}, Map<String, Map<String, Object?>>? errors, bool streaming = false}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(412 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    config.debugOverrideSession(_me);
    final adapter = streaming
        ? _StreamingAdapter(replies, sseFor: sse, statusFor: status, errorsFor: errors)
        : FakeNextxAdapter(replies, sseFor: sse, statusFor: status, errorsFor: errors);
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
    await settle(tester);
    return (adapter, config);
  }

  group('library', () {
    testWidgets('cards, filter chips, list toggle', (tester) async {
      await pump(tester, const NotebookHomeScreen(), _replies());
      expect(find.byKey(const ValueKey('notebook-card-3')), findsOneWidget);
      expect(find.text('คู่มือบริการลูกค้า'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notebook-scope-mine')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notebook-card-4')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-card-6')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('notebook-scope-business')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('notebook-scope-business')));
      await tester.pump();
      expect(find.byKey(const ValueKey('notebook-card-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-card-3')), findsNothing);
      await tester.tap(find.byTooltip('แสดงเป็นรายการ'));
      await tester.pump();
      expect(find.byKey(const ValueKey('notebook-more-4')), findsOneWidget);
    });

    testWidgets('create sends title / description / visibility / appearance', (tester) async {
      final (adapter, config) = await pump(tester, const NotebookHomeScreen(), {
        ..._replies(),
        'POST /api/ai/notebooks': {'item': nbRow(9, title: 'สมุดใหม่ของฉัน', sources: 0)},
      });
      final c = NotebookLibraryController(config.apiClient, meId: '2');
      await tester.runAsync(c.load);
      final nb = await tester.runAsync(() => c.create(title: 'สมุดใหม่ของฉัน', description: 'ทดสอบ', visibility: 'business'));
      final body = _body(_last(adapter, 'POST /api/ai/notebooks'));
      expect(body, {'title': 'สมุดใหม่ของฉัน', 'description': 'ทดสอบ', 'visibility': 'business', 'appearance': NotebookAppearance.forTitle('สมุดใหม่ของฉัน').toJson()});
      expect(nb!.id, '9');
      expect(c.items.first.id, '9');
      // The sheet itself.
      await tester.tap(find.byKey(const ValueKey('notebook-create')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-title-field')), findsOneWidget);
      expect(find.text('ทั้งธุรกิจ'), findsWidgets);
    });

    testWidgets('long-press → delete with confirm', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookHomeScreen(), {..._replies(), 'DELETE /api/ai/notebooks/6': {'deleted': true}});
      await tester.longPress(find.byKey(const ValueKey('notebook-card-6')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-menu-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester);
      expect(adapter.callKeys, contains('DELETE /api/ai/notebooks/6'));
      expect(find.byKey(const ValueKey('notebook-card-6')), findsNothing);
    });

    testWidgets('AI_NOTEBOOK_DISABLED → friendly disabled state', (tester) async {
      await pump(tester, const NotebookHomeScreen(), {}, status: {'GET /api/ai/notebooks': 403}, errors: {
        'GET /api/ai/notebooks': {'error_code': 'AI_NOTEBOOK_DISABLED', 'message': 'โน้ตบุ๊กถูกปิด'},
      });
      expect(find.byKey(const ValueKey('notebook-disabled')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-create')), findsNothing);
    });
  });

  group('sources', () {
    testWidgets('toggle, select-all and reorder payloads', (tester) async {
      final (adapter, config) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), {
        ..._replies(),
        'PATCH /api/ai/notebooks/3/sources/12': {'item': nbSource(12, 'url', 'x', 'y', enabled: false)},
        'POST /api/ai/notebooks/3/sources/select': {'item': nbDetail()},
        'POST /api/ai/notebooks/3/sources/reorder': {'item': nbDetail()},
      });
      expect(find.byKey(const ValueKey('notebook-source-status-14')), findsOneWidget);
      expect(find.text('อ่านไม่สำเร็จ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notebook-source-toggle-12')));
      await settle(tester);
      expect(_body(_last(adapter, 'PATCH /api/ai/notebooks/3/sources/12')), {'enabled': false});
      await tester.tap(find.byKey(const ValueKey('notebook-select-all')));
      await settle(tester);
      expect(_body(_last(adapter, 'POST /api/ai/notebooks/3/sources/select')), {'ids': [11, 12, 13, 14], 'enabled': true});
      final c = NotebookController(config.apiClient, '3');
      await tester.runAsync(c.load);
      await tester.runAsync(() => c.reorder(0, 2));
      expect(_body(_last(adapter, 'POST /api/ai/notebooks/3/sources/reorder')), {'ids': [12, 13, 11, 14]});
      expect(c.sources.map((s) => s.id), ['12', '13', '11', '14']);
    });

    testWidgets('upload a file: progress, attachment, then a file source', (tester) async {
      final (adapter, config) = await pump(tester, const SizedBox(), {
        ..._replies(),
        'POST /api/ai/attachments': {'id': 5, 'name': 'สเปก.txt', 'extracted_text': 'แอร์ 9000 BTU', 'extract_status': 'ready'},
        'POST /api/ai/notebooks/3/sources': {'item': nbSource(31, 'file', 'สเปก.txt', 'แอร์ 9000 BTU', config: {'attachment_id': 5, 'extract_status': 'ready'})},
      }, streaming: true);
      final c = NotebookController(config.apiClient, '3');
      await tester.runAsync(c.load);
      final progress = <double>[];
      c.addListener(() {
        if (c.uploads.isNotEmpty) progress.add(c.uploads.first.progress);
      });
      final ok = await tester.runAsync(() => c.addFile(() => MultipartFile.fromBytes(List.filled(4000, 65), filename: 'สเปก.txt'), name: 'สเปก.txt'));
      expect(ok, isTrue);
      expect(progress.where((p) => p > 0 && p < 1), isNotEmpty);
      expect(progress, contains(1.0));
      final body = _body(_last(adapter, 'POST /api/ai/notebooks/3/sources'));
      expect(body['source_kind'], 'file');
      expect(body['content'], 'แอร์ 9000 BTU');
      expect((body['source_config'] as Map)['attachment_id'], 5);
      expect(c.sources.last.id, '31');
      expect(c.uploads, isEmpty);
    });

    testWidgets('add sheet: web link and pasted text', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), {
        ..._replies(),
        'POST /api/ai/notebooks/3/sources': {'item': nbSource(32, 'url', 'Example', 'เนื้อหา', config: {'url': 'https://example.com', 'source': 'fetch'})},
      });
      await tester.tap(find.byKey(const ValueKey('notebook-add-source')));
      await settle(tester);
      // No `/recordings` on this (mocked) server → 404 → the record entry is hidden (see r77).
      expect(find.byKey(const ValueKey('notebook-add-record')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('notebook-add-url')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('notebook-url-field')), 'example.com');
      await tester.tap(find.byKey(const ValueKey('notebook-url-add')));
      await settle(tester);
      final url = _body(_last(adapter, 'POST /api/ai/notebooks/3/sources'));
      expect(url['source_kind'], 'url');
      expect(url['url'], 'https://example.com');
      await tester.tap(find.byKey(const ValueKey('notebook-add-source')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-add-text')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('notebook-text-body')), 'โปรโมชันเดือนนี้ลด 10%');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('notebook-text-add')));
      await settle(tester);
      final text = _body(_last(adapter, 'POST /api/ai/notebooks/3/sources'));
      expect(text['source_kind'], 'manual');
      expect(text['content'], 'โปรโมชันเดือนนี้ลด 10%');
    });

    testWidgets('file picker in the add sheet uploads each file', (tester) async {
      NotebookPickers.files = () async => [(name: 'a.txt', bytes: utf8.encode('hello'))];
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.sources), {
        ..._replies(),
        'POST /api/ai/attachments': {'id': 6, 'name': 'a.txt', 'extracted_text': 'hello'},
        'POST /api/ai/notebooks/3/sources': {'item': nbSource(33, 'file', 'a.txt', 'hello')},
      });
      await tester.tap(find.byKey(const ValueKey('notebook-add-source')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-add-file')));
      await settle(tester);
      expect(adapter.callKeys, containsAllInOrder(['POST /api/ai/attachments', 'POST /api/ai/notebooks/3/sources']));
      expect(find.text('a.txt'), findsOneWidget);
    });
  });

  group('chat', () {
    testWidgets('guide card, streamed answer, tappable [n] → citation sheet → source', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), _replies(), sse: {'POST /api/ai/chat': nbChatSse()});
      expect(find.byKey(const ValueKey('notebook-guide-summary')), findsOneWidget);
      expect(find.text('ราคา'), findsOneWidget);
      expect(_last(adapter, 'GET /api/ai/notebooks/3/guide').queryParameters['locale'], 'th');
      await tester.tap(find.byKey(const ValueKey('notebook-guide-q0')));
      await settle(tester);
      final chat = _body(_last(adapter, 'POST /api/ai/chat'));
      expect(chat['notebook_id'], 3);
      expect(chat['source_ids'], [11, 12, 13]);
      expect(chat['conversation_id'], '9');
      expect(find.byKey(const ValueKey('notebook-cite-chip-1')), findsOneWidget);
      expect(_tapInlineCitation(tester, 1), isTrue);
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-citation-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-citation-quote')), findsOneWidget);
      expect(find.text('ราคาเริ่มต้น 15,000 บาท'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notebook-citation-goto')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-source-viewer')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-viewer-highlight')), findsOneWidget);
    });

    testWidgets('guide 404 → fixed suggestions; first question creates a notebook conversation', (tester) async {
      final replies = _replies(conversation: false)
        ..remove('GET /api/ai/notebooks/3/guide')
        ..addAll({
          'POST /api/ai/conversations': {'id': 40, 'title': 'x', 'mode': 'notebook'},
          'PATCH /api/ai/notebooks/3': {'item': nbRow(3)},
          'POST /api/ai/conversations/40/messages': {'id': 88},
        });
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), replies, sse: {'POST /api/ai/chat': nbChatSse(quote: false)});
      expect(find.text('สรุปประเด็นสำคัญจากแหล่งข้อมูลทั้งหมด'), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-guide-refresh')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('notebook-guide-q1')));
      await settle(tester);
      expect(_body(_last(adapter, 'POST /api/ai/conversations'))['mode'], 'notebook');
      expect(_body(_last(adapter, 'PATCH /api/ai/notebooks/3')), {'conversation_id': 40});
      // No quote from the server: the sheet shows the source's opening text instead.
      await tester.tap(find.byKey(const ValueKey('notebook-cite-chip-2')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-citation-quote')), findsNothing);
      expect(find.textContaining('ควรล้างแอร์'), findsWidgets);
    });

    testWidgets('save answer as note sends source_message_id', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), {
        ..._replies(),
        'POST /api/ai/notebooks/3/notes': {'item': nbNote(50, 'note', 'ราคาแอร์รุ่นเริ่มต้นเท่าไร', 'x')},
      }, sse: {'POST /api/ai/chat': nbChatSse()});
      await tester.tap(find.byKey(const ValueKey('notebook-guide-q0')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('notebook-save-note')));
      await settle(tester);
      final body = _body(_last(adapter, 'POST /api/ai/notebooks/3/notes'));
      expect(body['source_message_id'], 77);
      expect(body['artifact_kind'], 'note');
      expect(body['title'], 'ราคาแอร์รุ่นเริ่มต้นเท่าไร');
      expect((body['meta'] as Map)['citations'], hasLength(2));
      expect(find.text('บันทึกแล้ว'), findsOneWidget);
    });

    testWidgets('no enabled sources → empty state, input off', (tester) async {
      final none = nbDetail(withConversation: true, sources: [nbSource(11, 'manual', 'A', 'x', enabled: false)]);
      await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), {..._replies(), 'GET /api/ai/notebooks/3': {'item': none}});
      expect(find.byKey(const ValueKey('notebook-chat-no-sources')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('notebook-chat-input'))).enabled, isFalse);
    });

    testWidgets('stale guide → "อัปเดตคู่มือ" calls refresh', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), {
        ..._replies(),
        'GET /api/ai/notebooks/3/guide': {...nbGuide(), 'stale': true},
        'POST /api/ai/notebooks/3/guide/refresh': {...nbGuide(), 'summary': 'สรุปใหม่'},
      });
      await tester.tap(find.byKey(const ValueKey('notebook-guide-update')));
      await settle(tester);
      expect(adapter.callKeys, contains('POST /api/ai/notebooks/3/guide/refresh'));
      expect(find.byKey(const ValueKey('notebook-guide-update')), findsNothing);
    });
  });

  group('studio', () {
    testWidgets('sync run opens the flashcards; cards flip and advance', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), {
        ..._replies(),
        'POST /api/ai/notebooks/3/studio': {'item': nbNote(60, 'flashcards', 'แฟลชการ์ด', nbFlashcards)},
      });
      await tester.tap(find.byKey(const ValueKey('notebook-studio-flashcards')));
      await settle(tester);
      final body = _body(_last(adapter, 'POST /api/ai/notebooks/3/studio'));
      expect(body['kind'], 'flashcards');
      expect(body['source_ids'], [11, 12, 13]);
      expect(body.containsKey('async'), isFalse);
      expect(find.byKey(const ValueKey('notebook-flashcards')), findsOneWidget);
      expect(find.text('ราคาเริ่มต้นของแอร์คือเท่าไร'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('flashcard-0')));
      await tester.pumpAndSettle();
      expect(find.text('15,000 บาท'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('flashcard-next')));
      await tester.pumpAndSettle();
      expect(find.text('การ์ด 2/3'), findsOneWidget);
    });

    testWidgets('async run polls the job, then opens the new note', (tester) async {
      var polls = 0;
      final replies = {
        ..._replies(),
        'GET /api/ai/jobs-status': {'enabled': true, 'worker_seen_recently': true},
        'POST /api/ai/notebooks/3/studio': {'queued': true, 'jobId': 'j1'},
        'GET /api/ai/jobs/j1': {'state': 'active', 'progress': {'phase': 'llm'}},
      };
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), replies);
      adapter.onRequest = (o) {
        if (o.path == '/api/ai/jobs/j1' && ++polls >= 2) {
          adapter.replies['GET /api/ai/jobs/j1'] = {'state': 'completed'};
          adapter.replies['GET /api/ai/notebooks/3'] = {
            'item': nbDetail(withConversation: true, notes: [nbNote(70, 'quiz', 'แบบทดสอบ', nbQuiz), ...nbDetail()['notes'] as List]),
          };
        }
      };
      await tester.tap(find.byKey(const ValueKey('notebook-studio-quiz')));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_body(_last(adapter, 'POST /api/ai/notebooks/3/studio'))['async'], isTrue);
      expect(polls, greaterThanOrEqualTo(2));
      expect(find.byKey(const ValueKey('notebook-quiz')), findsOneWidget);
    });

    testWidgets('quiz: pick answers, score', (tester) async {
      final (_, config) = await pump(tester, const SizedBox(), _replies());
      final c = NotebookController(config.apiClient, '3');
      await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: NotebookNoteScreen(c: c, note: NotebookNote.fromJson(nbNote(23, 'quiz', 'แบบทดสอบ', nbQuiz))))));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quiz-q0-o2')));
      await tester.tap(find.byKey(const ValueKey('quiz-q1-o1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quiz-check')));
      await tester.pump();
      expect(find.text('คะแนน 1/2'), findsOneWidget);
    });

    testWidgets('mind map renders natively; audio card; infographic; report download', (tester) async {
      final (_, config) = await pump(tester, const SizedBox(), _replies());
      final c = NotebookController(config.apiClient, '3');
      Future<void> show(Map<String, dynamic> raw) async {
        await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: NotebookNoteScreen(key: ValueKey(raw['id']), c: c, note: NotebookNote.fromJson(raw), onAsk: (_) {}))));
        await tester.pump();
      }

      await show(nbNote(21, 'mindmap', 'แผนผังความคิด', nbMindmap));
      expect(find.byKey(const ValueKey('notebook-mindmap')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-root')), findsOneWidget);
      expect(find.text('ติดตั้งฟรี'), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-mindmap-diagram')), findsOneWidget);

      await show(nbNote(24, 'audio', 'ภาพรวมแบบเสียง', 'A: สวัสดี', meta: {'downloadUrl': '/api/ai/exports/tok', 'fileName': 'audio.mp3'}));
      expect(find.byType(NxAudioPlayerCard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nx-audio-speed')));
      await tester.pump();
      expect(find.text('1.25x'), findsOneWidget);

      await show(nbNote(26, 'infographic', 'อินโฟกราฟิก', '<div><strong>1.</strong> ราคา 15,000</div>'));
      expect(find.byKey(const ValueKey('notebook-infographic')), findsOneWidget);

      await show(nbNote(25, 'report', 'รายงาน', '# รายงาน', meta: {'downloadUrl': '/api/ai/exports/rep', 'fileName': 'รายงาน.pdf'}));
      expect(find.byKey(const ValueKey('notebook-download')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-download-preview')), findsOneWidget);
    });

    testWidgets('new note via editor', (tester) async {
      final (adapter, config) = await pump(tester, const SizedBox(), {
        ..._replies(),
        'POST /api/ai/notebooks/3/notes': {'item': nbNote(80, 'note', 'ไอเดีย', 'เนื้อหา')},
      });
      final c = NotebookController(config.apiClient, '3');
      await tester.runAsync(c.load);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: NotebookNoteEditor(c: c))));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('notebook-note-title')), 'ไอเดีย');
      await tester.enterText(find.byKey(const ValueKey('notebook-note-body')), 'เนื้อหา');
      await tester.tap(find.byKey(const ValueKey('notebook-note-save')));
      await settle(tester);
      expect(_body(_last(adapter, 'POST /api/ai/notebooks/3/notes')), {'title': 'ไอเดีย', 'content': 'เนื้อหา', 'artifact_kind': 'note'});
      expect(c.notes.first.id, '80');
    });
  });

  testWidgets('share: read-only link, then revoke', (tester) async {
    final share = {'id': 1, 'notebook_id': 3, 'token': 'tok1', 'share_mode': 'read_only', 'targets': []};
    final replies = {
      ..._replies(),
      'GET /api/ai/notebooks/3/shares': {'items': []},
      'POST /api/ai/notebooks/3/shares': {'item': share, 'path': '/ai/notebook/public/tok1', 'public_path': '/ai/notebook/public/tok1'},
      'DELETE /api/ai/notebooks/3/shares/1': {'deleted': true},
      'GET /api/users': {'list': []},
    };
    final (adapter, _) = await pump(tester, Scaffold(body: NotebookShareSheet(notebook: Notebook.fromJson(nbRow(3)))), replies);
    adapter.onRequest = (o) {
      if (o.method == 'POST' && o.path == '/api/ai/notebooks/3/shares') {
        adapter.replies['GET /api/ai/notebooks/3/shares'] = {'items': [share]};
      }
    };
    await tester.tap(find.byKey(const ValueKey('notebook-share-create-link')));
    await settle(tester);
    expect(_body(_last(adapter, 'POST /api/ai/notebooks/3/shares')), {'share_mode': 'read_only'});
    expect(find.byKey(const ValueKey('notebook-share-link')), findsOneWidget);
    expect(find.textContaining('/ai/notebook/public/tok1'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('notebook-share-revoke-1')));
    await settle(tester);
    expect(adapter.callKeys, contains('DELETE /api/ai/notebooks/3/shares/1'));
    expect(find.byKey(const ValueKey('notebook-share-1')), findsNothing);
  });

  group('entry points', () {
    test('ISAAC menu "AI Notebook" and web links open the native notebook', () {
      expect(IsaacMenu.notebook.route, AppRoutes.notebook);
      expect(isaacItemFor('/notebook')?.key, 'isaac-notebook');
      expect(isaacItemFor('/notebook/3')?.key, 'isaac-notebook');
      expect(isaacItemFor('/ai/notebook/3')?.key, 'isaac-notebook');
      expect(isaacItemFor('/isaac')?.key, 'isaac-notebook');
      expect(isaacItemFor('/ai/shared/x')?.key, 'ai-assistant');
      expect(notificationDeepLink('/ai/notebook/5'), '/notebook/5');
      expect(notificationDeepLink('/ai/notebook'), '/notebook');
      expect(aiInAppRoute('/ai/notebook/7'), '/notebook/7');
      expect(aiInAppRoute('/ai/notebook/public/abc'), isNull);
    });

    testWidgets('/isaac and /ai/notebook/:id route to the native screens', (tester) async {
      SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
      final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    config.debugOverrideSession(_me);
      config.apiClient.debugSetHttpAdapter(FakeNextxAdapter(_replies()));
      final router = GoRouter(initialLocation: '/isaac', routes: [
        GoRoute(path: AppRoutes.isaacNotebook, redirect: (_, _) => AppRoutes.notebook),
        GoRoute(path: AppRoutes.notebook, builder: (_, _) => const NotebookHomeScreen()),
        GoRoute(path: '/notebook/:id', builder: (_, s) => NotebookScreen(id: s.pathParameters['id']!)),
        GoRoute(path: '/ai/notebook/:id', redirect: (_, s) => AppRoutes.notebookOf(s.pathParameters['id']!)),
      ]);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp.router(routerConfig: router)));
      await settle(tester);
      expect(find.byType(NotebookHomeScreen), findsOneWidget);
      router.go('/ai/notebook/3');
      await settle(tester);
      expect(find.byType(NotebookScreen), findsOneWidget);
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}
