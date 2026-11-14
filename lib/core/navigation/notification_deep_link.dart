import '../entity_modules.dart';
import 'app_routes.dart';

const _workspaceReserved = {
  'reports',
  'jira-integration',
  'all-space',
  'table',
  'boards',
  'item',
};

class WorkspaceItemSlug {
  const WorkspaceItemSlug({required this.boardCode, required this.itemNo});
  final String boardCode;
  final int itemNo;

  String get value => '$boardCode-$itemNo';
}

/// `/workspace/NSMO-250` — รหัสงานเต็มหน้า ไม่ใช่ id บอร์ดตัวเลข
WorkspaceItemSlug? parseWorkspaceItemSlug(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  try {
    s = Uri.decodeComponent(s);
  } catch (_) {}
  final m = RegExp(r'^(.+)-(\d+)$').firstMatch(s);
  if (m == null) return null;
  final code = m.group(1)!.trim();
  final n = int.tryParse(m.group(2)!);
  if (code.isEmpty || n == null || n < 1) return null;
  if (RegExp(r'^\d+$').hasMatch(code)) return null;
  if (_workspaceReserved.contains(code.toLowerCase())) return null;
  return WorkspaceItemSlug(boardCode: code.toUpperCase(), itemNo: n);
}

bool isWorkspaceReservedSegment(String seg) =>
    _workspaceReserved.contains(seg.trim().toLowerCase());

Uri? _asUri(String path) {
  final raw = path.trim();
  if (raw.isEmpty) return null;
  return Uri.tryParse(raw.startsWith('/') ? 'http://local.nx$raw' : raw);
}

/// Maps a NEXTX notification `link_path` / FCM `url` to a go_router location.
/// Record tab a notification should open on (from `link_extra` / meta kind).
String? notificationTab(String? extra) {
  final e = (extra ?? '').toLowerCase();
  if (e.isEmpty) return null;
  if (e.startsWith('quotation_approv') || e == 'quotation_rejected') return 'approval';
  if (e.startsWith('quotation_customer') || e.startsWith('job_') || e == 'job_from_quotation') return 'summary';
  if (e == 'comment_mention') return 'comments';
  return null;
}

/// `?tab=comments&comment=<id>` for links to a record comment (web `section=comments&comment=`).
String _commentQuery(Uri? uri) {
  if (uri == null) return '';
  final section = uri.queryParameters['section'] ?? uri.queryParameters['tab'];
  final comment = uri.queryParameters['comment'];
  final hasComment = comment != null && comment.isNotEmpty;
  if (section != 'comments' && !hasComment) return '';
  return '?tab=comments${hasComment ? '&comment=${Uri.encodeQueryComponent(comment)}' : ''}';
}

String notificationDeepLink(String path, {String? linkId, String? extra}) {
  final link = _notificationDeepLink(path, linkId: linkId, extra: extra);
  final tab = notificationTab(extra);
  if (tab == null || !(link.startsWith('/crm/') || link.startsWith('/fsm/')) || link.contains('?')) return link;
  return '$link?tab=$tab';
}

/// `/comm-ai/history?call=<id>` → that call's summary screen; `?summary=<id>` → that chat summary.
/// Null when the link has neither (the history list itself).
String? commAiHistoryRedirect(Uri uri) {
  final call = uri.queryParameters['call'];
  if (call != null && call.isNotEmpty) return AppRoutes.commAiCall(call);
  final summary = uri.queryParameters['summary'];
  if (summary != null && summary.isNotEmpty) return AppRoutes.commAiSummary(summary);
  return null;
}

/// Web notebook link → native: `/ai/notebook/<id>?recording_id=<rid>&note_id=<nid>` → `/notebook/<id>?recording=…&note=…`.
String notebookWebRedirect(String id, Map<String, String> q) {
  final rid = q['recording_id'] ?? q['recording'];
  final nid = q['note_id'] ?? q['note'];
  final out = <String, String>{
    if (rid != null && rid.isNotEmpty) 'recording': rid,
    if (nid != null && nid.isNotEmpty) 'note': nid,
  };
  final base = AppRoutes.notebookOf(id);
  return out.isEmpty ? base : '$base?${Uri(queryParameters: out).query}';
}

