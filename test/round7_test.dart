import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/session_state.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/offline_queue.dart';

import 'support/fake_api.dart';

const _clockIn = 'POST /api/hr/attendance/clock-in';
const _clockOut = 'POST /api/hr/attendance/clock-out';

Map<String, dynamic> _health(List<String> features) => {
      'app': 'MOAI NEXT API',
      'signature': 'aisystem',
      'mobile': {'features': features},
    };

Future<AppConfig> _config(FakeNextxAdapter adapter, {List<String> features = const ['offline_attendance']}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  adapter.replies['GET /api/health'] = _health(features);
  final config = AppConfig();
  config.apiClient.debugSetHttpAdapter(adapter);
  while (!config.isReady) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  config.debugOverrideSession(const SessionState(accessToken: 't', userId: '7', businessId: '3'));
  await config.refreshServerInfo(force: true);
  return config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('online punch is sent right away', () async {
    final adapter = FakeNextxAdapter({_clockIn: {'attendance': {}}});
    final config = await _config(adapter);
    expect(await config.punch(clockIn: true, lat: 13.7, lng: 100.5), isFalse);
    final body = adapter.calls.lastWhere((c) => c.path == '/api/hr/attendance/clock-in').data as Map;
    expect(body.containsKey('offline'), isFalse);
    expect(await config.pendingPunches(), isEmpty);
  });

  test('offline punch keeps the device time and is sent later with it', () async {
    final adapter = FakeNextxAdapter({_clockIn: {'attendance': {}}, _clockOut: {'attendance': {}}}, offline: {_clockIn, _clockOut});
    final config = await _config(adapter);
    final before = DateTime.now().toUtc();
    expect(await config.punch(clockIn: true, lat: 13.7, lng: 100.5), isTrue);
    expect(await config.punch(clockIn: false, lat: 13.7, lng: 100.5), isTrue);
    expect((await config.pendingPunches()).map((e) => e['dir']), ['in', 'out']);
    expect(OfflineQueue.pending.value, 2);

    // still offline: nothing is lost, order kept
    await config.flushOfflineQueue();
    expect((await config.pendingPunches()).length, 2);

    adapter.offline.clear();
    await config.flushOfflineQueue();
    expect(await config.pendingPunches(), isEmpty);
    final sent = adapter.calls.where((c) => c.path.startsWith('/api/hr/attendance/clock-')).toList();
    final inBody = sent[sent.length - 2].data as Map;
    final outBody = sent.last.data as Map;
    expect(sent[sent.length - 2].path, '/api/hr/attendance/clock-in');
    expect(sent.last.path, '/api/hr/attendance/clock-out');
    expect(inBody['offline'], isTrue);
    final at = DateTime.parse(inBody['client_time'] as String);
    expect(at.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    expect(outBody['offline'], isTrue);
  });

  test('a punch the server refuses is kept and shown, never dropped', () async {
    final adapter = FakeNextxAdapter({_clockIn: {'attendance': {}}}, offline: {_clockIn});
    final config = await _config(adapter);
    await config.punch(clockIn: true, lat: 1, lng: 1);
    adapter.offline.clear();
    adapter.replies.remove(_clockIn); // server answers an error now
    await config.flushOfflineQueue();
    expect(await config.pendingPunches(), isEmpty);
    expect(config.failedPunches.length, 1);
    expect(config.failedPunches.single['dir'], 'in');
    expect(config.failedPunches.single['error'], isNotNull);
    await config.dismissFailedPunch(config.failedPunches.single);
    expect(config.failedPunches, isEmpty);
  });

  test('another account\'s queued punch is never sent as the current user', () async {
    final adapter = FakeNextxAdapter({_clockIn: {'attendance': {}}}, offline: {_clockIn});
    final config = await _config(adapter);
    await config.punch(clockIn: true, lat: 1, lng: 1);
    config.debugOverrideSession(const SessionState(accessToken: 't2', userId: '8', businessId: '3'));
    adapter.offline.clear();
    final callsBefore = adapter.calls.where((c) => c.path == '/api/hr/attendance/clock-in').length;
    await config.flushOfflineQueue();
    expect(adapter.calls.where((c) => c.path == '/api/hr/attendance/clock-in').length, callsBefore);
    expect((await config.pendingPunches()).single['user_id'], '7');
  });

  test('old server without offline support: the error is shown, nothing queued', () async {
    final adapter = FakeNextxAdapter({}, offline: {_clockIn});
    final config = await _config(adapter, features: const []);
    expect(() => config.punch(clockIn: true, lat: 1, lng: 1), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await config.pendingPunches(), isEmpty);
  });

  test('leave files are uploaded as files[] and removal keeps them on the server', () async {
    final adapter = FakeNextxAdapter({
      'POST /api/hr/leave-requests/5/attachments': {
        'attachments': [
          {'id': 'a1', 'name': 'cert.pdf', 'mime': 'application/pdf', 'url': '/api/hr/leave-requests/5/attachments/a1'},
        ],
      },
      'DELETE /api/hr/leave-requests/5/attachments/a1': {'attachments': []},
    });
    final config = await _config(adapter);
    final list = await config.apiClient.uploadLeaveAttachments('5', [(bytes: const [37, 80, 68, 70], name: 'cert.pdf')]);
    expect(list.single['name'], 'cert.pdf');
    final form = adapter.calls.last.data;
    expect(form.files.single.key, 'files[]');
    expect(await config.apiClient.removeLeaveAttachment('5', 'a1'), isEmpty);
  });
}
