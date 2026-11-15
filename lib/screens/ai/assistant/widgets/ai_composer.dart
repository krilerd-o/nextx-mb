import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';

import '../../../../core/ai_commands.dart';
import '../../../../core/entity_display.dart';
import '../../../../core/entity_modules.dart';
import '../../../../core/i18n.dart';
import '../../../../services/api_client.dart';
import '../../../../widgets/nx_attachments.dart';
import '../../../../widgets/nx_icons.dart';
import 'ai_style.dart';

/// The bottom bar: one rounded field with attachments / record chip on top,
/// the text in the middle and `＋  ⚡Auto▾  …  🎤  ➤` underneath.
class AiComposer extends StatelessWidget {
  const AiComposer({
    super.key,
    required this.input,
    required this.focus,
    required this.locked,
    required this.sending,
    required this.uploading,
    required this.uploadProgress,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.modeLabel,
    required this.modeIcon,
    required this.onMode,
    required this.onAttach,
    required this.listening,
    required this.onMic,
    required this.onSend,
    required this.onStop,
    this.contextTitle,
    this.onClearContext,
    this.panel,
    this.compact = false,
    this.actionLabel,
    this.onClearAction,
  });

  /// A create command waiting for details ("สร้าง Lead" chip): send opens its form.
  final String? actionLabel;
  final VoidCallback? onClearAction;

  final TextEditingController input;
  final FocusNode focus;
  final bool locked;
  final bool sending;
  final bool uploading;
  final double? uploadProgress;
  final List<Map<String, dynamic>> attachments;
  final ValueChanged<Map<String, dynamic>> onRemoveAttachment;
  final String modeLabel;
  final IconData modeIcon;
  final VoidCallback onMode;
  final VoidCallback onAttach;
  final bool listening;
  final VoidCallback onMic;
  final VoidCallback onSend;
  final VoidCallback onStop;

  /// Record chip (`@` mention or "ถาม Isaac").
  final String? contextTitle;
  final VoidCallback? onClearContext;

  /// Slash menu / mention picker shown above the field.
  final Widget? panel;

