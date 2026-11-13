import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai_assistant.dart';
import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../services/nx_speech.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_markdown.dart';
import '../comm_ai/comm_ai_isaac.dart';
import 'notebook_chat_settings.dart';
import 'notebook_sources_pane.dart';
import 'notebook_widgets.dart';

/// "แชท" tab: questions answered only from the enabled sources, with inline
/// `[n]` citations that open the cited passage.
class NotebookChatPane extends StatefulWidget {
  const NotebookChatPane({super.key, required this.c, this.onGoSources, this.onNoteSaved});
  final NotebookController c;

  /// Jump to the sources tab (empty state).
  final VoidCallback? onGoSources;

  /// A reply was saved as a note (e.g. show the studio tab).
  final ValueChanged<NotebookNote>? onNoteSaved;

  @override
  State<NotebookChatPane> createState() => NotebookChatPaneState();
}

class NotebookChatPaneState extends State<NotebookChatPane> {
  NotebookController get c => widget.c;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _listening = false;
  String _speechBase = '';
  bool _guideOpen = true;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (_listening) NxSpeech.instance.stop();
    c.removeListener(_onChange);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    final n = c.messages.length + (c.messages.lastOrNull?.content.length ?? 0);
    if (n != _lastCount) {
      _lastCount = n;
      _toBottom();
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  /// Sends [text] (e.g. from a suggestion or a mind map node).
  void ask(String text) {
    if (text.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _guideOpen = false);
    c.send(text);
    _toBottom();
  }

  /// Puts [text] in the composer (e.g. "ถามในแชท" from a mind map node) without sending.
  void draft(String text) {
    if (text.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _guideOpen = false);
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
  }

  Future<void> _settings() async {
    HapticFeedback.selectionClick();
    // Saved settings show in the indicator above the composer (no snackbar over the input).
    await showNotebookChatSettingsSheet(context, c);
  }

  void _send() {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    if (_listening) {
      NxSpeech.instance.stop();
      _listening = false;
    }
    _input.clear();
    ask(t);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await NxSpeech.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    HapticFeedback.selectionClick();
    _speechBase = _input.text.trim().isEmpty ? '' : '${_input.text.trim()} ';
    final ok = await NxSpeech.instance.start(
      localeId: L10n.isEn ? 'en_US' : 'th_TH',
      onText: (text, done) {
        if (!mounted) return;
        _input.text = '$_speechBase$text';
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        if (done) setState(() => _listening = false);
      },
      onStop: () {
        if (mounted && _listening) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ใช้ไมค์ไม่ได้ — ตรวจสิทธิ์ไมโครโฟนในการตั้งค่าเครื่อง'))));
      return;
    }
    setState(() => _listening = true);
  }

  void _openCitation(AiMessage m, int n) {
    final cites = NotebookCitation.list(m.citations);
    final cite = citationFor(cites, n) ?? NotebookCitation(n: n, title: tr('แหล่งที่ $n'));
    HapticFeedback.selectionClick();
    showCitationSheet(context, c, cite);
  }

  Future<void> _saveNote(AiMessage m) async {
    try {
      final note = await c.saveAsNote(m);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('บันทึกเป็นโน้ตแล้ว')),
        action: widget.onNoteSaved == null ? null : SnackBarAction(label: tr('ดูโน้ต'), onPressed: () => widget.onNoteSaved!(note)),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final noSources = c.enabledSources.isEmpty;
    final items = <Widget>[
      if (noSources) _noSources(context) else _guide(context),
      for (final (i, m) in c.messages.indexed) _message(context, m, last: i == c.messages.length - 1),
      if (c.chatError != null) _errorCard(context),
    ];
    return Column(children: [
      Expanded(
        child: c.chatLoading && c.messages.isEmpty
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : ListView(
                key: const ValueKey('notebook-chat-list'),
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: items,
              ),
      ),
      _composer(context, noSources),
    ]);
  }

  Widget _noSources(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: NotebookState(
        key: const ValueKey('notebook-chat-no-sources'),
        mood: 'curious',
        title: c.sources.isEmpty ? 'ยังไม่มีแหล่งข้อมูล' : 'ยังไม่ได้เลือกแหล่งข้อมูล',
        message: c.sources.isEmpty ? 'เพิ่มไฟล์ ลิงก์ หรือข้อความก่อน แล้วถามไอแซคได้เลย' : 'ติ๊กแหล่งที่อยากให้ไอแซคใช้ตอบในแท็บแหล่งข้อมูล',
        size: 88,
        action: widget.onGoSources == null ? null : FilledButton.tonalIcon(onPressed: widget.onGoSources, icon: const Icon(LucideIcons300.layers, size: 18), label: Text(tr('ไปที่แหล่งข้อมูล'))),
      ),
    );
  }

  Widget _guide(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final g = c.guide;
    final hasChat = c.messages.isNotEmpty;
    final open = _guideOpen || !hasChat;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.topCenter,
      child: Container(
        key: const ValueKey('notebook-guide'),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark ? [const Color(0xFF312E81).withValues(alpha: 0.45), const Color(0xFF1C1D26)] : const [Color(0xFFEEF2FF), Colors.white],
          ),
          border: Border.all(color: kIsaacIndigo.withValues(alpha: 0.16)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: hasChat ? () => setState(() => _guideOpen = !_guideOpen) : null,
            child: Row(children: [
              IsaacAvatar(mood: c.guideLoading ? 'reading' : 'explaining', size: 38, ring: false, animate: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('คู่มือสมุด'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    tr(c.guideLoading ? 'ไอแซคกำลังอ่านแหล่งข้อมูล…' : '${c.enabledSources.length} แหล่งที่เลือก'),
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
              if (g != null && !g.fallback && c.canWrite)
                IconButton(
                  key: const ValueKey('notebook-guide-refresh'),
                  tooltip: tr('สรุปใหม่'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons300.refreshCw, size: 18, color: c.guideStale ? kIsaacIndigo : null),
                  onPressed: c.guideLoading ? null : c.refreshGuide,
                ),
              if (hasChat) Icon(open ? NxI.caretUp : NxI.caretDown, size: 18, color: cs.onSurfaceVariant),
            ]),
          ),
          if (open) ...[
            if (c.guideLoading && g == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: LinearProgressIndicator(minHeight: 2))
            else if (g != null) ...[
              if (g.summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: const ValueKey('notebook-guide-summary'),
                  child: NxMarkdown(
                    data: linkCitations(g.summary),
                    selectable: false,
                    linkStyle: TextStyle(color: kIsaacIndigo, fontWeight: FontWeight.w800, fontSize: 13, backgroundColor: kIsaacIndigo.withValues(alpha: dark ? 0.22 : 0.1)),
                    onOpenLink: (href) {
                      final n = citationFromHref(href);
                      final list = c.enabledSources;
                      if (n == null || n < 1 || n > list.length) return;
                      final s = list[n - 1];
                      showCitationSheet(context, c, NotebookCitation(n: n, sourceId: s.id, title: s.displayTitle));
                    },
                  ),
                ),
              ],
              if (!g.fallback && c.canWrite && (g.stale || c.guideStale))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(child: Text(tr('แหล่งข้อมูลเปลี่ยนแล้ว'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
                    TextButton.icon(
                      key: const ValueKey('notebook-guide-update'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: kIsaacIndigo),
                      onPressed: c.guideLoading ? null : c.refreshGuide,
                      icon: const Icon(LucideIcons300.refreshCw, size: 14),
                      label: Text(tr('อัปเดตคู่มือ')),
                    ),
                  ]),
                ),
              if (c.guideError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr(c.guideError!), key: const ValueKey('notebook-guide-error'), style: theme.textTheme.labelSmall?.copyWith(color: cs.error)),
                ),
              if (c.guideLoading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
              if (g.topics.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in g.topics.take(8))
                    NotebookPill(
                      leading: const Icon(LucideIcons300.hash, size: 13, color: kIsaacIndigo),
                      label: t,
                      onTap: c.sending ? null : () => ask(tr('อธิบายเรื่อง "$t" จากแหล่งข้อมูล')),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              Text(tr('ลองถาม'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              for (final (i, q) in g.questions.take(5).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: ValueKey('notebook-guide-q$i'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: c.sending ? null : () => ask(tr(q)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                        child: Row(children: [
                          const Icon(LucideIcons300.sparkles, size: 16, color: kIsaacIndigo),
                          const SizedBox(width: 10),
                          Expanded(child: Text(tr(q), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                          Icon(NxI.arrowRight, size: 16, color: cs.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _errorCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('notebook-chat-error'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(NxI.warningCircle, color: cs.error, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(tr(c.chatError!), style: TextStyle(color: cs.onErrorContainer))),
        IconButton(icon: const Icon(NxI.x, size: 18), onPressed: c.clearChatError),
      ]),
    );
  }

  Widget _message(BuildContext context, AiMessage m, {required bool last}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF7C3AED)]),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6)),
          ),
          child: SelectableText(m.content, style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, height: 1.45)),
        ),
      );
    }
    final cites = NotebookCitation.list(m.citations);
    final known = {for (final x in cites) x.n};
    final waiting = m.streaming && m.content.trim().isEmpty;
    return Padding(
      key: ValueKey('notebook-answer-${c.messages.indexOf(m)}'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 10),
          child: IsaacAvatar(mood: m.streaming ? (waiting ? 'thinking_dots' : 'speaking') : 'answer_ready', size: 30, ring: false, animate: false),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (waiting)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(tr(aiStatusLabel(c.status)), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                ]),
              )
            else
              NxMarkdown(
                data: m.streaming ? m.content : linkCitations(m.content, known: known.isEmpty ? null : known),
                streaming: m.streaming,
                linkStyle: TextStyle(color: kIsaacIndigo, fontWeight: FontWeight.w800, fontSize: 13, backgroundColor: kIsaacIndigo.withValues(alpha: dark ? 0.22 : 0.1)),
                onOpenLink: (href) {
                  final n = citationFromHref(href);
                  if (n != null) {
                    _openCitation(m, n);
                  } else {
                    final u = Uri.tryParse(href);
                    if (u != null) launchExternal(u);
                  }
                },
              ),
            if (!m.streaming && cites.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in cites)
                  NotebookPill(
                    key: ValueKey('notebook-cite-chip-${x.n}'),
                    leading: CircleAvatar(radius: 9, backgroundColor: kIsaacIndigo, child: Text('${x.n}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800))),
                    label: x.title.isEmpty ? tr('แหล่งที่ ${x.n}') : x.title,
                    onTap: () => _openCitation(m, x.n),
                  ),
              ]),
            ],
            if (!m.streaming && m.content.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 0, children: [
                _action(
                  context,
                  key: 'notebook-save-note',
                  icon: c.savedAsNote.contains(m) ? NxI.checkCircle : LucideIcons300.notebookPen,
                  label: c.savedAsNote.contains(m) ? 'บันทึกแล้ว' : 'บันทึกเป็นโน้ต',
                  onTap: c.savedAsNote.contains(m) ? null : () => _saveNote(m),
                ),
                _action(context, key: 'notebook-copy', icon: NxI.copySimple, label: 'คัดลอก', onTap: () {
                  Clipboard.setData(ClipboardData(text: m.content));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('คัดลอกแล้ว'))));
                }),
                _action(context, key: 'notebook-share', icon: NxI.shareNetwork, label: 'แชร์', onTap: () => Share.share(m.content)),
                if (last) _action(context, key: 'notebook-regenerate', icon: LucideIcons300.refreshCw, label: 'ตอบใหม่', onTap: c.sending ? null : c.regenerate),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _action(BuildContext context, {required String key, required IconData icon, required String label, VoidCallback? onTap}) {
    return TextButton.icon(
      key: ValueKey(key),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8), foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(tr(label), style: const TextStyle(fontSize: 12.5)),
    );
  }

