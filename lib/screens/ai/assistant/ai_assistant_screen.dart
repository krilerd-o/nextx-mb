import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/ai_assistant.dart';
import '../../../core/app_config.dart';
import '../../../core/i18n.dart';
import '../../../core/isaac_states.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/nx_breakpoint.dart';
import '../../../core/nx_network.dart';
import '../../../services/nx_speech.dart';
import '../../../core/navigation/notification_deep_link.dart';
import '../../../widgets/isaac_sticker.dart';
import '../../../widgets/nx_attachments.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_markdown.dart';
import '../../../widgets/nx_skeleton.dart';
import '../../../widgets/nx_split_view.dart' show NxHingeSplit;
import '../web_session_screen.dart';
import 'ai_assistant_controller.dart';
import 'ai_cards.dart';

/// ISAAC AI Assistant (web `/ai`): chats kept on the server, streamed
/// answers with Isaac's moods, action cards, files, follow-ups, model + quota.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, this.controller, this.contextModule, this.contextId, this.contextTitle});

  /// For tests.
  final AiAssistantController? controller;

  /// "ถาม Isaac" from a record: the chat is about this record.
  final String? contextModule;
  final String? contextId;
  final String? contextTitle;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  late final AiAssistantController _c = widget.controller ?? AiAssistantController(context.read<AppConfig>().apiClient);
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  Timer? _tick;
  DateTime? _finishedAt;
  bool _wasSending = false;

  /// Voice input: listening, and the text typed before speaking started.
  bool _listening = false;
  String _speechBase = '';

  /// Boards for workspace tree proposals (loaded once) and the pick per proposal.
  List<Map<String, dynamic>>? _boards;
  bool _boardsLoading = false;
  final Map<String, String?> _boardFor = {};

  /// The board picked for [p]: the user's choice, else the proposal's board, else the first one (like the web).
  String? _boardOf(Map<String, dynamic> p) {
    final id = '${p['proposalId']}';
    if (_boardFor.containsKey(id)) return _boardFor[id];
    final pv = p['preview'] is Map ? p['preview'] as Map : const {};
    final f = pv['fields'] is Map ? pv['fields'] as Map : const {};
    final fromProposal = f['board_id']?.toString();
    if (fromProposal != null && fromProposal.isNotEmpty) return fromProposal;
    final list = _boards ?? const [];
    return list.isEmpty ? null : '${list.first['id']}';
  }

  List<Map<String, dynamic>> _writableBoards() {
    if (_boards == null && !_boardsLoading) {
      _boardsLoading = true;
      _c.api
          .getBoards(writable: true)
          .then((list) {
            if (!mounted) return;
            setState(() {
              _boards = list;
            });
          })
          .catchError((_) {
            if (mounted) setState(() => _boards = const []);
          });
    }
    return _boards ?? const [];
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _focus.addListener(() => setState(() {}));
    _input.addListener(() => setState(() {}));
    NxNetwork.instance.ensureStarted();
    if (widget.contextModule != null && widget.contextId != null) {
      _c.contextModule = widget.contextModule;
      _c.contextId = widget.contextId;
      _c.contextTitle = widget.contextTitle;
      _input.text = tr('สรุปรายการนี้ให้หน่อย และควรทำอะไรต่อ');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _c.init();
      if (mounted) IsaacSticker.preload(context);
    });
  }

  @override
  void dispose() {
    if (_listening) NxSpeech.instance.stop();
    _c.removeListener(_onChange);
    if (widget.controller == null) _c.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    _tick?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (_c.sending && !_wasSending) {
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (!_c.sending && _wasSending) {
      _tick?.cancel();
      _finishedAt = DateTime.now();
      Future.delayed(const Duration(milliseconds: kIsaacDoneMs + 100), () {
        if (mounted) setState(() {});
      });
    }
    _wasSending = _c.sending;
    if (mounted) setState(() {});
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max - _scroll.offset < 400 || _c.sending) _scroll.jumpTo(max);
    });
  }

  Future<void> _send([String? text]) async {
    final t = text ?? _input.text;
    if (text == null) _input.clear();
    HapticFeedback.lightImpact();
    await _c.send(t);
  }

  void _openLink(String href) {
    if (handleInAppWebLink(context, href)) return;
    openNxFile(href.startsWith('/') ? _c.api.absoluteUrl(href) : href);
  }

  // ── attachments

  Future<void> _attachMenu() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(NxI.camera), title: Text(tr('ถ่ายรูป')), onTap: () => Navigator.pop(ctx, 'camera')),
            ListTile(leading: const Icon(NxI.image), title: Text(tr('รูปภาพ')), onTap: () => Navigator.pop(ctx, 'gallery')),
            ListTile(leading: const Icon(NxI.paperclip), title: Text(tr('ไฟล์ (PDF, Word, Excel, เสียง, วิดีโอ)')), onTap: () => Navigator.pop(ctx, 'file')),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (picked == 'file') {
      final r = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'txt', 'doc', 'docx', 'json', 'csv', 'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'webp', 'mp3', 'm4a', 'wav', 'mp4', 'mov'],
      );
      final f = r?.files.firstOrNull;
      if (f == null || f.bytes == null) return;
      await _c.uploadAttachment(MultipartFile.fromBytes(f.bytes!, filename: f.name));
      return;
    }
    final x = await ImagePicker().pickImage(source: picked == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 2200, imageQuality: 85);
    if (x == null) return;
    await _c.uploadAttachment(MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name));
  }

  // ── model picker

  static const _providers = [
    ('gemini', 'Gemini'),
    ('claude', 'Claude'),
    ('openai', 'ChatGPT'),
    ('deepseek', 'DeepSeek'),
    ('kimi', 'Kimi'),
    ('qwen', 'Qwen'),
    ('gemma', 'Gemma'),
    ('ollama', 'Ollama'),
  ];

  Future<void> _pickModel() async {
    final choice = await showModalBottomSheet<(String, String?)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ModelSheet(api: _c.api, current: (_c.provider, _c.model), providers: _providers, policy: _c.policy),
    );
    if (choice != null) _c.setModel(choice.$1, choice.$2);
  }

  // ── conversation menu

  Future<void> _rename(AiConversation c) async {
    final ctl = TextEditingController(text: c.title);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('เปลี่ยนชื่อแชท')),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ยกเลิก'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('บันทึก'))),
        ],
      ),
    );
    if (v != null) await _c.rename(c.id, v);
  }

  /// Delete with undo (5s), like CRM records: hidden now, removed on the
  /// server only when the snackbar closes without "เลิกทำ".
  Future<void> _delete(AiConversation c) async {
    final removed = _c.removeLocal(c.id);
    if (removed == null) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            key: const ValueKey('ai-delete-undo'),
            content: Text(tr('ลบ "${c.title}" แล้ว')),
            duration: const Duration(seconds: 5),
            // Actions make snackbars persist by default; these must time out.
            persist: false,
            action: SnackBarAction(label: tr('เลิกทำ'), onPressed: () {}),
          ),
        )
        .closed;
    if (reason == SnackBarClosedReason.action) {
      _c.restoreLocal(removed);
      return;
    }
    try {
      await _c.api.deleteAiConversation(c.id);
    } catch (e) {
      _c.restoreLocal(removed);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(tr(aiErrorText(e)))));
    }
  }

  Future<void> _moveToProject(AiConversation c) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(NxI.x),
              title: Text(tr('ไม่อยู่ในโปรเจกต์')),
              trailing: c.projectId == null ? const Icon(NxI.check) : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final p in _c.projects)
              ListTile(
                leading: const Icon(NxI.folder),
                title: Text('${p['name'] ?? ''}'),
                trailing: c.projectId == '${p['id']}' ? const Icon(NxI.check) : null,
                onTap: () => Navigator.pop(ctx, '${p['id']}'),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    try {
      await _c.moveToProject(c.id, picked.isEmpty ? null : picked);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(aiErrorText(e)))));
    }
  }

  Future<void> _share() async {
    final id = _c.activeId;
    if (id == null) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(NxI.users),
            title: Text(tr('คนในธุรกิจนี้')),
            subtitle: Text(tr('ต้องเข้าสู่ระบบจึงเปิดดูได้')),
            onTap: () => Navigator.pop(ctx, 'business'),
          ),
          ListTile(
            leading: const Icon(NxI.globe),
            title: Text(tr('ทุกคนที่มีลิงก์')),
            subtitle: Text(tr('เปิดดูได้โดยไม่ต้องเข้าสู่ระบบ')),
            onTap: () => Navigator.pop(ctx, 'public'),
          ),
        ]),
      ),
    );
    if (mode == null || !mounted) return;
    try {
      final r = await _c.api.createAiShare(id, accessMode: mode);
      if (!mounted) return;
      final url = aiShareUrl(WebSessionScreen.webOrigin(context.read<AppConfig>().apiBaseUrl), r);
      if (url.isNotEmpty) await Share.share('${_c.activeTitle}\n$url');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(aiErrorText(e)))));
    }
  }

  void _chatMenu(AiConversation c) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(c.starred ? NxI.star : NxI.star, color: c.starred ? const Color(0xFFF59E0B) : null),
              title: Text(tr(c.starred ? 'เลิกติดดาว' : 'ติดดาว')),
              onTap: () {
                Navigator.pop(ctx);
                _c.toggleStar(c.id, !c.starred);
              },
            ),
            ListTile(
              leading: const Icon(NxI.pencilSimple),
              title: Text(tr('เปลี่ยนชื่อ')),
              onTap: () {
                Navigator.pop(ctx);
                _rename(c);
              },
            ),
            if (_c.projects.isNotEmpty)
              ListTile(
                leading: const Icon(NxI.folder),
                title: Text(tr('ย้ายไปโปรเจกต์')),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveToProject(c);
                },
              ),
            ListTile(
              leading: Icon(NxI.trash, color: Theme.of(ctx).colorScheme.error),
              title: Text(tr('ลบ'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final empty = _c.messages.isEmpty && !_c.chatLoading;
    final bp = NxBreakpoint.of(context);
    final docked = bp.twoPane;
    final chat = SafeArea(
      bottom: false,
      child: Column(
        children: [
          // Header: chats · title · new chat · ⋯
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                if (Navigator.of(context).canPop())
                  IconButton(tooltip: tr('กลับ'), icon: const Icon(NxI.arrowLeft), onPressed: () => Navigator.of(context).maybePop()),
                if (!docked)
                  IconButton(
                    key: const ValueKey('ai-open-chats'),
                    tooltip: tr('รายการแชท'),
                    icon: const Icon(NxI.listBullets),
                    onPressed: () {
                      _c.loadConversations();
                      _scaffold.currentState?.openDrawer();
                    },
                  ),
                Expanded(
                  child: GestureDetector(
                    onTap: _c.activeId == null
                        ? null
                        : () => _rename(
                            _c.conversations.firstWhere(
                              (x) => x.id == _c.activeId,
                              orElse: () => AiConversation(id: _c.activeId!, title: _c.activeTitle),
                            ),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _c.activeId == null ? 'AI Assistant' : (_c.activeTitle.isEmpty ? tr('แชทใหม่') : _c.activeTitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text('ISAAC AI', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                IconButton(key: const ValueKey('ai-new-chat'), tooltip: tr('แชทใหม่'), icon: const Icon(NxI.squarePen), onPressed: _c.newChat),
                if (_c.activeId != null)
                  IconButton(
                    tooltip: tr('เพิ่มเติม'),
                    icon: const Icon(NxI.dotsThree),
                    onPressed: () => _chatMenu(
                      _c.conversations.firstWhere(
                        (x) => x.id == _c.activeId,
                        orElse: () => AiConversation(id: _c.activeId!, title: _c.activeTitle, starred: _c.activeStarred),
                      ),
                    ),
                  ),
                if (_c.activeId != null) IconButton(tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork), onPressed: _share),
              ],
            ),
          ),
          if (_c.quotaExhausted) _Banner(color: cs.error, icon: NxI.warningCircle, text: tr('โควตา AI เดือนนี้หมดแล้ว — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ')),
          Expanded(
            child: _c.chatLoading
                ? const NxSkeletonChat()
                : empty
                ? _welcome(context)
                : ListView.builder(
                    key: const ValueKey('ai-messages'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _c.messages.length,
                    itemBuilder: (context, i) => _message(context, _c.messages[i], last: i == _c.messages.length - 1),
                  ),
          ),
          if (_c.error != null)
            _Banner(
              key: const ValueKey('ai-error'),
              color: cs.error,
              icon: NxI.warningCircle,
              text: _c.error!,
              action: _c.messages.any((m) => m.isUser) ? 'ลองใหม่' : null,
              onAction: () {
                _c.clearError();
                if (_c.activeId != null) _c.regenerate();
              },
              onClose: _c.clearError,
            ),
          if (_c.followUps.isNotEmpty && !_c.sending && !_cramped(context)) _followUps(context),
          if (!_cramped(context)) _usageStrip(context),
          if (_c.contextModule != null) _contextChip(context),
          _composer(context),
        ],
      ),
    );
    if (!docked)
      return Scaffold(
        key: _scaffold,
        drawer: Drawer(child: SafeArea(child: _chatList(context))),
        body: chat,
      );
    // Tablet / opened foldable: chats stay on the left (left of the fold,
    // measured from where this view starts, e.g. after the side rail).
    final sidebar = Material(
      key: const ValueKey('ai-chat-sidebar'),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: SafeArea(right: false, child: _chatList(context, docked: true)),
    );
    return Scaffold(
      key: _scaffold,
      body: bp.hinge != null
          ? NxHingeSplit(hinge: bp.hinge!, list: sidebar, detail: chat)
          : Row(
              children: [
                SizedBox(width: 320, child: sidebar),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(child: chat),
              ],
            ),
    );
  }

  String _mood({AiMessage? m, bool last = false}) {
    final st = _c.status;
    return resolveIsaacState(
      welcome: m == null && _c.messages.isEmpty,
      error: last && _c.error != null,
      composerFocused: _focus.hasFocus,
      draftLength: _input.text.length,
      loading: last && _c.sending && (m?.content.isEmpty ?? true),
      streaming: last && _c.sending && (m?.content.isNotEmpty ?? false),
      phase: st?.type == 'status' ? '${st?.data['phase'] ?? ''}' : st?.type,
      toolName: st?.type == 'tool_start' ? '${st?.data['name'] ?? ''}' : null,
      hasAskUser: (m?.askUser.isNotEmpty ?? false),
      hasDownloads: (m?.downloads.isNotEmpty ?? false),
      attachmentCount: last && _c.sending ? (_c.messages.length > 1 ? _c.messages[_c.messages.length - 2].attachments.length : 0) : 0,
      elapsedMs: _c.sendStartedAt == null ? null : DateTime.now().difference(_c.sendStartedAt!).inMilliseconds,
      finishedAgoMs: last && _finishedAt != null ? DateTime.now().difference(_finishedAt!).inMilliseconds : null,
      simpleQa: (m?.proposals.isEmpty ?? true) && (m?.content.length ?? 0) < 600,
      actionConfirmed: (m?.proposals ?? const []).any((p) => _c.proposalState['${p['proposalId']}'] == 'done'),
      uploading: _c.uploading,
    );
  }

  Widget _welcome(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = context.read<AppConfig>().session.displayName ?? '';
    const intents = [
      (NxI.magnifyingGlass, 'ค้นหาในระบบ', 'ลูกค้า สัญญา เคส บอร์ด', 'ช่วยค้นหาลูกค้าหรือรายการในระบบให้หน่อย'),
      (NxI.plus, 'สร้างรายการ', 'Lead, Contact, Case, นัด', 'อยากสร้างรายการใหม่ในระบบ'),
      (NxI.file, 'เอกสาร / ส่งออก', 'Word, PDF, Excel จากข้อมูล', 'ช่วยสร้างเอกสารหรือส่งออกข้อมูลเป็นไฟล์'),
      (NxI.kanban, 'งานบนบอร์ด', 'Workspace task / epic', 'สร้างงานบนบอร์ด Workspace'),
    ];
    return ListView(
      key: const ValueKey('ai-welcome'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        const Center(child: IsaacSticker(state: 'hello', size: 104)),
        const SizedBox(height: 12),
        _TypedText(
          text: name.isEmpty ? tr('สวัสดี') : tr('สวัสดี คุณ $name'),
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          tr('ถามอะไรเกี่ยวกับงาน CRM ก็ได้'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final w = (box.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (icon, title, desc, prompt) in intents)
                  SizedBox(
                    width: w,
                    child: Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        key: ValueKey('ai-intent-$title'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          _input.text = tr(prompt);
                          _focus.requestFocus();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 20, color: cs.primary),
                              const SizedBox(height: 8),
                              Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                tr(desc),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in _c.suggestedPrompts.take(3))
              ActionChip(
                avatar: Icon(NxI.sparkle, size: 14, color: cs.primary),
                label: Text('${(L10n.isEn ? p['name_en'] : p['name_th']) ?? p['name_th'] ?? ''}'),
                onPressed: () => _send('${(L10n.isEn ? p['prompt_en'] : p['prompt_th']) ?? p['prompt_th'] ?? ''}'),
              ),
            ActionChip(
              avatar: Icon(NxI.briefcase, size: 14, color: cs.primary),
              label: Text(tr('ใช้บริบท CRM')),
              onPressed: () => _send(tr('จากบริบท CRM ของฉัน วันนี้ควรโฟกัสอะไร?')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _message(BuildContext context, AiMessage m, {required bool last}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (m.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6, left: 40),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (m.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: NxAttachmentStrip(items: m.attachments, thumb: 72),
                  ),
                if (m.content.trim().isNotEmpty) SelectableText(m.content, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
              ],
            ),
          ),
        ),
      );
    }
    final waiting = m.streaming && m.content.isEmpty;
    final mood = _mood(m: m, last: last);
    return Padding(
      key: ValueKey('ai-reply-${m.id ?? m.hashCode}'),
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IsaacSticker(state: last ? mood : 'happy', size: 40, animate: last),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  aiModelBadge(m.provider, m.model),
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                ),
              ),
              if (last && _c.sending) ...[
                const SizedBox(width: 8),
                Text(tr(kIsaacLabels[mood] ?? ''), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (waiting) _waiting(context) else NxMarkdown(data: m.content, streaming: m.streaming, onOpenLink: _openLink),
          for (final p in m.proposals)
            AiProposalCard(
              proposal: p,
              state: _c.proposalState['${p['proposalId']}'],
              boards: aiIsWorkspaceTree(p) ? _writableBoards() : null,
              boardId: _boardOf(p),
              onBoard: (v) => setState(() => _boardFor['${p['proposalId']}'] = v),
              onConfirm: () async {
                final board = _boardOf(p);
                if (aiNeedsBoard(p) && (board == null || board.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เลือกบอร์ดก่อนยืนยัน'))));
                  return;
                }
                final link = await _c.confirmProposal(p, boardId: aiIsWorkspaceTree(p) ? board : null);
                if (link != null && link.isNotEmpty && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr('ทำรายการแล้ว')),
                      // Actions make snackbars persist by default; these must time out.
                      persist: false,
                      action: SnackBarAction(label: tr('เปิด'), onPressed: () => _openLink(link)),
                    ),
                  );
                }
              },
              onCancel: () => _c.cancelProposal(p),
            ),
          if (m.askUser.isNotEmpty) AiAskUserCard(questions: m.askUser, enabled: !_c.sending, onPick: _send),
          if (m.downloads.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AiDownloadChips(downloads: m.downloads, onRegenerate: last ? _c.regenerate : null),
            ),
          if (m.citations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AiCitationChips(citations: m.citations),
            ),
          if (!m.streaming && m.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _ActionIcon(
                    icon: NxI.copySimple,
                    label: 'คัดลอก',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: m.content));
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('คัดลอกแล้ว'))));
                    },
                  ),
                  if (last)
                    _ActionIcon(key: const ValueKey('ai-regenerate'), icon: NxI.arrowsClockwise, label: 'สร้างใหม่', onTap: _c.sending ? null : _c.regenerate),
                  _ActionIcon(icon: NxI.shareNetwork, label: 'แชร์', onTap: () => Share.share(m.content)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _waiting(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final secs = _c.sendStartedAt == null ? 0 : DateTime.now().difference(_c.sendStartedAt!).inSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Shimmer(
          child: Container(
            key: const ValueKey('ai-status'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
            child: Text(
              '${tr(aiStatusLabel(_c.status))}${secs >= 3 ? '  ${secs}s' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_c.routeSteps.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final (i, s) in _c.routeSteps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: i == _c.routeSteps.length - 1 ? cs.primary : cs.outline, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${s['label'] ?? s['id'] ?? ''}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _followUps(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        key: const ValueKey('ai-followups'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final f in _c.followUps)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(label: Text('${f['label'] ?? f['prompt'] ?? ''}'), onPressed: () => _send('${f['prompt'] ?? f['label'] ?? ''}')),
            ),
        ],
      ),
    );
  }

  /// Quota meter under the chat (cloud-metered plans only) + "switch model"
  /// choices when the month or this model's day runs out (web `AiUsageStrip`).
  Widget _usageStrip(BuildContext context) {
    final u = _c.usageView;
    if (u == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = u.exhausted ? cs.error : (u.low ? const Color(0xFFF59E0B) : cs.primary);
    return Padding(
      key: const ValueKey('ai-usage'),
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: u.usedFraction, minHeight: 4, color: color, backgroundColor: cs.surfaceContainerHighest),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tr('เหลือ ${aiTokenCount(u.remaining)} / ${aiTokenCount(u.quota)}'),
                style: theme.textTheme.labelSmall?.copyWith(color: u.exhausted || u.low ? color : cs.onSurfaceVariant),
              ),
            ],
          ),
          if (u.dailyExhausted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('โมเดลนี้ใช้ครบโควตาวันนี้แล้ว'), style: theme.textTheme.labelSmall?.copyWith(color: cs.error)),
            ),
          if (u.suggestSwitch)
            SizedBox(
              height: 40,
              child: ListView(
                key: const ValueKey('ai-usage-switch'),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final alt in u.alternatives.take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: 6, top: 4),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(NxI.arrowsClockwise, size: 14, color: cs.primary),
                        label: Text(tr('สลับไป ${aiModelBadge('${alt['provider'] ?? ''}', alt['model']?.toString() ?? alt['labelHint']?.toString())}')),
                        onPressed: () => _c.setModel('${alt['provider']}', alt['model']?.toString()),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await NxSpeech.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    HapticFeedback.selectionClick();
    _speechBase = _input.text.trim().isEmpty ? '' : '${_input.text.trim()} ';
    final ok = await NxSpeech.instance.start(
      localeId: L10n.isEn ? 'en_US' : 'th_TH',
      onText: (text, done) {
        if (!mounted) return;
        _input.text = '$_speechBase$text';
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        if (done) setState(() => _listening = false);
      },
      onStop: () {
        if (mounted && _listening) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ใช้ไมค์ไม่ได้ — ตรวจสิทธิ์ไมโครโฟนในการตั้งค่าเครื่อง'))));
      return;
    }
    setState(() => _listening = true);
  }

  /// Keyboard up in a short window: drop the extras around the composer.
  bool _cramped(BuildContext context) => MediaQuery.viewInsetsOf(context).bottom > 0 && MediaQuery.sizeOf(context).height < 700;

  Widget _contextChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('ai-context'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: Icon(NxI.link, size: 14, color: cs.primary),
          label: Text(tr('เกี่ยวกับ: ${_c.contextTitle ?? '${_c.contextModule} #${_c.contextId}'}'), overflow: TextOverflow.ellipsis),
          onDeleted: _c.clearContext,
          deleteButtonTooltipMessage: tr('ไม่ใช้บริบทนี้'),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locked = _c.quotaExhausted;
    final canSend = !locked && !_c.uploading && (_input.text.trim().isNotEmpty || _c.pendingAttachments.isNotEmpty);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _focus.hasFocus ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_c.pendingAttachments.isNotEmpty || _c.uploading)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: NxAttachmentStrip(items: _c.pendingAttachments, thumb: 56, onRemove: _c.removeAttachment),
                    ),
                    if (_c.uploading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
            TextField(
              key: const ValueKey('ai-input'),
              controller: _input,
              focusNode: _focus,
              enabled: !locked,
              minLines: 1,
              // Short window (landscape / split screen): keep the chat visible above the keyboard.
              maxLines: MediaQuery.sizeOf(context).height < 520 ? 2 : 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: tr(locked ? 'โควตาหมด — ส่งข้อความไม่ได้' : 'ถามอะไรก็ได้…'),
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('ai-attach'),
                  tooltip: tr('แนบไฟล์'),
                  icon: const Icon(NxI.plus),
                  onPressed: locked || _c.sending ? null : _attachMenu,
                ),
                Flexible(
                  child: ActionChip(
                    key: const ValueKey('ai-model'),
                    avatar: Icon(NxI.sparkle, size: 14, color: cs.primary),
                    label: Text(_c.provider == 'auto' ? 'Auto' : aiModelBadge(_c.provider, _c.model), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _c.sending ? null : _pickModel,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                if (!_c.sending && !locked)
                  IconButton(
                    key: const ValueKey('ai-mic'),
                    tooltip: tr(_listening ? 'หยุดฟัง' : 'พูดแทนพิมพ์'),
                    onPressed: _toggleMic,
                    icon: Icon(_listening ? NxI.stop : NxI.microphone, color: _listening ? cs.error : null),
                  ),
                if (_c.sending)
                  IconButton.filled(key: const ValueKey('ai-stop'), tooltip: tr('หยุด'), onPressed: _c.stop, icon: const Icon(NxI.stop, size: 16))
                else
                  IconButton.filled(
                    key: const ValueKey('ai-send'),
                    tooltip: tr('ส่ง'),
                    onPressed: canSend ? () => _send() : null,
                    icon: const Icon(NxI.paperPlaneTilt, size: 18),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatList(BuildContext context, {bool docked = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final groups = groupAiChats(_c.visibleConversations);
    void close() {
      if (!docked) Navigator.pop(context);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              const IsaacSticker(state: 'idle', size: 36, animate: false),
              const SizedBox(width: 8),
              Expanded(
                child: Text('ISAAC AI', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  close();
                  _c.newChat();
                },
                icon: const Icon(NxI.squarePen, size: 16),
                label: Text(tr('แชทใหม่')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(NxI.magnifyingGlass, size: 18), hintText: tr('ค้นหาแชท'), isDense: true),
            onSubmitted: (v) {
              _c.query = v;
              _c.loadConversations();
            },
          ),
        ),
        if (_c.projects.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              key: const ValueKey('ai-project-filter'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(tr('ทั้งหมด')), selected: _c.projectFilter == null, onSelected: (_) => _c.setProjectFilter(null)),
                ),
                for (final p in _c.projects)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: const Icon(NxI.folder, size: 14),
                      label: Text('${p['name'] ?? ''}'),
                      selected: _c.projectFilter == '${p['id']}',
                      onSelected: (_) => _c.setProjectFilter('${p['id']}'),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        // Agent and Notebook stay on the web (signed in automatically).
        ListTile(
          dense: true,
          leading: Icon(NxI.robot, color: cs.primary),
          title: Text(tr('Agent')),
          subtitle: Text(tr('งาน Agent และงานพื้นหลัง')),
          onTap: () {
            close();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WebSessionScreen(path: '/ai/agent', title: 'AI Agent', subtitle: 'ISAAC AI'),
              ),
            );
          },
        ),
        ListTile(
          dense: true,
          leading: Icon(NxI.bookOpen, color: cs.primary),
          title: Text(tr('Notebook')),
          subtitle: Text(tr('ถามจากแหล่งข้อมูลในสมุดของคุณ')),
          onTap: () {
            close();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WebSessionScreen(path: '/ai/notebook', title: 'AI Notebook', subtitle: 'ISAAC AI'),
              ),
            );
          },
        ),
        const Divider(),
        Expanded(
          child: _c.listLoading && _c.conversations.isEmpty
              ? const SingleChildScrollView(child: NxSkeletonList(rows: 5))
              : _c.visibleConversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const IsaacSticker(state: 'confused', size: 64, animate: false),
                      const SizedBox(height: 8),
                      Text(tr('ยังไม่มีแชท'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView(
                  key: const ValueKey('ai-chat-list'),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text(
                          tr(g.label),
                          style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final c in g.items)
                        ListTile(
                          key: ValueKey('ai-chat-${c.id}'),
                          dense: true,
                          selected: c.id == _c.activeId,
                          selectedTileColor: cs.primary.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: c.starred ? const Icon(NxI.star, size: 16, color: Color(0xFFF59E0B)) : const Icon(NxI.chatCircle, size: 16),
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(icon: const Icon(NxI.dotsThree, size: 18), onPressed: () => _chatMenu(c)),
                          onTap: () {
                            close();
                            _c.open(c.id);
                          },
                          onLongPress: () => _chatMenu(c),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({required this.api, required this.current, required this.providers, this.policy});
  final dynamic api;
  final (String, String?) current;
  final List<(String, String)> providers;

  /// Business policy: hides disabled providers / models (null = all).
  final AiModelPolicy? policy;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  String? _open;
  final Map<String, List<String>> _models = {};
  final Set<String> _loading = {};

  Future<void> _load(String p) async {
    setState(() {
      _open = _open == p ? null : p;
      if (!_models.containsKey(p)) _loading.add(p);
    });
    if (_models.containsKey(p)) return;
    final fromPolicy = widget.policy?.models(p);
    if (fromPolicy != null) {
      _models[p] = fromPolicy;
      setState(() => _loading.remove(p));
      return;
    }
    try {
      final r = await widget.api.getAiModels(provider: p) as Map<String, dynamic>;
      final list = r['models'] is List ? r['models'] as List : const [];
      _models[p] = [
        for (final m in list)
          if (m is Map) '${m['id'] ?? m['name'] ?? m['model'] ?? ''}' else '$m',
      ].where((e) => e.isNotEmpty).toList();
    } catch (_) {
      _models[p] = const [];
    }
    if (mounted) setState(() => _loading.remove(p));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(NxI.sparkle, color: cs.primary),
              title: Text(tr('Auto (แนะนำ)')),
              subtitle: Text(tr('ระบบเลือกโมเดลที่พร้อมและเหมาะกับคำถาม')),
              trailing: widget.current.$1 == 'auto' ? Icon(NxI.check, color: cs.primary) : null,
              onTap: () => Navigator.pop(context, ('auto', null)),
            ),
            const Divider(),
            for (final (id, label) in widget.providers.where((x) => widget.policy?.providerEnabled(x.$1) ?? true)) ...[
              ListTile(
                title: Text(label),
                trailing: _loading.contains(id)
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_open == id ? NxI.caretUp : NxI.caretDown, size: 18),
                onTap: () => _load(id),
              ),
              if (_open == id)
                if ((_models[id] ?? const []).isEmpty && !_loading.contains(id))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(tr('ยังไม่ได้ตั้งค่าผู้ให้บริการนี้'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  )
                else
                  for (final m in _models[id] ?? const <String>[])
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      dense: true,
                      title: Text(m),
                      trailing: widget.current.$1 == id && widget.current.$2 == m ? Icon(NxI.check, color: cs.primary) : null,
                      onTap: () => Navigator.pop(context, (id, m)),
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.color, required this.icon, required this.text, this.action, this.onAction, this.onClose});
  final Color color;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr(text), style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(tr(action!))),
          if (onClose != null) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(NxI.x, size: 16), onPressed: onClose),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({super.key, required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tr(label),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 17, color: cs.onSurfaceVariant),
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: chars.length.toDouble()),
      duration: Duration(milliseconds: (chars.length * 35).clamp(200, 1400)),
      builder: (context, v, _) => Text(chars.take(v.round()).join(), textAlign: TextAlign.center, style: style),
    );
  }
}

/// Soft shimmer on the status chip while waiting.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1.5 + 3 * _a.value, 0),
          end: Alignment(-0.5 + 3 * _a.value, 0),
          colors: [Colors.transparent, Colors.white.withValues(alpha: 0.35), Colors.transparent],
        ).createShader(r),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// `/workspace/...`, `/modules/...` links in answers open inside the app.
bool handleInAppWebLink(BuildContext context, String href) {
  final route = aiInAppRoute(href, serverOrigin: WebSessionScreen.webOrigin(context.read<AppConfig>().apiBaseUrl));
  if (route == null) return false;
  context.push(route);
  return true;
}

const _inAppPrefixes = ['modules', 'calendar', 'workspace', 'crm', 'fsm', 'jobs', 'chat'];

/// App route for a link in an AI answer, or null when it should open outside.
String? aiInAppRoute(String href, {String? serverOrigin}) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return null;
  if (uri.hasScheme) {
    if (serverOrigin == null || uri.origin != serverOrigin) return null;
  }
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length >= 3 && segs[0] == 'share' && segs[1] == 'ai') return AppRoutes.aiShared(segs[2]);
  if (segs.isEmpty || !_inAppPrefixes.contains(segs.first)) return null;
  final path = '/${segs.join('/')}${uri.hasQuery ? '?${uri.query}' : ''}';
  return notificationDeepLink(path);
}
