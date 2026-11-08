/// Isaac sticker states — the 60 states of the web
/// (`pages/ai-assistant/lib/isaacStates.js` + `aiStickerRegistry.js`), with
/// the same "which mood when" rules (`resolveIsaacState`).
const kIsaacStates = [
  'idle', 'hello', 'thinking', 'listening', 'speaking', 'happy', 'celebrate', 'confused', 'surprised', 'love',
  'sad', 'sleepy', 'focused', 'skeptical', 'confident', 'curious', 'idea', 'reading', 'analyzing', 'wink',
  'determined', 'embarrassed', 'worried', 'relieved', 'thinking_dots', 'searching', 'ingesting', 'composing', 'summarizing', 'translating',
  'coding', 'verifying', 'connecting', 'clarifying', 'retrying', 'done', 'overthinking', 'computer_typing', 'book_overload', 'brainstorming',
  'image_creating', 'data_sorting', 'multitasking', 'learning', 'debugging', 'planning', 'explaining', 'handoff', 'flower_peace', 'scheming_rub',
  'glasses_check', 'puzzled_shrug', 'scholar', 'guitar_rock', 'skateboard', 'weightlift', 'cowboy', 'magician', 'error', 'unsupported',
];

/// Thai label per state (the web file's Thai text is mis-encoded; these are the intended labels).
const kIsaacLabels = {
  'idle': 'พร้อมช่วย', 'hello': 'สวัสดี', 'thinking': 'กำลังคิด', 'listening': 'กำลังฟัง', 'speaking': 'กำลังตอบ',
  'happy': 'ดีใจ', 'celebrate': 'สำเร็จแล้ว', 'confused': 'สงสัย', 'surprised': 'ประหลาดใจ', 'love': 'ขอบคุณ',
  'sad': 'เสียใจ', 'sleepy': 'ง่วง', 'focused': 'จดจ่อ', 'skeptical': 'ไม่ค่อยเชื่อ', 'confident': 'มั่นใจ',
  'curious': 'อยากรู้', 'idea': 'คิดออกแล้ว', 'reading': 'อ่านหนังสือ', 'analyzing': 'วิเคราะห์', 'wink': 'รู้กันนะ',
  'determined': 'มุ่งมั่น', 'embarrassed': 'เขิน', 'worried': 'กังวล', 'relieved': 'โล่งใจ', 'thinking_dots': 'คิดแบบสามจุด',
  'searching': 'ค้นหาข้อมูล', 'ingesting': 'รับและอ่านไฟล์', 'composing': 'กำลังเขียนคำตอบ', 'summarizing': 'สรุปใจความ', 'translating': 'แปลภาษา',
  'coding': 'เขียนโค้ด', 'verifying': 'ตรวจสอบคำตอบ', 'connecting': 'เชื่อมต่อเครื่องมือ', 'clarifying': 'ขอข้อมูลเพิ่ม', 'retrying': 'ลองอีกครั้ง',
  'done': 'คำตอบพร้อมแล้ว', 'overthinking': 'คิดจนไฟลุก', 'computer_typing': 'พิมพ์คอมพิวเตอร์', 'book_overload': 'อ่านจนหนังสือท่วม', 'brainstorming': 'ระดมไอเดีย',
  'image_creating': 'สร้างภาพ', 'data_sorting': 'จัดระเบียบข้อมูล', 'multitasking': 'ทำหลายงาน', 'learning': 'เรียนรู้สิ่งใหม่', 'debugging': 'แก้บั๊ก',
  'planning': 'วางแผนงาน', 'explaining': 'อธิบายคำตอบ', 'handoff': 'ส่งต่อให้เจ้าหน้าที่', 'flower_peace': 'สายชิลชูสองนิ้ว', 'scheming_rub': 'ยืนถูมือเจ้าเล่ห์',
  'glasses_check': 'จับแว่นมองชัด ๆ', 'puzzled_shrug': 'งงแล้วยักไหล่', 'scholar': 'บัณฑิตอธิบาย', 'guitar_rock': 'ร็อกกีตาร์', 'skateboard': 'เล่นสเก็ตบอร์ด',
  'weightlift': 'ยกดัมเบล', 'cowboy': 'คาวบอยเปิดหมวก', 'magician': 'นักมายากล', 'error': 'เกิดข้อผิดพลาด', 'unsupported': 'ทำรายการนี้ไม่ได้',
};

/// How long the "done" mood shows after an answer (web `duration`).
const kIsaacDoneMs = 3200;

