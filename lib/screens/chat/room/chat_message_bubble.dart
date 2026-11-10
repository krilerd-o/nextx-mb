import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_config.dart';
import '../../../core/chat_format.dart';
import '../../../core/chat_merge.dart';
import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../widgets/nx_avatar.dart';
import '../../../widgets/nx_html_view.dart';
import '../../../widgets/nx_icons.dart';
import 'chat_attachments.dart';

String chatSenderName(Map<String, dynamic> m) {
  final who = [m['first_name'], m['last_name']].where((e) => e != null && e.toString().isNotEmpty).join(' ');
  if (who.isNotEmpty) return who;
  final ext = m['external_display_name']?.toString() ?? m['sender_name']?.toString() ?? m['email1']?.toString() ?? '';
  return ext.isNotEmpty ? ext : 'User #${m['user_id'] ?? ''}';
}

String chatClock(dynamic raw) {
  final d = parseThai(raw?.toString() ?? '');
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

List<Map<String, dynamic>> chatAttachmentsOf(Map<String, dynamic> m) =>
    (m['attachments'] is List ? m['attachments'] as List : const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

/// Call log message (kind = call) — centred pill with "โทรกลับ".
class ChatCallLogPill extends StatelessWidget {
  const ChatCallLogPill({super.key, required this.message, required this.me, this.onCallBack});
  final Map<String, dynamic> message;
  final String? me;
  final void Function(bool video)? onCallBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final call = message['call'] is Map ? Map<String, dynamic>.from(message['call'] as Map) : <String, dynamic>{};
    final l = chatCallLabel(call, me);
    final video = call['media'] == 'video';
    final tone = l.missed ? cs.error : const Color(0xFF16A34A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          key: ValueKey('chat-call-log-${message['id']}'),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: l.missed ? cs.errorContainer.withValues(alpha: 0.5) : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: tone,
              child: Icon(l.missed ? NxI.phoneMissed : (video ? NxI.videoCamera : NxI.phone), size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tr(l.title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${tr(l.detail)} · ${chatClock(message['created_at'])}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
            if (onCallBack != null) ...[
              const SizedBox(width: 10),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => onCallBack!(video),
                child: Text(tr('โทรกลับ')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Quote of the message being replied to (inside a bubble or above the composer).
class ChatReplyQuote extends StatelessWidget {
  const ChatReplyQuote({super.key, required this.reply, required this.onBubble, this.onTap});
  final Map<String, dynamic> reply;
  final bool onBubble;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final api = context.read<AppConfig>().apiClient;
    final name = reply['sender_name']?.toString() ?? chatSenderName(reply);
    final kind = reply['attachment_kind']?.toString() ??
        (chatAttachmentsOf(reply).isNotEmpty ? chatAttachmentKind(chatAttachmentsOf(reply).first['mime_type']?.toString()) : null);
    var text = reply['missing'] == true
        ? 'ข้อความต้นฉบับไม่พร้อมแสดง'
        : reply['deleted'] == true
            ? 'ข้อความถูกลบแล้ว'
            : chatPlainText(reply['body']?.toString()).replaceAll('\n', ' ');
    if (text.isEmpty && kind != null) text = chatKindLabel(kind);
    final thumbPath = reply['attachment_path']?.toString() ??
        (kind == 'image' && chatAttachmentsOf(reply).isNotEmpty ? chatAttachmentsOf(reply).first['file_path']?.toString() : null);
    final fg = onBubble ? cs.onPrimary : cs.onSurface;
    final accent = onBubble ? cs.onPrimary : cs.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: const ValueKey('chat-reply-quote'),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          border: Border(left: BorderSide(color: accent, width: 3)),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (reply['missing'] != true) Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent)),
              Text(tr(text), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.85))),
            ]),
          ),
          if (thumbPath != null && thumbPath.isNotEmpty) ...[
            const SizedBox(width: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 36, height: 36, child: ChatNetworkImage(urls: api.chatFileUrls(thumbPath)))),
          ],
        ]),
      ),
    );
  }
}

