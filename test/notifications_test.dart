import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/mail/mail_home_screen.dart';
import 'package:nextx_mobile/screens/notifications/notification_center_screen.dart';
import 'package:nextx_mobile/services/realtime_service.dart';
import 'package:nextx_mobile/services/unread_service.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';

void main() {
  test('summary parsing follows the NEXTX {total, by_category} shape', () {
    expect(parseUnreadSummary({'total': 7, 'by_category': {'chat': 7}}), 7);
    expect(parseUnreadSummary({'unread': 3}), 3);
    expect(
      parseUnreadSummary({
        'list': [
          {'unread': 2},
          {'count': 1},
        ],
      }),
      3,
    );
    expect(parseUnreadSummary({}), 0);
  });

  test('realtime notification bumps the shared counter; read lowers it', () async {
    final u = UnreadNotifications.instance;
    u.clear();
    RealtimeService.instance.dispatchForTest('notification', {'id': 1});
    await Future<void>.delayed(Duration.zero);
    expect(u.count, 1);
    u.markedRead();
    u.markedRead();
    expect(u.count, 0);
  });

  test('relative time labels', () {
    final now = DateTime(2026, 11, 6, 12);
    expect(relativeTime(now.subtract(const Duration(seconds: 20)).toIso8601String(), now: now), 'เมื่อสักครู่');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)).toIso8601String(), now: now), '5 นาทีที่แล้ว');
    expect(relativeTime(now.subtract(const Duration(hours: 3)).toIso8601String(), now: now), '3 ชั่วโมงที่แล้ว');
    expect(relativeTime(null), '');
  });

  test('icon by type', () {
    expect(notificationIcon({'link_path': '/camp?room=1'}), NxI.chatCircle);
    expect(notificationIcon({'type': 'quotation_approval'}), NxI.receipt);
    expect(notificationIcon({}), NxI.bell);
  });

  test('mail realtime filter', () {
    expect(isMailRealtimeEvent(const RealtimeEvent('mail:new', {})), isTrue);
    expect(isMailRealtimeEvent(const RealtimeEvent('notification', {'link_path': '/mail?open=3'})), isTrue);
    expect(isMailRealtimeEvent(const RealtimeEvent('notification', {'link_path': '/camp?room=1'})), isFalse);
    expect(isMailRealtimeEvent(const RealtimeEvent('new_message', {})), isFalse);
  });
}