String normalizeIsaacState(String? s) {
  final raw = (s ?? '').trim();
  if (kIsaacStates.contains(raw)) return raw;
  return const {'welcome': 'hello', 'tool_busy': 'connecting', 'streaming': 'speaking', 'answered': 'happy', 'clarify': 'clarifying', 'idle_after_answer': 'flower_peace'}[raw] ?? 'idle';
}

/// Tool / skill → mood (web `mapToolOrSkillToState`).
String? isaacStateForTool(String? toolName, [List<String> skills = const []]) {
  final t = (toolName ?? '').toLowerCase();
  if (skills.length > 1) return 'multitasking';
  bool has(String s) => skills.contains(s);
  bool m(String re) => RegExp(re).hasMatch(t);
  if (has('web-lookup') || m(r'search|web|lookup|browse')) return 'searching';
  if (has('analytics') || m(r'analy|report|metric')) return 'analyzing';
  if (m(r'image_gen|create_image|dall|draw_image')) return 'image_creating';
  if (has('vision-extract') || m(r'vision|ocr|screenshot')) return 'ingesting';
  if (has('document-work-breakdown') || has('workspace') || m(r'plan|wbs|workspace_tree')) return 'planning';
  if (has('crm-entity') || m(r'bulk|csv|import|export_entity|list_')) return 'data_sorting';
  if (has('document-edit') || has('document-authoring') || m(r'document_edit|author')) return 'computer_typing';
  if (has('document-export') || m(r'generate_document|export.*doc|pdf')) return 'guitar_rock';
  if (has('case') || has('call-log')) return 'focused';
  if (has('job') || m(r'agent_job|job_worker')) return 'determined';
  if (has('clarify')) return 'clarifying';
  if (has('social') || has('sales')) return 'brainstorming';
  if (m(r'debug|fix_bug|stack.?trace')) return 'debugging';
  if (m(r'code|script|typescript|javascript|python')) return 'coding';
  if (m(r'translat|แปล')) return 'translating';
  if (m(r'summar|สรุป')) return 'summarizing';
  if (m(r'learn|ingest_knowledge|add_source')) return 'learning';
  if (m(r'knowledge|notebook|source|read_file')) return 'reading';
  if (m(r'materialize|workspace.*create')) return 'weightlift';
  return null;
}

/// Mood for the chat right now (web `resolveIsaacState`, the parts the app has).
String resolveIsaacState({
  bool welcome = false,
  bool error = false,
  bool unsupported = false,
  bool aborted = false,
  bool providerNotReady = false,
  bool dailyLow = false,
  bool composerFocused = false,
  int draftLength = 0,
  bool loading = false,
  bool streaming = false,
  String? phase,
  String? toolName,
  List<String> skills = const [],
  bool hasAskUser = false,
  bool hasFollowups = false,
  bool hasDownloads = false,
  int attachmentCount = 0,
  int? elapsedMs,
  int? firstTokenMs,
  int? finishedAgoMs,
  bool simpleQa = false,
}) {
  final p = (phase ?? '').toLowerCase();
  if (welcome) return 'hello';
  if (unsupported) return 'unsupported';
  if (error) return 'error';
  if (aborted) return 'embarrassed';
  if (dailyLow) return 'skeptical';
  if (providerNotReady) return 'worried';
  if (composerFocused && draftLength >= 1 && !loading && !streaming) return 'listening';
  if (!loading && !streaming) {
    if (hasAskUser || hasFollowups || skills.contains('clarify')) return 'clarifying';
    if (hasDownloads) return 'celebrate';
    if (finishedAgoMs != null && finishedAgoMs >= 0 && finishedAgoMs < kIsaacDoneMs) return 'done';
    if (finishedAgoMs != null) return simpleQa ? 'happy' : 'flower_peace';
    return 'idle';
  }
  if (p == 'stall_retry' || p == 'empty_summary_retry') return 'retrying';
  if (p == 'finalizing') return 'composing';
  if (p == 'streaming_answer' || (streaming && !loading)) {
    if (firstTokenMs != null && firstTokenMs < 400) return 'surprised';
    return 'speaking';
  }
  if (p == 'vision' || p == 'ocr' || p == 'extracting' || attachmentCount > 0) {
    return attachmentCount > 1 ? 'book_overload' : 'ingesting';
  }
  if (p == 'tool_done') return 'verifying';
  if (toolName != null && toolName.isNotEmpty) return isaacStateForTool(toolName, skills) ?? 'connecting';
  if (skills.length > 1) return 'multitasking';
  if (elapsedMs != null && elapsedMs > 12000) return 'overthinking';
  if (p == 'thinking' || p == 'routing' || p == 'auto') return 'thinking';
  return 'thinking_dots';
}