  /// Short window: fewer lines.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canSend = !locked && !uploading && (actionLabel != null || input.text.trim().isNotEmpty || attachments.isNotEmpty);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: AiStyle.of(context),
              switchInCurve: AiStyle.curve,
              transitionBuilder: (child, a) => SizeTransition(
                sizeFactor: a,
                alignment: Alignment.bottomCenter,
                child: FadeTransition(opacity: a, child: child),
              ),
              child: panel == null ? const SizedBox.shrink(key: ValueKey('no-panel')) : Padding(padding: const EdgeInsets.only(bottom: 8), child: panel),
            ),
            AnimatedContainer(
              duration: AiStyle.of(context),
              curve: AiStyle.curve,
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              decoration: BoxDecoration(
                color: AiStyle.surface(context),
                borderRadius: BorderRadius.circular(AiStyle.composerRadius),
                border: Border.all(color: focus.hasFocus ? cs.primary.withValues(alpha: 0.45) : cs.outlineVariant.withValues(alpha: 0.45)),
                boxShadow: AiStyle.softShadow(context),
              ),
              child: AnimatedSize(
                duration: AiStyle.of(context),
                curve: AiStyle.curve,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actionLabel != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            key: const ValueKey('ai-create-chip'),
                            avatar: Icon(NxI.plus, size: 14, color: cs.onPrimary),
                            label: Text(
                              actionLabel!,
                              style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600),
                            ),
                            shape: const StadiumBorder(),
                            side: BorderSide.none,
                            backgroundColor: cs.primary,
                            deleteIcon: Icon(NxI.x, size: 14, color: cs.onPrimary),
                            visualDensity: VisualDensity.compact,
                            onDeleted: onClearAction,
                            deleteButtonTooltipMessage: tr('ยกเลิก'),
                          ),
                        ),
                      ),
                    if (contextTitle != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            key: const ValueKey('ai-context'),
                            avatar: Icon(NxI.at, size: 14, color: cs.primary),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(contextTitle!, overflow: TextOverflow.ellipsis),
                            ),
                            shape: const StadiumBorder(),
                            side: BorderSide.none,
                            backgroundColor: AiStyle.tint(context),
                            visualDensity: VisualDensity.compact,
                            onDeleted: onClearContext,
                            deleteButtonTooltipMessage: tr('ไม่ใช้บริบทนี้'),
                          ),
                        ),
                      ),
                    if (attachments.isNotEmpty || uploading)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: NxAttachmentStrip(items: attachments, thumb: 56, onRemove: onRemoveAttachment),
                            ),
                            if (uploading)
                              SizedBox(
                                key: const ValueKey('ai-upload-progress'),
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, value: uploadProgress),
                              ),
                          ],
                        ),
                      ),
                    TextField(
                      key: const ValueKey('ai-input'),
                      controller: input,
                      focusNode: focus,
                      enabled: !locked,
                      minLines: 1,
                      maxLines: compact ? 2 : 6,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.45),
                      decoration: InputDecoration(
                        hintText: tr(
                          locked
                              ? 'โควตาหมด — ส่งข้อความไม่ได้'
                              : actionLabel != null
                              ? 'พิมพ์รายละเอียดให้ไอแซคกรอก หรือกดส่งเพื่อเปิดฟอร์ม'
                              : 'ถามไอแซค… พิมพ์ / หรือ @',
                        ),
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.75), fontSize: 16),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    Row(
                      children: [
                        _RoundIcon(key: const ValueKey('ai-attach'), tooltip: 'แนบไฟล์ / คำสั่ง', icon: NxI.plus, onTap: locked ? null : onAttach),
                        const SizedBox(width: 4),
                        Flexible(
                          child: _ModeChip(label: modeLabel, icon: modeIcon, onTap: onMode),
                        ),
                        const Spacer(),
                        if (!locked)
                          _RoundIcon(
                            key: const ValueKey('ai-mic'),
                            tooltip: listening ? 'หยุดฟัง' : 'พูดแทนพิมพ์',
                            icon: listening ? NxI.stop : NxI.microphone,
                            color: listening ? cs.error : null,
                            onTap: onMic,
                          ),
                        const SizedBox(width: 4),
                        AnimatedSwitcher(
                          duration: AiStyle.of(context, const Duration(milliseconds: 180)),
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: sending
                              ? _SendButton(key: const ValueKey('ai-stop'), tooltip: 'หยุด', icon: NxI.stop, onTap: onStop, active: true)
                              : _SendButton(
                                  key: const ValueKey('ai-send'),
                                  tooltip: 'ส่ง',
                                  icon: NxI.paperPlaneTilt,
                                  onTap: canSend ? onSend : null,
                                  active: canSend,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({super.key, required this.tooltip, required this.icon, this.onTap, this.color});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tr(tooltip),
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    icon: Icon(icon, size: 22, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      label: tr('โหมดการตอบ: $label'),
      child: Material(
        color: AiStyle.tint(context),
        shape: const StadiumBorder(),
        child: InkWell(
          key: const ValueKey('ai-model'),
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => AiStyle.accent.createShader(r), child: Icon(icon, size: 16)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      tr(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(NxI.caretDown, size: 14, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.tooltip, required this.icon, required this.onTap, required this.active});
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr(tooltip),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tr(tooltip),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AiStyle.of(context),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active ? AiStyle.accent : null,
              color: active ? null : cs.onSurface.withValues(alpha: 0.08),
            ),
            child: Icon(icon, size: 19, color: active ? Colors.white : cs.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}

/// Panel above the composer listing slash commands, grouped by source.
class AiSlashMenu extends StatelessWidget {
  const AiSlashMenu({super.key, required this.commands, required this.onPick, this.onManage});
  final List<AiCommand> commands;
  final ValueChanged<AiCommand> onPick;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rows = <Widget>[];
    AiCommandSource? last;
    for (final c in commands.take(30)) {
      if (c.source != last) {
        last = c.source;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              tr(aiCommandSourceLabel(c.source)),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
            ),
          ),
        );
      }
      rows.add(
        ListTile(
          key: ValueKey('ai-cmd-${c.source.name}-${c.command}'),
          dense: true,
          minTileHeight: 48,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AiStyle.tint(context), borderRadius: BorderRadius.circular(10)),
            child: Icon(AiStyle.commandIcon(c.icon), size: 16, color: cs.primary),
          ),
          title: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '/${c.command}  ',
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                ),
                TextSpan(text: tr(c.title)),
              ],
            ),
          ),
          subtitle: c.description.isEmpty ? null : Text(tr(c.description), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onPick(c),
        ),
      );
    }
    return _Panel(
      key: const ValueKey('ai-slash-menu'),
      header: Row(
        children: [
          Icon(AiIcons.slash, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('คำสั่งลัด'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (onManage != null) TextButton(onPressed: onManage, child: Text(tr('จัดการ'))),
        ],
      ),
      child: commands.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('ไม่พบคำสั่ง — กด "จัดการ" เพื่อสร้างคำสั่งของคุณ'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            )
          : ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 6), children: rows),
    );
  }
}

