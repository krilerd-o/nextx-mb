import 'dart:convert';

/// Demo data for the ISAAC Notebook tests (NEXTX `/api/ai/notebooks*` shapes).

Map<String, dynamic> nbRow(int id, {String title = 'สมุด', int userId = 2, String visibility = 'private', int sources = 2, bool canWrite = true, String updated = '2026-11-13T08:00:00.000Z'}) => {
      'id': id,
      'business_id': 1,
      'user_id': userId,
      'title': title,
      'description': '',
      'visibility': visibility,
      'conversation_id': null,
      'source_count': sources,
      'enabled_source_count': sources,
      'can_write': canWrite,
      'created_at': updated,
      'updated_at': updated,
    };

List<Map<String, dynamic>> nbLibrary() => [
      nbRow(3, title: 'ข้อมูลสินค้าแอร์ 2569', sources: 4),
      nbRow(4, title: 'คู่มือบริการลูกค้า', userId: 9, visibility: 'business', sources: 6, canWrite: false),
      nbRow(5, title: 'สรุปประชุมทีมขาย Q4', userId: 9, sources: 3, canWrite: false),
      nbRow(6, title: 'นโยบายรับประกัน', sources: 1, updated: '2026-11-01T08:00:00.000Z'),
    ];

Map<String, dynamic> nbSource(int id, String kind, String title, String content, {bool enabled = true, int order = 0, Map<String, dynamic> config = const {}}) => {
      'id': id,
      'notebook_id': 3,
      'source_kind': kind,
      'knowledge_id': null,
      'attachment_id': null,
      'title': title,
      'excerpt': content.length > 120 ? content.substring(0, 120) : content,
      'content': content,
      'enabled': enabled,
      'sort_order': order,
      'source_config': config,
      'created_at': '2026-11-13T08:00:00.000Z',
      'updated_at': '2026-11-13T08:00:00.000Z',
    };

const nbPriceText = 'บริษัทตัวอย่างขายเครื่องปรับอากาศ ราคาเริ่มต้น 15,000 บาท\n\nรับประกันคอมเพรสเซอร์ 5 ปี และอะไหล่ 1 ปี\n\nบริการติดตั้งฟรีในกรุงเทพและปริมณฑล';

final nbFlashcards = jsonEncode({
  'cards': [
    {'q': 'ราคาเริ่มต้นของแอร์คือเท่าไร', 'a': '15,000 บาท'},
    {'q': 'รับประกันคอมเพรสเซอร์กี่ปี', 'a': '5 ปี'},
    {'q': 'ติดตั้งฟรีที่ไหน', 'a': 'กรุงเทพและปริมณฑล'},
  ],
});

final nbQuiz = jsonEncode({
  'questions': [
    {'prompt': 'รับประกันคอมเพรสเซอร์กี่ปี', 'options': ['1 ปี', '3 ปี', '5 ปี'], 'answer': 2},
    {'prompt': 'ราคาเริ่มต้นเท่าไร', 'options': ['15,000 บาท', '20,000 บาท'], 'answer': 0},
  ],
});

const nbMindmap = '```mermaid\nmindmap\n  root((แอร์ 2569))\n    ราคา\n      9000 BTU 15000\n      12000 BTU 18000\n    บริการ\n      ติดตั้งฟรี\n      ล้างแอร์\n    รับประกัน\n      คอมเพรสเซอร์ 5 ปี\n      อะไหล่ 1 ปี\n```';

Map<String, dynamic> nbNote(int id, String kind, String title, String content, {Map<String, dynamic> meta = const {}}) => {
      'id': id,
      'notebook_id': 3,
      'title': title,
      'content': content,
      'artifact_kind': kind,
      'source_message_id': null,
      'meta': meta,
      'created_at': '2026-11-13T07:00:00.000Z',
      'updated_at': '2026-11-13T07:00:00.000Z',
    };