  Widget _composer(BuildContext context, bool noSources) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final canSend = _input.text.trim().isNotEmpty && !noSources;
    final settings = c.chatSettings;
    final custom = !settings.isDefault;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (custom)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Material(
                color: kIsaacIndigo.withValues(alpha: dark ? 0.22 : 0.1),
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('notebook-chat-settings-indicator'),
                  onTap: c.canWrite ? _settings : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons300.slidersHorizontal, size: 14, color: dark ? const Color(0xFFA5B4FC) : kIsaacIndigo),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [for (final p in settings.summaryParts) tr(p)].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: dark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C1D26) : Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _focus.hasFocus ? kIsaacIndigo.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (c.canWrite)
              IconButton(
                key: const ValueKey('notebook-chat-settings'),
                tooltip: tr('ตั้งค่าแชท'),
                onPressed: _settings,
                icon: Badge(
                  isLabelVisible: custom,
                  smallSize: 8,
                  backgroundColor: kIsaacIndigo,
                  child: Icon(LucideIcons300.slidersHorizontal, color: custom ? kIsaacIndigo : null),
                ),
              ),
            IconButton(
              key: const ValueKey('notebook-mic'),
              tooltip: tr(_listening ? 'หยุดฟัง' : 'พูดคำถาม'),
              onPressed: noSources ? null : _toggleMic,
              icon: Icon(_listening ? NxI.stop : NxI.microphone, color: _listening ? cs.error : null),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('notebook-chat-input'),
                controller: _input,
                focusNode: _focus,
                enabled: !noSources,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: tr(noSources ? 'เลือกแหล่งข้อมูลก่อนถาม' : (_listening ? 'กำลังฟัง…' : 'ถามจากแหล่งข้อมูลของคุณ')),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(2),
              child: c.sending
                  ? IconButton.filled(
                      key: const ValueKey('notebook-stop'),
                      tooltip: tr('หยุด'),
                      style: IconButton.styleFrom(backgroundColor: cs.error),
                      onPressed: c.stop,
                      icon: const Icon(NxI.stop, color: Colors.white, size: 20),
                    )
                  : IconButton.filled(
                      key: const ValueKey('notebook-send'),
                      tooltip: tr('ส่ง'),
                      style: IconButton.styleFrom(backgroundColor: kIsaacIndigo, disabledBackgroundColor: cs.surfaceContainerHighest),
                      onPressed: canSend ? _send : null,
                      icon: const Icon(NxI.paperPlaneTilt, color: Colors.white, size: 20),
                    ),
            ),
          ]),
          ),
        ]),
      ),
    );
  }
}

