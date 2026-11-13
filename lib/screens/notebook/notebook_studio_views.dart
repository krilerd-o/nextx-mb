import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/notebook/notebook_studio_meta.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_markdown.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../comm_ai/comm_ai_isaac.dart' show kIsaacIndigo;
import 'notebook_chat_pane.dart' show showCitationSheet;
import 'notebook_sources_pane.dart' show showSourceViewer;
import 'notebook_widgets.dart';

/// Native views of the Phase 3 studio outputs (study guide, FAQ, briefing,
/// timeline) built from the note's `meta`; `source_ids` and inline `[n]` open
/// the sources.

EdgeInsets studioPadding(BuildContext context) => EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom);

/// Opens source [id] of the notebook (or says it is gone).
void openStudioSource(BuildContext context, NotebookController c, String id, {String? highlight, int? start, int? end}) {
  final s = c.sourceById(id);
  if (s == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('ไม่พบแหล่งนี้ในสมุดแล้ว'))));
    return;
  }
  HapticFeedback.selectionClick();
  showSourceViewer(context, c, s, highlight: highlight, start: start, end: end);
}

/// `[n] title` pills for [ids]; tap opens that source.
class StudioSourceChips extends StatelessWidget {
  const StudioSourceChips({super.key, required this.c, required this.sources, required this.ids, this.max = 4});
  final NotebookController c;
  final List<StudioSourceRef> sources;
  final List<String> ids;
  final int max;

  @override
  Widget build(BuildContext context) {
    final refs = refsFor(sources, ids);
    if (refs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final r in refs.take(max))
        Builder(builder: (context) {
          final src = c.sourceById(r.sourceId);
          final title = r.title.isNotEmpty ? r.title : (src?.displayTitle ?? tr('แหล่งข้อมูล'));
          return Material(
            color: kNotebookAccent.withValues(alpha: dark ? 0.18 : 0.07),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('studio-ref-${r.sourceId}'),
              onTap: () => openStudioSource(context, c, r.sourceId),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: src == null ? theme.disabledColor : kNotebookAccent, borderRadius: BorderRadius.circular(99)),
                    child: r.n > 0
                        ? Text('${r.n}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800, height: 1.1))
                        : const Icon(LucideIcons300.fileText, size: 11, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: dark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA))),
                  ),
                ]),
              ),
            ),
          );
        }),
      if (refs.length > max) Padding(padding: const EdgeInsets.only(top: 3), child: Text('+${refs.length - max}', style: theme.textTheme.labelSmall)),
    ]);
  }
}

/// Markdown with tappable `[n]` (numbers from `meta.sources`).
class StudioMarkdown extends StatelessWidget {
  const StudioMarkdown({super.key, required this.c, required this.meta, required this.text, this.selectable = true});
  final NotebookController c;
  final Map<String, dynamic> meta;
  final String text;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cites = studioCitations(meta);
    final known = {for (final x in cites) x.n};
    return NxMarkdown(
      data: known.isEmpty ? text : linkCitations(text, known: known),
      selectable: selectable,
      linkStyle: TextStyle(color: kIsaacIndigo, fontWeight: FontWeight.w800, fontSize: 13, backgroundColor: kIsaacIndigo.withValues(alpha: dark ? 0.22 : 0.1)),
      onOpenLink: (href) {
        final n = citationFromHref(href);
        final cite = n == null ? null : citationFor(cites, n);
        if (cite != null) showCitationSheet(context, c, cite);
      },
    );
  }
}

/// Gradient header of a studio output: badge, title, counts; "จากแม่แบบ" when the AI was off.
class StudioHeader extends StatelessWidget {
  const StudioHeader({super.key, required this.kind, required this.title, this.stats = const [], this.template = false, this.trailing});
  final StudioKind kind;
  final String title;
  final List<String> stats;
  final bool template;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kind.colors.first.withValues(alpha: dark ? 0.32 : 0.14), kind.colors.last.withValues(alpha: dark ? 0.16 : 0.05)],
        ),
        border: Border.all(color: kind.colors.first.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          StudioKindBadge(kind: kind, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title.trim() != kind.label)
                Text(tr(kind.label), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: dark ? kind.colors.first.withValues(alpha: 0.95) : kind.colors.last)),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.3)),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text([for (final s in stats) tr(s)].join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ]),
          ),
          ?trailing,
        ]),
        if (template)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(key: const ValueKey('studio-template-note'), children: [
              Icon(LucideIcons300.info, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(tr('ร่างจากแม่แบบ เพราะ AI ไม่พร้อมตอนสร้าง — ลองสร้างใหม่ได้'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
            ]),
          ),
      ]),
    );
  }
}

