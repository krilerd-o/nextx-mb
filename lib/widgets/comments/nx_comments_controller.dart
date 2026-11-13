import 'dart:async';

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../services/api_client.dart';
import 'nx_comment_format.dart';

/// Where comments are read / written: a CRM record (`/api/entity/:module/:id/comments`)
/// or a workspace task / epic (`/api/boards/:b/(tasks|epics)/:id/comments`).
class NxCommentsApi {
  const NxCommentsApi({
    required this.post,
    required this.update,
    required this.upload,
    this.delete,
    this.like,
    this.mentionUsers,
    this.linkPreview,
    this.adminEditsAll = false,
  });

  /// Business owner / admin may edit and delete anyone's comment (records: yes; workspace: own only).
  final bool adminEditsAll;

  /// `body` is HTML (web format), `parentId` the comment replied to.
  final Future<Map<String, dynamic>> Function({required String body, required List<Map<String, dynamic>> attachments, Object? parentId}) post;
  final Future<void> Function(Object commentId, String body) update;

  /// Uploads one file → attachment maps (`{url, name, mime, size, file_id}`), reporting 0..1.
  final Future<List<Map<String, dynamic>>> Function(MultipartFile file, void Function(double progress) onProgress) upload;
  final Future<void> Function(Object commentId)? delete;

  /// Toggles my like → `{liked, like_count}` (workspace only — the web has no likes on records).
  final Future<Map<String, dynamic>> Function(Object commentId)? like;

  /// People who can be @mentioned (the web uses the business users list).
  final Future<List<Map<String, dynamic>>> Function()? mentionUsers;
  final Future<Map<String, dynamic>> Function(String url)? linkPreview;

  /// Record comments — same endpoints and payload as the web EntityDetailPane.
  factory NxCommentsApi.entity(ApiClient api, String module, String id) => NxCommentsApi(
        post: ({required body, required attachments, parentId}) =>
            api.postEntityComment(module, id, body, attachments: attachments, parentId: parentId),
        update: (cid, body) => api.updateEntityComment(module, id, cid, body),
        delete: (cid) => api.deleteEntityComment(module, id, cid),
        upload: (file, onProgress) => api.uploadCommentAttachments(
              [file],
              onSendProgress: (sent, total) => onProgress(total > 0 ? sent / total : 0),
            ),
        mentionUsers: () => api.getEntityMentionUsers(module, id),
        linkPreview: api.getLinkPreview,
        adminEditsAll: true,
      );

  /// Workspace task / epic comments (likes, delete, board attachments).
  factory NxCommentsApi.workspace(ApiClient api, String boardId, String kind, String id) => NxCommentsApi(
        post: ({required body, required attachments, parentId}) =>
            api.addItemComment(boardId, kind, id, body, parentId: parentId?.toString(), attachments: attachments),
        update: (cid, body) => api.updateItemComment(boardId, kind, id, '$cid', body),
        delete: (cid) => api.deleteItemComment(boardId, kind, id, '$cid'),
        like: (cid) => api.toggleItemCommentLike(boardId, kind, id, '$cid'),
        upload: (file, onProgress) => api.uploadBoardAttachments(
              boardId,
              [file],
              onSendProgress: (sent, total) => onProgress(total > 0 ? sent / total : 0),
            ),
        mentionUsers: api.getUsersCached,
        linkPreview: api.getLinkPreview,
      );
}

enum NxUploadStatus { uploading, done, failed }

/// A file in the composer tray: uploads as soon as it is picked; retry / remove.
class NxCommentUpload {
  NxCommentUpload({required this.name, required this.bytes, this.mime});
  final String name;
  final Uint8List bytes;
  final String? mime;
  double progress = 0;
  NxUploadStatus status = NxUploadStatus.uploading;
  List<Map<String, dynamic>> result = const [];
  String? error;

  bool get isImage {
    final m = (mime ?? '').toLowerCase();
    if (m.startsWith('image/')) return true;
    return RegExp(r'\.(png|jpe?g|gif|webp|heic|bmp)$', caseSensitive: false).hasMatch(name);
  }
}

/// Text field controller that paints picked @mentions as chips.
class NxMentionTextController extends TextEditingController {
  NxMentionTextController({super.text});

