// Performance round: detail / list / task screens ask in parallel and only once.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/crm_home_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/crm/entity_list_screen.dart';
import 'package:nextx_mobile/screens/workspace/task_detail_screen.dart';

import 'support/fake_api.dart';

/// Answers after [delay] (real time) and records when each request started / ended.
class _SlowAdapter implements HttpClientAdapter {
  _SlowAdapter(this.inner);
  final FakeNextxAdapter inner;
  static const delay = Duration(milliseconds: 40);
  final events = <(String, String)>[]; // (start|end, METHOD /path)

  int startOf(String key) => events.indexWhere((e) => e.$1 == 'start' && e.$2 == key);
  int endOf(String key) => events.indexWhere((e) => e.$1 == 'end' && e.$2 == key);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final key = '${o.method.toUpperCase()} ${o.path}';
    events.add(('start', key));
    await Future<void>.delayed(delay);
    final r = await inner.fetch(o, s, c);
    events.add(('end', key));
    return r;
  }

  @override
  void close({bool force = false}) {}
}

Future<AppConfig> _config(WidgetTester tester, HttpClientAdapter adapter, {List<String> menus = const ['lead', 'workspace']}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  config.debugOverrideSession(SessionState(accessToken: 't', userId: '7', businessId: '1', menusLoaded: true, menuKeys: menus));
  config.apiClient.debugSetHttpAdapter(adapter);
  return config;
}

Future<void> _pump(WidgetTester tester, AppConfig config, Widget home) async {
  await tester.pumpWidget(ChangeNotifierProvider.value(value: config, child: MaterialApp(home: home)));
}

Future<void> _wait(WidgetTester tester, {int ms = 400}) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

void main() {
  testWidgets('entity detail: record, comments, tags, tag catalog and schema all start before any answers', (tester) async {
    final slow = _SlowAdapter(FakeNextxAdapter({
      'GET /api/entity/lead/1': {'id': 1, 'lastname': '[QA] ลีดเร็ว', 'status': 'New'},
      'GET /api/entity/lead/1/comments': [],
      'GET /api/entity/lead/1/tags': [],
      'GET /api/tags': [],
      'GET /api/fields/lead': {'fields': [{'name': 'lastname', 'label': 'นามสกุล'}]},
      'GET /api/users': [],
    }));
    final config = await _config(tester, slow);
    await _pump(tester, config, const EntityDetailScreen(module: 'lead', row: {'id': '1'}));
    await _wait(tester);
    const keys = [
      'GET /api/entity/lead/1',
      'GET /api/entity/lead/1/comments',
      'GET /api/entity/lead/1/tags',
      'GET /api/tags',
      'GET /api/fields/lead',
    ];
    final firstEnd = [for (final k in keys) slow.endOf(k)].reduce((a, b) => a < b ? a : b);
    for (final k in keys) {
      expect(slow.startOf(k), greaterThanOrEqualTo(0), reason: '$k asked');
      expect(slow.startOf(k), lessThan(firstEnd), reason: '$k overlaps the others (was one after another)');
      expect(slow.events.where((e) => e == ('start', k)), hasLength(1), reason: '$k once');
    }
    expect(find.text('[QA] ลีดเร็ว'), findsWidgets);
    await _done(tester);
  });

  testWidgets('CRM home tiles ask for real totals (with_total=1, cols=id)', (tester) async {
    final fake = FakeNextxAdapter({
      'GET /api/entity/lead': {'list': [{'id': 1}], 'total': 1234},
    });
    final config = await _config(tester, fake, menus: const ['lead']);
    await _pump(tester, config, const CrmHomeScreen());
    await _wait(tester, ms: 200);
    final call = fake.calls.firstWhere((c) => c.path == '/api/entity/lead');
    expect(call.queryParameters['with_total'], '1');
    expect(call.queryParameters['cols'], 'id');
    expect(call.queryParameters['limit'], '1');
    await _done(tester);
  });

  testWidgets('entity list: page 1 waits for the default view (fetched once), then reuses saved columns', (tester) async {
    final fake = FakeNextxAdapter({
      'GET /api/customviews': {
        'views': [
          {'id': 5, 'name': 'ของฉัน', 'is_default': true},
        ],
        'default_id': 5,
      },
      'GET /api/fields/lead': {'fields': [{'name': 'lastname', 'label': 'นามสกุล'}, {'name': 'lead_status', 'label': 'สถานะ'}]},
      'GET /api/entity/lead': {'list': [{'id': 1, 'lastname': '[QA] A'}], 'total': 1},
    });
    final config = await _config(tester, fake, menus: const ['lead']);
    await _pump(tester, config, const EntityListScreen(module: 'lead', title: 'ลีด'));
    await _wait(tester);
    final lists = fake.calls.where((c) => c.path == '/api/entity/lead').toList();
    expect(lists, hasLength(1), reason: 'not once without the view and again with it');
    final cv = lists.single.queryParameters['cv_id'];
    final views = fake.calls.where((c) => c.path == '/api/customviews');
    expect(views, hasLength(1));
    expect(cv == null || cv == '5', isTrue);
    expect(lists.single.queryParameters['cols'], isNotNull, reason: 'slim rows from the schema');

    // Second visit: the saved columns let page 1 go out alongside the schema.
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getKeys().any((k) => k.startsWith('nx_list_cols_lead_')), isTrue);
    await _done(tester);
  });

  testWidgets('task detail: watchers + links with the item; board statuses / epics / board cached 60 s', (tester) async {
    TaskBoardMetaCache.instance.invalidate();
    final slow = _SlowAdapter(FakeNextxAdapter({
      // The item itself is read through the board's task list (?ids=9).
      'GET /api/boards/3/tasks': [{'id': 9, 'title': '[QA] งาน', 'board_id': 3, 'type': 'task'}],
      'GET /api/boards/3/statuses': [{'id': 1, 'name': 'To do'}],
      'GET /api/boards/3/epics': {'list': []},
      'GET /api/boards/3': {'id': 3, 'code': 'QA', 'name': 'บอร์ด'},
      'GET /api/boards/3/items/task/9/watchers': {'list': []},
      'GET /api/boards/3/items/task/9/links': {'list': []},
      'GET /api/users': [],
    }));
    final config = await _config(tester, slow);
    Widget screen() => const TaskDetailScreen(task: {'id': 9, 'board_id': 3, 'title': '[QA] งาน', 'type': 'task'});
    await _pump(tester, config, screen());
    await _wait(tester);
    final itemEnd = slow.endOf('GET /api/boards/3/tasks');
    for (final side in ['GET /api/boards/3/items/task/9/watchers', 'GET /api/boards/3/items/task/9/links']) {
      expect(slow.startOf(side), greaterThanOrEqualTo(0), reason: side);
      expect(slow.startOf(side), lessThan(itemEnd), reason: '$side no longer waits for the item');
    }
    // Open the task again (back and forth): statuses / epics / board come from the cache.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, config, screen());
    await _wait(tester);
    for (final k in ['GET /api/boards/3/statuses', 'GET /api/boards/3/epics']) {
      expect(slow.events.where((e) => e == ('start', k)), hasLength(1), reason: '$k once in 60 s');
    }
    await _done(tester);
  });
}
