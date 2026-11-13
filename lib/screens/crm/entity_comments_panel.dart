import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../widgets/comments/nx_comment_composer.dart';
import '../../widgets/comments/nx_comment_thread.dart';
import '../../widgets/comments/nx_comments_controller.dart';

export '../../widgets/comments/nx_comment_composer.dart' show NxCommentComposer;
export '../../widgets/comments/nx_comments_controller.dart' show NxCommentsController;

/// Controller for a record's comments tab (the web's `/api/entity/:module/:id/comments`):
/// author / business admins edit and delete, @mentions from the business users.
NxCommentsController entityCommentsController(BuildContext context, {required String module, required String id, required Future<void> Function() onChanged}) {
  final config = context.read<AppConfig>();
  final s = config.session;
  return NxCommentsController(
    api: NxCommentsApi.entity(config.apiClient, module, id),
    onChanged: onChanged,
    meId: s.userId,
    isAdmin: s.isBusinessAdmin || s.isSuperadmin,
  );
}

/// Record comments tab: threads like the web (reply → nested thread, collapse,
/// reply quote), mention chips, link previews, file preview, edit / delete.
///
/// With a [controller] the host shows [NxCommentComposer] (sticky at the
/// bottom of the screen); without one the composer sits under the list.
class EntityCommentsPanel extends StatefulWidget {
  const EntityCommentsPanel({
    super.key,
    required this.module,
    required this.id,
    required this.comments,
    required this.onChanged,
    this.controller,
    this.focusCommentId,
  });

  final String module;
  final String id;
  final List<Map<String, dynamic>> comments;
  final Future<void> Function() onChanged;
  final NxCommentsController? controller;

  /// Comment to scroll to and highlight (mention notification deep link).
  final String? focusCommentId;

  @override
  State<EntityCommentsPanel> createState() => _EntityCommentsPanelState();
}

class _EntityCommentsPanelState extends State<EntityCommentsPanel> {
  NxCommentsController? _own;
  String? _pendingFocus;

  NxCommentsController get _ctl =>
      widget.controller ?? (_own ??= entityCommentsController(context, module: widget.module, id: widget.id, onChanged: widget.onChanged));

  @override
  void initState() {
    super.initState();
    _pendingFocus = widget.focusCommentId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
  }

  @override
  void didUpdateWidget(covariant EntityCommentsPanel old) {
    super.didUpdateWidget(old);
    _own?.onChanged = widget.onChanged;
    if (widget.focusCommentId != old.focusCommentId) _pendingFocus = widget.focusCommentId;
    if (_pendingFocus != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
  }

  void _focus() {
    final id = _pendingFocus;
    if (!mounted || id == null || id.isEmpty) return;
    if (!widget.comments.any((c) => '${c['id']}' == id)) return;
    _pendingFocus = null;
    _ctl.flash(id, duration: const Duration(seconds: 4));
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inline = widget.controller == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxCommentThreadView(
          comments: widget.comments,
          controller: _ctl,
          emptyHint: inline
              ? 'เริ่มสนทนาได้จากช่องด้านล่าง — พิมพ์ @ เพื่อกล่าวถึง แนบรูป ไฟล์ หรือลิงก์ได้'
              : 'เขียนจากช่องด้านล่างของจอ — พิมพ์ @ เพื่อกล่าวถึง แนบรูป ไฟล์ หรือลิงก์ได้',
        ),
        if (inline) ...[
          const SizedBox(height: 8),
          NxCommentComposer(controller: _ctl),
        ],
      ],
    );
  }
}
