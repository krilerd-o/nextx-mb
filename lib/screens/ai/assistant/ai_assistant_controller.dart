import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai_assistant.dart';
import '../../../core/ai_commands.dart';
import '../../../core/i18n.dart';
import '../../../services/api_client.dart';

/// State of the ISAAC AI Assistant (web `AiAssistantProvider.jsx`):
/// conversations and folders on the server, one open chat, streaming replies,
/// proposals, answer mode and slash commands.
class AiAssistantController extends ChangeNotifier {
  AiAssistantController(this.api);

  final ApiClient api;

  /// Chats per page in the history list.
  static const pageSize = 50;

  List<AiConversation> conversations = [];
  bool listLoading = false;
  bool loadingMore = false;
  bool hasMore = false;
  String query = '';

  /// Archived chats (loaded when the user opens that section).
  List<AiConversation> archivedChats = [];
  bool archivedLoading = false;

  /// The record this chat is about ("ถาม Isaac" from a record page, or `@` mention).
  String? contextModule;
  String? contextId;
  String? contextTitle;

  void clearContext() {
    contextModule = contextId = contextTitle = null;
    _notify();
  }

  void setContext(String module, String id, String title) {
    contextModule = module;
    contextId = id;
    contextTitle = title;
    _notify();
  }

  /// Chat folders (server "AI projects") and the one shown, null = all.
  List<AiFolder> folders = const [];
  String? projectFilter;

  /// Kept for older callers / tests: folders as raw maps.
  List<Map<String, dynamic>> get projects => [
    for (final f in folders) {'id': f.id, 'name': f.name, 'color': f.color, 'icon': f.icon, 'instructions': f.instructions},
  ];

  AiFolder? folderById(String? id) => id == null ? null : folders.where((f) => f.id == id).firstOrNull;

  /// Chats visible in the list (folder filter applied).
  List<AiConversation> get visibleConversations => projectFilter == null ? conversations : conversations.where((c) => c.projectId == projectFilter).toList();

  int chatCountIn(String folderId) {
    final f = folderById(folderId);
    final local = conversations.where((c) => c.projectId == folderId).length;
    // The server counts every chat; the local list may be one page only.
    return f?.chatCount != null && f!.chatCount! > local ? f.chatCount! : local;
  }

  String? activeId;
  String activeTitle = '';
  bool activeStarred = false;
  bool activeArchived = false;
  String? activeProjectId;
  List<AiMessage> messages = [];
  bool chatLoading = false;

  /// New chat started from a folder page: filed there when it is created.
  String? pendingProjectId;

  /// A reply is streaming.
  bool sending = false;
  AiStreamEvent? status;
  List<Map<String, dynamic>> routeSteps = const [];
  DateTime? sendStartedAt;
  String? error;
  String? errorCode;

  /// Bumped (at most every [_tokenFrame]) while tokens arrive. Only the
  /// streaming message listens, so the screen does not rebuild per token.
  final ValueNotifier<int> streamTick = ValueNotifier(0);
  static const _tokenFrame = Duration(milliseconds: 50);
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _tickTimer;

  /// `auto` or a provider id; model when not auto (the "ขั้นสูง" picker).
  String provider = 'auto';
  String? model;
  ({String provider, String model})? sticky;

  /// Answer mode with Auto: `auto` · `fast` · `deep`.
  String autoMode = 'auto';

  /// Use CRM data (business knowledge) in answers.
  bool injectContext = true;
  double temperature = 0.7;

  Map<String, dynamic>? usage;
  AiModelPolicy? policy;

  AiUsageView? get usageView => AiUsageView.from(usage);
  List<Map<String, dynamic>> suggestedPrompts = const [];
  List<Map<String, dynamic>> followUps = const [];

  /// Slash commands from the business and from the user.
  List<AiCommand> businessCommands = const [];
  List<AiCommand> myCommands = const [];

  /// Built-in + business + mine, for the `/` menu.
  List<AiCommand> get allCommands => [...kAiBuiltinCommands, ...businessCommands, ...myCommands];

  /// Files uploaded for the next message.
  final List<Map<String, dynamic>> pendingAttachments = [];
  bool uploading = false;

  /// Upload progress 0..1 of the file being sent (null when unknown).
  double? uploadProgress;

  /// Proposals confirmed / cancelled: proposalId → working | done | cancelled.
  /// Filled from the server when a chat opens, so a reopened chat stays done.
  final Map<String, String> proposalState = {};

  /// Link returned when a proposal ran (open the new record).
  final Map<String, String> proposalLinks = {};

  CancelToken? _cancel;
  bool _disposed = false;

