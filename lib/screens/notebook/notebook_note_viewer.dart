import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/nx_page_route.dart';
import '../../services/file_open.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_audio_player_card.dart';
import '../../widgets/nx_confirm_sheet.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_markdown.dart';
import '../../widgets/nx_mermaid_view.dart';
import '../comm_ai/comm_ai_isaac.dart';
import '../docs/document_preview.dart';
import 'notebook_chat_pane.dart' show showCitationSheet;
import 'notebook_widgets.dart';

/// Opens a note / studio output in its native viewer.
Future<void> openNotebookNote(BuildContext context, NotebookController c, NotebookNote note, {ValueChanged<String>? onAsk}) =>
    nxPush<void>(context, NotebookNoteScreen(c: c, note: note, onAsk: onAsk));

class NotebookNoteScreen extends StatefulWidget {
  const NotebookNoteScreen({super.key, required this.c, required this.note, this.onAsk});
  final NotebookController c;
  final NotebookNote note;
  final ValueChanged<String>? onAsk;

  @override
  State<NotebookNoteScreen> createState() => _NotebookNoteScreenState();
}

class _NotebookNoteScreenState extends State<NotebookNoteScreen> {
  late NotebookNote _n = widget.note;

  bool get _editable => const {'note', 'report', 'table', 'styleguide', 'video', 'audio', 'mindmap'}.contains(_n.kind);

  Future<void> _edit() async {
    final fresh = await Navigator.of(context).push<NotebookNote>(MaterialPageRoute(builder: (_) => NotebookNoteEditor(c: widget.c, note: _n)));
    if (fresh != null && mounted) setState(() => _n = fresh);
  }

  Future<void> _more() async {
    final pick = await showAppBottomSheet<String>(
      context: context,
      title: null,
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(NxI.copySimple), title: Text(tr('คัดลอกเนื้อหา')), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: const Icon(NxI.shareNetwork), title: Text(tr('แชร์เป็นข้อความ')), onTap: () => Navigator.pop(ctx, 'share')),
          if (_editable) ListTile(leading: const Icon(NxI.pencilSimple), title: Text(tr('แก้ไข')), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            key: const ValueKey('notebook-note-delete'),
            leading: const Icon(NxI.trash, color: kNxDangerRed),
            title: Text(tr('ลบโน้ต'), style: const TextStyle(color: kNxDangerRed, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || pick == null) return;
    switch (pick) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _n.content));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('คัดลอกแล้ว'))));
      case 'share':
        await Share.share('${_n.displayTitle}\n\n${_n.content}');
      case 'edit':
        await _edit();
      case 'delete':
        final ok = await showDeleteConfirm(context, name: _n.displayTitle, loses: const ['เนื้อหาของโน้ตนี้'], note: null);
        if (!ok || !mounted) return;
        try {
          await widget.c.deleteNote(_n);
          if (mounted) Navigator.of(context).maybePop();
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = _n.studio ?? StudioKind.note;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: NxAppHeader(
            title: _n.displayTitle,
            subtitle: _n.displayTitle == k.label ? 'ไอแซคเอไอ' : k.label,
            actions: [
              if (_editable)
                IconButton(key: const ValueKey('notebook-note-edit'), tooltip: tr('แก้ไข'), icon: const Icon(NxI.pencilSimple), onPressed: _edit),
              IconButton(key: const ValueKey('notebook-note-more'), tooltip: tr('ตัวเลือก'), icon: const Icon(NxI.dotsThreeVertical), onPressed: _more),
            ],
          ),
        ),
      ),
      body: NotebookBackdrop(
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: NotebookNoteBody(c: widget.c, note: _n, onAsk: widget.onAsk == null
                  ? null
                  : (q) {
                      Navigator.of(context).maybePop();
                      widget.onAsk!(q);
                    }),
            ),
          ),
        ),
      ),
    );
  }
}

