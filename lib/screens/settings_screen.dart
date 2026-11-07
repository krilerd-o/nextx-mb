import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/app_version.dart';
import '../core/effects.dart';
import '../core/i18n.dart';
import '../core/menu_access.dart';
import '../core/navigation/app_routes.dart';
import '../core/nx_breakpoint.dart';
import '../core/nx_page_route.dart';
import '../core/server_profile.dart';
import '../core/shell_tabs.dart';
import '../services/app_lock.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_icons.dart';
import '../widgets/nx_scroll_scaffold.dart';
import 'onboarding/tab_setup_screen.dart' show TabBarPreview;
import 'profile/my_signatures_screen.dart';
import 'profile/phone_verify_screen.dart';
import 'profile_edit_screen.dart';
import 'profile_screen.dart' show showChangePasswordDialog;
import 'spaces/space_switcher.dart' show showSpaceSwitcher, SpaceAvatar;
import 'update_required_screen.dart';

/// Profile hub — opened from the avatar (and Menu → ตั้งค่า). Everything the
/// user can set, in groups: profile, Space & business, appearance (theme,
/// colour, language), menu bar, notifications, security, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Installed app version (package_info_plus; `--dart-define=APP_VERSION=` overrides).
  static String get appVersion => AppVersion.value;

  /// Release builds lock the API endpoint; QA builds can re-enable with
  /// `--dart-define=ALLOW_API_URL_EDIT=true`.
  static const bool _allowApiUrlEditInRelease = bool.fromEnvironment('ALLOW_API_URL_EDIT');
  static bool get canEditApiUrl => !kReleaseMode || _allowApiUrlEditInRelease;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// One searchable setting: which group it sits in, the words it matches, and its row.
class _Entry {
  const _Entry(this.group, this.words, this.child);
  final String group;
  final List<String> words;
  final Widget child;
}

