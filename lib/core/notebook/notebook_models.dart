import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../i18n.dart';
import '../thai_time.dart';
import 'notebook_appearance.dart';

export 'notebook_appearance.dart';

/// ISAAC Notebook (NEXTX `/api/ai/notebooks*`) — models and pure helpers for
/// the native notebook (library, sources, chat with citations, studio).

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];
int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
bool _bool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  return s == 'true' || s == '1';
}

String? _str(dynamic v) {
  final s = v?.toString();
  return s == null || s.isEmpty || s == 'null' ? null : s;
}

class Notebook {
  Notebook({
    required this.id,
    this.title = '',
    this.description = '',
    this.visibility = 'private',
    this.conversationId,
    this.userId,
    this.sourceCount,
    this.enabledSourceCount,
    this.canWrite = true,
    this.createdAt,
    this.updatedAt,
    this.sources,
    this.notes,
    this.chatSettings,
    this.appearance,
    this.serverHasAppearance = false,
  });

  final String id;
  String title;
  String description;

  /// `private` | `business`.
  String visibility;
  String? conversationId;
  final String? userId;
  final int? sourceCount;
  final int? enabledSourceCount;
  final bool canWrite;
  final String? createdAt;
  String? updatedAt;

  /// Only on `GET /notebooks/:id`.
  List<NotebookSource>? sources;
  List<NotebookNote>? notes;

  /// `chat_settings` (NEXTX notebook v5); null on older servers.
  ChatSettings? chatSettings;

  /// `appearance` (NEXTX notebook v6): null when never chosen or on an older server.
  NotebookAppearance? appearance;

  /// The server sent an `appearance` key (v6+), so it stores what we PATCH.
  final bool serverHasAppearance;

  /// The user's pick kept on the device ([NotebookAppearanceStore]), used when the server has none.
  NotebookAppearance? localAppearance;

  /// What the card shows: server → device → colour / icon from the title.
  NotebookAppearance get look => appearance ?? localAppearance ?? NotebookAppearance.forTitle(title);

  bool get pinned => look.pinned;

  bool get isBusiness => visibility == 'business';

  /// Sources shown on the card: the list when loaded, else the server count.
  int get sourcesTotal => sources?.length ?? sourceCount ?? 0;

  factory Notebook.fromJson(Map<String, dynamic> m) => Notebook(
        id: '${m['id']}',
        title: '${m['title'] ?? ''}',
        description: '${m['description'] ?? ''}',
        visibility: '${m['visibility'] ?? 'private'}',
        conversationId: _str(m['conversation_id']),
        userId: _str(m['user_id']),
        sourceCount: _int(m['source_count']),
        enabledSourceCount: _int(m['enabled_source_count']),
        canWrite: _bool(m['can_write'], fallback: true),
        createdAt: _str(m['created_at']),
        updatedAt: _str(m['updated_at'] ?? m['created_at']),
        sources: m['sources'] is List ? [for (final s in _maps(m['sources'])) NotebookSource.fromJson(s)] : null,
        notes: m['notes'] is List ? [for (final n in _maps(m['notes'])) NotebookNote.fromJson(n)] : null,
        chatSettings: m['chat_settings'] is Map ? ChatSettings.fromJson(_map(m['chat_settings'])) : null,
        appearance: NotebookAppearance.tryParse(m['appearance']),
        serverHasAppearance: m.containsKey('appearance'),
      );

  /// Keeps loaded sources / notes when a PATCH returns only the notebook row.
  Notebook merge(Notebook fresh) {
    fresh.sources ??= sources;
    fresh.notes ??= notes;
    fresh.chatSettings ??= chatSettings;
    fresh.localAppearance ??= localAppearance;
    if (!fresh.serverHasAppearance) fresh.appearance ??= appearance;
    return fresh;
  }
}

/// How ISAAC answers in this notebook's chat (`PATCH /notebooks/:id {chat_settings}`).
class ChatSettings {
  const ChatSettings({this.goal = 'default', this.customPrompt, this.persona, this.length = 'default'});

  /// default | learning_guide | custom
  final String goal;
  final String? customPrompt;
  final String? persona;

  /// shorter | default | longer
  final String length;

  static const defaults = ChatSettings();
  static const goals = ['default', 'learning_guide', 'custom'];
  static const lengths = ['shorter', 'default', 'longer'];
  static const customPromptMax = 4000;
  static const personaMax = 500;

  factory ChatSettings.fromJson(Map<String, dynamic> m) {
    final g = '${m['goal'] ?? 'default'}';
    final l = '${m['length'] ?? 'default'}';
    return ChatSettings(
      goal: goals.contains(g) ? g : 'default',
      customPrompt: _str(m['custom_prompt']),
      persona: _str(m['persona']),
      length: lengths.contains(l) ? l : 'default',
    );
  }

