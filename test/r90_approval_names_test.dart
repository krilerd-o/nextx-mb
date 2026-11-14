import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/entity_display.dart';
import 'package:nextx_mobile/core/service_journey.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/screens/crm/entity_detail_screen.dart';
import 'package:nextx_mobile/screens/journey/approval_request_sheet.dart';

import 'support/fake_api.dart';

/// `/api/users` rows exactly as the server sends them (no `name` /
/// `display_name` — the old sheet fell back to the id: "16", "22", "2").
const _users = [
  {'id': 2, 'first_name': 'Somchai', 'last_name': 'Jaidee', 'first_name_th': 'สมชาย', 'last_name_th': 'ใจดี', 'email1': 'somchai@example.com', 'user_name': 'somchai', 'title': 'ผู้จัดการฝ่ายขาย'},
  {'id': 16, 'first_name': 'Suda', 'last_name': 'Rakdee', 'first_name_th': '', 'last_name_th': '', 'email1': 'suda@example.com', 'user_name': 'suda'},
  {'id': 22, 'first_name': 'Anan', 'last_name': 'Boonmee', 'first_name_th': 'อนันต์', 'last_name_th': 'บุญมี', 'email1': 'anan@example.com', 'department': 'บัญชี'},
];

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _body(FakeNextxAdapter a, String key) {
  final c = a.calls.lastWhere((c) => '${c.method.toUpperCase()} ${c.path}' == key);
  final d = c.data;
  return d is Map ? Map<String, dynamic>.from(d) : jsonDecode('$d') as Map<String, dynamic>;
}

Future<FakeNextxAdapter> _pumpQuotation(WidgetTester tester, {List<Object> lastCandidates = const [16, 22, 2], Map<String, Map<String, Object?>>? errorsFor}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  ServiceJourney.debugClear();
  const qt = {
    'id': 9,
    'quotation_no': 'QT-9',
    'subject': '[QA] R90',
    'quotation_status': 'เปิดใบเสนอราคา',
    'approval_state': 'none',
    'offer_status': 'เสนอราคา',
    'grand_total': 12500,
  };
  final adapter = FakeNextxAdapter({
    'GET /api/fields/quotation': {'list': [], 'picklists': {}},
    'GET /api/settings/job': {'config': {}},
    'GET /api/links/quotation/9': {'quotations': [], 'jobs': [], 'activities': []},
    'GET /api/entity/quotation/9': qt,
    'GET /api/entity/quotation/9/comments': {'list': []},
    'GET /api/entity/quotation/9/tags': {'list': []},
    'GET /api/tags': {'list': []},
    'GET /api/quotation/9/approval-history': {'state': 'none', 'steps': []},
    'GET /api/quotation/9/revisions': {'list': []},
    'GET /api/quotation/9/lines': {
      'list': [
        {'id': 1, 'description': 'A', 'qty': 1, 'price': 12500},
      ],
    },
    'GET /api/quotation/9/customer-activity': {'link_sent': false},
    'GET /api/users': {'list': _users},
    'GET /api/settings/quotation': {
      'config': {
        'approval': {
          'required': true,
          'levels': [
            {'level': 1, 'enabled': true, 'label': 'หัวหน้าทีม', 'mode': 'any', 'candidates': [16]},
            {'level': 2, 'enabled': true, 'label': 'ผู้บริหาร', 'mode': 'any', 'candidates': lastCandidates},
          ],
        },
      },
    },
    'POST /api/quotation/9/approval/submit': {'ok': true},
  }, errorsFor: errorsFor);
  final config = AppConfig();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '2', businessId: '1', menusLoaded: true, menuKeys: ['job', 'quotation', 'activity']));
  config.apiClient.debugSetHttpAdapter(adapter);
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: config,
    child: MaterialApp(home: EntityDetailScreen(key: UniqueKey(), module: 'quotation', row: const {'id': 9})),
  ));
  await _frames(tester);
  return adapter;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('next-action-submit_approval')));
  await _frames(tester);
}

