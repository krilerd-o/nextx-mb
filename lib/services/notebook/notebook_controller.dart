import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/ai_assistant.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/notebook/notebook_recording.dart';
import '../../screens/ai/assistant/ai_assistant_controller.dart' show aiErrorText;
import '../api_client.dart';
import '../audio/recording_upload_queue.dart';
import '../realtime_service.dart';
import 'notebook_recorder.dart';

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
  NotebookLibraryController(this.api, {this.meId, this.prefsScope});

  final ApiClient api;
  final String? meId;

  /// `AppConfig.businessScope` (server + user + business): where picks are kept on the
  /// device for servers without `appearance`. Null = no device copy (tests).
  final String? prefsScope;

  List<Notebook> items = [];
  bool loading = false;
  bool loaded = false;
  String? error;
  bool disabled = false;
  NotebookScope scope = NotebookScope.all;
  String query = '';
  bool grid = true;
  bool _disposed = false;

  /// Scope + search, pinned first.
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
      final next = [for (final r in rows) Notebook.fromJson(r)];
      final scopeKey = prefsScope;
      if (scopeKey != null) {
        final local = await NotebookAppearanceStore.load(scopeKey);
        for (final n in next) {
          n.localAppearance = local[n.id];
        }
      }
      items = next;
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

  /// [appearance] defaults to the title's colour / icon so every new book looks different.
  Future<Notebook> create({required String title, String description = '', String visibility = 'private', NotebookAppearance? appearance}) async {
    final t = title.trim().isEmpty ? 'สมุดโน้ตใหม่' : title.trim();
    final look = appearance ?? NotebookAppearance.forTitle(t);
    final m = await api.createNotebook(title: t, description: description.trim(), visibility: visibility, appearance: look.toJson());
    final nb = Notebook.fromJson({'user_id': meId, 'source_count': 0, ...m});
    await keepNotebookAppearance(nb, look, prefsScope);
    items = [nb, ...items.where((x) => x.id != nb.id)];
    _notify();
    return nb;
  }

  Future<void> update(Notebook n, {String? title, String? description, String? visibility, NotebookAppearance? appearance}) async {
    final m = await api.updateNotebook(n.id, {'title': ?title, 'description': ?description, 'visibility': ?visibility, 'appearance': ?appearance?.toJson()});
    final fresh = n.merge(Notebook.fromJson({'user_id': n.userId, 'source_count': n.sourceCount, 'enabled_source_count': n.enabledSourceCount, ...m}));
    if (appearance != null) await keepNotebookAppearance(fresh, appearance, prefsScope);
    items = [for (final x in items) x.id == n.id ? fresh : x];
    _notify();
  }

  /// Colour / icon / cover / pin only.
  Future<void> setAppearance(Notebook n, NotebookAppearance look) => update(n, appearance: look);

  Future<void> togglePin(Notebook n) => setAppearance(n, n.look.copyWith(pinned: !n.pinned));

  Future<void> delete(Notebook n) async {
    await api.deleteNotebook(n.id);
    items = items.where((x) => x.id != n.id).toList();
    if (prefsScope != null) await NotebookAppearanceStore.save(prefsScope!, n.id, null);
    _notify();
  }
}