  Map<String, dynamic> toJson() => {
        'goal': goal,
        'custom_prompt': (customPrompt ?? '').trim().isEmpty ? null : customPrompt!.trim(),
        'persona': (persona ?? '').trim().isEmpty ? null : persona!.trim(),
        'length': length,
      };

  /// Nothing changed from the defaults (no indicator in the chat).
  bool get isDefault => goal == 'default' && length == 'default' && (persona ?? '').trim().isEmpty;

  /// "ผู้ช่วยการเรียนรู้ · สั้นลง" (Thai; wrap each part with tr()).
  List<String> get summaryParts => [
        if (goal != 'default') chatGoalLabel(goal),
        if ((persona ?? '').trim().isNotEmpty) 'บทบาทกำหนดเอง',
        if (length != 'default') chatLengthLabel(length),
      ];
}

String chatGoalLabel(String goal) => switch (goal) {
      'learning_guide' => 'ผู้ช่วยการเรียนรู้',
      'custom' => 'กำหนดเอง',
      _ => 'ค่าเริ่มต้น',
    };

String chatLengthLabel(String length) => switch (length) {
      'shorter' => 'สั้นลง',
      'longer' => 'ยาวขึ้น',
      _ => 'ปกติ',
    };

/// Library filters (ของฉัน / แชร์กับฉัน / ทั้งธุรกิจ).
enum NotebookScope { all, mine, shared, business }

/// Which filter a notebook belongs to for [meId].
NotebookScope notebookScopeOf(Notebook n, String? meId) {
  if (n.userId != null && meId != null && n.userId == meId) return NotebookScope.mine;
  if (n.isBusiness) return NotebookScope.business;
  return NotebookScope.shared;
}

/// Filtered by scope + search, pinned books first (server order kept inside each group).
List<Notebook> filterNotebooks(List<Notebook> all, {NotebookScope scope = NotebookScope.all, String query = '', String? meId}) {
  final q = query.trim().toLowerCase();
  final hits = [
    for (final n in all)
      if ((scope == NotebookScope.all || notebookScopeOf(n, meId) == scope) &&
          (q.isEmpty || n.title.toLowerCase().contains(q) || n.description.toLowerCase().contains(q)))
        n,
  ];
  return pinnedFirst(hits);
}

/// Stable: pinned notebooks first, otherwise the given order.
List<Notebook> pinnedFirst(List<Notebook> list) => [...list.where((n) => n.pinned), ...list.where((n) => !n.pinned)];

/// Cover colours + emoji from the notebook id (stable per notebook).
({List<Color> colors, String emoji}) notebookCover(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  const palettes = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF0EA5E9), Color(0xFF6366F1)],
    [Color(0xFF10B981), Color(0xFF0EA5E9)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFFEC4899), Color(0xFF8B5CF6)],
    [Color(0xFF14B8A6), Color(0xFF22C55E)],
    [Color(0xFFF97316), Color(0xFFF43F5E)],
    [Color(0xFF64748B), Color(0xFF6366F1)],
  ];
  const emojis = ['📘', '🧠', '💡', '📊', '🗂️', '🧭', '🚀', '📝', '🔬', '🎯', '🌱', '📚'];
  return (colors: palettes[h % palettes.length], emoji: emojis[(h ~/ 7) % emojis.length]);
}

/// "5 นาทีที่แล้ว" style label (Thai time).
String notebookRelativeTime(String? raw, {DateTime? now}) {
  final d = parseThai(raw ?? '');
  if (d == null) return '';
  final diff = (now ?? thaiNow()).difference(d);
  if (diff.inMinutes < 1) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
  return '${d.day}/${d.month}/${uiYear(d.year)}';
}

// ------------------------------------------------------------------ sources

enum NotebookSourceStatus { processing, ready, error, empty }

class NotebookSource {
  NotebookSource({
    required this.id,
    this.kind = 'manual',
    this.knowledgeId,
    this.attachmentId,
    this.title = '',
    this.excerpt = '',
    this.content = '',
    this.enabled = true,
    this.sortOrder = 0,
    this.config = const {},
    this.updatedAt,
  });

  final String id;

  /// manual | file | url | library | crm_module | picklist
  final String kind;
  final String? knowledgeId;
  final String? attachmentId;
  String title;
  String excerpt;
  String content;
  bool enabled;
  int sortOrder;
  Map<String, dynamic> config;
  final String? updatedAt;

