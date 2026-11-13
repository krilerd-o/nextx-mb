import 'notebook_models.dart';

/// ISAAC Notebook Phase 3 studio outputs: the structured `meta` of study guides,
/// FAQs, briefings, timelines, JSON mind maps and the two-host Audio Overview.
/// Every parser returns null when its block is missing, so the viewer falls back
/// to the markdown `content`.

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];
int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String? _str(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty || s == 'null' ? null : s;
}

List<String> _ids(dynamic v) => [for (final x in (v is List ? v : const [])) if (_str(x) != null) _str(x)!];

/// `meta.sources[]`: the numbered sources a studio output cites as `[n]`.
class StudioSourceRef {
  const StudioSourceRef({required this.n, required this.sourceId, this.title = ''});
  final int n;
  final String sourceId;
  final String title;
}

List<StudioSourceRef> studioSources(Map<String, dynamic> meta) => [
      for (final (i, m) in _maps(meta['sources']).indexed)
        if (_str(m['source_id']) != null) StudioSourceRef(n: _int(m['n']) ?? i + 1, sourceId: _str(m['source_id'])!, title: '${m['title'] ?? ''}'.trim()),
    ];

/// `meta.generated == 'template'`: the AI was not available, the server filled a template.
bool studioFromTemplate(Map<String, dynamic> meta) => '${meta['generated'] ?? ''}' == 'template';

// ------------------------------------------------------------- study guide

class StudyQuestion {
  const StudyQuestion(this.q, {this.a = '', this.sourceIds = const []});
  final String q;
  final String a;
  final List<String> sourceIds;
}

class GlossaryTerm {
  const GlossaryTerm(this.term, this.definition, {this.sourceIds = const []});
  final String term;
  final String definition;
  final List<String> sourceIds;
}

class StudyGuide {
  const StudyGuide({this.quiz = const [], this.essays = const [], this.glossary = const []});
  final List<StudyQuestion> quiz;
  final List<StudyQuestion> essays;
  final List<GlossaryTerm> glossary;

  bool get isEmpty => quiz.isEmpty && essays.isEmpty && glossary.isEmpty;

  static StudyGuide? fromMeta(Map<String, dynamic> meta) {
    if (meta['study_guide'] is! Map) return null;
    final m = _map(meta['study_guide']);
    final g = StudyGuide(
      quiz: [for (final x in _maps(m['quiz'])) if (_str(x['q']) != null) StudyQuestion(_str(x['q'])!, a: '${x['a'] ?? ''}'.trim(), sourceIds: _ids(x['source_ids']))],
      essays: [for (final x in _maps(m['essay_questions'])) if (_str(x['q']) != null) StudyQuestion(_str(x['q'])!, sourceIds: _ids(x['source_ids']))],
      glossary: [
        for (final x in _maps(m['glossary']))
          if (_str(x['term']) != null) GlossaryTerm(_str(x['term'])!, '${x['definition'] ?? ''}'.trim(), sourceIds: _ids(x['source_ids'])),
      ],
    );
    return g.isEmpty ? null : g;
  }
}

// --------------------------------------------------------------------- faq

List<StudyQuestion>? faqFromMeta(Map<String, dynamic> meta) {
  if (meta['faq'] is! List) return null;
  final out = [for (final x in _maps(meta['faq'])) if (_str(x['q']) != null) StudyQuestion(_str(x['q'])!, a: '${x['a'] ?? ''}'.trim(), sourceIds: _ids(x['source_ids']))];
  return out.isEmpty ? null : out;
}

// ---------------------------------------------------------------- briefing

class BriefingTheme {
  const BriefingTheme(this.title, this.summary, {this.sourceIds = const []});
  final String title;
  final String summary;
  final List<String> sourceIds;
}

class BriefingQuote {
  const BriefingQuote(this.text, {this.sourceId, this.n, this.attribution, this.verified = false, this.start, this.end});
  final String text;
  final String? sourceId;
  final int? n;
  final String? attribution;

  /// The server found the exact text in the source (with [start]..[end]).
  final bool verified;
  final int? start;
  final int? end;
}

class Briefing {
  const Briefing({this.title, this.summary = '', this.summarySourceIds = const [], this.themes = const [], this.quotes = const [], this.conclusion});
  final String? title;
  final String summary;
  final List<String> summarySourceIds;
  final List<BriefingTheme> themes;
  final List<BriefingQuote> quotes;
  final String? conclusion;

