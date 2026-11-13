// Notebook recordings as NEXTX answers them (shapes copied from the demo server, recording 16).
import 'notebook_fixtures.dart';

const nbRecTranscript = '[00:02] สวัสดีครับคุณวิภา วันนี้โทรมาติดตามเรื่องเครื่องปรับอากาศที่สาขาบางนาครับ\n'
    '[00:06] ขอโทษด้วยครับ เดี๋ยวผมนัดช่างเข้าไปตรวจอีกครั้ง วันพฤหัสนี้สะดวกไหมครับ\n'
    '[00:10] ค่ะ ตอนนี้แอร์ชั้น 3 ยังมีน้ำหยดอยู่เลย ช่างมาครั้งก่อนก็ยังไม่หาย';

Map<String, dynamic> nbRecording({int id = 16, String status = 'ready', bool segments = true, int? noteId = 17, int? sourceId = 54}) => {
      'id': id,
      'notebook_id': 3,
      'title': 'ประชุมลูกค้าสาขาบางนา',
      'status': status,
      'locale': 'th',
      'started_at': DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String(),
      'ended_at': status == 'ready' ? '2026-11-13T10:04:15.348Z' : null,
      'duration_ms': 11000,
      'bookmarks': [
        {'at_ms': 6000, 'label': 'นัดช่าง'},
      ],
      'parts_received': [0],
      'parts_total': 1,
      'audio_url': '/api/ai/notebooks/3/recordings/$id/audio',
      'audio_mime': 'audio/mp4',
      'transcript_source': 'live',
      'source_id': status == 'ready' ? sourceId : null,
      'note_id': status == 'ready' ? noteId : null,
      'error': status == 'failed' ? 'ถอดเสียงไม่สำเร็จ' : null,
      if (segments)
        'segments': [
          {'seq': 1, 'start_ms': 2000, 'end_ms': 4200, 'text': 'สวัสดีครับคุณวิภา วันนี้โทรมาติดตามเรื่องเครื่องปรับอากาศที่สาขาบางนาครับ', 'speaker': null},
          {'seq': 2, 'start_ms': 6000, 'end_ms': 9000, 'text': 'ขอโทษด้วยครับ เดี๋ยวผมนัดช่างเข้าไปตรวจอีกครั้ง วันพฤหัสนี้สะดวกไหมครับ', 'speaker': null},
          {'seq': 3, 'start_ms': 10000, 'end_ms': 11000, 'text': 'ค่ะ ตอนนี้แอร์ชั้น 3 ยังมีน้ำหยดอยู่เลย ช่างมาครั้งก่อนก็ยังไม่หาย', 'speaker': null},
        ],
    };

Map<String, dynamic> nbRecordingSource() => nbSource(54, 'recording', 'ประชุมลูกค้าสาขาบางนา', nbRecTranscript, order: 4, config: {
      'recording_id': 16,
      'duration_ms': 11000,
      'audio_path': '/api/ai/notebooks/3/recordings/16/audio',
      'audio_mime': 'audio/mp4',
      'bookmarks': [
        {'at_ms': 6000, 'label': 'นัดช่าง'},
      ],
      'transcript_source': 'live',
      'segment_count': 3,
    });

Map<String, dynamic> nbMeetingSummary() => {
      'headline': 'ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด นัดช่างเข้าตรวจวันพฤหัสบ่าย และขอใบเสนอราคา MA รายปี',
      'topics': ['แอร์รั่ว', 'สัญญา MA'],
      'sentiment': {'label': 'negative', 'reason': 'ลูกค้ากังวลเพราะซ่อมแล้วยังไม่หาย'},
      'key_points': ['แอร์ชั้น 3 สาขาบางนายังมีน้ำหยด แม้ช่างเคยเข้าแก้ไขแล้ว [#2]', 'ตกลงนัดช่างเข้าตรวจอีกครั้งวันพฤหัสช่วงบ่าย [#3]', 'ลูกค้าต้องการใบเสนอราคาสัญญาบำรุงรักษารายปี'],
      'discussion_points': ['การซ่อมครั้งก่อนไม่ได้แก้ปัญหา ลูกค้าเริ่มกังวลเรื่องคุณภาพงาน [#2]'],
      'action_items': [
        {'text': 'นัดช่างเข้าตรวจแอร์ชั้น 3 วันพฤหัสบ่าย', 'owner': 'สมชาย', 'due': '2026-11-19'},
        {'text': 'ส่งใบเสนอราคาสัญญา MA รายปี', 'owner': 'สมชาย', 'due': '2026-11-20'},
      ],
      'recommendations': ['เปิด Visit ให้ช่าง พร้อมแนบประวัติการซ่อมครั้งก่อน', 'เปิด Task ทำใบเสนอราคา MA และนัดโทรติดตามหลังส่ง'],
      'suggestions': <Map<String, dynamic>>[],
      'lines': [
        {'n': 1, 'at': '00:02', 'seq': 1, 'start_ms': 2000, 'text': 'สวัสดีครับคุณวิภา'},
      ],
    };

Map<String, dynamic> nbMeetingNote() => nbNote(
      17,
      'meeting_summary',
      'สรุปการประชุม: ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด',
      '# ลูกค้าแจ้งแอร์ชั้น 3 น้ำหยด\n\n## ใจความสำคัญ\n- แอร์ชั้น 3 ยังมีน้ำหยด',
      meta: {'kind': 'meeting_summary', 'recording_id': 16, 'source_id': 54, 'duration_ms': 11000, 'summary': nbMeetingSummary()},
    );

/// Notebook 3 with the recording source and its summary note.
Map<String, dynamic> nbDetailWithRecording({bool withConversation = true}) {
  final d = nbDetail(withConversation: withConversation);
  return {
    ...d,
    'sources': [...(d['sources'] as List), nbRecordingSource()],
    'notes': [nbMeetingNote(), ...(d['notes'] as List)],
  };
}
