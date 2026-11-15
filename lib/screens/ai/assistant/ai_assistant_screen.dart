import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/ai_assistant.dart';
import '../../../core/ai_commands.dart';
import '../../../core/app_config.dart';
import '../../../core/i18n.dart';
import '../../../core/isaac_states.dart';
import '../../../core/navigation/app_routes.dart';
import '../../../core/navigation/notification_deep_link.dart';
import '../../../core/nx_breakpoint.dart';
import '../../../core/nx_network.dart';
import '../../../services/nx_speech.dart';
import '../../../widgets/app_bottom_sheet.dart';
import '../../../widgets/isaac_sticker.dart';
import '../../../widgets/nx_attachments.dart';
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_skeleton.dart';
import '../../../widgets/nx_split_view.dart' show NxHingeSplit;
import '../../search/search_modules.dart';
import '../web_session_screen.dart';
import 'ai_assistant_controller.dart';
import 'ai_cards.dart';
import 'ai_project_screen.dart';
import 'ai_prompt_library_screen.dart';
import 'widgets/ai_chat_drawer.dart';
import 'widgets/ai_composer.dart';
import 'widgets/ai_header.dart';
import 'widgets/ai_message_tile.dart';
import 'widgets/ai_mode_sheet.dart';
import 'widgets/ai_sheets.dart';
import 'widgets/ai_style.dart';
import 'widgets/ai_welcome.dart';

