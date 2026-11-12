
import 'package:flutter/material.dart';
import '../widgets/nx_scroll_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/nx_breakpoint.dart';
import '../services/api_client.dart';
import '../services/device_push_service.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_hero_cta.dart';
import '../widgets/nx_surface_card.dart';
import '../widgets/nx_icons.dart';
import 'profile/change_password_screen.dart';
import 'profile/my_signatures_screen.dart';
import 'profile/phone_verify_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';
import '../core/nx_page_route.dart';
import '../core/i18n.dart';

/// Phase 7 — โปรไฟล์, ภาษา/รูปแบบวันที่, รหัสผ่าน/2FA placeholder, accent, avatar (C1)
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfig>();
    final email = config.session.email ?? '—';
    final image = config.profileAvatarImage;
    final avatar = CircleAvatar(
      radius: 48,
      backgroundColor: theme.colorScheme.primaryContainer,
      backgroundImage: image,
      onBackgroundImageError: image == null ? null : (_, _) {},
      child: image == null ? Icon(NxI.userFill, size: 48, color: theme.colorScheme.primary) : null,
    );

    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ความปลอดภัยขั้นสูง'),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          NxSurfaceCard(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              children: [
                avatar,
                const SizedBox(height: 12),
                Text(tr(email), style: theme.textTheme.titleMedium),
                Text(
                  tr('v${SettingsScreen.appVersion}'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  tr('รูปโปรไฟล์อัปโหลดไปเซิร์ฟเวอร์'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                NxHeroCta(
                  label: 'เลือกรูป',
                  onPressed: () async {
                    try {
                      await config.uploadProfileAvatarToServer();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr(formatApiError(e)))),
                        );
                      }
                    }
                  },
                ),
                if (config.profileAvatarUrl == null && (config.profileAvatarBase64 ?? '').isNotEmpty)
                  TextButton(
                    onPressed: () => config.clearProfileAvatar(),
                    child: Text(tr('ลบรูป')),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      nxPush<bool>(context, const ProfileEditScreen()),
                  icon: const Icon(NxI.pencilSimple),
                  label: Text(tr('แก้ไขข้อมูลส่วนตัว')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr('ความปลอดภัย'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(NxI.pencilSimple),
                  title: Text(tr('ลายเซ็นของฉัน')),
                  subtitle: Text(tr('ใช้บนใบเสนอราคาและเอกสาร (TH / EN)')),
                  trailing: const Icon(NxI.caretRight),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MySignaturesScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(NxI.phone),
                  title: Text(tr('ยืนยันเบอร์มือถือ')),
                  subtitle: Text(tr('ใช้เข้าสู่ระบบด้วย OTP SMS')),
                  trailing: const Icon(NxI.caretRight),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PhoneVerifyScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(NxI.password),
                  title: Text(tr('เปลี่ยนรหัสผ่าน')),
                  subtitle: Text(tr('ยืนยันด้วย OTP ทางอีเมลหรือ SMS')),
                  onTap: () => showChangePasswordDialog(context),
                ),
                ListTile(
                  leading: const Icon(NxI.bell),
                  title: Text(tr('โทเคนพุช (FCM)')),
                  subtitle: Text(
                    tr(
                      DevicePushService.instance.lastToken == null ||
                              DevicePushService.instance.lastToken!.isEmpty
                          ? 'ยังไม่มี — เปิดแอปบนมือถือจริงแล้วล็อกอิน'
                          : DevicePushService.instance.lastToken!,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    var token = DevicePushService.instance.lastToken;
                    if (token == null || token.isEmpty) {
                      await config.syncPushToken();
                      token = DevicePushService.instance.lastToken;
                    }
                    if (token == null || token.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(
                                'ยังไม่มีโทเคน — ใช้แอปบน Android หลังวาง google-services.json',
                              ),
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: token));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'คัดลอกโทเคนแล้ว — วางใน Firebase Cloud Messaging เพื่อทดสอบ',
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(NxI.shieldCheck),
                  title: Text(tr('Two-factor (2FA)')),
                  subtitle: Text(tr('ยังไม่เปิดใช้บนเซิร์ฟเวอร์มือถือ')),
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(tr('Two-factor authentication')),
                        content: Text(
                          tr(
                            'แอปยังไม่มี endpoint 2FA จาก NEXTX web API '
                            'เมื่อเซิร์ฟเวอร์เปิดใช้ จะเชื่อมจากหน้านี้',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(tr('ปิด')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Change-password dialog (current + new + confirm), used by the profile hub.
/// Opens "เปลี่ยนรหัสผ่าน" (OTP by email / SMS instead of the old password).
Future<void> showChangePasswordDialog(BuildContext context) =>
    nxPush<bool>(context, const ChangePasswordScreen());
