import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/i18n.dart';
import '../core/navigation/push_tap.dart';
import '../core/thai_time.dart';
import '../screens/calendar/cal/cal_birthdays.dart';
import '../screens/calendar/cal/cal_model.dart';

/// "Tomorrow is X's birthday" — a local notification at 09:00 Thai time the
/// day before, for every day with customer birthdays in the next 30 days
/// (one notification per day, listing everyone). Rescheduled whenever the
/// birthdays are loaded; nothing goes through the server.
///
/// If the app is opened after 09:00 and tomorrow has birthdays, it notifies
/// right away (once per day) so the reminder is never missed.
class BirthdayReminders {
  BirthdayReminders._();
  static final BirthdayReminders instance = BirthdayReminders._();

  static const _channelId = 'birthday_reminders';
  static const _idBase = 742000; // ids 742000…742030 belong to this feature
  static const days = 30;
  static const hour = 9;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static String _enabledKey(String scope) => 'nx_bday_remind_$scope';
  static const _sentKey = 'nx_bday_remind_sent';

  /// On by default; per server + user.
  static Future<bool> isEnabled(String scope) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_enabledKey(scope)) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(String scope, bool on, {List<CalBirthday>? birthdays}) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_enabledKey(scope), on);
    } catch (_) {}
    if (!on) {
      await instance.cancelAll();
    } else if (birthdays != null) {
      await instance.sync(birthdays, scope: scope);
    }
  }

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> _init() async {
    if (_ready) return true;
    if (!_supported) return false;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
      // Same plugin instance as push: keep the same tap → deep link handler.
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        // Push banners shown in the foreground carry their data as JSON.
        onDidReceiveNotificationResponse: (r) => handleNotificationPayload(r.payload),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            'วันเกิดลูกค้า',
            description: 'เตือนล่วงหน้า 1 วันก่อนวันเกิดลูกค้า',
            importance: Importance.defaultImportance,
          ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Days (birthday date → people) whose reminder falls in the next [days].
  @visibleForTesting
  static Map<DateTime, List<CalBirthday>> plan(List<CalBirthday> all, DateTime now) {
    final today = calDay(now);
    final out = <DateTime, List<CalBirthday>>{};
    for (var i = 1; i <= days; i++) {
      final d = today.add(Duration(days: i));
      for (final b in all) {
        if (b.on(d)) (out[d] ??= []).add(b);
      }
    }
    return out;
  }

  /// Title / body of the reminder for [people] born on [day].
  static (String, String) message(List<CalBirthday> people, DateTime day) {
    final title = people.length == 1
        ? tr('พรุ่งนี้วันเกิด ${people.first.name}')
        : tr('พรุ่งนี้วันเกิดลูกค้า ${people.length} คน');
    // No age in the reminder (not shown anywhere).
    String one(CalBirthday b) => [b.name, '(${b.typeLabel}${b.org == null ? '' : ' · ${b.org}'})'].join(' ');

    final body = people.length == 1
        ? [one(people.first), tr('แตะเพื่อดูในปฏิทิน')].join('\n')
        : people.take(5).map(one).join('\n') + (people.length > 5 ? '\n${tr('และอีก ${people.length - 5} คน')}' : '');
    return (title, body);
  }

  Future<void> cancelAll() async {
    if (!await _init()) return;
    for (var i = 0; i <= days; i++) {
      await _plugin.cancel(_idBase + i);
    }
  }

  /// Replace the scheduled reminders with ones for [all] (when enabled).
  Future<void> sync(List<CalBirthday> all, {required String scope}) async {
    if (!await isEnabled(scope)) return;
    if (!await _init()) return;
    await cancelAll();
    final now = thaiNow();
    final plan = BirthdayReminders.plan(all, now);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'วันเกิดลูกค้า',
        channelDescription: 'เตือนล่วงหน้า 1 วันก่อนวันเกิดลูกค้า',
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(),
    );
    final today = calDay(now);
    for (final e in plan.entries) {
      final day = e.key;
      final (title, body) = message(e.value, day);
      final offset = day.difference(today).inDays; // 1…30
      final remindAt = day.subtract(const Duration(days: 1)).add(const Duration(hours: hour));
      if (!remindAt.isAfter(now)) {
        // Tomorrow's birthdays and 09:00 already passed: tell now, once a day.
        await _notifyNowOnce(_idBase + offset, title, body, day, details);
        continue;
      }
      try {
        await _plugin.zonedSchedule(
          _idBase + offset,
          title,
          body,
          tz.TZDateTime(tz.local, remindAt.year, remindAt.month, remindAt.day, remindAt.hour),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: '/calendar',
        );
      } catch (_) {}
    }
  }

  Future<void> _notifyNowOnce(int id, String title, String body, DateTime day, NotificationDetails details) async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = calKey(day);
      if (p.getString(_sentKey) == key) return;
      await _plugin.show(id, title, body, details, payload: '/calendar');
      await p.setString(_sentKey, key);
    } catch (_) {}
  }
}