Map<String, dynamic> nbDetail({bool withConversation = false, List<Map<String, dynamic>>? sources, List<Map<String, dynamic>>? notes}) => {
      ...nbRow(3, title: 'ข้อมูลสินค้าแอร์ 2569', sources: 4),
      if (withConversation) 'conversation_id': 9,
      'sources': sources ??
          [
            nbSource(11, 'file', 'ราคาแอร์ 2569.pdf', nbPriceText, order: 0, config: {'attachment_id': 1, 'extract_status': 'ready', 'mime': 'application/pdf'}),
            nbSource(12, 'url', 'คู่มือการดูแลแอร์ – example.com', 'ควรล้างแอร์ทุก 6 เดือน เพื่อประหยัดไฟ', order: 1, config: {'url': 'https://example.com/aircare', 'source': 'fetch'}),
            nbSource(13, 'manual', 'โน้ตจากทีมขาย', 'ลูกค้าถามเรื่องผ่อน 0% บ่อย', order: 2),
            nbSource(14, 'url', 'รีวิวแอร์ประหยัดไฟ', '', order: 3, enabled: false, config: {'url': 'https://youtu.be/abc123', 'source': 'youtube', 'fetch_error': 'timeout'}),
          ],
      'notes': notes ??
          [
            nbNote(21, 'mindmap', 'แผนผังความคิด', nbMindmap),
            nbNote(22, 'flashcards', 'แฟลชการ์ด', nbFlashcards),
            nbNote(23, 'quiz', 'แบบทดสอบ', nbQuiz),
            nbNote(24, 'audio', 'ภาพรวมแบบเสียง', 'A: สวัสดีครับ วันนี้เราสรุปเรื่องแอร์ปี 2569\nB: เริ่มจากราคาก่อนเลย [1]', meta: {'downloadUrl': '/api/ai/exports/tok', 'fileName': 'audio.mp3'}),
            nbNote(25, 'report', 'รายงาน', '# รายงานสินค้า\n\nราคาเริ่มต้น 15,000 บาท [1]', meta: {'downloadUrl': '/api/ai/exports/rep', 'fileName': 'รายงาน.pdf', 'expiresAt': '2099-01-01T00:00:00.000Z'}),
          ],
    };

Map<String, dynamic> nbGuide() => {
      'summary': 'สมุดนี้รวมราคาแอร์ปี 2569 การรับประกัน และวิธีดูแลรักษา [1] [2] เหมาะใช้ตอบคำถามลูกค้าเรื่องราคาและบริการ',
      'topics': ['ราคา', 'การรับประกัน', 'การติดตั้ง', 'การดูแลรักษา'],
      'questions': ['ราคาแอร์รุ่นเริ่มต้นเท่าไร', 'รับประกันอะไรบ้าง', 'ควรล้างแอร์บ่อยแค่ไหน'],
      'generated_at': '2026-11-13T08:00:00.000Z',
      'stale': false,
    };

/// SSE body of `/api/ai/chat` with tokens and a `done` that carries citations.
String nbChatSse({String answer = 'ราคาเริ่มต้นอยู่ที่ 15,000 บาท [1] และควรล้างแอร์ทุก 6 เดือน [2]', bool quote = true}) {
  String ev(Map<String, dynamic> m) => 'data: ${jsonEncode(m)}\n\n';
  final half = answer.length ~/ 2;
  return [
    ev({'type': 'status', 'phase': 'thinking'}),
    ev({'type': 'token', 'content': answer.substring(0, half)}),
    ev({'type': 'token', 'content': answer.substring(half)}),
    ev({
      'type': 'done',
      'message': {'role': 'assistant', 'content': answer},
      'citations': [
        {'source_id': 11, 'n': 1, 'title': 'ราคาแอร์ 2569.pdf', 'loc': '[1]', if (quote) 'quote': 'ราคาเริ่มต้น 15,000 บาท', if (quote) 'chunk_index': 0},
        {'source_id': 12, 'n': 2, 'title': 'คู่มือการดูแลแอร์ – example.com', 'loc': '[2]'},
      ],
    }),
  ].join();
}
