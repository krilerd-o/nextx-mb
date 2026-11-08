import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../services/api_client.dart';
import '../../../services/birthday_reminders.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_overlay_panel.dart';
import 'cal_model.dart';

/// Birthday pink, used for every birthday mark on the calendar.
const calBirthdayColor = Color(0xFFEC4899);

/// A customer's birthday: a Lead, a Contact, or an Account's contact person.
class CalBirthday {
  const CalBirthday({
    required this.module,
    required this.id,
    required this.name,
    required this.born,
    this.org,
    this.phone,
    this.email,
    this.imageUrl,
    required this.row,
  });

  final String module; // lead | contact | account
  final String id;
  final String name;
  final DateTime born;
  final String? org; // company / account name
  final String? phone;
  final String? email;
  final String? imageUrl;
  final Map<String, dynamic> row;

  /// Which birthday field each module keeps, and the columns we need.
  static const fields = {
    'contact': 'birthdate',
    'lead': 'birthdate',
    'account': 'contact_person_birthdate',
  };
  static const cols = {
    'contact': 'id,contact_name,contact_titlename,contact_firstname,contact_lastname,nickname,birthdate,mobile_1st,email_1st,account_name_1st,company_name,image_url',
    'lead': 'id,lead_name,lead_titlename,lead_firstname,lead_lastname,birthdate,mobile_1st,email_1st,company_name,position_name,image_url',
    'account': 'id,account_name,contact_name_1st,contact_person_title,contact_person_birthdate,contact_mobile_1st,mobile_1st,email_1st,image_url',
  };

  static String? _s(dynamic v) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty || t == 'null' ? null : t;
  }

  static CalBirthday? from(String module, Map<String, dynamic> r) {
    final born = parseThaiDate(r[fields[module]]);
    final id = _s(r['id']);
    if (born == null || id == null) return null;
    String? name;
    String? org;
    switch (module) {
      case 'contact':
        name = _s(r['contact_name']) ?? [_s(r['contact_firstname']), _s(r['contact_lastname'])].whereType<String>().join(' ');
        final nick = _s(r['nickname']);
        if (nick != null && name.isNotEmpty) name = '$name ($nick)';
        org = _s(r['account_name_1st']) ?? _s(r['company_name']);
      case 'lead':
        name = _s(r['lead_name']) ?? [_s(r['lead_firstname']), _s(r['lead_lastname'])].whereType<String>().join(' ');
        org = _s(r['company_name']);
      case 'account':
        // The birthday belongs to the account's contact person.
        name = _s(r['contact_name_1st']) ?? _s(r['account_name']);
        org = _s(r['account_name']);
    }
    return CalBirthday(
      module: module,
      id: id,
      name: (name == null || name.isEmpty) ? tr('(ไม่มีชื่อ)') : name,
      born: born,
      org: org == name ? null : org,
      phone: module == 'account' ? (_s(r['contact_mobile_1st']) ?? _s(r['mobile_1st'])) : _s(r['mobile_1st']),
      email: _s(r['email_1st']),
      imageUrl: _s(r['image_url']),
      row: r,
    );
  }

  /// Record type as the CRM names it.
  String get typeLabel => switch (module) {
        'lead' => 'Lead',
        'contact' => 'Contact',
        _ => 'Account',
      };

  /// One colour per type (also on the badge).
  Color get typeColor => switch (module) {
        'lead' => const Color(0xFFF59E0B),
        'contact' => const Color(0xFF3B82F6),
        _ => const Color(0xFF10B981),
      };

  String get kindLabel => switch (module) {
        'lead' => tr('ลูกค้าเป้าหมาย'),
        'contact' => tr('ผู้ติดต่อ'),
        _ => tr('ผู้ติดต่อของบัญชี'),
      };

  /// The birthday in [year]; 29 Feb falls on 28 Feb in other years.
  DateTime inYear(int year) {
    final leap = DateTime(year, 2, 29).month == 2;
    if (born.month == 2 && born.day == 29 && !leap) return DateTime(year, 2, 28);
    return DateTime(year, born.month, born.day);
  }

  bool on(DateTime day) => sameDay(inYear(day.year), day);

  /// Age reached on the birthday in [year] (null when the year is unknown/odd).
  int? ageIn(int year) {
    final a = year - born.year;
    return born.year < 1900 || a <= 0 || a > 120 ? null : a;
  }
}

/// All birthdays the user can see (Lead / Contact / Account), loaded once.
///
/// NEXTX has no "birthday on this day-of-year" filter, so this asks the list
/// API for records that *have* a birthday (a date range covering every year,
/// the same Quick-Filter period the web uses) and works out the days here.
/// Pages of 500, up to [maxPerModule] per module; modules the user may not
/// read are skipped quietly.
class CalBirthdays extends ChangeNotifier {
  CalBirthdays(this._api, {this.scope});
  final ApiClient _api;