String _notificationDeepLink(String path, {String? linkId, String? extra}) {
  final uri = _asUri(path);
  final segs = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
  final open = uri?.queryParameters['open'];

  // "ISAAC สรุปการโทรเสร็จแล้ว" (type ai, link_extra comm_ai_call): open the call summary.
  if (segs.isNotEmpty && segs.first == 'comm-ai' && uri != null) {
    final direct = commAiHistoryRedirect(uri);
    if (direct != null) return direct;
    if ((extra ?? '').toLowerCase() == 'comm_ai_call' && linkId != null && linkId.isNotEmpty) return AppRoutes.commAiCall(linkId);
    if (segs.length >= 2 && segs[1] == 'history') return AppRoutes.commAi;
    return uri.path;
  }
  if ((extra ?? '').toLowerCase() == 'comm_ai_call' && linkId != null && linkId.isNotEmpty) return AppRoutes.commAiCall(linkId);

  // Notebook links from the web: /ai/notebook[/<id>] → the native notebook (public links stay on the web).
  if (segs.length >= 2 && segs[0] == 'ai' && segs[1] == 'notebook') {
    // "ไอแซคสรุปบันทึกเสียงเสร็จแล้ว": ?recording_id=<rid> (or link_extra notebook_recording + link_id) opens its summary.
    if (segs.length >= 3 && segs[2] != 'public') {
      final q = {...?uri?.queryParameters};
      // NEXTX sends link_id = notebook id, link_extra = recording id (older drafts: extra 'notebook_recording' + link_id).
      final ex = (extra ?? '').trim();
      if (RegExp(r'^\d+$').hasMatch(ex)) q['recording_id'] ??= ex;
      if (ex.toLowerCase() == 'notebook_recording' && linkId != null && linkId.isNotEmpty && linkId != segs[2]) q['recording_id'] ??= linkId;
      return notebookWebRedirect(segs[2], q);
    }
    if (segs.length == 2) return AppRoutes.notebook;
  }
  if (segs.isNotEmpty && segs.first == 'notebook') return uri!.path;

  if (segs.length >= 3 && segs.first == 'modules') {
    // The web's quotation / job form pages: /modules/<m>/new[?from=|?revise=], /modules/<m>/<id>/edit.
    final module = EntityModules.normalize(segs[1]);
    if (module == 'quotation' || module == 'job') {
      final q = uri?.queryParameters ?? const <String, String>{};
      if (segs[2] == 'new') {
        final from = q['from'], revise = q['revise'];
        if (revise != null && revise.isNotEmpty && module == 'quotation') return AppRoutes.docForm(module, mode: 'revise', id: revise);
        if (from != null && from.isNotEmpty) return AppRoutes.docForm(module, mode: 'duplicate', id: from);
        return AppRoutes.docForm(module);
      }
      if (segs.length >= 4 && segs[3] == 'edit') return AppRoutes.docForm(module, mode: 'edit', id: segs[2]);
    }
  }
  if (segs.length >= 2 && segs.first == 'modules') {
    final module = EntityModules.normalize(segs[1]);
    String? id;
    if (segs.length >= 4 && segs[2] == 'view') {
      id = segs[3];
    } else if (segs.length >= 3 && segs[2] != 'view') {
      id = segs[2];
    }
    id ??= (open != null && open.isNotEmpty) ? open : linkId;
    final q = _commentQuery(uri);
    if (module == 'activity' && q.isNotEmpty && id != null && id.isNotEmpty) return '${AppRoutes.activity(id)}$q';
    if (EntityModules.isFsm(module)) {
      if (id != null && id.isNotEmpty) return '${AppRoutes.fsmRecord(module, id)}$q';
      return AppRoutes.fsmModule(module);
    }
    if (id != null && id.isNotEmpty) return '${AppRoutes.crmRecord(module, id)}$q';
    return AppRoutes.crmModule(module);
  }

  if (segs.isNotEmpty && segs.first == 'calendar') {
    final id = segs.length >= 2 ? segs[1] : (open ?? linkId);
    if (id != null && id.isNotEmpty) return '${AppRoutes.activity(id)}${_commentQuery(uri)}';
    return AppRoutes.calendar;
  }

  if (segs.isNotEmpty && segs.first == 'workspace') {
    if (segs.length >= 3 && segs[1] == 'boards' && int.tryParse(segs[2]) != null) {
      return AppRoutes.board(segs[2]);
    }
    if (segs.length >= 3 && segs[1] == 'item') {
      return AppRoutes.workspaceHome;
    }
    if (segs.length >= 2 && segs[1] == 'all-space') {
      if (segs.length >= 3) {
        final slug = parseWorkspaceItemSlug(segs[2]);
        if (slug != null) return AppRoutes.board(slug.value);
      }
      return AppRoutes.workspaceHome;
    }
    if (segs.length >= 3 && !isWorkspaceReservedSegment(segs[1])) {
      final nested = parseWorkspaceItemSlug(segs[2]);
      if (nested != null) return AppRoutes.board(nested.value);
      return AppRoutes.task(segs[1], segs[2]);
    }
    if (segs.length >= 2) {
      final slug = parseWorkspaceItemSlug(segs[1]);
      if (slug != null) return AppRoutes.board(slug.value);
      if (!isWorkspaceReservedSegment(segs[1])) return AppRoutes.board(segs[1]);
    }
    return AppRoutes.workspaceHome;
  }

  // HR: the web's leave pages (approver: /hr/leave-management, requester: /hr/leave).
  if (segs.isNotEmpty && segs.first == 'hr') {
    final id = (open != null && open.isNotEmpty) ? open : linkId;
    if (segs.length >= 2 && segs[1] == 'leave-management') return AppRoutes.leave(tab: 'approve', id: id);
    if (segs.length >= 2 && segs[1] == 'leave') return AppRoutes.leave(tab: 'mine', id: id);
    if (segs.length >= 2 && segs[1] == 'attendance-report') return AppRoutes.attendanceReport;
    return AppRoutes.attendance;
  }

  // Announcements (company / system broadcasts): the reader screen.
  if (segs.isNotEmpty && segs.first == 'announcements') {
    if (segs.length >= 2) return AppRoutes.announcement(segs[1]);
    return AppRoutes.notifications;
  }

  // Web pages without a screen of their own in the app.
  if (segs.isNotEmpty) {
    switch (segs.first) {
      case 'commercial-store':
        return AppRoutes.commerce;
      case 'mailbox':
        return AppRoutes.mail;
      case 'approvals':
        return AppRoutes.approvals;
      case 'call-log':
        return uri == null ? AppRoutes.callLog : '${AppRoutes.callLog}${uri.hasQuery ? '?${uri.query}' : ''}';
      case 'analytics-reports':
      case 'customize-reports':
        return AppRoutes.notifications;
      case 'settings':
        if (segs.length >= 2 && segs[1] == 'comm-ai') return AppRoutes.commAiSettings;
        if (segs.length >= 2 && segs[1] == 'lead-scoring') return AppRoutes.crmModule('lead');
        if (segs.length >= 2 && (segs[1] == 'mail' || segs[1] == 'mailbox')) return AppRoutes.mail;
        return AppRoutes.notifications;
      case 'ai':
        // AI Agent job results open in the Assistant (same conversation id).
        if (segs.length >= 2 && segs[1] == 'agent') return uri!.hasQuery ? '${AppRoutes.aiChat}?${uri.query}' : AppRoutes.aiChat;
    }
  } else if (path.trim() == '/') {
    return AppRoutes.notifications;
  }

  // Chat: the `room` of the url first (it is always the room), then the record id.
  final room = uri?.queryParameters['room'];
  final chatId = (room != null && room.isNotEmpty) ? room : linkId;
  if ((path.contains('chat') || path.contains('camp') || path.contains('community-chat')) &&
      chatId != null &&
      chatId.isNotEmpty) {
    return AppRoutes.chatRoom(chatId);
  }
  if (path.contains('hr')) return AppRoutes.attendance;
  if (path.contains('chat') || path.contains('camp') || path.contains('community-chat')) {
    return AppRoutes.chatHome;
  }
  if (path.startsWith('/crm/') ||
      path.startsWith('/fsm/') ||
      path.startsWith('/calendar/') ||
      path.startsWith('/jobs/') ||
      path.startsWith('/workspace/') ||
      path.startsWith('/chat/')) {
    return uri == null ? path : '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
  }
  if (path.startsWith('/')) return path;
  return AppRoutes.notifications;
}