  static Briefing? fromMeta(Map<String, dynamic> meta) {
    if (meta['briefing'] is! Map) return null;
    final m = _map(meta['briefing']);
    final b = Briefing(
      title: _str(m['title']),
      summary: '${m['executive_summary'] ?? ''}'.trim(),
      summarySourceIds: _ids(m['executive_summary_source_ids']),
      themes: [
        for (final t in _maps(m['themes']))
          if (_str(t['title']) != null || _str(t['summary']) != null) BriefingTheme(_str(t['title']) ?? '', '${t['summary'] ?? ''}'.trim(), sourceIds: _ids(t['source_ids'])),
      ],
      quotes: [
        for (final q in _maps(m['quotes']))
          if (_str(q['text']) != null)
            BriefingQuote(
              _str(q['text'])!,
              sourceId: _str(q['source_id']),
              n: _int(q['n']),
              attribution: _str(q['attribution']),
              verified: q['verified'] == true,
              start: _int(q['start']),
              end: _int(q['end']),
            ),
      ],
      conclusion: _str(m['conclusion']),
    );
    if (b.summary.isEmpty && b.themes.isEmpty && b.quotes.isEmpty) return null;
    return b;
  }
}

// ---------------------------------------------------------------- timeline

class TimelineEvent {
  const TimelineEvent(this.event, {this.date, this.sourceIds = const []});
  final String? date;
  final String event;
  final List<String> sourceIds;
}

class CastMember {
  const CastMember(this.name, {this.description = '', this.sourceIds = const []});
  final String name;
  final String description;
  final List<String> sourceIds;

  /// Up to two letters for the avatar (Thai or Latin), skipping honorifics such as "คุณ".
  String get initials {
    var n = name.trim();
    for (final p in const ['คุณ', 'นาย', 'นาง', 'นางสาว', 'ดร.', 'Mr. ', 'Ms. ', 'Mrs. ', 'Dr. ']) {
      if (n.startsWith(p) && n.length > p.length) {
        n = n.substring(p.length).trim();
        break;
      }
    }
    final words = n.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    String first(String w) => String.fromCharCodes(w.runes.take(1));
    if (words.length == 1 || RegExp(r'[฀-๿]').hasMatch(words.first)) return first(words.first).toUpperCase();
    return (first(words[0]) + first(words[1])).toUpperCase();
  }
}

class Timeline {
  const Timeline({this.events = const [], this.cast = const []});
  final List<TimelineEvent> events;
  final List<CastMember> cast;

  static Timeline? fromMeta(Map<String, dynamic> meta) {
    if (meta['timeline'] is! List && meta['cast'] is! List) return null;
    final t = Timeline(
      events: [for (final e in _maps(meta['timeline'])) if (_str(e['event']) != null) TimelineEvent(_str(e['event'])!, date: _str(e['date']), sourceIds: _ids(e['source_ids']))],
      cast: [for (final c in _maps(meta['cast'])) if (_str(c['name']) != null) CastMember(_str(c['name'])!, description: '${c['description'] ?? ''}'.trim(), sourceIds: _ids(c['source_ids']))],
    );
    return t.events.isEmpty && t.cast.isEmpty ? null : t;
  }
}

// ------------------------------------------------------------ JSON mind map

/// A node of `meta.mindmap.root` (ids like `root.0.1`).
class MindTreeNode {
  MindTreeNode({required this.id, required this.label, List<MindTreeNode>? children, this.sourceIds = const [], this.parent}) : children = children ?? [];
  final String id;
  final String label;
  final List<MindTreeNode> children;
  final List<String> sourceIds;
  final MindTreeNode? parent;

  int get depth => parent == null ? 0 : parent!.depth + 1;
  int get size => 1 + children.fold<int>(0, (a, c) => a + c.size);
  bool get isLeaf => children.isEmpty;

  /// Labels from the root down to this node.
  List<String> get path => [...?parent?.path, label];

  Iterable<MindTreeNode> get all sync* {
    yield this;
    for (final c in children) {
      yield* c.all;
    }
  }

  /// Source ids of this node, else the closest ancestor's.
  List<String> get effectiveSourceIds => sourceIds.isNotEmpty ? sourceIds : (parent?.effectiveSourceIds ?? const []);

  static MindTreeNode? fromMeta(Map<String, dynamic> meta) {
    final m = meta['mindmap'];
    if (m is! Map || m['root'] is! Map) return null;
    var counter = 0;
    MindTreeNode build(Map<String, dynamic> raw, MindTreeNode? parent, String fallbackId, int depth) {
      counter++;
      final node = MindTreeNode(id: _str(raw['id']) ?? fallbackId, label: _str(raw['label']) ?? '—', sourceIds: _ids(raw['source_ids']), parent: parent);
      // Same limits as the server (depth ≤ 4, ≤ 120 nodes) so a bad payload cannot blow up the layout.
      if (depth < 5) {
        for (final (i, c) in _maps(raw['children']).indexed) {
          if (counter >= 160) break;
          node.children.add(build(c, node, '${node.id}.$i', depth + 1));
        }
      }
      return node;
    }

    final root = build(_map(m['root']), null, 'root', 0);
    return root.label == '—' && root.isLeaf ? null : root;
  }
}

