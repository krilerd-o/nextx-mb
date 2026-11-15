import 'package:flutter/material.dart';

import '../../../../core/ai_assistant.dart';
import '../../../../core/ai_commands.dart';
import '../../../../core/i18n.dart';
import '../../../../widgets/app_bottom_sheet.dart';
import '../../../../widgets/nx_icons.dart';
import 'ai_style.dart';

/// One row in an action sheet.
class _Act extends StatelessWidget {
  const _Act({super.key, required this.icon, required this.label, required this.value, this.danger = false, this.subtitle, this.trailing});
  final IconData icon;
  final String label;
  final String value;
  final bool danger;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      minTileHeight: 52,
      leading: Icon(icon, color: color ?? cs.onSurfaceVariant),
      title: Text(tr(label), style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(tr(subtitle!)),
      trailing: trailing,
      onTap: () => Navigator.pop(context, value),
    );
  }
}

/// Chat menu (title ▾ / long-press / ⋯): pin · rename · folder · share · archive · delete.
Future<String?> showAiChatMenu(BuildContext context, AiConversation chat, {required bool canShare}) {
  return showAppBottomSheet<String>(
    context: context,
    title: null,
    child: Column(
      key: const ValueKey('ai-chat-menu'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            chat.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        _Act(icon: chat.starred ? AiIcons.pinOff : AiIcons.pin, label: chat.starred ? 'เลิกปักหมุด' : 'ปักหมุด', value: 'pin'),
        const _Act(icon: NxI.pencilSimple, label: 'เปลี่ยนชื่อ', value: 'rename'),
        const _Act(icon: NxI.folder, label: 'ย้ายไปโฟลเดอร์', value: 'move'),
        if (canShare) const _Act(icon: NxI.shareNetwork, label: 'แชร์แชท', value: 'share'),
        _Act(icon: NxI.archive, label: chat.archived ? 'นำกลับจากที่เก็บถาวร' : 'เก็บถาวร', value: 'archive'),
        const _Act(icon: NxI.trash, label: 'ลบ', value: 'delete', danger: true),
      ],
    ),
  );
}

/// Pick a folder: `''` = no folder, `__new__` = create one, else the folder id.
Future<String?> showAiFolderPicker(BuildContext context, List<AiFolder> folders, {String? current}) {
  return showAppBottomSheet<String>(
    context: context,
    title: 'ย้ายไปโฟลเดอร์',
    child: Column(
      key: const ValueKey('ai-folder-picker'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _Act(icon: NxI.x, label: 'ไม่อยู่ในโฟลเดอร์', value: '', trailing: current == null ? const Icon(NxI.check) : null),
        for (final f in folders)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            minTileHeight: 52,
            leading: Icon(NxI.folder, color: AiStyle.folderColor(context, f.color)),
            title: Text(f.name),
            trailing: current == f.id ? const Icon(NxI.check) : null,
            onTap: () => Navigator.pop(context, f.id),
          ),
        const _Act(key: ValueKey('ai-folder-new'), icon: AiIcons.folderPlus, label: 'สร้างโฟลเดอร์ใหม่', value: '__new__'),
      ],
    ),
  );
}

