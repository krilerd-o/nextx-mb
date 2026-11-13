import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/ai_assistant.dart';
import '../../core/notebook/notebook_models.dart';
import '../../screens/ai/assistant/ai_assistant_controller.dart' show aiErrorText;
import '../api_client.dart';

/// Friendly text + whether the feature is off, for any notebook error.
({String text, bool disabled, String? code}) notebookError(Object e) {
  final code = e is ApiEnvelopeException ? e.errorCode : null;
  final disabled = code != null && isNotebookDisabledCode(code);
  if (code != null && code.toUpperCase() == 'AI_NOTEBOOK_DISABLED') {
    return (text: 'ผู้ดูแลปิดสมุดโน้ต AI ของธุรกิจนี้ไว้', disabled: true, code: code);
  }
  if (disabled) return (text: 'ธุรกิจนี้ยังไม่ได้เปิดใช้ AI', disabled: true, code: code);
  return (text: aiErrorText(e), disabled: false, code: code);
}

bool _isNotFound(Object e) =>
    (e is ApiException && e.statusCode == 404) || (e is ApiEnvelopeException && (e.statusCode == 404 || e.errorCode == 'NOT_MOCKED'));

// ------------------------------------------------------------------ library

class NotebookLibraryController extends ChangeNotifier {
  NotebookLibraryController(this.api, {this.meId});

  final ApiClient api;
  final String? meId;

  List<Notebook> items = [];
  bool loading = false;
  bool loaded = false;
  String? error;
  bool disabled = false;
  NotebookScope scope = NotebookScope.all;
  String query = '';
  bool grid = true;
  bool _disposed = false;

  List<Notebook> get visible => filterNotebooks(items, scope: scope, query: query, meId: meId);

  int countFor(NotebookScope s) => s == NotebookScope.all ? items.length : items.where((n) => notebookScopeOf(n, meId) == s).length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    loading = true;
    _notify();
    try {
      final rows = await api.getNotebooks();
      items = [for (final r in rows) Notebook.fromJson(r)];
      error = null;
      disabled = false;
    } catch (e) {
      final err = notebookError(e);
      error = err.text;
      disabled = err.disabled;
    } finally {
      loading = false;
      loaded = true;
      _notify();
    }
  }

  void setScope(NotebookScope s) {
    scope = s;
    _notify();
  }

  void setQuery(String q) {
    query = q;
    _notify();
  }

  void toggleGrid() {
    grid = !grid;
    _notify();
  }

  Future<Notebook> create({required String title, String description = '', String visibility = 'private'}) async {
    final m = await api.createNotebook(title: title.trim().isEmpty ? 'สมุดโน้ตใหม่' : title.trim(), description: description.trim(), visibility: visibility);
    final nb = Notebook.fromJson({'user_id': meId, 'source_count': 0, ...m});
    items = [nb, ...items.where((x) => x.id != nb.id)];
    _notify();
    return nb;
  }

  Future<void> update(Notebook n, {String? title, String? description, String? visibility}) async {
    final m = await api.updateNotebook(n.id, {'title': ?title, 'description': ?description, 'visibility': ?visibility});
    final fresh = Notebook.fromJson({'user_id': n.userId, 'source_count': n.sourceCount, 'enabled_source_count': n.enabledSourceCount, ...m});
    items = [for (final x in items) x.id == n.id ? fresh : x];
    _notify();
  }

  Future<void> delete(Notebook n) async {
    await api.deleteNotebook(n.id);
    items = items.where((x) => x.id != n.id).toList();
    _notify();
  }
}

// ----------------------------------------------------------------- notebook

/// A file being uploaded as a source (progress bar in the sources list).
class NotebookUpload {
  NotebookUpload(this.name, {this.kind = 'file'});
  final String name;
  final String kind;
  double progress = 0;
  String? error;
  bool get failed => error != null;
}

/// A studio output being made (sync call or a polled background job).
class StudioRun {
  StudioRun(this.kind);
  final StudioKind kind;
  String phase = '';
  String? error;
}

class NotebookController extends ChangeNotifier {
  NotebookController(this.api, this.id);

