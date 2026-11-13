import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/app_version.dart';
import '../../core/i18n.dart';
import '../../core/menu_access.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_page_route.dart';
import '../../core/shell_tabs.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import '../dashboard/home_layout_editor.dart';
import '../notifications/notification_center_screen.dart' show relativeTime;
import '../onboarding/tab_setup_screen.dart' show TabBarPreview;
import '../profile/profile_ui.dart';

/// Platform icon + Thai label for a session row.
(IconData, String) deviceKind(Map<String, dynamic> s) {
  final platform = (s['platform'] ?? '').toString().toLowerCase();
  final web = s['client']?.toString() == 'web';
  if (platform == 'android') return (web ? NxI.globe : NxI.deviceMobile, web ? 'เว็บบน Android' : 'แอป Android');
  if (platform == 'ios') return (web ? NxI.globe : NxI.deviceMobile, web ? 'เว็บบน iPhone' : 'แอป iPhone');
  if (platform == 'ipados') return (NxI.tablet, web ? 'เว็บบน iPad' : 'แอป iPad');
  if (platform == 'windows' || platform == 'macos' || platform == 'linux') return (NxI.laptop, 'เว็บบนคอมพิวเตอร์');
  return (web ? NxI.globe : NxI.deviceMobile, web ? 'เว็บเบราว์เซอร์' : 'แอปมือถือ');
}

/// Browser / OS from a user-agent ("Chrome บน Windows"), or null.
String? browserFromUserAgent(String? ua) {
  final u = (ua ?? '').trim();
  if (u.isEmpty) return null;
  String? browser;
  if (u.contains('Edg/')) {
    browser = 'Edge';
  } else if (u.contains('OPR/') || u.contains('Opera')) {
    browser = 'Opera';
  } else if (u.contains('Firefox/')) {
    browser = 'Firefox';
  } else if (u.contains('Chrome/') || u.contains('CriOS/')) {
    browser = 'Chrome';
  } else if (u.contains('Safari/')) {
    browser = 'Safari';
  }
  String? os;
  if (u.contains('Windows')) {
    os = 'Windows';
  } else if (u.contains('iPhone')) {
    os = 'iPhone';
  } else if (u.contains('iPad')) {
    os = 'iPad';
  } else if (u.contains('Mac OS X') || u.contains('Macintosh')) {
    os = 'macOS';
  } else if (u.contains('Android')) {
    os = 'Android';
  } else if (u.contains('Linux')) {
    os = 'Linux';
  }
  if (browser == null && os == null) return null;
  if (browser == null) return os;
  return os == null ? browser : '$browser · $os';
}

