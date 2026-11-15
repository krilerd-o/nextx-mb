import 'package:flutter/material.dart';

import '../../../core/ai_commands.dart';
import '../../../core/i18n.dart';
import '../../../widgets/nx_icons.dart';
import 'ai_assistant_controller.dart';
import 'widgets/ai_sheets.dart';
import 'widgets/ai_style.dart';

/// คลังคำสั่ง: every slash command (built-in, business, mine) with search.
/// Tap one to use it; make, edit and delete your own.
class AiPromptLibraryScreen extends StatefulWidget {
  const AiPromptLibraryScreen({super.key, required this.controller});
  final AiAssistantController controller;

  @override
  State<AiPromptLibraryScreen> createState() => _AiPromptLibraryScreenState();
}

class _AiPromptLibraryScreenState extends State<AiPromptLibraryScreen> {
  final _q = TextEditingController();

  AiAssistantController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _edit([AiCommand? cmd]) async {
    final r = await showAiCommandEditor(context, command: cmd);
    if (r == null || !mounted) return;
    try {
      await c.saveMyCommand(id: cmd?.id, command: r.command, title: r.title, prompt: r.prompt);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(aiErrorText(e)))));
    }
  }

  Future<void> _delete(AiCommand cmd) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบคำสั่ง /${cmd.command}?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
        ],
      ),
    );
    if (ok != true || cmd.id == null) return;
    try {
      await c.deleteMyCommand(cmd.id!);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(aiErrorText(e)))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final list = aiFilterCommands(c.allCommands, _q.text);
        final sections = [for (final s in AiCommandSource.values) (source: s, items: list.where((x) => x.source == s).toList())];
        return Scaffold(
          key: const ValueKey('ai-prompt-library'),
          backgroundColor: AiStyle.canvas(context),
          appBar: AppBar(
            backgroundColor: AiStyle.canvas(context),
            surfaceTintColor: Colors.transparent,
            title: Text(tr('คลังคำสั่ง'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const ValueKey('ai-command-new'),
            onPressed: () => _edit(),
            icon: const Icon(NxI.plus),
            label: Text(tr('คำสั่งใหม่')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(AiStyle.gutter, 4, AiStyle.gutter, 96),
            children: [
              TextField(
                key: const ValueKey('ai-command-search'),
                controller: _q,
                decoration: InputDecoration(
                  prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
                  hintText: tr('ค้นหาคำสั่ง'),
                  isDense: true,
                  filled: true,
                  fillColor: AiStyle.surface(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                ),
              ),
              for (final s in sections)
                if (s.items.isNotEmpty || s.source == AiCommandSource.mine) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                    child: Text(
                      tr(aiCommandSourceLabel(s.source)),
                      style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (s.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        tr('ยังไม่มี — กด "คำสั่งใหม่" หรือกดค้างที่ข้อความของคุณในแชทแล้วเลือก "บันทึกเป็นคำสั่งของฉัน"'),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    Material(
                      color: AiStyle.surface(context),
                      borderRadius: BorderRadius.circular(AiStyle.cardRadius),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, cmd) in s.items.indexed) ...[
                            if (i > 0) Divider(height: 1, indent: 60, color: cs.outlineVariant.withValues(alpha: 0.4)),
                            ListTile(
                              key: ValueKey('ai-lib-${cmd.source.name}-${cmd.command}'),
                              minTileHeight: 56,
                              leading: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(color: AiStyle.tint(context), borderRadius: BorderRadius.circular(10)),
                                child: Icon(AiStyle.commandIcon(cmd.icon), size: 17, color: cs.primary),
                              ),
                              title: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '/${cmd.command}  ',
                                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                                    ),
                                    TextSpan(text: tr(cmd.title)),
                                  ],
                                ),
                              ),
                              subtitle: cmd.description.isEmpty ? null : Text(tr(cmd.description), maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: cmd.source == AiCommandSource.mine
                                  ? PopupMenuButton<String>(
                                      tooltip: tr('ตัวเลือก'),
                                      icon: const Icon(NxI.dotsThreeVertical, size: 18),
                                      onSelected: (v) => v == 'edit' ? _edit(cmd) : _delete(cmd),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(value: 'edit', child: Text(tr('แก้ไข'))),
                                        PopupMenuItem(value: 'delete', child: Text(tr('ลบ'))),
                                      ],
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, cmd),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
            ],
          ),
        );
      },
    );
  }
}
