import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../core/i18n.dart';
import '../../core/notebook/notebook_models.dart';
import '../../services/api_exceptions.dart';
import '../../services/notebook/notebook_controller.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_sliding_segmented.dart';
import 'notebook_widgets.dart';

/// "ตั้งค่าแชท": how ISAAC answers in this notebook — goal (default / learning
/// guide / custom prompt), persona and answer length. Returns true when saved.
Future<bool> showNotebookChatSettingsSheet(BuildContext context, NotebookController c) async {
  final saved = await showAppBottomSheet<bool>(context: context, title: null, child: NotebookChatSettingsForm(c: c));
  return saved == true;
}

/// Inline text of a failed save (400 validation → what to fix, in Thai).
String chatSettingsErrorText(Object e) {
  if (e is ApiEnvelopeException && e.statusCode == 400) {
    final field = '${e.details?['field'] ?? ''}';
    if (field.contains('custom_prompt') || e.message.contains('custom_prompt')) return 'กรอกคำสั่งสำหรับโหมด "กำหนดเอง" ก่อนบันทึก';
    if (field.contains('persona')) return 'บทบาทยาวเกินไป (ไม่เกิน 500 ตัวอักษร)';
    if (RegExp(r'[฀-๿]').hasMatch(e.message)) return e.message;
    return 'ตั้งค่าไม่ถูกต้อง — ตรวจสอบอีกครั้ง';
  }
  return notebookError(e).text;
}

class NotebookChatSettingsForm extends StatefulWidget {
  const NotebookChatSettingsForm({super.key, required this.c});
  final NotebookController c;

  @override
  State<NotebookChatSettingsForm> createState() => _NotebookChatSettingsFormState();
}

class _NotebookChatSettingsFormState extends State<NotebookChatSettingsForm> {
  late final ChatSettings _initial = widget.c.chatSettings;
  late String _goal = _initial.goal;
  late String _length = _initial.length;
  late final _prompt = TextEditingController(text: _initial.customPrompt ?? '');
  late final _persona = TextEditingController(text: _initial.persona ?? '');
  bool _busy = false;
  String? _error;

  static const _goals = [
    ('default', 'ค่าเริ่มต้น', 'ตอบตรงประเด็นจากแหล่งข้อมูล พร้อมอ้างอิง', LucideIcons300.messageSquareText),
    ('learning_guide', 'ผู้ช่วยการเรียนรู้', 'อธิบายทีละขั้น ถามกลับเพื่อช่วยให้เข้าใจ', LucideIcons300.graduationCap),
    ('custom', 'กำหนดเอง', 'เขียนคำสั่งเองว่าอยากให้ไอแซคตอบแบบไหน', LucideIcons300.penLine),
  ];

  @override
  void dispose() {
    _prompt.dispose();
    _persona.dispose();
    super.dispose();
  }

  Future<void> _save({bool reset = false}) async {
    if (!reset && _goal == 'custom' && _prompt.text.trim().isEmpty) {
      setState(() => _error = 'กรอกคำสั่งสำหรับโหมด "กำหนดเอง" ก่อนบันทึก');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.c.saveChatSettings(reset ? null : ChatSettings(goal: _goal, customPrompt: _prompt.text, persona: _persona.text, length: _length));
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = chatSettingsErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(BuildContext context, String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: tr(hint),
      isDense: true,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kNotebookAccent, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final label = theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant);
    return Column(key: const ValueKey('notebook-chat-settings-sheet'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const NotebookIconBadge(icon: LucideIcons300.slidersHorizontal, color: kNotebookAccent, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ตั้งค่าแชท'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(tr('กำหนดวิธีที่ไอแซคตอบในสมุดนี้ — ใช้กับทุกคนที่แชทในสมุด'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      Text(tr('เป้าหมายการสนทนา'), style: label),
      const SizedBox(height: 8),
      for (final (id, title, hint, icon) in _goals)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _GoalTile(
            key: ValueKey('chat-goal-$id'),
            icon: icon,
            title: title,
            hint: hint,
            selected: _goal == id,
            onTap: _busy
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _goal = id;
                      _error = null;
                    });
                  },
          ),
        ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: _goal != 'custom'
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: TextField(
                  key: const ValueKey('chat-custom-prompt'),
                  controller: _prompt,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: ChatSettings.customPromptMax,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: _field(context, 'เช่น ตอบเหมือนที่ปรึกษาฝ่ายขาย เน้นตัวเลขและขั้นตอนที่ทำได้จริง'),
                ),
              ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text(tr('บทบาทของไอแซค'), style: label)),
        Text(tr('ไม่บังคับ'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('chat-persona'),
        controller: _persona,
        minLines: 1,
        maxLines: 3,
        maxLength: ChatSettings.personaMax,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        decoration: _field(context, 'เช่น ครูสอนงานบริการลูกค้า'),
      ),
      const SizedBox(height: 10),
      Text(tr('ความยาวคำตอบ'), style: label),
      const SizedBox(height: 8),
      KeyedSubtree(
        key: const ValueKey('chat-length'),
        child: NxSlidingSegmented<String>(
          value: _length,
          options: [for (final l in ChatSettings.lengths) (l, chatLengthLabel(l), null)],
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _length = v);
          },
        ),
      ),
      if (_error != null)
        Container(
          key: const ValueKey('chat-settings-error'),
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: dark ? 0.35 : 0.6), borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(NxI.warningCircle, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(_error!), style: theme.textTheme.bodyMedium?.copyWith(color: dark ? cs.onSurface : cs.onErrorContainer))),
          ]),
        ),
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('chat-settings-save'),
        style: FilledButton.styleFrom(backgroundColor: kNotebookAccent, minimumSize: const Size.fromHeight(50)),
        onPressed: _busy ? null : _save,
        child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(tr('บันทึก')),
      ),
      const SizedBox(height: 4),
      Center(
        child: TextButton.icon(
          key: const ValueKey('chat-settings-reset'),
          style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          onPressed: _busy ? null : () => _save(reset: true),
          icon: const Icon(LucideIcons300.rotateCcw, size: 16),
          label: Text(tr('รีเซ็ตค่าเริ่มต้น')),
        ),
      ),
    ]);
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({super.key, required this.icon, required this.title, required this.hint, required this.selected, this.onTap});
  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? kNotebookAccent.withValues(alpha: dark ? 0.2 : 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? kNotebookAccent : cs.outlineVariant.withValues(alpha: 0.6), width: selected ? 1.5 : 1),
            ),
            child: Row(children: [
              NotebookIconBadge(icon: icon, color: selected ? kNotebookAccent : cs.onSurfaceVariant, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(tr(hint), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
                ]),
              ),
              const SizedBox(width: 8),
              Icon(selected ? NxI.checkCircle : NxI.circle, size: 22, color: selected ? kNotebookAccent : cs.outlineVariant),
            ]),
          ),
        ),
      ),
    );
  }
}
