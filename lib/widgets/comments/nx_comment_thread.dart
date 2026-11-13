import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../screens/notifications/notification_center_screen.dart' show relativeTime;
import '../nx_attachments.dart';
import '../nx_avatar.dart';
import '../nx_html_view.dart';
import '../nx_icons.dart';
import '../nx_overlay_panel.dart';
import 'nx_comment_composer.dart' show NxMentionField;
import 'nx_comment_format.dart';
import 'nx_comments_controller.dart';
import 'nx_link_preview.dart';

/// Threads with more replies than this start collapsed ("ดูการตอบกลับ N รายการ").
const kCommentCollapseAfter = 2;

/// Comment attachments (`attachments` JSON) + images pasted inline in old rich-text bodies.
List<Map<String, dynamic>> nxCommentFiles(Map<String, dynamic> c) {
  final raw = c['attachments'];
  final list = <Map<String, dynamic>>[
    if (raw is List)
      for (final a in raw)
        if (a is Map && '${a['url'] ?? a['path'] ?? ''}'.isNotEmpty) Map<String, dynamic>.from(a)
        else if (a is String && a.isNotEmpty) {'url': a, 'name': a.split('/').last},
  ];
  final seen = {for (final a in list) nxAttachmentUrl(a)};
  for (final img in nxInlineImages('${c['body'] ?? ''}')) {
    if (seen.add(nxAttachmentUrl(img))) list.add(img);
  }
  return list;
}

/// Threaded comments like the web CommentThread: oldest first, replies nested
/// under their comment, long threads collapsed, reply / like / edit / delete.
class NxCommentThreadView extends StatelessWidget {
  const NxCommentThreadView({
    super.key,
    required this.comments,
    required this.controller,
    this.nameOf,
    this.emptyText = 'ยังไม่มีคอมเม้นท์',
    this.emptyHint = 'เริ่มสนทนาได้จากช่องด้านล่าง — พิมพ์ @ เพื่อกล่าวถึง แนบรูป ไฟล์ หรือลิงก์ได้',
  });

  final List<Map<String, dynamic>> comments;
  final NxCommentsController controller;

  /// Display name for a user id when the row has no `user_name`.
  final String Function(Object? userId)? nameOf;
  final String emptyText;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final tree = buildCommentTree(comments, maxDepth: controller.maxDepth);
        if (tree.isEmpty) {
          return Padding(
            key: ValueKey('${controller.keyPrefix}comments-empty'),
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Column(children: [
              Icon(NxI.chatCircle, size: 36, color: cs.primary.withValues(alpha: 0.45)),
              const SizedBox(height: 10),
              Text(tr(emptyText), textAlign: TextAlign.center, style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(tr(emptyHint), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          );
        }
        final hi = controller.highlightId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final root in tree) _thread(context, root, hi),
          ],
        );
      },
    );
  }

  Widget _thread(BuildContext context, CommentNode root, String? hi) {
    final cs = Theme.of(context).colorScheme;
    final n = root.replyCount;
    final all = root.descendants.toList();
    // A highlighted reply opens its thread (and it stays open after the highlight fades).
    if (hi != null && all.any((d) => d.id == hi)) controller.expanded.add(root.id);
    final open = n <= kCommentCollapseAfter || controller.expanded.contains(root.id);
    final p = controller.keyPrefix;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxCommentTile(key: ValueKey('${p}comment-${root.id}'), node: root, rootId: root.id, controller: controller, nameOf: nameOf),
          if (n > 0)
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Container(
                padding: const EdgeInsets.only(left: 14),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7), width: 2))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (open)
                      for (final r in all)
                        Padding(
                          padding: EdgeInsets.only(top: 10, left: ((r.depth - 1).clamp(0, 3)) * 14.0),
                          child: NxCommentTile(key: ValueKey('${p}comment-${r.id}'), node: r, rootId: root.id, controller: controller, nameOf: nameOf, parent: _parentOf(all, root, r)),
                        ),
                    if (n > kCommentCollapseAfter)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: ValueKey('${p}comment-thread-toggle-${root.id}'),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => controller.toggleThread(root.id),
                          icon: Icon(open ? NxI.caretUp : NxI.caretDown, size: 16),
                          label: Text(open ? tr('ซ่อนการตอบกลับ') : tr('ดูการตอบกลับ $n รายการ')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Map<String, dynamic>? _parentOf(List<CommentNode> all, CommentNode root, CommentNode r) {
    final pid = '${r.comment['parent_id'] ?? ''}';
    if (pid == root.id) return root.comment;
    for (final d in all) {
      if (d.id == pid) return d.comment;
    }
    return null;
  }
}

/// One comment: avatar, bubble (name, time, quote, text with mention chips and
/// links), files, link previews and the action row; edits in place.
class NxCommentTile extends StatefulWidget {
  const NxCommentTile({super.key, required this.node, required this.rootId, required this.controller, this.nameOf, this.parent});
  final CommentNode node;
  final String rootId;
  final NxCommentsController controller;
  final String Function(Object? userId)? nameOf;