  /// The user left (screen closed / app in the background) while Isaac was
  /// answering: tell them when it is done.
  bool notifyOnFinish = false;
  void Function(String chatId, String title, String text)? onBackgroundReply;

  /// Screen closed mid-answer: finish the answer, then dispose.
  bool disposeWhenIdle = false;

  /// A message is on its way (creating the chat, saving, or streaming).
  bool _starting = false;
  bool get busy => sending || _starting;

  bool get quotaExhausted {
    final u = usage;
    if (u == null || u['meters_cloud'] == false) return false;
    final r = num.tryParse('${u['remaining'] ?? ''}');
    return r != null && r <= 0;
  }

  /// "Auto · คิดลึก" or the picked model.
  String get modeLabel => provider == 'auto' ? (autoMode == 'auto' ? 'Auto' : aiModeLabel(autoMode)) : aiModelBadge(provider, model);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    _tickTimer?.cancel();
    streamTick.dispose();
    super.dispose();
  }

  Future<void> init() async {
    await _loadPrefs();
    await Future.wait([
      loadConversations(),
      loadProjects(),
      loadCommands(),
      api.getAiUsage().then((u) => usage = u).catchError((_) => <String, dynamic>{}),
      api.getAiModelPolicy().then((p) => policy = AiModelPolicy.fromJson(p)).catchError((_) => const AiModelPolicy({}, {})),
      api.getAiSuggestedPrompts().then((p) => suggestedPrompts = p).catchError((_) => <Map<String, dynamic>>[]),
    ]);
    _notify();
  }

  // ── preferences (answer mode, CRM data, temperature)

  static const _kMode = 'ai.mode';
  static const _kCtx = 'ai.inject_context';
  static const _kTemp = 'ai.temperature';

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = p.getString(_kMode);
      if (m != null && kAiModes.contains(m)) autoMode = m;
      injectContext = p.getBool(_kCtx) ?? true;
      temperature = p.getDouble(_kTemp) ?? 0.7;
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kMode, autoMode);
      await p.setBool(_kCtx, injectContext);
      await p.setDouble(_kTemp, temperature);
    } catch (_) {}
  }

  /// Auto / Fast / Deep: back to Auto routing (drops a manual model).
  void setMode(String mode) {
    if (!kAiModes.contains(mode)) return;
    autoMode = mode;
    provider = 'auto';
    model = null;
    sticky = null;
    if ((errorCode ?? '').contains('EXHAUSTED')) clearError();
    _notify();
    unawaited(_savePrefs());
    unawaited(reloadUsage());
  }

  void setInjectContext(bool v) {
    injectContext = v;
    _notify();
    unawaited(_savePrefs());
  }

  void setTemperature(double v) {
    temperature = v;
    _notify();
    unawaited(_savePrefs());
  }

  // ── chat list

  Future<void> loadConversations() async {
    listLoading = true;
    _notify();
    try {
      final rows = await api.getAiConversations(q: query, archived: false, limit: pageSize);
      conversations = _chatRows(rows);
      hasMore = rows.length >= pageSize;
    } catch (_) {
    } finally {
      listLoading = false;
      _notify();
    }
  }

  /// Next page of the history list (dedupes in case the server ignores paging).
  Future<void> loadMore() async {
    if (!hasMore || loadingMore || listLoading) return;
    loadingMore = true;
    _notify();
    try {
      final rows = await api.getAiConversations(q: query, archived: false, limit: pageSize, offset: conversations.length);
      final seen = {for (final c in conversations) c.id};
      final fresh = _chatRows(rows).where((c) => seen.add(c.id)).toList();
      conversations = [...conversations, ...fresh];
      hasMore = fresh.isNotEmpty && rows.length >= pageSize;
    } catch (_) {
      hasMore = false;
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  Future<void> loadArchived() async {
    archivedLoading = true;
    _notify();
    try {
      archivedChats = _chatRows(await api.getAiConversations(archived: true, limit: pageSize)).where((c) => c.archived).toList();
    } catch (_) {
      archivedChats = [];
    } finally {
      archivedLoading = false;
      _notify();
    }
  }

  List<AiConversation> _chatRows(List<Map<String, dynamic>> rows) => [
    for (final r in rows)
      if ('${r['mode'] ?? 'chat'}' == 'chat' || r['mode'] == null) AiConversation.fromJson(r),
  ].where((c) => !c.archived).toList();

  /// Search the history (debounced by the caller).
  Future<void> search(String q) async {
    query = q;
    await loadConversations();
  }

  /// Most recent chats for the welcome screen ("ทำต่อ").
  List<AiConversation> get recentChats {
    final list = [...conversations]..sort((a, b) => (b.updatedAt ?? '').compareTo(a.updatedAt ?? ''));
    return list.take(3).toList();
  }

  void newChat({String? inFolder}) {
    if (sending) stop();
    activeId = null;
    activeTitle = '';
    activeStarred = false;
    activeArchived = false;
    activeProjectId = inFolder;
    pendingProjectId = inFolder;
    messages = [];
    followUps = const [];
    error = null;
    errorCode = null;
    pendingAttachments.clear();
    _notify();
  }

  Future<void> open(String id) async {
    if (sending) stop();
    activeId = id;
    pendingProjectId = null;
    chatLoading = true;
    error = null;
    followUps = const [];
    messages = [];
    _notify();
    try {
      final c = await api.getAiConversation(id);
      activeTitle = '${c['title'] ?? ''}';
      activeStarred = c['starred'] == true || c['starred'] == 1;
      activeArchived = c['archived'] == true || c['archived'] == 1;
      activeProjectId = c['project_id']?.toString();
      messages = [
        for (final m in (c['messages'] is List ? c['messages'] as List : const []))
          if (m is Map) AiMessage.fromJson(Map<String, dynamic>.from(m)),
      ];
      // Proposals already confirmed / cancelled on the server stay that way.
      for (final m in messages) {
        for (final p in m.proposals) {
          final pid = '${p['proposalId'] ?? ''}';
          final st = '${p['status'] ?? ''}';
          if (pid.isEmpty) continue;
          if (st == 'done' || st == 'cancelled') proposalState[pid] = st;
          if (p['link'] != null) proposalLinks[pid] = '${p['link']}';
        }
      }
    } catch (e) {
      error = formatApiError(e);
    } finally {
      chatLoading = false;
      _notify();
    }
  }

  Future<String> _ensureConversation(String titleHint) async {
    if (activeId != null) return activeId!;
    final folder = pendingProjectId;
    final c = await api.createAiConversation({
      'title': titleHint,
      'mode': 'chat',
      'project_id': ?(folder == null ? null : int.tryParse(folder) ?? folder),
      if (contextModule != null && contextId != null) ...{'context_module': contextModule, 'context_id': int.tryParse(contextId!) ?? contextId},
    });
    activeId = '${c['id']}';
    activeTitle = '${c['title'] ?? titleHint}';
    activeProjectId = folder;
    pendingProjectId = null;
    conversations = [
      AiConversation.fromJson({...c, 'title': activeTitle, 'project_id': ?folder}),
      ...conversations.where((x) => x.id != activeId),
    ];
    _notify();
    return activeId!;
  }

  /// Send like the web: ensure conversation → save user message → stream →
  /// save assistant message. [deep] sends this one message in "คิดลึก" mode.
  Future<void> send(String text, {bool deep = false}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && pendingAttachments.isEmpty) || sending || uploading) return;
    error = null;
    errorCode = null;
    followUps = const [];
    final attachments = List<Map<String, dynamic>>.from(pendingAttachments);
    pendingAttachments.clear();
    final user = AiMessage(
      role: 'user',
      content: trimmed,
      attachments: attachments,
      provider: provider,
      model: model,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    final prior = List<AiMessage>.from(messages);
    messages = [...messages, user];
    _starting = true;
    _notify();
    try {
      final titleHint = trimmed.isNotEmpty ? (trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed) : '${attachments.first['original_name'] ?? 'แชทใหม่'}';
      final convId = await _ensureConversation(titleHint);
      await _save(convId, user);
      await _stream(convId, aiHistoryForApi([...prior, user]), _imageIds(attachments), deep: deep);
    } catch (e) {
      _fail(e);
    } finally {
      _starting = false;
      if (disposeWhenIdle && !_disposed) dispose();
    }
  }

  /// Messages the server has not stored yet (save failed twice): shown
  /// with "ยังไม่บันทึก · ลองอีกครั้ง" so history never drifts silently.
  final Set<AiMessage> unsaved = {};

  /// Save [m] to chat [convId]: one quiet retry, then mark it unsaved.
  Future<void> _save(String convId, AiMessage m) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final saved = await api.appendAiMessage(convId, m.toSaveJson());
        if (saved['id'] != null) m.id = '${saved['id']}';
        if (unsaved.remove(m)) _notify();
        return;
      } catch (_) {
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    unsaved.add(m);
    _notify();
  }

  /// "ลองอีกครั้ง" under an unsaved message.
  Future<void> resave(AiMessage m) async {
    final id = activeId;
    if (id == null) return;
    await _save(id, m);
  }

  List<String> _imageIds(List<Map<String, dynamic>> attachments) => [
    for (final a in attachments)
      if (aiIsImage(a) && a['id'] != null) '${a['id']}',
  ];

  void _tickStream() {
    final now = DateTime.now();
    if (now.difference(_lastTick) >= _tokenFrame) {
      _lastTick = now;
      _tickTimer?.cancel();
      _tickTimer = null;
      streamTick.value++;
    } else {
      _tickTimer ??= Timer(_tokenFrame, () {
        _tickTimer = null;
        _lastTick = DateTime.now();
        if (!_disposed) streamTick.value++;
      });
    }
  }

  Future<void> _stream(String convId, List<Map<String, dynamic>> history, List<String> imageIds, {bool deep = false}) async {
    sending = true;
    status = const AiStreamEvent('status', {'phase': 'thinking'});
    routeSteps = provider == 'auto'
        ? const [
            {'id': 'analyze', 'label': 'วิเคราะห์โจทย์…'},
            {'id': 'model', 'label': 'กำลังเลือกโมเดล…'},
          ]
        : const [];
    sendStartedAt = DateTime.now();
    final reply = AiMessage(role: 'assistant', streaming: true, provider: provider, model: model, createdAt: DateTime.now().toUtc().toIso8601String());
    messages = [...messages, reply];
    _notify();
    final cancel = _cancel = CancelToken();
    Map<String, dynamic>? done;
    ApiEnvelopeException? streamError;
    try {
      final body = aiChatBody(
        history: history,
        conversationId: convId,
        provider: provider,
        model: model,
        sticky: deep ? null : sticky,
        attachmentIds: imageIds,
        contextModule: contextModule,
        contextId: contextId,
        contextTitle: contextTitle,
        autoMode: deep ? 'deep' : autoMode,
        injectContext: injectContext,
        temperature: temperature,
      );
      await for (final ev in api.streamAiChat(body, cancel: cancel)) {
        switch (ev.type) {
          case 'token':
            final first = reply.content.isEmpty;
            reply.content += ev.token;
            if (first) {
              // Waiting → text: the tile changes shape, rebuild once.
              _notify();
            } else {
              _tickStream();
            }
            continue;
          case 'tool_proposal':
            final p = ev.data['proposal'];
            if (p is Map) reply.proposals = _mergeProposals(reply.proposals, [Map<String, dynamic>.from(p)]);
          case 'tool_start':
            status = ev;
            final name = '${ev.data['name'] ?? ev.data['tool'] ?? ''}';
            if (name.isNotEmpty) {
              reply.toolSteps = [
                ...reply.toolSteps,
                {'name': name, 'label': ev.data['label'] ?? aiToolLabel(name), 'done': false},
              ];
            }
          case 'tool_done':
            status = ev;
            final name = '${ev.data['name'] ?? ev.data['tool'] ?? ''}';
            final i = reply.toolSteps.lastIndexWhere((s) => s['name'] == name && s['done'] != true);
            if (i >= 0) reply.toolSteps = [...reply.toolSteps]..[i] = {...reply.toolSteps[i], 'done': true};
          case 'auto_route':
            status = ev;
            final steps = ev.data['steps'];
            if (steps is List) {
              routeSteps = [
                for (final s in steps)
                  if (s is Map) Map<String, dynamic>.from(s),
              ];
            }
            final p = '${ev.data['provider'] ?? ''}', m = '${ev.data['model'] ?? ''}';
            if (p.isNotEmpty && m.isNotEmpty) {
              if (!deep) sticky = (provider: p, model: m);
              reply.provider = p;
              reply.model = m;
            }
          case 'done':
            done = ev.data;
          case 'error':
            // Let the server close the stream; cancelling mid-read can hang.
            streamError ??= ApiEnvelopeException(500, '${ev.data['error_code'] ?? 'AI_ERROR'}', '${ev.data['message'] ?? 'AI ตอบไม่สำเร็จ'}');
          default:
            status = ev;
        }
        _notify();
      }
      _tickTimer?.cancel();
      _tickTimer = null;
      if (cancel.isCancelled) return;
      if (streamError != null) throw streamError;
      final d = done ?? const <String, dynamic>{};
      final msg = d['message'] is Map ? Map<String, dynamic>.from(d['message'] as Map) : const <String, dynamic>{};
      final apiContent = '${msg['content'] ?? ''}';
      if (apiContent.trim().isNotEmpty) reply.content = apiContent;
      reply.proposals = _mergeProposals(_maps(d['proposals']), reply.proposals);
      reply.downloads = aiDownloadsFromToolResults(d['toolResults']);
      reply.askUser = _maps(msg['ask_user']);
      reply.citations = _maps(d['citations']).isNotEmpty ? _maps(d['citations']) : _maps(msg['citations']);
      reply.provider = '${d['provider'] ?? reply.provider ?? provider}';
      reply.model = d['model']?.toString() ?? reply.model;
      reply.toolSteps = [
        for (final s in reply.toolSteps) {...s, 'done': true},
      ];
      reply.streaming = false;
      if (d['usageSummary'] is Map) usage = Map<String, dynamic>.from(d['usageSummary'] as Map);
      sending = false;
      status = null;
      _notify();
      await _save(convId, reply);
      _loadFollowUps(history, reply.content);
      if (notifyOnFinish && onBackgroundReply != null) {
        notifyOnFinish = false;
        onBackgroundReply!(convId, activeTitle, reply.content);
      }
      // Title comes from the first message on the server: refresh the list.
      unawaited(loadConversations());
    } catch (e) {
      if (cancel.isCancelled) return;
      messages = messages.where((m) => m != reply || m.content.trim().isNotEmpty).toList();
      reply.streaming = false;
      _fail(e);
    } finally {
      if (identical(_cancel, cancel)) _cancel = null;
      sending = false;
      status = null;
      _notify();
      if (disposeWhenIdle && !_disposed) dispose();
    }
  }

  Future<void> _loadFollowUps(List<Map<String, dynamic>> history, String reply) async {
    if (reply.trim().isEmpty) return;
    final lastUser = history.lastWhere((m) => m['role'] == 'user', orElse: () => const {'content': ''});
    try {
      final items = await api.postAiReplySuggestions(lastReply: reply, lastUserMessage: '${lastUser['content']}', locale: L10n.isEn ? 'en' : 'th');
      followUps = items.take(6).toList();
      _notify();
    } catch (_) {}
  }

  void _fail(Object e) {
    errorCode = e is ApiEnvelopeException ? e.errorCode : null;
    error = aiErrorText(e);
    sending = false;
    _notify();
    // Quota errors: refresh the meter so "switch model" choices show up.
    if ((errorCode ?? '').contains('EXHAUSTED')) unawaited(reloadUsage());
  }

  Future<void> reloadUsage() async {
    try {
      usage = await api.getAiUsage(provider: provider == 'auto' ? null : provider, model: model);
      _notify();
    } catch (_) {}
  }

  /// Stop generation (the web aborts the request the same way).
  void stop() {
    _cancel?.cancel();
    _cancel = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    messages = messages.where((m) => !(m.streaming && m.content.trim().isEmpty)).map((m) => m..streaming = false).toList();
    sending = false;
    status = null;
    _notify();
  }

  /// Drop the last reply on the server, then stream it again.
  Future<void> regenerate() async {
    final id = activeId;
    if (id == null || sending) return;
    error = null;
    try {
      await api.regenerateAi(id);
      while (messages.isNotEmpty && !messages.last.isUser) {
        messages = messages.sublist(0, messages.length - 1);
      }
      _notify();
      final last = messages.where((m) => m.isUser).lastOrNull;
      await _stream(id, aiHistoryForApi(messages), _imageIds(last?.attachments ?? const []));
    } catch (e) {
      _fail(e);
    }
  }

  /// "ลองใหม่" on the error banner: when the last message is the user's (no
  /// reply came back) stream again for it; otherwise regenerate the reply.
  Future<void> retry() async {
    if (sending) return;
    clearError();
    final last = messages.lastOrNull;
    if (last == null) return;
    if (!last.isUser) return regenerate();
    final id = activeId;
    try {
      if (id == null) {
        // The chat was never created: send the text again from scratch.
        messages = messages.sublist(0, messages.length - 1);
        pendingAttachments
          ..clear()
          ..addAll(last.attachments);
        await send(last.content);
        return;
      }
      await _stream(id, aiHistoryForApi(messages), _imageIds(last.attachments));
    } catch (e) {
      _fail(e);
    }
  }

  /// Edit a sent message: keep the chat up to it, replace it with [text] on
  /// the server, then answer again.
  Future<void> editAndResend(AiMessage original, String text) async {
    final trimmed = text.trim();
    final i = messages.indexOf(original);
    if (i < 0 || !original.isUser || trimmed.isEmpty || sending) return;
    error = null;
    errorCode = null;
    followUps = const [];
    final edited = AiMessage(
      role: 'user',
      content: trimmed,
      attachments: original.attachments,
      provider: provider,
      model: model,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    messages = [...messages.sublist(0, i), edited];
    _notify();
    try {
      final id = activeId;
      if (id == null) {
        messages = messages.sublist(0, i);
        await send(trimmed);
        return;
      }
      await api.replaceAiMessages(id, [for (final m in messages) m.toSaveJson()]);
      await _stream(id, aiHistoryForApi(messages), _imageIds(edited.attachments));
    } catch (e) {
      _fail(e);
    }
  }

  /// A record saved from a create form (/lead, /นัด …): an assistant
  /// message with a done card + link, saved to the chat like any reply.
  Future<void> addCreatedCard({
    required String module,
    required String id,
    required String label,
    required String title,
    required Map<String, dynamic> values,
    required String link,
    String? kind,
    Map<String, dynamic>? replacesProposal,
  }) async {
    final pid = 'form-$module-$id';
    final summary = <String, dynamic>{};
    for (final k in _kCardFieldOrder) {
      final v = values[k];
      if (v == null || '$v'.isEmpty || summary.length >= 6) continue;
      summary[k] = v is Map ? '${v['label'] ?? v['id']}' : (k == 'priority' ? (_kPriorityTh['$v'] ?? v) : v);
    }
    final owner = values['smownerid'] ?? values['assignee_id'];
    final proposal = <String, dynamic>{
      'proposalId': pid,
      'tool': 'create_${module == 'workspace_item' ? (kind == 'epic' ? 'workspace_epic' : 'workspace_item') : module}',
      'status': 'done',
      'link': link,
      'preview': {
        'module': module,
        'record': {'module': module, 'id': id, 'title': title, 'kind': ?kind},
        'fields': summary,
        if (owner != null) 'owner': owner is Map ? {'id': owner['id'], 'label': owner['label']} : {'id': owner, 'label': '$owner'},
      },
    };
    proposalState[pid] = 'done';
    proposalLinks[pid] = link;
    final text = title.isEmpty ? '$label แล้ว' : '$label **$title** แล้ว';
    final reply = AiMessage(role: 'assistant', content: text, proposals: [proposal], createdAt: DateTime.now().toUtc().toIso8601String());
    if (replacesProposal != null) {
      final old = '${replacesProposal['proposalId'] ?? ''}';
      if (old.isNotEmpty) proposalState[old] = 'form';
    }
    messages = [...messages, reply];
    _notify();
    try {
      final convId = await _ensureConversation(title.isEmpty ? label : '$label $title');
      await _save(convId, reply);
      unawaited(loadConversations());
    } catch (e) {
      error = aiErrorText(e);
      _notify();
    }
  }

  /// 👍 (1) / 👎 (-1) on an answer; the same again clears it.
  Future<void> setFeedback(AiMessage m, int rating, {String? note}) async {
    final id = activeId;
    if (id == null || m.id == null) return;
    final before = m.feedback;
    final next = before == rating && note == null ? 0 : rating;
    m.feedback = next == 0 ? null : next;
    _notify();
    try {
      await api.postAiFeedback(id, m.id!, next, note: note);
    } catch (e) {
      m.feedback = before;
      error = aiErrorText(e);
      _notify();
    }
  }

  Future<String?> confirmProposal(Map<String, dynamic> p, {String? boardId}) async {
    final id = '${p['proposalId'] ?? ''}';
    if (id.isEmpty) return null;
    proposalState[id] = 'working';
    _notify();
    try {
      final r = await api.confirmAiTool(id, boardId: boardId, conversationId: activeId, messageId: _messageIdOf(id));
      proposalState[id] = 'done';
      final link = (r['link'] ?? r['board_link'])?.toString();
      if (link != null && link.isNotEmpty) proposalLinks[id] = link;
      _notify();
      return link;
    } catch (e) {
      proposalState.remove(id);
      error = aiErrorText(e);
      _notify();
      return null;
    }
  }

  Future<void> cancelProposal(Map<String, dynamic> p) async {
    final id = '${p['proposalId'] ?? ''}';
    if (id.isEmpty) return;
    proposalState[id] = 'cancelled';
    _notify();
    try {
      await api.cancelAiTool(id, conversationId: activeId, messageId: _messageIdOf(id));
    } catch (_) {}
  }

  String? _messageIdOf(String proposalId) => messages.where((m) => m.proposals.any((p) => '${p['proposalId']}' == proposalId)).firstOrNull?.id;

  Future<void> uploadAttachment(MultipartFile file) async {
    uploading = true;
    uploadProgress = null;
    _notify();
    try {
      final a = await api.uploadAiAttachment(
        file,
        conversationId: activeId,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          uploadProgress = sent / total;
          _notify();
        },
      );
      pendingAttachments.add(a);
    } catch (e) {
      error = aiErrorText(e);
    } finally {
      uploading = false;
      uploadProgress = null;
      _notify();
    }
  }

  /// Several files picked at once, uploaded one after another.
  Future<void> uploadAttachments(List<MultipartFile> files) async {
    for (final f in files) {
      await uploadAttachment(f);
    }
  }

  void removeAttachment(Map<String, dynamic> a) {
    pendingAttachments.remove(a);
    _notify();
  }

  // ── chat actions

  Future<void> rename(String id, String title) async {
    if (title.trim().isEmpty) return;
    await api.updateAiConversation(id, {'title': title.trim()});
    if (id == activeId) activeTitle = title.trim();
    await loadConversations();
  }

  Future<void> toggleStar(String id, bool starred) async {
    await api.updateAiConversation(id, {'starred': starred});
    if (id == activeId) activeStarred = starred;
    await loadConversations();
  }

  Future<void> delete(String id) async {
    await api.deleteAiConversation(id);
    if (id == activeId) newChat();
    conversations = conversations.where((c) => c.id != id).toList();
    _notify();
  }

  /// Archive (hide from history) or bring back.
  Future<void> setArchived(String id, bool archived) async {
    await api.updateAiConversation(id, {'archived': archived});
    if (id == activeId) activeArchived = archived;
    if (archived) {
      final c = conversations.where((x) => x.id == id).firstOrNull;
      conversations = conversations.where((x) => x.id != id).toList();
      if (c != null) archivedChats = [c.copyWith(archived: true), ...archivedChats];
      if (id == activeId) newChat();
    } else {
      archivedChats = archivedChats.where((x) => x.id != id).toList();
      unawaited(loadConversations());
    }
    _notify();
  }

  /// Hide a chat now; the caller deletes it on the server unless undone.
  ({int index, AiConversation chat})? removeLocal(String id) {
    final i = conversations.indexWhere((c) => c.id == id);
    if (i < 0) return null;
    final c = conversations[i];
    conversations = [...conversations]..removeAt(i);
    if (id == activeId) newChat();
    _notify();
    return (index: i, chat: c);
  }

  void restoreLocal(({int index, AiConversation chat}) r) {
    final list = [...conversations];
    list.insert(r.index.clamp(0, list.length), r.chat);
    conversations = list;
    _notify();
  }

  // ── folders

  Future<void> loadProjects() async {
    try {
      folders = [for (final m in await api.getAiProjects()) AiFolder.fromJson(m)];
      if (projectFilter != null && folderById(projectFilter) == null) projectFilter = null;
    } catch (_) {
      folders = const [];
    }
    _notify();
  }

  void setProjectFilter(String? id) {
    projectFilter = id;
    _notify();
  }

  Future<void> moveToProject(String chatId, String? projectId) async {
    await api.updateAiConversation(chatId, {'project_id': projectId});
    if (chatId == activeId) activeProjectId = projectId;
    await Future.wait([loadConversations(), loadProjects()]);
  }

  /// Move several chats at once (multi-select in the history).
  Future<void> moveManyToProject(Iterable<String> chatIds, String? projectId) async {
    for (final id in chatIds) {
      await api.updateAiConversation(id, {'project_id': projectId});
      if (id == activeId) activeProjectId = projectId;
    }
    await Future.wait([loadConversations(), loadProjects()]);
  }

  Future<AiFolder?> createFolder({required String name, String? color, String? icon, String? instructions}) async {
    final r = await api.createAiProject({
      'name': name.trim(),
      'color': ?color,
      'icon': ?icon,
      if (instructions != null && instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
    });
    await loadProjects();
    return r['id'] == null ? null : AiFolder.fromJson(r);
  }

  Future<void> updateFolder(String id, {String? name, String? color, String? icon, String? instructions}) async {
    await api.updateAiProject(id, {if (name != null) 'name': name.trim(), 'color': ?color, 'icon': ?icon, 'instructions': ?instructions?.trim()});
    await loadProjects();
  }

  /// The folder goes; its chats stay (outside any folder).
  Future<void> deleteFolder(String id) async {
    await api.deleteAiProject(id);
    if (projectFilter == id) projectFilter = null;
    if (activeProjectId == id) activeProjectId = null;
    await Future.wait([loadProjects(), loadConversations()]);
  }

  // ── slash commands

  Future<void> loadCommands() async {
    await Future.wait([
      api
          .getAiQuickPrompts()
          .then(
            (rows) =>
                businessCommands = [for (final r in rows) AiCommand.fromQuickPrompt(r, en: L10n.isEn)].where((c) => c.template.trim().isNotEmpty).toList(),
          )
          .catchError((_) => businessCommands = const []),
      api.getAiMyPrompts().then((rows) => myCommands = [for (final r in rows) AiCommand.fromMine(r)]).catchError((_) => myCommands = const []),
    ]);
    _notify();
  }

  Future<void> saveMyCommand({String? id, required String command, required String title, required String prompt}) async {
    final body = {'command': command, 'title': title.trim(), 'prompt': prompt.trim()};
    if (id == null) {
      await api.createAiMyPrompt(body);
    } else {
      await api.updateAiMyPrompt(id, body);
    }
    await loadCommands();
  }

  Future<void> deleteMyCommand(String id) async {
    await api.deleteAiMyPrompt(id);
    myCommands = myCommands.where((c) => c.id != id).toList();
    _notify();
  }

  void setModel(String p, String? m) {
    provider = p;
    model = m;
    if (p == 'auto') sticky = null;
    if ((errorCode ?? '').contains('EXHAUSTED')) clearError();
    _notify();
    unawaited(reloadUsage());
  }

  void clearError() {
    error = null;
    errorCode = null;
    _notify();
  }
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e),
      ]
    : <Map<String, dynamic>>[];

