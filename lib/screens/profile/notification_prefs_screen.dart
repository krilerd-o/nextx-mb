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
import '../../widgets/app_bottom_sheet.dart';
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

  /// How often it fires ("ทันที", "วันละครั้ง 09:00"); empty on older servers.
  String get frequency => trPair(raw['frequency_th'], raw['frequency_en']);
  bool get locked => raw['locked'] == true;

  /// The company's default for this event, when it set one (locked events use it).
  Map<String, bool>? get companyDefault {
    final c = raw['company_default'];
    return c is Map ? {for (final e in c.entries) '${e.key}': e.value == true} : null;
  }

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

/// Look of one delivery channel: mobile push, the bell (in the app and on the
/// web) and browser (Web Push).
({IconData icon, Color color, String label, String hint}) notifChannelStyle(String key) => switch (key) {
  'push' => (icon: NxI.deviceMobile, color: const Color(0xFF6366F1), label: 'มือถือ', hint: 'แจ้งเตือนขึ้นบนเครื่อง'),
  'web_push' => (icon: NxI.globe, color: const Color(0xFF0EA5E9), label: 'เบราว์เซอร์', hint: 'แจ้งเตือนบนคอมพิวเตอร์'),
  _ => (icon: NxI.bell, color: const Color(0xFFF43F5E), label: 'กระดิ่ง', hint: 'รายการในแอปและบนเว็บ'),
};

/// "Test sent" message from `POST /api/notifications/test`'s answer.
String notifTestResultText(Map<String, dynamic> r) {
  int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  final list = r['devices'];
  final devices = list is List ? list.length : (n(r['devices']) ?? n(r['device_count']) ?? n(r['tokens']));
  final sent = n(r['sent']) ?? n(r['delivered']);
  if (r['no_devices'] == true || devices == 0 || (devices == null && sent == 0)) {
    return 'ส่งแล้ว แต่ยังไม่มีเครื่องที่ลงทะเบียนรับแจ้งเตือน — ลองปิดแล้วเปิดแอปใหม่';
  }
  return 'ส่งการแจ้งเตือนทดสอบแล้ว — ควรขึ้นบนเครื่องนี้ภายในไม่กี่วินาที';
}

/// Per-device rows of a new server's test answer (`devices:[{platform,
/// device_name, token_hint, result, detail}]`); empty for older servers.
List<Map<String, dynamic>> notifTestDevices(Map<String, dynamic> r) {
  final list = r['devices'];
  if (list is! List) return const [];
  return [for (final d in list) if (d is Map) Map<String, dynamic>.from(d)];
}

/// Look of one device result: sent / invalid (token expired, removed) / failed.
({String label, IconData icon, Color color}) notifTestResultStyle(String? result) => switch ((result ?? '').trim()) {
      'sent' => (label: 'ส่งแล้ว', icon: NxI.checkCircle, color: const Color(0xFF16A34A)),
      'queued' => (label: 'เข้าคิวรอส่งใหม่', icon: NxI.clock, color: const Color(0xFF2563EB)),
      'invalid' || 'invalid_removed' => (label: 'เครื่องนี้ใช้ไม่ได้แล้ว', icon: NxI.prohibit, color: const Color(0xFFF59E0B)),
      'skipped' => (label: 'ข้าม (ส่งทางอื่น)', icon: NxI.minus, color: const Color(0xFF64748B)),
      _ => (label: 'ส่งไม่สำเร็จ', icon: NxI.xCircle, color: const Color(0xFFDC2626)),
    };

/// Readable platform of a registered device.
String notifPlatformLabel(String? p) => switch ((p ?? '').trim().toLowerCase()) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'huawei' || 'hms' => 'Huawei',
      'web' || 'web_push' || 'webpush' => 'เบราว์เซอร์',
      final other => other,
    };

/// How the server sent it (`transport`).
String notifTransportLabel(String? t) => switch ((t ?? '').trim()) {
      'notify' => 'ส่งผ่าน Notify',
      'fcm' || 'fcm_direct' => 'ส่งผ่าน Firebase โดยตรง',
      'notify+fcm_fallback' => 'Notify ไม่ตอบ — ส่งผ่าน Firebase โดยตรงแทน',
      'hms' => 'ส่งผ่าน Huawei Push',
      'queued' || 'queue' => 'เข้าคิวรอส่งใหม่',
      'none' || '' => '',
      final other => 'ส่งผ่าน $other',
    };