/// The note rendered by kind (used full-screen and in tests).
class NotebookNoteBody extends StatelessWidget {
  const NotebookNoteBody({super.key, required this.c, required this.note, this.onAsk});
  final NotebookController c;
  final NotebookNote note;
  final ValueChanged<String>? onAsk;

  @override
  Widget build(BuildContext context) {
    final n = note;
    final pad = EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom);
    switch (n.kind) {
      case 'flashcards':
        final cards = parseFlashcards(n.content);
        if (cards.isNotEmpty) return FlashcardsView(cards: cards);
      case 'quiz':
        final qs = parseQuiz(n.content);
        if (qs.isNotEmpty) return QuizView(questions: qs);
    }
    final children = <Widget>[];
    if (n.kind == 'audio') {
      final url = n.downloadUrl;
      children.add(url == null
          ? NotebookCard(
              child: Row(children: [
                const IsaacAvatar(mood: 'shrug', size: 44, ring: false, animate: false),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('ยังไม่มีไฟล์เสียง (เซิร์ฟเวอร์ยังไม่ได้ตั้งค่าเสียงพูด) — อ่านสคริปต์ด้านล่างได้'))),
              ]),
            )
          : NxAudioPlayerCard(
              title: n.displayTitle,
              subtitle: tr('ไอแซคสรุปเป็นเสียง'),
              fileName: n.fileName,
              load: () => c.downloadExport(url),
              trailing: const IsaacAvatar(mood: 'speaking', size: 34, ring: false, animate: false),
            ));
      children.add(const NotebookSectionLabel('สคริปต์'));
    } else if (n.kind == 'mindmap') {
      final root = parseMindmap(n.content);
      if (root != null) {
        children.add(MindmapView(root: root, onAsk: onAsk));
        final code = mermaidCode(n.content);
        if (code != null) {
          children.add(Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('notebook-mindmap-diagram'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NxMermaidView(code: code))),
              icon: const Icon(LucideIcons300.network, size: 16),
              label: Text(tr('ดูเป็นไดอะแกรม')),
            ),
          ));
        }
        if (n.downloadUrl != null) children.add(NotebookDownloadCard(c: c, note: n));
        return ListView(padding: pad, children: children);
      }
    } else if (n.kind == 'infographic') {
      children.add(NotebookCard(
        key: const ValueKey('notebook-infographic'),
        padding: const EdgeInsets.all(14),
        child: NxHtmlView(html: n.content),
      ));
      return ListView(padding: pad, children: children);
    }
    if (n.downloadUrl != null && n.kind != 'audio') children.add(NotebookDownloadCard(c: c, note: n));
    final cites = NotebookCitation.list([for (final x in (n.meta['citations'] is List ? n.meta['citations'] as List : const [])) if (x is Map) Map<String, dynamic>.from(x)]);
    final question = '${n.meta['question'] ?? ''}'.trim();
    if (question.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(LucideIcons300.messageCircleQuestion, size: 18, color: kNotebookAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(question, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
        ]),
      ));
    }
    children.add(NotebookCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: NxMarkdown(
        data: cites.isEmpty ? n.content : linkCitations(n.content, known: {for (final x in cites) x.n}),
        onOpenLink: (href) {
          final i = citationFromHref(href);
          if (i != null) {
            final cite = citationFor(cites, i);
            if (cite != null) showCitationSheet(context, c, cite);
          }
        },
      ),
    ));
    return ListView(padding: pad, children: children);
  }
}

/// PDF / XLSX / MP3 from the studio: preview (PDF), open, share — downloaded with the session.
class NotebookDownloadCard extends StatefulWidget {
  const NotebookDownloadCard({super.key, required this.c, required this.note});
  final NotebookController c;
  final NotebookNote note;

  @override
  State<NotebookDownloadCard> createState() => _NotebookDownloadCardState();
}

class _NotebookDownloadCardState extends State<NotebookDownloadCard> {
  bool _busy = false;