/// `/announcements/<id>` → that announcement's id, else null.
String? announcementIdOf(String? url) {
  final uri = _asUri(url ?? '');
  if (uri == null || (uri.hasScheme && uri.host != 'local.nx')) return null;
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length >= 2 && segs.first == 'announcements') return segs[1];
  return null;
}

/// Events whose notification is a message to read (no record page).
const _readerEvents = {'announcement', 'app_update', 'system_notice'};

/// Where an event that has no record page of its own opens (push `event`).
/// Null → follow the notification's `url`. Announcements open their reader
/// (`url` = `/announcements/<id>`), otherwise the notification itself.
String? notificationEventRoute(String? event, {String? id, String? notificationId, String? url}) {
  final e = (event ?? '').trim();
  switch (e) {
    case 'leave_request':
      return AppRoutes.leave(tab: 'approve', id: id);
    case 'leave_result':
      return AppRoutes.leave(tab: 'mine', id: id);
  }
  if (_readerEvents.contains(e)) {
    final ann = announcementIdOf(url);
    if (ann != null) return AppRoutes.announcement(ann, notificationId: notificationId);
    return AppRoutes.notificationsOf(notificationId);
  }
  return null;
}

/// Route of one row of `GET /api/notifications` (bell tray / center). A row
/// without a record page (announcement, system notice) opens itself in the
/// notification center.
String notificationItemRoute(Map<String, dynamic> item) {
  final meta = item['meta'];
  final extra = item['link_extra']?.toString() ?? (meta is Map ? meta['kind']?.toString() : null);
  final event = item['event']?.toString() ?? (meta is Map ? meta['event']?.toString() : null);
  final path = item['link_path']?.toString() ?? '';
  final linkId = item['link_id']?.toString();
  final id = item['id']?.toString();
  final ann = announcementIdOf(path);
  if (ann != null) return AppRoutes.announcement(ann, notificationId: id);
  if (path.trim().isEmpty || path.trim() == '/') {
    final byEvent = notificationEventRoute(event, id: linkId, notificationId: id);
    if (byEvent != null) return byEvent;
    if (linkId == null || linkId.isEmpty) return AppRoutes.notificationsOf(id);
  }
  final route = notificationDeepLink(path, linkId: linkId, extra: extra);
  return route == AppRoutes.notifications ? AppRoutes.notificationsOf(id) : route;
}

