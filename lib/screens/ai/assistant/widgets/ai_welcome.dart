import 'package:flutter/material.dart';

import '../../../../core/ai_assistant.dart';
import '../../../../core/i18n.dart';
import '../../../../widgets/isaac_sticker.dart';
import '../../../../widgets/nx_icons.dart';
import 'ai_style.dart';

/// A one-tap starter on the empty chat. Every one of them only fills the
/// input (with the part to type selected) — nothing is sent by surprise.
class AiQuickAction {
  const AiQuickAction(this.key, this.icon, this.label, this.template);
  final String key;
  final IconData icon;
  final String label;

  /// Null: the parent shows a small picker (e.g. what to create).
  final String? template;
}

const kAiQuickActions = [
  AiQuickAction('search', NxI.magnifyingGlass, 'ค้นหา', 'ค้นหา [ชื่อลูกค้า / เลขที่ / คำค้น] ในระบบ'),
  AiQuickAction('create', NxI.plus, 'สร้าง', null),
  AiQuickAction('docs', NxI.fileText, 'เอกสาร / Export', 'ทำเอกสาร [Word / PDF / Excel] เรื่อง [หัวข้อ] จากข้อมูลในระบบ'),
  AiQuickAction('board', NxI.kanban, 'งานบนบอร์ด', 'สร้างงานบนบอร์ด [ชื่อบอร์ด]: [ชื่องาน] กำหนดส่ง [วัน]'),
  AiQuickAction('today', NxI.chartBar, 'สรุปวันนี้', 'สรุปงาน นัด และเคสของฉันวันนี้ [เพิ่มเติม] และควรโฟกัสอะไร'),
];

/// Record actions when the chat is about a record ("ถาม Isaac" / `@`).
const kAiRecordActions = [
  (NxI.textAlignLeft, 'สรุปเรคคอร์ด', 'สรุปรายการนี้ให้หน่อย และควรทำอะไรต่อ'),
  (NxI.envelope, 'ร่างอีเมลติดตาม', 'ร่างอีเมลติดตามสำหรับรายการนี้ เรื่อง [หัวข้อ]'),
  (NxI.calendarPlus, 'สร้างนัดติดตาม', 'สร้างนัดติดตามสำหรับรายการนี้ วัน [วัน เวลา]'),
  (NxI.trendUp, 'ความเสี่ยง / โอกาส', 'วิเคราะห์ความเสี่ยงและโอกาสของรายการนี้'),
];

class AiWelcome extends StatelessWidget {
  const AiWelcome({
    super.key,
    required this.name,
    required this.onAction,
    required this.suggestions,
    required this.onSuggestion,
    required this.recents,
    required this.folderOf,
    required this.onOpenChat,
    this.contextTitle,
    this.folderName,
    this.showSlashHint = false,
  });

  final String name;

  /// Quick action / record action tapped: template to put in the input, or
  /// the action key when it has no template.
  final void Function(AiQuickAction action) onAction;

  /// Server suggestions (`{name_th, prompt_th, ...}`): these send at once.
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<String> onSuggestion;
  final List<AiConversation> recents;
  final AiFolder? Function(String? id) folderOf;
  final ValueChanged<String> onOpenChat;

  /// The record this chat is about.
  final String? contextTitle;