/// The sheet alone, with a controllable user directory.
Future<List<Map<String, dynamic>>?> _pumpSheet(
  WidgetTester tester, {
  required Future<List<Map<String, dynamic>>> Function() loadUsers,
  List<ApprovalLevel>? levels,
  Future<void> Function(List<Map<String, dynamic>>)? onSubmit,
  Map<int, Set<String>> preselected = const {},
}) async {
  List<Map<String, dynamic>>? result;
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async {
              result = await showModalBottomSheet<List<Map<String, dynamic>>>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ApprovalRequestSheet(
                    levels: levels ??
                        const [
                          ApprovalLevel(level: 1, label: 'หัวหน้าทีม', candidates: ['16']),
                          ApprovalLevel(level: 2, label: 'ผู้บริหาร', candidates: ['16', '22', '2']),
                        ],
                    loadUsers: loadUsers,
                    onSubmit: onSubmit,
                    preselected: preselected,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return result;
}

/// Text shown on approver rows (never a bare id).
List<String> _rowTexts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.descendant(
        of: find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('approver-')),
        matching: find.byType(Text),
      )))
        t.data ?? '',
    ];

bool _enabled(WidgetTester tester) {
  final b = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('approval-submit')));
  return b.onPressed != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('userFullName: Thai name when there is one, else first + last; subtitle = position or e-mail', () {
    expect(userFullName(Map<String, dynamic>.from(_users[0])), 'สมชาย ใจดี');
    expect(userFullName(Map<String, dynamic>.from(_users[0]), thai: false), 'Somchai Jaidee');
    expect(userFullName(Map<String, dynamic>.from(_users[1])), 'Suda Rakdee');
    expect(userSubtitle(Map<String, dynamic>.from(_users[0])), 'ผู้จัดการฝ่ายขาย');
    expect(userSubtitle(Map<String, dynamic>.from(_users[1])), 'suda@example.com');
    expect(userSubtitle(Map<String, dynamic>.from(_users[2])), 'บัญชี');
  });

  testWidgets('quotation "ส่งขออนุมัติ": approvers by name (not ids), one section per level', (tester) async {
    await _pumpQuotation(tester);
    await _openSheet(tester);
    // The ids the owner saw as chip labels are gone.
    final texts = _rowTexts(tester);
    expect(texts, isNotEmpty);
    for (final id in ['16', '22', '2']) {
      expect(texts, isNot(contains(id)), reason: id);
      expect(find.widgetWithText(FilterChip, id), findsNothing);
    }
    expect(find.text('ระดับ 1'), findsOneWidget);
    expect(find.text('ระดับสุดท้าย · ต้องเลือก'), findsOneWidget);
    final last = find.byKey(const ValueKey('approval-level-2'));
    expect(find.descendant(of: last, matching: find.text('สมชาย ใจดี')), findsOneWidget);
    expect(find.descendant(of: last, matching: find.text('Suda Rakdee')), findsOneWidget);
    expect(find.descendant(of: last, matching: find.text('อนันต์ บุญมี')), findsOneWidget);
    // Subtitles: position / department / e-mail.
    expect(find.descendant(of: last, matching: find.text('ผู้จัดการฝ่ายขาย')), findsOneWidget);
    expect(find.descendant(of: last, matching: find.text('suda@example.com')), findsOneWidget);
    // Level 1 offers only its candidate.
    final first = find.byKey(const ValueKey('approval-level-1'));
    expect(find.descendant(of: first, matching: find.text('Suda Rakdee')), findsOneWidget);
    expect(find.descendant(of: first, matching: find.text('สมชาย ใจดี')), findsNothing);
  });

  testWidgets('send is enabled only once the last level has someone; the body still carries user ids', (tester) async {
    final a = await _pumpQuotation(tester);
    await _openSheet(tester);
    expect(_enabled(tester), isFalse);
    expect(find.byKey(const ValueKey('approval-need-last')), findsOneWidget);
    // Level 1 alone is not enough.
    await tester.tap(find.byKey(const ValueKey('approver-1-16')));
    await _frames(tester, 2);
    expect(_enabled(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('approver-2-22')));
    await _frames(tester, 2);
    expect(_enabled(tester), isTrue);
    expect(find.byKey(const ValueKey('approval-need-last')), findsNothing);
    // Toggle off and on again.
    await tester.tap(find.byKey(const ValueKey('approver-2-22')));
    await _frames(tester, 2);
    expect(_enabled(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('approver-2-22')));
    await tester.tap(find.byKey(const ValueKey('approver-2-2')));
    await _frames(tester, 2);
    await tester.tap(find.byKey(const ValueKey('approval-submit')));
    await _frames(tester);
    expect(_body(a, 'POST /api/quotation/9/approval/submit')['levels'], [
      {
        'level': 1,
        'user_ids': [16],
      },
      {
        'level': 2,
        'user_ids': [22, 2],
      },
    ]);
    expect(find.byKey(const ValueKey('approval-submit')), findsNothing);
    expect(find.text('ส่งขออนุมัติแล้ว'), findsOneWidget);
  });

  testWidgets('a candidate missing from the user directory → "ผู้ใช้ #id", still selectable', (tester) async {
    await _pumpQuotation(tester, lastCandidates: [22, 99]);
    await _openSheet(tester);
    final last = find.byKey(const ValueKey('approval-level-2'));
    expect(find.descendant(of: last, matching: find.text('อนันต์ บุญมี')), findsOneWidget);
    expect(find.descendant(of: last, matching: find.text('ผู้ใช้ #99')), findsOneWidget);
    expect(_rowTexts(tester), isNot(contains('99')));
  });

  testWidgets('the server rejects the request → error in the sheet, it stays open', (tester) async {
    final a = await _pumpQuotation(tester, errorsFor: {
      'POST /api/quotation/9/approval/submit': {'error_code': 'VALIDATION', 'message': 'ต้องเลือกผู้อนุมัติระดับสุดท้าย'},
    });
    await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('approver-2-22')));
    await _frames(tester, 2);
    await tester.tap(find.byKey(const ValueKey('approval-submit')));
    await _frames(tester);
    expect(a.callKeys, contains('POST /api/quotation/9/approval/submit'));
    expect(find.byKey(const ValueKey('approval-send-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('approval-submit')), findsOneWidget);
    expect(find.text('ส่งขออนุมัติแล้ว'), findsNothing);
  });

  testWidgets('while the names load: placeholders, no ids, send disabled', (tester) async {
    final users = Completer<List<Map<String, dynamic>>>();
    await _pumpSheet(tester, loadUsers: () => users.future, preselected: const {
      2: {'22'},
    });
    expect(find.byKey(const ValueKey('approver-skeleton-2-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('approver-skeleton-1-0')), findsOneWidget);
    expect(_rowTexts(tester).where((t) => t.isNotEmpty), isEmpty);
    for (final id in ['16', '22', 'ผู้ใช้ #16']) {
      expect(find.text(id), findsNothing, reason: id);
    }
    expect(find.byKey(const ValueKey('approver-2-22')), findsNothing);
    expect(_enabled(tester), isFalse);
    users.complete([for (final u in _users) Map<String, dynamic>.from(u)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('approver-skeleton-2-0')), findsNothing);
    expect(find.text('อนันต์ บุญมี'), findsOneWidget);
    // Pre-selected from the previous chain → ready to send.
    expect(_enabled(tester), isTrue);
  });

  testWidgets('directory fails → error with retry, approvers as "ผู้ใช้ #id"; retry shows names', (tester) async {
    var fail = true;
    await _pumpSheet(tester, loadUsers: () async {
      if (fail) throw Exception('network');
      return [for (final u in _users) Map<String, dynamic>.from(u)];
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('approval-users-error')), findsOneWidget);
    expect(find.text('ผู้ใช้ #22'), findsOneWidget);
    expect(_rowTexts(tester), isNot(contains('22')));
    fail = false;
    await tester.tap(find.byKey(const ValueKey('approval-users-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('approval-users-error')), findsNothing);
    expect(find.text('อนันต์ บุญมี'), findsOneWidget);
    expect(find.text('ผู้ใช้ #22'), findsNothing);
  });

  testWidgets('without onSubmit the sheet returns the levels as ids (step form / callers)', (tester) async {
    List<Map<String, dynamic>>? got;
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            key: const ValueKey('open'),
            onPressed: () async {
              got = await showModalBottomSheet<List<Map<String, dynamic>>>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => SingleChildScrollView(
                  child: ApprovalRequestSheet(
                    levels: const [ApprovalLevel(level: 1)],
                    loadUsers: () async => [for (final u in _users) Map<String, dynamic>.from(u)],
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // No candidates → every business user is offered.
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(find.text('ผู้อนุมัติ · ต้องเลือก'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('approver-1-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('approval-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(got, [
      {
        'level': 1,
        'user_ids': [2],
      },
    ]);
  });
}
