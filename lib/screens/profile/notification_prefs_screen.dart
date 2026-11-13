import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/settings_tiles.dart';
import 'profile_ui.dart';

/// Device-level notification permission: true on, false off, null unknown.
typedef PushPermissionCheck = Future<bool?> Function();

Future<bool?> _defaultPermission() async {
  try {
    final s = await ph.Permission.notification.status;
    return s.isGranted || s.isProvisional;
  } catch (_) {
    return null;
  }
}

Future<void> _defaultOpenSettings() async {
  try {
    await ph.openAppSettings();
  } catch (_) {}
}

/// One event of `GET /api/me/notification-preferences`.
class NotifEvent {
  NotifEvent(this.raw);
  final Map<String, dynamic> raw;
  String get key => '${raw['key']}';
  String get label => trPair(raw['label_th'], raw['label_en']);
  String get description => trPair(raw['description_th'], raw['description_en']);
  bool get locked => raw['locked'] == true;

  /// Channels this event can use (`available_channels`); null = all.
  List<String>? get availableChannels {
    final a = raw['available_channels'];
    return a is List ? [for (final x in a) '$x'] : null;
  }

  bool offers(String channel) => availableChannels?.contains(channel) ?? true;
  Map<String, bool> get channels {
    final c = raw['channels'];
    return {
      if (c is Map)
        for (final e in c.entries) '${e.key}': e.value == true,
    };
  }
}

/// `{events:{…}}` part of a PUT: only the channels that differ from [before].
Map<String, Map<String, bool>> notifEventChanges(Map<String, Map<String, bool>> before, Map<String, Map<String, bool>> after) {
  final out = <String, Map<String, bool>>{};
  after.forEach((k, ch) {
    ch.forEach((c, v) {
      if (before[k]?[c] != v) (out[k] ??= {})[c] = v;
    });
  });
  return out;
}

