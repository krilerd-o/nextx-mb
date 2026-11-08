import 'dart:async';
import 'dart:convert';

import 'thai_time.dart';

/// ISAAC AI Assistant — models and helpers ported from the web
/// (`frontend/src/pages/ai-assistant/`), so the app talks to `/api/ai/*` the
/// same way and stores messages in the same shape.

/// Same system hint as the web (`lib/aiProviders.js` SYSTEM_HINT).
const kAiSystemHint =
    "You are a helpful assistant for MOAI NEXT (aisystem). You help with CRM, Workspace, and Social via tools when needed, and you can also answer general questions, draft text, and work with files the user attaches. Reply concisely in the user's language (Thai or English). Do not claim you are CRM-only. For live CRM data always use tools. For Excel/CSV from CRM use export_records. For public live info (e.g. weather) use web_lookup. For attached document content use extracted text / summarize_attachment. When generating downloadable Office/PDF files use generate_document.";

List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

class AiMessage {
  AiMessage({
    this.id,
    required this.role,
    this.content = '',
    this.attachments = const [],
    this.proposals = const [],
    this.downloads = const [],
    this.citations = const [],
    this.askUser = const [],
    this.provider,
    this.model,
    this.createdAt,
    this.streaming = false,
    this.error,
  });

  final String? id;
  final String role; // user | assistant
  String content;
  List<Map<String, dynamic>> attachments;
  List<Map<String, dynamic>> proposals;
  List<Map<String, dynamic>> downloads;
  List<Map<String, dynamic>> citations;
  List<Map<String, dynamic>> askUser;
  String? provider;
  String? model;
  final String? createdAt;
  bool streaming;
  String? error;

  bool get isUser => role == 'user';

  factory AiMessage.fromJson(Map<String, dynamic> m) => AiMessage(
        id: m['id']?.toString(),
        role: '${m['role'] ?? 'assistant'}',
        content: '${m['content'] ?? ''}',
        attachments: _maps(m['attachments']),
        proposals: _maps(m['proposals']),
        downloads: _maps(m['downloads']),
        citations: _maps(m['citations']),
        askUser: _maps(m['ask_user']),
        provider: m['provider']?.toString(),
        model: m['model']?.toString(),
        createdAt: m['created_at']?.toString(),
      );

  /// Body for `POST /ai/conversations/:id/messages` (web `persistMessage`).
  Map<String, dynamic> toSaveJson() => {
        'role': role,
        'content': content,
        if (attachments.isNotEmpty) 'attachments': attachments,
        if (provider != null) 'provider': provider,
        if (model != null) 'model': model,
        if (proposals.isNotEmpty) 'proposals': proposals,
        if (downloads.isNotEmpty) 'downloads': downloads,
        if (citations.isNotEmpty) 'citations': citations,
        if (askUser.isNotEmpty) 'ask_user': askUser,
      };
}

class AiConversation {
  const AiConversation({required this.id, required this.title, this.starred = false, this.projectId, this.updatedAt, this.mode});
  final String id;
  final String title;
  final bool starred;
  final String? projectId;
  final String? updatedAt;
  final String? mode;

  factory AiConversation.fromJson(Map<String, dynamic> m) => AiConversation(
        id: '${m['id']}',
        title: '${m['title'] ?? ''}'.trim().isEmpty ? 'แชทใหม่' : '${m['title']}',
        starred: m['starred'] == true || m['starred'] == 1,
        projectId: m['project_id']?.toString(),
        updatedAt: (m['updated_at'] ?? m['created_at'])?.toString(),
        mode: m['mode']?.toString(),
      );
}