/// One chat message. Long press = actions, swipe right = reply.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.me,
    required this.showName,
    required this.showAvatar,
    required this.onLongPress,
    this.onReply,
    this.onJumpTo,
    this.onReact,
    this.onOpenThread,
    this.replyFallback,
    this.highlighted = false,
    this.inThread = false,
  });

  final Map<String, dynamic> message;
  final String? me;
  final bool showName;
  final bool showAvatar;
  final VoidCallback onLongPress;
  final VoidCallback? onReply;
  final void Function(String id)? onJumpTo;
  final void Function(String emoji)? onReact;
  final VoidCallback? onOpenThread;
  final Map<String, dynamic>? replyFallback;
  final bool highlighted;
  final bool inThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final m = message;
    final mine = isOwnChatMessage(m, me);
    final deleted = m['deleted_at'] != null;
    final body = deleted ? '' : (m['body']?.toString() ?? m['content']?.toString() ?? '');
    final atts = deleted ? const <Map<String, dynamic>>[] : chatAttachmentsOf(m);
    final reactions = chatReactions(m);
    final edited = !deleted && (m['edited_at'] != null || m['is_edited'] == true);
    final fwd = m['forwarded_from'] is Map ? Map<String, dynamic>.from(m['forwarded_from'] as Map) : null;
    final reply = m['reply_to'] is Map ? Map<String, dynamic>.from(m['reply_to'] as Map) : replyFallback;
    final link = body.isEmpty ? null : chatLinks(body).firstOrNull;
    final onlyMedia = body.trim().isEmpty && atts.isNotEmpty && atts.every((a) => chatAttachmentKind(a['mime_type']?.toString()) == 'image') && reply == null && fwd == null;
    final bg = onlyMedia ? Colors.transparent : (mine ? cs.primary : cs.surfaceContainerHighest);
    final fg = mine && !onlyMedia ? cs.onPrimary : cs.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine || !showAvatar ? 18 : 6),
      bottomRight: Radius.circular(mine && showAvatar ? 6 : 18),
    );
    final threadCount = int.tryParse('${m['thread_reply_count'] ?? ''}') ?? 0;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
      padding: onlyMedia ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fwd != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(NxI.forward, size: 13, color: fg.withValues(alpha: 0.75)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(tr('ส่งต่อจาก ${fwd['user_name'] ?? 'ผู้ใช้'}'), key: const ValueKey('chat-forwarded'), style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.75))),
                ),
              ]),
            ),
          if (m['reply_to_id'] != null && reply != null)
            ChatReplyQuote(reply: reply, onBubble: mine, onTap: onJumpTo == null ? null : () => onJumpTo!('${reply['id'] ?? m['reply_to_id']}')),
          if (deleted)
            Text(tr('ข้อความนี้ถูกลบแล้ว'), style: theme.textTheme.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.7), fontStyle: FontStyle.italic))
          else if (body.trim().isNotEmpty)
            NxHtmlView(html: _mentionsToHtml(chatMarkdownToHtml(body)), selectable: false, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          if (atts.isNotEmpty) ChatAttachments(attachments: atts, mine: mine && !onlyMedia),
          if (link != null) ChatLinkPreview(url: link, mine: mine),
          if (!onlyMedia)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr('${edited ? 'แก้ไขแล้ว · ' : ''}${chatClock(m['created_at'])}'),
                style: theme.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.65), fontSize: 10.5),
              ),
            ),
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showName && !mine)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Text(chatSenderName(m), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
        GestureDetector(onLongPress: () {
          HapticFeedback.mediumImpact();
          onLongPress();
        }, child: bubble),
        if (reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (final r in reactions)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onReact == null ? null : () => onReact!(r['emoji'].toString()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: r['me'] == true ? cs.primaryContainer : cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: r['me'] == true ? cs.primary : cs.outlineVariant),
                    ),
                    child: Text('${r['emoji']} ${r['count'] ?? 1}', style: theme.textTheme.labelSmall),
                  ),
                ),
            ]),
          ),
        if (threadCount > 0 && !inThread)
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: onOpenThread,
            icon: const Icon(NxI.thread, size: 15),
            label: Text(tr('$threadCount การตอบกลับ')),
          ),
      ],
    );

    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlighted ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
      padding: EdgeInsets.only(top: showName ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 38,
              child: showAvatar ? NxAvatar(label: chatSenderName(m), size: 30) : null,
            ),
          Flexible(child: content),
        ],
      ),
    );
    if (onReply == null || deleted) return row;
    return _SwipeToReply(onReply: onReply!, child: row);
  }

  /// `@[12:Name]` → bold @Name.
  static String _mentionsToHtml(String body) =>
      body.replaceAllMapped(RegExp(r'@\[(\d+):((?:[^\[\]]|\[[^\[\]]*\])+)\]'), (m) => '<b>@${m[2]}</b>');
}

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply});
  final Widget child;
  final VoidCallback onReply;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _fired = false;
  static const _trigger = 64.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(0.0, 90.0);
        if (next >= _trigger && !_fired) {
          _fired = true;
          HapticFeedback.selectionClick();
        }
        setState(() => _dx = next);
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply();
        setState(() {
          _dx = 0;
          _fired = false;
        });
      },
      child: Stack(alignment: Alignment.centerLeft, children: [
        if (_dx > 8)
          Positioned(
            left: 8,
            child: Opacity(
              opacity: (_dx / _trigger).clamp(0.0, 1.0),
              child: CircleAvatar(radius: 14, backgroundColor: cs.primaryContainer, child: Icon(NxI.reply, size: 16, color: cs.onPrimaryContainer)),
            ),
          ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}