/// Record id of a push (`data`, all strings): `link_id`, else `id`.
/// Servers since round 2 send `id` = the record (link_id) and
/// `notification_id` = the bell row; round-1 servers sent the bell row id in
/// both, which is no record id — then there is none (null).
String? pushRecordId(Map<String, dynamic> data) {
  String? s(String k) {
    final v = data[k]?.toString().trim();
    return (v == null || v.isEmpty || v == 'null') ? null : v;
  }

  final link = s('link_id');
  if (link != null) return link;
  final id = s('id');
  if (id != null && id == s('notification_id')) return null;
  return id;
}

/// Chat room a push is about (`?room=` of its url, else its record id), or null.
String? pushChatRoom(Map<String, dynamic> data) {
  final url = '${data['url'] ?? data['link_path'] ?? ''}';
  final room = _asUri(url)?.queryParameters['room']?.trim();
  if (room != null && room.isNotEmpty) return room;
  final event = '${data['event'] ?? ''}';
  if (event.startsWith('chat_') || url.contains('chat') || url.contains('camp')) return pushRecordId(data);
  return null;
}

String? notificationDeepLinkFromData(Map<String, dynamic> data) {
  String? s(String k) {
    final v = data[k]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final url = s('url') ?? s('link_path') ?? '';
  final id = pushRecordId(data);
  final event = s('event');
  final byEvent = notificationEventRoute(event, id: id, notificationId: s('notification_id'), url: url);
  // Leave events carry the leave id; the web's /hr/leave* url maps the same way.
  if (byEvent != null && (url.isEmpty || _readerEvents.contains(event) || url == '/')) return byEvent;
  final ann = announcementIdOf(url);
  if (ann != null) return AppRoutes.announcement(ann, notificationId: s('notification_id'));
  if (url.isEmpty && id == null) return byEvent ?? AppRoutes.notificationsOf(s('notification_id'));
  final route = notificationDeepLink(url, linkId: id, extra: s('extra') ?? s('link_extra'));
  // No screen for it in the app (e.g. a report on the web): open the notification itself.
  return route == AppRoutes.notifications ? AppRoutes.notificationsOf(s('notification_id')) : route;
}
