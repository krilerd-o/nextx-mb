/// ISAAC AI Minute Meeting (ไอแซคบันทึกประชุม) — models shared by the screens and the recorder.
library;

String? _s(Object? v) {
  final t = v?.toString().trim();
  return t == null || t.isEmpty || t == 'null' ? null : t;
}

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

List<String> _strList(Object? v) => v is List ? [for (final x in v) if (_s(x) != null) _s(x)!] : const [];

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// Languages the server can transcribe / translate (code → Thai label).
const kMinuteLangs = <String, String>{
  'th': 'ไทย',
  'en': 'อังกฤษ',
  'zh': 'จีน',
  'ja': 'ญี่ปุ่น',
  'my': 'เมียนมา',
  'lo': 'ลาว',
  'km': 'เขมร',
  'vi': 'เวียดนาม',
};

/// Summary templates (key → Thai label, short hint).
const kMinuteTemplates = <String, (String, String)>{
  'general': ('ประชุมทั่วไป', 'เรื่องที่คุย ข้อตกลง งานที่ต้องทำ'),
  'sales': ('ประชุมลูกค้า / ขาย', 'ความต้องการ งบ ผู้ตัดสินใจ ขั้นตอนถัดไป'),
  'project': ('ประชุมโปรเจกต์', 'ความคืบหน้า ความเสี่ยง ผู้รับผิดชอบ กำหนดส่ง'),
  'interview': ('สัมภาษณ์', 'ประสบการณ์ จุดแข็ง ข้อสรุป'),
  'training': ('อบรม / บรรยาย', 'หัวข้อ ประเด็นสำคัญ คำถาม'),
  'brainstorm': ('ระดมความคิด', 'ไอเดีย การจัดกลุ่ม สิ่งที่เลือก'),
};

String minuteLangLabel(String code) => kMinuteLangs[code] ?? code.toUpperCase();
String minuteTemplateLabel(String key) => kMinuteTemplates[key]?.$1 ?? 'ประชุมทั่วไป';

