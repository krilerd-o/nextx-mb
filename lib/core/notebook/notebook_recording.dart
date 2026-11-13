/// ISAAC Notebook recordings (NEXTX `/api/ai/notebooks/:id/recordings*`): live meeting recordings
/// that become a `recording` source plus a summary note.
library;

import 'dart:convert';

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty || s == 'null' ? null : s;
}

/// recording | paused | processing | ready | failed (+ `uploading`: parts still on this phone).
enum RecordingStatus {
  recording,
  paused,
  uploading,
  processing,
  ready,
  failed;

  static RecordingStatus of(Object? v) => switch ('${v ?? ''}'.toLowerCase()) {
        'recording' || 'live' => RecordingStatus.recording,
        'paused' => RecordingStatus.paused,
        'uploading' => RecordingStatus.uploading,
        'processing' || 'queued' || 'transcribing' || 'summarizing' => RecordingStatus.processing,
        'ready' || 'done' || 'completed' => RecordingStatus.ready,
        'failed' || 'error' => RecordingStatus.failed,
        _ => RecordingStatus.processing,
      };

  bool get active => this == recording || this == paused;
  bool get working => this == uploading || this == processing;
}

/// A line of transcript (live: [partial] while the speaker is still talking).
class RecordingSegment {
  const RecordingSegment({required this.seq, required this.text, this.startMs = 0, this.endMs = 0, this.speaker, this.partial = false});
  final int seq;
  final String text;
  final int startMs;
  final int endMs;
  final String? speaker;
  final bool partial;

  factory RecordingSegment.fromJson(Map<String, dynamic> m) => RecordingSegment(
        seq: _int(m['seq']) ?? 0,
        text: '${m['text'] ?? ''}',
        startMs: _int(m['start_ms']) ?? 0,
        endMs: _int(m['end_ms']) ?? 0,
        speaker: _str(m['speaker']),
        partial: m['partial'] == true,
      );
}

class RecordingBookmark {
  const RecordingBookmark({required this.atMs, this.label});
  final int atMs;
  final String? label;

  factory RecordingBookmark.fromJson(Map<String, dynamic> m) => RecordingBookmark(atMs: _int(m['at_ms']) ?? 0, label: _str(m['label']));
  Map<String, dynamic> toJson() => {'at_ms': atMs, 'label': ?label};
}

class NotebookRecording {
  NotebookRecording({
    required this.id,
    required this.notebookId,
    this.title = '',
    this.status = RecordingStatus.processing,
    this.startedAt,
    this.endedAt,
    this.durationMs = 0,
    this.bookmarks = const [],
    this.sourceId,
    this.noteId,
    this.error,
    this.segments = const [],
    this.locale,
  });

  final String id;
  final String notebookId;
  String title;
  RecordingStatus status;
  final String? startedAt;
  final String? endedAt;
  final int durationMs;
  final List<RecordingBookmark> bookmarks;
  final String? sourceId;
  final String? noteId;
  final String? error;
  final List<RecordingSegment> segments;
  final String? locale;

  factory NotebookRecording.fromJson(Map<String, dynamic> m) {
    final bm = m['bookmarks'];
    final seg = m['segments'];
    return NotebookRecording(
      id: '${m['id']}',
      notebookId: '${m['notebook_id'] ?? ''}',
      title: '${m['title'] ?? ''}',
      status: RecordingStatus.of(m['status']),
      startedAt: _str(m['started_at']),
      endedAt: _str(m['ended_at']),
      durationMs: _int(m['duration_ms']) ?? 0,
      bookmarks: bm is List ? [for (final b in bm) if (b is Map) RecordingBookmark.fromJson(Map<String, dynamic>.from(b))] : const [],
      sourceId: _str(m['source_id']),
      noteId: _str(m['note_id']),
      error: _str(m['error']),
      segments: seg is List ? ([for (final s in seg) if (s is Map) RecordingSegment.fromJson(Map<String, dynamic>.from(s))]..sort((a, b) => a.startMs != b.startMs ? a.startMs.compareTo(b.startMs) : a.seq.compareTo(b.seq))) : const [],
      locale: _str(m['locale']),
    );
  }

  String get displayTitle => title.trim().isEmpty ? 'บันทึกเสียง' : title.trim();
}

/// `m:ss` / `h:mm:ss` for a timer or a transcript time stamp.
String recordingClock(int ms) {
  final total = (ms < 0 ? 0 : ms) ~/ 1000;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '${m.toString().padLeft(2, '0')}:$ss';
}

/// Default title of a new recording: "บันทึกเสียง 13 พ.ย. 14:05".
String defaultRecordingTitle(DateTime t) {
  const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  return 'บันทึกเสียง ${t.day} ${months[t.month - 1]} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

const _summaryKeys = ['key_points', 'discussion_points', 'action_items', 'recommendations'];

bool _looksLikeSummary(Object? v) => v is Map && _summaryKeys.any((k) => v[k] is List);

/// The structured meeting summary of a note made from a recording (the same shape as a call summary:
/// `headline, key_points, discussion_points, action_items, recommendations, …`), or null when the note
/// is plain markdown. Looks in `meta.summary` / `meta.structured` / `meta.result` / `meta`, then the
/// content when it is JSON.
Map<String, dynamic>? meetingSummaryOf({required Map<String, dynamic> meta, required String content}) {
  for (final v in [meta['summary'], meta['structured'], meta['result'], meta['meeting_summary'], meta]) {
    if (_looksLikeSummary(v)) return Map<String, dynamic>.from(v as Map);
  }
  var t = content.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$').firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  if (!t.startsWith('{')) return null;
  try {
    final j = jsonDecode(t);
    if (_looksLikeSummary(j)) return Map<String, dynamic>.from(j as Map);
    if (j is Map && _looksLikeSummary(j['summary'])) return Map<String, dynamic>.from(j['summary'] as Map);
  } catch (_) {}
  return null;
}

/// `[mm:ss] text` / `[h:mm:ss] text` lines (a recording source's content) as segments.
List<RecordingSegment> parseTranscriptLines(String content) {
  final out = <RecordingSegment>[];
  final re = RegExp(r'^\s*\[(?:(\d+):)?(\d{1,2}):(\d{2})\]\s*(.+)$');
  for (final line in content.split('\n')) {
    final m = re.firstMatch(line);
    if (m == null) continue;
    final h = int.tryParse(m.group(1) ?? '0') ?? 0, mm = int.parse(m.group(2)!), ss = int.parse(m.group(3)!);
    out.add(RecordingSegment(seq: out.length + 1, text: m.group(4)!.trim(), startMs: ((h * 60 + mm) * 60 + ss) * 1000));
  }
  return out;
}
