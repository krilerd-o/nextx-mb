// Performance round: fewer / shared / parallel requests.
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/services/api_client.dart';

import 'support/fake_api.dart';

ApiClient _api(FakeNextxAdapter fake) {
  final api = ApiClient()..attachSession(baseUrl: 'https://api.test', accessToken: 't', userId: '7', businessId: '1');
  api.debugSetHttpAdapter(fake);
  return api;
}

void main() {
  group('request de-dup', () {
    test('simultaneous getFieldSchema / getUsersCached / getModuleLabels share one request each', () async {
      final fake = FakeNextxAdapter({
        'GET /api/fields/lead': {'fields': [{'fieldname': 'firstname'}]},
        'GET /api/users': [{'id': 1, 'name': 'A'}],
        'GET /api/modules': [{'name': 'lead', 'tablabel': 'ลีด'}],
      });
      final api = _api(fake);
      final schemas = await Future.wait([for (var i = 0; i < 3; i++) api.getFieldSchema('lead')]);
      final users = await Future.wait([for (var i = 0; i < 3; i++) api.getUsersCached()]);
      final labels = await Future.wait([for (var i = 0; i < 3; i++) api.getModuleLabels()]);
      expect(fake.callKeys.where((k) => k == 'GET /api/fields/lead'), hasLength(1));
      expect(fake.callKeys.where((k) => k == 'GET /api/users'), hasLength(1));
      expect(fake.callKeys.where((k) => k == 'GET /api/modules'), hasLength(1));
      expect(schemas.every((s) => identical(s, schemas.first)), isTrue);
      expect(users.first.single['name'], 'A');
      expect(labels.first['lead']?.$1, 'ลีด');
      expect(api.debugInflightCount, 0, reason: 'finished requests are forgotten');
    });

    test('a failed shared request is not cached; the next call tries again', () async {
      final fake = FakeNextxAdapter({}, errorsFor: {'GET /api/fields/deal': {'error_code': 'X', 'message': 'boom'}}, statusFor: {'GET /api/fields/deal': 500});
      final api = _api(fake);
      final results = await Future.wait([
        for (var i = 0; i < 2; i++) api.getFieldSchema('deal').then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(results.every((r) => r is! ModuleFieldSchema), isTrue);
      expect(fake.callKeys.where((k) => k == 'GET /api/fields/deal'), hasLength(1));
      fake.errorsFor.clear();
      fake.replies['GET /api/fields/deal'] = {'fields': []};
      fake.statusFor.clear();
      await api.getFieldSchema('deal');
      expect(fake.callKeys.where((k) => k == 'GET /api/fields/deal'), hasLength(2));
    });

    test('fresh schema reads are never folded into an older request', () async {
      final fake = FakeNextxAdapter({'GET /api/fields/lead': {'fields': []}});
      final api = _api(fake);
      await Future.wait([api.getFieldSchema('lead'), api.getFieldSchema('lead', fresh: true)]);
      expect(fake.callKeys.where((k) => k == 'GET /api/fields/lead'), hasLength(2));
    });
  });
}