  /// Picked mentions: display name → user id.
  final Map<String, String> mentions = {};

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final names = mentions.keys.where((n) => text.contains('@$n')).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (names.isEmpty) return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    final cs = Theme.of(context).colorScheme;
    final chip = (style ?? const TextStyle()).copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w700,
      background: Paint()..color = cs.primary.withValues(alpha: 0.12),
    );
    final re = RegExp(names.map((n) => RegExp.escape('@$n')).join('|'));
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: chip));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: spans);
  }

  /// Loads stored HTML for editing (mentions kept as chips).
  void setHtml(String html) {
    final p = commentFromHtml(html);
    mentions
      ..clear()
      ..addAll(p.mentions);
    value = TextEditingValue(text: p.text, selection: TextSelection.collapsed(offset: p.text.length));
  }

  String toHtml() => commentToHtml(text, mentions: {
        for (final e in mentions.entries)
          if (text.contains('@${e.key}')) e.key: e.value,
      });

  void clearAll() {
    mentions.clear();
    clear();
  }

  /// The `@query` being typed at the caret.
  ({int start, String query})? get mentionQuery => selection.isValid && selection.isCollapsed ? mentionQueryAt(text, selection.baseOffset) : null;

  /// Puts `@Name ` in front of the draft (replying to someone's reply).
  void prependMention(Map<String, dynamic> user) {
    final name = mentionUserLabel(user).replaceAll(RegExp(r'[\[\]@]'), '').trim();
    if (name.isEmpty) return;
    mentions[name] = '${user['id']}';
    final next = '@$name ${text.trimLeft()}';
    value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: next.length));
  }

  /// Replaces the `@query` at the caret with `@Name ` and remembers the mention.
  void insertMention(Map<String, dynamic> user, {({int start, String query})? at}) {
    final name = mentionUserLabel(user).replaceAll(RegExp(r'[\[\]@]'), '').trim();
    final q = at ?? mentionQuery;
    final caret = selection.isValid ? selection.baseOffset : text.length;
    final start = q?.start ?? caret;
    final end = q == null ? caret : q.start + 1 + q.query.length;
    final insert = '@$name ';
    final next = text.replaceRange(start, end.clamp(start, text.length), insert);
    mentions[name] = '${user['id']}';
    value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + insert.length));
  }
}

/// State of a comments tab: composer draft, reply / edit target, upload tray,
/// mention suggestions, expanded threads and the highlighted comment.
class NxCommentsController extends ChangeNotifier {
  NxCommentsController({
    required this.api,
    required this.onChanged,
    this.meId,
    this.isAdmin = false,
    this.maxDepth = 5,
    this.keyPrefix = '',
  }) {
    text.addListener(_onText);
    focus.addListener(_notify);
  }

  NxCommentsApi api;

  /// Reload the comment list (after post / edit / delete).
  Future<void> Function() onChanged;
  String? meId;
  bool isAdmin;

  /// Max nesting (backend `MAX_COMMENT_DEPTH`).
  final int maxDepth;

  /// Widget keys: `'${keyPrefix}comment-input'` etc. (`ws-` on workspace).
  final String keyPrefix;

  final text = NxMentionTextController();
  final focus = FocusNode();
  Map<String, dynamic>? replyTo;
  final List<NxCommentUpload> uploads = [];
  bool sending = false;
  String? error;

  /// Threads whose replies are shown (`id` of the root).
  final Set<String> expanded = {};

  /// Briefly highlighted comment (deep link from a mention notification).
  String? highlightId;

  /// Link in the draft whose preview the user closed.
  final Set<String> dismissedPreviews = {};

  List<Map<String, dynamic>>? _users;
  bool _loadingUsers = false;
  bool _disposed = false;

  /// People matching an `@query` (loads the users list on first use).
  List<Map<String, dynamic>> mentionSuggestionsFor(String query) {
    final users = _users;
    if (users == null) {
      _loadUsers();
      return const [];
    }
    return filterMentionUsers(users, query, limit: 8);
  }

  bool get usersLoaded => _users != null;