List<Map<String, dynamic>> _mergeProposals(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  final seen = <String>{};
  return [
    for (final p in [...a, ...b])
      if (seen.add('${p['proposalId'] ?? p.hashCode}')) p,
  ];
}

/// Workspace priority values → Thai.
const _kPriorityTh = {'low': 'ต่ำ', 'medium': 'ปานกลาง', 'high': 'สูง', 'urgent': 'ด่วน', 'highest': 'สูงสุด', 'lowest': 'ต่ำสุด'};

/// Fields shown on a "created" card, in this order (names before ids).
const _kCardFieldOrder = [
  'lead_firstname',
  'lead_lastname',
  'contact_firstname',
  'contact_lastname',
  'account_name',
  'company_name',
  'case_name',
  'subject',
  'title',
  'customer_name',
  'related_account_id',
  'account_id',
  'mobile_1st',
  'email_1st',
  'lead_status',
  'case_status',
  'case_priority',
  'priority',
  'date_start',
  'due_date',
  'location',
  'activitytype',
];

/// Thai label for a tool the agent runs (shown in the reply's step line).
String aiToolLabel(String name) {
  const labels = {
    'search_entities': 'ค้นหาข้อมูล',
    'get_entity': 'อ่านรายละเอียด',
    'list_related': 'ดูรายการที่เกี่ยวข้อง',
    'search_workspace_boards': 'ค้นหาบอร์ด',
    'search_workspace_items': 'ค้นหางาน',
    'get_workspace_item': 'อ่านงาน',
    'create_lead': 'สร้าง Lead',
    'create_contact': 'สร้าง Contact',
    'create_account': 'สร้างบัญชีลูกค้า',
    'create_case': 'เปิดเคส',
    'create_activity': 'สร้างนัด',
    'update_entity': 'แก้ไขข้อมูล',
    'update_status': 'เปลี่ยนสถานะ',
    'export_records': 'ส่งออกไฟล์',
    'generate_document': 'สร้างเอกสาร',
    'export_document': 'ส่งออกเอกสาร',
    'web_lookup': 'ค้นเว็บ',
    'summarize_attachment': 'อ่านไฟล์แนบ',
    'create_workspace_item': 'สร้างงานบนบอร์ด',
    'plan_workspace_tree': 'วางแผนงาน',
    'create_analytics_dashboard': 'สร้างแดชบอร์ด',
  };
  return labels[name] ?? name.replaceAll('_', ' ');
}

/// Friendly Thai text for AI errors (web `friendlyAiError`).
String aiErrorText(Object e) {
  if (e is ApiEnvelopeException) {
    final c = e.errorCode.toUpperCase();
    if (c.contains('QUOTA_EXHAUSTED')) return 'โควตา AI เดือนนี้หมดแล้ว — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ';
    if (c.contains('DAILY_EXHAUSTED')) return 'โมเดลนี้ใช้ครบโควตาวันนี้แล้ว — ลองเลือก Auto หรือโมเดลอื่น';
    if (c.contains('AUTO_NO_MODEL')) return 'ตอนนี้ยังไม่มีโมเดล AI ที่พร้อมใช้ — ให้ผู้ดูแลตั้งค่าผู้ให้บริการ AI';
    if (c.contains('FEATURE_DISABLED')) return 'ธุรกิจนี้ยังไม่ได้เปิดใช้ AI Assistant';
    if (e.message.isNotEmpty) return e.message;
  }
  return formatApiError(e);
}