// ---------------------------------------------------------- audio overview

/// Audio Overview formats (`options.audio.format`).
const kAudioFormats = [
  ('brief', 'สรุปสั้น', 'ใจความสำคัญในไม่กี่นาที'),
  ('deep_dive', 'เจาะลึก', 'สองพิธีกรคุยกันอย่างละเอียด'),
  ('critique', 'วิจารณ์', 'ชี้จุดแข็ง จุดอ่อน และข้อสังเกต'),
  ('debate', 'ดีเบต', 'สองมุมมองถกเถียงกัน'),
];

/// Audio Overview lengths (`options.audio.length`).
const kAudioLengths = [('short', 'สั้น'), ('default', 'ปกติ'), ('long', 'ยาว')];

String audioFormatLabel(String id) => kAudioFormats.where((f) => f.$1 == id).firstOrNull?.$2 ?? id;
String audioLengthLabel(String id) => kAudioLengths.where((f) => f.$1 == id).firstOrNull?.$2 ?? id;

/// `options` of `POST /studio` for a v2 Audio Overview.
Map<String, dynamic> audioStudioOptions({required String format, required String length}) => {
      'audio': {'format': format, 'length': length, 'hosts': 2},
    };

class AudioTurn {
  const AudioTurn({required this.speaker, required this.text, this.startMs, this.endMs});

  /// `A` | `B`.
  final String speaker;
  final String text;
  final int? startMs;
  final int? endMs;

  bool get isA => speaker.toUpperCase() != 'B';
}

class AudioOverview {
  const AudioOverview({
    this.format = 'deep_dive',
    this.length = 'default',
    this.hosts = 2,
    this.voices = const [],
    this.provider,
    this.durationMs,
    this.pauseMs,
    this.scriptSource,
    this.turns = const [],
    this.ttsError,
  });

  final String format;
  final String length;
  final int hosts;
  final List<String> voices;
  final String? provider;
  final int? durationMs;
  final int? pauseMs;
  final String? scriptSource;
  final List<AudioTurn> turns;

  /// Why no voice was made (the script is still there).
  final String? ttsError;

  /// Every turn has timings and there was no TTS error: the transcript follows the audio.
  bool get timed => ttsError == null && turns.isNotEmpty && turns.every((t) => t.startMs != null && t.endMs != null);

  /// Index of the turn playing at [ms] (the last one started), or -1.
  int turnAt(int ms) {
    if (!timed) return -1;
    var hit = -1;
    for (final (i, t) in turns.indexed) {
      if (t.startMs! <= ms) hit = i;
      if (t.startMs! > ms) break;
    }
    return hit;
  }

  /// `meta.audio` with `version: 2`, else null (classic audio notes).
  static AudioOverview? fromMeta(Map<String, dynamic> meta) {
    final a = meta['audio'];
    if (a is! Map) return null;
    final m = _map(a);
    if ((_int(m['version']) ?? 0) < 2) return null;
    final turns = [
      for (final t in _maps(m['turns']))
        if (_str(t['text']) != null) AudioTurn(speaker: _str(t['speaker']) ?? 'A', text: _str(t['text'])!, startMs: _int(t['start_ms']), endMs: _int(t['end_ms'])),
    ];
    return AudioOverview(
      format: _str(m['format']) ?? 'deep_dive',
      length: _str(m['length']) ?? 'default',
      hosts: _int(m['hosts']) ?? 2,
      voices: [for (final v in (m['voices'] is List ? m['voices'] as List : const [])) '$v'],
      provider: _str(m['provider']),
      durationMs: _int(m['duration_ms']),
      pauseMs: _int(m['pause_ms']),
      scriptSource: _str(m['script_source']),
      turns: turns,
      ttsError: _str(m['tts_error']),
    );
  }
}

/// `[n]` refs of [ids] (via `meta.sources`), in order, without repeats; an id missing
/// from `meta.sources` comes back with `n: 0` (the viewer finds its title in the notebook).
List<StudioSourceRef> refsFor(List<StudioSourceRef> sources, List<String> ids) {
  final out = <StudioSourceRef>[];
  for (final id in ids) {
    if (out.any((r) => r.sourceId == id)) continue;
    out.add(sources.where((s) => s.sourceId == id).firstOrNull ?? StudioSourceRef(n: 0, sourceId: id));
  }
  return out;
}

/// Citations for inline `[n]` markers of a studio note (from `meta.sources`).
List<NotebookCitation> studioCitations(Map<String, dynamic> meta) => [for (final s in studioSources(meta)) NotebookCitation(n: s.n, sourceId: s.sourceId, title: s.title)];