/// ISAAC AI Assistant (web `/ai`), redesigned for phones: a calm chat with
/// three header controls, quick starters, `/` commands, `@` records, answer
/// modes, folders and smooth streaming.
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, this.controller, this.contextModule, this.contextId, this.contextTitle, this.initialPrompt});

  /// For tests.
  final AiAssistantController? controller;

  /// "ถาม Isaac" from a record: the chat is about this record.
  final String? contextModule;
  final String? contextId;
  final String? contextTitle;

  /// Text put in the input on open (e.g. Home brief → "ถามต่อ").
  final String? initialPrompt;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  late final AiAssistantController _c = widget.controller ?? AiAssistantController(context.read<AppConfig>().apiClient);
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  DateTime? _finishedAt;
  bool _wasSending = false;

  /// Follow new text only while the user is at the bottom.
  bool _pinned = true;
  bool _showJump = false;

  /// `/` and `@` being typed (null = not).
  String? _slash;
  String? _mention;

  /// A `/วิเคราะห์` command: the next message goes in "คิดลึก".
  bool _deepNext = false;

  /// Voice input: listening, and the text typed before speaking started.
  bool _listening = false;
  String _speechBase = '';

  /// First-run hint "ลองพิมพ์ / …" (once per device).
  bool _showSlashHint = false;
  static const _kHintSeen = 'ai.slash_hint_seen';

  /// Drafts per chat (kept while switching chats / leaving the screen).
  String? _draftKeyFor;
  Timer? _draftSave;

  /// Boards for workspace tree proposals (loaded once) and the pick per proposal.
  List<Map<String, dynamic>>? _boards;
  bool _boardsLoading = false;
  final Map<String, String?> _boardFor = {};

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
            if (mounted) setState(() => _boards = list);
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
    _c.streamTick.addListener(_follow);
    _focus.addListener(() => setState(() {}));
    _input.addListener(_onInput);
    _scroll.addListener(_onScroll);
    NxNetwork.instance.ensureStarted();
    if (widget.contextModule != null && widget.contextId != null) {
      _c.contextModule = widget.contextModule;
      _c.contextId = widget.contextId;
      _c.contextTitle = widget.contextTitle;
      _input.text = tr('สรุปรายการนี้ให้หน่อย และควรทำอะไรต่อ');
    } else if ((widget.initialPrompt ?? '').trim().isNotEmpty) {
      final t = widget.initialPrompt!.trim();
      _input.value = TextEditingValue(text: t, selection: aiTemplateSelection(t));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_c.init());
      if (mounted) IsaacSticker.preload(context);
      await _loadPrefs();
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final seen = p.getBool(_kHintSeen) ?? false;
      if (_input.text.isEmpty) {
        final draft = p.getString(_draftKey(null));
        if (draft != null && draft.isNotEmpty) _input.text = draft;
      }
      _draftKeyFor = _draftKey(_c.activeId);
      if (mounted) setState(() => _showSlashHint = !seen);
    } catch (_) {}
  }

  Future<void> _markHintSeen() async {
    if (!_showSlashHint) return;
    setState(() => _showSlashHint = false);
    try {
      (await SharedPreferences.getInstance()).setBool(_kHintSeen, true);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_listening) NxSpeech.instance.stop();
    _draftSave?.cancel();
    _c.removeListener(_onChange);
    _c.streamTick.removeListener(_follow);
    if (widget.controller == null) _c.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── state hooks

  void _onChange() {
    if (!_c.sending && _wasSending) {
      _finishedAt = DateTime.now();
      Future.delayed(const Duration(milliseconds: kIsaacDoneMs + 100), () {
        if (mounted) setState(() {});
      });
    }
    _wasSending = _c.sending;
    final key = _draftKey(_c.activeId);
    if (_draftKeyFor != null && key != _draftKeyFor) _switchDraft(key);
    if (mounted) setState(() {});
    _follow();
  }

  void _onInput() {
    final sel = _input.selection;
    final cursor = sel.isValid ? sel.baseOffset : _input.text.length;
    final slash = aiSlashQuery(_input.text, cursor);
    final mention = slash == null ? aiMentionQuery(_input.text, cursor) : null;
    if (slash != null) _markHintSeen();
    setState(() {
      _slash = slash;
      _mention = mention;
    });
    _draftSave?.cancel();
    _draftSave = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  String _draftKey(String? chatId) => 'ai.draft.${chatId ?? 'new'}';

  Future<void> _saveDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final k = _draftKeyFor ?? _draftKey(_c.activeId);
      if (_input.text.trim().isEmpty) {
        await p.remove(k);
      } else {
        await p.setString(k, _input.text);
      }
    } catch (_) {}
  }

  Future<void> _switchDraft(String key) async {
    // A brand-new chat just got its id: the text was sent, nothing to carry.
    final fromNew = _draftKeyFor == _draftKey(null);
    _draftKeyFor = key;
    if (fromNew && _c.messages.isNotEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final d = p.getString(key) ?? '';
      if (mounted && _input.text != d) _input.text = d;
    } catch (_) {}
  }

  bool get _nearBottom => _scroll.hasClients && _scroll.position.maxScrollExtent - _scroll.offset < 80;

  /// Any scroll: back at the bottom (not dragging up) → follow again;
  /// away from it while not following → show "↓".
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final near = _nearBottom;
    final up = _scroll.position.userScrollDirection == ScrollDirection.forward;
    if (near && !up && (!_pinned || _showJump)) {
      setState(() {
        _pinned = true;
        _showJump = false;
      });
    } else if (!near && !_pinned && !_showJump) {
      setState(() => _showJump = true);
    }
  }

  /// Only the user's own drag up stops following (our jumps do not).
  bool _onUserScroll(UserScrollNotification n) {
    if (n.direction == ScrollDirection.forward && _pinned) setState(() => _pinned = false);
    return false;
  }

  /// Keep the newest text in view — only while the user has not scrolled up.
  void _follow([int tries = 10]) {
    if (!_pinned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !_pinned) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.offset < max - 0.5) {
        _scroll.jumpTo(max);
        // The lazy list measures the items it just built and may grow:
        // check again next frame until it settles.
        if (tries > 1) {
          _follow(tries - 1);
          WidgetsBinding.instance.scheduleFrame();
        }
      }
    });
  }

  void _jumpToEnd() {
    if (!_scroll.hasClients) return;
    setState(() {
      _pinned = true;
      _showJump = false;
    });
    _scroll.animateTo(_scroll.position.maxScrollExtent, duration: AiStyle.of(context, const Duration(milliseconds: 300)), curve: AiStyle.curve);
  }

  // ── sending

  Future<void> _send([String? text]) async {
    final t = text ?? _input.text;
    final deep = _deepNext;
    if (text == null) _input.clear();
    _deepNext = false;
    _pinned = true;
    HapticFeedback.lightImpact();
    unawaited(_markHintSeen());
    await _c.send(t, deep: deep);
  }

  void _insertTemplate(String template) {
    _input.value = TextEditingValue(text: template, selection: aiTemplateSelection(template));
    _focus.requestFocus();
  }

  void _pickCommand(AiCommand c) {
    HapticFeedback.selectionClick();
    setState(() => _deepNext = c.deep);
    _insertTemplate(tr(c.template));
  }

  void _pickMention(AiMention m) {
    final sel = _input.selection;
    final r = aiStripMention(_input.text, sel.isValid ? sel.baseOffset : _input.text.length);
    _input.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.cursor),
    );
    _c.setContext(m.module, m.id, m.title);
    HapticFeedback.selectionClick();
  }

  void _openLink(String href) {
    if (handleInAppWebLink(context, href)) return;
    openNxFile(href.startsWith('/') ? _c.api.absoluteUrl(href) : href);
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr(text)), action: action, persist: action == null ? null : false));
  }

  // ── attachments, mode, quick actions

  Future<void> _attachMenu() async {
    final picked = await showAiAttachSheet(context, canAttach: !_c.uploading);
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'mention':
        _insertAtCursor('@');
        return;
      case 'commands':
        _input.value = const TextEditingValue(text: '/', selection: TextSelection.collapsed(offset: 1));
        _focus.requestFocus();
        return;
      case 'file':
        final r = await FilePicker.platform.pickFiles(
          withData: true,
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'txt', 'doc', 'docx', 'json', 'csv', 'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'webp', 'mp3', 'm4a', 'wav', 'mp4', 'mov'],
        );
        final files = [
          for (final f in r?.files ?? const <PlatformFile>[])
            if (f.bytes != null) MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ];
        if (files.isNotEmpty) await _c.uploadAttachments(files.take(8).toList());
        return;
      case 'gallery':
        final xs = await ImagePicker().pickMultiImage(maxWidth: 2200, imageQuality: 85, limit: 8);
        if (xs.isEmpty) return;
        await _c.uploadAttachments([for (final x in xs) MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name)]);
        return;
      case 'camera':
        final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, imageQuality: 85);
        if (x == null) return;
        await _c.uploadAttachment(MultipartFile.fromBytes(await x.readAsBytes(), filename: x.name));
    }
  }

  void _insertAtCursor(String s) {
    final sel = _input.selection;
    final at = sel.isValid ? sel.baseOffset : _input.text.length;
    final before = _input.text.substring(0, at);
    final pad = before.isEmpty || before.endsWith(' ') || before.endsWith('\n') ? '' : ' ';
    final text = '$before$pad$s${_input.text.substring(at)}';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + pad.length + s.length),
    );
    _focus.requestFocus();
  }

  Future<void> _pickMode() async {
    await showAppBottomSheet<void>(
      context: context,
      title: null,
      child: AiModeSheet(controller: _c),
    );
    if (mounted) setState(() => _deepNext = false);
  }

  Future<void> _quickAction(AiQuickAction a) async {
    HapticFeedback.selectionClick();
    if (a.template != null) return _insertTemplate(tr(a.template!));
    if (a.key == 'create') {
      final t = await showAiCreatePicker(context);
      if (t != null && mounted) _insertTemplate(tr(t));
    }
  }

  // ── chat menu

  AiConversation _activeChat() => _c.conversations.firstWhere(
    (x) => x.id == _c.activeId,
    orElse: () => AiConversation(id: _c.activeId!, title: _c.activeTitle, starred: _c.activeStarred, projectId: _c.activeProjectId),
  );

  Future<void> _chatMenu(AiConversation chat) async {
    final action = await showAiChatMenu(context, chat, canShare: true);
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'pin':
          await _c.toggleStar(chat.id, !chat.starred);
        case 'rename':
          final v = await showAiTextDialog(context, title: 'เปลี่ยนชื่อแชท', initial: chat.title);
          if (v != null) await _c.rename(chat.id, v);
        case 'move':
          await _moveToFolder({chat.id}, current: chat.projectId);
        case 'share':
          await _share(chat.id, chat.title);
        case 'archive':
          await _c.setArchived(chat.id, !chat.archived);
          if (mounted && !chat.archived) {
            _snack(
              'เก็บ "${chat.title}" ถาวรแล้ว',
              action: SnackBarAction(label: tr('เลิกทำ'), onPressed: () => _c.setArchived(chat.id, false)),
            );
          }
        case 'delete':
          await _delete(chat);
      }
    } catch (e) {
      if (mounted) _snack(aiErrorText(e));
    }
  }

  /// Delete with undo (5s): hidden now, removed on the server only when the
  /// snackbar closes without "เลิกทำ".
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

  Future<void> _moveToFolder(Set<String> chatIds, {String? current}) async {
    var picked = await showAiFolderPicker(context, _c.folders, current: current);
    if (picked == null || !mounted) return;
    if (picked == '__new__') {
      final f = await _createFolder();
      if (f == null) return;
      picked = f.id;
    }
    final target = picked.isEmpty ? null : picked;
    if (chatIds.length == 1) {
      await _c.moveToProject(chatIds.first, target);
    } else {
      await _c.moveManyToProject(chatIds, target);
    }
    if (mounted) {
      final name = _c.folderById(target)?.name;
      _snack(name == null ? 'นำออกจากโฟลเดอร์แล้ว' : 'ย้ายไป "$name" แล้ว');
    }
  }

  Future<AiFolder?> _createFolder() async {
    final r = await showAiFolderEditor(context);
    if (r == null) return null;
    try {
      return await _c.createFolder(name: r.name, color: r.color, instructions: r.instructions);
    } catch (e) {
      if (mounted) _snack(aiErrorText(e));
      return null;
    }
  }

  Future<void> _folderMenu(AiFolder f, {bool showOpen = true}) async {
    final action = await showAiFolderMenu(context, f, showOpen: showOpen);
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'open':
          await _openFolder(f);
        case 'edit':
          final r = await showAiFolderEditor(context, folder: f);
          if (r != null) await _c.updateFolder(f.id, name: r.name, color: r.color, instructions: r.instructions);
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('ลบโฟลเดอร์ "${f.name}"?')),
              content: Text(tr('แชทในโฟลเดอร์จะยังอยู่ ย้ายออกมาไว้นอกโฟลเดอร์')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ลบ'))),
              ],
            ),
          );
          if (ok == true) await _c.deleteFolder(f.id);
      }
    } catch (e) {
      if (mounted) _snack(aiErrorText(e));
    }
  }

  Future<void> _openFolder(AiFolder f) async {
    _closeDrawer();
    final r = await Navigator.of(context).push<AiFolderResult>(
      MaterialPageRoute(
        builder: (_) => AiProjectScreen(controller: _c, folderId: f.id, onEdit: () => _folderMenu(f, showOpen: false)),
      ),
    );
    if (r == null || !mounted) return;
    if (r.newChat) {
      _c.newChat(inFolder: f.id);
      _focus.requestFocus();
    } else if (r.chatId != null) {
      await _c.open(r.chatId!);
    }
  }

  Future<void> _openPrompts() async {
    _closeDrawer();
    final cmd = await Navigator.of(context).push<AiCommand>(MaterialPageRoute(builder: (_) => AiPromptLibraryScreen(controller: _c)));
    if (cmd != null && mounted) _pickCommand(cmd);
  }

  Future<void> _share(String id, String title) async {
    final mode = await showAiShareSheet(context);
    if (mode == null || !mounted) return;
    try {
      final r = await _c.api.createAiShare(id, accessMode: mode);
      if (!mounted) return;
      final url = aiShareUrl(WebSessionScreen.webOrigin(context.read<AppConfig>().apiBaseUrl), r);
      if (url.isNotEmpty) await Share.share('$title\n$url');
    } catch (e) {
      if (mounted) _snack(aiErrorText(e));
    }
  }

  void _closeDrawer() {
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  // ── message actions

  Future<void> _messageActions(AiMessage m) async {
    HapticFeedback.mediumImpact();
    final isLastReply = !m.isUser && identical(m, _c.messages.lastOrNull);
    final action = await showAiMessageActions(context, isUser: m.isUser, canRegenerate: isLastReply && !_c.sending, canEdit: !_c.sending);
    if (action == null || !mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.content));
        if (mounted) _snack('คัดลอกแล้ว');
      case 'select':
        await showAppBottomSheet<void>(
          context: context,
          title: 'เลือกข้อความ',
          child: SelectableText(m.content, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55)),
        );
      case 'share':
        await Share.share(m.content);
      case 'edit':
        final v = await showAiTextDialog(context, title: 'แก้ไขข้อความ', initial: m.content, action: 'ส่งใหม่', multiline: true);
        if (v != null && v.trim().isNotEmpty) {
          _pinned = true;
          await _c.editAndResend(m, v);
        }
      case 'save':
        final r = await showAiCommandEditor(context, prompt: m.content);
        if (r != null) {
          try {
            await _c.saveMyCommand(command: r.command, title: r.title, prompt: r.prompt);
            if (mounted) _snack('บันทึกเป็นคำสั่ง /${r.command} แล้ว');
          } catch (e) {
            if (mounted) _snack(aiErrorText(e));
          }
        }
      case 'regenerate':
        await _c.regenerate();
    }
  }

  // ── build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bp = NxBreakpoint.of(context);
    final docked = bp.twoPane;
    final empty = _c.messages.isEmpty && !_c.chatLoading;
    final activeFolder = _c.folderById(_c.activeId == null ? _c.pendingProjectId : _c.activeProjectId);
    final cramped = MediaQuery.viewInsetsOf(context).bottom > 0 && MediaQuery.sizeOf(context).height < 700;
    final name = context.read<AppConfig>().session.displayName ?? '';

    final chat = SafeArea(
      bottom: false,
      child: Column(
        children: [
          AiHeader(
            title: _c.activeId == null ? (activeFolder != null ? tr('แชทใหม่') : tr('ไอแซค')) : (_c.activeTitle.isEmpty ? tr('แชทใหม่') : _c.activeTitle),
            subtitle: activeFolder?.name,
            folderColor: activeFolder == null ? null : AiStyle.folderColor(context, activeFolder.color),
            showHistoryButton: !docked,
            onHistory: () {
              _c.loadConversations();
              _scaffold.currentState?.openDrawer();
            },
            onNewChat: () {
              HapticFeedback.selectionClick();
              _c.newChat();
            },
            onTitle: _c.activeId == null ? null : () => _chatMenu(_activeChat()),
          ),
          if (_c.quotaExhausted) _Banner(color: cs.error, icon: NxI.warningCircle, text: 'โควตา AI เดือนนี้หมดแล้ว — ติดต่อผู้ดูแลเพื่อเพิ่มแพ็กเกจ'),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _c.chatLoading
                      ? const NxSkeletonChat()
                      : empty
                      ? _centered(
                          AiWelcome(
                            name: name,
                            onAction: _quickAction,
                            suggestions: _c.suggestedPrompts,
                            onSuggestion: _send,
                            recents: _c.recentChats,
                            folderOf: _c.folderById,
                            onOpenChat: _c.open,
                            contextTitle: _c.contextModule != null ? (_c.contextTitle ?? '${_c.contextModule} #${_c.contextId}') : null,
                            folderName: _c.activeId == null ? activeFolder?.name : null,
                            showSlashHint: _showSlashHint,
                          ),
                        )
                      : _messageList(context),
                ),
                if (_showJump && !empty)
                  Positioned(
                    right: 16,
                    bottom: 8,
                    child: _JumpButton(onTap: _jumpToEnd, live: _c.sending),
                  ),
              ],
            ),
          ),
          if (_c.error != null)
            _Banner(
              key: const ValueKey('ai-error'),
              color: cs.error,
              icon: NxI.warningCircle,
              text: _c.error!,
              action: _c.messages.any((m) => m.isUser) ? 'ลองใหม่' : null,
              onAction: _c.retry,
              onClose: _c.clearError,
            ),
          if (_c.followUps.isNotEmpty && !_c.sending && !cramped && _slash == null && _mention == null) _followUps(context),
          if (!cramped) _usageStrip(context),
          _centered(
            AiComposer(
              input: _input,
              focus: _focus,
              locked: _c.quotaExhausted,
              sending: _c.sending,
              uploading: _c.uploading,
              uploadProgress: _c.uploadProgress,
              attachments: _c.pendingAttachments,
              onRemoveAttachment: _c.removeAttachment,
              modeLabel: _deepNext ? 'คิดลึก (ครั้งนี้)' : _c.modeLabel,
              modeIcon: _deepNext ? AiStyle.modeIcon('deep') : (_c.provider == 'auto' ? AiStyle.modeIcon(_c.autoMode) : NxI.sparkle),
              onMode: _pickMode,
              onAttach: _attachMenu,
              listening: _listening,
              onMic: _toggleMic,
              onSend: () => _send(),
              onStop: _c.stop,
              contextTitle: _c.contextModule == null ? null : (_c.contextTitle ?? '${_c.contextModule} #${_c.contextId}'),
              onClearContext: _c.clearContext,
              compact: MediaQuery.sizeOf(context).height < 520,
              panel: _panel(),
            ),
          ),
        ],
      ),
    );

    final drawer = AiChatDrawer(
      controller: _c,
      docked: docked,
      onNewChat: () {
        _closeDrawer();
        _c.newChat();
      },
      onOpenChat: (id) {
        _closeDrawer();
        _c.open(id);
      },
      onChatMenu: _chatMenu,
      onOpenFolder: _openFolder,
      onFolderMenu: _folderMenu,
      onCreateFolder: _createFolder,
      onMoveMany: (ids) => _moveToFolder(ids),
      onAgent: () {
        _closeDrawer();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const WebSessionScreen(path: '/ai/agent', title: 'AI Agent', subtitle: 'ไอแซคเอไอ'),
          ),
        );
      },
      onNotebook: () {
        _closeDrawer();
        context.push(AppRoutes.notebook);
      },
      onPrompts: _openPrompts,
    );

    if (!docked) {
      return Scaffold(
        key: _scaffold,
        backgroundColor: AiStyle.canvas(context),
        drawer: Drawer(
          backgroundColor: AiStyle.canvas(context),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(AiStyle.sheetRadius))),
          child: SafeArea(child: drawer),
        ),
        body: chat,
      );
    }
    // Tablet / opened foldable: history stays on the left.
    final sidebar = Material(
      key: const ValueKey('ai-chat-sidebar'),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      child: SafeArea(right: false, child: drawer),
    );
    return Scaffold(
      key: _scaffold,
      backgroundColor: AiStyle.canvas(context),
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

  /// Keeps the chat readable on wide screens.
  Widget _centered(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AiStyle.maxContentWidth),
      child: child,
    ),
  );

  Widget? _panel() {
    if (_slash != null) {
      return AiSlashMenu(commands: aiFilterCommands(_c.allCommands, _slash!), onPick: _pickCommand, onManage: _openPrompts);
    }
    if (_mention != null) {
      return AiMentionPicker(api: _c.api, query: _mention!, modules: _mentionModules(), onPick: _pickMention);
    }
    return null;
  }

  List<String> _mentionModules() {
    const preferred = ['account', 'contact', 'lead', 'deal'];
    try {
      final allowed = globalSearchModulesFor(context.read<AppConfig>().session);
      final list = preferred.where(allowed.contains).toList();
      return list.isEmpty ? allowed.take(4).toList() : list;
    } catch (_) {
      return preferred;
    }
  }

  Widget _messageList(BuildContext context) {
    final msgs = _c.messages;
    return NotificationListener<ScrollMetricsNotification>(
      // Content grew (an answer laid out, an image loaded): stay at the end.
      onNotification: (_) {
        if (_pinned) _follow();
        return false;
      },
      child: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: ListView.builder(
          key: const ValueKey('ai-messages'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(AiStyle.gutter, 4, AiStyle.gutter, 16),
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final m = msgs[i];
            final last = i == msgs.length - 1;
            final day = m.createdLocal;
            final prevDay = i == 0 ? null : msgs[i - 1].createdLocal;
            final newDay = day != null && (prevDay == null || prevDay.year != day.year || prevDay.month != day.month || prevDay.day != day.day);
            final tile = m.isUser ? AiUserBubble(message: m, onLongPress: () => _messageActions(m)) : _reply(context, m, last: last);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AiStyle.maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (newDay && msgs.length > 1) AiDaySeparator(day: day),
                    _FadeIn(key: ValueKey('fade-${m.hashCode}'), animate: last, child: tile),
                  ],
                ),
              ),
            );
          },
        ),
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

  Widget _reply(BuildContext context, AiMessage m, {required bool last}) {
    final extras = <Widget>[
      for (final p in m.proposals)
        AiProposalCard(
          proposal: p,
          state: _c.proposalState['${p['proposalId']}'],
          boards: aiIsWorkspaceTree(p) ? _writableBoards() : null,
          boardId: _boardOf(p),
          onBoard: (v) => setState(() => _boardFor['${p['proposalId']}'] = v),
          onOpen: _c.proposalLinks['${p['proposalId']}'] == null ? null : () => _openLink(_c.proposalLinks['${p['proposalId']}']!),
          onConfirm: () async {
            final board = _boardOf(p);
            if (aiNeedsBoard(p) && (board == null || board.isEmpty)) {
              _snack('เลือกบอร์ดก่อนยืนยัน');
              return;
            }
            HapticFeedback.mediumImpact();
            final link = await _c.confirmProposal(p, boardId: aiIsWorkspaceTree(p) ? board : null);
            if (link != null && link.isNotEmpty && mounted) {
              _snack(
                'ทำรายการแล้ว',
                action: SnackBarAction(label: tr('เปิด'), onPressed: () => _openLink(link)),
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
    ];
    return AiAssistantTile(
      message: m,
      isLast: last,
      sending: _c.sending,
      mood: _mood(m: m, last: last),
      streamTick: _c.streamTick,
      statusLabel: aiStatusLabel(_c.status),
      routeSteps: _c.routeSteps,
      sendStartedAt: _c.sendStartedAt,
      onOpenLink: _openLink,
      onLongPress: () => _messageActions(m),
      extras: extras,
      actions: last && !m.streaming && m.content.trim().isNotEmpty
          ? AiReplyActions(
              onCopy: () {
                Clipboard.setData(ClipboardData(text: m.content));
                HapticFeedback.selectionClick();
                _snack('คัดลอกแล้ว');
              },
              onRegenerate: _c.sending ? null : _c.regenerate,
              onShare: () => Share.share(m.content),
              onMore: () => _messageActions(m),
            )
          : null,
    );
  }

  Widget _followUps(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: ListView(
        key: const ValueKey('ai-followups'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AiStyle.gutter, vertical: 4),
        children: [
          for (final f in _c.followUps)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(NxI.sparkle, size: 14, color: cs.primary),
                label: Text('${f['label'] ?? f['prompt'] ?? ''}'),
                shape: const StadiumBorder(),
                side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                backgroundColor: AiStyle.surface(context),
                onPressed: () => _send('${f['prompt'] ?? f['label'] ?? ''}'),
              ),
            ),
        ],
      ),
    );
  }

  /// Quota meter (cloud-metered plans only) + "switch model" choices when the
  /// month or this model's day runs out (web `AiUsageStrip`).
  Widget _usageStrip(BuildContext context) {
    final u = _c.usageView;
    if (u == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = u.exhausted ? cs.error : (u.low ? AiStyle.warn(context) : cs.primary);
    return Padding(
      key: const ValueKey('ai-usage'),
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: u.usedFraction, minHeight: 3, color: color, backgroundColor: cs.surfaceContainerHighest),
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
      _snack('ใช้ไมค์ไม่ได้ — ตรวจสิทธิ์ไมโครโฟนในการตั้งค่าเครื่อง');
      return;
    }
    setState(() => _listening = true);
  }
}