/// Opens [u] outside the app (links in answers).
void launchExternal(Uri u) {
  if (u.scheme != 'http' && u.scheme != 'https') return;
  unawaited(_launch(u));
}

Future<void> _launch(Uri u) async {
  try {
    await NotebookLinks.open(u);
  } catch (_) {}
}

/// Link opener (tests replace it).
class NotebookLinks {
  NotebookLinks._();
  static Future<void> Function(Uri u) open = (u) async {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  };
}

/// The passage behind `[n]`: source title, the quoted passage(s) (server
/// `passages`, else `quote`) or the source's opening lines, and "ไปที่แหล่ง",
/// which opens the source scrolled to the passage and highlighted.
Future<void> showCitationSheet(BuildContext context, NotebookController c, NotebookCitation cite) {
  final source = c.sourceById(cite.sourceId) ?? (cite.sourceId == null && cite.n - 1 < c.enabledSources.length && cite.n > 0 ? c.enabledSources[cite.n - 1] : null);
  return showAppBottomSheet<void>(
    context: context,
    title: null,
    child: Builder(builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;
      final st = source == null ? null : sourceKindStyle(source);
      final preview = source == null ? '' : (source.excerpt.trim().isNotEmpty ? source.excerpt.trim() : source.body.trim());
      final passages = cite.passages.where((p) => p.quote.isNotEmpty).take(4).toList();
      final quote = cite.quote;
      void go({NotebookPassage? p}) {
        if (source == null) return;
        HapticFeedback.selectionClick();
        Navigator.pop(ctx);
        final first = p ?? passages.firstOrNull;
        if (first != null) {
          showSourceViewer(context, c, source, highlight: first.quote, start: first.start, end: first.end);
        } else {
          showSourceViewer(context, c, source, highlight: quote);
        }
      }

      Widget quoteCard(String text, {Key? key, VoidCallback? onTap, int maxLines = 10, String? label}) => Material(
            key: key,
            color: const Color(0xFFFDE68A).withValues(alpha: dark ? 0.16 : 0.4),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFFF59E0B), width: 3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(LucideIcons300.quote, size: 18, color: const Color(0xFFB45309).withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: label == null
                          ? const SizedBox.shrink()
                          : Text(label, style: theme.textTheme.labelSmall?.copyWith(color: dark ? const Color(0xFFFCD34D) : const Color(0xFFB45309), fontWeight: FontWeight.w700)),
                    ),
                    if (onTap != null) Icon(NxI.arrowRight, size: 16, color: const Color(0xFFB45309).withValues(alpha: 0.8)),
                  ]),
                  const SizedBox(height: 6),
                  Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
                ]),
              ),
            ),
          );

      return Column(key: const ValueKey('notebook-citation-sheet'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: kIsaacIndigo, shape: BoxShape.circle),
            child: Text('${cite.n}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                cite.title.isNotEmpty ? cite.title : (source?.displayTitle ?? tr('แหล่งที่ ${cite.n}')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (source != null)
                Row(children: [
                  Icon(st!.icon, size: 13, color: st.color),
                  const SizedBox(width: 4),
                  Flexible(child: Text(tr(notebookSourceKindLabel(source)), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
                  if (passages.length > 1) ...[
                    const SizedBox(width: 6),
                    Text('· ${tr('${passages.length} ข้อความ')}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        if (passages.isNotEmpty) ...[
          for (final (i, p) in passages.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            quoteCard(
              p.quote,
              key: ValueKey('notebook-citation-passage-$i'),
              maxLines: passages.length > 1 ? 6 : 10,
              label: passages.length > 1 ? tr('ข้อความที่ ${i + 1}') : tr('ข้อความที่อ้างอิง'),
              onTap: source == null ? null : () => go(p: p),
            ),
          ],
        ] else if (quote != null)
          quoteCard(quote, key: const ValueKey('notebook-citation-quote'), label: tr('ข้อความที่อ้างอิง'), onTap: source == null ? null : go)
        else if (preview.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
            child: Text(preview, maxLines: 6, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: cs.onSurfaceVariant)),
          )
        else
          Text(tr('ไม่พบแหล่งนี้ในสมุดแล้ว'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (source != null)
          FilledButton.icon(
            key: const ValueKey('notebook-citation-goto'),
            onPressed: go,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: kIsaacIndigo),
            icon: const Icon(NxI.arrowRight, size: 18),
            label: Text(tr('ไปที่แหล่ง')),
          ),
      ]);
    }),
  );
}