  Future<void> _go(Future<void> Function(List<int> bytes) f) async {
    final url = widget.note.downloadUrl;
    if (url == null) return;
    setState(() => _busy = true);
    try {
      await f(await widget.c.downloadExport(url));
    } catch (e) {
      if (mounted) {
        final expired = widget.note.downloadExpired;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(expired ? 'ไฟล์หมดอายุแล้ว — สร้างใหม่ในสตูดิโอ' : notebookError(e).text))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.note.fileName;
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : 'FILE';
    final isPdf = ext == 'PDF';
    final (IconData icon, Color color) = switch (ext) {
      'PDF' => (LucideIcons300.fileText, const Color(0xFFDC2626)),
      'XLSX' || 'XLS' || 'CSV' => (LucideIcons300.sheet, const Color(0xFF16A34A)),
      'MP3' || 'M4A' || 'WAV' => (LucideIcons300.audioLines, const Color(0xFF8B5CF6)),
      _ => (LucideIcons300.file, kNotebookAccent),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NotebookCard(
        key: const ValueKey('notebook-download'),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(children: [
          NotebookIconBadge(icon: icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(widget.note.downloadExpired ? tr('ลิงก์หมดอายุ') : ext, style: theme.textTheme.labelSmall?.copyWith(color: widget.note.downloadExpired ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          if (!_busy && isPdf)
            IconButton(
              key: const ValueKey('notebook-download-preview'),
              tooltip: tr('ดูตัวอย่าง'),
              icon: const Icon(NxI.eye, size: 20),
              onPressed: () {
                final url = widget.note.downloadUrl!;
                final base = name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
                openDocumentPreview(
                  context,
                  DocumentSource(
                    title: widget.note.displayTitle,
                    fileBase: base,
                    variants: [DocVariant(id: 'file', label: 'PDF', birt: false, fetch: (_) => widget.c.downloadExport(url))],
                  ),
                );
              },
            ),
          if (!_busy)
            IconButton(key: const ValueKey('notebook-download-open'), tooltip: tr('เปิด'), icon: const Icon(NxI.arrowSquareOut, size: 20), onPressed: () => _go((b) => openFileBytes(b, name))),
          if (!_busy)
            IconButton(key: const ValueKey('notebook-download-share'), tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork, size: 20), onPressed: () => _go((b) => shareFileBytes(b, name))),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------- flashcards

class FlashcardsView extends StatefulWidget {
  const FlashcardsView({super.key, required this.cards});
  final List<Flashcard> cards;

  @override
  State<FlashcardsView> createState() => _FlashcardsViewState();
}

class _FlashcardsViewState extends State<FlashcardsView> {
  late List<Flashcard> _cards = widget.cards;
  final _page = PageController(viewportFraction: 0.9);
  int _i = 0;
  final Set<int> _flipped = {};
  final Set<int> _known = {};

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= _cards.length) return;
    _page.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(key: const ValueKey('notebook-flashcards'), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
        child: Row(children: [
          Text(tr('การ์ด ${_i + 1}/${_cards.length}'), key: const ValueKey('flashcard-counter'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (_known.isNotEmpty) Text(tr('จำได้ ${_known.length}'), style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            key: const ValueKey('flashcard-shuffle'),
            tooltip: tr('สลับลำดับ'),
            icon: const Icon(LucideIcons300.shuffle, size: 20),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() {
                _cards = [..._cards]..shuffle(math.Random());
                _flipped.clear();
                _known.clear();
              });
              _page.jumpToPage(0);
            },
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(value: (_i + 1) / _cards.length, minHeight: 4, color: const Color(0xFFEF4444), backgroundColor: cs.surfaceContainerHighest),
        ),
      ),
      Expanded(
        child: PageView.builder(
          controller: _page,
          itemCount: _cards.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
            child: _FlipCard(
              key: ValueKey('flashcard-$i'),
              card: _cards[i],
              flipped: _flipped.contains(i),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _flipped.contains(i) ? _flipped.remove(i) : _flipped.add(i));
              },
            ),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Row(children: [
            IconButton.filledTonal(key: const ValueKey('flashcard-prev'), tooltip: tr('ก่อนหน้า'), onPressed: _i > 0 ? () => _go(_i - 1) : null, icon: const Icon(NxI.caretLeft)),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('flashcard-known'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: _known.contains(_i) ? const Color(0xFF16A34A) : null),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _known.contains(_i) ? _known.remove(_i) : _known.add(_i));
                  if (_known.contains(_i)) _go(_i + 1);
                },
                icon: Icon(_known.contains(_i) ? NxI.checkCircle : NxI.check, size: 18),
                label: Text(tr(_known.contains(_i) ? 'จำได้แล้ว' : 'จำได้')),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(key: const ValueKey('flashcard-next'), tooltip: tr('ถัดไป'), onPressed: _i < _cards.length - 1 ? () => _go(_i + 1) : null, icon: const Icon(NxI.caretRight)),
          ]),
        ),
      ),
    ]);
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({super.key, required this.card, required this.flipped, required this.onTap});
  final Flashcard card;
  final bool flipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: flipped ? 1 : 0),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        builder: (context, t, _) {
          final back = t > 0.5;
          final angle = t * math.pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: back
                ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateY(math.pi), child: _face(context, back: true))
                : _face(context, back: false),
          );
        },
      ),
    );
  }

  Widget _face(BuildContext context, {required bool back}) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final text = back ? card.back : card.front;
    return Container(
      key: ValueKey(back ? 'flashcard-back' : 'flashcard-front'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: back
            ? null
            : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEF4444), Color(0xFFBE123C)]),
        color: back ? (dark ? const Color(0xFF1C1D26) : Colors.white) : null,
        border: back ? Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35), width: 1.5) : null,
        boxShadow: [BoxShadow(color: const Color(0xFFBE123C).withValues(alpha: dark ? 0.25 : 0.18), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: back ? const Color(0xFFEF4444).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
            child: Text(tr(back ? 'คำตอบ' : 'คำถาม'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: back ? const Color(0xFFDC2626) : Colors.white)),
          ),
          const Spacer(),
          Icon(LucideIcons300.rotateCcw, size: 18, color: back ? theme.hintColor : Colors.white70),
        ]),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Text(
                text.isEmpty ? '—' : text,
                textAlign: TextAlign.center,
                style: (back ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(
                  color: back ? null : Colors.white,
                  fontWeight: back ? FontWeight.w600 : FontWeight.w800,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
        Center(child: Text(tr(back ? 'แตะเพื่อดูคำถาม' : 'แตะเพื่อดูคำตอบ'), style: TextStyle(fontSize: 12, color: back ? theme.hintColor : Colors.white70))),
      ]),
    );
  }
}