/// Bottom sheet: the result of the test on each of my devices.
Future<void> showNotifTestResultSheet(BuildContext context, Map<String, dynamic> r) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final devices = notifTestDevices(r);
  final okCount = devices.where((d) => d['result'] == 'sent').length;
  final transport = notifTransportLabel(r['transport']?.toString());
  final job = '${r['job_id'] ?? ''}'.trim();
  final sub = [
    if (transport.isNotEmpty) tr(transport),
    if (job.isNotEmpty && job != 'null') 'job $job',
  ].join(' · ');
  return showAppBottomSheet<void>(
    context: context,
    title: 'ผลการส่งทดสอบ',
    child: Column(
      key: const ValueKey('np-test-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('ส่งถึง $okCount จาก ${devices.length} เครื่อง'),
          key: const ValueKey('np-test-summary'),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (sub.isNotEmpty) Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final (i, d) in devices.indexed)
          Builder(builder: (context) {
            final st = notifTestResultStyle(d['result']?.toString());
            final platform = notifPlatformLabel(d['platform']?.toString());
            final name = '${d['device_name'] ?? ''}'.trim();
            final hint = '${d['token_hint'] ?? ''}'.trim();
            final detail = '${d['detail'] ?? ''}'.trim();
            final pIcon = '${d['platform']}'.startsWith('web') ? NxI.globe : NxI.deviceMobile;
            return Container(
              key: ValueKey('np-test-device-$i'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: st.color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: st.color.withValues(alpha: 0.25)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(pIcon, color: cs.onSurfaceVariant, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      name.isNotEmpty ? name : (platform.isEmpty ? tr('เครื่องที่ลงทะเบียน') : platform),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [if (name.isNotEmpty && platform.isNotEmpty) platform, if (hint.isNotEmpty && hint != 'null') hint].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (detail.isNotEmpty && detail != 'null')
                      Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: st.color)),
                  ]),
                ),
                const SizedBox(width: 8),
                // Status at most ~40% of the row: long labels wrap instead of overflowing.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(st.icon, size: 16, color: st.color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(tr(st.label), maxLines: 2, textAlign: TextAlign.end, style: theme.textTheme.labelMedium?.copyWith(color: st.color, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ]),
            );
          }),
        if (devices.any((d) => d['result'] == 'invalid' || d['result'] == 'invalid_removed'))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('เครื่องที่ใช้ไม่ได้แล้ว (ถอนแอป / ล้างข้อมูล) ระบบลบออกให้เอง'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    ),
  );
}

