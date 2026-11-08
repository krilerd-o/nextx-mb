/// Isaac sticker states — Isaac Bot V4, the same 60 states as the web
/// (`pages/ai-assistant/lib/isaacStates.js` + `aiStickerRegistry.js`), with
/// the same "which mood when" rules (`resolveIsaacState`).
const kIsaacStates = [
  'idle',
  'hello',
  'thinking',
  'listening',
  'speaking',
  'happy',
  'celebrate',
  'confused',
  'surprised',
  'love',
  'sad',
  'sleepy',
  'focused',
  'skeptical',
  'confident',
  'curious',
  'idea',
  'reading',
  'analyzing',
  'wink',
  'determined',
  'embarrassed',
  'worried',
  'relieved',
  'thinking_dots',
  'searching',
  'processing',
  'loading',
  'answer_ready',
  'typing',
  'connecting',
  'checking',
  'downloading',
  'uploading',
  'success',
  'retry',
  'overthinking',
  'computer',
  'book_flood',
  'brainstorm',
  'create_image',
  'organize_data',
  'multitask',
  'learning',
  'debug',
  'planning',
  'explaining',
  'human_handoff',
  'peace',
  'scheming',
  'adjust_glasses',
  'shrug',
  'graduate',
  'rock_guitar',
  'skateboard',
  'workout',
  'cowboy',
  'magician',
  'error',
  'unsupported',
];

/// Thai label per state.
const kIsaacLabels = {
  'idle': 'พร้อมช่วย',
  'hello': 'สวัสดี',
  'thinking': 'กำลังคิด',
  'listening': 'กำลังฟัง',
  'speaking': 'กำลังตอบ',
  'happy': 'ดีใจ',
  'celebrate': 'สำเร็จแล้ว',
  'confused': 'สงสัย',
  'surprised': 'ประหลาดใจ',
  'love': 'ขอบคุณ',
  'sad': 'เสียใจ',
  'sleepy': 'ง่วง',
  'focused': 'จดจ่อ',
  'skeptical': 'ไม่ค่อยเชื่อ',
  'confident': 'มั่นใจ',
  'curious': 'อยากรู้',
  'idea': 'คิดออกแล้ว',
  'reading': 'อ่านหนังสือ',
  'analyzing': 'วิเคราะห์',
  'wink': 'รู้กันนะ',
  'determined': 'มุ่งมั่น',
  'embarrassed': 'เขิน',
  'worried': 'กังวล',
  'relieved': 'โล่งใจ',
  'thinking_dots': 'คิดแบบสามจุด',
  'searching': 'ค้นหาข้อมูล',
  'processing': 'กำลังประมวลผล',
  'loading': 'กำลังเตรียม',
  'answer_ready': 'คำตอบพร้อมแล้ว',
  'typing': 'กำลังพิมพ์คำตอบ',
  'connecting': 'เชื่อมต่อเครื่องมือ',
  'checking': 'ตรวจสอบความถูกต้อง',
  'downloading': 'กำลังเตรียมไฟล์',
  'uploading': 'กำลังอัปโหลดไฟล์',
  'success': 'ทำรายการสำเร็จ',
  'retry': 'ลองอีกครั้ง',
  'overthinking': 'คิดจนไฟลุก',
  'computer': 'พิมพ์คอมพิวเตอร์',
  'book_flood': 'อ่านจนหนังสือท่วม',
  'brainstorm': 'ระดมไอเดีย',
  'create_image': 'สร้างภาพ',
  'organize_data': 'จัดระเบียบข้อมูล',
  'multitask': 'ทำหลายงาน',
  'learning': 'เรียนรู้สิ่งใหม่',
  'debug': 'แก้บั๊ก',
  'planning': 'วางแผนงาน',
  'explaining': 'อธิบายคำตอบ',
  'human_handoff': 'ส่งต่อให้เจ้าหน้าที่',
  'peace': 'สายชิลชูสองนิ้ว',
  'scheming': 'ยืนถูมือเจ้าเล่ห์',
  'adjust_glasses': 'จับแว่นมองชัด ๆ',
  'shrug': 'งงแล้วยักไหล่',
  'graduate': 'บัณฑิตอธิบาย',
  'rock_guitar': 'ร็อกกีตาร์',
  'skateboard': 'เล่นสเก็ตบอร์ด',
  'workout': 'ยกดัมเบล',
  'cowboy': 'คาวบอยเปิดหมวก',
  'magician': 'นักมายากล',
  'error': 'เกิดข้อผิดพลาด',
  'unsupported': 'ทำรายการนี้ไม่ได้',
};

/// One loop of a GIF (80 frames @ 25fps): how long "answer ready" shows.
const kIsaacDoneMs = 3200;