  /// Server + user prefs scope: when set, reminders are rescheduled on load.
  final String? scope;

  /// Shared between Home and the calendar for a while (same API client).
  /// Keyed by server + business: another business never sees these.
  static final Map<String, (DateTime, List<CalBirthday>)> _cache = {};

  String get _cacheKey => '${_api.baseUrl}|${_api.businessId}';
  static const cacheFor = Duration(minutes: 30);

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static const maxPerModule = 5000;

  List<CalBirthday> _all = const [];
  final Map<String, List<CalBirthday>> _byMonthDay = {};
  bool loaded = false;
  bool _loading = false;
  bool enabled = true;

  List<CalBirthday> get all => _all;

  /// Loads finish after the screen may be gone (e.g. business switched).
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> load({bool force = false}) async {
    if (_loading || (loaded && !force)) return;
    _loading = true;
    final hit = _cache[_cacheKey];
    final List<CalBirthday> out;
    if (!force && hit != null && DateTime.now().difference(hit.$1) < cacheFor) {
      out = hit.$2;
    } else {
      out = <CalBirthday>[];
      await Future.wait([
        for (final m in CalBirthday.fields.keys) _loadModule(m, out),
      ]);
      out.sort((a, b) => a.name.compareTo(b.name));
      _cache[_cacheKey] = (DateTime.now(), out);
      if (scope != null) BirthdayReminders.instance.sync(out, scope: scope!);
    }
    _all = out;
    _byMonthDay.clear();
    for (final b in out) {
      _byMonthDay.putIfAbsent('${b.born.month}-${b.born.day}', () => []).add(b);
    }
    loaded = true;
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadModule(String module, List<CalBirthday> out) async {
    for (var page = 1; page * 500 <= maxPerModule; page++) {
      try {
        final res = await _api.getEntityList(module, limit: 500, page: page, extra: {
          'cols': CalBirthday.cols[module]!,
          'period_field': CalBirthday.fields[module]!,
          'period_preset': 'custom',
          'period_start': '1800-01-01',
          'period_end': '2200-12-31',
        });
        for (final r in res.items) {
          final b = CalBirthday.from(module, r);
          if (b != null) out.add(b);
        }
        if (res.items.length < 500) return;
      } catch (_) {
        return; // no permission / module off: no birthdays from it
      }
    }
  }

  /// Birthdays falling on [day] (empty while switched off).
  List<CalBirthday> on(DateTime day) {
    if (!enabled) return const [];
    final l = [...?_byMonthDay['${day.month}-${day.day}']];
    // 29 Feb people celebrate on 28 Feb in a common year.
    if (day.month == 2 && day.day == 28 && DateTime(day.year, 2, 29).month != 2) l.addAll(_byMonthDay['2-29'] ?? const []);
    return l;
  }

  void setEnabled(bool v) {
    if (enabled == v) return;
    enabled = v;
    notifyListeners();
  }
}

/// Pink cake badge / avatar used in lists.
class CalBirthdayAvatar extends StatelessWidget {
  const CalBirthdayAvatar({super.key, required this.b, this.size = 40});
  final CalBirthday b;
  final double size;

  @override
  Widget build(BuildContext context) {
    // First letter of the name, skipping tags such as "[QA]".
    final clean = b.name.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    final first = clean.characters.where((c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c)).firstOrNull;
    final initials = (first ?? '?').toUpperCase();
    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size + 4,
          height: size + 4,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFFF472B6), Color(0xFFFB923C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: CircleAvatar(
            backgroundColor: const Color(0xFFFCE7F3),
            foregroundImage: b.imageUrl != null && b.imageUrl!.startsWith('http') ? NetworkImage(b.imageUrl!) : null,
            child: Text(initials, style: TextStyle(color: calBirthdayColor, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
          ),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
            child: Icon(NxI.cakeFill, size: size * 0.32, color: calBirthdayColor),
          ),
        ),
      ]),
    );
  }
}

/// "Lead" / "Contact" / "Account" pill in the type's colour.
class CalBirthdayTypeBadge extends StatelessWidget {
  const CalBirthdayTypeBadge({super.key, required this.b, this.large = false});
  final CalBirthday b;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('cal-bday-type-${b.module}-${b.id}'),
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 6, vertical: large ? 2 : 1),
      decoration: BoxDecoration(
        color: b.typeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: b.typeColor.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        b.typeLabel,
        style: TextStyle(fontSize: large ? 11 : 10, height: 1.2, fontWeight: FontWeight.w800, color: Color.lerp(b.typeColor, Colors.black, 0.3)),
      ),
    );
  }
}