/// Chats grouped วันนี้ / เมื่อวาน / ก่อนหน้า by Bangkok day (web
/// `groupChatsByDate`); starred chats get their own group on top.
List<({String label, List<AiConversation> items})> groupAiChats(List<AiConversation> chats, {DateTime? now}) {
  final n = now ?? thaiNow();
  final today = DateTime(n.year, n.month, n.day);
  final groups = <String, List<AiConversation>>{'ติดดาว': [], 'วันนี้': [], 'เมื่อวาน': [], 'ก่อนหน้า': []};
  for (final c in chats) {
    if (c.starred) {
      groups['ติดดาว']!.add(c);
      continue;
    }
    final d = parseThai(c.updatedAt ?? '');
    if (d == null) {
      groups['ก่อนหน้า']!.add(c);
      continue;
    }
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    groups[diff <= 0 ? 'วันนี้' : (diff == 1 ? 'เมื่อวาน' : 'ก่อนหน้า')]!.add(c);
  }
  return [for (final e in groups.entries) if (e.value.isNotEmpty) (label: e.key, items: e.value)];
}

/// Attachment text appended to a prompt (web `attachmentsToPromptSuffix`).
String aiAttachmentsSuffix(List<Map<String, dynamic>> attachments) {
  if (attachments.isEmpty) return '';
  final lines = [
    for (final a in attachments)
      () {
        final kind = '${a['kind'] ?? a['type'] ?? 'file'}';
        final name = '${a['name'] ?? a['original_name'] ?? 'file'}';
        final url = '${a['url'] ?? ''}';
        final extracted = a['extracted_text'] ?? a['extractedText'];
        if (extracted != null && '$extracted'.isNotEmpty) {
          final t = '$extracted';
          return '[$kind: $name]\nExtracted content:\n${t.length > 12000 ? t.substring(0, 12000) : t}';
        }
        if (a['transcript'] != null) return '[$kind: $name]\nTranscript:\n${a['transcript']}';
        if (kind == 'audio') {
          return '[Attached audio: $name${url.isNotEmpty ? ' — $url' : ''}]\n(Note: audio transcript unavailable — enable media transcription in AI agent policy or wait for speech-to-text.)';
        }
        if (kind == 'image') {
          return '[Attached image: $name${url.isNotEmpty ? ' — $url' : ''}]\n(Describe based on filename/context; no vision text extracted yet.)';
        }
        if (a['extract_status'] == 'unsupported' || a['extract_error'] != null) {
          return '[Attached $kind: $name] (Could not extract text: ${a['extract_error'] ?? a['extract_status']})';
        }
        return '[Attached $kind: $name${url.isNotEmpty ? ' — $url' : ''}${a['id'] != null ? ' id=${a['id']}' : ''}]';
      }(),
  ];
  return '\n\n${lines.join('\n')}';
}

bool aiIsImage(Map<String, dynamic> a) {
  final k = '${a['kind'] ?? a['type'] ?? ''}'.toLowerCase();
  final mime = '${a['mime_type'] ?? a['mime'] ?? ''}'.toLowerCase();
  return k == 'image' || mime.startsWith('image/');
}

/// History for `/ai/chat`: system hint + each turn with its attachment text.
List<Map<String, dynamic>> aiHistoryForApi(List<AiMessage> messages) => [
      {'role': 'system', 'content': kAiSystemHint},
      for (final m in messages)
        if (m.error == null && !m.streaming && (m.content.trim().isNotEmpty || m.attachments.isNotEmpty))
          {'role': m.role, 'content': '${m.content}${aiAttachmentsSuffix(m.attachments)}'},
    ];

/// `POST /api/ai/chat` body (web `buildAutoChatBody` + extras). Auto = the
/// server picks a ready model (`auto_route` event says which).
Map<String, dynamic> aiChatBody({
  required List<Map<String, dynamic>> history,
  required String? conversationId,
  String provider = 'auto',
  String? model,
  ({String provider, String model})? sticky,
  bool injectContext = true,
  List<String> attachmentIds = const [],
  String? contextModule,
  String? contextId,
  String? contextTitle,
}) {
  final auto = provider == 'auto';
  return {
    if (auto) 'auto': true,
    'provider': provider,
    if (!auto && model != null && model.isNotEmpty) 'model': model,
    if (auto && sticky != null) 'sticky_provider': sticky.provider,
    if (auto && sticky != null) 'sticky_model': sticky.model,
    'messages': history,
    'temperature': 0.7,
    'inject_context': injectContext,
    'context_module': ?contextModule,
    'context_id': ?contextId,
    'context_title': ?contextTitle,
    'conversation_id': ?conversationId,
    'enable_tools': true,
    if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
    'stream': true,
  };
}

