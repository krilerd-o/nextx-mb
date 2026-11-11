import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/screens/deep_link_loaders.dart';

void main() {
  test('approval notification opens the approval tab', () {
    expect(notificationDeepLink('/modules/quotation/view/12', linkId: '12', extra: 'quotation_approval'), '/crm/quotation/12?tab=approval');
    expect(notificationDeepLink('/modules/quotation/view/12', extra: 'quotation_rejected'), '/crm/quotation/12?tab=approval');
    expect(notificationDeepLink('/modules/quotation/view/12', extra: 'quotation_customer_signed'), '/crm/quotation/12?tab=summary');
    expect(notificationDeepLink('/modules/job/view/5', extra: 'job_forward'), contains('/job/5?tab=summary'));
    expect(notificationDeepLink('/modules/quotation/view/12'), '/crm/quotation/12');
    expect(notificationDeepLink('/modules/case?open=7', extra: 'status_change'), '/crm/case/7');
  });

  test('push data carries the extra', () {
    expect(notificationDeepLinkFromData({'url': '/modules/quotation/view/3', 'id': '99', 'extra': 'quotation_approval'}), '/crm/quotation/3?tab=approval');
  });

  test('routes that can open beside a list', () {
    expect(nxPaneForRoute('/crm/quotation/3?tab=approval'), isA<EntityByIdLoader>());
    expect((nxPaneForRoute('/crm/quotation/3?tab=approval')! as EntityByIdLoader).tab, 'approval');
    expect(nxPaneForRoute('/calendar/8'), isA<ActivityByIdLoader>());
    expect(nxPaneForRoute('/workspace'), isNull);
  });
}
