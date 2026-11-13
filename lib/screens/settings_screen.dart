import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/app_version.dart';
import '../core/i18n.dart';
import '../core/menu_access.dart';
import '../core/navigation/app_routes.dart';
import '../core/nx_page_route.dart';
import '../core/server_profile.dart';
import '../services/offline_queue.dart';
import '../services/shutter_sound.dart';
import '../widgets/nx_icons.dart';
import '../widgets/settings_tiles.dart';
import '../widgets/shutter_sound_picker.dart';
import 'profile/my_signatures_screen.dart';
import 'profile/notification_prefs_screen.dart';
import 'profile/profile_manage_screen.dart';
import 'profile/profile_ui.dart';
import 'profile/security_settings_screen.dart';
import 'profile/theme_settings_screen.dart';
import 'update_required_screen.dart';

export '../widgets/settings_tiles.dart' show SettingsAppear, SettingsGroup, SettingsTile;

/// One searchable setting: which group it sits in, the words it matches, and its row.
class _Entry {
  const _Entry(this.group, this.words, this.child);
  final String group;
  final List<String> words;
  final Widget child;
}

/// A setting that lives on another page: found by search, opens that page.
class _Elsewhere {
  const _Elsewhere(this.id, this.page, this.icon, this.tint, this.words, this.open);
  final String id;
  final String page;
  final IconData icon;
  final Color tint;
  final List<String> words;
  final void Function(BuildContext context) open;
}

const _groupOrder = [
  'การใช้งาน',
  'ข้อมูลและพื้นที่จัดเก็บ',
  'เกี่ยวกับแอป',
  'ช่วยเหลือและวินิจฉัย',
];

