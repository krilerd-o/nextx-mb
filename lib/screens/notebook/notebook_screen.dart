import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/notebook/notebook_recording.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_sliding_segmented.dart';
import 'notebook_chat_pane.dart';
import 'notebook_home_screen.dart' show showNotebookEditSheet;
import 'notebook_note_viewer.dart';
import 'notebook_recorder_ui.dart';
import 'notebook_share_sheet.dart';
import 'notebook_sources_pane.dart';
import 'notebook_studio_pane.dart';
import 'notebook_widgets.dart';

enum NotebookTab { sources, chat, studio }

/// `/notebook/:id` — one notebook: แหล่งข้อมูล / แชท / สตูดิโอ. Phones switch
/// tabs; a tablet shows sources + chat (studio switches with sources); wide
/// screens show all three panes.
class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key, required this.id, this.controller, this.initialTab, this.openRecordingId, this.openNoteId});
  final String id;

  /// From "ไอแซคสรุปบันทึกเสียงเสร็จแล้ว" (toast / push): open that recording's summary note after load.
  final String? openRecordingId;
  final String? openNoteId;

  /// For tests.
  final NotebookController? controller;
  final NotebookTab? initialTab;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  late final NotebookController _c = widget.controller ?? NotebookController(context.read<AppConfig>().apiClient, widget.id);
  NotebookTab? _tab;
  NotebookTab _side = NotebookTab.sources;
  final _chatKey = GlobalKey<NotebookChatPaneState>();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    if (widget.initialTab == NotebookTab.studio) _side = NotebookTab.studio;
    _c.addListener(_onChange);
    _c.guideLocale = L10n.isEn ? 'en' : 'th';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _c.init();
      if (mounted) await _openFromLink();
    });
  }

  /// `?recording=&note=`: show the summary note made from a recording.
  Future<void> _openFromLink() async {
    var nid = widget.openNoteId;
    final rid = widget.openRecordingId;
    if (_c.notebook == null || ((nid == null || nid.isEmpty) && (rid == null || rid.isEmpty))) return;
    if ((nid == null || nid.isEmpty) && rid != null) {
      nid = _c.recordingNotes[rid];
      if (nid == null) {
        try {
          nid = NotebookRecording.fromJson(await _c.api.getNotebookRecording(widget.id, rid)).noteId;
        } catch (_) {}
      }
    }
    if (nid == null || !mounted) return;
    var note = _c.noteById(nid);
    if (note == null) {
      await _c.load(quiet: true);
      note = _c.noteById(nid);
    }
    if (note != null && mounted) await openNotebookNote(context, _c, note, onAsk: _ask, onDraft: _draft);
  }

  Future<void> _record() async {
    HapticFeedback.selectionClick();
    await startNotebookRecording(context, _c);
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // First load: open on the chat when there is something to ask about.
    if (_tab == null && _c.notebook != null) _tab = _c.sources.isEmpty ? NotebookTab.sources : NotebookTab.chat;
    setState(() {});
  }

  void _setTab(NotebookTab t) {
    HapticFeedback.selectionClick();
    setState(() {
      _tab = t;
      if (t != NotebookTab.chat) _side = t;
    });
  }

  void _ask(String q) {
    _setTab(NotebookTab.chat);
    WidgetsBinding.instance.addPostFrameCallback((_) => _chatKey.currentState?.ask(q));
  }

  /// Switches to the chat with [q] in the composer (not sent yet).
  void _draft(String q) {
    _setTab(NotebookTab.chat);
    WidgetsBinding.instance.addPostFrameCallback((_) => _chatKey.currentState?.draft(q));
  }

  Future<void> _edit() async {
    final nb = _c.notebook;
    if (nb == null) return;
    final out = await showNotebookEditSheet(context, initial: nb);
    if (out == null) return;
    try {
      await _c.rename(out.title, description: out.description);
      if (out.visibility != nb.visibility) await _c.api.updateNotebook(nb.id, {'visibility': out.visibility});
      nb.visibility = out.visibility;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nb = _c.notebook;
    final title = nb == null ? 'สมุดโน้ต' : (nb.title.isEmpty ? 'สมุดโน้ต' : nb.title);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: NxAppHeader(
            title: title,
            subtitle: nb == null ? 'ไอแซคเอไอ' : tr('${_c.sources.length} แหล่ง · ${_c.notes.length} โน้ต'),
            actions: [
              if (nb != null && _c.canRecord)
                _RecordAction(c: _c, onTap: _record),
              if (nb != null && nb.canWrite)
                IconButton(
                  key: const ValueKey('notebook-share-open'),
                  tooltip: tr('แชร์'),
                  icon: const Icon(NxI.shareNetwork),
                  onPressed: () => showNotebookShareSheet(context, notebook: nb),
                ),
              if (nb != null && nb.canWrite)
                IconButton(key: const ValueKey('notebook-edit'), tooltip: tr('แก้ไขสมุด'), icon: const Icon(NxI.pencilSimple), onPressed: _edit),
            ],
          ),
        ),
      ),
      body: NotebookBackdrop(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_c.disabled) return NotebookDisabledState(message: _c.error);
    if (_c.notebook == null) {
      if (_c.error != null) {
        return NotebookState(
          mood: 'error',
          title: 'เปิดสมุดไม่ได้',
          message: _c.error,
          action: FilledButton.tonal(onPressed: _c.init, child: Text(tr('ลองอีกครั้ง'))),
        );
      }
      return const SingleChildScrollView(key: ValueKey('notebook-loading'), child: NxSkeletonList(rows: 5));
    }
    final sources = NotebookSourcesPane(c: _c);
    final chat = NotebookChatPane(
      key: _chatKey,
      c: _c,
      onGoSources: () => _setTab(NotebookTab.sources),
      onNoteSaved: (n) => openNotebookNote(context, _c, n, onAsk: _ask, onDraft: _draft),
    );
    final studio = NotebookStudioPane(c: _c, onAsk: _ask, onDraft: _draft);
    final bp = NxBreakpoint.of(context);
    if (bp.width >= 1100 && bp.height >= 560) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 340, child: _pane(context, 'แหล่งข้อมูล', LucideIcons300.layers, sources)),
        _divider(context),
        Expanded(child: _pane(context, 'แชท', LucideIcons300.messagesSquare, chat)),
        _divider(context),
        SizedBox(width: 360, child: _pane(context, 'สตูดิโอ', LucideIcons300.wandSparkles, studio)),
      ]);
    }
    if (bp.twoPane) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: bp.width >= 900 ? 380 : 330,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: NxSlidingSegmented<NotebookTab>(
                value: _side,
                options: const [(NotebookTab.sources, 'แหล่งข้อมูล', LucideIcons300.layers), (NotebookTab.studio, 'สตูดิโอ', LucideIcons300.wandSparkles)],
                onChanged: _setTab,
              ),
            ),
            Expanded(child: IndexedStack(index: _side == NotebookTab.studio ? 1 : 0, children: [sources, studio])),
          ]),
        ),
        _divider(context),
        Expanded(child: chat),
      ]);
    }
    final tab = _tab ?? NotebookTab.chat;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: KeyedSubtree(
          key: const ValueKey('notebook-tabs'),
          child: NxSlidingSegmented<NotebookTab>(
          value: tab,
          options: const [
            (NotebookTab.sources, 'แหล่งข้อมูล', LucideIcons300.layers),
            (NotebookTab.chat, 'แชท', LucideIcons300.messagesSquare),
            (NotebookTab.studio, 'สตูดิโอ', LucideIcons300.wandSparkles),
          ],
          onChanged: _setTab,
        ),
        ),
      ),
      Expanded(child: IndexedStack(index: tab.index, children: [sources, chat, studio])),
    ]);
  }

  Widget _divider(BuildContext context) => VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25));

  Widget _pane(BuildContext context, String label, IconData icon, Widget child) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
        child: Row(children: [
          Icon(icon, size: 18, color: kNotebookAccent),
          const SizedBox(width: 8),
          Text(tr(label), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ]),
      ),
      Expanded(child: child),
    ]);
  }
}