  factory NotebookSource.fromJson(Map<String, dynamic> m) => NotebookSource(
        id: '${m['id']}',
        kind: '${m['source_kind'] ?? 'manual'}',
        knowledgeId: _str(m['knowledge_id']),
        attachmentId: _str(m['attachment_id'] ?? _map(m['source_config'])['attachment_id']),
        title: '${m['title'] ?? ''}',
        excerpt: '${m['excerpt'] ?? ''}',
        content: '${m['content'] ?? ''}',
        enabled: _bool(m['enabled'], fallback: true),
        sortOrder: _int(m['sort_order']) ?? 0,
        config: _map(m['source_config']),
        updatedAt: _str(m['updated_at']),
      );

  String? get url => _str(config['url']);

  /// YouTube links are sent as `url` sources for now (server fetches later).
  bool get isYoutube => kind == 'url' && ('${config['source'] ?? ''}' == 'youtube' || isYoutubeUrl(url ?? title));

  /// Why fetching a link failed (`blocked_url`, `http_error`, `timeout`, …), null when fine.
  String? get fetchError => _str(config['fetch_error']);

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final u = url;
    if (u != null) return Uri.tryParse(u)?.host ?? u;
    return 'แหล่งข้อมูล';
  }

  /// Text to read: full content, else the excerpt.
  String get body => content.trim().isNotEmpty ? content : excerpt;

  /// processing / ready / error from the attachment's `extract_status`
  /// (kept in `source_config`); a source without any text is "empty".
  NotebookSourceStatus get status {
    final s = '${config['extract_status'] ?? config['status'] ?? ''}'.toLowerCase();
    if (s == 'pending' || s == 'processing' || s == 'queued' || s == 'running') return NotebookSourceStatus.processing;
    if (s == 'error' || s == 'failed' || s == 'unsupported' || fetchError != null) return NotebookSourceStatus.error;
    if (body.trim().isEmpty) return NotebookSourceStatus.empty;
    return NotebookSourceStatus.ready;
  }

  String? get error {
    final f = fetchError;
    if (f != null) return _str(config['fetch_error_message']) ?? fetchErrorLabel(f);
    return _str(config['extract_error'] ?? config['error']);
  }
}

/// Thai text of a link fetch failure (server `fetch_error`).
String fetchErrorLabel(String code) => switch (code) {
      'blocked_url' => 'ลิงก์นี้ถูกบล็อกเพื่อความปลอดภัย',
      'http_error' => 'เปิดหน้าเว็บไม่สำเร็จ',
      'timeout' => 'หน้าเว็บตอบช้าเกินไป',
      'unsupported_type' => 'ไม่รองรับไฟล์ชนิดนี้จากลิงก์',
      'empty_content' => 'ไม่พบเนื้อหาในหน้าเว็บ',
      _ => 'ดึงเนื้อหาจากลิงก์ไม่สำเร็จ',
    };

bool isYoutubeUrl(String s) {
  final u = Uri.tryParse(s.trim());
  final host = (u?.host ?? '').toLowerCase();
  return host.endsWith('youtube.com') || host == 'youtu.be' || host.endsWith('.youtu.be');
}

/// Normalises a typed link: adds https:// when there is no scheme.
String? normalizeWebUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final u = Uri.tryParse(s);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || !u.host.contains('.')) return null;
  return u.toString();
}

/// Thai label of a source kind.
String notebookSourceKindLabel(NotebookSource s) {
  if (s.isYoutube) return 'YouTube';
  switch (s.kind) {
    case 'file':
      return 'ไฟล์';
    case 'url':
      return 'เว็บไซต์';
    case 'library':
      return 'คลังความรู้';
    case 'crm_module':
      return 'ข้อมูล CRM';
    case 'picklist':
      return 'Picklist';
    case 'recording':
      return 'บันทึกเสียง';
    default:
      return 'ข้อความ';
  }
}

/// Body of `POST /notebooks/:id/sources/reorder` after moving the item at [oldIndex]
/// so it ends up at [newIndex] (indexes of the final list, like `onReorderItem`).
List<String> reorderedIds(List<NotebookSource> list, int oldIndex, int newIndex) {
  final ids = [for (final s in list) s.id];
  final id = ids.removeAt(oldIndex);
  ids.insert(newIndex.clamp(0, ids.length), id);
  return ids;
}

/// Ids as numbers when they are numeric (the server compares bigint ids).
List<Object> apiIds(Iterable<String> ids) => [for (final i in ids) int.tryParse(i) ?? i];

// -------------------------------------------------------------------- notes