/// Folder menu (long-press): open · edit · delete.
Future<String?> showAiFolderMenu(BuildContext context, AiFolder f, {bool showOpen = true}) {
  return showAppBottomSheet<String>(
    context: context,
    title: null,
    child: Column(
      key: const ValueKey('ai-folder-menu'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(NxI.folder, color: AiStyle.folderColor(context, f.color)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(f.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        if (showOpen) const _Act(icon: AiIcons.folderOpen, label: 'เปิดโฟลเดอร์', value: 'open'),
        const _Act(icon: NxI.pencilSimple, label: 'แก้ไขชื่อ สี และคำสั่งประจำโฟลเดอร์', value: 'edit'),
        const _Act(icon: NxI.trash, label: 'ลบโฟลเดอร์', subtitle: 'แชทในโฟลเดอร์จะยังอยู่', value: 'delete', danger: true),
      ],
    ),
  );
}

/// Create / edit a folder: name, colour, standing instructions.
Future<({String name, String color, String instructions})?> showAiFolderEditor(BuildContext context, {AiFolder? folder}) {
  return showAppBottomSheet<({String name, String color, String instructions})>(
    context: context,
    title: folder == null ? 'สร้างโฟลเดอร์' : 'แก้ไขโฟลเดอร์',
    child: _FolderEditor(folder: folder),
  );
}

class _FolderEditor extends StatefulWidget {
  const _FolderEditor({this.folder});
  final AiFolder? folder;

  @override
  State<_FolderEditor> createState() => _FolderEditorState();
}

class _FolderEditorState extends State<_FolderEditor> {
  late final _name = TextEditingController(text: widget.folder?.name ?? '');
  late final _instructions = TextEditingController(text: widget.folder?.instructions ?? '');
  late String _color = widget.folder?.color ?? kAiFolderColors.first;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      key: const ValueKey('ai-folder-editor'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('ai-folder-name'),
          controller: _name,
          autofocus: widget.folder == null,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: tr('ชื่อโฟลเดอร์'), hintText: tr('เช่น ลูกค้า ABC, ทีมขาย, โครงการ Q4')),
        ),
        const SizedBox(height: 16),
        Text(tr('สี'), style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in kAiFolderColors)
              Semantics(
                button: true,
                selected: _color == hex,
                label: hex,
                child: GestureDetector(
                  onTap: () => setState(() => _color = hex),
                  child: AnimatedContainer(
                    duration: AiStyle.of(context),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AiStyle.folderColor(context, hex),
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == hex ? cs.onSurface : Colors.transparent, width: 2.5),
                    ),
                    child: _color == hex ? const Icon(NxI.check, size: 16, color: Colors.white) : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('ai-folder-instructions'),
          controller: _instructions,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: tr('คำสั่งประจำโฟลเดอร์ (ไม่บังคับ)'),
            hintText: tr('เช่น ตอบเป็นข้อ ๆ ใช้ภาษาทางการ อ้างอิงลูกค้า ABC เสมอ'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('ไอแซคจะทำตามคำสั่งนี้ในทุกแชทของโฟลเดอร์'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('ai-folder-save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (name: _name.text.trim(), color: _color, instructions: _instructions.text.trim())),
          child: Text(tr('บันทึก')),
        ),
      ],
    );
  }
}

/// Long-press on a message.
Future<String?> showAiMessageActions(BuildContext context, {required bool isUser, required bool canRegenerate, required bool canEdit}) {
  return showAppBottomSheet<String>(
    context: context,
    title: null,
    child: Column(
      key: const ValueKey('ai-message-actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Act(icon: NxI.copySimple, label: 'คัดลอก', value: 'copy'),
        const _Act(icon: NxI.textT, label: 'เลือกข้อความ', value: 'select'),
        const _Act(icon: NxI.shareNetwork, label: 'แชร์', value: 'share'),
        if (isUser && canEdit) const _Act(key: ValueKey('ai-act-edit'), icon: NxI.pencilSimple, label: 'แก้ไขแล้วส่งใหม่', value: 'edit'),
        if (isUser) const _Act(key: ValueKey('ai-act-save-command'), icon: AiIcons.slash, label: 'บันทึกเป็นคำสั่งของฉัน', value: 'save'),
        if (!isUser && canRegenerate) const _Act(icon: NxI.arrowsClockwise, label: 'สร้างคำตอบใหม่', value: 'regenerate'),
        if (!isUser) const _Act(key: ValueKey('ai-act-speak'), icon: NxI.speakerHigh, label: 'อ่านออกเสียง', value: 'speak'),
      ],
    ),
  );
}

/// ＋ in the composer: camera · photos · files · record · commands.
Future<String?> showAiAttachSheet(BuildContext context, {required bool canAttach}) {
  return showAppBottomSheet<String>(
    context: context,
    title: null,
    child: Column(
      key: const ValueKey('ai-attach-sheet'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canAttach)
          Row(
            children: [
              for (final (icon, label, v) in const [(NxI.camera, 'กล้อง', 'camera'), (NxI.image, 'รูปภาพ', 'gallery'), (NxI.paperclip, 'ไฟล์', 'file')])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _BigTile(key: ValueKey('ai-attach-$v'), icon: icon, label: label, onTap: () => Navigator.pop(context, v)),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        const _Act(
          key: ValueKey('ai-attach-mention'),
          icon: NxI.at,
          label: 'อ้างอิงเรคคอร์ด',
          subtitle: 'ลูกค้า Lead เคส ให้ไอแซคใช้เป็นบริบท',
          value: 'mention',
        ),
        const _Act(key: ValueKey('ai-attach-commands'), icon: AiIcons.slash, label: 'คำสั่งลัด', subtitle: 'เลือกงานที่ใช้บ่อย', value: 'commands'),
      ],
    ),
  );
}

class _BigTile extends StatelessWidget {
  const _BigTile({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: AiStyle.tint(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(height: 6),
              Text(tr(label), style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

/// "สร้าง" quick action: which record to create (only what the user may create).
Future<AiCommand?> showAiCreatePicker(BuildContext context, List<AiCommand> commands) {
  return showAppBottomSheet<AiCommand>(
    context: context,
    title: 'สร้างอะไร',
    child: Column(
      key: const ValueKey('ai-create-picker'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in commands)
          ListTile(
            key: ValueKey('ai-create-${c.command}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            minTileHeight: 52,
            leading: Icon(AiStyle.commandIcon(c.icon), color: Theme.of(context).colorScheme.primary),
            title: Text(tr(c.title)),
            subtitle: Text(tr('ฟอร์มครบทุกช่อง · ไอแซคช่วยกรอก')),
            onTap: () => Navigator.pop(context, c),
          ),
        if (commands.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('คุณยังไม่มีสิทธิ์สร้างรายการ'))),
      ],
    ),
  );
}

/// 👎: what was wrong (optional) → note sent with the feedback; null = cancelled.
Future<String?> showAiThumbDownSheet(BuildContext context) {
  const reasons = ['ข้อมูลไม่ถูกต้อง', 'ตอบไม่ครบ', 'ไม่ตรงคำถาม', 'ช้าเกินไป', 'อื่นๆ'];
  return showAppBottomSheet<String>(
    context: context,
    title: 'คำตอบนี้ยังไม่ดีเพราะ',
    child: Wrap(
      key: const ValueKey('ai-thumb-down-sheet'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final r in reasons)
          ActionChip(key: ValueKey('ai-thumb-reason-$r'), label: Text(tr(r)), onPressed: () => Navigator.pop(context, r)),
      ],
    ),
  );
}

/// Who can open a shared chat.
Future<String?> showAiShareSheet(BuildContext context) {
  return showAppBottomSheet<String>(
    context: context,
    title: 'แชร์แชทนี้',
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Act(icon: NxI.users, label: 'คนในธุรกิจนี้', subtitle: 'ต้องเข้าสู่ระบบจึงเปิดดูได้', value: 'business'),
        _Act(icon: NxI.globe, label: 'ทุกคนที่มีลิงก์', subtitle: 'เปิดดูได้โดยไม่ต้องเข้าสู่ระบบ', value: 'public'),
      ],
    ),
  );
}

/// One-line (or multi-line) text dialog: rename, edit message.
Future<String?> showAiTextDialog(BuildContext context, {required String title, required String initial, String action = 'บันทึก', bool multiline = false}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(title: title, initial: initial, action: action, multiline: multiline),
  );
}

/// Owns its controller so it lives through the closing animation.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.action, required this.multiline});
  final String title;
  final String initial;
  final String action;
  final bool multiline;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(widget.title)),
      content: TextField(
        key: const ValueKey('ai-dialog-field'),
        controller: _ctl,
        autofocus: true,
        minLines: widget.multiline ? 2 : 1,
        maxLines: widget.multiline ? 8 : 1,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('ยกเลิก'))),
        FilledButton(key: const ValueKey('ai-dialog-ok'), onPressed: () => Navigator.pop(context, _ctl.text), child: Text(tr(widget.action))),
      ],
    );
  }
}

