import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../core/nx_page_route.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../comm_ai/comm_ai_isaac.dart';
import '../../core/notebook/notebook_studio_meta.dart';
import 'notebook_audio_overview.dart';
import 'notebook_note_viewer.dart';
import 'notebook_widgets.dart';

/// "สตูดิโอ" tab: make study material from the enabled sources, and the
/// notebook's notes (saved answers, studio outputs, own notes).
class NotebookStudioPane extends StatelessWidget {
  const NotebookStudioPane({super.key, required this.c, this.onAsk, this.onDraft});
  final NotebookController c;

  /// Ask in the chat (mind map node "ถามต่อ").
  final ValueChanged<String>? onAsk;

  /// Put a question in the chat composer ("ถามในแชท" on the interactive mind map).
  final ValueChanged<String>? onDraft;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Future<void> _run(BuildContext context, StudioKind kind) async {
    final messenger = ScaffoldMessenger.of(context);
    if (c.enabledSources.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(tr('เลือกแหล่งข้อมูลอย่างน้อย 1 แหล่งก่อน'))));
      return;
    }
    String? template;
    Map<String, dynamic>? options;
    if (kind.id == 'infographic') {
      template = await _pickTemplate(context);
      if (template == null) return;
    }
    if (kind.id == 'audio' && context.mounted) {
      // Audio Overview v2: format + length first (no options = the classic single voice).
      final pick = await showAudioOptionsSheet(context);
      if (pick == null) return;
      options = audioStudioOptions(format: pick.format, length: pick.length);
    }
    HapticFeedback.selectionClick();
    try {
      final note = await c.runStudio(kind, templateId: template, locale: L10n.isEn ? 'en' : 'th', options: options);
      HapticFeedback.mediumImpact();
      if (note != null && context.mounted) await openNotebookNote(context, c, note, onAsk: onAsk, onDraft: onDraft);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr(notebookError(e).text))));
    }
  }

  Future<String?> _pickTemplate(BuildContext context) => showAppBottomSheet<String>(
        context: context,
        title: 'รูปแบบอินโฟกราฟิก',
        child: Builder(
          builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (id, label, hint) in kInfographicTemplates)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NotebookCard(
                  key: ValueKey('notebook-infographic-$id'),
                  onTap: () => Navigator.pop(ctx, id),
                  child: Row(children: [
                    NotebookIconBadge(
                      icon: switch (id) { 'timeline' => LucideIcons300.listOrdered, 'stats' => LucideIcons300.chartColumn, _ => LucideIcons300.layoutGrid },
                      color: const Color(0xFFEC4899),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(tr(hint), style: Theme.of(ctx).textTheme.bodySmall),
                      ]),
                    ),
                    const Icon(NxI.caretRight, size: 18),
                  ]),
                ),
              ),
          ]),
        ),
      );

  Future<void> _newNote(BuildContext context) async {
    await nxPush<void>(context, NotebookNoteEditor(c: c));
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final run = c.studioRun;
    final notes = c.notes;
    final ts = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8);
    return CustomScrollView(
      key: const ValueKey('notebook-studio'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (run != null) _progress(context, run),
              NotebookSectionLabel(
                'สร้างจากแหล่งที่เลือก',
                trailing: Text(tr('${c.enabledSources.length} แหล่ง'), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 80 * ts),
            delegate: SliverChildListDelegate([for (final k in StudioKind.all) _tile(context, k, busy: run != null)]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          sliver: SliverToBoxAdapter(
            child: NotebookSectionLabel(
              notes.isEmpty ? 'โน้ต' : tr('โน้ต (${notes.length})'),
              trailing: TextButton.icon(
                key: const ValueKey('notebook-new-note'),
                onPressed: () => _newNote(context),
                icon: const Icon(NxI.plus, size: 16),
                label: Text(tr('โน้ตใหม่')),
              ),
            ),
          ),
        ),
        if (notes.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: NotebookCard(
                child: Row(children: [
                  const IsaacAvatar(mood: 'idea', size: 52, ring: false, animate: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr('ผลงานจากสตูดิโอและคำตอบที่บันทึกไว้จะอยู่ตรงนี้ — ลองสร้างแผนผังความคิดหรือแฟลชการ์ดดูสิ'),
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList.separated(
              itemCount: notes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _noteCard(context, notes[i]),
            ),
          ),
      ],
    );
  }

  Widget _progress(BuildContext context, StudioRun run) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('notebook-studio-progress'),
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [run.kind.colors.first.withValues(alpha: 0.14), run.kind.colors.last.withValues(alpha: 0.06)]),
        border: Border.all(color: run.kind.colors.first.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const IsaacAvatar(mood: 'create_image', size: 44, ring: false, animate: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('กำลังสร้าง${run.kind.label}'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(tr(studioPhaseLabel(run.phase)), key: const ValueKey('notebook-studio-phase'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(minHeight: 4, color: run.kind.colors.first)),
          ]),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, StudioKind k, {required bool busy}) {
    final theme = Theme.of(context);
    final running = c.studioRun?.kind.id == k.id;
    return Opacity(
      opacity: busy && !running ? 0.5 : 1,
      child: NotebookCard(
        key: ValueKey('notebook-studio-${k.id}'),
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        radius: 18,
        onTap: busy ? null : () => _run(context, k),
        child: Row(children: [
          running
              ? SizedBox(width: 38, height: 38, child: Padding(padding: const EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2.4, color: k.colors.first)))
              : StudioKindBadge(kind: k, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Long names (สรุปสำหรับผู้บริหาร) wrap rather than lose their ending.
              Text(tr(k.label), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
              Text(tr(k.hint), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.3)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _noteCard(BuildContext context, NotebookNote n) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final k = n.studio ?? StudioKind.note;
    final snippet = n.snippet;
    return NotebookCard(
      key: ValueKey('notebook-note-${n.id}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      onTap: () => openNotebookNote(context, c, n, onAsk: onAsk, onDraft: onDraft),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StudioKindBadge(kind: k, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (snippet.isNotEmpty)
              Text(tr(snippet), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(child: Text(tr(k.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: k.colors.first, fontWeight: FontWeight.w700))),
              if (n.downloadUrl != null) ...[
                const SizedBox(width: 6),
                Icon(NxI.downloadSimple, size: 12, color: cs.onSurfaceVariant),
              ],
              const SizedBox(width: 8),
              const Spacer(),
              Text(tr(notebookRelativeTime(n.updatedAt)), maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
