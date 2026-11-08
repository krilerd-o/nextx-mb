import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/ai_assistant.dart';
import '../../../services/api_client.dart';
import '../../../services/api_exceptions.dart';

/// State of the ISAAC AI Assistant (web `AiAssistantProvider.jsx`):
/// conversations on the server, one open chat, streaming replies, proposals.
class AiAssistantController extends ChangeNotifier {
  AiAssistantController(this.api);

  final ApiClient api;

  List<AiConversation> conversations = [];
  bool listLoading = false;
  String query = '';

  String? activeId;
  String activeTitle = '';
  bool activeStarred = false;
  List<AiMessage> messages = [];
  bool chatLoading = false;

  /// A reply is streaming.
  bool sending = false;
  AiStreamEvent? status;
  List<Map<String, dynamic>> routeSteps = const [];
  DateTime? sendStartedAt;
  String? error;
  String? errorCode;

  /// `auto` or a provider id; model when not auto.
  String provider = 'auto';
  String? model;
  ({String provider, String model})? sticky;

  Map<String, dynamic>? usage;
  List<Map<String, dynamic>> suggestedPrompts = const [];
  List<Map<String, dynamic>> followUps = const [];

  /// Files uploaded for the next message.
  final List<Map<String, dynamic>> pendingAttachments = [];
  bool uploading = false;

  /// Proposals confirmed / cancelled this session: proposalId → result.
  final Map<String, String> proposalState = {};

  CancelToken? _cancel;
  bool _disposed = false;