Widget _numberDot(int n, Color color, {double size = 26}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text('$n', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.46, height: 1.1)),
    );

// ------------------------------------------------------------- study guide

enum _StudyTab { quiz, essay, glossary }

class StudyGuideView extends StatefulWidget {
  const StudyGuideView({super.key, required this.c, required this.note, required this.guide, this.onDraft});
  final NotebookController c;
  final NotebookNote note;
  final StudyGuide guide;

  /// Put a question in the chat composer ("ฝึกตอบในแชท").
  final ValueChanged<String>? onDraft;

  @override
  State<StudyGuideView> createState() => _StudyGuideViewState();
}

class _StudyGuideViewState extends State<StudyGuideView> {
  late _StudyTab _tab = widget.guide.quiz.isNotEmpty ? _StudyTab.quiz : (widget.guide.essays.isNotEmpty ? _StudyTab.essay : _StudyTab.glossary);
  final Set<int> _shown = {};

  static const _teal = Color(0xFF0D9488);

  @override
  Widget build(BuildContext context) {
    final g = widget.guide;
    final n = widget.note;
    final sources = studioSources(n.meta);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tabs = <(_StudyTab, String, IconData?)>[
      if (g.quiz.isNotEmpty) (_StudyTab.quiz, 'แบบทดสอบ', null),
      if (g.essays.isNotEmpty) (_StudyTab.essay, 'เรียงความ', null),
      if (g.glossary.isNotEmpty) (_StudyTab.glossary, 'คำศัพท์', null),
    ];
    final children = <Widget>[
      StudioHeader(
        kind: StudioKind.studyGuide,
        title: n.displayTitle,
        template: studioFromTemplate(n.meta),
        stats: [
          if (g.quiz.isNotEmpty) '${g.quiz.length} ข้อ',
          if (g.essays.isNotEmpty) '${g.essays.length} เรียงความ',
          if (g.glossary.isNotEmpty) '${g.glossary.length} คำศัพท์',
        ],
      ),
      if (tabs.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: KeyedSubtree(key: const ValueKey('study-tabs'), child: NxSlidingSegmented<_StudyTab>(value: _tab, options: tabs, onChanged: (t) => setState(() => _tab = t))),
        ),
    ];
    switch (_tab) {
      case _StudyTab.quiz:
        final all = _shown.length == g.quiz.length;
        children.add(Row(children: [
          Expanded(child: Text(tr('แบบทดสอบแบบตอบสั้น'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
          TextButton.icon(
            key: const ValueKey('study-reveal-all'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _teal),
            onPressed: () => setState(() => all ? _shown.clear() : _shown.addAll(List.generate(g.quiz.length, (i) => i))),
            icon: Icon(all ? LucideIcons300.eyeOff : LucideIcons300.eye, size: 16),
            label: Text(tr(all ? 'ซ่อนเฉลยทั้งหมด' : 'ดูเฉลยทั้งหมด')),
          ),
        ]));
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(tr('ลองตอบในใจก่อน แล้วแตะเพื่อดูเฉลย · ดูแล้ว ${_shown.length}/${g.quiz.length}'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ));
        for (final (i, q) in g.quiz.indexed) {
          children.add(_quizCard(context, i, q, sources));
        }
      case _StudyTab.essay:
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(tr('คำถามเชิงเรียงความ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ));
        for (final (i, q) in g.essays.indexed) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NotebookCard(
              key: ValueKey('study-essay-$i'),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _numberDot(i + 1, const Color(0xFF0891B2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(q.q, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.45)),
                    const SizedBox(height: 8),
                    StudioSourceChips(c: widget.c, sources: sources, ids: q.sourceIds),
                    if (widget.onDraft != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: ValueKey('study-essay-$i-ask'),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: kNotebookAccent),
                          onPressed: () => widget.onDraft!(tr('ช่วยวางโครงคำตอบเรียงความจากแหล่งข้อมูล: "${q.q}"')),
                          icon: const Icon(LucideIcons300.messagesSquare, size: 16),
                          label: Text(tr('ฝึกตอบในแชท')),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ));
        }
      case _StudyTab.glossary:
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(tr('อภิธานศัพท์'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ));
        children.add(NotebookCard(
          key: const ValueKey('study-glossary'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, t) in g.glossary.indexed) ...[
              if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
              Padding(
                key: ValueKey('study-term-$i'),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 3), child: Icon(LucideIcons300.bookA, size: 16, color: _teal)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t.term, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.35))),
                  ]),
                  if (t.definition.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 24, top: 2),
                      child: Text(t.definition, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: cs.onSurfaceVariant)),
                    ),
                  if (t.sourceIds.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(left: 24, top: 6), child: StudioSourceChips(c: widget.c, sources: sources, ids: t.sourceIds, max: 2)),
                ]),
              ),
            ],
          ]),
        ));
    }
    return ListView(key: const ValueKey('notebook-study-guide'), padding: studioPadding(context), children: children);
  }

  Widget _quizCard(BuildContext context, int i, StudyQuestion q, List<StudioSourceRef> sources) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final open = _shown.contains(i);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NotebookCard(
        key: ValueKey('study-q$i'),
        border: open ? _teal.withValues(alpha: 0.45) : null,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => open ? _shown.remove(i) : _shown.add(i));
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _numberDot(i + 1, _teal),
            const SizedBox(width: 12),
            Expanded(child: Text(q.q, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.45))),
            const SizedBox(width: 6),
            Icon(open ? NxI.caretUp : NxI.caretDown, size: 18, color: theme.hintColor),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !open
                ? Padding(
                    padding: const EdgeInsets.only(left: 38, top: 6),
                    child: Text(tr('แตะเพื่อดูเฉลย'), key: ValueKey('study-q$i-reveal'), style: theme.textTheme.labelMedium?.copyWith(color: _teal, fontWeight: FontWeight.w700)),
                  )
                : Container(
                    key: ValueKey('study-q$i-answer'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 38, top: 10),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(color: _teal.withValues(alpha: dark ? 0.2 : 0.08), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('เฉลย'), style: theme.textTheme.labelSmall?.copyWith(color: dark ? const Color(0xFF5EEAD4) : _teal, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(q.a.isEmpty ? '—' : q.a, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                      if (q.sourceIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        StudioSourceChips(c: widget.c, sources: sources, ids: q.sourceIds),
                      ],
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------------- faq

class FaqView extends StatefulWidget {
  const FaqView({super.key, required this.c, required this.note, required this.items});
  final NotebookController c;
  final NotebookNote note;
  final List<StudyQuestion> items;

  @override
  State<FaqView> createState() => _FaqViewState();
}

class _FaqViewState extends State<FaqView> {
  final Set<int> _open = {0};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final sources = studioSources(widget.note.meta);
    final items = widget.items;
    final all = _open.length == items.length;
    const blue = Color(0xFF0284C7);
    return ListView(key: const ValueKey('notebook-faq'), padding: studioPadding(context), children: [
      StudioHeader(
        kind: StudioKind.faq,
        title: widget.note.displayTitle,
        template: studioFromTemplate(widget.note.meta),
        stats: ['${items.length} คำถาม'],
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('faq-toggle-all'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () => setState(() => all ? _open.clear() : _open.addAll(List.generate(items.length, (i) => i))),
          icon: Icon(all ? LucideIcons300.chevronsDownUp : LucideIcons300.chevronsUpDown, size: 16),
          label: Text(tr(all ? 'ยุบทั้งหมด' : 'ขยายทั้งหมด')),
        ),
      ),
      for (final (i, q) in items.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NotebookCard(
            key: ValueKey('faq-$i'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            border: _open.contains(i) ? blue.withValues(alpha: 0.4) : null,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _open.contains(i) ? _open.remove(i) : _open.add(i));
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: blue.withValues(alpha: dark ? 0.3 : 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(tr('ถ'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: dark ? const Color(0xFF7DD3FC) : blue)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(q.q, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.45))),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _open.contains(i) ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(NxI.caretDown, size: 18, color: theme.hintColor),
                ),
              ]),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: !_open.contains(i)
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        key: ValueKey('faq-$i-answer'),
                        padding: const EdgeInsets.only(left: 36, top: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          StudioMarkdown(c: widget.c, meta: widget.note.meta, text: q.a.isEmpty ? '—' : q.a, selectable: false),
                          if (q.sourceIds.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            StudioSourceChips(c: widget.c, sources: sources, ids: q.sourceIds),
                          ],
                        ]),
                      ),
              ),
            ]),
          ),
        ),
      if (items.isEmpty) Text(tr('ยังไม่มีคำถาม'), style: TextStyle(color: cs.onSurfaceVariant)),
    ]);
  }
}