/// Header mic: starts a recording (red while this notebook is being recorded).
class _RecordAction extends StatelessWidget {
  const _RecordAction({required this.c, required this.onTap});
  final NotebookController c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c.recorder,
      builder: (context, _) {
        final here = c.recorder.active && c.recorder.notebookId == c.id;
        return IconButton(
          key: const ValueKey('notebook-record'),
          tooltip: tr(here ? 'เปิดหน้าบันทึกเสียง' : 'บันทึกเสียง'),
          onPressed: onTap,
          icon: here
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: kRecordRed, shape: BoxShape.circle),
                  child: const Icon(NxI.microphone, size: 16, color: Colors.white),
                )
              : const Icon(NxI.microphone),
        );
      },
    );
  }
}

/// Kept for deep links such as `/notebook/:id/source/:sid`: opens the source after load.
class NotebookSourceDeepLink extends StatefulWidget {
  const NotebookSourceDeepLink({super.key, required this.id, required this.sourceId});
  final String id;
  final String sourceId;

  @override
  State<NotebookSourceDeepLink> createState() => _NotebookSourceDeepLinkState();
}

class _NotebookSourceDeepLinkState extends State<NotebookSourceDeepLink> {
  late final NotebookController _c = NotebookController(context.read<AppConfig>().apiClient, widget.id);
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_maybeOpen);
  }

  void _maybeOpen() {
    if (_opened || !mounted) return;
    final s = _c.sourceById(widget.sourceId);
    if (s == null) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showSourceViewer(context, _c, s);
    });
  }

  @override
  void dispose() {
    _c.removeListener(_maybeOpen);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotebookScreen(id: widget.id, controller: _c, initialTab: NotebookTab.sources);
}