/// Download chips from `done.toolResults` (web `downloadsFromToolResults`).
List<Map<String, dynamic>> aiDownloadsFromToolResults(dynamic toolResults) {
  final out = <Map<String, dynamic>>[];
  for (final tr in _maps(toolResults)) {
    final r = tr['result'] is Map ? Map<String, dynamic>.from(tr['result'] as Map) : tr;
    if (r['downloadUrl'] != null) {
      final name = '${r['fileName'] ?? 'download'}';
      out.add({
        'url': r['downloadUrl'],
        'fileName': name,
        'expiresAt': r['expiresAt'],
        'tool': tr['name'] ?? r['format'] ?? 'file',
        'format': r['format'] ?? name.split('.').last.toUpperCase(),
      });
    }
    for (final d in _maps(r['downloads'])) {
      if (d['downloadUrl'] == null) continue;
      out.add({'url': d['downloadUrl'], 'fileName': d['fileName'] ?? 'download', 'expiresAt': d['expiresAt'], 'tool': tr['name'] ?? 'export_document', 'format': d['format']});
    }
  }
  return out;
}

/// One server-sent event of `/api/ai/chat` (`data: {type, ...}`).
class AiStreamEvent {
  const AiStreamEvent(this.type, this.data);
  final String type; // token | status | tool_plan | tool_start | tool_done | auto_route | skill_plan | tool_proposal | done | error
  final Map<String, dynamic> data;

  String get token => '${data['content'] ?? ''}';
}

