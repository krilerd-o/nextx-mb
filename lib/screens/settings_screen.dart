
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
import '../core/ui_font.dart';
import '../services/app_lock.dart';
import '../services/shutter_sound.dart';
import '../widgets/shutter_sound_picker.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/nx_app_header.dart';
import '../widgets/nx_appearance_controls.dart';
import '../widgets/nx_icons.dart';
import '../widgets/nx_scroll_scaffold.dart';
import 'onboarding/tab_setup_screen.dart' show TabBarPreview;
import 'profile/delete_account_screen.dart';
import 'profile/my_signatures_screen.dart';
import 'profile/phone_verify_screen.dart';
import 'profile_screen.dart' show showChangePasswordDialog;
import 'spaces/space_switcher.dart' show showSpaceSwitcher, SpaceAvatar;
import 'update_required_screen.dart';
import 'dashboard/home_layout_editor.dart';
import '../services/birthday_reminders.dart';
import 'calendar/cal/cal_birthdays.dart';

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
  void initState() {
    super.initState();
    ShutterSound.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

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
    final tabs = resolveShellTabs(
      roles: config.shellConfig?.roles ?? const ['general'],
      custom: config.shellConfig?.tabs,
      allowed: (keys) => MenuAccess.any(session, keys),
    );

    return [
      // ── Space & business
      _Entry('Space และธุรกิจ', ['Space', 'สลับ', 'เพิ่ม'], SettingsTile(
        icon: NxI.arrowsClockwise,
        tint: const Color(0xFF6366F1),
        title: config.spaces.length > 1 ? 'สลับ Space (${config.spaces.length})' : 'สลับ / เพิ่ม Space',
        subtitle: sp?.title ?? serverLabel(config.apiBaseUrl),
        trailing: sp == null ? null : SpaceAvatar(space: sp, size: 30),
        onTap: () => showSpaceSwitcher(context),
      )),
      // Business / package switching lives in the header switcher (not repeated here).
      _Entry('Space และธุรกิจ', ['อุปกรณ์', 'เครื่อง', 'ออกจากระบบ'], SettingsTile(
        icon: NxI.monitorSmartphone,
        tint: const Color(0xFF64748B),
        title: 'อุปกรณ์ที่เข้าใช้งาน',
        subtitle: 'ดูและออกจากระบบเครื่องอื่น',
        onTap: () => context.push(AppRoutes.devices),
      )),

      // ── Appearance
      _Entry('รูปลักษณ์', ['สีธีม', 'สีหลัก', 'สี', 'accent', 'color'], SettingsTile(
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
      _Entry('รูปลักษณ์', ['ฟอนต์', 'แบบอักษร', 'font', 'ตัวอักษร'], SettingsTile(
        key: const ValueKey('settings-font'),
        icon: NxI.textT,
        tint: const Color(0xFF0EA5E9),
        title: 'ฟอนต์',
        subtitle: uiFontById(config.uiFontId).label,
        onTap: () => showUiFontPicker(context),
      )),
      _Entry('รูปลักษณ์', ['ขนาด', 'สเกล', 'scale', 'ตัวอักษร', 'ซูม'], SettingsTile(
        key: const ValueKey('settings-ui-scale'),
        icon: NxI.monitorSmartphone,
        tint: const Color(0xFF22C55E),
        title: 'ขนาดหน้าจอ',
        subtitle: 'ตัวอักษร ปุ่ม และไอคอนทั้งแอป',
        below: const NxUiScaleControl(),
      )),
      _Entry('รูปลักษณ์', ['เมนู', 'แท็บเล็ต', 'ตำแหน่ง', 'tablet', 'rail', 'dock'], SettingsTile(
        key: const ValueKey('settings-nav-dock'),
        icon: NxI.squaresFour,
        tint: const Color(0xFF8B5CF6),
        title: 'ตำแหน่งเมนู (แท็บเล็ต)',
        subtitle: config.navDock.label,
        onTap: () => showNavDockPicker(context),
      )),
      _Entry('รูปลักษณ์', ['เสียง', 'ชัตเตอร์', 'กล้อง', 'shutter', 'camera', 'ถ่ายรูป'], SettingsTile(
        key: const ValueKey('settings-shutter'),
        icon: NxI.camera,
        tint: const Color(0xFFF97316),
        title: 'เสียงชัตเตอร์',
        subtitle: ShutterSound.instance.style.labelTh,
        onTap: () async {
          await showShutterSoundPicker(context);
          if (mounted) setState(() {});
        },
      )),
      _Entry('รูปลักษณ์', ['วันที่', 'เวลา', 'รูปแบบ', 'date'], SettingsTile(
        icon: NxI.calendarClock,
        tint: const Color(0xFF14B8A6),
        title: 'รูปแบบวันที่/เวลา',
        subtitle: '${config.dateFormatPattern} · เวลาประเทศไทย',
        onTap: () => _pickDateFormat(context, config),
      )),
      _Entry('รูปลักษณ์', ['เอฟเฟกต์', 'เบลอ', 'ลื่น', 'animation'], ValueListenableBuilder<EffectsPreference>(
        valueListenable: Effects.preference,
        builder: (context, pref, _) => SettingsTile(
          icon: NxI.sparkle,
          tint: const Color(0xFFEC4899),
          title: 'เอฟเฟกต์และความลื่น',
          subtitle: pref.label,
          onTap: () => _pickEffects(context, config, pref),
        ),
      )),

      // ── Menu bar
      _Entry('เมนูและการใช้งาน', ['เมนูล่าง', 'แถบเมนู', 'แท็บ', 'tab'], SettingsTile(
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
      _Entry('เมนูและการใช้งาน', ['หน้าหลัก', 'วิดเจ็ท', 'home', 'widget'], SettingsTile(
        icon: NxI.squaresFour,
        tint: const Color(0xFF10B981),
        title: 'ปรับแต่งหน้าหลัก',
        subtitle: 'เรียงและซ่อน/แสดงกล่องบนหน้าหลัก',
        onTap: () => nxPush<bool>(context, const HomeLayoutEditorScreen(), root: true),
      )),
      _Entry('เมนูและการใช้งาน', ['บทบาท', 'role'], SettingsTile(
        icon: NxI.users,
        tint: const Color(0xFF0EA5E9),
        title: 'บทบาทของฉัน',
        subtitle: roleSummary(config.shellConfig?.roles ?? const []),
        onTap: () => context.push(AppRoutes.roleEditor),
      )),

      // ── Notifications
      _Entry('การแจ้งเตือน', ['แจ้งเตือน', 'notification'], SettingsTile(
        icon: NxI.bell,
        tint: const Color(0xFFF43F5E),
        title: 'ศูนย์การแจ้งเตือน',
        onTap: () => context.push(AppRoutes.notifications),
      )),
      _Entry('การแจ้งเตือน', ['วันเกิด', 'birthday', 'ลูกค้า'], const _BirthdayReminderTile()),
      _Entry('การแจ้งเตือน', ['มีอะไรใหม่', 'ประกาศ', 'เวอร์ชัน'], SettingsTile(
        icon: NxI.megaphone,
        tint: const Color(0xFFF59E0B),
        title: 'มีอะไรใหม่',
        subtitle: 'ประกาศเวอร์ชันและฟีเจอร์ใหม่',
        onTap: () => context.push(AppRoutes.whatsNew),
      )),

      // ── Account & security
      _Entry('บัญชีและความปลอดภัย', ['ล็อก', 'ลายนิ้วมือ', 'ใบหน้า', 'biometric'], const _AppLockTile()),
      _Entry('บัญชีและความปลอดภัย', ['รหัสผ่าน', 'password'], SettingsTile(
        icon: NxI.password,
        tint: const Color(0xFF475569),
        title: 'เปลี่ยนรหัสผ่าน',
        onTap: () => showChangePasswordDialog(context),
      )),
      _Entry('บัญชีและความปลอดภัย', ['เบอร์', 'มือถือ', 'OTP'], SettingsTile(
        icon: NxI.phone,
        tint: const Color(0xFF10B981),
        title: 'ยืนยันเบอร์มือถือ',
        subtitle: 'ใช้เข้าสู่ระบบด้วย OTP SMS',
        onTap: () => nxPush<void>(context, const PhoneVerifyScreen()),
      )),
      _Entry('บัญชีและความปลอดภัย', ['ลายเซ็น', 'signature'], SettingsTile(
        icon: NxI.penLine,
        tint: const Color(0xFF8B5CF6),
        title: 'ลายเซ็นของฉัน',
        subtitle: 'ใช้บนใบเสนอราคาและเอกสาร (TH / EN)',
        onTap: () => nxPush<void>(context, const MySignaturesScreen()),
      )),
      _Entry('บัญชีและความปลอดภัย', ['ขั้นสูง', 'โทเคน', '2FA', 'push'], SettingsTile(
        icon: NxI.shieldCheck,
        tint: const Color(0xFF64748B),
        title: 'ความปลอดภัยขั้นสูง',
        subtitle: 'โทเคนพุช, 2FA',
        onTap: () => context.push(AppRoutes.profileSecurity),
      )),
      _Entry('บัญชีและความปลอดภัย', ['ลบบัญชี', 'ปิดบัญชี', 'delete'], SettingsTile(
        key: const ValueKey('settings-delete-account'),
        icon: NxI.trash,
        tint: const Color(0xFFDC2626),
        title: 'ลบบัญชี',
        subtitle: 'ปิดบัญชีถาวร ยืนยันด้วย OTP',
        onTap: () => nxPush<void>(context, const DeleteAccountScreen()),
      )),

      // ── About
      _Entry('เกี่ยวกับ', ['เวอร์ชัน', 'version'], SettingsTile(
        icon: NxI.info,
        tint: cs.primary,
        title: 'MOAI NEXT Mobile',
        subtitle: 'เวอร์ชัน ${SettingsScreen.appVersion}',
      )),
      if (config.updateNeed == UpdateNeed.optional)
        _Entry('เกี่ยวกับ', ['อัปเดต', 'update'], SettingsTile(
          icon: NxI.arrowSquareOut,
          tint: const Color(0xFF10B981),
          title: 'มีแอปเวอร์ชันใหม่ ${config.serverInfo?.latestVersion ?? ''}',
          subtitle: 'เวอร์ชันในเครื่อง ${AppVersion.value}',
          onTap: storeUrlFor(config.serverInfo) == null ? null : () => openStore(config.serverInfo),
        )),
      _Entry('เกี่ยวกับ', ['บันทึกปัญหา', 'ปัญหา', 'log', 'diagnostics'], SettingsTile(
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
      header: const NxAppHeader(title: 'การตั้งค่า'),
      body: Builder(
        builder: (context) => ListView(
          padding: pad.copyWith(top: pad.top + NxScrollScaffold.topInset(context)),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            SettingsAppear(
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
                    SettingsAppear(
                      key: ValueKey(g.key),
                      index: stagger++,
                      child: SettingsGroup(title: g.key, children: g.value),
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Fades + slides a hub section in, one after another, the first time it shows.
class SettingsAppear extends StatelessWidget {
  const SettingsAppear({super.key, required this.index, required this.child});
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

/// Grey section label + rounded card holding the rows, hairline-separated.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.title, required this.children});
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
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
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
class _AccentPalette extends StatelessWidget {
  const _AccentPalette({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget swatch(int i) => Semantics(
          button: true,
          selected: i == selected,
          label: tr(AppConfig.accentNames[i]),
          child: GestureDetector(
            key: ValueKey('accent-${AppConfig.accentKeys[i]}'),
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
        );
    Widget group(String title, int from, int to) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(tr(title), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
            Wrap(spacing: 10, runSpacing: 10, children: [for (var i = from; i < to; i++) swatch(i)]),
          ],
        );
    // Same two groups as the web: standard tones, then pastels.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('โทนมาตรฐาน', 0, AppConfig.accentPastelStart),
        const SizedBox(height: 10),
        group('โทนพาสเทล', AppConfig.accentPastelStart, AppConfig.accentOptions.length),
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
      builder: (context, _) => SettingsTile(
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

/// "เตือนวันเกิดลูกค้าล่วงหน้า 1 วัน" (09:00 the day before), on by default.
class _BirthdayReminderTile extends StatefulWidget {
  const _BirthdayReminderTile();

  @override
  State<_BirthdayReminderTile> createState() => _BirthdayReminderTileState();
}

class _BirthdayReminderTileState extends State<_BirthdayReminderTile> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    BirthdayReminders.isEnabled(context.read<AppConfig>().prefsScope).then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: NxI.cake,
      tint: const Color(0xFFEC4899),
      title: 'เตือนวันเกิดลูกค้าล่วงหน้า 1 วัน',
      subtitle: 'Lead / Contact / Account · แจ้งเวลา 09:00 ของวันก่อนวันเกิด',
      trailing: Switch(
        key: const ValueKey('settings-bday-remind'),
        value: _on ?? true,
        onChanged: _on == null
            ? null
            : (v) async {
                setState(() => _on = v);
                final config = context.read<AppConfig>();
                List<CalBirthday>? all;
                if (v) {
                  final b = CalBirthdays(config.apiClient);
                  await b.load();
                  all = b.all;
                  b.dispose();
                }
                await BirthdayReminders.setEnabled(config.prefsScope, v, birthdays: all);
              },
      ),
    );
  }
}