/// "↓" back to the newest message (pulses while a reply is streaming).
class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.onTap, required this.live});
  final VoidCallback onTap;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('ai-jump-bottom'),
      color: AiStyle.surface(context),
      shape: const StadiumBorder(),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AiIcons.toBottom, size: 16, color: cs.primary),
              if (live) ...[
                const SizedBox(width: 6),
                Text(
                  tr('ข้อความใหม่'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// New messages fade in and rise 8px (off with reduced motion).
class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child, required this.animate});
  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final d = AiStyle.of(context, const Duration(milliseconds: 260));
    if (!animate || d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: AiStyle.curve,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: c),
      ),
      child: child,
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
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr(text), style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(tr(action!))),
          if (onClose != null) IconButton(tooltip: tr('ปิด'), visualDensity: VisualDensity.compact, icon: const Icon(NxI.x, size: 16), onPressed: onClose),
        ],
      ),
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
  if (segs.length >= 2 && segs[0] == 'ai' && segs[1] == 'notebook' && (segs.length == 2 || segs[2] != 'public')) {
    return segs.length == 2 ? AppRoutes.notebook : AppRoutes.notebookOf(segs[2]);
  }
  if (segs.isEmpty || !_inAppPrefixes.contains(segs.first)) return null;
  final path = '/${segs.join('/')}${uri.hasQuery ? '?${uri.query}' : ''}';
  return notificationDeepLink(path);
}
