import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/i18n.dart';
import '../nx_attachments.dart' show nxFileStyle;
import '../nx_avatar.dart';
import '../nx_icons.dart';
import '../nx_overlay_panel.dart';
import 'nx_comment_format.dart';
import 'nx_comments_controller.dart';
import 'nx_link_preview.dart';

/// Max files in one comment (the server keeps 20) and per-file size (web: 500 MB).
const kCommentMaxFiles = 10;
const kCommentMaxFileBytes = 500 * 1024 * 1024;

typedef PickedCommentFile = ({String name, Uint8List bytes, String? mime});

/// Test hook: replaces the camera / gallery / file pickers.
Future<List<PickedCommentFile>> Function(String source)? debugCommentFilePicker;

String? _mimeOf(String name) {
  final e = name.toLowerCase().split('.').last;
  return switch (e) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    _ => null,
  };
}

/// Camera (one photo) / gallery (several photos) / files (several) → bytes.
Future<List<PickedCommentFile>> pickCommentFiles(BuildContext context, String source) async {
  final hook = debugCommentFilePicker;
  if (hook != null) return hook(source);
  final out = <PickedCommentFile>[];
  if (source == 'file') {
    final picked = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    for (final f in picked?.files ?? const <PlatformFile>[]) {
      if (f.bytes != null) out.add((name: f.name, bytes: f.bytes!, mime: _mimeOf(f.name)));
    }
    return out;
  }
  final picker = ImagePicker();
  // Phone photos are 4–12 MB: 1920 px is plenty for a comment.
  if (source == 'camera') {
    final x = await picker.pickImage(source: ImageSource.camera, maxWidth: 1920, imageQuality: 82);
    if (x != null) out.add((name: x.name, bytes: await x.readAsBytes(), mime: x.mimeType ?? _mimeOf(x.name)));
  } else {
    for (final x in await picker.pickMultiImage(maxWidth: 1920, imageQuality: 82)) {
      out.add((name: x.name, bytes: await x.readAsBytes(), mime: x.mimeType ?? _mimeOf(x.name)));
    }
  }
  return out;
}

/// Text field with the @mention people picker (business users, like the web).
class NxMentionField extends StatelessWidget {
  const NxMentionField({
    super.key,
    required this.controller,
    required this.text,
    required this.focus,
    this.fieldKey,
    this.hint = 'เขียนคอมเม้นท์…',
    this.suggestionsAbove = true,
    this.enabled = true,
    this.decoration,
  });

  final NxCommentsController controller;
  final NxMentionTextController text;
  final FocusNode focus;
  final Key? fieldKey;
  final String hint;