/// "ครบ 36 ปี · วันนี้" style line for [b] on [day].
String calBirthdayLine(CalBirthday b, DateTime day) {
  final age = b.ageIn(day.year);
  final today = calDay(thaiNow());
  final at = calDay(b.inYear(day.year));
  final diff = at.difference(today).inDays;
  final when = diff == 0
      ? tr('วันนี้')
      : diff == 1
          ? tr('พรุ่งนี้')
          : diff > 1
              ? tr('อีก $diff วัน')
              : tr('ผ่านมา ${-diff} วัน');
  return [if (age != null) tr('ครบ $age ปี'), when].join(' · ');
}

/// One row: avatar, name, kind · company, age.
class CalBirthdayTile extends StatelessWidget {
  const CalBirthdayTile({super.key, required this.b, required this.day, required this.onTap});
  final CalBirthday b;
  final DateTime day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      key: ValueKey('cal-bday-${b.module}-${b.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(children: [
          CalBirthdayAvatar(b: b, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                CalBirthdayTypeBadge(b: b),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [if (b.module == 'account') b.kindLabel, ?b.org].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              calBirthdayLine(b, day),
              maxLines: 2,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(color: calBirthdayColor, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Floating birthday card: who it is, which record, the date and age, how to
/// reach them, and quick actions (call, email, open record, plan a greeting).
Future<void> showCalBirthdayCard(
  BuildContext context, {
  required CalBirthday b,
  required DateTime day,
  required VoidCallback onOpenRecord,
  required VoidCallback onPlanGreeting,
  Rect? anchor,
}) {
  return showNxBlurPanel<void>(
    context: context,
    anchor: anchor,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final age = b.ageIn(day.year);
      final bornLabel = b.born.year < 1900
          ? '${b.born.day} ${monthShort(b.born.month)}'
          : '${b.born.day} ${monthShort(b.born.month)} ${uiYear(b.born.year)}';
      final isToday = sameDay(calDay(thaiNow()), calDay(b.inYear(day.year)));
      Widget info(IconData icon, String label, String value, {VoidCallback? onTap}) => InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(children: [
                Icon(icon, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                SizedBox(width: 58, child: Text(tr(label), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                Expanded(
                  child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: onTap != null ? cs.primary : null, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          );
      Widget action(IconData icon, String label, VoidCallback? onTap, {Key? key}) => Expanded(
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(14),
              onTap: onTap == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      onTap();
                    },
              child: Opacity(
                opacity: onTap == null ? 0.35 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: calBirthdayColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(icon, size: 20, color: calBirthdayColor),
                    ),
                    const SizedBox(height: 4),
                    Text(tr(label), style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
                  ]),
                ),
              ),
            ),
          );
      return Column(
        key: const ValueKey('cal-bday-card'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header on a soft pink wash.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [calBirthdayColor.withValues(alpha: 0.16), const Color(0xFFFB923C).withValues(alpha: 0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(children: [
              CalBirthdayAvatar(b: b, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(isToday ? NxI.partyPopper : NxI.cake, size: 15, color: calBirthdayColor),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        isToday ? tr('สุขสันต์วันเกิดวันนี้') : tr('วันเกิด'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(color: calBirthdayColor, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(b.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    CalBirthdayTypeBadge(b: b, large: true),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(20)),
                      child: Text(b.kindLabel, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (age != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: calBirthdayColor, borderRadius: BorderRadius.circular(20)),
                        child: Text(tr('ครบ $age ปี'), style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          info(NxI.cake, 'วันเกิด', '$bornLabel · ${calBirthdayLine(b, day).split(' · ').last}'),
          if (b.org != null) info(NxI.buildings, b.module == 'account' ? 'บัญชี' : 'บริษัท', b.org!),
          if (b.phone != null) info(NxI.phone, 'โทร', b.phone!, onTap: () => launchUrl(Uri(scheme: 'tel', path: b.phone))),
          if (b.email != null) info(NxI.envelope, 'อีเมล', b.email!, onTap: () => launchUrl(Uri(scheme: 'mailto', path: b.email))),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Row(children: [
              action(NxI.phone, 'โทร', b.phone == null ? null : () => launchUrl(Uri(scheme: 'tel', path: b.phone))),
              action(NxI.envelope, 'ส่งอีเมล', b.email == null ? null : () => launchUrl(Uri(scheme: 'mailto', path: b.email, queryParameters: {'subject': tr('สุขสันต์วันเกิด')}))),
              action(NxI.calendarPlus, 'นัดอวยพร', onPlanGreeting, key: const ValueKey('cal-bday-plan')),
              action(NxI.user, 'ดูข้อมูล', onOpenRecord, key: const ValueKey('cal-bday-open')),
            ]),
          ),
        ],
      );
    },
  );
}