// ---------------------------------------------------------------- briefing

class BriefingView extends StatelessWidget {
  const BriefingView({super.key, required this.c, required this.note, required this.briefing});
  final NotebookController c;
  final NotebookNote note;
  final Briefing briefing;

  static const _palette = [Color(0xFF4F46E5), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF8B5CF6)];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final b = briefing;
    final sources = studioSources(note.meta);
    final section = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800);
    return ListView(key: const ValueKey('notebook-briefing'), padding: studioPadding(context), children: [
      StudioHeader(
        kind: StudioKind.briefing,
        title: b.title ?? note.displayTitle,
        template: studioFromTemplate(note.meta),
        stats: [
          if (b.themes.isNotEmpty) '${b.themes.length} ประเด็น',
          if (b.quotes.isNotEmpty) '${b.quotes.length} คำพูด',
        ],
      ),
      if (b.summary.isNotEmpty)
        Container(
          key: const ValueKey('briefing-summary'),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C1D26) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(LucideIcons300.sparkles, size: 16, color: kNotebookAccent),
              const SizedBox(width: 6),
              Text(tr('บทสรุปผู้บริหาร'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: kNotebookAccent)),
            ]),
            const SizedBox(height: 6),
            StudioMarkdown(c: c, meta: note.meta, text: b.summary),
            if (b.summarySourceIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              StudioSourceChips(c: c, sources: sources, ids: b.summarySourceIds),
            ],
          ]),
        ),
      if (b.themes.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(tr('ประเด็นสำคัญ'), style: section)),
        for (final (i, t) in b.themes.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NotebookCard(
              key: ValueKey('briefing-theme-$i'),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _numberDot(i + 1, _palette[i % _palette.length]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (t.title.isNotEmpty) Text(t.title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.35)),
                    if (t.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      StudioMarkdown(c: c, meta: note.meta, text: t.summary, selectable: false),
                    ],
                    if (t.sourceIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      StudioSourceChips(c: c, sources: sources, ids: t.sourceIds),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
      ],
      if (b.quotes.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 8), child: Text(tr('คำพูดสำคัญจากแหล่ง'), style: section)),
        for (final (i, q) in b.quotes.indexed) _quote(context, i, q, sources),
      ],
      if (b.conclusion != null)
        Container(
          key: const ValueKey('briefing-conclusion'),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [const Color(0xFF334155).withValues(alpha: dark ? 0.5 : 0.08), const Color(0xFF4F46E5).withValues(alpha: dark ? 0.3 : 0.06)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(LucideIcons300.flag, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(tr('บทสรุป'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 6),
            StudioMarkdown(c: c, meta: note.meta, text: b.conclusion!),
          ]),
        ),
    ]);
  }

  Widget _quote(BuildContext context, int i, BriefingQuote q, List<StudioSourceRef> sources) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final src = q.sourceId == null ? null : c.sourceById(q.sourceId);
    final canOpen = q.verified && src != null;
    const green = Color(0xFF16A34A);
    final ref = q.sourceId == null ? null : refsFor(sources, [q.sourceId!]).firstOrNull;
    final who = q.attribution ?? ref?.title ?? src?.displayTitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFFDE68A).withValues(alpha: dark ? 0.12 : 0.3),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('briefing-quote-$i'),
          onTap: canOpen ? () => openStudioSource(context, c, q.sourceId!, highlight: q.text, start: q.start, end: q.end) : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFF59E0B), width: 3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(LucideIcons300.quote, size: 18, color: const Color(0xFFB45309).withValues(alpha: 0.8)),
                const Spacer(),
                Container(
                  key: ValueKey(q.verified ? 'briefing-quote-$i-verified' : 'briefing-quote-$i-unverified'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: q.verified ? green.withValues(alpha: dark ? 0.25 : 0.12) : cs.surfaceContainerHighest.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(q.verified ? LucideIcons300.badgeCheck : LucideIcons300.circleAlert, size: 13, color: q.verified ? green : cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(tr(q.verified ? 'ตรงกับต้นฉบับ' : 'ยังไม่ยืนยัน'),
                        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: q.verified ? (dark ? const Color(0xFF86EFAC) : green) : cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Text('“${q.text}”', style: theme.textTheme.bodyLarge?.copyWith(height: 1.55, fontStyle: FontStyle.italic)),
              if (who != null || canOpen) ...[
                const SizedBox(height: 8),
                Row(children: [
                  if (ref != null && ref.n > 0) ...[_numberDot(ref.n, kNotebookAccent, size: 18), const SizedBox(width: 6)],
                  Expanded(child: Text(who == null ? '' : '— $who', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
                  if (canOpen) ...[
                    const SizedBox(width: 6),
                    Text(tr('ดูในแหล่ง'), style: theme.textTheme.labelSmall?.copyWith(color: kNotebookAccent, fontWeight: FontWeight.w800)),
                    const Icon(NxI.caretRight, size: 14, color: kNotebookAccent),
                  ],
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- timeline

class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.c, required this.note, required this.timeline});
  final NotebookController c;
  final NotebookNote note;
  final Timeline timeline;

  static const _amber = Color(0xFFF59E0B);
  static const _avatars = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFEC4899), Color(0xFFF97316), Color(0xFF8B5CF6)];

  /// The server writes "ไม่ระบุ" (or nothing) when a date is not known.
  static bool _noDate(String? d) => d == null || d.trim().isEmpty || const {'ไม่ระบุ', 'n/a', 'unknown', '-', '—'}.contains(d.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final t = timeline;
    final sources = studioSources(note.meta);
    return ListView(key: const ValueKey('notebook-timeline'), padding: studioPadding(context), children: [
      StudioHeader(
        kind: StudioKind.timeline,
        title: note.displayTitle,
        template: studioFromTemplate(note.meta),
        stats: [
          if (t.events.isNotEmpty) '${t.events.length} เหตุการณ์',
          if (t.cast.isNotEmpty) '${t.cast.length} บุคคล',
        ],
      ),
      if (t.events.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text(tr('ลำดับเหตุการณ์'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        for (final (i, e) in t.events.indexed)
          IntrinsicHeight(
            key: ValueKey('timeline-event-$i'),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: CustomPaint(painter: _RailPainter(color: _amber, line: cs.outlineVariant.withValues(alpha: 0.7), first: i == 0, last: i == t.events.length - 1, hollow: _noDate(e.date))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NotebookCard(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _noDate(e.date) ? cs.surfaceContainerHighest.withValues(alpha: 0.8) : _amber.withValues(alpha: dark ? 0.25 : 0.14),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(LucideIcons300.calendarClock, size: 13, color: _noDate(e.date) ? cs.onSurfaceVariant : (dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309))),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _noDate(e.date) ? tr('ไม่ระบุวันที่') : e.date!,
                              key: ValueKey('timeline-date-$i'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: _noDate(e.date) ? cs.onSurfaceVariant : (dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309))),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Text(e.event, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                      if (e.sourceIds.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        StudioSourceChips(c: c, sources: sources, ids: e.sourceIds),
                      ],
                    ]),
                  ),
                ),
              ),
            ]),
          ),
      ],
      if (t.cast.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 10), child: Text(tr('บุคคลและหน่วยงานที่เกี่ยวข้อง'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
        for (final (i, p) in t.cast.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NotebookCard(
              key: ValueKey('timeline-cast-$i'),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _avatars[i % _avatars.length].withValues(alpha: dark ? 0.35 : 0.15),
                  child: Text(p.initials, style: TextStyle(fontWeight: FontWeight.w800, color: dark ? Colors.white : _avatars[i % _avatars.length])),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                    if (p.description.isNotEmpty) Text(p.description, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45)),
                    if (p.sourceIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      StudioSourceChips(c: c, sources: sources, ids: p.sourceIds, max: 3),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// Timeline rail: a line through the row and a dot level with the date pill.
class _RailPainter extends CustomPainter {
  _RailPainter({required this.color, required this.line, required this.first, required this.last, this.hollow = false});
  final Color color;
  final Color line;
  final bool first;
  final bool last;
  final bool hollow;

  @override
  void paint(Canvas canvas, Size size) {
    const dotY = 22.0;
    final x = size.width / 2;
    final l = Paint()
      ..color = line
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, first ? dotY : 0), Offset(x, last ? dotY : size.height), l);
    canvas.drawCircle(Offset(x, dotY), 8, Paint()..color = color.withValues(alpha: 0.22));
    if (hollow) {
      canvas.drawCircle(
          Offset(x, dotY),
          5,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    } else {
      canvas.drawCircle(Offset(x, dotY), 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.color != color || old.line != line || old.first != first || old.last != last || old.hollow != hollow;
}