  /// The @ button: types "@" at the caret (opens the people picker).
  void typeAt() {
    final t = text.text;
    final sel = text.selection;
    final at = sel.isValid ? sel.baseOffset.clamp(0, t.length) : t.length;
    final needSpace = at > 0 && !RegExp(r'\s').hasMatch(t[at - 1]);
    final ins = needSpace ? ' @' : '@';
    final next = t.replaceRange(at, sel.isValid ? sel.extentOffset.clamp(at, t.length) : at, ins);
    text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at + ins.length));
    focus.requestFocus();
    _loadUsers();
  }

  Future<List<Map<String, dynamic>>> users() async {
    await _loadUsers();
    return _users ?? const [];
  }

  Future<void> _loadUsers() async {
    if (_users != null || _loadingUsers || api.mentionUsers == null) return;
    _loadingUsers = true;
    try {
      _users = await api.mentionUsers!();
    } catch (_) {
      _users = const [];
    } finally {
      _loadingUsers = false;
      _notify();
    }
  }

  void _onText() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get hasUploading => uploads.any((u) => u.status == NxUploadStatus.uploading);
  bool get hasFailed => uploads.any((u) => u.status == NxUploadStatus.failed);
  bool get isEmpty => text.text.trim().isEmpty && !uploads.any((u) => u.status == NxUploadStatus.done);

  /// Send is allowed: something to send, nothing still uploading or failed.
  bool get canSend => !sending && !isEmpty && !hasUploading && !hasFailed;

  /// First link in the draft (for the preview card), unless dismissed.
  String? get draftLink {
    final urls = commentUrls(text.text);
    for (final u in urls) {
      if (!dismissedPreviews.contains(u)) return u;
    }
    return null;
  }

  bool isMine(Map<String, dynamic> c) => meId != null && meId!.isNotEmpty && '${c['user_id']}' == meId;
  bool canEdit(Map<String, dynamic> c) => isMine(c) || (isAdmin && api.adminEditsAll);
  bool canDelete(Map<String, dynamic> c) => api.delete != null && canEdit(c);

  void startReply(Map<String, dynamic> c) {
    replyTo = c;
    final root = c['_root']?.toString();
    if (root != null) expanded.add(root);
    // Replying to someone else's reply: mention them (the server threads under the root).
    final isReply = c['parent_id'] != null && '${c['parent_id']}' != 'null' && '${c['parent_id']}'.isNotEmpty;
    final author = '${c['user_name'] ?? ''}'.trim();
    if (isReply && author.isNotEmpty && !isMine(c) && c['user_id'] != null && !text.text.contains('@$author')) {
      text.prependMention({'id': c['user_id'], 'first_name': author});
    }
    focus.requestFocus();
    _notify();
  }

  void cancelReply() {
    replyTo = null;
    _notify();
  }

  void dismissPreview(String url) {
    dismissedPreviews.add(url);
    _notify();
  }

  void pickMention(Map<String, dynamic> user) {
    text.insertMention(user);
    _notify();
  }

  /// Adds picked files to the tray and uploads each one with progress.
  void addFiles(List<({String name, Uint8List bytes, String? mime})> files) {
    for (final f in files) {
      final u = NxCommentUpload(name: f.name, bytes: f.bytes, mime: f.mime);
      uploads.add(u);
      _upload(u);
    }
    _notify();
  }

  Future<void> _upload(NxCommentUpload u) async {
    u
      ..status = NxUploadStatus.uploading
      ..progress = 0
      ..error = null;
    _notify();
    try {
      final res = await api.upload(MultipartFile.fromBytes(u.bytes, filename: u.name), (p) {
        u.progress = p.clamp(0, 1).toDouble();
        _notify();
      });
      if (!uploads.contains(u)) return;
      if (res.isEmpty) throw StateError(tr('อัปโหลดไม่สำเร็จ'));
      u
        ..result = res
        ..progress = 1
        ..status = NxUploadStatus.done;
    } catch (e) {
      u
        ..status = NxUploadStatus.failed
        ..error = e is StateError ? e.message : formatApiError(e);
    }
    _notify();
  }

  void retry(NxCommentUpload u) => _upload(u);

  void remove(NxCommentUpload u) {
    uploads.remove(u);
    _notify();
  }

  List<Map<String, dynamic>> get readyAttachments => [
        for (final u in uploads)
          if (u.status == NxUploadStatus.done)
            for (final a in u.result) {...a, 'mime': a['mime'] ?? u.mime ?? 'application/octet-stream'},
      ];

  /// Posts the draft (reply when [replyTo] is set). Returns true when sent.
  Future<bool> send() async {
    if (!canSend) return false;
    sending = true;
    error = null;
    _notify();
    try {
      final body = text.text.trim().isEmpty ? '' : text.toHtml();
      final parent = replyTo;
      final res = await api.post(body: body, attachments: readyAttachments, parentId: parent?['id']);
      HapticFeedback.lightImpact();
      text.clearAll();
      uploads.clear();
      dismissedPreviews.clear();
      replyTo = null;
      final root = parent?['_root']?.toString() ?? parent?['id']?.toString();
      if (root != null) expanded.add(root);
      final newId = res['id']?.toString();
      if (newId != null && newId.isNotEmpty) flash(newId);
      await onChanged();
      return true;
    } catch (e) {
      error = formatApiError(e);
      return false;
    } finally {
      sending = false;
      _notify();
    }
  }

  /// Saves an edited comment (HTML).
  Future<bool> saveEdit(Map<String, dynamic> c, String html) async {
    try {
      await api.update(c['id'] as Object, html);
      await onChanged();
      return true;
    } catch (e) {
      error = formatApiError(e);
      _notify();
      return false;
    }
  }

  Future<bool> delete(Map<String, dynamic> c) async {
    final del = api.delete;
    if (del == null) return false;
    try {
      await del(c['id'] as Object);
      if ('${replyTo?['id']}' == '${c['id']}') replyTo = null;
      await onChanged();
      return true;
    } catch (e) {
      error = formatApiError(e);
      _notify();
      return false;
    }
  }

  Timer? _flashTimer;

  /// Highlights [id] for a few seconds (and keeps its thread open).
  void flash(String id, {Duration duration = const Duration(seconds: 3)}) {
    highlightId = id;
    _flashTimer?.cancel();
    _flashTimer = Timer(duration, () {
      highlightId = null;
      _notify();
    });
    _notify();
  }

  void toggleThread(String rootId) {
    expanded.contains(rootId) ? expanded.remove(rootId) : expanded.add(rootId);
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _flashTimer?.cancel();
    text.removeListener(_onText);
    focus.removeListener(_notify);
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}
