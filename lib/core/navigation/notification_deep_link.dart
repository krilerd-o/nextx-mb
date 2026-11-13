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

  if ((path.contains('chat') || path.contains('camp') || path.contains('community-chat')) &&
      linkId != null &&
      linkId.isNotEmpty) {
    return AppRoutes.chatRoom(linkId);
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

String? notificationDeepLinkFromData(Map<String, dynamic> data) {
  final url = data['url']?.toString() ?? data['link_path']?.toString() ?? '';
  final id = data['link_id']?.toString() ?? data['id']?.toString();
  if (url.isEmpty && (id == null || id.isEmpty)) return AppRoutes.notifications;
  return notificationDeepLink(url, linkId: id, extra: data['extra']?.toString() ?? data['link_extra']?.toString());
}