/// A CRM record picked with `@`.
typedef AiMention = ({String module, String id, String title});

/// Panel above the composer searching CRM records for `@query`.
class AiMentionPicker extends StatefulWidget {
  const AiMentionPicker({super.key, required this.api, required this.query, required this.modules, required this.onPick});
  final ApiClient api;
  final String query;
  final List<String> modules;
  final ValueChanged<AiMention> onPick;

  @override
  State<AiMentionPicker> createState() => _AiMentionPickerState();
}

class _AiMentionPickerState extends State<AiMentionPicker> {
  Timer? _debounce;
  CancelToken? _cancel;
  bool _loading = false;
  List<({String module, String id, String title, String subtitle})> _hits = const [];

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(AiMentionPicker old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    if (widget.query.trim().length < 2) {
      setState(() {
        _hits = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    final q = widget.query.trim();
    final found = <({String module, String id, String title, String subtitle})>[];
    await Future.wait([
      for (final m in widget.modules)
        widget.api
            .getEntityList(m, limit: 4, q: q, cancel: cancel, extra: const {'omit_long_text': '1'})
            .then((page) {
              for (final row in page.items) {
                found.add((module: m, id: strId(row['id']), title: entityTitle(row, module: m), subtitle: EntityModules.titleOf(m)));
              }
            })
            .timeout(const Duration(seconds: 8))
            .catchError((_) {}),
    ]);
    if (!mounted || cancel.isCancelled) return;
    setState(() {
      _hits = found.where((h) => h.id.isNotEmpty).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final short = widget.query.trim().length < 2;
    return _Panel(
      key: const ValueKey('ai-mention-picker'),
      header: Row(
        children: [
          Icon(NxI.at, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('อ้างอิงเรคคอร์ด'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
      child: short
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('พิมพ์ชื่อลูกค้า เคส หรือ Lead อย่างน้อย 2 ตัวอักษร'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            )
          : _hits.isEmpty && !_loading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('ไม่พบเรคคอร์ด'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            )
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 6),
              children: [
                for (final h in _hits)
                  ListTile(
                    key: ValueKey('ai-mention-${h.module}-${h.id}'),
                    dense: true,
                    minTileHeight: 48,
                    leading: Icon(NxI.link, size: 18, color: cs.primary),
                    title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(tr(h.subtitle)),
                    onTap: () => widget.onPick((module: h.module, id: h.id, title: h.title)),
                  ),
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.header, required this.child});
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxH = (MediaQuery.sizeOf(context).height * 0.36).clamp(160.0, 340.0);
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: AiStyle.surface(context),
        borderRadius: BorderRadius.circular(AiStyle.cardRadius),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: AiStyle.softShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      // Own Material so list rows show their ripple on the panel's fill.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: SizedBox(height: 36, child: header),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