/// Create / edit one of the user's commands.
Future<({String command, String title, String prompt})?> showAiCommandEditor(BuildContext context, {AiCommand? command, String? prompt}) {
  return showAppBottomSheet<({String command, String title, String prompt})>(
    context: context,
    title: command == null ? 'คำสั่งใหม่' : 'แก้ไขคำสั่ง',
    child: _CommandEditor(command: command, prompt: prompt),
  );
}

class _CommandEditor extends StatefulWidget {
  const _CommandEditor({this.command, this.prompt});
  final AiCommand? command;
  final String? prompt;

  @override
  State<_CommandEditor> createState() => _CommandEditorState();
}

class _CommandEditorState extends State<_CommandEditor> {
  late final _title = TextEditingController(text: widget.command?.title ?? '');
  late final _cmd = TextEditingController(text: widget.command?.command ?? '');
  late final _prompt = TextEditingController(text: widget.command?.template ?? widget.prompt ?? '');

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _cmd, _prompt]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _cmd.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slug = aiCommandSlug(_cmd.text.isEmpty ? _title.text : _cmd.text);
    final ok = _title.text.trim().isNotEmpty && _prompt.text.trim().isNotEmpty;
    return Column(
      key: const ValueKey('ai-command-editor'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('ai-command-title'),
          controller: _title,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: tr('ชื่อคำสั่ง'), hintText: tr('เช่น รายงานรายสัปดาห์')),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('ai-command-slug'),
          controller: _cmd,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: tr('พิมพ์เรียกด้วย'), prefixText: '/', hintText: slug.isEmpty ? 'weekly' : slug),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('ai-command-prompt'),
          controller: _prompt,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: tr('ข้อความคำสั่ง'),
            hintText: tr('ใส่ [ ] ตรงส่วนที่จะกรอกเอง เช่น สรุปงานของ [ทีม] สัปดาห์นี้'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('ส่วนใน [ ] จะถูกเลือกไว้ให้พิมพ์ทับได้ทันที'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('ai-command-save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
          onPressed: ok ? () => Navigator.pop(context, (command: slug, title: _title.text.trim(), prompt: _prompt.text.trim())) : null,
          child: Text(tr('บันทึก')),
        ),
      ],
    );
  }
}