/// "จัดการการแจ้งเตือน": per event, in-app (web & app) and push switches,
/// grouped as the server sends them, with per-group all on / off, a global
/// "pause push on mobile" and locked events shown disabled. Changes save on
/// their own (debounced `PUT` of only the changed events), optimistic with
/// rollback on error. The top card shows the phone's own permission.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key, this.permission, this.openSettings, this.debounce = const Duration(milliseconds: 700)});

  final PushPermissionCheck? permission;
  final Future<void> Function()? openSettings;
  final Duration debounce;

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _unsupported = false;
  Object? _error;
  bool? _osAllowed;

  /// What the switches show / what the server last confirmed.
  final Map<String, Map<String, bool>> _values = {};
  final Map<String, Map<String, bool>> _confirmed = {};
  bool _paused = false;
  bool _confirmedPaused = false;

  Timer? _debounce;
  bool _saving = false;
  bool _again = false;

  late final ApiClient _api;

  @override
  void initState() {
    super.initState();
    // Read while the context is alive (dispose may still save).
    _api = context.read<AppConfig>().apiClient;
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Leaving with a change still waiting: send it now (fire and forget).
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _flush(silent: true);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings: the permission may have changed.
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final v = await (widget.permission ?? _defaultPermission)();
    if (mounted) setState(() => _osAllowed = v);
  }

  void _apply(Map<String, dynamic> d) {
    _data = d;
    _values.clear();
    _confirmed.clear();
    for (final g in (d['groups'] as List? ?? const [])) {
      if (g is! Map) continue;
      for (final e in (g['events'] as List? ?? const [])) {
        if (e is! Map) continue;
        final ev = NotifEvent(Map<String, dynamic>.from(e));
        _values[ev.key] = {...ev.channels};
        _confirmed[ev.key] = {...ev.channels};
      }
    }
    _paused = d['push_paused'] == true;
    _confirmedPaused = _paused;
  }

  Future<void> _load() async {
    try {
      final d = await _api.getNotificationPreferences();
      if (!mounted) return;
      setState(() {
        _apply(d);
        _error = null;
        _unsupported = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isMissingEndpoint(e)) {
          _unsupported = true;
        } else {
          _error = e;
        }
      });
    }
  }

  List<String> get _channelKeys {
    final c = _data?['channels'];
    final keys = [
      if (c is List)
        for (final x in c)
          if (x is Map && x['key'] != null) '${x['key']}',
    ];
    return keys.isEmpty ? const ['in_app', 'push'] : keys;
  }

  String _channelLabel(String key) {
    final c = _data?['channels'];
    if (c is List) {
      for (final x in c) {
        if (x is Map && '${x['key']}' == key) {
          final l = trPair(x['label_th'], x['label_en']);
          if (l.isNotEmpty) return l;
        }
      }
    }
    return tr(key == 'push' ? 'พุช' : 'ในแอป');
  }

  void _set(String event, String channel, bool v) {
    HapticFeedback.selectionClick();
    setState(() => (_values[event] ??= {})[channel] = v);
    _schedule();
  }

  void _setPaused(bool v) {
    HapticFeedback.selectionClick();
    setState(() => _paused = v);
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, _flush);
  }

  Future<void> _flush({bool silent = false}) async {
    if (_saving) {
      _again = true;
      return;
    }
    final events = notifEventChanges(_confirmed, _values);
    final paused = _paused != _confirmedPaused ? _paused : null;
    if (events.isEmpty && paused == null) return;
    _saving = true;
    final messenger = silent ? null : ScaffoldMessenger.maybeOf(context);
    try {
      final r = await _api.updateNotificationPreferences(events: events, pushPaused: paused);
      // Confirmed: what we sent.
      events.forEach((k, ch) => (_confirmed[k] ??= {}).addAll(ch));
      if (paused != null) _confirmedPaused = paused;
      // The server's answer wins when nothing newer is waiting.
      final idle = notifEventChanges(_confirmed, _values).isEmpty && _paused == _confirmedPaused;
      if (mounted && idle && r['groups'] is List) setState(() => _apply(r));
    } catch (e) {
      // Roll back what failed, unless the user changed it again meanwhile.
      if (mounted) {
        setState(() {
          events.forEach((k, ch) {
            ch.forEach((c, sent) {
              if (_values[k]?[c] == sent) (_values[k] ??= {})[c] = _confirmed[k]?[c] ?? !sent;
            });
          });
          if (paused != null && _paused == paused) _paused = _confirmedPaused;
        });
      }
      messenger?.showSnackBar(SnackBar(content: Text(tr('บันทึกการแจ้งเตือนไม่สำเร็จ · ${formatApiError(e)}'))));
    } finally {
      _saving = false;
      if (_again) {
        _again = false;
        if (mounted) unawaited(_flush());
      }
    }
  }

  /// All unlocked events of a group on (or off) in every channel.
  void _setGroup(List<NotifEvent> events, bool on) {
    HapticFeedback.mediumImpact();
    setState(() {
      for (final e in events) {
        if (e.locked) continue;
        for (final c in _channelKeys) {
          if (e.offers(c)) (_values[e.key] ??= {})[c] = on;
        }
      }
    });
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[_deviceCard(context)];
    var i = 1;

    if (_unsupported) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: NxSoftNote(
            key: ValueKey('np-unsupported'),
            icon: NxI.cloud,
            title: 'ยังเลือกการแจ้งเตือนแต่ละเรื่องไม่ได้',
            text: 'ระบบ MOAI NEXT ของพื้นที่ทำงานนี้ต้องอัปเดตก่อน — ตอนนี้แอปยังแจ้งเตือนตามค่าเริ่มต้นของระบบ',
          ),
        ),
      );
    } else if (_error != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: NxSoftNote(
            key: const ValueKey('np-error'),
            icon: NxI.warningCircle,
            color: cs.error,
            text: formatApiError(_error!),
            action: TextButton(onPressed: _load, child: Text(tr('ลองใหม่'))),
          ),
        ),
      );
    } else if (_data == null) {
      children.add(const Padding(padding: EdgeInsets.only(top: 16), child: NxSkeletonList(rows: 4)));
    } else {
      children.add(
        SettingsAppear(
          index: i++,
          child: SettingsGroup(
            title: 'ทั้งหมด',
            children: [
              SettingsTile(
                key: const ValueKey('np-pause-tile'),
                icon: NxI.bellSlash,
                tint: const Color(0xFFF59E0B),
                title: 'หยุดแจ้งเตือนบนมือถือชั่วคราว',
                subtitle: _paused ? 'หยุดพุชทุกเรื่องอยู่ · ยังเห็นในแอปและบนเว็บตามปกติ' : 'ปิดพุชทุกเรื่องไว้ก่อน โดยไม่เปลี่ยนตัวเลือกด้านล่าง',
                trailing: Switch(key: const ValueKey('np-pause'), value: _paused, onChanged: _setPaused),
              ),
            ],
          ),
        ),
      );
      final channels = _channelKeys;
      for (final g in (_data!['groups'] as List? ?? const [])) {
        if (g is! Map) continue;
        final events = [
          for (final e in (g['events'] as List? ?? const []))
            if (e is Map) NotifEvent(Map<String, dynamic>.from(e)),
        ];
        if (events.isEmpty) continue;
        final open = events.where((e) => !e.locked).toList();
        final allOn = open.isNotEmpty && open.every((e) => channels.where(e.offers).every((c) => _values[e.key]?[c] == true));
        final gk = '${g['key']}';
        children.add(
          SettingsAppear(
            index: i++,
            child: SettingsGroup(
              title: trPair(g['label_th'], g['label_en']),
              action: open.isEmpty
                  ? null
                  : TextButton(
                      key: ValueKey('np-all-$gk'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () => _setGroup(open, !allOn),
                      child: Text(tr(allOn ? 'ปิดทั้งหมด' : 'เปิดทั้งหมด')),
                    ),
              children: [
                _ChannelHeader(labels: [for (final c in channels) _channelLabel(c)]),
                for (final e in events) _EventRow(event: e, channels: channels, values: _values[e.key] ?? const {}, pushPaused: _paused, onChanged: (c, v) => _set(e.key, c, v)),
              ],
            ),
          ),
        );
      }
    }

    children.add(
      SettingsAppear(
        index: i++,
        child: SettingsGroup(
          title: 'บนเครื่องนี้',
          children: [
            SettingsTile(
              key: const ValueKey('np-center'),
              icon: NxI.bell,
              tint: const Color(0xFFF43F5E),
              title: 'ศูนย์การแจ้งเตือน',
              subtitle: 'ดูการแจ้งเตือนทั้งหมด',
              onTap: () => context.push(AppRoutes.notifications),
            ),
            const BirthdayReminderTile(),
          ],
        ),
      ),
    );
    return ProfileSubPage(
      title: 'จัดการการแจ้งเตือน',
      onRefresh: () async {
        await _checkPermission();
        await _load();
      },
      children: children,
    );
  }

  Widget _deviceCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final allowed = _osAllowed;
    final color = allowed == false ? const Color(0xFFF97316) : (allowed == true ? const Color(0xFF16A34A) : cs.onSurfaceVariant);
    final status = allowed == null ? 'ตรวจสอบสิทธิ์การแจ้งเตือนของเครื่องไม่ได้' : (allowed ? 'เครื่องนี้อนุญาตการแจ้งเตือนแล้ว' : 'เครื่องนี้ปิดการแจ้งเตือนของแอปอยู่');
    final sub = allowed == false ? 'เปิดในการตั้งค่าเครื่องเพื่อรับพุช' : (_paused ? 'พักพุชไว้ชั่วคราว' : 'รับพุชตามตัวเลือกด้านล่าง');
    return Container(
      key: const ValueKey('np-device'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: Icon(allowed == false ? NxI.bellSlash : NxI.bellRinging, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(status),
                  key: const ValueKey('np-device-status'),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(tr(sub), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (allowed != true)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OutlinedButton.icon(
                      key: const ValueKey('np-open-settings'),
                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.5))),
                      onPressed: () async {
                        await (widget.openSettings ?? _defaultOpenSettings)();
                        await _checkPermission();
                      },
                      icon: const Icon(NxI.gear, size: 16),
                      label: Text(tr('เปิดในการตั้งค่าเครื่อง')),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 2),
      child: Row(
        children: [
          const Spacer(),
          for (final l in labels)
            SizedBox(
              width: 64,
              child: Text(
                l,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.channels, required this.values, required this.pushPaused, required this.onChanged});
  final NotifEvent event;
  final List<String> channels;
  final Map<String, bool> values;
  final bool pushPaused;
  final void Function(String channel, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final desc = event.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        event.label,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500, color: event.locked ? cs.onSurfaceVariant : null),
                      ),
                    ),
                    if (event.locked) ...[const SizedBox(width: 6), Icon(NxI.lock, size: 14, color: cs.onSurfaceVariant, key: ValueKey('np-locked-${event.key}'))],
                  ],
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                if (event.locked) Text(tr('ตั้งโดยระบบ เปลี่ยนไม่ได้'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          for (final c in channels)
            if (!event.offers(c))
              SizedBox(
                width: 64,
                child: Text(
                  '—',
                  key: ValueKey('np-${event.key}-$c-na'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline),
                ),
              )
            else
              SizedBox(
                width: 64,
                child: Opacity(
                  opacity: c == 'push' && pushPaused && !event.locked ? 0.5 : 1,
                  child: Switch(key: ValueKey('np-${event.key}-$c'), value: values[c] ?? false, onChanged: event.locked ? null : (v) => onChanged(c, v)),
                ),
              ),
        ],
      ),
    );
  }
}