class NotebookNote {
  NotebookNote({
    required this.id,
    this.title = '',
    this.content = '',
    this.kind = 'note',
    this.sourceMessageId,
    this.meta = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  String title;
  String content;

  /// note | report | table | mindmap | styleguide | flashcards | quiz | audio | video | infographic
  final String kind;
  final String? sourceMessageId;
  Map<String, dynamic> meta;
  final String? createdAt;
  String? updatedAt;

  factory NotebookNote.fromJson(Map<String, dynamic> m) => NotebookNote(
        id: '${m['id']}',
        title: '${m['title'] ?? ''}',
        content: '${m['content'] ?? ''}',
        kind: '${m['artifact_kind'] ?? 'note'}',
        sourceMessageId: _str(m['source_message_id']),
        meta: {..._map(m['meta']), if (m['download'] is Map && _map(m['meta'])['downloadUrl'] == null) ..._downloadMeta(_map(m['download']))},
        createdAt: _str(m['created_at']),
        updatedAt: _str(m['updated_at'] ?? m['created_at']),
      );

  static Map<String, dynamic> _downloadMeta(Map<String, dynamic> d) => {
        if (d['downloadUrl'] != null) 'downloadUrl': d['downloadUrl'],
        if (d['fileName'] != null) 'fileName': d['fileName'],
        if (d['expiresAt'] != null) 'expiresAt': d['expiresAt'],
      };

  String? get downloadUrl => _str(meta['downloadUrl'] ?? meta['download_url']);
  String get fileName => _str(meta['fileName'] ?? meta['file_name']) ?? 'download';

  bool get downloadExpired {
    final exp = parseThai('${meta['expiresAt'] ?? ''}');
    return exp != null && exp.isBefore(thaiNow());
  }

  StudioKind? get studio => StudioKind.of(kind);

  String get displayTitle => title.trim().isNotEmpty ? title.trim() : (studio?.label ?? 'โน้ต');

  /// One line under the title in the notes list.
  String get snippet {
    final k = kind;
    if (k == 'flashcards') {
      final n = parseFlashcards(content).length;
      if (n > 0) return '$n การ์ด';
    }
    if (k == 'quiz') {
      final n = parseQuiz(content).length;
      if (n > 0) return '$n ข้อ';
    }
    if (k == 'infographic') return 'อินโฟกราฟิก HTML';
    if (k == 'mindmap' || k == 'mindmap_json') {
      final tree = k == 'mindmap_json' ? meta['mindmap'] : null;
      final label = tree is Map && tree['root'] is Map ? _str((tree['root'] as Map)['label']) : null;
      if (label != null) return label;
      final root = parseMindmap(content);
      if (root != null) return root.label;
    }
    if (k == 'faq' && meta['faq'] is List && (meta['faq'] as List).isNotEmpty) return '${(meta['faq'] as List).length} คำถาม';
    if (k == 'timeline' && meta['timeline'] is List && (meta['timeline'] as List).isNotEmpty) return '${(meta['timeline'] as List).length} เหตุการณ์';
    final plain = content
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'[#*_>`|\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return plain.length > 120 ? '${plain.substring(0, 120)}…' : plain;
  }
}

// ------------------------------------------------------------------- studio

/// Studio outputs (server `aiNotebookStudioService.js`).
class StudioKind {
  const StudioKind(this.id, this.label, this.hint, this.icon, this.colors);
  final String id;
  final String label;
  final String hint;
  final IconData icon;
  final List<Color> colors;

  static const audio = StudioKind('audio', 'ภาพรวมเสียง', 'สรุปเป็นบทสนทนา ฟังได้', LucideIcons300.headphones, [Color(0xFF8B5CF6), Color(0xFF6366F1)]);
  static const report = StudioKind('report', 'รายงาน', 'เอกสารสรุปพร้อม PDF', LucideIcons300.fileText, [Color(0xFF475569), Color(0xFF1E293B)]);
  static const table = StudioKind('table', 'ตาราง', 'ข้อมูลเป็นตาราง + Excel', LucideIcons300.table2, [Color(0xFF3B82F6), Color(0xFF4F46E5)]);
  static const mindmap = StudioKind('mindmap', 'แผนผังความคิด', 'เห็นภาพรวมเป็นกิ่งก้าน', LucideIcons300.network, [Color(0xFFF43F5E), Color(0xFFEC4899)]);
  static const styleguide = StudioKind('styleguide', 'คู่มือสไตล์', 'โทนภาษาและคำที่ใช้', LucideIcons300.palette, [Color(0xFFF59E0B), Color(0xFFF97316)]);
  static const flashcards = StudioKind('flashcards', 'แฟลชการ์ด', 'การ์ดถาม–ตอบ ทบทวนเร็ว', LucideIcons300.galleryVerticalEnd, [Color(0xFFEF4444), Color(0xFFBE123C)]);
  static const quiz = StudioKind('quiz', 'แบบทดสอบ', 'ทดสอบความเข้าใจ มีคะแนน', LucideIcons300.listChecks, [Color(0xFF0EA5E9), Color(0xFF2563EB)]);
  static const video = StudioKind('video', 'วิดีโอ (สตอรีบอร์ด)', 'ฉากและบทพูดสำหรับวิดีโอ', LucideIcons300.clapperboard, [Color(0xFF10B981), Color(0xFF0D9488)]);
  static const infographic = StudioKind('infographic', 'อินโฟกราฟิก', 'การ์ด ไทม์ไลน์ หรือสถิติ', LucideIcons300.chartPie, [Color(0xFFEC4899), Color(0xFFC026D3)]);
  static const note = StudioKind('note', 'โน้ต', 'โน้ตของคุณ', LucideIcons300.stickyNote, [Color(0xFF6366F1), Color(0xFF8B5CF6)]);

  // Phase 3: native views from `meta` (markdown `content` as the fallback).
  static const studyGuide = StudioKind('study_guide', 'คู่มือการเรียน', 'แบบทดสอบ เรียงความ คำศัพท์', LucideIcons300.graduationCap, [Color(0xFF14B8A6), Color(0xFF0891B2)]);
  static const faq = StudioKind('faq', 'คำถามที่พบบ่อย', 'ถาม–ตอบจากแหล่งข้อมูล', LucideIcons300.messageCircleQuestion, [Color(0xFF0EA5E9), Color(0xFF6366F1)]);
  static const briefing = StudioKind('briefing', 'สรุปสำหรับผู้บริหาร', 'ประเด็นหลักและคำพูดสำคัญ', LucideIcons300.briefcaseBusiness, [Color(0xFF334155), Color(0xFF4F46E5)]);
  static const timeline = StudioKind('timeline', 'ไทม์ไลน์', 'ลำดับเหตุการณ์และบุคคล', LucideIcons300.calendarClock, [Color(0xFFF59E0B), Color(0xFFEA580C)]);
  static const mindmapJson = StudioKind('mindmap_json', 'แผนผังความคิด', 'แตะเพื่อขยายทีละกิ่ง', LucideIcons300.network, [Color(0xFFF43F5E), Color(0xFFEC4899)]);

  /// Made by the server from a notebook recording (not in the studio grid).
  static const meetingSummary = StudioKind('meeting_summary', 'สรุปการประชุม', 'สรุปจากบันทึกเสียง', LucideIcons300.audioLines, [Color(0xFFF43F5E), Color(0xFFBE123C)]);

  /// Grid order (most useful first).
  /// The interactive mind map (`mindmap_json`) replaces the Mermaid-only `mindmap` tile;
  /// older `mindmap` notes still open with their own viewer.
  static const all = [audio, studyGuide, briefing, faq, timeline, mindmapJson, report, flashcards, quiz, table, infographic, video, styleguide];

  static StudioKind? of(String id) {
    for (final k in [...all, mindmap, note, meetingSummary]) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// Infographic templates (`template_id`).
const kInfographicTemplates = [
  ('cards', 'การ์ด', 'กริดการ์ด 4–6 ช่อง'),
  ('timeline', 'ไทม์ไลน์', 'ลำดับเหตุการณ์'),
  ('stats', 'สถิติ', 'ตัวเลขและ KPI'),
];

/// Text of a background studio job phase (`progress.phase` / `state`).
String studioPhaseLabel(String phase) {
  switch (phase.toLowerCase()) {
    case '':
    case 'queued':
    case 'waiting':
    case 'delayed':
      return 'รอคิว…';
    case 'active':
    case 'running':
      return 'กำลังสร้าง…';
    case 'context':
    case 'sources':
      return 'กำลังอ่านแหล่งข้อมูล…';
    case 'llm':
    case 'generating':
      return 'ไอแซคกำลังเขียน…';
    case 'tts':
    case 'audio':
      return 'กำลังสร้างเสียง…';
    case 'export':
    case 'file':
      return 'กำลังทำไฟล์…';
    case 'done':
    case 'completed':
      return 'เสร็จแล้ว';
  }
  return 'กำลังสร้าง…';
}

dynamic _jsonBlob(String content) {
  final raw = content.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false).firstMatch(raw);
  var text = fence != null ? fence.group(1)!.trim() : raw;
  if (fence == null) {
    final a = text.indexOf('{'), b = text.lastIndexOf('}');
    if (a > 0 && b > a) text = text.substring(a, b + 1);
  }
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

class Flashcard {
  const Flashcard(this.front, this.back);
  final String front;
  final String back;
}

/// `{cards:[{q,a}]}` (also `prompt/answer`, `front/back`).
List<Flashcard> parseFlashcards(String content) {
  final j = _jsonBlob(content);
  final cards = j is Map ? j['cards'] : (j is List ? j : null);
  return [
    for (final c in _maps(cards))
      if ('${c['q'] ?? c['prompt'] ?? c['front'] ?? c['question'] ?? ''}'.trim().isNotEmpty)
        Flashcard('${c['q'] ?? c['prompt'] ?? c['front'] ?? c['question']}'.trim(), '${c['a'] ?? c['answer'] ?? c['back'] ?? ''}'.trim()),
  ];
}

class QuizQuestion {
  const QuizQuestion(this.prompt, this.options, this.answer, {this.explanation});
  final String prompt;
  final List<String> options;

  /// Index of the right option.
  final int answer;
  final String? explanation;
}

/// `{questions:[{prompt, options, answer}]}`; `answer` may be the index or the option text.
List<QuizQuestion> parseQuiz(String content) {
  final j = _jsonBlob(content);
  final qs = j is Map ? j['questions'] : (j is List ? j : null);
  final out = <QuizQuestion>[];
  for (final q in _maps(qs)) {
    final options = [for (final o in (q['options'] is List ? q['options'] as List : const [])) '$o'];
    final prompt = '${q['prompt'] ?? q['q'] ?? q['question'] ?? ''}'.trim();
    if (prompt.isEmpty || options.isEmpty) continue;
    final a = q['answer'] ?? q['correct'];
    var idx = _int(a) ?? options.indexOf('$a');
    if (idx < 0 || idx >= options.length) idx = 0;
    out.add(QuizQuestion(prompt, options, idx, explanation: _str(q['explanation'] ?? q['why'])));
  }
  return out;
}

/// Score of [picked] (question index → option index).
int quizScore(List<QuizQuestion> qs, Map<int, int> picked) {
  var s = 0;
  for (var i = 0; i < qs.length; i++) {
    if (picked[i] == qs[i].answer) s++;
  }
  return s;
}

class MindNode {
  MindNode(this.label, [List<MindNode>? children]) : children = children ?? [];
  final String label;
  final List<MindNode> children;

  int get size => 1 + children.fold<int>(0, (a, c) => a + c.size);
}

/// The ```mermaid block of a note (or the whole note when it is bare mermaid).
String? mermaidCode(String content) {
  final m = RegExp(r'```\s*mermaid\s*\n([\s\S]*?)```', caseSensitive: false).firstMatch(content);
  if (m != null) return m.group(1)!.trim();
  final t = content.trim();
  if (RegExp(r'^(mindmap|graph|flowchart)\b').hasMatch(t)) return t;
  return null;
}

String _mindLabel(String raw) {
  var s = raw.trim();
  // id((text)) / id(text) / id[text] / id{{text}} / id))text(( …
  final shape = RegExp(r'^[\w-]*\s*[\(\[\{\)]+(.*?)[\)\]\}\(]+$').firstMatch(s);
  if (shape != null && shape.group(1)!.trim().isNotEmpty) s = shape.group(1)!.trim();
  s = s.replaceAll(RegExp(r'::icon\([^)]*\)'), '').replaceAll(RegExp(r'^["`]+|["`]+$'), '').trim();
  return s;
}

/// Tree of a mermaid `mindmap` (indentation) or `graph`/`flowchart` (edges).
MindNode? parseMindmap(String content) {
  final code = mermaidCode(content);
  if (code == null) return null;
  final lines = code.split('\n').where((l) => l.trim().isNotEmpty && !l.trim().startsWith('%%')).toList();
  if (lines.isEmpty) return null;
  final head = lines.first.trim().toLowerCase();
  if (head.startsWith('mindmap')) {
    final stack = <(int, MindNode)>[];
    MindNode? root;
    for (final l in lines.skip(1)) {
      final indent = l.length - l.trimLeft().length;
      final label = _mindLabel(l);
      if (label.isEmpty) continue;
      final node = MindNode(label);
      if (root == null) {
        root = node;
        stack.add((indent, node));
        continue;
      }
      // Pop to the parent; anything at or left of the root hangs off the root.
      while (stack.length > 1 && stack.last.$1 >= indent) {
        stack.removeLast();
      }
      stack.last.$2.children.add(node);
      stack.add((indent, node));
    }
    return root;
  }
  if (head.startsWith('graph') || head.startsWith('flowchart')) {
    final labels = <String, String>{};
    final kids = <String, List<String>>{};
    final order = <String>[];
    final hasParent = <String>{};
    final nodeRe = RegExp(r'([\w-]+)\s*(?:\(\(([^)]*)\)\)|\(([^)]*)\)|\[([^\]]*)\]|\{([^}]*)\})?');
    String? take(String part) {
      final m = nodeRe.firstMatch(part.trim());
      if (m == null) return null;
      final id = m.group(1)!;
      final label = [for (var g = 2; g <= 5; g++) m.group(g)].firstWhere((x) => x != null && x.trim().isNotEmpty, orElse: () => null);
      if (label != null) labels[id] = label.trim().replaceAll('"', '');
      if (!order.contains(id)) order.add(id);
      return id;
    }

    for (final l in lines.skip(1)) {
      final parts = l.split(RegExp(r'\s*(?:-{2,}>|==>|-\.->|-{3,})(?:\|[^|]*\|)?\s*'));
      if (parts.length < 2) {
        take(l);
        continue;
      }
      String? prev;
      for (final p in parts) {
        if (p.trim().isEmpty) continue;
        final id = take(p);
        if (id == null) continue;
        if (prev != null && prev != id) {
          (kids[prev] ??= []).add(id);
          hasParent.add(id);
        }
        prev = id;
      }
    }
    if (order.isEmpty) return null;
    final rootId = order.firstWhere((id) => !hasParent.contains(id), orElse: () => order.first);
    final seen = <String>{};
    MindNode build(String id) {
      seen.add(id);
      return MindNode(labels[id] ?? id, [for (final k in kids[id] ?? const <String>[]) if (!seen.contains(k)) build(k)]);
    }

    return build(rootId);
  }
  return null;
}

// ----------------------------------------------------------------- citations

/// One matched passage of a citation: the quote and its `start..end` offsets
/// into the source `content` (null when the server could not place it).
class NotebookPassage {
  const NotebookPassage({required this.quote, this.chunkIndex, this.start, this.end});
  final String quote;
  final int? chunkIndex;
  final int? start;
  final int? end;

  factory NotebookPassage.fromJson(Map<String, dynamic> m) =>
      NotebookPassage(quote: '${m['quote'] ?? ''}'.trim(), chunkIndex: _int(m['chunk_index']), start: _int(m['start']), end: _int(m['end']));

  bool get hasRange => start != null && end != null && end! > start! && start! >= 0;
}

class NotebookCitation {
  const NotebookCitation({required this.n, this.sourceId, this.title = '', this.loc = '', this.quote, this.chunkIndex, this.passages = const []});
  final int n;
  final String? sourceId;
  final String title;
  final String loc;

  /// Exact passage (server ≥ notebook v2), shown in the citation sheet.
  final String? quote;
  final int? chunkIndex;

  /// Passages behind `[n]` (server ≥ notebook v5); empty on older answers.
  final List<NotebookPassage> passages;

  factory NotebookCitation.fromJson(Map<String, dynamic> m, int index) {
    final loc = '${m['loc'] ?? ''}';
    final fromLoc = int.tryParse(RegExp(r'\d+').firstMatch(loc)?.group(0) ?? '');
    return NotebookCitation(
      n: _int(m['n']) ?? fromLoc ?? index + 1,
      sourceId: _str(m['source_id'] ?? m['sourceId']),
      title: '${m['title'] ?? ''}',
      loc: loc,
      quote: _str(m['quote'] ?? m['snippet']),
      chunkIndex: _int(m['chunk_index']),
      passages: [for (final p in _maps(m['passages'])) if ('${p['quote'] ?? ''}'.trim().isNotEmpty || _int(p['start']) != null) NotebookPassage.fromJson(p)],
    );
  }

  static List<NotebookCitation> list(List<Map<String, dynamic>> raw) => [for (final (i, c) in raw.indexed) NotebookCitation.fromJson(c, i)];
}

NotebookCitation? citationFor(List<NotebookCitation> list, int n) {
  for (final c in list) {
    if (c.n == n) return c;
  }
  return null;
}

/// Turns inline `[1]` / `[1, 2]` markers into `nxcite:` links so they can be
/// tapped inside the rendered markdown. Fenced code and existing links stay.
String linkCitations(String text, {Set<int>? known}) {
  final parts = text.split('```');
  final re = RegExp(r'(?<![\]\\!])\[(\d{1,3}(?:\s*[,،、]\s*\d{1,3})*)\](?![\(\[:])');
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i].replaceAllMapped(re, (m) {
      final nums = [for (final x in m.group(1)!.split(RegExp(r'[,،、]'))) int.tryParse(x.trim())].whereType<int>().toList();
      if (nums.isEmpty || (known != null && known.isNotEmpty && !nums.every(known.contains))) return m.group(0)!;
      return nums.map((n) => '[\\[$n\\]](nxcite:$n)').join();
    });
  }
  return parts.join('```');
}

/// `nxcite:3` → 3.
int? citationFromHref(String href) => href.startsWith('nxcite:') ? int.tryParse(href.substring(7)) : null;

/// Where [quote] sits in [content] (whitespace-insensitive), or null.
({int start, int end})? findQuote(String content, String? quote) {
  final q = (quote ?? '').trim();
  if (q.isEmpty || content.isEmpty) return null;
  final i = content.indexOf(q);
  if (i >= 0) return (start: i, end: i + q.length);
  // Loose match: collapse whitespace on both sides.
  final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map(RegExp.escape).toList();
  if (words.isEmpty) return null;
  final m = RegExp(words.join(r'\s+')).firstMatch(content);
  if (m != null) return (start: m.start, end: m.end);
  // First 40 characters as a fallback anchor.
  if (q.length > 40) return findQuote(content, q.substring(0, 40));
  return null;
}

/// Where to highlight a cited passage in [content]: the server offsets when they
/// fit (and still match the quote), else a search for [quote], else null.
({int start, int end})? passageRange(String content, {int? start, int? end, String? quote}) {
  if (start != null && end != null && start >= 0 && end > start && end <= content.length) {
    final q = (quote ?? '').trim();
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final slice = content.substring(start, end);
    if (q.isEmpty || norm(slice) == norm(q) || norm(slice).contains(norm(q)) || norm(q).contains(norm(slice))) return (start: start, end: end);
  }
  return findQuote(content, quote);
}

// --------------------------------------------------------------------- guide

class NotebookGuide {
  const NotebookGuide({this.summary = '', this.topics = const [], this.questions = const [], this.generatedAt, this.stale = false, this.fallback = false});
  final String summary;
  final List<String> topics;
  final List<String> questions;
  final String? generatedAt;
  final bool stale;

  /// The server has no guide endpoint yet: fixed prompts are shown.
  final bool fallback;

  bool get isEmpty => summary.trim().isEmpty && topics.isEmpty && questions.isEmpty;

  factory NotebookGuide.fromJson(Map<String, dynamic> m) {
    final g = m['guide'] is Map ? _map(m['guide']) : m;
    List<String> strs(dynamic v) => [
          for (final x in (v is List ? v : const []))
            if ((x is Map ? '${x['label'] ?? x['title'] ?? x['text'] ?? x['question'] ?? ''}' : '$x').trim().isNotEmpty)
              (x is Map ? '${x['label'] ?? x['title'] ?? x['text'] ?? x['question']}' : '$x').trim(),
        ];
    return NotebookGuide(
      summary: '${g['summary'] ?? ''}'.trim(),
      topics: strs(g['topics']),
      questions: strs(g['questions'] ?? g['suggested_questions']),
      generatedAt: _str(g['generated_at']),
      stale: _bool(g['stale']),
    );
  }

  /// Fixed prompts when `/guide` is missing (older servers); topics = source titles.
  factory NotebookGuide.fallbackFor(List<NotebookSource> sources) => NotebookGuide(
        fallback: true,
        topics: [for (final s in sources.where((s) => s.enabled).take(5)) s.displayTitle],
        questions: const [
          'สรุปประเด็นสำคัญจากแหล่งข้อมูลทั้งหมด',
          'มีตัวเลขหรือข้อเท็จจริงสำคัญอะไรบ้าง',
          'แหล่งข้อมูลเหล่านี้เห็นตรงกันหรือขัดแย้งกันตรงไหน',
          'ควรทำอะไรต่อจากข้อมูลนี้',
        ],
      );
}

// -------------------------------------------------------------------- shares

class NotebookShare {
  const NotebookShare({required this.id, this.token = '', this.mode = 'read_only', this.targets = const [], this.createdAt});
  final String id;
  final String token;

  /// read_only | users | roles | business
  final String mode;
  final List<({String type, String id})> targets;
  final String? createdAt;

  factory NotebookShare.fromJson(Map<String, dynamic> m) => NotebookShare(
        id: '${m['id']}',
        token: '${m['token'] ?? ''}',
        mode: '${m['share_mode'] ?? 'read_only'}',
        targets: [for (final t in _maps(m['targets'])) (type: '${t['share_to_type']}', id: '${t['share_to_id']}')],
        createdAt: _str(m['created_at']),
      );

  String get modeLabel => switch (mode) {
        'users' => 'เฉพาะผู้ใช้ที่เลือก',
        'roles' => 'ตามบทบาท',
        'business' => 'ทุกคนในธุรกิจ',
        _ => 'ลิงก์อ่านอย่างเดียว',
      };

  /// Web path of the link (`/ai/notebook/public/:token` or the notebook page).
  String path(String notebookId) => mode == 'read_only' ? '/ai/notebook/public/$token' : '/ai/notebook/$notebookId';
}

/// Codes that mean the notebook feature is switched off for this business.
bool isNotebookDisabledCode(String code) {
  final c = code.toUpperCase();
  return c == 'AI_NOTEBOOK_DISABLED' || c == 'AI_FEATURE_DISABLED' || c.contains('FEATURE_DISABLED');
}
