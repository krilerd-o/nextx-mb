import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/i18n.dart';
import 'package:nextx_mobile/core/notebook/notebook_models.dart';
import 'package:nextx_mobile/core/notebook/notebook_studio_meta.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/notebook/notebook_chat_pane.dart';
import 'package:nextx_mobile/screens/notebook/notebook_mind_tree.dart';
import 'package:nextx_mobile/screens/notebook/notebook_note_viewer.dart';
import 'package:nextx_mobile/screens/notebook/notebook_screen.dart';
import 'package:nextx_mobile/screens/notebook/notebook_sources_pane.dart';
import 'package:nextx_mobile/services/notebook/notebook_controller.dart';
import 'package:nextx_mobile/widgets/nx_audio_player_card.dart';
import 'package:nextx_mobile/widgets/nx_markdown.dart';

import 'support/fake_api.dart';
import 'support/notebook_p3_fixtures.dart';

/// ISAAC Notebook Phase 3 (batch 1): passage citations, Audio Overview v2,
/// interactive mind map, study guide / FAQ / briefing / timeline, chat settings.

const _me = SessionState(accessToken: 't', userId: '1', businessId: '1', menusLoaded: true, menuKeys: ['ai-assistant']);

Map<String, dynamic> _body(RequestOptions o) => o.data is Map ? Map<String, dynamic>.from(o.data as Map) : (o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : <String, dynamic>{});

RequestOptions _last(FakeNextxAdapter a, String key) => a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);

Map<String, dynamic> _nb({List<Map<String, dynamic>> notes = const [], Map<String, dynamic>? chatSettings}) => {
      ...p3Notebook(),
      'notes': notes,
      'chat_settings': ?chatSettings,
    };

Map<String, Object?> _replies({List<Map<String, dynamic>> notes = const [], Map<String, dynamic>? chatSettings}) => {
      'GET /api/ai/notebooks/3': {'item': _nb(notes: notes, chatSettings: chatSettings)},
      'GET /api/ai/notebooks/3/guide': {'summary': 'สรุปสมุด', 'topics': ['ราคา'], 'questions': ['ลูกค้า ABC แจ้งปัญหาอะไร'], 'stale': false},
      'GET /api/ai/conversations/9': {'id': 9, 'messages': []},
      'POST /api/ai/conversations/9/messages': {'id': 77},
      'GET /api/ai/jobs-status': {'enabled': false},
    };

const _defaults = {'goal': 'default', 'custom_prompt': null, 'persona': null, 'length': 'default'};

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

/// Text of the highlighted (background-coloured) span in the source viewer.
String? _highlighted(WidgetTester tester) {
  final f = find.byKey(const ValueKey('notebook-viewer-highlight'));
  if (f.evaluate().isEmpty) return null;
  final span = tester.widget<SelectableText>(f).textSpan!;
  String? out;
  span.visitChildren((s) {
    if (s is TextSpan && s.style?.backgroundColor != null && (s.text ?? '').isNotEmpty) {
      out = s.text;
      return false;
    }
    return true;
  });
  return out;
}

/// Scrolls the note's list until [key] is built and on screen.
Future<void> _scrollTo(WidgetTester tester, Key key, {bool up = false}) async {
  final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
  await tester.scrollUntilVisible(find.byKey(key), up ? -200 : 200, scrollable: list, maxScrolls: 60);
  await tester.pump();
}