/// After a create / PATCH that sent [look]: a v6 server stored it (drop the device copy);
/// an older server ignored it, so keep it on the device for [scope] and show it.
Future<void> keepNotebookAppearance(Notebook nb, NotebookAppearance look, String? scope) async {
  if (nb.serverHasAppearance && nb.appearance != null) {
    nb.localAppearance = null;
    if (scope != null) await NotebookAppearanceStore.save(scope, nb.id, null);
    return;
  }
  nb.appearance = null;
  nb.localAppearance = look;
  if (scope != null) await NotebookAppearanceStore.save(scope, nb.id, look);
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
  NotebookController(this.api, this.id, {Stream<RealtimeEvent>? events, NotebookRecorder? recorder, RecordingUploadQueue? queue})
      : _events = events,
        _recorderOverride = recorder,
        _queueOverride = queue;

  final ApiClient api;
  final String id;
  final Stream<RealtimeEvent>? _events;
  final NotebookRecorder? _recorderOverride;
  final RecordingUploadQueue? _queueOverride;

  /// The app-wide recorder (one recording at a time).
  NotebookRecorder get recorder => _recorderOverride ?? NotebookRecorder.instance;
  RecordingUploadQueue get _queue => _queueOverride ?? RecordingUploadQueue.instance;

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
    _recPoll?.cancel();
    _rtSub?.cancel();
    _finSub?.cancel();
    _sentSub?.cancel();
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
    _wireRecordings();
    await load();
    if (notebook == null) return;
    await Future.wait([loadChat(), loadGuide(), loadRecordings()]);
  }

  // ── recordings (meetings recorded into this notebook)

  /// Recordings that are not a source yet: being uploaded / processed, failed, or live on another device.
  List<NotebookRecording> recordings = [];

  /// False on servers without notebook recordings (the record entry is hidden); null until known.
  bool? recordingsSupported;

  /// Time between status polls while a recording is processed (tests shorten it).
  static Duration recordingPollEvery = const Duration(seconds: 4);

  Timer? _recPoll;
  StreamSubscription<RealtimeEvent>? _rtSub;
  StreamSubscription<FinishedRecording>? _finSub;
  StreamSubscription<RecordingPart>? _sentSub;
  final Map<String, String> _csidOf = {}; // recording id (or local:<csid>) → client session id

  /// Summary notes made from recordings (recording id → note id), from GET / the ready event.
  final Map<String, String> recordingNotes = {};

  bool get canRecord => canWrite && recordingsSupported != false;

  /// The server answered 404 to a recording call: hide the record entry.
  void markRecordingsUnsupported() {
    recordingsSupported = false;
    _notify();
  }

  void _wireRecordings() {
    if (_rtSub != null) return;
    _rtSub = (_events ?? RealtimeService.instance.events).listen(_onRealtime);
    _finSub = recorder.finished.listen((f) {
      if (f.notebookId == id) trackFinished(f);
    });
    _sentSub = _queue.sent.listen((p) {
      if (p.target != RecordingTarget.notebook || p.notebookId != id) return;
      if (p.op == RecordingOp.create) {
        // Recorded offline: the recording exists on the server now.
        final local = 'local:${p.clientSessionId}';
        final i = recordings.indexWhere((r) => r.id == local);
        if (i >= 0) {
          final r = recordings[i];
          recordings[i] = NotebookRecording(id: p.recordingId, notebookId: id, title: r.title, status: r.status, durationMs: r.durationMs);
          _csidOf[p.recordingId] = p.clientSessionId;
          _notify();
        }
      }
      if (p.op == RecordingOp.stop) _schedulePoll(soon: true);
    });
  }

  void _onRealtime(RealtimeEvent e) {
    final d = e.data;
    if ('${d['notebook_id']}' != id) return;
    final rid = '${d['recording_id'] ?? ''}';
    switch (e.type) {
      case 'ai:notebook_recording_ready':
        if (d['note_id'] != null) recordingNotes[rid] = '${d['note_id']}';
        recordings = recordings.where((r) => r.id != rid).toList();
        _notify();
        unawaited(load(quiet: true));
      case 'ai:notebook_recording_status':
        final i = recordings.indexWhere((r) => r.id == rid);
        if (i >= 0) {
          recordings[i].status = RecordingStatus.of(d['status']);
          _notify();
          if (recordings[i].status == RecordingStatus.failed) unawaited(loadRecordings()); // with its error text
        } else {
          unawaited(loadRecordings());
        }
    }
  }

  Future<void> loadRecordings() async {
    try {
      final rows = await api.getNotebookRecordings(id);
      recordingsSupported = true;
      final fresh = [for (final r in rows) NotebookRecording.fromJson(r)];
      for (final r in fresh) {
        if (r.noteId != null) recordingNotes[r.id] = r.noteId!;
      }
      final local = recordings.where((r) => r.id.startsWith('local:') || (r.status.working && !fresh.any((x) => x.id == r.id))).toList();
      bool show(NotebookRecording r) {
        if (r.status == RecordingStatus.ready || (recorder.recordingId == r.id && recorder.active)) return false;
        if (!r.status.active) return true;
        // Live on another device: only fairly recent ones (an abandoned session stays "recording" on the server).
        final started = DateTime.tryParse(r.startedAt ?? '');
        return started != null && DateTime.now().difference(started).inHours < 12;
      }

      recordings = [...local, ...fresh.where(show)];
    } catch (e) {
      if (_isNotFound(e)) recordingsSupported = false;
    }
    _notify();
    _schedulePoll();
  }

  /// A recording stopped on this phone: show it as "กำลังประมวลผล…" until it is a source.
  void trackFinished(FinishedRecording f) {
    final rid = f.recordingId ?? 'local:${f.clientSessionId}';
    _csidOf[rid] = f.clientSessionId;
    recordings = [
      NotebookRecording(id: rid, notebookId: id, title: f.title, status: _uploading(rid) ? RecordingStatus.uploading : RecordingStatus.processing, durationMs: f.durationMs),
      ...recordings.where((r) => r.id != rid),
    ];
    _notify();
    _schedulePoll(soon: true);
  }

  bool _uploading(String rid) {
    final csid = _csidOf[rid];
    return _queue.pendingFor(clientSessionId: csid, recordingId: rid.startsWith('local:') ? null : rid).isNotEmpty;
  }

  void _schedulePoll({bool soon = false}) {
    if (_disposed) return;
    if (!recordings.any((r) => r.status.working)) {
      _recPoll?.cancel();
      _recPoll = null;
      return;
    }
    if (_recPoll?.isActive == true && !soon) return;
    _recPoll?.cancel();
    _recPoll = Timer(soon ? const Duration(milliseconds: 300) : recordingPollEvery, () => unawaited(pollRecordings()));
  }

  /// One status round for the recordings being uploaded / processed.
  Future<void> pollRecordings() async {
    var becameReady = false;
    for (final r in [...recordings]) {
      if (_disposed) return;
      if (!r.status.working) continue;
      if (_uploading(r.id)) {
        r.status = RecordingStatus.uploading;
        continue;
      }
      if (r.id.startsWith('local:')) continue;
      try {
        final fresh = NotebookRecording.fromJson(await api.getNotebookRecording(id, r.id));
        if (fresh.noteId != null) recordingNotes[r.id] = fresh.noteId!;
        if (fresh.status == RecordingStatus.ready) {
          recordings = recordings.where((x) => x.id != r.id).toList();
          becameReady = true;
        } else {
          final i = recordings.indexWhere((x) => x.id == r.id);
          // Still "recording" on the server = the stop is on its way: keep showing processing.
          if (i >= 0) recordings[i] = fresh.status.active ? (r..status = RecordingStatus.processing) : fresh;
        }
      } catch (e) {
        if (_isNotFound(e)) recordings = recordings.where((x) => x.id != r.id).toList();
      }
    }
    if (becameReady) await load(quiet: true);
    _notify();
    _recPoll = null;
    _schedulePoll();
  }

  Future<void> retryRecording(NotebookRecording r) async {
    await api.retryNotebookRecording(id, r.id);
    r.status = RecordingStatus.processing;
    _notify();
    _schedulePoll(soon: true);
  }

  Future<void> deleteRecording(NotebookRecording r) async {
    if (!r.id.startsWith('local:')) await api.deleteNotebookRecording(id, r.id);
    recordings = recordings.where((x) => x.id != r.id).toList();
    _notify();
  }

  /// The recording behind a `recording` source (`source_config.recording_id`, else by `source_id`).
  Future<NotebookRecording?> recordingForSource(NotebookSource s) async {
    var rid = '${s.config['recording_id'] ?? ''}';
    if (rid.isEmpty || rid == 'null') {
      try {
        final rows = await api.getNotebookRecordings(id);
        rid = '${rows.where((r) => '${r['source_id']}' == s.id).firstOrNull?['id'] ?? ''}';
      } catch (_) {}
    }
    if (rid.isEmpty || rid == 'null') return null;
    final r = NotebookRecording.fromJson(await api.getNotebookRecording(id, rid));
    if (r.noteId != null) recordingNotes[r.id] = r.noteId!;
    return r;
  }

  NotebookNote? noteById(String? nid) => nid == null ? null : notes.where((n) => n.id == nid).firstOrNull;

  // ── notebook

  Future<void> rename(String title, {String? description}) async {
    final nb = notebook;
    if (nb == null || title.trim().isEmpty) return;
    final m = await api.updateNotebook(id, {'title': title.trim(), 'description': ?description});
    notebook = nb.merge(Notebook.fromJson({'user_id': nb.userId, ...m}));
    _sortSources();
    _notify();
  }

  // ── chat settings

  ChatSettings get chatSettings => notebook?.chatSettings ?? ChatSettings.defaults;

  /// Saves how ISAAC answers here; null resets to the defaults. Throws (e.g. 400 validation) to the caller.
  Future<void> saveChatSettings(ChatSettings? s) async {
    final nb = notebook;
    if (nb == null) return;
    final m = await api.updateNotebookChatSettings(id, s?.toJson());
    if (m['id'] != null) {
      notebook = nb.merge(Notebook.fromJson({'user_id': nb.userId, ...m}));
      _sortSources();
    }
    // Older servers echo the row without `chat_settings`: keep what was saved.
    notebook!.chatSettings = m['chat_settings'] is Map ? ChatSettings.fromJson(Map<String, dynamic>.from(m['chat_settings'] as Map)) : (s ?? ChatSettings.defaults);
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
  /// [options]: e.g. `{audio: {format, length, hosts: 2}}` for the v2 Audio Overview.
  Future<NotebookNote?> runStudio(StudioKind kind, {String? templateId, String locale = 'th', Map<String, dynamic>? options}) async {
    if (studioRun != null || notebook == null) return null;
    final run = studioRun = StudioRun(kind);
    _notify();
    try {
      final before = {for (final n in notes) n.id};
      final async = await _useJobs();
      final res = await api.runNotebookStudio(id, kind: kind.id, sourceIds: [for (final s in enabledSources) s.id], locale: locale, templateId: templateId, async: async, options: options);
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