const _groupOrder = [
  'Space และธุรกิจ',
  'รูปลักษณ์',
  'เมนูและการใช้งาน',
  'การแจ้งเตือน',
  'บัญชีและความปลอดภัย',
  'เกี่ยวกับ',
];

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(_Entry e) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return [e.group, ...e.words].any((w) => w.toLowerCase().contains(q) || tr(w).toLowerCase().contains(q));
  }

  List<_Entry> _entries(BuildContext context, AppConfig config) {
    final cs = Theme.of(context).colorScheme;
    final session = config.session;
    final sp = config.activeSpace;
    final dark = config.themeMode == ThemeMode.dark ||
        (config.themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final tabs = resolveShellTabs(
      roles: config.shellConfig?.roles ?? const ['general'],
      custom: config.shellConfig?.tabs,
      allowed: (keys) => MenuAccess.any(session, keys),
    );

    return [
      // ── Space & business
      _Entry('Space และธุรกิจ', ['Space', 'สลับ', 'เพิ่ม'], _Tile(
        icon: NxI.arrowsClockwise,
        tint: const Color(0xFF6366F1),
        title: config.spaces.length > 1 ? 'สลับ Space (${config.spaces.length})' : 'สลับ / เพิ่ม Space',
        subtitle: sp?.title ?? serverLabel(config.apiBaseUrl),
        trailing: sp == null ? null : SpaceAvatar(space: sp, size: 30),
        onTap: () => showSpaceSwitcher(context),
      )),
      _Entry('Space และธุรกิจ', ['ธุรกิจ', 'บริษัท'], _Tile(
        icon: NxI.briefcase,
        tint: const Color(0xFF0EA5E9),
        title: 'สลับธุรกิจ',
        subtitle: session.businessName ?? '—',
        onTap: () => config.clearBusiness(),
      )),
      _Entry('Space และธุรกิจ', ['Package', 'แพ็กเกจ'], _Tile(
        icon: NxI.package,
        tint: const Color(0xFF10B981),
        title: 'สลับ Package',
        subtitle: (session.packageCode ?? '').isEmpty ? '—' : session.packageCode,
        onTap: () => config.clearPackage(),
      )),
      _Entry('Space และธุรกิจ', ['อุปกรณ์', 'เครื่อง', 'ออกจากระบบ'], _Tile(
        icon: NxI.monitorSmartphone,
        tint: const Color(0xFF64748B),
        title: 'อุปกรณ์ที่เข้าใช้งาน',
        subtitle: 'ดูและออกจากระบบเครื่องอื่น',
        onTap: () => context.push(AppRoutes.devices),
      )),

      // ── Appearance
      _Entry('รูปลักษณ์', ['ธีม', 'โหมดมืด', 'สว่าง', 'มืด', 'dark', 'light'], _Tile(
        icon: dark ? NxI.moon : NxI.sun,
        tint: const Color(0xFF8B5CF6),
        title: 'ธีม',
        below: _Segmented<ThemeMode>(
          value: config.themeMode,
          options: const [
            (ThemeMode.light, 'สว่าง', NxI.sun),
            (ThemeMode.dark, 'มืด', NxI.moon),
            (ThemeMode.system, 'ตามเครื่อง', NxI.deviceMobile),
          ],
          onChanged: config.setThemeMode,
        ),
      )),
      _Entry('รูปลักษณ์', ['สีธีม', 'สีหลัก', 'สี', 'accent', 'color'], _Tile(
        icon: NxI.palette,
        tint: config.accentColor,
        title: 'สีธีม',
        subtitle: AppConfig.accentNames[config.accentIndex.clamp(0, AppConfig.accentNames.length - 1)],
        below: _AccentPalette(
          selected: config.accentIndex,
          onSelect: (i) {
            HapticFeedback.selectionClick();
            config.setAccentIndex(i);
          },
        ),
      )),
      _Entry('รูปลักษณ์', ['ภาษา', 'language', 'English', 'ไทย'], _Tile(
        icon: NxI.languages,
        tint: const Color(0xFFF97316),
        title: 'ภาษา',
        subtitle: 'มีผลทั้งแอปทันที',
        below: _Segmented<String>(
          value: config.uiLocaleCode,
          options: const [('th', 'ไทย', null), ('en', 'English', null)],
          translate: false,
          onChanged: config.setUiLocaleCode,
        ),
      )),
      _Entry('รูปลักษณ์', ['วันที่', 'เวลา', 'รูปแบบ', 'date'], _Tile(
        icon: NxI.calendarClock,
        tint: const Color(0xFF14B8A6),
        title: 'รูปแบบวันที่/เวลา',
        subtitle: '${config.dateFormatPattern} · เวลาประเทศไทย',
        onTap: () => _pickDateFormat(context, config),
      )),
      _Entry('รูปลักษณ์', ['เอฟเฟกต์', 'เบลอ', 'ลื่น', 'animation'], ValueListenableBuilder<EffectsPreference>(
        valueListenable: Effects.preference,
        builder: (context, pref, _) => _Tile(
          icon: NxI.sparkle,
          tint: const Color(0xFFEC4899),
          title: 'เอฟเฟกต์และความลื่น',
          subtitle: pref.label,
          onTap: () => _pickEffects(context, config, pref),
        ),
      )),

      // ── Menu bar
      _Entry('เมนูและการใช้งาน', ['เมนูล่าง', 'แถบเมนู', 'แท็บ', 'tab'], _Tile(
        icon: NxI.panelBottom,
        tint: const Color(0xFF6366F1),
        title: 'แถบเมนูล่าง',
        subtitle: 'เลือกและเรียงแท็บที่ต้องการ',
        onTap: () => context.push(AppRoutes.tabEditor),
        below: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(width: 360, child: TabBarPreview(tabs: tabs)),
            ),
          ),
        ),
      )),
      _Entry('เมนูและการใช้งาน', ['บทบาท', 'role'], _Tile(
        icon: NxI.users,
        tint: const Color(0xFF0EA5E9),
        title: 'บทบาทของฉัน',
        subtitle: roleSummary(config.shellConfig?.roles ?? const []),
        onTap: () => context.push(AppRoutes.roleEditor),
      )),

      // ── Notifications
      _Entry('การแจ้งเตือน', ['แจ้งเตือน', 'notification'], _Tile(
        icon: NxI.bell,
        tint: const Color(0xFFF43F5E),
        title: 'ศูนย์การแจ้งเตือน',
        onTap: () => context.push(AppRoutes.notifications),
      )),
      _Entry('การแจ้งเตือน', ['มีอะไรใหม่', 'ประกาศ', 'เวอร์ชัน'], _Tile(
        icon: NxI.megaphone,
        tint: const Color(0xFFF59E0B),
        title: 'มีอะไรใหม่',
        subtitle: 'ประกาศเวอร์ชันและฟีเจอร์ใหม่',
        onTap: () => context.push(AppRoutes.whatsNew),
      )),

      // ── Account & security
      _Entry('บัญชีและความปลอดภัย', ['ล็อก', 'ลายนิ้วมือ', 'ใบหน้า', 'biometric'], const _AppLockTile()),
      _Entry('บัญชีและความปลอดภัย', ['รหัสผ่าน', 'password'], _Tile(
        icon: NxI.password,
        tint: const Color(0xFF475569),
        title: 'เปลี่ยนรหัสผ่าน',
        onTap: () => showChangePasswordDialog(context),
      )),
      _Entry('บัญชีและความปลอดภัย', ['เบอร์', 'มือถือ', 'OTP'], _Tile(
        icon: NxI.phone,
        tint: const Color(0xFF10B981),
        title: 'ยืนยันเบอร์มือถือ',
        subtitle: 'ใช้เข้าสู่ระบบด้วย OTP SMS',
        onTap: () => nxPush<void>(context, const PhoneVerifyScreen()),
      )),
      _Entry('บัญชีและความปลอดภัย', ['ลายเซ็น', 'signature'], _Tile(
        icon: NxI.penLine,
        tint: const Color(0xFF8B5CF6),
        title: 'ลายเซ็นของฉัน',
        subtitle: 'ใช้บนใบเสนอราคาและเอกสาร (TH / EN)',
        onTap: () => nxPush<void>(context, const MySignaturesScreen()),
      )),
      _Entry('บัญชีและความปลอดภัย', ['ขั้นสูง', 'โทเคน', '2FA', 'push'], _Tile(
        icon: NxI.shieldCheck,
        tint: const Color(0xFF64748B),
        title: 'ความปลอดภัยขั้นสูง',
        subtitle: 'โทเคนพุช, 2FA',
        onTap: () => context.push(AppRoutes.profile),
      )),

      // ── About
      _Entry('เกี่ยวกับ', ['เวอร์ชัน', 'version'], _Tile(
        icon: NxI.info,
        tint: cs.primary,
        title: 'MOAI NEXT Mobile',
        subtitle: 'เวอร์ชัน ${SettingsScreen.appVersion}',
      )),
      if (config.updateNeed == UpdateNeed.optional)
        _Entry('เกี่ยวกับ', ['อัปเดต', 'update'], _Tile(
          icon: NxI.arrowSquareOut,
          tint: const Color(0xFF10B981),
          title: 'มีแอปเวอร์ชันใหม่ ${config.serverInfo?.latestVersion ?? ''}',
          subtitle: 'เวอร์ชันในเครื่อง ${AppVersion.value}',
          onTap: storeUrlFor(config.serverInfo) == null ? null : () => openStore(config.serverInfo),
        )),
      _Entry('เกี่ยวกับ', ['บันทึกปัญหา', 'ปัญหา', 'log', 'diagnostics'], _Tile(
        icon: NxI.bug,
        tint: const Color(0xFFF97316),
        title: 'บันทึกปัญหา',
        subtitle: 'ส่งข้อมูลให้ทีมพัฒนาเมื่อพบปัญหา',
        onTap: () => context.push(AppRoutes.diagnostics),
      )),
    ];
  }

  Future<void> _pickDateFormat(BuildContext context, AppConfig config) {
    const options = ['dd/MM/yyyy HH:mm', 'yyyy-MM-dd HH:mm', 'MM/dd/yyyy h:mm a'];
    return showAppBottomSheet<void>(
      context: context,
      title: 'รูปแบบวันที่/เวลา',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            ListTile(
              title: Text(o),
              trailing: o == config.dateFormatPattern ? Icon(NxI.check, color: Theme.of(context).colorScheme.primary) : null,
              onTap: () {
                config.setDateFormatPattern(o);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickEffects(BuildContext context, AppConfig config, EffectsPreference pref) {
    return showAppBottomSheet<void>(
      context: context,
      title: 'เอฟเฟกต์และความลื่น',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in EffectsPreference.values)
            ListTile(
              title: Text(tr(p.label)),
              trailing: p == pref ? Icon(NxI.check, color: Theme.of(context).colorScheme.primary) : null,
              onTap: () async {
                await Effects.setPreference(p);
                if (context.mounted) Navigator.pop(context);
                config.refreshUi();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, AppConfig config) async {
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
    final pad = NxBreakpoint.of(context).scrollPadding(context);
    final visible = _entries(context, config).where(_matches).toList();
    final groups = <String, List<Widget>>{};
    for (final g in _groupOrder) {
      final rows = [for (final e in visible) if (e.group == g) e.child];
      if (rows.isNotEmpty) groups[g] = rows;
    }

    var stagger = 0;
    return NxScrollScaffold(
      insetBody: false,
      header: const NxAppHeader(title: 'โปรไฟล์และการตั้งค่า'),
      body: Builder(
        builder: (context) => ListView(
          padding: pad.copyWith(top: pad.top + NxScrollScaffold.topInset(context)),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _Appear(index: stagger++, child: const _HubHero()),
            const SizedBox(height: 14),
            _Appear(
              index: stagger++,
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: InputDecoration(
                  hintText: tr('ค้นหาการตั้งค่า'),
                  prefixIcon: const Icon(NxI.magnifyingGlass, size: 20),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(NxI.x, size: 18),
                          onPressed: () => setState(() {
                            _search.clear();
                            _q = '';
                          }),
                        ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                children: [
                  for (final g in groups.entries)
                    _Appear(
                      key: ValueKey(g.key),
                      index: stagger++,
                      child: _Group(title: g.key, children: g.value),
                    ),
                  if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        tr('ไม่พบการตั้งค่าที่ตรงกับ "$_q"'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            if (_q.isEmpty) ...[
              const SizedBox(height: 20),
              _Appear(
                index: stagger++,
                child: Material(
                  color: cs.errorContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _logout(context, config),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(NxI.signOut, size: 20, color: cs.error),
                          const SizedBox(width: 10),
                          Text(
                            tr('ออกจากระบบ Space นี้'),
                            style: theme.textTheme.titleSmall?.copyWith(color: cs.error),
                          ),
                        ],
                      ),
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
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Fades + slides a hub section in, one after another, the first time it shows.
class _Appear extends StatelessWidget {
  const _Appear({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Effects.animate(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + 45 * index.clamp(0, 8)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        // Each section starts a little later than the previous one.
        final start = (index.clamp(0, 8) * 0.08).clamp(0.0, 0.6);
        final v = ((t - start) / (1 - start)).clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
        );
      },
      child: child,
    );
  }
}

/// Big profile card: photo (or initials) ringed in the Space colour, name,
/// email, role · business, and quick actions.
class _HubHero extends StatelessWidget {
  const _HubHero();

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

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(cs.primary.withValues(alpha: 0.16), cs.surfaceContainerHighest),
            cs.surfaceContainerHighest,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push(AppRoutes.profile),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [ring, cs.primary, Color.lerp(ring, Colors.white, 0.4)!, ring]),
                  ),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: cs.surface,
                    backgroundImage: image,
                    child: image == null
                        ? Text(
                            name.characters.take(2).toString().toUpperCase(),
                            style: theme.textTheme.titleLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if ((s.email ?? '').isNotEmpty && s.email != name)
                      Text(
                        s.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(label: role, color: ring),
                        if ((s.businessName ?? '').isNotEmpty) _Chip(label: s.businessName!, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroAction(
                  icon: NxI.pencilSimple,
                  label: 'แก้ไขโปรไฟล์',
                  onTap: () => nxPush<bool>(context, const ProfileEditScreen()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroAction(
                  icon: NxI.user,
                  label: 'รูปโปรไฟล์',
                  onTap: () => context.push(AppRoutes.profile),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroAction(
                  icon: NxI.arrowsClockwise,
                  label: 'สลับ Space',
                  onTap: () => showSpaceSwitcher(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, letterSpacing: 0.4),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(height: 4),
              Text(
                tr(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey section label + rounded card holding the rows, hairline-separated.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
          child: Text(
            tr(title).toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 60, color: cs.outlineVariant.withValues(alpha: 0.6)),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Settings row: tinted icon tile, title/subtitle, trailing or chevron, and an
/// optional control underneath (segmented picker, colour palette, preview).
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.below,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 19, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(title), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          tr(subtitle!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
            if (below != null) ...[const SizedBox(height: 12), below!],
          ],
        ),
      ),
    );
  }
}

/// Pill segmented control with a sliding thumb.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged, this.translate = true});
  final T value;
  /// Off for language names, which always show in their own language.
  final bool translate;
  final List<(T, String, IconData?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final index = options.indexWhere((o) => o.$1 == value).clamp(0, options.length - 1);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < options.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == index) return;
                          HapticFeedback.selectionClick();
                          onChanged(options[i].$1);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                              color: i == index ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (options[i].$3 != null) ...[
                                  Icon(options[i].$3, size: 16, color: i == index ? cs.onPrimary : cs.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(child: Text(translate ? tr(options[i].$2) : options[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Theme colour swatches; the chosen one grows and shows a check.
class _AccentPalette extends StatelessWidget {
  const _AccentPalette({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < AppConfig.accentOptions.length; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: tr(AppConfig.accentNames[i]),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                // Not easeOutBack: an overshoot would make the padding negative.
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                padding: EdgeInsets.all(i == selected ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: i == selected ? AppConfig.accentOptions[i] : Colors.transparent, width: 2),
                ),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  scale: i == selected ? 1 : 0.86,
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: AppConfig.accentOptions[i]),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: i == selected
                          ? Icon(NxI.check, key: const ValueKey(true), size: 16, color: cs.surface)
                          : const SizedBox.shrink(key: ValueKey(false)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า" — hidden on devices without it.
class _AppLockTile extends StatefulWidget {
  const _AppLockTile();

  @override
  State<_AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<_AppLockTile> {
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
    final lock = AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => _Tile(
        icon: NxI.fingerprint,
        tint: const Color(0xFF0EA5E9),
        title: 'ล็อกแอปด้วยลายนิ้วมือ / ใบหน้า',
        subtitle: _supported ? 'ขอสแกนเมื่อเปิดแอป หรือกลับมาหลังพักเกิน 5 นาที' : 'เครื่องนี้ไม่รองรับ',
        trailing: Switch(
          value: lock.enabled,
          onChanged: _busy || !_supported
              ? null
              : (v) async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await lock.setEnabled(v);
                  if (!ok) messenger.showSnackBar(SnackBar(content: Text(tr('ยืนยันตัวตนไม่สำเร็จ'))));
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ),
    );
  }
}