/// "จัดการการแจ้งเตือน": what the server sends (only the events the company
/// has on), grouped, each with its description, how often it fires and a
/// switch per channel it offers — มือถือ (push), กระดิ่ง (in-app, web + app),
/// เบราว์เซอร์ (Web Push). Locked events show a lock and cannot change.
/// Per-group all on / off, a global "pause push", the phone's own permission
/// and a "send a test to this phone" button. Changes save on their own
/// (debounced `PUT` of only the changed events), optimistic with rollback.
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
  bool _testing = false;

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

  /// Channel keys in the server's order (มือถือ, กระดิ่ง, เบราว์เซอร์).
  List<String> get _channelKeys {
    final c = _data?['channels'];
    final keys = [
      if (c is List)
        for (final x in c)
          if (x is Map && x['key'] != null) '${x['key']}',
    ];
    return keys.isEmpty ? const ['push', 'in_app'] : keys;
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
    return tr(notifChannelStyle(key).label);
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

  /// All unlocked events of a group on (or off) in every channel they offer.
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

  Future<void> _sendTest() async {
    if (_testing) return;
    HapticFeedback.selectionClick();
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    String text;
    Map<String, dynamic>? result;
    try {
      result = await _api.sendTestNotification();
      text = tr(notifTestResultText(result));
    } catch (e) {
      text = isMissingEndpoint(e) ? tr('ระบบของพื้นที่ทำงานนี้ยังส่งทดสอบไม่ได้ — ต้องอัปเดตก่อน') : tr('ส่งทดสอบไม่สำเร็จ · ${formatApiError(e)}');
    }
    if (!mounted) return;
    setState(() => _testing = false);
    // New servers: what happened on each of my devices.
    if (result != null && notifTestDevices(result).isNotEmpty) {
      await showNotifTestResultSheet(context, result);
      return;
    }
    messenger?.showSnackBar(SnackBar(key: const ValueKey('np-test-result'), content: Text(text)));
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
      // Settings groups: caption, tiles with a tinted icon square, two lines and a switch.
      children.add(const NxSkeletonSettings(key: ValueKey('notif-prefs-skeleton'), groups: [2, 4, 3], padded: false));
    } else {
      final channels = _channelKeys;
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
              _ChannelLegend(channels: [for (final c in channels) (key: c, label: _channelLabel(c))]),
            ],
          ),
        ),
      );
      for (final g in (_data!['groups'] as List? ?? const [])) {
        if (g is! Map) continue;
        final events = [
          for (final e in (g['events'] as List? ?? const []))
            if (e is Map) NotifEvent(Map<String, dynamic>.from(e)),
        ];
        // The company turned every event of this group off: no header either.
        if (events.isEmpty) continue;
        final open = events.where((e) => !e.locked).toList();
        final allOn = open.isNotEmpty && open.every((e) => channels.where(e.offers).every((c) => _values[e.key]?[c] == true));
        final gk = '${g['key']}';
        children.add(
          SettingsAppear(
            index: i++,
            child: SettingsGroup(
              key: ValueKey('np-group-$gk'),
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
                for (final e in events)
                  _EventRow(
                    event: e,
                    channels: [
                      for (final c in channels)
                        if (e.offers(c)) (key: c, label: _channelLabel(c)),
                    ],
                    values: _values[e.key] ?? const {},
                    pushPaused: _paused,
                    onChanged: (c, v) => _set(e.key, c, v),
                  ),
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
    final compact = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    return Container(
      key: const ValueKey('np-device'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (allowed != true)
                      OutlinedButton.icon(
                        key: const ValueKey('np-open-settings'),
                        style: compact,
                        onPressed: () async {
                          await (widget.openSettings ?? _defaultOpenSettings)();
                          await _checkPermission();
                        },
                        icon: const Icon(NxI.gear, size: 16),
                        label: Text(tr('เปิดในการตั้งค่าเครื่อง')),
                      ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('np-test'),
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                      onPressed: _testing ? null : _sendTest,
                      icon: _testing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.paperPlaneTilt, size: 16),
                      label: Text(tr('ส่งทดสอบมาที่เครื่องนี้')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Channel = ({String key, String label});

/// What each channel means, once, above the groups.
class _ChannelLegend extends StatelessWidget {
  const _ChannelLegend({required this.channels});
  final List<_Channel> channels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      key: const ValueKey('np-legend'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      // One chip per channel; a chip wraps its own text rather than overflow.
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.maxWidth,
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final c in channels)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(notifChannelStyle(c.key).icon, size: 15, color: notifChannelStyle(c.key).color),
                          ),
                        ),
                        TextSpan(
                          text: c.label,
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' ${tr(notifChannelStyle(c.key).hint)}',
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.channels, required this.values, required this.pushPaused, required this.onChanged});
  final NotifEvent event;

  /// Only the channels this event offers.
  final List<_Channel> channels;
  final Map<String, bool> values;
  final bool pushPaused;
  final void Function(String channel, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final desc = event.description;
    final freq = event.frequency;
    final locked = event.locked;
    return Padding(
      key: ValueKey('np-event-${event.key}'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event.label,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: locked ? cs.onSurfaceVariant : null),
                ),
              ),
              if (locked) _LockBadge(key: ValueKey('np-locked-${event.key}'), byCompany: event.companyDefault != null),
            ],
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
              ),
            ),
          if (freq.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                key: ValueKey('np-freq-${event.key}'),
                children: [
                  Icon(NxI.clock, size: 13, color: cs.primary.withValues(alpha: 0.85)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      freq,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (channels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < channels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ChannelSwitch(
                      eventKey: event.key,
                      channel: channels[i],
                      value: values[channels[i].key] ?? false,
                      dimmed: channels[i].key == 'push' && pushPaused && !locked,
                      onChanged: locked ? null : (v) => onChanged(channels[i].key, v),
                    ),
                  ),
                ],
                // Keep cells the same width when an event offers fewer channels.
                for (var i = channels.length; i < 3; i++) ...[const SizedBox(width: 8), const Expanded(child: SizedBox())],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({super.key, required this.byCompany});
  final bool byCompany;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tr(byCompany ? 'บริษัทกำหนดไว้ เปลี่ยนไม่ได้' : 'ตั้งโดยระบบ เปลี่ยนไม่ได้'),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(NxI.lock, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              tr(byCompany ? 'บริษัทกำหนด' : 'ระบบกำหนด'),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// One channel of one event: icon + name over its switch, the whole cell
/// tappable, tinted in the channel's colour while on.
class _ChannelSwitch extends StatelessWidget {
  const _ChannelSwitch({required this.eventKey, required this.channel, required this.value, required this.dimmed, required this.onChanged});
  final String eventKey;
  final _Channel channel;
  final bool value;
  final bool dimmed;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = notifChannelStyle(channel.key);
    final on = value && onChanged != null;
    final dark = theme.brightness == Brightness.dark;
    final fill = on ? style.color.withValues(alpha: dark ? 0.2 : 0.1) : cs.surface.withValues(alpha: dark ? 0.35 : 0.7);
    return Opacity(
      opacity: dimmed ? 0.55 : (onChanged == null ? 0.7 : 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? style.color.withValues(alpha: 0.45) : cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(style.icon, size: 14, color: on ? style.color : cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        channel.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: on ? cs.onSurface : cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 36,
                  child: FittedBox(
                    child: Switch(key: ValueKey('np-$eventKey-${channel.key}'), value: value, activeTrackColor: style.color, onChanged: onChanged),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
