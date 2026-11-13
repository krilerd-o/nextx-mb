import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/screens/profile/change_password_screen.dart';
import 'package:nextx_mobile/screens/profile/delete_account_screen.dart';
import 'package:nextx_mobile/screens/profile/my_signatures_screen.dart';
import 'package:nextx_mobile/screens/profile/notification_prefs_screen.dart';
import 'package:nextx_mobile/screens/profile/phone_change_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_hub_screen.dart';
import 'package:nextx_mobile/screens/profile/profile_manage_screen.dart';
import 'package:nextx_mobile/screens/profile/security_settings_screen.dart';
import 'package:nextx_mobile/screens/profile/theme_settings_screen.dart';
import 'package:nextx_mobile/screens/profile_edit_screen.dart';
import 'package:nextx_mobile/screens/settings/devices_screen.dart';
import 'package:nextx_mobile/screens/settings_screen.dart';
import 'package:nextx_mobile/screens/whats_new/whats_new_screen.dart';

import 'support/profile_harness.dart';

final _replies = <String, Object?>{
  'GET /api/me/profile': {
    'profile': {
      'first_name': 'Somchai',
      'last_name': 'Jaidee',
      'first_name_th': 'สมชาย',
      'last_name_th': 'ใจดีมากๆ นามสกุลยาว',
      'email1': 'somchai.jaidee.longname@example-company.co.th',
      'phone_mobile': '0811111111',
      'title': 'ผู้จัดการฝ่ายขายและบริการลูกค้าภาคตะวันออกเฉียงเหนือ',
      'department': 'ฝ่ายขาย',
      'address_street': '99/9 ถนนพระราม 9',
      'user_language': 'th',
      'weekstart': 1,
      'hour_format': '24',
    },
  },
  'GET /api/me/sessions': {
    'current_sid': 'me',
    'list': [
      {'sid': 'me', 'client': 'mobile', 'platform': 'android', 'device_name': 'Samsung Galaxy S24 Ultra 5G', 'app_version': '1.4.0', 'current': true},
      {'sid': 'w', 'client': 'web', 'platform': 'windows', 'user_agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/120 Safari/537', 'ip': '203.0.113.9', 'location': 'กรุงเทพมหานคร ประเทศไทย', 'last_seen_at': '2026-11-10T03:00:00Z'},
    ],
  },
  'GET /api/me/verify/methods': {
    'email': {'available': true, 'masked': 'so•••@example-company.co.th'},
    'sms': {'available': false, 'reason': 'no_phone'},
    'password': {'available': true},
  },
  'GET /api/me/signatures': {'upload_signature_th': null},
  'GET /api/me/notification-preferences': {
    'channels': [
      {'key': 'in_app', 'label_th': 'ในแอป (เว็บและแอป)', 'label_en': 'In-app'},
      {'key': 'push', 'label_th': 'พุช', 'label_en': 'Push'},
    ],
    'push_paused': false,
    'groups': [
      {
        'key': 'work',
        'label_th': 'งาน',
        'events': [
          {'key': 'a', 'label_th': 'มีคนมอบหมายงานให้คุณในบอร์ดที่คุณเป็นสมาชิก', 'description_th': 'รวมถึงงานย่อยและการเปลี่ยนผู้รับผิดชอบ', 'channels': {'in_app': true, 'push': true}},
          {'key': 'b', 'label_th': 'ประกาศ', 'channels': {'in_app': true, 'push': true}, 'locked': true},
        ],
      },
    ],
  },
  'GET /api/whats-new': [
    {'id': 1, 'type': 'improvement', 'version': '1.4.0', 'title_th': 'ปรับปรุงหน้าโปรไฟล์', 'description_th': '<p>สั้นๆ</p>', 'date': '2026-11-13'},
  ],
};

final _pages = <String, Widget Function()>{
  'hub': () => const ProfileHubScreen(),
  'manage': () => const ProfileManageScreen(),
  'edit': () => const ProfileEditScreen(),
  'phone': () => const PhoneChangeScreen(currentPhone: '0811111111'),
  'delete': () => const DeleteAccountScreen(),
  'theme': () => const ThemeSettingsScreen(),
  'devices': () => const DevicesScreen(),
  'signatures': () => const MySignaturesScreen(),
  'security': () => const SecuritySettingsScreen(),
  'password': () => const ChangePasswordScreen(),
  'notifications': () => NotificationPrefsScreen(permission: () async => true),
  'whats-new': () => const WhatsNewScreen(),
  'settings': () => const SettingsScreen(),
};

void main() {
  for (final size in const [Size(412, 915), Size(1024, 1366)]) {
    for (final b in Brightness.values) {
      testWidgets('every profile page lays out at ${size.width.toInt()}×${size.height.toInt()} ${b.name}, text ×1.3', (tester) async {
        for (final p in _pages.entries) {
          await pumpProfilePage(tester, p.value(), _replies, size: size, brightness: b, textScale: 1.3);
          expect(tester.takeException(), isNull, reason: p.key);
          // Scroll to the bottom too.
          final list = find.byType(Scrollable);
          if (list.evaluate().isNotEmpty) {
            await tester.fling(list.first, const Offset(0, -3000), 3000);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '${p.key} (bottom)');
          }
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