  /// The comment this one answers (shown as a quote for replies to replies).
  final Map<String, dynamic>? parent;

  @override
  State<NxCommentTile> createState() => _NxCommentTileState();
}

class _NxCommentTileState extends State<NxCommentTile> {
  NxMentionTextController? _edit;
  final _editFocus = FocusNode();
  bool _saving = false;
  bool _revealed = false;

  Map<String, dynamic> get c => widget.node.comment;
  NxCommentsController get ctl => widget.controller;
  String get p => ctl.keyPrefix;

  @override
  void dispose() {
    _edit?.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  String _name(Map<String, dynamic> row) {
    final n = '${row['user_name'] ?? row['authorName'] ?? ''}'.trim();
    if (n.isNotEmpty && n != 'null') return n;
    return widget.nameOf?.call(row['user_id']) ?? 'ผู้ใช้';
  }

  void _startEdit() {
    _edit?.dispose();
    _edit = NxMentionTextController()..setHtml('${c['body'] ?? ''}');
    setState(() {});
    _editFocus.requestFocus();
  }

  Future<void> _saveEdit() async {
    final e = _edit;
    if (e == null) return;
    final html = e.text.trim().isEmpty ? '' : e.toHtml();
    if (html.isEmpty && nxCommentFiles(c).isEmpty) return;
    setState(() => _saving = true);
    final ok = await ctl.saveEdit(c, html);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _edit?.dispose();
        _edit = null;
      }
    });
    if (!ok && ctl.error != null) _snack(ctl.error!);
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(t))));

  Future<void> _delete() async {
    final replies = widget.node.replyCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('ลบคอมเม้นท์นี้?')),
        content: Text(replies > 0 ? tr('การตอบกลับ $replies รายการใต้คอมเม้นท์นี้จะถูกลบไปด้วย') : tr('ลบแล้วกู้คืนไม่ได้')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
          FilledButton(
            key: ValueKey('${p}comment-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('ลบ')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ctl.delete(c);
    if (!done && mounted && ctl.error != null) _snack(ctl.error!);
  }

  /// Optimistic like state (the comment maps may be read-only).
  bool? _liked;
  int? _likes;

  bool get _isLiked => _liked ?? c['liked_by_me'] == true;
  int get _likeCount => _likes ?? int.tryParse('${c['like_count'] ?? 0}') ?? 0;

  @override
  void didUpdateWidget(covariant NxCommentTile old) {
    super.didUpdateWidget(old);
    if (old.node.comment != widget.node.comment) {
      _liked = null;
      _likes = null;
    }
  }

  Future<void> _like() async {
    final like = ctl.api.like;
    if (like == null) return;
    HapticFeedback.selectionClick();
    final liked = _isLiked;
    final count = _likeCount;
    setState(() {
      _liked = !liked;
      _likes = count + (liked ? -1 : 1);
    });
    try {
      final r = await like(c['id'] as Object);
      if (!mounted) return;
      setState(() {
        if (r['liked'] != null) _liked = r['liked'] == true;
        if (r['like_count'] != null) _likes = int.tryParse('${r['like_count']}') ?? _likes;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = liked;
        _likes = count;
      });
    }
  }

  Future<void> _menu() async {
    final text = commentFromHtml('${c['body'] ?? ''}').text;
    final pick = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(NxI.reply), title: Text(tr('ตอบกลับ')), onTap: () => Navigator.pop(ctx, 'reply')),
          if (text.isNotEmpty) ListTile(leading: const Icon(NxI.copySimple), title: Text(tr('คัดลอกข้อความ')), onTap: () => Navigator.pop(ctx, 'copy')),
          if (ctl.canEdit(c)) ListTile(leading: const Icon(NxI.pencilSimple), title: Text(tr('แก้ไข')), onTap: () => Navigator.pop(ctx, 'edit')),
          if (ctl.canDelete(c))
            ListTile(
              leading: Icon(NxI.trash, color: Theme.of(ctx).colorScheme.error),
              title: Text(tr('ลบ'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ],
      ),
    );
    switch (pick) {
      case 'reply':
        ctl.startReply({...c, '_root': widget.rootId});
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        _snack('คัดลอกแล้ว');
      case 'edit':
        _startEdit();
      case 'delete':
        await _delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reply = widget.node.depth > 0;
    final name = _name(c);
    final body = '${c['body'] ?? ''}';
    final files = nxCommentFiles(c);
    final urls = commentUrls(body).take(2).toList();
    final highlighted = ctl.highlightId == widget.node.id;
    if (highlighted && !_revealed) {
      _revealed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 300));
      });
    }
    final quote = widget.parent != null && widget.node.depth > 1 ? widget.parent : null;
    final liked = _isLiked;
    final likes = _likeCount;
    final editing = _edit != null;

    final bubble = AnimatedContainer(
      key: ValueKey('${p}comment-bubble-${widget.node.id}'),
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: highlighted ? cs.primary.withValues(alpha: 0.14) : cs.surfaceContainerHighest.withValues(alpha: theme.brightness == Brightness.dark ? 0.55 : 0.7),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
        ),
        border: highlighted ? Border.all(color: cs.primary.withValues(alpha: 0.5)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(
              child: Text(tr(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Text(tr(relativeTime(c['created_at'])), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          if (quote != null)
            Container(
              key: ValueKey('${p}comment-quote-${widget.node.id}'),
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: cs.primary, width: 3)),
              ),
              child: Text(
                '${tr('ตอบกลับ')} ${_name(quote)}: ${commentFromHtml('${quote['body'] ?? ''}').text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          if (editing) ...[
            const SizedBox(height: 6),
            NxMentionField(
              controller: ctl,
              text: _edit!,
              focus: _editFocus,
              fieldKey: ValueKey('${p}comment-edit-field'),
              suggestionsAbove: false,
              hint: 'แก้ไขคอมเม้นท์',
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _edit?.dispose();
                          _edit = null;
                        }),
                child: Text(tr('ยกเลิก')),
              ),
              const SizedBox(width: 4),
              FilledButton(
                key: ValueKey('${p}comment-edit-save'),
                onPressed: _saving ? null : _saveEdit,
                child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('บันทึก')),
              ),
            ]),
          ] else if (nxCommentHasText(body)) ...[
            const SizedBox(height: 3),
            NxCommentBody(html: body, keyPrefix: p),
          ],
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NxAvatar(label: name, size: reply ? 28 : 34),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(onLongPress: editing ? null : _menu, child: bubble),
              if (files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: NxAttachmentStrip(
                    key: ValueKey('${p}comment-files-${widget.node.id}'),
                    items: files,
                    thumb: reply ? 72 : 88,
                    onOpenFile: (a) => openCommentFile(context, a),
                    onFileActions: (a) => showCommentFileActions(context, a),
                  ),
                ),
              for (final u in urls)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: NxLinkPreviewCard(url: u, fetch: ctl.api.linkPreview, compact: reply),
                ),
              if (!editing)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _action(key: ValueKey('${p}comment-reply-${widget.node.id}'), label: 'ตอบกลับ', onTap: () => ctl.startReply({...c, '_root': widget.rootId})),
                      if (ctl.api.like != null)
                        _action(
                          key: ValueKey('${p}like-${widget.node.id}'),
                          icon: NxI.heart,
                          label: likes > 0 ? '$likes' : 'ถูกใจ',
                          color: liked ? const Color(0xFFE11D48) : null,
                          onTap: _like,
                        ),
                      if (ctl.canEdit(c)) _action(key: ValueKey('${p}comment-edit-${widget.node.id}'), label: 'แก้ไข', onTap: _startEdit),
                      if (ctl.canDelete(c)) _action(key: ValueKey('${p}comment-delete-${widget.node.id}'), label: 'ลบ', color: cs.error, onTap: _delete),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action({Key? key, IconData? icon, required String label, Color? color, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(tr(label), style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// Comment text: @mentions as chips, links tappable (in-app for NEXTX links);
/// rich legacy HTML (lists, tables, bold…) falls back to [NxHtmlView].
class NxCommentBody extends StatefulWidget {
  const NxCommentBody({super.key, required this.html, this.keyPrefix = '', this.style});
  final String html;
  final String keyPrefix;
  final TextStyle? style;

  @override
  State<NxCommentBody> createState() => _NxCommentBodyState();
}

class _NxCommentBodyState extends State<NxCommentBody> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = widget.style ?? theme.textTheme.bodyMedium;
    if (commentNeedsRichView(widget.html)) return NxHtmlView(html: widget.html, style: style);
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final segs = commentSegments(widget.html);
    if (segs.length == 1 && segs.first.kind == CommentSegKind.text) {
      return Text(segs.first.value, style: style);
    }
    final chip = style?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w700,
      background: Paint()..color = cs.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12),
    );
    return Text.rich(
      key: ValueKey('${widget.keyPrefix}comment-rich'),
      TextSpan(style: style, children: [
        for (final s in segs)
          switch (s.kind) {
            CommentSegKind.text => TextSpan(text: s.value),
            CommentSegKind.mention => TextSpan(text: ' @${s.value} ', style: chip),
            CommentSegKind.url => TextSpan(
                text: s.value,
                style: TextStyle(color: cs.primary, decoration: TextDecoration.underline, decorationColor: cs.primary),
                recognizer: (TapGestureRecognizer()..onTap = () => openCommentLink(context, s.value)).also(_taps.add),
              ),
          },
      ]),
    );
  }
}

extension _Also<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
