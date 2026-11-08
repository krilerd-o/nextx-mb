import 'package:flutter/material.dart';
import '../../widgets/nx_skeleton.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_logout.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_surface_card.dart';
import '../notifications/notification_center_screen.dart' show relativeTime;
import '../../core/i18n.dart';
import '../../widgets/nx_refresh.dart';

/// Platform icon + Thai label for a session row.
(IconData, String) deviceKind(Map<String, dynamic> s) {
  final platform = (s['platform'] ?? '').toString().toLowerCase();
  final web = s['client']?.toString() == 'web';
  if (platform == 'android') return (NxI.deviceMobile, web ? 'เว็บบน Android' : 'แอป Android');
  if (platform == 'ios') return (NxI.deviceMobile, web ? 'เว็บบน iPhone' : 'แอป iPhone');
  if (platform == 'windows' || platform == 'macos' || platform == 'linux') return (NxI.globe, 'เว็บบนคอมพิวเตอร์');
  return (web ? NxI.globe : NxI.deviceMobile, web ? 'เว็บเบราว์เซอร์' : 'แอปมือถือ');
}

/// Devices signed in to this Space's account: see each one, sign one out,
/// sign out the others or every device. Older servers (no `device_sessions`)
/// only offer "sign out this device".
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>>? _list;
  String? _current;
  Object? _error;
  bool _busy = false;

  bool get _supported => context.read<AppConfig>().serverInfo?.has('device_sessions') ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!_supported) {
      setState(() => _list = const []);
      return;
    }
    try {
      final r = await context.read<AppConfig>().apiClient.getDeviceSessions();
      if (!mounted) return;
      setState(() {
        _list = r.list;
        _current = r.currentSid;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<bool> _confirm(String title, String body, String ok) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: Text(tr(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ok))),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _kick(Map<String, dynamic> s) async {
    final (_, kind) = deviceKind(s);
    final name = (s['device_name'] ?? kind).toString();
    if (!await _confirm('ออกจากระบบ "$name"?', 'อุปกรณ์นี้จะต้องเข้าสู่ระบบใหม่', 'ออกจากระบบ')) return;
    if (!mounted) return;
    final api = context.read<AppConfig>().apiClient;
    setState(() => _list = [...?_list]..remove(s));
    await _run(() => api.revokeDeviceSession(s['sid'].toString()), 'ออกจากระบบ $name แล้ว');
  }

  Future<void> _logoutHere() async {
    final config = context.read<AppConfig>();
    if (!await confirmNxLogout(context, config)) return;
    await config.logout();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfig>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _list;
    final others = list?.where((s) => s['sid']?.toString() != _current).toList() ?? const [];
    return NxScrollScaffold(
      header: const NxAppHeader(title: 'อุปกรณ์ที่เข้าใช้งาน'),
      body: NxRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              tr('${config.activeSpace?.title ?? ''} · ${config.session.email ?? ''}'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(tr(formatApiError(_error!)), style: TextStyle(color: cs.error))
            else if (list == null)
              const NxSkeletonList(rows: 3)
            else if (!_supported)
              Text(
                tr('ระบบ MOAI NEXT ของ Space นี้ยังไม่รองรับการดูอุปกรณ์อื่น (ต้องอัปเดตระบบ) — ออกจากระบบเครื่องนี้ได้ตามปกติ'),
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              )
            else
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DeviceTile(
                    s: s,
                    current: s['sid']?.toString() == _current,
                    onKick: _busy || s['sid']?.toString() == _current ? null : () => _kick(s),
                  ),
                ),
            const SizedBox(height: 16),
            if (_supported && others.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!await _confirm('ออกจากระบบอุปกรณ์อื่นทั้งหมด?', 'อุปกรณ์อื่น ${others.length} เครื่องจะต้องเข้าสู่ระบบใหม่ เครื่องนี้ใช้งานต่อได้', 'ออกจากระบบ')) return;
                        if (!context.mounted) return;
                        await _run(() => context.read<AppConfig>().apiClient.revokeOtherDeviceSessions(), 'ออกจากระบบอุปกรณ์อื่นแล้ว');
                      },
                icon: const Icon(NxI.signOut),
                label: Text(tr('ออกจากระบบอุปกรณ์อื่น (${others.length})')),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _logoutHere,
              icon: const Icon(NxI.signOut),
              label: Text(tr('ออกจากระบบเครื่องนี้')),
            ),
            if (_supported) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: cs.error),
                onPressed: _busy
                    ? null
                    : () async {
                        if (!await _confirm('ออกจากระบบทุกอุปกรณ์?', 'ทุกเครื่องรวมเครื่องนี้จะต้องเข้าสู่ระบบใหม่', 'ออกจากทุกเครื่อง')) return;
                        if (!context.mounted) return;
                        final config = context.read<AppConfig>();
                        try {
                          await config.apiClient.revokeAllDeviceSessions();
                        } catch (_) {}
                        await config.logout();
                      },
                child: Text(tr('ออกจากระบบทุกอุปกรณ์')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.s, required this.current, required this.onKick});
  final Map<String, dynamic> s;
  final bool current;
  final VoidCallback? onKick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (icon, kind) = deviceKind(s);
    final name = (s['device_name']?.toString().trim().isNotEmpty ?? false) ? s['device_name'].toString() : kind;
    final details = [
      if (name != kind) kind,
      if ((s['app_version'] ?? '').toString().isNotEmpty) 'v${s['app_version']}',
      if ((s['ip'] ?? '').toString().isNotEmpty) s['ip'].toString(),
    ].join(' · ');
    final tile = NxSurfaceCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (current ? const Color(0xFF16A34A) : cs.primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: current ? const Color(0xFF16A34A) : cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(tr(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                    if (current) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                        child: Text(tr('เครื่องนี้'), style: TextStyle(color: Color(0xFF16A34A), fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                if (details.isNotEmpty) Text(tr(details), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                Text(
                  tr(current ? 'กำลังใช้งาน' : 'ใช้งานล่าสุด ${relativeTime(s['last_seen_at'])}'),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onKick != null) IconButton(tooltip: tr('ออกจากระบบอุปกรณ์นี้'), icon: Icon(NxI.signOut, color: cs.error), onPressed: onKick),
        ],
      ),
    );
    if (onKick == null) return tile;
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
        decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(18)),
        child: const Icon(NxI.signOut, color: Colors.white),
      ),
      child: tile,
    );
  }
}