  final ApiClient api;
  final String id;

  /// Time between background-job polls (tests shorten it).
  static Duration pollEvery = const Duration(milliseconds: 1500);
  static int pollMax = 120;

  Notebook? notebook;
  bool loading = false;
  String? error;
  bool disabled = false;
  bool _disposed = false;

  List<NotebookSource> get sources => notebook?.sources ?? const [];
  List<NotebookNote> get notes => notebook?.notes ?? const [];
  List<NotebookSource> get enabledSources => sources.where((s) => s.enabled).toList();
  bool get canWrite => notebook?.canWrite ?? true;
  bool get allEnabled => sources.isNotEmpty && sources.every((s) => s.enabled);

  final List<NotebookUpload> uploads = [];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }

  void _sortSources() {
    final list = notebook?.sources;
    if (list == null) return;
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final c = a.$2.sortOrder.compareTo(b.$2.sortOrder);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    notebook!.sources = [for (final e in indexed) e.$2];
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      _notify();
    }
    try {
      final fresh = Notebook.fromJson(await api.getNotebook(id));
      notebook = notebook == null ? fresh : notebook!.merge(fresh);
      _sortSources();
      error = null;
      disabled = false;
    } catch (e) {
      final err = notebookError(e);
      error = err.text;
      disabled = err.disabled;
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Loads the notebook, then its chat and guide.
  Future<void> init() async {
    await load();
    if (notebook == null) return;
    await Future.wait([loadChat(), loadGuide()]);
  }

  // ── notebook

  Future<void> rename(String title, {String? description}) async {
    final nb = notebook;
    if (nb == null || title.trim().isEmpty) return;
    final m = await api.updateNotebook(id, {'title': title.trim(), 'description': ?description});
    notebook = nb.merge(Notebook.fromJson({'user_id': nb.userId, ...m}));
    _sortSources();
    _notify();
  }

  // ── sources

  Future<void> toggleSource(NotebookSource s, bool enabled) async {
    final was = s.enabled;
    s.enabled = enabled;
    _notify();
    try {
      await api.updateNotebookSource(id, s.id, {'enabled': enabled});
      _guideStale = true;
    } catch (e) {
      s.enabled = was;
      error = notebookError(e).text;
      _notify();
    }
  }

  Future<void> selectAll(bool enabled) async {
    final list = sources;
    if (list.isEmpty) return;
    final before = {for (final s in list) s.id: s.enabled};
    for (final s in list) {
      s.enabled = enabled;
    }
    _notify();
    try {
      await api.selectNotebookSources(id, [for (final s in list) s.id], enabled: enabled);
      _guideStale = true;
    } catch (e) {
      for (final s in list) {
        s.enabled = before[s.id] ?? s.enabled;
      }
      error = notebookError(e).text;
      _notify();
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final nb = notebook;
    if (nb == null) return;
    final ids = reorderedIds(sources, oldIndex, newIndex);
    final byId = {for (final s in sources) s.id: s};
    final before = sources;
    nb.sources = [for (final (i, sid) in ids.indexed) byId[sid]!..sortOrder = i];
    _notify();
    try {
      await api.reorderNotebookSources(id, ids);
    } catch (e) {
      nb.sources = before;
      error = notebookError(e).text;
      _notify();
    }
  }

  void _addSources(List<Map<String, dynamic>> rows) {
    final nb = notebook;
    if (nb == null) return;
    final added = [for (final r in rows) NotebookSource.fromJson(r)];
    final ids = {for (final s in added) s.id};
    nb.sources = [...sources.where((s) => !ids.contains(s.id)), ...added];
    _guideStale = true;
    _notify();
  }

  Future<void> addText({required String title, required String content}) async {
    final rows = await api.addNotebookSource(id, {'source_kind': 'manual', 'title': title.trim().isEmpty ? 'ข้อความ' : title.trim(), 'content': content.trim()});
    _addSources(rows);
  }

  /// Web page or YouTube link (YouTube goes as `url` for now).
  Future<void> addUrl(String url, {bool youtube = false}) async {
    final rows = await api.addNotebookSource(id, {
      'source_kind': 'url',
      'url': url,
      'title': url,
      if (youtube) 'source_config': {'url': url, 'provider': 'youtube'},
    });
    _addSources(rows);
  }

  Future<void> addKnowledge(List<String> knowledgeIds) async {
    if (knowledgeIds.isEmpty) return;
    final rows = await api.addNotebookSource(id, {'source_kind': 'library', 'knowledge_ids': apiIds(knowledgeIds)});
    _addSources(rows);
  }

  /// Upload → `/ai/attachments` (text extracted / transcribed there) → file source.
  /// Progress shows in [uploads]; returns false when it failed.
  Future<bool> addFile(MultipartFile Function() file, {required String name, String kind = 'file'}) async {
    final up = NotebookUpload(name, kind: kind);
    uploads.add(up);
    _notify();
    try {
      final att = await api.uploadAiAttachment(
        file(),
        conversationId: notebook?.conversationId,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          up.progress = (sent / total).clamp(0, 1).toDouble();
          _notify();
        },
      );
      up.progress = 1;
      _notify();
      final text = '${att['extracted_text'] ?? ''}'.trim().isNotEmpty ? '${att['extracted_text']}' : '${att['transcript'] ?? ''}';
      final rows = await api.addNotebookSource(id, {
        'source_kind': 'file',
        'title': '${att['name'] ?? att['original_name'] ?? name}',
        if (text.trim().isNotEmpty) 'content': text,
        'source_config': {
          'attachment_id': att['id'],
          'extract_status': ?att['extract_status'],
          'extract_error': ?att['extract_error'],
          'mime': ?att['mime'],
          'kind': ?att['kind'],
        },
      });
      _addSources(rows);
      uploads.remove(up);
      _notify();
      return true;
    } catch (e) {
      up.error = notebookError(e).text;
      _notify();
      return false;
    }
  }

  void dismissUpload(NotebookUpload up) {
    uploads.remove(up);
    _notify();
  }

  Future<void> renameSource(NotebookSource s, String title) async {
    if (title.trim().isEmpty) return;
    final m = await api.updateNotebookSource(id, s.id, {'title': title.trim()});
    _replaceSource(s, m);
  }

  Future<void> refreshSource(NotebookSource s) async {
    final m = await api.refreshNotebookSource(id, s.id);
    _replaceSource(s, m);
    _guideStale = true;
  }

  void _replaceSource(NotebookSource s, Map<String, dynamic> m) {
    final nb = notebook;
    if (nb == null || m['id'] == null) return;
    final fresh = NotebookSource.fromJson(m);
    nb.sources = [for (final x in sources) x.id == s.id ? fresh : x];
    _notify();
  }

  Future<void> deleteSource(NotebookSource s) async {
    await api.deleteNotebookSource(id, s.id);
    notebook?.sources = sources.where((x) => x.id != s.id).toList();
    _guideStale = true;
    _notify();
  }

  NotebookSource? sourceById(String? sid) => sid == null ? null : sources.where((s) => s.id == sid).firstOrNull;

  // ── guide

  NotebookGuide? guide;
  bool guideLoading = false;
  bool _guideStale = false;
  bool get guideStale => _guideStale || (guide?.stale ?? false);

  /// Guide in the app language (the server caches per locale).
  String guideLocale = 'th';

  /// Last refresh error (quota, provider not set up …); null when fine.
  String? guideError;

  Future<void> loadGuide() async {
    guideLoading = true;
    _notify();
    try {
      final g = NotebookGuide.fromJson(await api.getNotebookGuide(id, locale: guideLocale));
      // Canned / empty answers: keep the server summary, add fixed questions.
      guide = g.questions.isEmpty ? NotebookGuide(summary: g.summary, topics: g.topics, questions: NotebookGuide.fallbackFor(sources).questions, generatedAt: g.generatedAt, stale: g.stale) : g;
      _guideStale = false;
    } catch (e) {
      // Older servers have no guide (404); AI errors too: fixed suggestions instead.
      guide = NotebookGuide.fallbackFor(sources);
      if (!_isNotFound(e)) guideError = notebookError(e).text;
    } finally {
      guideLoading = false;
      _notify();
    }
  }

  Future<void> refreshGuide() async {
    if (guide?.fallback == true && guideError == null) {
      guide = NotebookGuide.fallbackFor(sources);
      _guideStale = false;
      _notify();
      return;
    }
    guideLoading = true;
    guideError = null;
    _notify();
    try {
      final g = NotebookGuide.fromJson(await api.refreshNotebookGuide(id, locale: guideLocale));
      guide = g.questions.isEmpty ? NotebookGuide(summary: g.summary, topics: g.topics, questions: NotebookGuide.fallbackFor(sources).questions, generatedAt: g.generatedAt, stale: g.stale) : g;
      _guideStale = false;
    } catch (e) {
      if (_isNotFound(e)) {
        guide = NotebookGuide.fallbackFor(sources);
      } else {
        guideError = notebookError(e).text;
      }
    } finally {
      guideLoading = false;
      _notify();
    }
  }

  // ── chat

  List<AiMessage> messages = [];
  bool chatLoading = false;
  bool sending = false;
  AiStreamEvent? status;
  String? chatError;
  CancelToken? _cancel;

  /// Server message id of an assistant reply (for "save as note").
  final Map<AiMessage, String> _savedIds = {};

  /// Replies already saved as notes this session.
  final Set<AiMessage> savedAsNote = {};

  Future<void> loadChat() async {
    final conv = notebook?.conversationId;
    if (conv == null) return;
    chatLoading = true;
    _notify();
    try {
      final c = await api.getAiConversation(conv);
      messages = [
        for (final m in (c['messages'] is List ? c['messages'] as List : const []))
          if (m is Map) AiMessage.fromJson(Map<String, dynamic>.from(m)),
      ];
    } catch (_) {
      // A missing conversation is re-created on the next question.
    } finally {
      chatLoading = false;
      _notify();
    }
  }

  /// Notebook chats live in a `mode: notebook` conversation linked on the notebook (web provider 1303-1331).
  Future<String> _ensureConversation() async {
    final nb = notebook!;
    final existing = nb.conversationId;
    if (existing != null) return existing;
    final c = await api.createAiConversation({'title': nb.title.isEmpty ? 'Notebook' : nb.title, 'mode': 'notebook'});
    final convId = '${c['id']}';
    nb.conversationId = convId;
    try {
      await api.updateNotebook(id, {'conversation_id': int.tryParse(convId) ?? convId});
    } catch (_) {
      // Linking is best-effort, like the web.
    }
    return convId;
  }

  Map<String, dynamic> _chatBody(String convId, List<Map<String, dynamic>> history) => {
        ...aiChatBody(history: history, conversationId: convId, injectContext: true),
        'notebook_id': int.tryParse(id) ?? id,
        'source_ids': apiIds([for (final s in enabledSources) s.id]),
      };

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || sending || notebook == null) return;
    chatError = null;
    final user = AiMessage(role: 'user', content: q);
    final prior = List<AiMessage>.from(messages);
    messages = [...messages, user];
    _notify();
    try {
      final convId = await _ensureConversation();
      unawaited(api.appendAiMessage(convId, user.toSaveJson()).then((_) {}, onError: (_) {}));
      await _stream(convId, aiHistoryForApi([...prior, user]));
    } catch (e) {
      _chatFail(e);
    }
  }

  Future<void> _stream(String convId, List<Map<String, dynamic>> history) async {
    sending = true;
    status = const AiStreamEvent('status', {'phase': 'thinking'});
    final reply = AiMessage(role: 'assistant', streaming: true);
    messages = [...messages, reply];
    _notify();
    final cancel = _cancel = CancelToken();
    Map<String, dynamic>? done;
    ApiEnvelopeException? streamError;
    try {
      await for (final ev in api.streamAiChat(_chatBody(convId, history), cancel: cancel)) {
        switch (ev.type) {
          case 'token':
            reply.content += ev.token;
          case 'done':
            done = ev.data;
          case 'error':
            streamError ??= ApiEnvelopeException(500, '${ev.data['error_code'] ?? 'AI_ERROR'}', '${ev.data['message'] ?? 'AI ตอบไม่สำเร็จ'}');
          default:
            status = ev;
        }
        _notify();
      }
      if (cancel.isCancelled) return;
      if (streamError != null) throw streamError;
      final d = done ?? const <String, dynamic>{};
      final msg = d['message'] is Map ? Map<String, dynamic>.from(d['message'] as Map) : const <String, dynamic>{};
      final apiContent = '${msg['content'] ?? ''}';
      if (apiContent.trim().isNotEmpty) reply.content = apiContent;
      final cites = d['citations'] is List ? d['citations'] : msg['citations'];
      reply.citations = cites is List ? [for (final c in cites) if (c is Map) Map<String, dynamic>.from(c)] : const [];
      reply.downloads = aiDownloadsFromToolResults(d['toolResults']);
      reply.provider = d['provider']?.toString();
      reply.model = d['model']?.toString();
      reply.streaming = false;
      sending = false;
      status = null;
      _notify();
      try {
        final saved = await api.appendAiMessage(convId, reply.toSaveJson());
        final mid = (saved['message'] is Map ? (saved['message'] as Map)['id'] : saved['id'])?.toString();
        if (mid != null && mid.isNotEmpty) _savedIds[reply] = mid;
      } catch (_) {}
    } catch (e) {
      if (cancel.isCancelled) return;
      messages = messages.where((m) => m != reply || m.content.trim().isNotEmpty).toList();
      reply.streaming = false;
      _chatFail(e);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      sending = false;
      status = null;
      _notify();
    }
  }

  void _chatFail(Object e) {
    final err = notebookError(e);
    chatError = err.text;
    if (err.disabled) disabled = true;
    sending = false;
    _notify();
  }

  void clearChatError() {
    chatError = null;
    _notify();
  }

  void stop() {
    _cancel?.cancel();
    _cancel = null;
    messages = messages.where((m) => !(m.streaming && m.content.trim().isEmpty)).map((m) => m..streaming = false).toList();
    sending = false;
    status = null;
    _notify();
  }

  Future<void> regenerate() async {
    final conv = notebook?.conversationId;
    if (conv == null || sending) return;
    chatError = null;
    try {
      await api.regenerateAi(conv).catchError((_) => <String, dynamic>{});
      while (messages.isNotEmpty && !messages.last.isUser) {
        messages = messages.sublist(0, messages.length - 1);
      }
      _notify();
      await _stream(conv, aiHistoryForApi(messages));
    } catch (e) {
      _chatFail(e);
    }
  }

  /// The user question just before [reply].
  String questionFor(AiMessage reply) {
    final i = messages.indexOf(reply);
    for (var j = i - 1; j >= 0; j--) {
      if (messages[j].isUser) return messages[j].content;
    }
    return '';
  }

  /// "บันทึกเป็นโน้ต": the answer (with its citations) becomes a note.
  Future<NotebookNote> saveAsNote(AiMessage reply) async {
    final q = questionFor(reply).trim();
    final title = q.isEmpty ? 'คำตอบจากแชท' : (q.length > 60 ? '${q.substring(0, 60)}…' : q);
    final mid = _savedIds[reply] ?? reply.id;
    final m = await api.addNotebookNote(id, {
      'title': title,
      'content': reply.content,
      'artifact_kind': 'note',
      if (mid != null && int.tryParse(mid) != null) 'source_message_id': int.parse(mid),
      'meta': {
        'from': 'chat',
        if (q.isNotEmpty) 'question': q,
        if (reply.citations.isNotEmpty) 'citations': reply.citations,
      },
    });
    final note = NotebookNote.fromJson(m);
    notebook?.notes = [note, ...notes.where((n) => n.id != note.id)];
    savedAsNote.add(reply);
    _notify();
    return note;
  }

  // ── notes

  Future<NotebookNote> addNote({String title = '', String content = '', String kind = 'note'}) async {
    final m = await api.addNotebookNote(id, {'title': title.trim().isEmpty ? 'โน้ตใหม่' : title.trim(), 'content': content, 'artifact_kind': kind});
    final note = NotebookNote.fromJson(m);
    notebook?.notes = [note, ...notes.where((n) => n.id != note.id)];
    _notify();
    return note;
  }

  Future<NotebookNote> updateNote(NotebookNote n, {String? title, String? content}) async {
    final m = await api.updateNotebookNote(id, n.id, {'title': ?title, 'content': ?content});
    final NotebookNote fresh;
    if (m['id'] == null) {
      if (title != null) n.title = title;
      if (content != null) n.content = content;
      fresh = n;
    } else {
      fresh = NotebookNote.fromJson(m);
    }
    notebook?.notes = [for (final x in notes) x.id == n.id ? fresh : x];
    _notify();
    return fresh;
  }

  Future<void> deleteNote(NotebookNote n) async {
    await api.deleteNotebookNote(id, n.id);
    notebook?.notes = notes.where((x) => x.id != n.id).toList();
    _notify();
  }

  // ── studio

  StudioRun? studioRun;
  bool? _jobsAvailable;

  Future<bool> _useJobs() async {
    if (_jobsAvailable != null) return _jobsAvailable!;
    try {
      final s = await api.getAiJobsStatus();
      _jobsAvailable = s['enabled'] == true && s['worker_seen_recently'] != false;
    } catch (_) {
      _jobsAvailable = false;
    }
    return _jobsAvailable!;
  }

  /// Makes a studio output from the enabled sources; returns the new note.
  Future<NotebookNote?> runStudio(StudioKind kind, {String? templateId, String locale = 'th'}) async {
    if (studioRun != null || notebook == null) return null;
    final run = studioRun = StudioRun(kind);
    _notify();
    try {
      final before = {for (final n in notes) n.id};
      final async = await _useJobs();
      final res = await api.runNotebookStudio(id, kind: kind.id, sourceIds: [for (final s in enabledSources) s.id], locale: locale, templateId: templateId, async: async);
      NotebookNote? note;
      if (res['queued'] == true && res['jobId'] != null) {
        run.phase = 'queued';
        _notify();
        await _pollJob('${res['jobId']}', run);
        await load(quiet: true);
        note = notes.where((n) => !before.contains(n.id)).firstOrNull ?? notes.firstOrNull;
      } else {
        final item = res['item'] is Map ? Map<String, dynamic>.from(res['item'] as Map) : res;
        if (item['id'] != null) {
          note = NotebookNote.fromJson(item);
          notebook?.notes = [note, ...notes.where((n) => n.id != note!.id)];
        } else {
          await load(quiet: true);
          note = notes.firstOrNull;
        }
      }
      studioRun = null;
      _notify();
      return note;
    } catch (e) {
      run.error = notebookError(e).text;
      studioRun = null;
      error = run.error;
      _notify();
      rethrow;
    }
  }

  Future<void> _pollJob(String jobId, StudioRun run) async {
    for (var i = 0; i < pollMax; i++) {
      if (_disposed) return;
      final job = await api.getAiJob(jobId);
      final state = '${job['state'] ?? ''}'.toLowerCase();
      final progress = job['progress'];
      final phase = progress is Map ? '${progress['phase'] ?? ''}'.toLowerCase() : '';
      run.phase = phase.isNotEmpty ? phase : state;
      _notify();
      if (state == 'completed' || phase == 'done') return;
      if (state == 'failed' || phase == 'failed' || phase == 'error') {
        throw ApiEnvelopeException(500, 'STUDIO_FAILED', '${job['failedReason'] ?? 'สร้างไม่สำเร็จ'}');
      }
      await Future<void>.delayed(pollEvery);
    }
    throw ApiEnvelopeException(504, 'STUDIO_TIMEOUT', 'ใช้เวลานานเกินไป — ลองใหม่อีกครั้ง');
  }

  /// Cached studio files (url → bytes) for this session.
  final Map<String, List<int>> _files = {};

  Future<List<int>> downloadExport(String url) async {
    final hit = _files[url];
    if (hit != null) return hit;
    final bytes = await api.downloadNotebookExport(url);
    _files[url] = bytes;
    return bytes;
  }
}