/// "1:02:05" / "12:05".
String minuteClock(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String minuteStatusLabel(String status, {String? stage}) => switch (status) {
  'live' => 'กำลังบันทึก',
  'paused' => 'หยุดชั่วคราว',
  'uploading' => 'กำลังอัปโหลด',
  'processing' => switch (stage) {
    'recording_wait' => 'รอไฟล์บันทึกห้อง',
    'transcribe' => 'กำลังถอดข้อความ',
    'summary' => 'กำลังสรุป',
    'translate' => 'กำลังแปล',
    _ => 'กำลังประมวลผล',
  },
  'ready' => 'พร้อมแล้ว',
  'failed' => 'ไม่สำเร็จ',
  _ => status,
};

String minuteSourceLabel(String source) => switch (source) {
  'upload' => 'ไฟล์',
  'room' => 'ห้องประชุม',
  _ => 'บันทึกสด',
};

class MinuteMeeting {
  const MinuteMeeting({
    required this.id,
    required this.title,
    this.source = 'record',
    this.mediaKind = 'audio',
    this.status = 'live',
    this.locale = 'th',
    this.languages = const [],
    this.summaryMode = 'later',
    this.template = 'general',
    this.durationMs = 0,
    this.startedAt,
    this.mediaUrl,
    this.mediaMime,
    this.progress = 0,
    this.stage,
    this.error,
    this.headline,
    this.snippet,
    this.roomCode,
    this.speakers = const {},
    this.translateLangs = const [],
    this.ownerId,
  });

  factory MinuteMeeting.fromJson(Map<String, dynamic> j) => MinuteMeeting(
    id: '${j['id'] ?? ''}',
    title: _s(j['title']) ?? '',
    source: _s(j['source']) ?? 'record',
    mediaKind: _s(j['media_kind']) ?? 'audio',
    status: _s(j['status']) ?? 'live',
    locale: _s(j['locale']) ?? 'th',
    languages: _strList(j['languages']),
    summaryMode: _s(j['summary_mode']) ?? 'later',
    template: _s(j['template']) ?? 'general',
    durationMs: _i(j['duration_ms']),
    startedAt: DateTime.tryParse('${j['started_at'] ?? ''}')?.toLocal(),
    mediaUrl: _s(j['media_url']),
    mediaMime: _s(j['media_mime']),
    progress: _i(j['progress']),
    stage: _s(j['stage']),
    error: _s(j['error']),
    headline: _s(j['headline']),
    snippet: _s(j['snippet']),
    roomCode: _s(j['room_code']),
    speakers: {for (final e in _map(j['speakers']).entries) e.key: '${e.value}'},
    translateLangs: _strList(_map(j['features'])['translate']),
    ownerId: _s(j['owner_id']),
  );

  final String id;
  final String title;
  final String source;
  final String mediaKind;
  final String status;
  final String locale;
  final List<String> languages;
  final String summaryMode;
  final String template;
  final int durationMs;
  final DateTime? startedAt;
  final String? mediaUrl;
  final String? mediaMime;
  final int progress;
  final String? stage;
  final String? error;
  final String? headline;
  final String? snippet;
  final String? roomCode;
  final Map<String, String> speakers;
  final List<String> translateLangs;
  final String? ownerId;

  bool get busy => status == 'processing' || status == 'uploading';
  bool get ready => status == 'ready';
  bool get video => mediaKind == 'video';

  MinuteMeeting copyWith({String? title, String? status, int? progress, String? stage, Map<String, String>? speakers}) => MinuteMeeting(
    id: id,
    title: title ?? this.title,
    source: source,
    mediaKind: mediaKind,
    status: status ?? this.status,
    locale: locale,
    languages: languages,
    summaryMode: summaryMode,
    template: template,
    durationMs: durationMs,
    startedAt: startedAt,
    mediaUrl: mediaUrl,
    mediaMime: mediaMime,
    progress: progress ?? this.progress,
    stage: stage ?? this.stage,
    error: error,
    headline: headline,
    snippet: snippet,
    roomCode: roomCode,
    speakers: speakers ?? this.speakers,
    translateLangs: translateLangs,
    ownerId: ownerId,
  );
}

class MinuteLine {
  const MinuteLine({required this.seq, required this.text, this.startMs = 0, this.endMs = 0, this.speaker, this.partial = false, this.edited = false});

  factory MinuteLine.fromJson(Map<String, dynamic> j) => MinuteLine(
    seq: _i(j['seq']),
    text: '${j['text'] ?? ''}',
    startMs: _i(j['start_ms']),
    endMs: _i(j['end_ms']),
    speaker: _s(j['speaker']),
    partial: j['partial'] == true,
    edited: j['edited'] == true,
  );

  final int seq;
  final String text;
  final int startMs;
  final int endMs;
  final String? speaker;
  final bool partial;
  final bool edited;
}

class MinuteAction {
  const MinuteAction({required this.text, this.owner, this.due, this.atMs});
  factory MinuteAction.fromJson(Object? j) {
    if (j is! Map) return MinuteAction(text: '${j ?? ''}');
    return MinuteAction(text: '${j['text'] ?? ''}', owner: _s(j['owner']), due: _s(j['due']), atMs: j['at_ms'] is num ? (j['at_ms'] as num).toInt() : null);
  }
  final String text;
  final String? owner;
  final String? due;
  final int? atMs;
}

class MinuteChapter {
  const MinuteChapter({required this.atMs, required this.title, this.summary});
  final int atMs;
  final String title;
  final String? summary;
}

class MinuteSummary {
  const MinuteSummary({
    required this.id,
    this.template = 'general',
    this.lang = 'th',
    this.headline = '',
    this.keyPoints = const [],
    this.decisions = const [],
    this.actions = const [],
    this.discussion = const [],
    this.openQuestions = const [],
    this.recommendations = const [],
    this.chapters = const [],
    this.nextMeeting,
    this.markdown = '',
  });

  factory MinuteSummary.fromJson(Map<String, dynamic> j) => MinuteSummary(
    id: '${j['id'] ?? ''}',
    template: _s(j['template']) ?? 'general',
    lang: _s(j['lang']) ?? 'th',
    headline: _s(j['headline']) ?? '',
    keyPoints: _strList(j['key_points']),
    decisions: _strList(j['decisions']),
    actions: j['action_items'] is List ? [for (final a in j['action_items'] as List) MinuteAction.fromJson(a)] : const [],
    discussion: _strList(j['discussion_points']),
    openQuestions: _strList(j['open_questions']),
    recommendations: _strList(j['recommendations']),
    chapters: j['chapters'] is List
        ? [
            for (final c in j['chapters'] as List)
              if (c is Map) MinuteChapter(atMs: _i(c['at_ms']), title: '${c['title'] ?? ''}', summary: _s(c['summary'])),
          ]
        : const [],
    nextMeeting: _s(j['next_meeting']),
    markdown: '${j['markdown'] ?? ''}',
  );

  final String id;
  final String template;
  final String lang;
  final String headline;
  final List<String> keyPoints;
  final List<String> decisions;
  final List<MinuteAction> actions;
  final List<String> discussion;
  final List<String> openQuestions;
  final List<String> recommendations;
  final List<MinuteChapter> chapters;
  final String? nextMeeting;
  final String markdown;
}

/// What to do when a recording ends (the "จบการประชุม" sheet).
class MinuteFinish {
  const MinuteFinish({this.summarizeNow = true, this.template = 'general', this.translate = const [], this.emailTo = const [], this.tasks = false, this.expectVideo = false});
  final bool summarizeNow;
  final String template;
  final List<String> translate;
  final List<String> emailTo;
  final bool tasks;

  /// A camera file of this meeting is still uploading (the server waits for it, then joins it with the audio).
  final bool expectVideo;

  MinuteFinish withVideo() => MinuteFinish(summarizeNow: summarizeNow, template: template, translate: translate, emailTo: emailTo, tasks: tasks, expectVideo: true);

  Map<String, dynamic> toStopBody() => {
    'summary_mode': summarizeNow ? 'now' : 'later',
    'template': template,
    'features': {'summarize': summarizeNow, 'translate': translate, 'email_to': emailTo, 'tasks': tasks, if (expectVideo) 'expect_video': true},
  };
}
