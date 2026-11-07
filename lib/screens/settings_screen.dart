import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/nx_scroll_scaffold.dart';
import '../core/effects.dart';
import '../widgets/app_bottom_sheet.dart';
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
import '../widgets/nx_icons.dart';
import 'spaces/space_switcher.dart' show showSpaceSwitcher;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Installed app version (package_info_plus; `--dart-define=APP_VERSION=` overrides).
  static String get appVersion => AppVersion.value;

  /// Release builds lock the API endpoint; QA builds can re-enable with
  /// `--dart-define=ALLOW_API_URL_EDIT=true`.
  static const bool _allowApiUrlEditInRelease = bool.fromEnvironment(
    'ALLOW_API_URL_EDIT',
  );
  static bool get canEditApiUrl => !kReleaseMode || _allowApiUrlEditInRelease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final session = config.session;
    final sp = config.activeSpace;
    final pad = NxBreakpoint.of(context).scrollPadding(context);
    final dark =
        config.themeMode == ThemeMode.dark ||
        (config.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return NxScrollScaffold(
      insetBody: false,
      header: const NxAppHeader(title: 'ตั้งค่า'),
      body: Builder(
        builder: (context) => ListView(
          padding: pad.copyWith(
            top: pad.top + NxScrollScaffold.topInset(context),
          ),
          children: [
            _ProfileCard(onTap: () => context.push(AppRoutes.profile)),
            const _Section('Space ของคุณ'),
            _Row(
              icon: NxI.buildings,
              title:
                  sp?.title ??
                  session.businessName ??
                  serverLabel(config.apiBaseUrl),
              subtitle: [
                serverLabel(config.apiBaseUrl),
                if ((session.email ?? '').isNotEmpty) session.email!,
              ].join(' · '),
              trailing: Text(
                'ปัจจุบัน',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            _Row(
              icon: NxI.arrowsClockwise,
              title: config.spaces.length > 1
                  ? 'สลับ Space (${config.spaces.length})'
                  : 'สลับ / เพิ่ม Space',
              onTap: () => showSpaceSwitcher(context),
            ),
            _Row(
              icon: NxI.deviceMobile,
              title: 'อุปกรณ์ที่เข้าใช้งาน',
              onTap: () => context.push(AppRoutes.devices),
            ),
            const _Section('ธุรกิจและเมนู'),
            _Row(
              icon: NxI.briefcase,
              title: session.businessName ?? 'ธุรกิจ',
              subtitle: 'สลับธุรกิจ',
              onTap: () => config.clearBusiness(),
            ),
            _Row(
              icon: NxI.package,
              title:
                  'Package: ${(session.packageCode ?? '').isEmpty ? '—' : session.packageCode}',
              subtitle: 'สลับ Package (เมนูเปลี่ยนตาม Package)',
              onTap: () => config.clearPackage(),
            ),
            _Row(
              icon: NxI.squaresFour,
              title: 'ปรับแต่งเมนูล่าง',
              subtitle: 'เลือกและเรียงแท็บที่ต้องการ',
              onTap: () => context.push(AppRoutes.tabEditor),
            ),
            _Row(
              icon: NxI.user,
              title: 'บทบาทของฉัน',
              subtitle: roleSummary(config.shellConfig?.roles ?? const []),
              onTap: () => context.push(AppRoutes.roleEditor),
            ),
            const _Section('การตั้งค่า'),
            _Row(
              icon: NxI.moon,
              title: 'โหมดมืด',
              subtitle: config.themeMode == ThemeMode.system
                  ? 'ตามเครื่อง · กดค้างเพื่อกลับไปตามเครื่อง'
                  : 'กดค้างเพื่อให้ตามเครื่อง',
              onLongPress: () => config.setThemeMode(ThemeMode.system),
              trailing: Switch(
                value: dark,
                onChanged: (v) =>
                    config.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
              ),
            ),
            ValueListenableBuilder<EffectsPreference>(
              valueListenable: Effects.preference,
              builder: (context, pref, _) => _Row(
                icon: NxI.sparkle,
                title: 'เอฟเฟกต์และความลื่น',
                subtitle: pref.label,
                onTap: () => showAppBottomSheet<void>(
                  context: context,
                  title: 'เอฟเฟกต์และความลื่น',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in EffectsPreference.values)
                        ListTile(
                          title: Text(p.label),
                          trailing: p == pref
                              ? Icon(NxI.check, color: cs.primary)
                              : null,
                          onTap: () async {
                            await Effects.setPreference(p);
                            if (context.mounted) Navigator.pop(context);
                            config.refreshUi();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _Row(
              icon: NxI.bell,
              title: 'การแจ้งเตือน',
              onTap: () => context.push(AppRoutes.notifications),
            ),
            _Row(
              icon: NxI.shieldCheck,
              title: 'โปรไฟล์และความปลอดภัย',
              subtitle: 'ภาษา, รูปแบบวันที่, สีหลัก, เปลี่ยนรหัสผ่าน',
              onTap: () => context.push(AppRoutes.profile),
            ),
            const _AppLockCard(),
            const _Section('เกี่ยวกับ'),
            _Row(
              icon: NxI.info,
              title: 'MOAI NEXT Mobile',
              subtitle: 'เวอร์ชัน $appVersion',
            ),
            if (config.updateNeed == UpdateNeed.optional)
              _Row(
                icon: NxI.arrowSquareOut,
                title:
                    'มีแอปเวอร์ชันใหม่ ${config.serverInfo?.latestVersion ?? ''}',
                subtitle: 'เวอร์ชันในเครื่อง ${AppVersion.value}',
                onTap: storeUrlFor(config.serverInfo) == null
                    ? null
                    : () => openStore(config.serverInfo),
              ),
            _Row(
              icon: NxI.clipboardText,
              title: 'บันทึกปัญหา',
              subtitle: 'ส่งข้อมูลให้ทีมพัฒนาเมื่อพบปัญหา',
              onTap: () => context.push(AppRoutes.diagnostics),
            ),
            const SizedBox(height: 12),
            _Row(
              icon: NxI.signOut,
              color: cs.error,
              title: 'ออกจากระบบ Space นี้',
              subtitle: config.spaces.length > 1
                  ? 'Space อื่นยังใช้งานได้ตามเดิม'
                  : null,
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ออกจากระบบ?'),
                    content: Text(
                      'ออกจาก ${sp?.title ?? serverLabel(config.apiBaseUrl)} บนเครื่องนี้',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ยกเลิก'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('ออก'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await config.logout();
              },
            ),
          ],
        ),
      ),
    );
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
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => _Row(
        icon: NxI.fingerprint,
        title: 'ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า',
        subtitle: 'ขอสแกนเมื่อเปิดแอป หรือกลับมาหลังพักเกิน 5 นาที',
        trailing: Switch(
          value: lock.enabled,
          onChanged: _busy
              ? null
              : (v) async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await lock.setEnabled(v);
                  if (!ok)
                    messenger.showSnackBar(
                      const SnackBar(content: Text('ยืนยันตัวตนไม่สำเร็จ')),
                    );
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ),
    );
  }
}

/// Profile card: gradient avatar, role chip, name, business · package.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final s = config.session;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = config.activeSpace?.color ?? cs.primary;
    final name = s.displayName ?? s.email ?? 'ผู้ใช้';
    final role = (s.businessRole ?? (s.isBusinessAdmin ? 'admin' : 'member'))
        .toUpperCase();
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.lerp(color, Colors.black, 0.15)!,
                      color,
                      Color.lerp(color, Colors.white, 0.35)!,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
                child: Text(
                  name.characters.take(2).toString().toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        role,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        s.businessName ?? '',
                        s.packageCode ?? '',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small grey uppercase section label.
class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Plain settings row: line icon, title (+ subtitle), trailing or chevron.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.color,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
