import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/app_version.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_page_route.dart';
import '../../core/ui_font.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart' show NxLanguagePill;
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/settings_tiles.dart';
import '../hub/package_picker_screen.dart' show kPackageHints;
import '../spaces/add_space_sheet.dart';
import '../spaces/space_switcher.dart';
import '../../widgets/nx_workspace_switcher.dart' show showWorkspaceSwitcherSheet;
import 'my_signatures_screen.dart';
import 'notification_prefs_screen.dart';
import 'profile_manage_screen.dart';
import 'profile_ui.dart';
import 'security_settings_screen.dart';
import 'theme_settings_screen.dart';

/// The profile menu, top to bottom (keys `profile-menu-<id>`).
const kProfileMenuOrder = ['theme', 'devices', 'signatures', 'security', 'notifications', 'whats-new', 'settings'];

/// "โปรไฟล์" (avatar tap): who I am (with "จัดการโปรไฟล์" and "สลับ Space"),
/// my Spaces, then one menu row per area — theme, devices, signatures,
/// security, notifications, what's new, settings — each its own page.
/// Editing the profile is reached from "จัดการโปรไฟล์" (no button at the bottom).
class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  Future<void> _photo(AppConfig config) async {
    final has = config.profileAvatarUrl == null && (config.profileAvatarBase64 ?? '').isNotEmpty;
    final pick = await showAppBottomSheet<String>(
      context: context,
      title: 'รูปโปรไฟล์',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(NxI.image), title: Text(tr('เลือกรูปใหม่')), onTap: () => Navigator.pop(context, 'pick')),
        if (has)
          ListTile(
            leading: Icon(NxI.trash, color: Theme.of(context).colorScheme.error),
            title: Text(tr('ลบรูป'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(context, 'clear'),
          ),
      ]),
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (pick == 'pick') await config.uploadProfileAvatarToServer();
      if (pick == 'clear') await config.clearProfileAvatar();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
    }
  }

  Future<void> _logout(AppConfig config) async {
    if (await confirmNxLogout(context, config)) await config.logout();
  }

  String _themeSummary(AppConfig c) {
    final mode = switch (c.themeMode) { ThemeMode.light => 'สว่าง', ThemeMode.dark => 'มืด', _ => 'ตามเครื่อง' };
    return '${tr(mode)} · ${uiFontById(c.uiFontId).label} · ${(c.uiScale * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    var i = 0;

    final menu = <String, Widget>{
      'theme': SettingsTile(
        icon: NxI.palette,
        tint: const Color(0xFF8B5CF6),
        title: 'จัดการธีม',
        subtitle: _themeSummary(config),
        onTap: () => nxPush<void>(context, const ThemeSettingsScreen()),
      ),
      'devices': SettingsTile(
        icon: NxI.monitorSmartphone,
        tint: const Color(0xFF0EA5E9),
        title: 'จัดการอุปกรณ์',
        subtitle: 'เครื่องนี้และอุปกรณ์อื่น · เมนู บทบาท หน้าหลัก',
        onTap: () => context.push(AppRoutes.devices),
      ),
      'signatures': SettingsTile(
        icon: NxI.signature,
        tint: const Color(0xFFEC4899),
        title: 'จัดการลายเซ็น',
        subtitle: 'ลายเซ็น TH / EN บนใบเสนอราคาและเอกสาร',
        onTap: () => nxPush<void>(context, const MySignaturesScreen()),
      ),
      'security': SettingsTile(
        icon: NxI.shieldCheck,
        tint: const Color(0xFF10B981),
        title: 'จัดการความปลอดภัย',
        subtitle: 'ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า · เปลี่ยนรหัสผ่าน',
        onTap: () => nxPush<void>(context, const SecuritySettingsScreen()),
      ),
      'notifications': SettingsTile(
        icon: NxI.bell,
        tint: const Color(0xFFF43F5E),
        title: 'จัดการการแจ้งเตือน',
        subtitle: 'ในแอปและพุช เลือกได้ทีละเรื่อง',
        onTap: () => nxPush<void>(context, const NotificationPrefsScreen()),
      ),
      'whats-new': SettingsTile(
        icon: NxI.megaphone,
        tint: const Color(0xFFF59E0B),
        title: 'มีอะไรใหม่',
        subtitle: '${tr('เวอร์ชัน')} ${AppVersion.value}',
        onTap: () => context.push(AppRoutes.whatsNew),
      ),
      'settings': SettingsTile(
        icon: NxI.gear,
        tint: const Color(0xFF64748B),
        title: 'การตั้งค่า',
        subtitle: 'ข้อมูลในเครื่อง เกี่ยวกับแอป ช่วยเหลือ',
        onTap: () => context.push(AppRoutes.settings),
      ),
    };

    return ProfileSubPage(
      title: 'โปรไฟล์',
      actions: [
        NxLanguagePill(code: config.uiLocaleCode, onChanged: config.setUiLocaleCode),
        IconButton(
          key: const ValueKey('profile-open-settings'),
          tooltip: tr('การตั้งค่า'),
          icon: const Icon(NxI.gear),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
      children: [
        SettingsAppear(index: i++, child: _Hero(onPhoto: () => _photo(config))),

        // ── One row per area, each its own page.
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'บัญชีและการตั้งค่า', children: [
            for (final id in kProfileMenuOrder) KeyedSubtree(key: ValueKey('profile-menu-$id'), child: menu[id]!),
          ]),
        ),

        // ── พื้นที่ทำงานของฉัน (just above logout): one compact card — company with
        // its package capsule, then "สลับแพ็กเกจ" and "เพิ่มพื้นที่ทำงาน" side by side.
        const SizedBox(height: 4),
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'พื้นที่ทำงานของฉัน', children: [
            _CompanyPackageRow(onTap: () => showWorkspaceSwitcherSheet(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
              child: Row(children: [
                Expanded(
                  child: _MiniAction(
                    key: const ValueKey('profile-ws-switch-package'),
                    icon: NxI.arrowsLeftRight,
                    label: 'สลับแพ็กเกจ',
                    onTap: () => showWorkspaceSwitcherSheet(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniAction(
                    key: const ValueKey('profile-ws-add'),
                    icon: NxI.plus,
                    label: 'เพิ่มพื้นที่ทำงาน',
                    onTap: () => showAddSpaceSheet(context),
                  ),
                ),
              ]),
            ),
            // Several workspaces (other accounts / domains): switch between them here.
            if (config.spaces.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _MiniAction(
                  key: const ValueKey('profile-ws-switch-space'),
                  icon: NxI.arrowsClockwise,
                  label: 'สลับพื้นที่ทำงาน',
                  onTap: () => showSpaceSwitcher(context),
                ),
              ),
          ]),
        ),

        const SizedBox(height: 22),
        SettingsAppear(
          index: i++,
          child: NxLogoutButton(
            onPressed: () => _logout(config),
            subtitle: config.activeSpace?.title == null ? null : tr('เฉพาะ ${config.activeSpace!.title}'),
          ),
        ),
        if (config.spaces.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('พื้นที่ทำงานอื่นยังใช้งานได้ตามเดิม'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),

        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(
            'MOAI NEXT Mobile ${AppVersion.value}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
          ),
        ),
      ],
    );
  }
}

