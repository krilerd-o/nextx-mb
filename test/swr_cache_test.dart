import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/nx_swr_cache.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/widgets/nx_cached_future.dart';
import 'package:nextx_mobile/widgets/nx_skeleton.dart';

import 'support/fake_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    NxSwrCache.instance.reset();
  });

  group('NxSwrCache', () {
    test('keys sort the query and skip empty values', () {
      expect(NxSwrCache.key('/api/leave/requests', query: {'status': 'pending', 'all': 1, 'q': ''}), 'GET /api/leave/requests?all=1&status=pending');
      expect(NxSwrCache.key('/api/x', method: 'post'), 'POST /api/x');
    });

    test('LRU keeps at most capacity answers, dropping the least used', () {
      final c = NxSwrCache.instance..scope = 's1';
      for (var i = 0; i < NxSwrCache.capacity; i++) {
        c.put('GET /k$i', i);
      }
      expect(c.peek<int>('GET /k0'), 0); // touched → most recent
      c.put('GET /new', 1);
      expect(c.length, NxSwrCache.capacity);
      expect(c.peek<int>('GET /k0'), 0);
      expect(c.peek<int>('GET /k1'), isNull);
      expect(c.peek<String>('GET /new'), isNull, reason: 'wrong type reads as a miss');
    });

    test('scope change (Space switch / sign-out) drops the answers', () {
      final c = NxSwrCache.instance..scope = 'a';
      c.put('GET /api/leave', [1]);
      c.scope = 'b';
      expect(c.peek<List<int>>('GET /api/leave'), isNull);
      c.put('GET /api/leave', [2]);
      c.scope = '';
      expect(c.length, 0);
      c.put('GET /api/leave', [3]);
      expect(c.length, 0, reason: 'nothing is kept while signed out');
    });

    test('a write drops its API area only', () {
      final c = NxSwrCache.instance..scope = 'a';
      c.put(NxSwrCache.key('/api/leave/requests'), 1);
      c.put(NxSwrCache.key('/api/leave/balance', query: {'year': 2026}), 2);
      c.put(NxSwrCache.key('/api/chat/rooms'), 3);
      c.invalidateForWrite('/api/leave/requests/9/cancel');
      expect(c.has(NxSwrCache.key('/api/leave/requests')), isFalse);
      expect(c.has(NxSwrCache.key('/api/leave/balance', query: {'year': 2026})), isFalse);
      expect(c.has(NxSwrCache.key('/api/chat/rooms')), isTrue);
      expect(NxSwrCache.writeArea('/api/auth/logout'), isNull);
    });

    test('persisted answers come back from disk for the same Space, and go on sign-out', () async {
      final c = NxSwrCache.instance..scope = 'disk';
      c.put('GET /api/notifications', [
        {'id': 1},
      ], persist: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.reset();
      c.scope = 'disk';
      await c.warm();
      expect(c.peek<List<dynamic>>('GET /api/notifications'), isNotNull);
      c.scope = '';
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.scope = 'disk';
      await c.warm();
      expect(c.peek<List<dynamic>>('GET /api/notifications'), isNull);
    });
  });

  testWidgets('API writes invalidate cached answers of that area', (tester) async {
    final config = AppConfig();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '1'));
    final adapter = FakeNextxAdapter({'PUT /api/hr/leave-requests/5/cancel': {'ok': true}});
    config.apiClient.debugSetHttpAdapter(adapter);
    NxSwrCache.instance.put(NxSwrCache.key('/api/hr/leave-requests'), [1]);
    await tester.runAsync(() => config.apiClient.cancelLeave('5'));
    expect(NxSwrCache.instance.has(NxSwrCache.key('/api/hr/leave-requests')), isFalse);
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('second open shows the cached answer at once (no skeleton), then refreshes', (tester) async {
    NxSwrCache.instance.scope = 'w';
    var calls = 0;
    Completer<List<String>>? pending;
    Widget page() => MaterialApp(
          home: Scaffold(
            body: NxCachedFuture<List<String>>(
              cacheKey: NxSwrCache.key('/api/things'),
              load: () {
                calls++;
                pending = Completer<List<String>>();
                return pending!.future;
              },
              builder: (context, d) => ListView(children: [for (final s in d) Text(s)]),
            ),
          ),
        );

    await tester.pumpWidget(page());
    expect(find.byType(NxSkeletonList), findsOneWidget);
    pending!.complete(['หนึ่ง']);
    await tester.pump();
    expect(find.text('หนึ่ง'), findsOneWidget);

    // Leave and come back: cached data first, no skeleton, refresh line while loading.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    expect(calls, 2);
    expect(find.byType(NxSkeletonList), findsNothing);
    expect(find.text('หนึ่ง'), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-refresh-bar')), findsOneWidget);
    final state = tester.state<NxCachedFutureState<List<String>>>(find.byType(NxCachedFuture<List<String>>));
    expect(state.debugFromCache, isTrue);

    pending!.complete(['หนึ่ง', 'สอง']);
    await tester.pump();
    expect(find.text('สอง'), findsOneWidget);
    expect(find.byKey(const ValueKey('nx-refresh-bar')), findsNothing);
    expect(NxSwrCache.instance.peek<List<String>>(NxSwrCache.key('/api/things')), ['หนึ่ง', 'สอง']);
  });

  testWidgets('the cache is per Space: a switch shows the skeleton again', (tester) async {
    NxSwrCache.instance.scope = 'space-a';
    NxSwrCache.instance.put(NxSwrCache.key('/api/things'), ['เก่า']);
    NxSwrCache.instance.scope = 'space-b';
    final done = Completer<List<String>>();
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<ValueNotifier<int>>(
        create: (_) => ValueNotifier(0),
        child: Scaffold(
          body: NxCachedFuture<List<String>>(
            cacheKey: NxSwrCache.key('/api/things'),
            load: () => done.future,
            builder: (context, d) => ListView(children: [for (final s in d) Text(s)]),
          ),
        ),
      ),
    ));
    expect(find.text('เก่า'), findsNothing);
    expect(find.byType(NxSkeletonList), findsOneWidget);
    done.complete(const []);
    await tester.pump();
  });
}