/// Splits an SSE byte stream into events: `data:` lines joined until a blank
/// line; `:` comments (heartbeats) and unknown frames are skipped.
Stream<AiStreamEvent> parseAiSse(Stream<String> chunks) async* {
  var buf = '';
  final data = <String>[];
  AiStreamEvent? flush() {
    if (data.isEmpty) return null;
    final raw = data.join('\n');
    data.clear();
    if (raw.trim() == '[DONE]') return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final m = Map<String, dynamic>.from(j);
        return AiStreamEvent('${m['type'] ?? 'token'}', m);
      }
    } catch (_) {}
    return null;
  }

  await for (final chunk in chunks) {
    buf += chunk;
    while (true) {
      final i = buf.indexOf('\n');
      if (i < 0) break;
      var line = buf.substring(0, i);
      buf = buf.substring(i + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty) {
        final ev = flush();
        if (ev != null) yield ev;
      } else if (line.startsWith(':')) {
        continue; // heartbeat
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
  }
  if (buf.trim().startsWith('data:')) data.add(buf.trim().substring(5).trimLeft());
  final last = flush();
  if (last != null) yield last;
}

/// Thai label of a stream status (web `AiWaitingIndicator`).
String aiStatusLabel(AiStreamEvent? ev) {
  if (ev == null) return 'กำลังคิด…';
  final d = ev.data;
  if (ev.type == 'tool_start') {
    final l = '${d['label_th'] ?? d['label'] ?? ''}';
    return l.isNotEmpty ? l : 'กำลังใช้ ${d['name'] ?? 'เครื่องมือ'}…';
  }
  if (ev.type == 'auto_route') return 'กำลังเลือกโมเดล…';
  switch ('${d['phase'] ?? ''}') {
    case 'tools':
      return 'กำลังใช้เครื่องมือ…';
    case 'stall_retry':
    case 'empty_summary_retry':
      return 'กำลังลองอีกครั้ง…';
    case 'finalizing':
      return 'กำลังเตรียมคำตอบ…';
    case 'streaming_answer':
      return 'กำลังตอบ…';
    case 'vision':
      return 'กำลังอ่านรูป / PDF สแกน…';
  }
  return 'กำลังคิด…';
}

/// Short model name for the badge above a reply.
String aiModelBadge(String? provider, String? model) {
  final m = (model ?? '').trim();
  if (m.isNotEmpty) return m;
  final p = (provider ?? '').trim();
  return p.isEmpty || p == 'auto' ? 'Auto' : p[0].toUpperCase() + p.substring(1);
}

/// Quota meter from `/ai/usage` (web `AiUsageStrip`).
class AiUsageView {
  const AiUsageView({this.plan, this.quota, this.remaining, this.dailyLimit = 0, this.dailyRemaining, this.alternatives = const []});
  final String? plan;
  final num? quota;
  final num? remaining;
  final num dailyLimit;
  final num? dailyRemaining;
  final List<Map<String, dynamic>> alternatives;

  /// Only cloud-metered plans show a meter.
  static AiUsageView? from(Map<String, dynamic>? u) {
    if (u == null || u['meters_cloud'] != true) return null;
    final plan = u['plan'] is Map ? '${(u['plan'] as Map)['name'] ?? (u['plan'] as Map)['code'] ?? ''}' : null;
    final daily = u['modelDaily'] is Map ? Map<String, dynamic>.from(u['modelDaily'] as Map) : null;
    return AiUsageView(
      plan: plan == null || plan.isEmpty ? null : plan,
      quota: num.tryParse('${u['quota'] ?? ''}'),
      remaining: num.tryParse('${u['remaining'] ?? ''}'),
      dailyLimit: num.tryParse('${daily?['limit'] ?? ''}') ?? 0,
      dailyRemaining: num.tryParse('${daily?['remaining'] ?? ''}'),
      alternatives: _maps(u['alternatives']),
    );
  }

  double get usedFraction {
    final q = quota, r = remaining;
    if (q == null || q <= 0 || r == null) return 0;
    return (1 - (r / q)).clamp(0, 1).toDouble();
  }

  bool get exhausted => remaining != null && remaining! <= 0;
  bool get low => !exhausted && quota != null && quota! > 0 && remaining != null && remaining! / quota! < 0.1;
  bool get dailyExhausted => dailyRemaining != null && dailyRemaining! <= 0;

  /// Suggest switching models when the month or this model's day runs low.
  bool get suggestSwitch => alternatives.isNotEmpty && (exhausted || low || dailyExhausted);
}

/// 12 345 → "12.3K", 1 200 000 → "1.2M" (web `formatTokenCount`).
String aiTokenCount(num? n) {
  if (n == null) return '—';
  final a = n.abs();
  if (a >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (a >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '${n.round()}';
}

/// Providers and models the business allows (`/ai/model-policy`); null when
/// the server has no policy (everything allowed).
class AiModelPolicy {
  const AiModelPolicy(this.policies, this.catalogs);
  final Map<String, Map<String, dynamic>> policies;
  final Map<String, Map<String, dynamic>> catalogs;

  factory AiModelPolicy.fromJson(Map<String, dynamic> j) {
    Map<String, Map<String, dynamic>> m(dynamic v) =>
        v is Map ? {for (final e in v.entries) '${e.key}': e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{}} : {};
    return AiModelPolicy(m(j['policies']), m(j['catalogs']));
  }

  bool providerEnabled(String p) => policies[p]?['provider_enabled'] != false;

  /// Models to list for [p]: the catalog filtered by `enabled_models` when set;
  /// null when the catalog is unknown (ask `/ai/models`).
  List<String>? models(String p) {
    final cat = catalogs[p];
    if (cat == null || cat['models'] is! List) return null;
    final all = [for (final x in cat['models'] as List) '$x'].where((e) => e.isNotEmpty).toList();
    final allow = policies[p]?['enabled_models'];
    if (allow is List && allow.isNotEmpty) {
      final set = {for (final x in allow) '$x'};
      return all.where(set.contains).toList();
    }
    return all;
  }

  bool configured(String p) => catalogs[p]?['configured'] != false;
}
