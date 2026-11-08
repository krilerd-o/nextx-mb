import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../core/server_profile.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../profile_edit_screen.dart';
import '../settings_screen.dart';
import '../spaces/add_space_sheet.dart';
import '../spaces/space_switcher.dart';
import 'change_password_screen.dart';
import 'delete_account_screen.dart';
import 'my_signatures_screen.dart';
import 'phone_verify_screen.dart';

/// "โปรไฟล์" (avatar tap): who I am, my Spaces, account & security, and a way
/// into "การตั้งค่า" (theme, language, menus, notifications…), which is its
/// own page now.
class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await context.read<AppConfig>().apiClient.getMyProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {}
  }

  String? _p(String k) {
    final v = _profile?[k]?.toString().trim() ?? '';
    return v.isEmpty || v == 'null' ? null : v;
  }

  Future<void> _photo(AppConfig config) async {
    final has = (config.profileAvatarBase64 ?? '').isNotEmpty;
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
    final sp = config.activeSpace;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ออกจากระบบ?')),
        content: Text(tr('ออกจาก ${sp?.title ?? serverLabel(config.apiBaseUrl)} บนเครื่องนี้')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ออก'))),
        ],
      ),
    );
    if (ok == true) await config.logout();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final s = config.session;
    final pad = NxBreakpoint.of(context).scrollPadding(context);
    final active = config.activeSpace;
    final spaces = [...config.spaces]..sort((a, b) => a.id == active?.id ? -1 : (b.id == active?.id ? 1 : 0));
    var i = 0;

    return NxScrollScaffold(
      insetBody: false,
      header: NxAppHeader(
        title: 'โปรไฟล์',
        actions: [
          IconButton(
            key: const ValueKey('profile-open-settings'),
            tooltip: tr('การตั้งค่า'),
            icon: const Icon(NxI.gear),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Builder(
        builder: (context) => ListView(
          padding: pad.copyWith(top: pad.top + NxScrollScaffold.topInset(context)),
          children: [
            SettingsAppear(index: i++, child: _Hero(onPhoto: () => _photo(config))),

            // ── About me
            SettingsAppear(
              index: i++,
              child: SettingsGroup(title: 'ข้อมูลของฉัน', children: [
                SettingsTile(
                  icon: NxI.envelope,
                  tint: const Color(0xFF0EA5E9),
                  title: 'อีเมล',
                  subtitle: s.email ?? '—',
                ),
                SettingsTile(
                  icon: NxI.phone,
                  tint: const Color(0xFF10B981),
                  title: 'เบอร์มือถือ',
                  subtitle: _p('phone_mobile') ?? tr('ยังไม่ได้ยืนยัน · แตะเพื่อเพิ่ม'),
                  onTap: () => nxPush<void>(context, PhoneVerifyScreen(initialPhone: _p('phone_mobile'))).then((_) => _loadProfile()),
                ),
                if (_p('title') != null || _p('department') != null)
                  SettingsTile(
                    icon: NxI.briefcase,
                    tint: const Color(0xFF8B5CF6),
                    title: 'ตำแหน่ง / แผนก',
                    subtitle: [?_p('title'), ?_p('department')].join(' · '),
                  ),
              ]),
            ),

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

            // ── Account & security
            SettingsAppear(
              index: i++,
              child: SettingsGroup(title: 'บัญชีและความปลอดภัย', children: [
                SettingsTile(
                  icon: NxI.password,
                  tint: const Color(0xFF475569),
                  title: 'เปลี่ยนรหัสผ่าน',
                  subtitle: 'ยืนยันด้วย OTP ทางอีเมลหรือ SMS',
                  onTap: () => nxPush<bool>(context, const ChangePasswordScreen()),
                ),
                SettingsTile(
                  icon: NxI.penLine,
                  tint: const Color(0xFF8B5CF6),
                  title: 'ลายเซ็นของฉัน',
                  subtitle: 'ใช้บนใบเสนอราคาและเอกสาร (TH / EN)',
                  onTap: () => nxPush<void>(context, const MySignaturesScreen()),
                ),
                SettingsTile(
                  icon: NxI.monitorSmartphone,
                  tint: const Color(0xFF64748B),
                  title: 'อุปกรณ์ที่เข้าใช้งาน',
                  subtitle: 'ดูและออกจากระบบเครื่องอื่น',
                  onTap: () => context.push(AppRoutes.devices),
                ),
                SettingsTile(
                  key: const ValueKey('profile-delete-account'),
                  icon: NxI.trash,
                  tint: const Color(0xFFDC2626),
                  title: 'ลบบัญชี',
                  subtitle: 'ปิดบัญชีถาวร ยืนยันด้วย OTP',
                  onTap: () => nxPush<void>(context, const DeleteAccountScreen()),
                ),
              ]),
            ),

            // ── Settings (its own page)
            const SizedBox(height: 18),
            SettingsAppear(
              index: i++,
              child: Material(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  key: const ValueKey('profile-settings-row'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => context.push(AppRoutes.settings),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                        child: Icon(NxI.gear, color: cs.onPrimary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('การตั้งค่า'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            tr('ธีม สี ภาษา เมนู การแจ้งเตือน และอื่นๆ'),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ]),
                      ),
                      Icon(NxI.caretRight, color: cs.onSurfaceVariant),
                    ]),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),
            SettingsAppear(
              index: i++,
              child: Material(
                color: cs.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _logout(config),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(NxI.signOut, size: 20, color: cs.error),
                      const SizedBox(width: 10),
                      Text(tr('ออกจากระบบ Space นี้'), style: theme.textTheme.titleSmall?.copyWith(color: cs.error)),
                    ]),
                  ),
                ),
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
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 24),
              child: Text(
                'MOAI NEXT Mobile ${SettingsScreen.appVersion}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered profile card: photo ringed in the Space colour (tap to change),
/// name, email, role · business, and the two main actions.
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
    ImageProvider? image;
    final b64 = config.profileAvatarBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(b64.contains(',') ? b64.split(',').last : b64));
      } catch (_) {}
    }
    Widget chip(String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
        );
    return Container(
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
          Text(s.email!, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
          chip(role, ring),
          if ((s.businessName ?? '').isNotEmpty) chip(s.businessName!, cs.onSurfaceVariant),
        ]),
        const SizedBox(height: 16),
        // Two equal pills, one line each (the label never wraps to a taller button).
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              key: const ValueKey('profile-edit'),
              style: FilledButton.styleFrom(fixedSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => nxPush<bool>(context, const ProfileEditScreen()),
              icon: const Icon(NxI.pencilSimple, size: 18),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('แก้ไขโปรไฟล์'), maxLines: 1)),
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