  /// Composer at the bottom: the list opens above the field.
  final bool suggestionsAbove;
  final bool enabled;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([text, focus, controller]),
      builder: (context, _) {
        final q = focus.hasFocus ? text.mentionQuery : null;
        final users = q == null ? const <Map<String, dynamic>>[] : _matches(q.query);
        final list = q == null ? null : _Suggestions(controller: controller, users: users, onPick: (u) => text.insertMention(u, at: q), loading: users.isEmpty && q.query.isEmpty);
        final field = TextField(
          key: fieldKey,
          controller: text,
          focusNode: focus,
          enabled: enabled,
          minLines: 1,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: decoration ?? InputDecoration(hintText: tr(hint), border: InputBorder.none, isDense: true, filled: false),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (list != null && suggestionsAbove) list,
            field,
            if (list != null && !suggestionsAbove) list,
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _matches(String query) {
    // Loads the users on first "@" (cached by the API client).
    final all = controller.mentionSuggestionsFor(query);
    return all;
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.controller, required this.users, required this.onPick, required this.loading});
  final NxCommentsController controller;
  final List<Map<String, dynamic>> users;
  final ValueChanged<Map<String, dynamic>> onPick;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = controller.keyPrefix;
    return Container(
      key: ValueKey('${p}mention-picker'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: users.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr(controller.usersLoaded ? 'ไม่พบผู้ใช้' : 'กำลังโหลดรายชื่อ…'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                  child: Text(tr('กล่าวถึง'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                ),
                for (final u in users)
                  InkWell(
                    key: ValueKey('${p}mention-option-${u['id']}'),
                    onTap: () => onPick(u),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(children: [
                        NxAvatar(label: mentionUserLabel(u), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(mentionUserLabel(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            if ('${u['email1'] ?? u['email'] ?? ''}'.isNotEmpty)
                              Text('${u['email1'] ?? u['email']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Comment composer like the web CommentComposer: reply quote, @mentions,
/// attachment tray (thumbnails, upload progress, retry, remove), link preview
/// of the first pasted link, send disabled while empty / uploading.
///
/// [sticky]: sits at the bottom of the screen (a Scaffold's bottom bar) and
/// rises with the keyboard.
class NxCommentComposer extends StatelessWidget {
  const NxCommentComposer({super.key, required this.controller, this.sticky = false, this.enabled = true, this.hint = 'เขียนคอมเม้นท์…'});
  final NxCommentsController controller;
  final bool sticky;
  final bool enabled;
  final String hint;

  Future<void> _attach(BuildContext context) async {
    final source = await showNxBlurPanel<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(key: const ValueKey('comment-attach-camera'), leading: const Icon(NxI.camera), title: Text(tr('ถ่ายรูป')), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(key: const ValueKey('comment-attach-gallery'), leading: const Icon(NxI.images), title: Text(tr('เลือกรูปจากเครื่อง')), onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(key: const ValueKey('comment-attach-file'), leading: const Icon(NxI.file), title: Text(tr('เลือกไฟล์')), onTap: () => Navigator.pop(ctx, 'file')),
        ],
      ),
    );
    if (source == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    List<PickedCommentFile> files;
    try {
      files = await pickCommentFiles(context, source);
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(tr('เปิดกล้อง / คลังรูปไม่ได้'))));
      return;
    }
    final tooBig = files.where((f) => f.bytes.length > kCommentMaxFileBytes).length;
    files = files.where((f) => f.bytes.length <= kCommentMaxFileBytes).toList();
    final room = kCommentMaxFiles - controller.uploads.length;
    if (files.length > room) {
      messenger?.showSnackBar(SnackBar(content: Text(tr('แนบได้สูงสุด $kCommentMaxFiles ไฟล์ต่อคอมเม้นท์'))));
      files = files.take(room < 0 ? 0 : room).toList();
    }
    if (tooBig > 0) messenger?.showSnackBar(SnackBar(content: Text(tr('ไฟล์ใหญ่เกิน 500 MB'))));
    if (files.isNotEmpty) controller.addFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final c = controller;
        final p = c.keyPrefix;
        final reply = c.replyTo;
        final link = c.draftLink;
        final inner = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 0, 4),
                child: Row(children: [
                  Icon(NxI.warningCircle, size: 16, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr(c.error!), style: theme.textTheme.bodySmall?.copyWith(color: cs.error))),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(NxI.x, size: 14), onPressed: c.clearError),
                ]),
              ),
            if (reply != null)
              Container(
                key: ValueKey('${p}comment-reply-bar'),
                margin: const EdgeInsets.fromLTRB(4, 2, 0, 6),
                padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: cs.primary, width: 3)),
                ),
                child: Row(children: [
                  Icon(NxI.reply, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('ตอบกลับ ${reply['user_name'] ?? ''}'), style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                      if (commentFromHtml('${reply['body'] ?? ''}').text.isNotEmpty)
                        Text(commentFromHtml('${reply['body'] ?? ''}').text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  IconButton(
                    key: ValueKey('${p}comment-reply-cancel'),
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('ยกเลิก'),
                    icon: const Icon(NxI.x, size: 16),
                    onPressed: c.cancelReply,
                  ),
                ]),
              ),
            if (c.uploads.isNotEmpty) _tray(context),
            if (link != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
                child: NxLinkPreviewCard(url: link, fetch: c.api.linkPreview, compact: true, onClose: () => c.dismissPreview(link)),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: ValueKey('${p}comment-attach'),
                  tooltip: tr('แนบรูป / ไฟล์'),
                  onPressed: !enabled || c.sending ? null : () => _attach(context),
                  icon: const Icon(NxI.plus, size: 22),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
                    decoration: BoxDecoration(
                      color: sticky ? cs.surfaceContainerHighest.withValues(alpha: 0.7) : cs.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: NxMentionField(
                            controller: c,
                            text: c.text,
                            focus: c.focus,
                            enabled: enabled,
                            fieldKey: ValueKey('${p}comment-input'),
                            hint: hint,
                          ),
                        ),
                      ),
                      if (c.api.mentionUsers != null)
                        IconButton(
                          key: ValueKey('${p}comment-mention'),
                          tooltip: tr('กล่าวถึง (@)'),
                          visualDensity: VisualDensity.compact,
                          onPressed: !enabled ? null : c.typeAt,
                          icon: Icon(NxI.at, size: 18, color: cs.onSurfaceVariant),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: IconButton.filled(
                    key: ValueKey('${p}comment-send'),
                    tooltip: tr(c.hasUploading ? 'รออัปโหลดให้เสร็จ' : 'ส่ง'),
                    onPressed: enabled && c.canSend ? c.send : null,
                    icon: c.sending
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                        : const Icon(NxI.paperPlaneTilt, size: 18),
                  ),
                ),
              ],
            ),
          ],
        );
        if (!sticky) {
          return Container(
            padding: const EdgeInsets.fromLTRB(2, 6, 6, 6),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(22)),
            child: inner,
          );
        }
        // Bottom bar: rises with the keyboard (the Scaffold leaves the inset to us).
        return Material(
          color: theme.colorScheme.surface,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.3 : 0.06), blurRadius: 16, offset: const Offset(0, -4))],
              color: cs.surface,
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: SafeArea(
              top: false,
              child: Padding(padding: const EdgeInsets.fromLTRB(4, 6, 10, 6), child: inner),
            ),
          ),
        );
      },
    );
  }

  Widget _tray(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = controller;
    final p = c.keyPrefix;
    return SizedBox(
      height: 84,
      child: ListView.separated(
        key: ValueKey('${p}comment-tray'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        itemCount: c.uploads.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final u = c.uploads[i];
          final st = nxFileStyle({'name': u.name, 'mime': u.mime});
          final failed = u.status == NxUploadStatus.failed;
          return Stack(
            key: ValueKey('${p}comment-upload-$i'),
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 72,
                  height: 72,
                  color: cs.surfaceContainerHighest,
                  child: u.isImage
                      ? Image.memory(u.bytes, width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216, errorBuilder: (_, _, _) => Icon(NxI.image, color: cs.onSurfaceVariant))
                      : Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(st.icon, color: st.color, size: 22),
                            const SizedBox(height: 4),
                            Text(u.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5)),
                          ]),
                        ),
                ),
              ),
              if (u.status == NxUploadStatus.uploading)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          key: ValueKey('${p}comment-upload-progress-$i'),
                          value: u.progress > 0 && u.progress < 1 ? u.progress : null,
                          strokeWidth: 3,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  ),
                ),
              if (failed)
                Positioned.fill(
                  child: Material(
                    color: cs.errorContainer.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: ValueKey('${p}comment-upload-retry-$i'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => c.retry(u),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(NxI.arrowCounterClockwise, size: 20, color: cs.onErrorContainer),
                        Text(tr('ลองใหม่'), style: TextStyle(fontSize: 10, color: cs.onErrorContainer, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  key: ValueKey('${p}comment-upload-remove-$i'),
                  onTap: () => c.remove(u),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle, border: Border.all(color: cs.outlineVariant)),
                    child: const Icon(NxI.x, size: 13),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
