import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import '../profile_edit_screen.dart';
import 'delete_account_screen.dart';
import 'phone_change_screen.dart';
import 'profile_ui.dart';

String _clean(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

/// Full name in Thai / English from a `/api/me/profile` row ('' when none).
String profileName(Map<String, dynamic> p, {required bool thai}) {
  final first = _clean(p[thai ? 'first_name_th' : 'first_name']);
  final last = _clean(p[thai ? 'last_name_th' : 'last_name']);
  return [first, last].where((e) => e.isNotEmpty).join(' ');
}

/// One-line address from the profile's address fields.
String profileAddress(Map<String, dynamic> p) =>
    [for (final k in ['address_street', 'address_city', 'address_state', 'address_postalcode', 'address_country']) _clean(p[k])].where((e) => e.isNotEmpty).join(' ');

/// "จัดการโปรไฟล์": what `GET /api/me/profile` holds about me, grouped, and
/// the account actions: change mobile number, delete (close) the account.
class ProfileManageScreen extends StatefulWidget {
  const ProfileManageScreen({super.key});

  @override
  State<ProfileManageScreen> createState() => _ProfileManageScreenState();
}

class _ProfileManageScreenState extends State<ProfileManageScreen> {
  Map<String, dynamic>? _p;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await context.read<AppConfig>().apiClient.getMyProfile();
      if (mounted) {
        setState(() {
          _p = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit() async {
    final saved = await nxPush<bool>(context, const ProfileEditScreen());
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = _p;
    final s = config.session;
    final children = <Widget>[];
    var i = 0;

    if (p == null) {
      children.add(_error == null
          ? const NxSkeletonList(rows: 4)
          : NxSoftNote(
              icon: NxI.warningCircle,
              color: cs.error,
              text: formatApiError(_error!),
              action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
            ));
    } else {
      final th = profileName(p, thai: true);
      final en = profileName(p, thai: false);
      final email = _clean(p['email1']).isNotEmpty ? _clean(p['email1']) : (s.email ?? '');
      final mobile = _clean(p['phone_mobile']);
      final lang = _clean(p['user_language']);
      Widget info(String key, IconData icon, Color tint, String title, String value) => SettingsTile(
            key: ValueKey('pm-$key'),
            icon: icon,
            tint: tint,
            title: title,
            subtitle: value.isEmpty ? tr('ยังไม่ได้ระบุ') : value,
          );
      children.addAll([
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'ข้อมูลส่วนตัว', action: TextButton.icon(
            key: const ValueKey('pm-edit'),
            onPressed: _edit,
            icon: const Icon(NxI.pencilSimple, size: 16),
            label: Text(tr('แก้ไข')),
          ), children: [
            info('name-th', NxI.user, const Color(0xFF6366F1), 'ชื่อ-นามสกุล (ไทย)', th),
            info('name-en', NxI.user, const Color(0xFF0EA5E9), 'ชื่อ-นามสกุล (อังกฤษ)', en),
            if (_clean(p['user_name']).isNotEmpty) info('username', NxI.at, const Color(0xFF64748B), 'ชื่อผู้ใช้', _clean(p['user_name'])),
          ]),
        ),
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'การทำงาน', children: [
            info('title', NxI.briefcase, const Color(0xFF8B5CF6), 'ตำแหน่ง', _clean(p['title'])),
            info('department', NxI.buildings, const Color(0xFFF97316), 'แผนก', _clean(p['department'])),
          ]),
        ),
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'ติดต่อ', children: [
            info('email', NxI.envelope, const Color(0xFF0EA5E9), 'อีเมล', email),
            info('mobile', NxI.deviceMobile, const Color(0xFF10B981), 'มือถือ', mobile.isEmpty ? '' : formatPhone(mobile)),
            if (_clean(p['phone_work']).isNotEmpty) info('work', NxI.phone, const Color(0xFF14B8A6), 'โทรศัพท์ที่ทำงาน', _clean(p['phone_work'])),
            if (_clean(p['phone_home']).isNotEmpty) info('home', NxI.house, const Color(0xFF64748B), 'โทรศัพท์บ้าน', _clean(p['phone_home'])),
            if (profileAddress(p).isNotEmpty) info('address', NxI.mapPin, const Color(0xFFEC4899), 'ที่อยู่', profileAddress(p)),
            if (lang.isNotEmpty) info('lang', NxI.languages, const Color(0xFFF59E0B), 'ภาษาบนเว็บ', lang == 'en' ? 'English' : 'ไทย'),
          ]),
        ),
        if (_clean(p['description']).isNotEmpty)
          SettingsAppear(
            index: i++,
            child: SettingsGroup(title: 'เกี่ยวกับฉัน', children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                child: Text(_clean(p['description']), style: theme.textTheme.bodyMedium),
              ),
            ]),
          ),
        SettingsAppear(
          index: i++,
          child: SettingsGroup(title: 'บัญชี', children: [
            SettingsTile(
              key: const ValueKey('pm-change-phone'),
              icon: NxI.phoneCall,
              tint: const Color(0xFF10B981),
              title: 'เปลี่ยนเบอร์โทรศัพท์',
              subtitle: mobile.isEmpty ? 'ยังไม่มีเบอร์มือถือ · เพิ่มเพื่อเข้าสู่ระบบด้วย OTP SMS' : formatPhone(mobile),
              onTap: () async {
                final changed = await nxPush<bool>(context, PhoneChangeScreen(currentPhone: mobile.isEmpty ? null : mobile));
                if (changed == true) await _load();
              },
            ),
            SettingsTile(
              key: const ValueKey('pm-delete-account'),
              icon: NxI.trash,
              tint: nxDangerColor(context),
              title: 'ลบบัญชี',
              subtitle: 'ปิดบัญชี (Inactive) · ผู้ดูแลระบบเปิดใช้งานคืนได้',
              onTap: () => nxPush<void>(context, const DeleteAccountScreen()),
            ),
          ]),
        ),
      ]);
    }

    return ProfileSubPage(title: 'จัดการโปรไฟล์', onRefresh: _load, children: [
      _ManageHeader(profile: p),
      ...children,
    ]);
  }
}

class _ManageHeader extends StatelessWidget {
  const _ManageHeader({required this.profile});
  final Map<String, dynamic>? profile;

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = config.session;
    final p = profile ?? const <String, dynamic>{};
    final th = profileName(p, thai: true), en = profileName(p, thai: false);
    final name = (L10n.isEn ? (en.isNotEmpty ? en : th) : (th.isNotEmpty ? th : en));
    final shown = name.isNotEmpty ? name : (s.displayName ?? s.email ?? '');
    final other = L10n.isEn ? th : en;
    final image = config.profileAvatarImage;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: cs.primary.withValues(alpha: 0.12),
          backgroundImage: image,
          onBackgroundImageError: image == null ? null : (_, _) {},
          child: image == null ? Text(shown.characters.take(2).toString().toUpperCase(), style: theme.textTheme.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)) : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(shown, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (other.isNotEmpty && other != shown) Text(other, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}