/// Older names (V3, logical aliases) → V4 state.
const _isaacAlias = {
  'welcome': 'hello', 'tool_busy': 'connecting', 'streaming': 'speaking', 'answered': 'happy', 'clarify': 'curious',
  'idle_after_answer': 'peace', 'ingesting': 'processing', 'composing': 'typing', 'summarizing': 'analyzing',
  'translating': 'typing', 'coding': 'computer', 'verifying': 'checking', 'clarifying': 'curious', 'retrying': 'retry',
  'done': 'answer_ready', 'computer_typing': 'computer', 'book_overload': 'book_flood', 'brainstorming': 'brainstorm',
  'image_creating': 'create_image', 'data_sorting': 'organize_data', 'multitasking': 'multitask', 'debugging': 'debug',
  'handoff': 'human_handoff', 'flower_peace': 'peace', 'scheming_rub': 'scheming', 'glasses_check': 'adjust_glasses',
  'puzzled_shrug': 'shrug', 'scholar': 'graduate', 'guitar_rock': 'rock_guitar', 'weightlift': 'workout',
};

String normalizeIsaacState(String? s) {
  final raw = (s ?? '').trim();
  if (kIsaacStates.contains(raw)) return raw;
  return _isaacAlias[raw] ?? 'idle';
}

/// Tool / skill → mood (web `mapToolOrSkillToState`).
String? isaacStateForTool(String? toolName, [List<String> skills = const []]) {
  final t = (toolName ?? '').toLowerCase();
  if (skills.length > 1) return 'multitask';
  bool has(String s) => skills.contains(s);
  bool m(String re) => RegExp(re).hasMatch(t);
  if (has('web-lookup') || m(r'search|web|lookup|browse')) return 'searching';
  if (has('analytics') || m(r'analy|report|metric')) return 'analyzing';
  if (m(r'image_gen|create_image|dall|draw_image')) return 'create_image';
  if (has('vision-extract') || m(r'vision|ocr|screenshot')) return 'processing';
  if (m(r'upload|attach')) return 'uploading';
  if (has('document-work-breakdown') || has('workspace') || m(r'plan|wbs|workspace_tree')) return 'planning';
  if (has('document-export') || m(r'generate_document|export|download|pdf|xlsx|docx')) return 'downloading';
  if (has('crm-entity') || m(r'bulk|csv|import|list_')) return 'organize_data';
  if (has('document-edit') || has('document-authoring') || m(r'document_edit|author')) return 'computer';
  if (has('case') || has('call-log')) return 'focused';
  if (has('job') || m(r'agent_job|job_worker')) return 'determined';
  if (has('clarify')) return 'curious';
  if (has('social') || has('sales')) return 'brainstorm';
  if (m(r'debug|fix_bug|stack.?trace')) return 'debug';
  if (m(r'code|script|typescript|javascript|python')) return 'computer';
  if (m(r'translat|แปล')) return 'typing';
  if (m(r'summar|สรุป')) return 'analyzing';
  if (m(r'learn|ingest_knowledge|add_source')) return 'learning';
  if (m(r'knowledge|notebook|source|read_file')) return 'reading';
  if (m(r'verify|validate|check')) return 'checking';
  if (m(r'materialize|workspace.*create')) return 'workout';
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
  bool actionConfirmed = false,
  bool uploading = false,
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
    if (hasAskUser || hasFollowups || skills.contains('clarify')) return 'curious';
    if (actionConfirmed) return 'success';
    if (hasDownloads) return 'celebrate';
    if (finishedAgoMs != null && finishedAgoMs >= 0 && finishedAgoMs < kIsaacDoneMs) return 'answer_ready';
    if (finishedAgoMs != null) return simpleQa ? 'happy' : 'peace';
    return 'idle';
  }
  if (p == 'stall_retry' || p == 'empty_summary_retry') return 'retry';
  if (p == 'finalizing') return 'typing';
  if (p == 'streaming_answer' || (streaming && !loading)) {
    if (firstTokenMs != null && firstTokenMs < 400) return 'surprised';
    return 'speaking';
  }
  if (uploading) return 'uploading';
  if (p == 'vision' || p == 'ocr' || p == 'extracting' || attachmentCount > 0) {
    if (attachmentCount > 1) return 'book_flood';
    if (attachmentCount > 0 && p.isEmpty) return 'uploading';
    return 'processing';
  }
  if (p == 'tool_done') return 'checking';
  if (toolName != null && toolName.isNotEmpty) return isaacStateForTool(toolName, skills) ?? 'connecting';
  if (skills.length > 1) return 'multitask';
  if (elapsedMs != null && elapsedMs > 12000) return 'overthinking';
  if (p == 'routing' || p == 'auto' || p == 'auto_route') return 'loading';
  if (p == 'thinking') return 'thinking';
  return 'thinking_dots';
}
