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
String notificationDeepLink(String path, {String? linkId}) {
  final uri = _asUri(path);
  final segs = uri?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
  final open = uri?.queryParameters['open'];

  if (segs.length >= 2 && segs.first == 'modules') {
    final module = EntityModules.normalize(segs[1]);
    String? id;
    if (segs.length >= 4 && segs[2] == 'view') {
      id = segs[3];
    } else if (segs.length >= 3 && segs[2] != 'view') {
      id = segs[2];
    }
    id ??= (open != null && open.isNotEmpty) ? open : linkId;
    if (EntityModules.isFsm(module)) {
      if (id != null && id.isNotEmpty) return AppRoutes.fsmRecord(module, id);
      return AppRoutes.fsmModule(module);
    }
    if (id != null && id.isNotEmpty) return AppRoutes.crmRecord(module, id);
    return AppRoutes.crmModule(module);
  }

  if (segs.isNotEmpty && segs.first == 'calendar') {
    final id = segs.length >= 2 ? segs[1] : (open ?? linkId);
    if (id != null && id.isNotEmpty) return AppRoutes.activity(id);
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
  return notificationDeepLink(url, linkId: id);
}
