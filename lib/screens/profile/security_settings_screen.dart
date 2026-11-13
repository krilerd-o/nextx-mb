import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/settings_tiles.dart';
import 'change_password_screen.dart';
import 'profile_ui.dart';

/// "จัดการความปลอดภัย": the app lock (fingerprint / face) on this device,
/// changing the password (step-up verified), and the advanced page (push
/// token, 2FA).
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    var i = 0;
    return ProfileSubPage(
      title: 'จัดการความปลอดภัย',
      children: [
        SettingsAppear(
          index: i++,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.alphaBlend(const Color(0xFF0EA5E9).withValues(alpha: 0.16), cs.surfaceContainerHighest), cs.surfaceContainerHighest],
              ),
            ),
            child: Row(children: [
              const ProfileHeroIcon(icon: NxI.shieldCheck, color: Color(0xFF0EA5E9), size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('ปกป้องบัญชีของคุณ'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    tr('ล็อกแอปบนเครื่องนี้ และเปลี่ยนรหัสผ่านหลังยืนยันตัวตน'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        SettingsAppear(
          index: i++,
          child: const SettingsGroup(
            title: 'ล็อกแอป',
            caption: 'ใช้ลายนิ้วมือหรือใบหน้าของเครื่องนี้',
            children: [AppLockTile()],
          ),
        ),
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'รหัสผ่าน',
            children: [
              SettingsTile(
                key: const ValueKey('sec-change-password'),
                icon: NxI.password,
                tint: const Color(0xFFF59E0B),
                title: 'เปลี่ยนรหัสผ่าน',
                subtitle: 'ยืนยันด้วย OTP อีเมล / SMS หรือรหัสผ่านปัจจุบัน',
                onTap: () => nxPush<bool>(context, const ChangePasswordScreen()),
              ),
            ],
          ),
        ),
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'ขั้นสูง',
            children: [
              SettingsTile(
                key: const ValueKey('sec-advanced'),
                icon: NxI.lockKeyhole,
                tint: const Color(0xFF64748B),
                title: 'ความปลอดภัยขั้นสูง',
                subtitle: 'โทเคนพุช, 2FA',
                onTap: () => context.push(AppRoutes.profileSecurity),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