  bool get quotaExhausted {
    final u = usage;
    if (u == null || u['meters_cloud'] == false) return false;
    final r = num.tryParse('${u['remaining'] ?? ''}');
    return r != null && r <= 0;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> init() async {
    await Future.wait([
      loadConversations(),
      api.getAiUsage().then((u) => usage = u).catchError((_) => <String, dynamic>{}),
      api.getAiSuggestedPrompts().then((p) => suggestedPrompts = p).catchError((_) => <Map<String, dynamic>>[]),
    ]);
    _notify();
  }

  Future<void> loadConversations() async {
    listLoading = true;
    _notify();
    try {
      final rows = await api.getAiConversations(q: query);
      conversations = [
        for (final r in rows)
          if ('${r['mode'] ?? 'chat'}' == 'chat' || r['mode'] == null) AiConversation.fromJson(r),
      ];
    } catch (_) {
    } finally {
      listLoading = false;
      _notify();
    }
  }

  void newChat() {
    if (sending) stop();
    activeId = null;
    activeTitle = '';
    activeStarred = false;
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
    chatLoading = true;
    error = null;
    followUps = const [];
    messages = [];
    _notify();
    try {
      final c = await api.getAiConversation(id);
      activeTitle = '${c['title'] ?? ''}';
      activeStarred = c['starred'] == true || c['starred'] == 1;
      messages = [
        for (final m in (c['messages'] is List ? c['messages'] as List : const []))
          if (m is Map) AiMessage.fromJson(Map<String, dynamic>.from(m)),
      ];
    } catch (e) {
      error = formatApiError(e);
    } finally {
      chatLoading = false;
      _notify();
    }
  }

  Future<String> _ensureConversation(String titleHint) async {
    if (activeId != null) return activeId!;
    final c = await api.createAiConversation({'title': titleHint, 'mode': 'chat'});
    activeId = '${c['id']}';
    activeTitle = '${c['title'] ?? titleHint}';
    conversations = [AiConversation.fromJson({...c, 'title': activeTitle}), ...conversations.where((x) => x.id != activeId)];
    _notify();
    return activeId!;
  }

  /// Send like the web: ensure conversation → save user message → stream →
  /// save assistant message.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && pendingAttachments.isEmpty) || sending || uploading) return;
    error = null;
    errorCode = null;
    followUps = const [];
    final attachments = List<Map<String, dynamic>>.from(pendingAttachments);
    pendingAttachments.clear();
    final user = AiMessage(role: 'user', content: trimmed, attachments: attachments, provider: provider, model: model);
    final prior = List<AiMessage>.from(messages);
    messages = [...messages, user];
    _notify();
    try {
      final titleHint = trimmed.isNotEmpty ? (trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed) : '${attachments.first['original_name'] ?? 'แชทใหม่'}';
      final convId = await _ensureConversation(titleHint);
      await api.appendAiMessage(convId, user.toSaveJson()).catchError((_) => <String, dynamic>{});
      await _stream(convId, aiHistoryForApi([...prior, user]), [for (final a in attachments) if (aiIsImage(a) && a['id'] != null) '${a['id']}']);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _stream(String convId, List<Map<String, dynamic>> history, List<String> imageIds) async {
    sending = true;
    status = const AiStreamEvent('status', {'phase': 'thinking'});
    routeSteps = provider == 'auto'
        ? const [
            {'id': 'analyze', 'label': 'วิเคราะห์โจทย์…'},
            {'id': 'model', 'label': 'กำลังเลือกโมเดล…'},
          ]
        : const [];
    sendStartedAt = DateTime.now();
    final reply = AiMessage(role: 'assistant', streaming: true, provider: provider, model: model);
    messages = [...messages, reply];
    _notify();
    final cancel = _cancel = CancelToken();
    Map<String, dynamic>? done;
    ApiEnvelopeException? streamError;
    try {
      final body = aiChatBody(history: history, conversationId: convId, provider: provider, model: model, sticky: sticky, attachmentIds: imageIds);
      await for (final ev in api.streamAiChat(body, cancel: cancel)) {
        switch (ev.type) {
          case 'token':
            reply.content += ev.token;
          case 'tool_proposal':
            final p = ev.data['proposal'];
            if (p is Map) reply.proposals = _mergeProposals(reply.proposals, [Map<String, dynamic>.from(p)]);
          case 'auto_route':
            status = ev;
            final steps = ev.data['steps'];
            if (steps is List) routeSteps = [for (final s in steps) if (s is Map) Map<String, dynamic>.from(s)];
            final p = '${ev.data['provider'] ?? ''}', m = '${ev.data['model'] ?? ''}';
            if (p.isNotEmpty && m.isNotEmpty) {
              sticky = (provider: p, model: m);
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
      reply.streaming = false;
      if (d['usageSummary'] is Map) usage = Map<String, dynamic>.from(d['usageSummary'] as Map);
      sending = false;
      status = null;
      _notify();
      await api.appendAiMessage(convId, reply.toSaveJson()).catchError((_) => <String, dynamic>{});
      _loadFollowUps(history, reply.content);
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
    }
  }

  Future<void> _loadFollowUps(List<Map<String, dynamic>> history, String reply) async {
    if (reply.trim().isEmpty) return;
    final lastUser = history.lastWhere((m) => m['role'] == 'user', orElse: () => const {'content': ''});
    try {
      final items = await api.postAiReplySuggestions(lastReply: reply, lastUserMessage: '${lastUser['content']}');
      followUps = items.take(6).toList();
      _notify();
    } catch (_) {}
  }

  void _fail(Object e) {
    errorCode = e is ApiEnvelopeException ? e.errorCode : null;
    error = aiErrorText(e);
    sending = false;
    _notify();
  }

  /// Stop generation (the web aborts the request the same way).
  void stop() {
    _cancel?.cancel();
    _cancel = null;
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
      await _stream(id, aiHistoryForApi(messages), [for (final a in last?.attachments ?? const <Map<String, dynamic>>[]) if (aiIsImage(a) && a['id'] != null) '${a['id']}']);
    } catch (e) {
      _fail(e);
    }
  }

  Future<String?> confirmProposal(Map<String, dynamic> p, {String? boardId}) async {
    final id = '${p['proposalId'] ?? ''}';
    if (id.isEmpty) return null;
    proposalState[id] = 'working';
    _notify();
    try {
      final r = await api.confirmAiTool(id, boardId: boardId);
      proposalState[id] = 'done';
      _notify();
      return (r['link'] ?? r['board_link'])?.toString();
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
      await api.cancelAiTool(id);
    } catch (_) {}
  }

  Future<void> uploadAttachment(MultipartFile file) async {
    uploading = true;
    _notify();
    try {
      final a = await api.uploadAiAttachment(file, conversationId: activeId);
      pendingAttachments.add(a);
    } catch (e) {
      error = aiErrorText(e);
    } finally {
      uploading = false;
      _notify();
    }
  }

  void removeAttachment(Map<String, dynamic> a) {
    pendingAttachments.remove(a);
    _notify();
  }

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

  void setModel(String p, String? m) {
    provider = p;
    model = m;
    if (p == 'auto') sticky = null;
    _notify();
  }

  void clearError() {
    error = null;
    errorCode = null;
    _notify();
  }
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

List<Map<String, dynamic>> _mergeProposals(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  final seen = <String>{};
  return [
    for (final p in [...a, ...b])
      if (seen.add('${p['proposalId'] ?? p.hashCode}')) p,
  ];
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
