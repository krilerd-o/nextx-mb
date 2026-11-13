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
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/settings_tiles.dart';
import '../profile_edit_screen.dart';
import '../spaces/add_space_sheet.dart';
import '../spaces/space_switcher.dart';
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
/// "แก้ไขโปรไฟล์" sits at the very bottom.
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
    final active = config.activeSpace;
    final spaces = [...config.spaces]..sort((a, b) => a.id == active?.id ? -1 : (b.id == active?.id ? 1 : 0));
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
        IconButton(
          key: const ValueKey('profile-open-settings'),
          tooltip: tr('การตั้งค่า'),
          icon: const Icon(NxI.gear),
          onPressed: () => context.push(AppRoutes.settings),
        ),
      ],
      children: [
        SettingsAppear(index: i++, child: _Hero(onPhoto: () => _photo(config))),

        // ── Spaces
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'Space ของฉัน', children: [
            for (final sp in spaces)
              Builder(
                builder: (c) => InkWell(
                  key: ValueKey('profile-space-${sp.id}'),
                  onTap: sp.id == active?.id
                      ? null
                      : () {
                          final box = c.findRenderObject() as RenderBox?;
                          runSpaceTransition(context, sp, box == null ? null : box.localToGlobal(Offset.zero) & box.size, () => config.switchSpace(sp.id));
                        },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(children: [
                      SpaceAvatar(space: sp, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr(sp.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            [sp.host, ?sp.email].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ]),
                      ),
                      if (sp.id == active?.id)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                          child: Text(tr('ใช้อยู่'), style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                        ),
                    ]),
                  ),
                ),
              ),
            SettingsTile(
              icon: NxI.plus,
              tint: cs.primary,
              title: 'เพิ่ม Space',
              subtitle: 'บัญชีอื่นหรือโดเมนอื่น',
              onTap: () => showAddSpaceSheet(context),
            ),
          ]),
        ),

        // ── One row per area, each its own page.
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'บัญชีและการตั้งค่า', children: [
            for (final id in kProfileMenuOrder) KeyedSubtree(key: ValueKey('profile-menu-$id'), child: menu[id]!),
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
              tr('Space อื่นยังใช้งานได้ตามเดิม'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),

        // ── Very bottom: edit my profile.
        const SizedBox(height: 14),
        SettingsAppear(
          index: i++,
          child: FilledButton.tonalIcon(
            key: const ValueKey('profile-edit'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            onPressed: () => nxPush<bool>(context, const ProfileEditScreen()),
            icon: const Icon(NxI.userPen, size: 20),
            label: Text(tr('แก้ไขโปรไฟล์'), style: const TextStyle(fontWeight: FontWeight.w700)),
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
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('profile-switch'),
              style: OutlinedButton.styleFrom(fixedSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => showSpaceSwitcher(context),
              icon: const Icon(NxI.arrowsClockwise, size: 18),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('สลับ Space'), maxLines: 1)),
            ),
          ),
        ]),
      ]),
    );
  }
}
