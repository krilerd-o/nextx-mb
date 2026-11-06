import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/server_profile.dart';
import '../core/shell_tabs.dart';
import '../core/app_version.dart';
import '../core/navigation/app_routes.dart';
import '../core/nx_breakpoint.dart';
import '../services/app_lock.dart';
import 'update_required_screen.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_app_logo.dart';
import '../widgets/nx_surface_card.dart';
import '../widgets/nx_icons.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Installed app version (package_info_plus; `--dart-define=APP_VERSION=` overrides).
  static String get appVersion => AppVersion.value;

  /// Release builds lock the API endpoint; QA builds can re-enable with
  /// `--dart-define=ALLOW_API_URL_EDIT=true`.
  static const bool _allowApiUrlEditInRelease = bool.fromEnvironment('ALLOW_API_URL_EDIT');
  static bool get canEditApiUrl => !kReleaseMode || _allowApiUrlEditInRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final config = context.watch<AppConfig>();

    return Scaffold(
      appBar: const NxAppHeader(title: 'ตั้งค่า'),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          Text(
            'About',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: const NxAppLogo(size: 40),
              title: const Text('MOAI NEXT Mobile'),
              subtitle: Text('Version $appVersion'),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'พื้นที่ทำงาน',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(NxI.buildings, color: colorScheme.primary),
                  title: Text(config.session.businessName ?? 'ธุรกิจ'),
                  subtitle: const Text('สลับธุรกิจ'),
                  trailing: const Icon(NxI.caretRight),
                  onTap: () => config.clearBusiness(),
                ),
                ListTile(
                  leading: Icon(NxI.package, color: colorScheme.primary),
                  title: Text('Package: ${(config.session.packageCode ?? '').isEmpty ? '—' : config.session.packageCode}'),
                  subtitle: const Text('สลับ Package (เมนูเปลี่ยนตาม Package)'),
                  trailing: const Icon(NxI.caretRight),
                  onTap: () => config.clearPackage(),
                ),
                ListTile(
                  leading: Icon(NxI.squaresFour, color: colorScheme.primary),
                  title: const Text('ปรับแต่งเมนูล่าง'),
                  subtitle: const Text('เลือกและเรียงแท็บที่ต้องการ'),
                  trailing: const Icon(NxI.caretRight),
                  onTap: () => context.push(AppRoutes.tabEditor),
                ),
                ListTile(
                  leading: Icon(NxI.users, color: colorScheme.primary),
                  title: const Text('บทบาทของฉัน'),
                  subtitle: Text(roleSummary(config.shellConfig?.roles ?? const [])),
                  trailing: const Icon(NxI.caretRight),
                  onTap: () => context.push(AppRoutes.roleEditor),
                ),
              ],
            ),
          ),
          if (config.updateNeed == UpdateNeed.optional) ...[
            const SizedBox(height: 20),
            NxSurfaceCard(
              onTap: storeUrlFor(config.serverInfo) == null ? null : () => openStore(config.serverInfo),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ListTile(
                leading: Icon(NxI.arrowsClockwise, color: colorScheme.primary),
                title: Text('มีแอปเวอร์ชันใหม่ ${config.serverInfo?.latestVersion ?? ''}'),
                subtitle: Text('เวอร์ชันในเครื่อง ${AppVersion.value}'),
                trailing: storeUrlFor(config.serverInfo) == null ? null : const Icon(NxI.caretRight),
              ),
            ),
          ],
          const _AppLockCard(),
          const SizedBox(height: 20),
          NxSurfaceCard(
            onTap: () => context.push(AppRoutes.diagnostics),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.warningCircle, color: colorScheme.primary),
              title: const Text('บันทึกปัญหา'),
              subtitle: const Text('ส่งข้อมูลให้ทีมพัฒนาเมื่อพบปัญหา'),
              trailing: const Icon(NxI.caretRight),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'เซิร์ฟเวอร์',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            onTap: () => _changeServer(context, config),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.globe, color: colorScheme.primary),
              title: Text(serverLabel(config.apiBaseUrl)),
              subtitle: const Text('ระบบ MOAI NEXT ที่เชื่อมต่ออยู่ · แตะเพื่อเปลี่ยน'),
              trailing: const Icon(NxI.caretRight),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Appearance',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(NxI.palette, color: colorScheme.primary),
                  title: const Text('Theme'),
                  subtitle: Text(_themeModeLabel(config.themeMode)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(NxI.moon)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(NxI.sun)),
                      ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(NxI.deviceMobile)),
                    ],
                    selected: {config.themeMode},
                    onSelectionChanged: (Set<ThemeMode> selected) {
                      config.setThemeMode(selected.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'โปรไฟล์',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            onTap: () => context.push(AppRoutes.profile),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.user, color: colorScheme.primary),
              title: const Text('โปรไฟล์และความปลอดภัย'),
              subtitle: const Text('ภาษา, รูปแบบวันที่, accent, เปลี่ยนรหัสผ่าน'),
              trailing: const Icon(NxI.caretRight),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'บัญชี',
            style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          NxSurfaceCard(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ออกจากระบบ?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ออก')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await context.read<AppConfig>().logout();
              }
            },
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              leading: Icon(NxI.signOut, color: colorScheme.error),
              title: Text('ออกจากระบบ', style: TextStyle(color: colorScheme.error)),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Shared DB • PostgreSQL • MongoDB • Node.js',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.system:
        return 'System';
    }
  }

  /// Switching servers signs out (sessions belong to one server).
  static Future<void> _changeServer(BuildContext context, AppConfig config) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เปลี่ยนเซิร์ฟเวอร์?'),
        content: const Text('ต้องออกจากระบบก่อน แล้วเลือกเซิร์ฟเวอร์และเข้าสู่ระบบใหม่'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ออกและเปลี่ยน')),
        ],
      ),
    );
    if (ok != true) return;
    await config.logout();
    await config.resetServerChoice();
  }
}

/// "ปลดล็อกด้วยลายนิ้วมือ / ใบหน้า" — hidden on devices without it.
class _AppLockCard extends StatefulWidget {
  const _AppLockCard();

  @override
  State<_AppLockCard> createState() => _AppLockCardState();
}

class _AppLockCardState extends State<_AppLockCard> {
  bool _supported = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppLock.instance.isSupported().then((v) {
      if (mounted) setState(() => _supported = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    final lock = AppLock.instance;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: NxSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ListenableBuilder(
          listenable: lock,
          builder: (context, _) => SwitchListTile(
            secondary: Icon(NxI.fingerprint, color: Theme.of(context).colorScheme.primary),
            title: const Text('ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า'),
            subtitle: const Text('ขอสแกนเมื่อเปิดแอป หรือกลับมาหลังพักเกิน 5 นาที'),
            value: lock.enabled,
            onChanged: _busy
                ? null
                : (v) async {
                    setState(() => _busy = true);
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await lock.setEnabled(v);
                    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('ยืนยันตัวตนไม่สำเร็จ')));
                    if (mounted) setState(() => _busy = false);
                  },
          ),
        ),
      ),
    );
  }
}