  /// New chat inside this folder.
  final String? folderName;
  final bool showSlashHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final greet = name.isEmpty ? tr('สวัสดี') : tr('สวัสดี คุณ $name');
    return ListView(
      key: const ValueKey('ai-welcome'),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      children: [
        const Center(
          child: _IsaacRing(child: IsaacSticker(state: 'hello', size: 72)),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AiStyle.gutter),
          child: _TypedText(
            text: greet,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 26, letterSpacing: -0.4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(folderName != null ? 'แชทใหม่ในโฟลเดอร์ $folderName' : 'วันนี้ให้ช่วยอะไรดี?'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (showSlashHint)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Container(
                key: const ValueKey('ai-slash-hint'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AiStyle.tint(context), borderRadius: BorderRadius.circular(999)),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: tr('ลองพิมพ์ ')),
                      TextSpan(
                        text: '/',
                        style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
                      ),
                      TextSpan(text: tr(' เพื่อดูคำสั่งลัด หรือ ')),
                      TextSpan(
                        text: '@',
                        style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
                      ),
                      TextSpan(text: tr(' เพื่ออ้างอิงเรคคอร์ด')),
                    ],
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        const SizedBox(height: 22),
        if (contextTitle != null) ...[
          _Section(title: tr('เกี่ยวกับรายการนี้')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AiStyle.gutter),
            child: _RecordCard(title: contextTitle!, onAction: onAction),
          ),
          const SizedBox(height: 18),
        ],
        _Section(title: tr('เริ่มเร็ว')),
        SizedBox(
          height: 46,
          child: ListView.separated(
            key: const ValueKey('ai-quick-actions'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AiStyle.gutter),
            itemCount: kAiQuickActions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final a = kAiQuickActions[i];
              return _QuickChip(action: a, onTap: () => onAction(a));
            },
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Section(title: tr('แนะนำสำหรับคุณ')),
          for (final p in suggestions.take(3))
            _SuggestionTile(
              label: '${(L10n.isEn ? p['name_en'] : p['name_th']) ?? p['name_th'] ?? ''}',
              onTap: () => onSuggestion('${(L10n.isEn ? p['prompt_en'] : p['prompt_th']) ?? p['prompt_th'] ?? ''}'),
            ),
        ],
        if (recents.isNotEmpty && folderName == null) ...[
          const SizedBox(height: 18),
          _Section(title: tr('ทำต่อ')),
          for (final c in recents) _RecentTile(chat: c, folder: folderOf(c.projectId), onTap: () => onOpenChat(c.id)),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AiStyle.gutter + 4, 0, AiStyle.gutter, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.2),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.action, required this.onTap});
  final AiQuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Flat white pill with a hairline edge: crisp on the canvas, no clipped shadow.
    return Material(
      color: AiStyle.surface(context),
      shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45))),
      child: InkWell(
        key: ValueKey('ai-quick-${action.key}'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(tr(action.label), style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AiStyle.gutter, 0, AiStyle.gutter, 8),
      child: Material(
        color: AiStyle.surface(context),
        borderRadius: BorderRadius.circular(AiStyle.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AiStyle.cardRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Icon(NxI.sparkle, size: 18, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                ),
                // ↗ = sends right away (unlike the quick actions).
                Semantics(
                  label: tr('ส่งทันที'),
                  child: Icon(NxI.arrowSquareOut, size: 16, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.chat, required this.folder, required this.onTap});
  final AiConversation chat;
  final AiFolder? folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      key: ValueKey('ai-recent-${chat.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AiStyle.gutter + 4),
      minTileHeight: 48,
      leading: Icon(NxI.chatCircle, size: 20, color: cs.onSurfaceVariant),
      title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
      trailing: folder == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(NxI.folder, size: 14, color: AiStyle.folderColor(context, folder!.color)),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    folder!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.title, required this.onAction});
  final String title;
  final void Function(AiQuickAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('ai-record-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AiStyle.surface(context),
        borderRadius: BorderRadius.circular(AiStyle.cardRadius),
        boxShadow: AiStyle.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AiStyle.tint(context), borderRadius: BorderRadius.circular(10)),
                child: Icon(NxI.link, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (icon, label, template) in kAiRecordActions)
                ActionChip(
                  avatar: Icon(icon, size: 16, color: cs.primary),
                  label: Text(tr(label)),
                  shape: const StadiumBorder(),
                  side: BorderSide.none,
                  backgroundColor: AiStyle.tint(context),
                  onPressed: () => onAction(AiQuickAction('record', icon, label, template)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Soft gradient ring around Isaac.
class _IsaacRing extends StatelessWidget {
  const _IsaacRing({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AiStyle.accent),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: AiStyle.canvas(context)),
        child: child,
      ),
    );
  }
}

/// Greeting typed out letter by letter (web `AiWelcome`).
class _TypedText extends StatelessWidget {
  const _TypedText({required this.text, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    final d = AiStyle.of(context, Duration(milliseconds: (chars.length * 35).clamp(200, 1400)));
    if (d == Duration.zero) return Text(text, textAlign: TextAlign.center, style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: chars.length.toDouble()),
      duration: d,
      builder: (context, v, _) => Text(chars.take(v.round()).join(), textAlign: TextAlign.center, style: style),
    );
  }
}