/// Compact theme switch on the profile card: three icon segments with a
/// sliding thumb (ระบบ / สว่าง / มืด), same height as "จัดการโปรไฟล์".
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static const _modes = [(ThemeMode.system, NxI.deviceMobile, 'ระบบ'), (ThemeMode.light, NxI.sun, 'สว่าง'), (ThemeMode.dark, NxI.moon, 'มืด')];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i = _modes.indexWhere((m) => m.$1 == mode).clamp(0, 2);
    return Container(
      key: const ValueKey('profile-theme-toggle'),
      height: 44,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: cs.outlineVariant)),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / 3;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            left: w * i,
            top: 0,
            bottom: 0,
            width: w,
            child: DecoratedBox(decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99))),
          ),
          Row(children: [
            for (final (m, icon, label) in _modes)
              Expanded(
                child: Tooltip(
                  message: tr(label),
                  child: Semantics(
                    button: true,
                    selected: m == mode,
                    label: tr(label),
                    child: InkWell(
                      key: ValueKey('profile-theme-${m.name}'),
                      borderRadius: BorderRadius.circular(99),
                      onTap: m == mode
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              onChanged(m);
                            },
                      child: Center(child: Icon(icon, size: 18, color: m == mode ? cs.primary : cs.onSurfaceVariant)),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/// Small tonal button used under the company row.
class _MiniAction extends StatelessWidget {
  const _MiniAction({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// พื้นที่ทำงานของฉัน → the company in use, its package as a capsule below.
class _CompanyPackageRow extends StatelessWidget {
  const _CompanyPackageRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = context.select((AppConfig c) => c.session);
    final code = (s.packageCode ?? '').trim();
    const tint = Color(0xFF0EA5E9);
    const pkgTint = Color(0xFF8B5CF6);
    return InkWell(
      key: const ValueKey('profile-ws-company'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: const Icon(NxI.buildings, size: 20, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('บริษัท'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(
                tr(s.businessName ?? 'ยังไม่ได้เลือกบริษัท'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Container(
                key: const ValueKey('profile-ws-package'),
                padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                decoration: BoxDecoration(
                  color: pkgTint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: pkgTint.withValues(alpha: 0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(kPackageHints[code]?.$2 ?? NxI.package, size: 13, color: pkgTint),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      tr(_packageLabel(code)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: pkgTint, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
          Icon(NxI.caretRight, size: 18, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// "NEXT X · ทุกเมนูของ NEXTX" from the session's package code.
String _packageLabel(String? code) {
  final c = (code ?? '').trim();
  if (c.isEmpty) return 'ยังไม่ได้เลือกแพ็กเกจ';
  final name = c.toUpperCase().replaceAll('_', ' ');
  final hint = kPackageHints[c]?.$1;
  return hint == null ? name : '$name · $hint';
}

/// Centered profile card: photo ringed in the Space colour (tap to change),
/// name, email, role · business, and "จัดการโปรไฟล์" / "สลับ Space".
class _Hero extends StatelessWidget {
  const _Hero({required this.onPhoto});
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final s = config.session;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ring = config.activeSpace?.color ?? cs.primary;
    final name = s.displayName ?? s.email ?? 'ผู้ใช้';
    final role = (s.businessRole ?? (s.isBusinessAdmin ? 'admin' : 'member')).toUpperCase();
    final image = config.profileAvatarImage;
    Widget chip(String label, Color color, {IconData? icon}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
    return Container(
      key: const ValueKey('profile-hero'),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(ring.withValues(alpha: 0.18), cs.surfaceContainerHighest), cs.surfaceContainerHighest],
        ),
      ),
      child: Column(children: [
        GestureDetector(
          key: const ValueKey('profile-photo'),
          onTap: () {
            HapticFeedback.selectionClick();
            onPhoto();
          },
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [ring, cs.primary, Color.lerp(ring, Colors.white, 0.4)!, ring]),
              ),
              child: CircleAvatar(
                radius: 46,
                backgroundColor: cs.surface,
                backgroundImage: image,
                onBackgroundImageError: image == null ? null : (_, _) {},
                child: image == null
                    ? Text(name.characters.take(2).toString().toUpperCase(),
                        style: theme.textTheme.headlineSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800))
                    : null,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 2)),
                child: Icon(NxI.camera, size: 14, color: cs.onPrimary),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if ((s.email ?? '').isNotEmpty && s.email != name)
          Text(s.email!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
          chip(role, ring, icon: NxI.userCheck),
          if ((s.businessName ?? '').isNotEmpty) chip(s.businessName!, cs.onSurfaceVariant, icon: NxI.buildings),
        ]),
        const SizedBox(height: 16),
        // Two equal pills, one line each (the label never wraps to a taller button).
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('profile-manage'),
              style: FilledButton.styleFrom(fixedSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => nxPush<void>(context, const ProfileManageScreen()),
              icon: const Icon(NxI.userCog, size: 18),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('จัดการโปรไฟล์'), maxLines: 1)),
            ),
          ),
          const SizedBox(width: 10),
          // Theme right here: ระบบ / สว่าง / มืด.
          Expanded(child: _ThemeToggle(mode: context.select((AppConfig c) => c.themeMode), onChanged: context.read<AppConfig>().setThemeMode)),
        ]),
      ]),
    );
  }
}