Future<void> settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NotebookController.pollEvery = const Duration(milliseconds: 10);
  });

  Future<(FakeNextxAdapter, AppConfig)> pump(WidgetTester tester, Widget screen, Map<String, Object?> replies,
      {Map<String, String> sse = const {}, Map<String, int> status = const {}, Map<String, Map<String, Object?>>? errors, Size size = const Size(412, 1000), double textScale = 1, Brightness brightness = Brightness.light}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    config.debugOverrideSession(_me);
    final adapter = FakeNextxAdapter(replies, sseFor: sse, statusFor: status, errorsFor: errors);
    config.apiClient.debugSetHttpAdapter(adapter);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
        home: screen,
      ),
    ));
    await settle(tester);
    return (adapter, config);
  }

  /// A note screen on a loaded controller.
  Future<(FakeNextxAdapter, NotebookController)> note(WidgetTester tester, Map<String, dynamic> raw,
      {Size size = const Size(412, 1000), double textScale = 1, Brightness brightness = Brightness.light, ValueChanged<String>? onDraft}) async {
    final (adapter, config) = await pump(tester, const SizedBox(), _replies(), size: size, textScale: textScale, brightness: brightness);
    final c = NotebookController(config.apiClient, '3');
    await tester.runAsync(c.load);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: config,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
        home: NotebookNoteScreen(key: ValueKey('${raw['id']}-$textScale-$brightness-$size'), c: c, note: NotebookNote.fromJson(raw), onDraft: onDraft, onAsk: (_) {}),
      ),
    ));
    await settle(tester, 6);
    return (adapter, c);
  }

  group('models', () {
    test('citations: passages with offsets; older citations keep working', () {
      final cites = NotebookCitation.list([for (final c in p3ChatDone()['citations'] as List) Map<String, dynamic>.from(c as Map)]);
      expect(cites.map((c) => c.n), [1, 2, 3]);
      expect(cites.first.passages.single.start, 0);
      expect(cites.first.passages.single.end, 106);
      expect(cites.first.passages.single.chunkIndex, isNull);
      expect(cites.first.passages.single.hasRange, isTrue);
      final old = NotebookCitation.fromJson({'source_id': 11, 'loc': '[2]', 'quote': 'x'}, 0);
      expect(old.passages, isEmpty);
      expect(old.quote, 'x');
    });

    test('passageRange: offsets when they fit, else the quote, else nothing', () {
      const body = 'หนึ่ง สอง\n\nราคา 5,000 บาท ต่อเดือน';
      final i = body.indexOf('5,000');
      expect(passageRange(body, start: i, end: i + 5, quote: '5,000'), (start: i, end: i + 5));
      // Stale offsets (past the end, or pointing at other text) → search the quote.
      expect(passageRange(body, start: 90, end: 99, quote: 'ต่อเดือน'), (start: body.indexOf('ต่อเดือน'), end: body.length));
      expect(passageRange(body, start: 0, end: 4, quote: 'ต่อเดือน')!.start, body.indexOf('ต่อเดือน'));
      expect(passageRange(body, start: null, end: null, quote: 'ไม่มีในนี้'), isNull);
      expect(passageRange(body, start: 2, end: 6), (start: 2, end: 6));
    });

    test('study guide / faq / briefing / timeline from real meta', () {
      final g = StudyGuide.fromMeta(NotebookNote.fromJson(p3StudyGuide()).meta)!;
      expect(g.quiz.length, 4);
      expect(g.essays.length, 2);
      expect(g.glossary.length, 3);
      expect(g.quiz.first.sourceIds, ['7']);
      final faq = faqFromMeta(NotebookNote.fromJson(p3Faq()).meta)!;
      expect(faq.first.q, 'Example Domain พูดถึงอะไร?');
      final b = Briefing.fromMeta(NotebookNote.fromJson(p3Briefing()).meta)!;
      expect(b.title, 'สรุปภาพรวมโน้ตบุ๊ก');
      expect(b.themes.length, 4);
      expect(b.quotes.every((q) => !q.verified), isTrue);
      expect(b.summarySourceIds, ['7', '8', '10']);
      final t = Timeline.fromMeta(NotebookNote.fromJson(p3Timeline()).meta)!;
      expect(t.events.length, 5);
      expect(t.events[3].date, 'ไม่ระบุ');
      expect(t.cast.map((c) => c.name), ['ลูกค้า ABC', 'คุณวิภา']);
      expect(t.cast[1].initials, 'ว');
      expect(const CastMember('Jane Doe').initials, 'JD');
      final meta = NotebookNote.fromJson(p3StudyGuide()).meta;
      final refs = refsFor(studioSources(meta), ['10', '999']);
      expect(refs.first.n, 3);
      expect(refs.first.title, 'บันทึกประชุม');
      expect(refs.last.n, 0, reason: 'unknown ids still link by id');
      expect(studioFromTemplate(meta), isFalse);
      // No meta → null (markdown fallback).
      expect(StudyGuide.fromMeta(const {}), isNull);
      expect(faqFromMeta(const {}), isNull);
      expect(Briefing.fromMeta(const {}), isNull);
      expect(Timeline.fromMeta(const {}), isNull);
    });

    test('mind map tree and audio overview from real meta', () {
      final root = MindTreeNode.fromMeta(NotebookNote.fromJson(p3MindmapJson()).meta)!;
      expect(root.label, 'Smoke: Notebook v2');
      expect(root.children.length, 6);
      expect(root.size, 23);
      final leaf = root.children[2].children[1];
      expect(leaf.id, 'root.2.1');
      expect(leaf.path, ['Smoke: Notebook v2', 'บันทึกประชุม', leaf.label]);
      expect(leaf.effectiveSourceIds, ['10']);
      expect(mindNodeQuestion(leaf), contains('ในหัวข้อ "บันทึกประชุม"'));
      expect(MindTreeNode.fromMeta(const {}), isNull);

      final o = AudioOverview.fromMeta(NotebookNote.fromJson(p3Audio()).meta)!;
      expect(o.format, 'deep_dive');
      expect(o.turns.length, 11);
      expect(o.turns[1].isA, isFalse);
      expect(o.timed, isTrue);
      expect(o.turnAt(0), 0);
      expect(o.turnAt(11000), 3);
      expect(o.turnAt(60000), 10);
      expect(AudioOverview.fromMeta(NotebookNote.fromJson(p3AudioClassic()).meta), isNull, reason: 'classic audio has no meta.audio');
      final broken = AudioOverview.fromMeta({
        'audio': {
          'version': 2,
          'tts_error': 'TTS_NOT_CONFIGURED',
          'turns': [
            {'speaker': 'A', 'text': 'สวัสดี', 'start_ms': null, 'end_ms': null},
          ],
        },
      })!;
      expect(broken.timed, isFalse);
      expect(broken.turnAt(0), -1);
      expect(audioStudioOptions(format: 'debate', length: 'long'), {
        'audio': {'format': 'debate', 'length': 'long', 'hosts': 2},
      });
    });

    test('chat settings and the new studio kinds', () {
      final nb = Notebook.fromJson(p3Notebook());
      final s = nb.chatSettings!;
      expect(s.goal, 'learning_guide');
      expect(s.persona, 'ครูสอนงานบริการลูกค้า');
      expect(s.length, 'shorter');
      expect(s.isDefault, isFalse);
      expect(s.summaryParts, ['ผู้ช่วยการเรียนรู้', 'บทบาทกำหนดเอง', 'สั้นลง']);
      expect(ChatSettings.fromJson(_defaults).isDefault, isTrue);
      expect(const ChatSettings(goal: 'custom', customPrompt: '  ตอบสั้น ', persona: '').toJson(), {'goal': 'custom', 'custom_prompt': 'ตอบสั้น', 'persona': null, 'length': 'default'});
      expect(ChatSettings.fromJson({'goal': 'weird', 'length': 'x'}).goal, 'default');
      expect(Notebook.fromJson({'id': 1}).chatSettings, isNull, reason: 'older servers');
      final ids = StudioKind.all.map((k) => k.id).toList();
      expect(ids, containsAll(['study_guide', 'faq', 'briefing', 'timeline', 'mindmap_json', 'audio']));
      expect(ids, isNot(contains('mindmap')), reason: 'the interactive map replaces the Mermaid tile');
      expect(StudioKind.of('mindmap')?.label, 'แผนผังความคิด', reason: 'old notes still open');
      expect(NotebookNote.fromJson(p3MindmapJson()).snippet, 'Smoke: Notebook v2');
      expect(NotebookNote.fromJson(p3Faq()).snippet, '3 คำถาม');
    });
  });

  group('A1 passage citations', () {
    testWidgets('[n] → passage sheet → source opens highlighted at start..end', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), _replies(), sse: {'POST /api/ai/chat': p3ChatSse()});
      await tester.tap(find.byKey(const ValueKey('notebook-guide-q0')));
      await settle(tester);
      expect(adapter.callKeys, contains('POST /api/ai/chat'));
      expect(_tapInlineCitation(tester, 1), isTrue);
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-citation-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-citation-passage-0')), findsOneWidget);
      expect(find.text('บันทึกประชุม'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('notebook-citation-goto')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-source-viewer')), findsOneWidget);
      expect(_highlighted(tester), 'ลูกค้า ABC แจ้งว่าใบแจ้งหนี้ออกช้ามากตั้งแต่เมื่อวาน ทีมพบว่างาน batch ตอนกลางคืนค้าง และจะแก้ภายในบ่ายนี้');
    });

    testWidgets('a passage in the middle of a long source; several passages; stale offsets fall back to the quote', (tester) async {
      final (_, config) = await pump(tester, const Scaffold(body: SizedBox()), _replies());
      final c = NotebookController(config.apiClient, '3');
      await tester.runAsync(c.load);
      final rec = c.sourceById('45')!;
      const quote = 'ผมจะส่งใบเสนอราคาให้ภายในวันศุกร์นี้ครับ';
      final at = rec.content.indexOf(quote);
      expect(at, greaterThan(100));
      final ctx = tester.element(find.byType(Scaffold));
      showCitationSheet(
        ctx,
        c,
        NotebookCitation.fromJson({
          'n': 3,
          'source_id': 45,
          'title': 'ทดสอบบันทึกเสียง REST',
          'passages': [
            {'chunk_index': 0, 'quote': 'สวัสดีครับคุณวิภา', 'start': 8, 'end': 25},
            {'chunk_index': 1, 'quote': quote, 'start': at, 'end': at + quote.length},
          ],
        }, 0),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-citation-passage-1')), findsOneWidget);
      expect(find.text('ข้อความที่ 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notebook-citation-passage-1')));
      await settle(tester);
      expect(_highlighted(tester), quote);
      Navigator.of(tester.element(find.byKey(const ValueKey('notebook-source-viewer')))).pop();
      await settle(tester);

      // Offsets from an older copy of the source: the quote is searched instead.
      showSourceViewer(ctx, c, rec, highlight: quote, start: 3000, end: 3010);
      await settle(tester);
      expect(_highlighted(tester), quote);
      Navigator.of(tester.element(find.byKey(const ValueKey('notebook-source-viewer')))).pop();
      await settle(tester);

      // Nothing matches: opens at the top with the quote shown above the text.
      showSourceViewer(ctx, c, rec, highlight: 'ข้อความที่ไม่มีในแหล่ง', start: null, end: null);
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-viewer-highlight')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-viewer-quote')), findsOneWidget);
    });
  });

  group('A3 audio overview v2', () {
    testWidgets('options sheet → POST options.audio + locale; player + transcript; tap a turn seeks and highlights', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), {
        ..._replies(),
        'POST /api/ai/notebooks/3/studio': {'item': p3Audio()},
      });
      await tester.tap(find.byKey(const ValueKey('notebook-studio-audio')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-audio-options')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audio-format-debate')));
      await tester.tap(find.text('ยาว'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('audio-generate')));
      await settle(tester, 10);
      final body = _body(_last(adapter, 'POST /api/ai/notebooks/3/studio'));
      expect(body['kind'], 'audio');
      expect(body['locale'], 'th');
      expect(body['options'], {
        'audio': {'format': 'debate', 'length': 'long', 'hosts': 2},
      });
      expect(body['source_ids'], [7, 8, 10, 11, 45, 54]);
      expect(find.byKey(const ValueKey('notebook-audio-overview')), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-overview-player')), findsOneWidget);
      expect(find.text('ผู้ดำเนินรายการ A'), findsWidgets);
      expect(find.text('ผู้ดำเนินรายการ B'), findsWidgets);
      expect(find.byKey(const ValueKey('audio-turn-current')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('audio-turn-3')));
      await settle(tester, 3);
      final ctl = tester.widget<NxAudioPlayerCard>(find.byKey(const ValueKey('audio-overview-player'))).controller!;
      expect(ctl.lastSeekMs, 10578);
      expect(find.descendant(of: find.byKey(const ValueKey('audio-turn-3')), matching: find.byKey(const ValueKey('audio-turn-current'))), findsOneWidget);
    });

    testWidgets('closing the options sheet makes nothing', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), _replies());
      await tester.tap(find.byKey(const ValueKey('notebook-studio-audio')));
      await settle(tester);
      Navigator.of(tester.element(find.byKey(const ValueKey('notebook-audio-options')))).pop();
      await settle(tester);
      expect(adapter.callKeys, isNot(contains('POST /api/ai/notebooks/3/studio')));
    });

    testWidgets('no voice (tts_error, no timings): script only with a note; classic audio unchanged', (tester) async {
      final raw = p3Audio();
      final meta = Map<String, dynamic>.from(raw['meta'] as Map)..remove('downloadUrl');
      final audio = Map<String, dynamic>.from(meta['audio'] as Map);
      audio['tts_error'] = 'TTS_NOT_CONFIGURED';
      audio['duration_ms'] = null;
      audio['turns'] = [for (final t in audio['turns'] as List) {...Map<String, dynamic>.from(t as Map), 'start_ms': null, 'end_ms': null}];
      meta['audio'] = audio;
      await note(tester, {...raw, 'meta': meta});
      expect(find.byKey(const ValueKey('notebook-audio-overview')), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-overview-no-voice')), findsOneWidget);
      expect(find.text('สร้างเสียงพูดไม่สำเร็จ'), findsOneWidget);
      expect(find.byType(NxAudioPlayerCard), findsNothing);
      expect(find.byKey(const ValueKey('audio-turn-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('audio-turn-0')));
      await settle(tester, 2);
      expect(find.byKey(const ValueKey('audio-turn-current')), findsNothing);

      await note(tester, p3AudioClassic());
      expect(find.byKey(const ValueKey('notebook-audio-overview')), findsNothing);
      expect(find.byType(NxAudioPlayerCard), findsOneWidget);
    });
  });

  group('A4 interactive mind map', () {
    testWidgets('expand / collapse a branch, all branches; root stays put', (tester) async {
      await note(tester, p3MindmapJson());
      expect(find.byKey(const ValueKey('notebook-mindtree')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindtree-node-root')), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('mindtree-node-root.$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('mindtree-node-root.0.0')), findsNothing);
      expect(find.text('+3'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('mindtree-toggle-root.0')));
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('mindtree-node-root.0.2')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindtree-node-root.1.0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mindtree-toggle-root.0')));
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('mindtree-node-root.0.2')), findsNothing);
      await settle(tester, 4);
      final rootAt = tester.getTopLeft(find.byKey(const ValueKey('mindtree-node-root')));
      await tester.tap(find.byKey(const ValueKey('mindtree-expand-all')));
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('mindtree-node-root.5.2')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindtree-node-root.3.1')), findsOneWidget);
      expect((tester.getTopLeft(find.byKey(const ValueKey('mindtree-node-root'))) - rootAt).distance, lessThan(1), reason: 'the root keeps its place on screen');
      await tester.tap(find.byKey(const ValueKey('mindtree-collapse-all')));
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('mindtree-node-root.5.2')), findsNothing);
      expect(find.byKey(const ValueKey('mindtree-node-root.5')), findsOneWidget);
      // Collapse the root itself, then zoom / fit.
      await tester.tap(find.byKey(const ValueKey('mindtree-toggle-root')));
      await settle(tester, 4);
      expect(find.byKey(const ValueKey('mindtree-node-root.0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mindtree-zoom-in')));
      await tester.tap(find.byKey(const ValueKey('mindtree-fit')));
      await settle(tester, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap a topic → "ถามในแชท" → chat tab with the question in the composer (not sent)', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), _replies(notes: [p3MindmapJson()]));
      await tester.tap(find.byKey(const ValueKey('notebook-note-107')));
      await settle(tester, 10);
      expect(find.byKey(const ValueKey('notebook-mindtree')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mindtree-node-root.2')));
      await settle(tester);
      expect(find.byKey(const ValueKey('mindtree-sheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-ref-10')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mindtree-ask')));
      await settle(tester, 12);
      expect(find.byKey(const ValueKey('notebook-mindtree')), findsNothing);
      final input = tester.widget<TextField>(find.byKey(const ValueKey('notebook-chat-input')));
      expect(input.controller!.text, 'อธิบายเรื่อง "บันทึกประชุม" จากแหล่งข้อมูล');
      expect(adapter.callKeys, isNot(contains('POST /api/ai/chat')));
    });

    testWidgets('no meta.mindmap → the Mermaid mind map as before', (tester) async {
      final raw = p3MindmapJson();
      await note(tester, {...raw, 'meta': {...Map<String, dynamic>.from(raw['meta'] as Map)}..remove('mindmap')});
      expect(find.byKey(const ValueKey('notebook-mindtree')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-mindmap')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-root')), findsOneWidget);
    });
  });

  group('A5 study guide, FAQ, briefing, timeline', () {
    testWidgets('study guide: reveal answers, essays, glossary, source chips', (tester) async {
      await note(tester, p3StudyGuide(), onDraft: (_) {});
      expect(find.byKey(const ValueKey('notebook-study-guide')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-q0')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-q0-answer')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('study-q0')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('study-q0-answer')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-q1-answer')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('study-reveal-all')));
      await settle(tester, 3);
      expect(find.text('ซ่อนเฉลยทั้งหมด'), findsOneWidget);
      await _scrollTo(tester, const ValueKey('study-q3-answer'));
      expect(find.byKey(const ValueKey('study-q3-answer')), findsOneWidget);
      await _scrollTo(tester, const ValueKey('study-tabs'), up: true);
      await tester.tap(find.text('เรียงความ'));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('study-essay-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-essay-0-ask')), findsOneWidget);
      await tester.tap(find.text('คำศัพท์'));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('study-glossary')), findsOneWidget);
      expect(find.byKey(const ValueKey('study-term-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('studio-ref-10')).first);
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-source-viewer')), findsOneWidget);
      expect(find.text('บันทึกประชุม'), findsWidgets);
    });

    testWidgets('faq accordion', (tester) async {
      await note(tester, p3Faq());
      expect(find.byKey(const ValueKey('notebook-faq')), findsOneWidget);
      expect(find.byKey(const ValueKey('faq-0-answer')), findsOneWidget, reason: 'the first answer starts open');
      expect(find.byKey(const ValueKey('faq-1-answer')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('faq-1')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('faq-1-answer')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('faq-0')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('faq-0-answer')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('faq-toggle-all')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('faq-2-answer')), findsOneWidget);
    });

    testWidgets('briefing: summary with [n], themes, quotes; a verified quote opens the source at start..end', (tester) async {
      final raw = p3Briefing();
      final meta = Map<String, dynamic>.from(raw['meta'] as Map);
      final b = Map<String, dynamic>.from(meta['briefing'] as Map);
      const text = 'ใบแจ้งหนี้ออกช้ามาก';
      const content = 'ลูกค้า ABC แจ้งว่าใบแจ้งหนี้ออกช้ามากตั้งแต่เมื่อวาน ทีมพบว่างาน batch ตอนกลางคืนค้าง และจะแก้ภายในบ่ายนี้';
      final at = content.indexOf(text);
      b['quotes'] = [
        ...b['quotes'] as List,
        {'n': 3, 'text': text, 'verified': true, 'source_id': 10, 'attribution': 'บันทึกประชุม', 'start': at, 'end': at + text.length},
      ];
      meta['briefing'] = b;
      await note(tester, {...raw, 'meta': meta});
      expect(find.byKey(const ValueKey('notebook-briefing')), findsOneWidget);
      expect(find.text('สรุปภาพรวมโน้ตบุ๊ก'), findsOneWidget);
      expect(find.byKey(const ValueKey('briefing-summary')), findsOneWidget);
      await _scrollTo(tester, const ValueKey('briefing-theme-3'));
      expect(find.byKey(const ValueKey('briefing-theme-3')), findsOneWidget);
      await _scrollTo(tester, const ValueKey('briefing-summary'), up: true);
      expect(_tapInlineCitation(tester, 2), isTrue);
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-citation-sheet')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const ValueKey('notebook-citation-sheet')))).pop();
      await settle(tester);
      // Unverified quotes do not jump into the source.
      await _scrollTo(tester, const ValueKey('briefing-quote-0'));
      expect(find.byKey(const ValueKey('briefing-quote-0-unverified')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('briefing-quote-0')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-source-viewer')), findsNothing);
      await _scrollTo(tester, const ValueKey('briefing-quote-3'));
      expect(find.byKey(const ValueKey('briefing-quote-3-verified')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('briefing-quote-3')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-source-viewer')), findsOneWidget);
      expect(_highlighted(tester), text);
    });

    testWidgets('timeline: events with dates (unknown date labelled), cast', (tester) async {
      await note(tester, p3Timeline());
      expect(find.byKey(const ValueKey('notebook-timeline')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('timeline-date-0'))).data, 'เมื่อวาน');
      await _scrollTo(tester, const ValueKey('timeline-date-3'));
      expect(tester.widget<Text>(find.byKey(const ValueKey('timeline-date-3'))).data, 'ไม่ระบุวันที่');
      await _scrollTo(tester, const ValueKey('timeline-event-4'));
      await _scrollTo(tester, const ValueKey('timeline-cast-1'));
      expect(find.text('คุณวิภา'), findsOneWidget);
      expect(find.text('ลูกค้าสาขาบางนา'), findsOneWidget);
    });

    testWidgets('without meta every kind falls back to markdown with tappable [n]; template note', (tester) async {
      for (final raw in [p3StudyGuide(), p3Faq(), p3Briefing(), p3Timeline()]) {
        final meta = {'sources': (raw['meta'] as Map)['sources'], 'generated': 'template'};
        await note(tester, {...raw, 'meta': meta});
        expect(find.byKey(const ValueKey('notebook-study-guide')), findsNothing);
        expect(find.byKey(const ValueKey('notebook-faq')), findsNothing);
        expect(find.byKey(const ValueKey('notebook-briefing')), findsNothing);
        expect(find.byKey(const ValueKey('notebook-timeline')), findsNothing);
        expect(find.byType(NxMarkdown), findsWidgets);
        expect(_tapInlineCitation(tester, 1), isTrue, reason: '${raw['artifact_kind']}: [1] links to meta.sources');
        await settle(tester);
        expect(find.byKey(const ValueKey('notebook-citation-sheet')), findsOneWidget);
        Navigator.of(tester.element(find.byKey(const ValueKey('notebook-citation-sheet')))).pop();
        await settle(tester);
      }
      await note(tester, {...p3Faq(), 'meta': {...Map<String, dynamic>.from(p3Faq()['meta'] as Map), 'generated': 'template'}});
      expect(find.byKey(const ValueKey('studio-template-note')), findsOneWidget);
    });

    testWidgets('studio tiles for the new kinds send kind + locale (th / en)', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), {
        ..._replies(),
        'POST /api/ai/notebooks/3/studio': {'item': p3Faq()},
      });
      for (final k in ['study_guide', 'faq', 'briefing', 'timeline', 'mindmap_json']) {
        expect(find.byKey(ValueKey('notebook-studio-$k')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('notebook-studio-mindmap')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('notebook-studio-faq')));
      await settle(tester, 10);
      final body = _body(_last(adapter, 'POST /api/ai/notebooks/3/studio'));
      expect(body['kind'], 'faq');
      expect(body['locale'], 'th');
      expect(body.containsKey('options'), isFalse);
      expect(find.byKey(const ValueKey('notebook-faq')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const ValueKey('notebook-faq')))).pop();
      await settle(tester, 6);
      L10n.set('en');
      addTearDown(() => L10n.set('th'));
      await tester.ensureVisible(find.byKey(const ValueKey('notebook-studio-timeline')));
      await tester.tap(find.byKey(const ValueKey('notebook-studio-timeline')));
      await settle(tester, 10);
      final en = _body(_last(adapter, 'POST /api/ai/notebooks/3/studio'));
      expect(en['kind'], 'timeline');
      expect(en['locale'], 'en');
    });
  });

  group('A7 chat settings', () {
    testWidgets('indicator; custom without a prompt is stopped; save PATCHes; 400 shows inline; reset sends null', (tester) async {
      final (adapter, _) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), {
        ..._replies(),
        'PATCH /api/ai/notebooks/3': {
          'item': {
            ..._nb(),
            'chat_settings': {'goal': 'custom', 'custom_prompt': 'ตอบเหมือนที่ปรึกษาฝ่ายขาย', 'persona': null, 'length': 'longer'},
          },
        },
      });
      expect(find.byKey(const ValueKey('notebook-chat-settings-indicator')), findsOneWidget);
      expect(find.text('ผู้ช่วยการเรียนรู้ · บทบาทกำหนดเอง · สั้นลง'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('notebook-chat-settings')));
      await settle(tester);
      expect(find.byKey(const ValueKey('notebook-chat-settings-sheet')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('chat-persona'))).controller!.text, 'ครูสอนงานบริการลูกค้า');
      await tester.tap(find.byKey(const ValueKey('chat-goal-custom')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('chat-custom-prompt')), findsOneWidget);
      expect(find.text('0/4000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-settings-save')));
      await settle(tester, 3);
      expect(find.byKey(const ValueKey('chat-settings-error')), findsOneWidget);
      expect(adapter.callKeys, isNot(contains('PATCH /api/ai/notebooks/3')));
      await tester.enterText(find.byKey(const ValueKey('chat-custom-prompt')), 'ตอบเหมือนที่ปรึกษาฝ่ายขาย');
      await tester.pump();
      expect(find.text('${'ตอบเหมือนที่ปรึกษาฝ่ายขาย'.characters.length}/4000'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-settings-error')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('chat-persona')), '');
      await tester.ensureVisible(find.text('ยาวขึ้น'));
      await tester.tap(find.text('ยาวขึ้น'));
      await tester.pump();

      // The server refuses first (400), then accepts.
      adapter.errorsFor['PATCH /api/ai/notebooks/3'] = {
        'error_code': 'SYS_400_VALIDATION',
        'message': 'chat_settings.custom_prompt is required when goal is custom',
        'details': {'field': 'chat_settings.custom_prompt'},
      };
      await tester.ensureVisible(find.byKey(const ValueKey('chat-settings-save')));
      await tester.tap(find.byKey(const ValueKey('chat-settings-save')));
      await settle(tester);
      expect(find.byKey(const ValueKey('chat-settings-error')), findsOneWidget);
      expect(find.text('กรอกคำสั่งสำหรับโหมด "กำหนดเอง" ก่อนบันทึก'), findsOneWidget);
      expect(find.byKey(const ValueKey('notebook-chat-settings-sheet')), findsOneWidget, reason: 'the sheet stays open');
      adapter.errorsFor.remove('PATCH /api/ai/notebooks/3');
      await tester.ensureVisible(find.byKey(const ValueKey('chat-settings-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-settings-save')));
      await settle(tester);
      expect(_body(_last(adapter, 'PATCH /api/ai/notebooks/3')), {
        'chat_settings': {'goal': 'custom', 'custom_prompt': 'ตอบเหมือนที่ปรึกษาฝ่ายขาย', 'persona': null, 'length': 'longer'},
      });
      expect(find.byKey(const ValueKey('notebook-chat-settings-sheet')), findsNothing);
      expect(find.text('กำหนดเอง · ยาวขึ้น'), findsOneWidget);

      // Reset → chat_settings: null; the indicator goes away.
      adapter.replies['PATCH /api/ai/notebooks/3'] = {
        'item': {..._nb(), 'chat_settings': _defaults},
      };
      await tester.tap(find.byKey(const ValueKey('notebook-chat-settings')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('chat-settings-reset')));
      await tester.tap(find.byKey(const ValueKey('chat-settings-reset')));
      await settle(tester);
      final reset = _last(adapter, 'PATCH /api/ai/notebooks/3');
      expect(_body(reset), {'chat_settings': null});
      expect(_body(reset).containsKey('chat_settings'), isTrue);
      expect(find.byKey(const ValueKey('notebook-chat-settings-indicator')), findsNothing);
    });

    testWidgets('read-only notebook: indicator only, no settings button', (tester) async {
      await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.chat), {
        ..._replies(),
        'GET /api/ai/notebooks/3': {
          'item': {..._nb(), 'can_write': false},
        },
      });
      expect(find.byKey(const ValueKey('notebook-chat-settings')), findsNothing);
      expect(find.byKey(const ValueKey('notebook-chat-settings-indicator')), findsOneWidget);
    });
  });

  group('layouts', () {
    final notes = {
      'study': p3StudyGuide,
      'faq': p3Faq,
      'briefing': p3Briefing,
      'timeline': p3Timeline,
      'mindmap': p3MindmapJson,
      'audio': p3Audio,
    };
    for (final size in const [Size(412, 915), Size(1024, 768)]) {
      for (final b in Brightness.values) {
        testWidgets('phone/tablet $size $b at text scale 1.3: no overflow', (tester) async {
          for (final e in notes.entries) {
            await note(tester, e.value(), size: size, textScale: 1.3, brightness: b);
            expect(tester.takeException(), isNull, reason: e.key);
          }
          // Expanded mind map and the sheets at 1.3 too.
          await note(tester, p3MindmapJson(), size: size, textScale: 1.3, brightness: b);
          await tester.tap(find.byKey(const ValueKey('mindtree-expand-all')));
          await settle(tester, 3);
          expect(tester.takeException(), isNull);
          final (_, config) = await pump(tester, const NotebookScreen(id: '3', initialTab: NotebookTab.studio), _replies(), size: size, textScale: 1.3, brightness: b);
          await tester.tap(find.byKey(const ValueKey('notebook-studio-audio')));
          await settle(tester);
          expect(find.byKey(const ValueKey('notebook-audio-options')), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(config, isNotNull);
        });
      }
    }
  });
}