String _clean(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

/// Display name of a session: its device name, else the browser, else the kind.
String deviceDisplayName(Map<String, dynamic> s) {
  final name = _clean(s['device_name']);
  if (name.isNotEmpty) return name;
  final web = browserFromUserAgent(_clean(s['user_agent']));
  if (s['client']?.toString() == 'web' && web != null) return web;
  return deviceKind(s).$2;
}

/// "3 ชั่วโมงที่แล้ว · 13/11/2569 14:05" (Bangkok time), or '' without a time.
String deviceLastActive(Object? raw) {
  final s = _clean(raw);
  if (s.isEmpty) return '';
  final rel = relativeTime(s);
  final abs = formatThaiField(s, null, year: uiYear);
  if (rel.isEmpty) return abs;
  // Older than a week, relativeTime already shows the date.
  return rel.contains('/') ? abs : '${tr(rel)} · $abs';
}

/// This phone as the server would list it, from the headers the app sends.
Map<String, dynamic> thisDeviceInfo() {
  final h = ApiClient.deviceHeaders;
  var name = h['X-Device-Name'] ?? '';
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  return {
    'device_name': name,
    'platform': h['X-Device-Platform'] ?? '',
    'client': 'mobile',
    'app_version': AppVersion.value,
  };
}

/// "จัดการอุปกรณ์": this device (always), the other devices signed in to the
/// account (sign out one / all others, with confirmation), and the settings
/// that shape the app on this device: bottom menu, role, Home layout.
/// Older servers (no `/api/me/sessions` or `unavailable`) keep this device's
/// card and say the server needs an update.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>>? _list;
  String? _current;
  Object? _error;
  bool _unavailable = false;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppConfig>().apiClient.getDeviceSessions();
      if (!mounted) return;
      setState(() {
        _list = r.list;
        _current = r.currentSid;
        _unavailable = r.unavailable;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _list = const [];
        if (isMissingEndpoint(e)) {
          _unavailable = true;
          _error = null;
        } else {
          _error = e;
        }
      });
    }
  }

  bool _isCurrent(Map<String, dynamic> s) => s['current'] == true || (_current != null && s['sid']?.toString() == _current);

  Future<bool> _confirm(String title, String body, String ok, {bool danger = true}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: Text(tr(body)),
        actions: [
          TextButton(key: const ValueKey('dev-confirm-cancel'), onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(
            key: const ValueKey('dev-confirm-ok'),
            style: danger ? FilledButton.styleFrom(backgroundColor: nxDangerColor(ctx), foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(ok)),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _run(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(SnackBar(content: Text(tr(done))));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _kick(Map<String, dynamic> s) async {
    final name = deviceDisplayName(s);
    if (!await _confirm('ออกจากระบบ "$name"?', 'อุปกรณ์นี้จะต้องเข้าสู่ระบบใหม่', 'ออกจากระบบ')) return;
    if (!mounted) return;
    final api = context.read<AppConfig>().apiClient;
    setState(() => _list = [...?_list]..remove(s));
    await _run(() => api.revokeDeviceSession(s['sid'].toString()), 'ออกจากระบบ $name แล้ว');
  }

  Future<void> _kickOthers(int n) async {
    if (!await _confirm('ออกจากระบบอุปกรณ์อื่นทั้งหมด?', 'อุปกรณ์อื่น $n เครื่องจะต้องเข้าสู่ระบบใหม่ เครื่องนี้ใช้งานต่อได้', 'ออกจากระบบ')) return;
    if (!mounted) return;
    final api = context.read<AppConfig>().apiClient;
    await _run(api.revokeOtherDeviceSessions, 'ออกจากระบบอุปกรณ์อื่นแล้ว');
  }

  Future<void> _logoutHere() async {
    final config = context.read<AppConfig>();
    if (!await confirmNxLogout(context, config)) return;
    await config.logout();
  }

  Future<void> _logoutAll() async {
    if (!await _confirm('ออกจากระบบทุกอุปกรณ์?', 'ทุกเครื่องรวมเครื่องนี้จะต้องเข้าสู่ระบบใหม่', 'ออกจากทุกเครื่อง')) return;
    if (!mounted) return;
    final config = context.read<AppConfig>();
    try {
      await config.apiClient.revokeAllDeviceSessions();
    } catch (_) {}
    await config.logout();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _list ?? const <Map<String, dynamic>>[];
    final mine = list.where(_isCurrent).firstOrNull;
    final others = [for (final s in list) if (!_isCurrent(s)) s]
      ..sort((a, b) => _clean(b['last_seen_at']).compareTo(_clean(a['last_seen_at'])));
    final session = config.session;
    final tabs = resolveShellTabs(
      roles: config.shellConfig?.roles ?? const ['general'],
      custom: config.shellConfig?.tabs,
      allowed: (keys) => MenuAccess.any(session, keys),
    );
    final sessionsWork = !_unavailable && _error == null && !_loading;
    var i = 0;

    return ProfileSubPage(
      title: 'จัดการอุปกรณ์',
      onRefresh: _load,
      children: [
        Text(
          [config.activeSpace?.title, session.email].where((e) => (e ?? '').isNotEmpty).join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        SettingsAppear(
          index: i++,
          child: _ThisDeviceCard(server: mine, busy: _busy, onLogout: _logoutHere),
        ),
        if (_unavailable)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: NxSoftNote(
              key: ValueKey('dev-unavailable'),
              icon: NxI.cloud,
              title: 'ยังดูอุปกรณ์อื่นไม่ได้',
              text: 'ระบบ MOAI NEXT ของพื้นที่ทำงานนี้ยังไม่รองรับการดูอุปกรณ์อื่น (ต้องอัปเดตเซิร์ฟเวอร์) — ออกจากระบบเครื่องนี้ได้ตามปกติ',
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: NxSoftNote(
              key: const ValueKey('dev-error'),
              icon: NxI.warningCircle,
              color: cs.error,
              text: formatApiError(_error!),
              action: TextButton.icon(onPressed: _load, icon: const Icon(NxI.arrowClockwise, size: 16), label: Text(tr('ลองใหม่'))),
            ),
          ),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 16), child: NxSkeletonList(rows: 2)),
        if (sessionsWork)
          SettingsAppear(
            index: i++,
            child: SettingsGroup(
              title: 'อุปกรณ์อื่น (${others.length})',
              caption: 'แตะไอคอนออกจากระบบ หรือปัดซ้ายเพื่อออกจากระบบเครื่องนั้น',
              children: [
                if (others.isEmpty)
                  Padding(
                    key: const ValueKey('dev-no-others'),
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      Icon(NxI.shieldCheck, color: const Color(0xFF16A34A).withValues(alpha: 0.9)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tr('ไม่มีอุปกรณ์อื่นที่เข้าสู่ระบบอยู่'), style: theme.textTheme.bodyMedium)),
                    ]),
                  )
                else
                  for (final s in others) _DeviceRow(s: s, onKick: _busy ? null : () => _kick(s)),
              ],
            ),
          ),
        if (sessionsWork && others.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('dev-revoke-others'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: nxDangerColor(context)),
            onPressed: _busy ? null : () => _kickOthers(others.length),
            icon: const Icon(NxI.signOut, size: 18),
            label: Text(tr('ออกจากระบบอุปกรณ์อื่นทั้งหมด (${others.length})')),
          ),
        ],
        if (sessionsWork)
          Center(
            child: TextButton(
              key: const ValueKey('dev-revoke-all'),
              style: TextButton.styleFrom(foregroundColor: nxDangerColor(context)),
              onPressed: _busy ? null : _logoutAll,
              child: Text(tr('ออกจากระบบทุกอุปกรณ์ (รวมเครื่องนี้)')),
            ),
          ),

        // ── How the app looks / works on this device (moved from settings).
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'ปรับแต่งการใช้งานบนเครื่องนี้',
            caption: 'เมนูล่าง บทบาท และกล่องบนหน้าหลัก',
            children: [
              SettingsTile(
                key: const ValueKey('dev-tab-editor'),
                icon: NxI.panelBottom,
                tint: const Color(0xFF6366F1),
                title: 'ปรับแต่งเมนู',
                subtitle: 'เลือกและเรียงแท็บที่ต้องการบนแถบเมนูล่าง',
                onTap: () => context.push(AppRoutes.tabEditor),
                below: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      // A picture of the bar: drawn at its own size whatever the text scale.
                      child: MediaQuery.withNoTextScaling(child: SizedBox(width: 360, child: TabBarPreview(tabs: tabs))),
                    ),
                  ),
                ),
              ),
              SettingsTile(
                key: const ValueKey('dev-role-editor'),
                icon: NxI.users,
                tint: const Color(0xFF0EA5E9),
                title: 'บทบาทของฉัน',
                subtitle: roleSummary(config.shellConfig?.roles ?? const []),
                onTap: () => context.push(AppRoutes.roleEditor),
              ),
              SettingsTile(
                key: const ValueKey('dev-home-editor'),
                icon: NxI.squaresFour,
                tint: const Color(0xFF10B981),
                title: 'ปรับแต่งหน้าหลัก',
                subtitle: 'เรียงและซ่อน/แสดงกล่องบนหน้าหลัก',
                onTap: () => nxPush<bool>(context, const HomeLayoutEditorScreen(), root: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// This phone: always shown, filled from the server's row when it has one.
class _ThisDeviceCard extends StatelessWidget {
  const _ThisDeviceCard({required this.server, required this.busy, required this.onLogout});
  final Map<String, dynamic>? server;
  final bool busy;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const green = Color(0xFF16A34A);
    final local = thisDeviceInfo();
    final s = <String, dynamic>{...local, ...?server?.map((k, v) => MapEntry(k, _clean(v).isEmpty ? local[k] : v))};
    final (icon, kind) = deviceKind(s);
    final name = deviceDisplayName(s);
    final version = _clean(s['app_version']).isEmpty ? AppVersion.value : _clean(s['app_version']);
    final ip = _clean(s['ip']);
    final location = _clean(s['location']);
    Widget fact(IconData i, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(i, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
          ]),
        );
    return Container(
      key: const ValueKey('dev-this-device'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(green.withValues(alpha: 0.16), cs.surfaceContainerHighest), cs.surfaceContainerHighest],
        ),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: green.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: green, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(tr(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('dev-this-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: green.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                  child: Text(tr('เครื่องนี้'), style: theme.textTheme.labelSmall?.copyWith(color: green, fontWeight: FontWeight.w800)),
                ),
              ]),
              Text(tr(kind), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        fact(NxI.package, '${tr('เวอร์ชันแอป')} $version'),
        if (ip.isNotEmpty || location.isNotEmpty) fact(NxI.mapPin, [location, ip].where((e) => e.isNotEmpty).join(' · ')),
        fact(NxI.clock, tr('ใช้งานอยู่ตอนนี้')),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          key: const ValueKey('dev-logout-here'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: busy ? null : onLogout,
          icon: const Icon(NxI.signOut, size: 18),
          label: Text(tr('ออกจากระบบเครื่องนี้')),
        ),
      ]),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.s, required this.onKick});
  final Map<String, dynamic> s;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (icon, kind) = deviceKind(s);
    final name = deviceDisplayName(s);
    final details = [
      if (name != kind) tr(kind),
      if (_clean(s['app_version']).isNotEmpty) 'v${_clean(s['app_version'])}',
    ].join(' · ');
    final place = [_clean(s['location']), _clean(s['ip'])].where((e) => e.isNotEmpty).join(' · ');
    final seen = deviceLastActive(s['last_seen_at'] ?? s['created_at']);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (details.isNotEmpty) Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                if (place.isNotEmpty)
                  Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (seen.isNotEmpty)
                  Text(
                    '${tr('ใช้งานล่าสุด')} $seen',
                    key: ValueKey('dev-seen-${s['sid']}'),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('dev-kick-${s['sid']}'),
            tooltip: tr('ออกจากระบบอุปกรณ์นี้'),
            icon: Icon(NxI.signOut, color: onKick == null ? cs.outline : nxDangerColor(context)),
            onPressed: onKick,
          ),
        ],
      ),
    );
    if (onKick == null) return row;
    // Swipe left to sign that device out.
    return Dismissible(
      key: ValueKey('dev-${s['sid']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onKick!();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: nxDangerColor(context),
        child: const Icon(NxI.signOut, color: Colors.white),
      ),
      child: row,
    );
  }
}
