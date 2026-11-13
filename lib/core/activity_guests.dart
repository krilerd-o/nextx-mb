import 'dart:convert';
import 'dart:math';

import 'i18n.dart';

/// Activity guests (`attendees` jsonb) — same shape as the NEXTX web
/// (`frontend/src/constants/activityGuests.js`) so both sides read each other:
/// `{id, kind: user|entity|email, user_id | module+entity_id | email, name, phone,
///   account_name, optional, response, isOrganizer}`.
const kGuestEntityModules = {'lead', 'contact', 'account', 'case'};

String _newGuestId() => 'g_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${Random().nextInt(1 << 30).toRadixString(36)}';

int? _pos(dynamic v) {
  final n = num.tryParse('${v ?? ''}');
  return n != null && n > 0 ? n.toInt() : null;
}

bool emailLooksValid(String? v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch((v ?? '').trim());

class ActivityGuest {
  ActivityGuest({
    String? id,
    required this.kind,
    this.userId,
    this.module,
    this.entityId,
    this.email = '',
    this.name = '',
    this.phone = '',
    this.accountName = '',
    this.optional = false,
    this.response = 'needsAction',
    this.isOrganizer = false,
  }) : id = id ?? _newGuestId();

  final String id;
  final String kind; // user | entity | email
  final int? userId;
  final String? module;
  final int? entityId;
  final String email;
  final String name;
  final String phone;
  final String accountName;
  final bool optional;
  final String response;
  final bool isOrganizer;

  /// Dedupe key (same as the web `guestKey`).
  String get key => switch (kind) {
        'user' => 'user:$userId',
        'entity' => 'entity:$module:$entityId',
        _ => 'email:${email.toLowerCase()}',
      };

  String get display => name.trim().isNotEmpty ? name.trim() : (email.isNotEmpty ? email : (kind == 'user' ? 'ผู้ใช้ #$userId' : '#$entityId'));

  ActivityGuest copyWith({bool? isOrganizer, String? name, String? email}) => ActivityGuest(
        id: id,
        kind: kind,
        userId: userId,
        module: module,
        entityId: entityId,
        email: email ?? this.email,
        name: name ?? this.name,
        phone: phone,
        accountName: accountName,
        optional: optional,
        response: response,
        isOrganizer: isOrganizer ?? this.isOrganizer,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        if (kind == 'user') 'user_id': userId,
        if (kind == 'entity') ...{'module': module, 'entity_id': entityId, 'account_name': accountName},
        'email': email,
        'name': name,
        'phone': phone,
        'optional': optional,
        'response': response,
        if (isOrganizer) 'isOrganizer': true,
      };

  /// Null for anything the web would also drop.
  static ActivityGuest? fromRaw(dynamic raw) {
    if (raw == null || raw == '') return null;
    if (raw is num || (raw is String && RegExp(r'^\d+$').hasMatch(raw.trim()))) {
      final uid = _pos(raw);
      return uid == null ? null : ActivityGuest(kind: 'user', userId: uid);
    }
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final uid = _pos(m['user_id'] ?? m['userId']);
    final module = '${m['module'] ?? m['related_module'] ?? ''}'.trim().toLowerCase();
    final eid = _pos(m['entity_id'] ?? m['related_id']);
    final email = '${m['email'] ?? m['email1'] ?? m['email_1st'] ?? ''}'.trim();
    var kind = '${m['kind'] ?? ''}'.trim().toLowerCase();
    if (kind.isEmpty) {
      if (uid != null && eid == null) {
        kind = 'user';
      } else if (kGuestEntityModules.contains(module) && eid != null) {
        kind = 'entity';
      } else if (emailLooksValid(email)) {
        kind = 'email';
      }
    }
    final rawId = '${m['id'] ?? ''}';
    final id = rawId.isNotEmpty && _pos(rawId) == null ? rawId : null;
    final name = '${m['name'] ?? m['display_name'] ?? m['_name'] ?? m['customer_name'] ?? ''}'.trim();
    final common = (
      name: name,
      phone: '${m['phone'] ?? m['mobile_1st'] ?? m['mobile'] ?? ''}'.trim(),
      optional: m['optional'] == true,
      response: '${m['response'] ?? 'needsAction'}',
      org: m['isOrganizer'] == true,
    );
    if (kind == 'user' && uid != null) {
      return ActivityGuest(id: id, kind: 'user', userId: uid, email: email, name: common.name, phone: common.phone, optional: common.optional, response: common.response, isOrganizer: common.org);
    }
    if (kind == 'entity' && kGuestEntityModules.contains(module) && eid != null) {
      return ActivityGuest(
        id: id,
        kind: 'entity',
        module: module,
        entityId: eid,
        email: email,
        name: common.name,
        phone: common.phone,
        accountName: '${m['account_name'] ?? m['company_name'] ?? ''}'.trim(),
        optional: common.optional,
        response: common.response,
        isOrganizer: common.org,
      );
    }
    if (emailLooksValid(email)) {
      return ActivityGuest(id: id, kind: 'email', email: email.toLowerCase(), name: common.name, phone: common.phone, optional: common.optional, response: common.response, isOrganizer: common.org);
    }
    return null;
  }
}

/// `attendees` as stored (list, JSON string, or "1,2,3") → unique guests.
List<ActivityGuest> parseActivityGuests(dynamic raw) {
  List<dynamic> list = const [];
  if (raw is List) {
    list = raw;
  } else if (raw is String && raw.trim().isNotEmpty) {
    try {
      final v = jsonDecode(raw);
      if (v is List) list = v;
    } catch (_) {
      list = raw.split(RegExp(r'[,;\s]+')).where((e) => e.isNotEmpty).toList();
    }
  }
  final seen = <String>{};
  final out = <ActivityGuest>[];
  for (final e in list) {
    final g = ActivityGuest.fromRaw(e);
    if (g == null || !seen.add(g.key)) continue;
    out.add(g);
  }
  return out;
}

/// The owner is always the first guest and the organizer (web `ensureOwnerGuest`).
List<ActivityGuest> ensureOwnerGuest(List<ActivityGuest> guests, int? ownerId, {String ownerName = ''}) {
  final next = <ActivityGuest>[];
  var found = false;
  for (final g in guests) {
    if (ownerId != null && g.kind == 'user' && g.userId == ownerId) {
      found = true;
      next.add(g.copyWith(isOrganizer: true, name: g.name.isEmpty ? ownerName : null));
    } else {
      next.add(g.isOrganizer ? g.copyWith(isOrganizer: false) : g);
    }
  }
  if (ownerId != null && !found) next.insert(0, ActivityGuest(kind: 'user', userId: ownerId, name: ownerName, isOrganizer: true));
  return next;
}

/// The first customer guest becomes the activity's related record (web
/// `projectRelatedFromGuests`).
Map<String, dynamic> projectRelatedFromGuests(List<ActivityGuest> guests) {
  for (final g in guests) {
    if (g.kind == 'entity') {
      return {
        'related_module': g.module,
        'related_id': g.entityId,
        'customer_name': g.name.isEmpty ? null : g.name,
        'customer_mobile': g.phone.isEmpty ? null : g.phone,
        'customer_email': g.email.isEmpty ? null : g.email,
        'account_name': g.accountName.isEmpty ? null : g.accountName,
      };
    }
  }
  for (final g in guests) {
    if (g.kind == 'email') return {'customer_name': g.name.isEmpty ? null : g.name, 'customer_email': g.email};
  }
  return const {};
}

/// Web reminder presets (minutes; 0 = none).
const kReminderPresets = [0, 10, 30, 60, 1440];

String reminderLabel(int m) => switch (m) {
      0 => 'ไม่เตือน',
      1440 => '1 วันก่อน',
      60 => '1 ชม. ก่อน',
      _ => '$m นาทีก่อน',
    };

/// Activity types of the web (`activityTypeProfiles.js`).
const kActivityTypes = ['Visit', 'Call', 'Meeting', 'Task', 'Education', 'Personal'];

String activityTypeLabel(String t) => switch (t) {
      'Visit' => 'เข้าพบลูกค้า',
      'Call' => 'โทร',
      'Meeting' => 'ประชุม',
      'Task' => 'งาน',
      'Education' => 'อบรม',
      'Personal' => 'ส่วนตัว',
      _ => t,
    };

/// Activity statuses of the web (`ACTIVITY_STATUSES` in `calendarEventUtils.js`):
/// stored value → Thai / English label.
const kActivityStatuses = {
  'Planned': ('วางแผน', 'Planned'),
  'In Progress': ('กำลังดำเนินการ', 'In Progress'),
  'Completed': ('เสร็จสิ้น', 'Completed'),
  'Cancelled': ('ยกเลิก', 'Cancelled'),
  // Older rows (vtiger style).
  'Held': ('เสร็จสิ้น', 'Held'),
  'Not Held': ('ไม่ได้จัด', 'Not held'),
  'Not Started': ('ยังไม่เริ่ม', 'Not started'),
};

/// Label of an activity status in the current language (`In Progress` →
/// `กำลังดำเนินการ`); unknown values pass through.
String activityStatusLabel(String s) {
  final hit = kActivityStatuses[s] ??
      kActivityStatuses.entries.where((e) => e.key.toLowerCase() == s.trim().toLowerCase()).map((e) => e.value).firstOrNull;
  if (hit == null) return s;
  return L10n.isEn ? hit.$2 : hit.$1;
}

/// Which guest kind to suggest first for a type (web `defaultGuestMode`).
String defaultGuestMode(String type) => switch (type) {
      'Visit' => 'lead',
      'Call' => 'contact',
      _ => 'user',
    };
