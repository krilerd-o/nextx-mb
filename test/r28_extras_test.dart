import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/ai_assistant.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/effects.dart';
import 'package:nextx_mobile/core/navigation/app_routes.dart';
import 'package:nextx_mobile/core/nx_network.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_assistant_screen.dart';
import 'package:nextx_mobile/screens/ai/assistant/ai_shared_chat_screen.dart';
import 'package:nextx_mobile/services/nx_speech.dart';
import 'package:nextx_mobile/widgets/isaac_sticker.dart';

import 'support/fake_api.dart';

const _member = SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['lead', 'ai-assistant']);

final _base = <String, Object?>{
  'GET /api/ai/conversations': <Map<String, dynamic>>[],
  'GET /api/ai/usage': {'meters_cloud': false},
  'GET /api/ai/suggested-prompts': <Map<String, dynamic>>[],
};

class _FakeSpeech implements NxSpeech {
  void Function(String, bool)? onText;
  bool _on = false;
  @override
  bool get listening => _on;
  @override
  Future<bool> start({required String localeId, required void Function(String text, bool done) onText, void Function()? onStop}) async {
    this.onText = onText;
    _on = true;
    return true;
  }

  @override
  Future<void> stop() async => _on = false;
}

Future<FakeNextxAdapter> _pump(WidgetTester tester, Widget screen, {Map<String, Object?> extra = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  final config = AppConfig()..debugOverrideSession(_member);
  final adapter = FakeNextxAdapter({..._base, ...extra});
  config.apiClient.debugSetHttpAdapter(adapter);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: screen)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return adapter;
}

void main() {
  tearDown(() {
    Effects.preference.value = EffectsPreference.lite;
    NxNetwork.instance.debugSet(false);
  });

  testWidgets('Isaac GIFs: big welcome moves; small ones only with full effects off mobile data', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    Effects.preference.value = EffectsPreference.lite;
    expect(IsaacSticker.shouldAnimate(ctx, size: 104), isTrue);
    expect(IsaacSticker.shouldAnimate(ctx, size: 40), isFalse);
    Effects.preference.value = EffectsPreference.full;
    expect(IsaacSticker.shouldAnimate(ctx, size: 40), isTrue);
    NxNetwork.instance.debugSet(true);
    expect(IsaacSticker.shouldAnimate(ctx, size: 40), isFalse);
    expect(IsaacSticker.shouldAnimate(ctx, size: 104), isTrue);
    Effects.preference.value = EffectsPreference.off;
    expect(IsaacSticker.shouldAnimate(ctx, size: 104), isFalse);
  });

  testWidgets('"ถาม Isaac" from a record: context chip, prompt ready, context sent with the chat', (tester) async {
    final adapter = await _pump(
      tester,
      const AiAssistantScreen(contextModule: 'lead', contextId: '12', contextTitle: '[QA] ลูกค้า A'),
      extra: {'POST /api/ai/conversations': {'id': 'c9', 'title': 'x'}, 'POST /api/ai/conversations/c9/messages': {'ok': true}},
    );
    expect(find.byKey(const ValueKey('ai-context')), findsOneWidget);
    expect(find.textContaining('[QA] ลูกค้า A'), findsOneWidget);
    expect(find.text('สรุปรายการนี้ให้หน่อย และควรทำอะไรต่อ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-send')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final create = adapter.calls.firstWhere((c) => c.method == 'POST' && c.path == '/api/ai/conversations');
    expect(Map<String, dynamic>.from(create.data as Map)['context_module'], 'lead');
    expect(Map<String, dynamic>.from(create.data as Map)['context_id'], 12);
    final chat = adapter.calls.firstWhere((c) => c.path == '/api/ai/chat');
    final body = Map<String, dynamic>.from(chat.data as Map);
    expect(body['context_module'], 'lead');
    expect(body['context_id'], '12');
    expect(AppRoutes.aiAsk(module: 'lead', id: '12', title: 'A B'), '/ai?ctx_module=lead&ctx_id=12&ctx_title=A+B');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('mic: speech fills the box; tap again stops', (tester) async {
    final fake = _FakeSpeech();
    final old = NxSpeech.instance;
    NxSpeech.instance = fake;
    addTearDown(() => NxSpeech.instance = old);
    await _pump(tester, const AiAssistantScreen());
    await tester.tap(find.byKey(const ValueKey('ai-mic')));
    await tester.pump();
    fake.onText!('[QA] นัดลูกค้าพรุ่งนี้', false);
    await tester.pump();
    expect(find.text('[QA] นัดลูกค้าพรุ่งนี้'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-mic')));
    await tester.pump();
    expect(fake.listening, isFalse);
    await tester.pump(const Duration(seconds: 4));
  });

  test('share links use the web route /share/ai/:token and open in the app', () {
    expect(aiShareUrl('https://qa.test', {'token': 'abc'}), 'https://qa.test/share/ai/abc');
    expect(aiInAppRoute('https://qa.test/share/ai/abc', serverOrigin: 'https://qa.test'), '/share/ai/abc');
  });

  testWidgets('shared chat opens read-only with the messages', (tester) async {
    await _pump(tester, const AiSharedChatScreen(token: 'abc'), extra: {
      'GET /api/ai/shared/abc': {
        'share': {'title': '[QA] สรุปยอดขาย', 'owner_display': 'QA Second'},
        'snapshot': {
          'messages': [
            {'role': 'user', 'content': '[QA] ขอสรุป'},
            {'role': 'assistant', 'content': '**ยอดขาย** เดือนนี้ 10 รายการ', 'model': 'gemini-2.5-flash'},
          ],
        },
      },
    });
    expect(find.text('[QA] สรุปยอดขาย'), findsOneWidget);
    expect(find.text('[QA] ขอสรุป'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-input')), findsNothing);
  });
}