// --------------------------------------------------------------------- quiz

class QuizView extends StatefulWidget {
  const QuizView({super.key, required this.questions});
  final List<QuizQuestion> questions;

  @override
  State<QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<QuizView> {
  final Map<int, int> _picked = {};
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final qs = widget.questions;
    final score = quizScore(qs, _picked);
    final ratio = qs.isEmpty ? 0.0 : score / qs.length;
    return ListView(
      key: const ValueKey('notebook-quiz'),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (_checked)
          Container(
            key: const ValueKey('quiz-score'),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(colors: ratio >= 0.7 ? const [Color(0xFF10B981), Color(0xFF0EA5E9)] : const [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
            ),
            child: Row(children: [
              IsaacAvatar(mood: ratio >= 0.7 ? 'celebrate' : (ratio >= 0.4 ? 'confident' : 'learning'), size: 60, animate: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('คะแนน $score/${qs.length}'), style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text(
                    tr(ratio >= 0.7 ? 'เยี่ยมมาก! เข้าใจเนื้อหาดีแล้ว' : (ratio >= 0.4 ? 'ดีเลย ทบทวนข้อที่ผิดอีกนิด' : 'ลองอ่านแหล่งข้อมูลอีกครั้งแล้วทำใหม่')),
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                  ),
                ]),
              ),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(tr('ตอบแล้ว ${_picked.length}/${qs.length} ข้อ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
        for (final (qi, q) in qs.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NotebookCard(
              key: ValueKey('quiz-q$qi'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${qi + 1}. ${q.prompt}', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.4)),
                const SizedBox(height: 10),
                for (final (oi, opt) in q.options.indexed) _option(context, qi, oi, opt, q),
                if (_checked && q.explanation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(q.explanation!, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        if (!_checked)
          FilledButton(
            key: const ValueKey('quiz-check'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _picked.isEmpty
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    setState(() => _checked = true);
                  },
            child: Text(tr('ตรวจคำตอบ')),
          )
        else
          OutlinedButton.icon(
            key: const ValueKey('quiz-retry'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => setState(() {
              _picked.clear();
              _checked = false;
            }),
            icon: const Icon(LucideIcons300.rotateCcw, size: 18),
            label: Text(tr('ทำใหม่')),
          ),
      ],
    );
  }

  Widget _option(BuildContext context, int qi, int oi, String opt, QuizQuestion q) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _picked[qi] == oi;
    final right = _checked && oi == q.answer;
    final wrong = _checked && selected && oi != q.answer;
    final Color border = right ? const Color(0xFF16A34A) : (wrong ? cs.error : (selected ? kNotebookAccent : cs.outlineVariant.withValues(alpha: 0.6)));
    final Color? fill = right
        ? const Color(0xFF16A34A).withValues(alpha: 0.1)
        : (wrong ? cs.error.withValues(alpha: 0.08) : (selected ? kNotebookAccent.withValues(alpha: 0.08) : null));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('quiz-q$qi-o$oi'),
          borderRadius: BorderRadius.circular(14),
          onTap: _checked
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _picked[qi] = oi);
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: selected || right ? 1.5 : 1)),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: selected || right ? border : Colors.transparent, border: Border.all(color: border)),
                child: right
                    ? const Icon(NxI.check, size: 14, color: Colors.white)
                    : wrong
                        ? const Icon(NxI.x, size: 14, color: Colors.white)
                        : Text(String.fromCharCode(65 + oi), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : cs.onSurfaceVariant)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(opt, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ mindmap

/// Native mind map: the root as a hero, branches as coloured cards, leaves as
/// chips (collapsible); tap a node to ask about it in the chat.
class MindmapView extends StatefulWidget {
  const MindmapView({super.key, required this.root, this.onAsk});
  final MindNode root;
  final ValueChanged<String>? onAsk;

  @override
  State<MindmapView> createState() => _MindmapViewState();
}

class _MindmapViewState extends State<MindmapView> {
  final Set<MindNode> _closed = {};

  static const _branch = [Color(0xFF6366F1), Color(0xFF0EA5E9), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF14B8A6)];

  void _ask(MindNode n) {
    final cb = widget.onAsk;
    if (cb == null) return;
    HapticFeedback.selectionClick();
    showAppBottomSheet<void>(
      context: context,
      title: null,
      child: Builder(
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(n.label, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('mindmap-ask'),
            onPressed: () {
              Navigator.pop(ctx);
              cb(tr('อธิบายเรื่อง "${n.label}" จากแหล่งข้อมูล'));
            },
            icon: const Icon(LucideIcons300.messagesSquare, size: 18),
            label: Text(tr('ถามไอแซคเรื่องนี้')),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final root = widget.root;
    return Column(key: const ValueKey('notebook-mindmap'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
        onTap: () => _ask(root),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFEC4899)]),
            boxShadow: [BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(children: [
            const Icon(LucideIcons300.brainCircuit, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(child: Text(root.label, key: const ValueKey('mindmap-root'), style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800))),
            Text(tr('${root.size - 1} หัวข้อ'), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      for (final (i, b) in root.children.indexed) _branchCard(context, b, _branch[i % _branch.length], last: i == root.children.length - 1),
    ]);
  }

  Widget _branchCard(BuildContext context, MindNode b, Color color, {bool last = false}) {
    final theme = Theme.of(context);
    final open = !_closed.contains(b);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 18,
            child: CustomPaint(painter: _ElbowPainter(color: color.withValues(alpha: 0.55), trunk: const Color(0xFFEC4899).withValues(alpha: 0.35), last: last)),
          ),
          Expanded(
            child: NotebookCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              border: color.withValues(alpha: 0.35),
              onTap: b.children.isEmpty ? () => _ask(b) : () => setState(() => open ? _closed.add(b) : _closed.remove(b)),
              onLongPress: () => _ask(b),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(b.label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.3))),
                  if (b.children.isNotEmpty) Icon(open ? NxI.caretUp : NxI.caretDown, size: 18, color: theme.hintColor),
                ]),
                if (open && b.children.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final leaf in b.children) _leaf(context, leaf, color)]),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _leaf(BuildContext context, MindNode n, Color color) {
    final theme = Theme.of(context);
    final more = n.children.isEmpty ? '' : '  +${n.size - 1}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => n.children.isEmpty ? _ask(n) : _showSub(n, color),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text('${n.label}$more', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showSub(MindNode n, Color color) {
    showNxSnapSheet<void>(
      context: context,
      title: n.label,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [MindmapView(root: n, onAsk: widget.onAsk == null ? null : (q) {
          Navigator.pop(ctx);
          widget.onAsk!(q);
        })],
      ),
    );
  }
}

/// Trunk down the left (through to the next branch unless [last]) and an elbow into this branch.
class _ElbowPainter extends CustomPainter {
  _ElbowPainter({required this.color, required this.trunk, required this.last});
  final Color color;
  final Color trunk;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Paint()
      ..color = trunk
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(6, -10), Offset(6, last ? 18 : size.height + 10), t);
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(6, 18)
      ..quadraticBezierTo(6, 24, 12, 24)
      ..lineTo(size.width, 24);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ElbowPainter old) => old.color != color || old.last != last || old.trunk != trunk;
}

// ------------------------------------------------------------------- editor

/// New note (no [note]) or edit an existing one.
class NotebookNoteEditor extends StatefulWidget {
  const NotebookNoteEditor({super.key, required this.c, this.note});
  final NotebookController c;
  final NotebookNote? note;

  @override
  State<NotebookNoteEditor> createState() => _NotebookNoteEditorState();
}

class _NotebookNoteEditorState extends State<NotebookNoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.content ?? '');
  bool _saving = false;
  bool _preview = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final n = widget.note;
      final NotebookNote out;
      if (n == null) {
        out = await widget.c.addNote(title: _title.text, content: _body.text);
      } else {
        out = await widget.c.updateNote(n, title: _title.text.trim(), content: _body.text);
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: NxAppHeader(
            title: widget.note == null ? 'โน้ตใหม่' : 'แก้ไขโน้ต',
            actions: [
              IconButton(
                tooltip: tr(_preview ? 'แก้ไข' : 'ดูตัวอย่าง'),
                icon: Icon(_preview ? NxI.pencilSimple : NxI.eye),
                onPressed: () => setState(() => _preview = !_preview),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: const ValueKey('notebook-note-save'),
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(tr('บันทึก')),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              TextField(
                key: const ValueKey('notebook-note-title'),
                controller: _title,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                decoration: InputDecoration(hintText: tr('หัวข้อโน้ต'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
              ),
              const Divider(),
              if (_preview)
                NxMarkdown(data: _body.text.isEmpty ? tr('_(ยังไม่มีเนื้อหา)_') : _body.text)
              else
                TextField(
                  key: const ValueKey('notebook-note-body'),
                  controller: _body,
                  autofocus: widget.note == null,
                  minLines: 12,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                  decoration: InputDecoration(hintText: tr('จดอะไรก็ได้ — รองรับ Markdown'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