/// "การตั้งค่า": what is left once theme, devices, signatures, security and
/// notifications have their own pages — grouped, searchable. Searching for a
/// setting that moved shows a shortcut to its page.
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

  bool _hit(List<String> words) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return words.any((w) => w.toLowerCase().contains(q) || tr(w).toLowerCase().contains(q));
  }

  List<_Entry> _entries(BuildContext context, AppConfig config) {
    final cs = Theme.of(context).colorScheme;
    final session = config.session;
    return [
      // ── Using the app
      _Entry('การใช้งาน', ['เสียง', 'ชัตเตอร์', 'กล้อง', 'shutter', 'camera', 'ถ่ายรูป'], SettingsTile(
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
      if (MenuAccess.allow(session, MenuAccess.commAi))
        _Entry('การใช้งาน', ['ไอแซค', 'ISAAC', 'AI', 'ถอดเสียง', 'สรุป', 'prompt', 'โทร', 'แชท'], SettingsTile(
          key: const ValueKey('settings-comm-ai'),
          icon: NxI.sparkle,
          tint: const Color(0xFF7C3AED),
          title: 'ไอแซคเอไอ การสื่อสาร',
          subtitle: session.isBusinessAdmin ? 'ถอดเสียงในสาย สรุปการโทร/แชท และ Prompt' : 'ดูการตั้งค่าการถอดเสียงและการสรุป',
          onTap: () => context.push(AppRoutes.commAiSettings),
        )),

      // ── Data & storage
      _Entry('ข้อมูลและพื้นที่จัดเก็บ', ['ค้างส่ง', 'ออฟไลน์', 'offline', 'ซิงค์', 'sync'], ValueListenableBuilder<int>(
        valueListenable: OfflineQueue.pending,
        builder: (context, n, _) => SettingsTile(
          key: const ValueKey('settings-offline-queue'),
          icon: NxI.cloud,
          tint: const Color(0xFF0EA5E9),
          title: 'ข้อมูลที่รอส่ง',
          subtitle: n == 0 ? 'ส่งครบแล้ว ไม่มีข้อมูลค้างในเครื่อง' : 'ค้าง $n รายการ · แตะเพื่อส่งตอนนี้',
          onTap: n == 0 ? null : () => config.flushOfflineQueue(),
        ),
      )),
      _Entry('ข้อมูลและพื้นที่จัดเก็บ', ['แคช', 'cache', 'รูป', 'ความจำ'], SettingsTile(
        key: const ValueKey('settings-clear-cache'),
        icon: NxI.hardDrives,
        tint: const Color(0xFF64748B),
        title: 'ล้างแคชรูปภาพ',
        subtitle: 'โหลดรูปใหม่จากเซิร์ฟเวอร์ ไม่ลบข้อมูลของคุณ',
        onTap: () {
          PaintingBinding.instance.imageCache
            ..clear()
            ..clearLiveImages();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ล้างแคชรูปภาพแล้ว'))));
        },
      )),

      // ── About
      _Entry('เกี่ยวกับแอป', ['เวอร์ชัน', 'version'], SettingsTile(
        key: const ValueKey('settings-version'),
        icon: NxI.info,
        tint: cs.primary,
        title: 'MOAI NEXT Mobile',
        subtitle: 'เวอร์ชัน ${SettingsScreen.appVersion}',
      )),
      if (config.updateNeed == UpdateNeed.optional)
        _Entry('เกี่ยวกับแอป', ['อัปเดต', 'update'], SettingsTile(
          icon: NxI.arrowSquareOut,
          tint: const Color(0xFF10B981),
          title: 'มีแอปเวอร์ชันใหม่ ${config.serverInfo?.latestVersion ?? ''}',
          subtitle: 'เวอร์ชันในเครื่อง ${AppVersion.value}',
          onTap: storeUrlFor(config.serverInfo) == null ? null : () => openStore(config.serverInfo),
        )),

      // ── Help & diagnostics
      _Entry('ช่วยเหลือและวินิจฉัย', ['บันทึกปัญหา', 'ปัญหา', 'log', 'diagnostics', 'ช่วยเหลือ'], SettingsTile(
        key: const ValueKey('settings-diagnostics'),
        icon: NxI.bug,
        tint: const Color(0xFFF97316),
        title: 'บันทึกปัญหา',
        subtitle: 'ส่งข้อมูลให้ทีมพัฒนาเมื่อพบปัญหา',
        onTap: () => context.push(AppRoutes.diagnostics),
      )),
    ];
  }

  /// Settings that moved to their own page (search shortcuts only).
  static final List<_Elsewhere> _elsewhere = [
    _Elsewhere('theme', 'จัดการธีม', NxI.palette, const Color(0xFF8B5CF6),
        ['ธีม', 'สว่าง', 'มืด', 'สีธีม', 'สี', 'ภาษา', 'ฟอนต์', 'ตัวอักษร', 'ขนาดหน้าจอ', 'ตำแหน่งเมนู', 'แท็บเล็ต', 'เอฟเฟกต์', 'วันที่', 'theme', 'dark', 'font', 'language'],
        (c) => nxPush<void>(c, const ThemeSettingsScreen())),
    _Elsewhere('devices', 'จัดการอุปกรณ์', NxI.monitorSmartphone, const Color(0xFF0EA5E9),
        ['อุปกรณ์', 'เครื่อง', 'ออกจากระบบ', 'เมนูล่าง', 'ปรับแต่งเมนู', 'แท็บ', 'บทบาท', 'หน้าหลัก', 'วิดเจ็ท', 'device', 'role', 'home', 'tab'],
        (c) => c.push(AppRoutes.devices)),
    _Elsewhere('signatures', 'จัดการลายเซ็น', NxI.signature, const Color(0xFFEC4899), ['ลายเซ็น', 'signature'],
        (c) => nxPush<void>(c, const MySignaturesScreen())),
    _Elsewhere('security', 'จัดการความปลอดภัย', NxI.shieldCheck, const Color(0xFF10B981),
        ['รหัสผ่าน', 'ล็อก', 'ลายนิ้วมือ', 'ใบหน้า', 'ความปลอดภัย', '2FA', 'password', 'biometric'],
        (c) => nxPush<void>(c, const SecuritySettingsScreen())),
    _Elsewhere('notifications', 'จัดการการแจ้งเตือน', NxI.bell, const Color(0xFFF43F5E), ['แจ้งเตือน', 'พุช', 'วันเกิด', 'notification', 'push'],
        (c) => nxPush<void>(c, const NotificationPrefsScreen())),
    _Elsewhere('whats-new', 'มีอะไรใหม่', NxI.megaphone, const Color(0xFFF59E0B), ['มีอะไรใหม่', 'ประกาศ', 'what'],
        (c) => c.push(AppRoutes.whatsNew)),
    _Elsewhere('profile', 'จัดการโปรไฟล์', NxI.userCog, const Color(0xFF6366F1), ['เบอร์', 'มือถือ', 'ลบบัญชี', 'ปิดบัญชี', 'โปรไฟล์', 'phone', 'delete'],
        (c) => nxPush<void>(c, const ProfileManageScreen())),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = context.watch<AppConfig>();
    final visible = _entries(context, config).where((e) => _hit([e.group, ...e.words])).toList();
    final groups = <String, List<Widget>>{};
    for (final g in _groupOrder) {
      final rows = [for (final e in visible) if (e.group == g) e.child];
      if (rows.isNotEmpty) groups[g] = rows;
    }
    final jumps = _q.isEmpty ? const <_Elsewhere>[] : _elsewhere.where((e) => _hit([e.page, ...e.words])).toList();

    var stagger = 0;
    return ProfileSubPage(
      title: 'การตั้งค่า',
      children: [
        SettingsAppear(
          index: stagger++,
          child: TextField(
            key: const ValueKey('settings-search'),
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
              if (jumps.isNotEmpty)
                SettingsGroup(
                  key: const ValueKey('settings-elsewhere'),
                  title: 'อยู่ในหน้าอื่น',
                  children: [
                    for (final j in jumps)
                      SettingsTile(
                        key: ValueKey('settings-jump-${j.id}'),
                        icon: j.icon,
                        tint: j.tint,
                        title: j.page,
                        subtitle: 'โปรไฟล์ → ${j.page}',
                        onTap: () => j.open(context),
                      ),
                  ],
                ),
              for (final g in groups.entries)
                SettingsAppear(
                  key: ValueKey(g.key),
                  index: stagger++,
                  child: SettingsGroup(title: g.key, children: g.value),
                ),
              if (groups.isEmpty && jumps.isEmpty)
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
    );
  }
}
