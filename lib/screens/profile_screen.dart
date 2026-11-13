
import 'package:flutter/material.dart';
import '../widgets/nx_scroll_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/nx_breakpoint.dart';
import '../services/device_push_service.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_surface_card.dart';
import '../widgets/nx_icons.dart';
import 'settings_screen.dart';
import '../core/i18n.dart';

/// "ความปลอดภัยขั้นสูง" (จัดการความปลอดภัย → ขั้นสูง): push token for
/// testing and the 2FA placeholder. Photo, profile, phone, signatures and the
/// password have their own pages in the profile area.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfig>();

    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ความปลอดภัยขั้นสูง'),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          Text(
            tr('สำหรับผู้ดูแลและการทดสอบ · v${SettingsScreen.appVersion}'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            child: Column(
              children: [
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
