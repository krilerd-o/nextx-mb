import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/chat_format.dart';
import '../../core/chat_merge.dart';
import '../../core/entity_display.dart';
import '../../core/error_reporting.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import 'room/chat_call_hooks.dart';
import 'room/chat_composer.dart';
import 'room/chat_message_actions.dart';
import '../comm_ai/call_summary_bubble.dart';
import '../comm_ai/chat_summary_sheet.dart';
import 'room/chat_message_bubble.dart';
import 'room/chat_room_info_screen.dart';

/// A chat room (or one thread when [threadRoot] is set): Slack/LINE-like bubbles for every message type,
/// long press actions, swipe to reply, rich composer, calls from the header.
class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.room, this.embedded = false, this.threadRoot, this.focusMessageId});
  final Map<String, dynamic> room;
  final bool embedded;
  final Map<String, dynamic>? threadRoot;
  final String? focusMessageId;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _pins = [];
  List<Map<String, dynamic>> _members = [];
  Map<String, List<String>> _readers = {};
  final Map<String, String> _typing = {};
  final Map<String, Timer> _typingExpiry = {};
  StreamSubscription<RealtimeEvent>? _sub;
  Timer? _typingDebounce;
  bool _iAmTyping = false;
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  bool _sending = false;
  Map<String, dynamic>? _editing;
  Map<String, dynamic>? _replyTo;
  String? _highlight;
  late Map<String, dynamic> _room = {...widget.room};

  String get _id => strId(widget.room['id']);
  String? get _me => context.read<AppConfig>().session.userId;
  ApiClient get _api => context.read<AppConfig>().apiClient;
  bool get _isThread => widget.threadRoot != null;
  String? get _threadId => widget.threadRoot?['id']?.toString();

  @override
  void initState() {
    super.initState();
    if (!_isThread) RealtimeService.instance.joinChatRoom(_id);
    _sub = RealtimeService.instance.events.listen(_onEvent);
    _scroll.addListener(_onScroll);
    _controller.addListener(_onTextChanged);
    _load();
    _api.getChatRoomMembers(_id).then((m) {
      if (mounted) setState(() => _members = m);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingDebounce?.cancel();
    for (final t in _typingExpiry.values) {
      t.cancel();
    }
    if (_iAmTyping) RealtimeService.instance.typing(_id, active: false);
    if (!_isThread) RealtimeService.instance.leaveChatRoom(_id);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _belongsHere(Map<String, dynamic> m) {
    final root = m['thread_root_id']?.toString();
    if (_isThread) return root == _threadId || '${m['id']}' == _threadId;
    return root == null || root.isEmpty || root == 'null';
  }

  // ---- realtime -----------------------------------------------------------

  void _onEvent(RealtimeEvent e) {
    if (!mounted) return;
    final forRoom = e.roomId == null || e.roomId == _id;
    switch (e.type) {
      case 'new_message':
        if (e.roomId != _id) return;
        if (!_belongsHere(e.data)) {
          // a reply in a thread → bump the root's reply count
          final root = e.data['thread_root_id']?.toString();
          if (!_isThread && root != null) {
            setState(() => _messages = [
                  for (final m in _messages)
                    '${m['id']}' == root ? {...m, 'thread_reply_count': (int.tryParse('${m['thread_reply_count'] ?? 0}') ?? 0) + 1} : m,
                ]);
          }
          return;
        }
        final nearBottom = _isNearBottom();
        setState(() => _messages = upsertChatMessage(_messages, fillChatSender(e.data, _messages)));
        final id = e.data['id']?.toString();
        if (id != null && !_isThread) _markRead(id);
        if (nearBottom || isOwnChatMessage(e.data, _me)) _scrollToBottom();
      case 'message_edited':
        if (!forRoom) return;
        setState(() => _messages = upsertChatMessage(_messages, e.data));
      case 'message_deleted':
        if (!forRoom) return;
        final id = e.data['id']?.toString() ?? e.data['message_id']?.toString();
        setState(() => _messages = [for (final m in _messages) '${m['id']}' == id ? {...m, 'deleted_at': DateTime.now().toIso8601String(), 'body': ''} : m]);
      case 'message_reaction':
        if (e.roomId == _id) _refreshLatest();
      case 'user_typing':
        final uid = e.data['user_id']?.toString();
        if (uid == null || uid == _me) return;
        _typingExpiry[uid]?.cancel();
        _typingExpiry[uid] = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _typing.remove(uid));
        });
        setState(() => _typing[uid] = e.data['display_name']?.toString() ?? 'มีคน');
      case 'read_receipt':
        final uid = e.data['user_id']?.toString();
        final mid = e.data['message_id']?.toString();
        if (uid == null || mid == null) return;
        setState(() => _readers = applyReadReceipt(_readers, _messages, uid, mid));
      case 'user_stopped_typing':
        final uid = e.data['user_id']?.toString();
        if (uid != null && _typing.containsKey(uid)) setState(() => _typing.remove(uid));
    }
  }

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has && !_iAmTyping) {
      _iAmTyping = true;
      RealtimeService.instance.typing(_id, active: true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      if (_iAmTyping) {
        _iAmTyping = false;
        RealtimeService.instance.typing(_id, active: false);
      }
    });
  }

  // ---- loading ------------------------------------------------------------

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.maxScrollExtent - _scroll.offset < 160;
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _onScroll() {
    if (_isThread) return;
    if (_scroll.hasClients && _scroll.offset < 80 && !_loadingOlder && _hasOlder && !_loading) _loadOlder();
  }

  void _markRead(String messageId) {
    RealtimeService.instance.markRead(_id, messageId);
    _api.markChatRead(_id, messageId).catchError((Object e) => debugPrint('[chat] mark read: $e'));
  }

  Future<void> _load() async {
    try {
      if (_isThread) {
        final list = await _api.getChatThread(_id, _threadId!);
        if (!mounted) return;
        setState(() {
          _messages = list;
          _loading = false;
          _hasOlder = false;
        });
        _scrollToBottom(jump: true);
        return;
      }
      final page = await _api.getChatMessagesPage(_id, limit: 50);
      final list = page.items;
      if (!mounted) return;
      setState(() {
        _messages = list;
        _readers = page.readers;
        _loading = false;
        _hasOlder = list.length >= 50;
      });
      final lastId = list.isEmpty ? null : list.last['id']?.toString();
      if (lastId != null) _markRead(lastId);
      if (widget.focusMessageId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(widget.focusMessageId!));
      } else {
        _scrollToBottom(jump: true);
      }
      _loadPins();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(formatApiError(e));
    }
  }

  Future<void> _loadPins() async {
    try {
      final pins = await _api.getChatPins(_id);
      if (mounted) setState(() => _pins = pins);
    } catch (_) {
      // Pins need the Mongo chat store; older servers do not have them.
    }
  }

  bool _isPinned(Map<String, dynamic> m) => _pins.any((p) => p['message_id']?.toString() == m['id']?.toString());

  Future<void> _refreshLatest() async {
    try {
      final list = _isThread ? await _api.getChatThread(_id, _threadId!) : (await _api.getChatMessagesPage(_id, limit: 50)).items;
      if (!mounted) return;
      var merged = _messages;
      for (final m in list) {
        merged = upsertChatMessage(merged, m);
      }
      setState(() => _messages = merged);
    } catch (e, s) {
      ErrorReporting.report(e, s);
    }
  }

  Future<void> _loadOlder() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final before = _messages.first['created_at']?.toString();
    final oldExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    try {
      final list = await _api.getChatMessages(_id, limit: 50, before: before);
      if (!mounted) return;
      var merged = _messages;
      for (final m in list) {
        merged = upsertChatMessage(merged, m);
      }
      setState(() {
        _messages = merged;
        _hasOlder = list.length >= 50;
        _loadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset + (_scroll.position.maxScrollExtent - oldExtent));
      });
    } catch (e) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr(text)), duration: const Duration(seconds: 2)));
  }

  Future<void> _jumpTo(String id) async {
    final key = _keys[id];
    if (key?.currentContext == null) {
      _snack('ข้อความนี้อยู่ก่อนหน้า — เลื่อนขึ้นเพื่อดู');
      return;
    }
    await Scrollable.ensureVisible(key!.currentContext!, alignment: 0.4, duration: const Duration(milliseconds: 300));
    setState(() => _highlight = id);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _highlight == id) setState(() => _highlight = null);
    });
  }

  // ---- send ---------------------------------------------------------------

  Future<void> _send(String text, Map<String, String> mentions, {List<Map<String, dynamic>>? attachments}) async {
    if (text.trim().isEmpty && (attachments == null || attachments.isEmpty)) return;
    setState(() => _sending = true);
    try {
      final editing = _editing;
      if (editing != null) {
        final updated = await _api.editChatMessage(_id, '${editing['id']}', text);
        if (!mounted) return;
        setState(() {
          _messages = upsertChatMessage(_messages, {...editing, ...updated, 'body': text, 'edited_at': updated['edited_at'] ?? DateTime.now().toIso8601String()});
          _editing = null;
        });
      } else {
        final enc = chatEncodeMentions(text, mentions);
        final reply = _replyTo;
        final sent = await _api.postChatMessage(
          _id,
          enc.body,
          attachments: attachments,
          replyToId: reply?['id']?.toString(),
          threadRootId: _threadId,
          mentionIds: enc.ids,
        );
        if (!mounted) return;
        if (sent['id'] != null) {
          final withReply = reply == null ? sent : {...sent, 'reply_to': sent['reply_to'] ?? {...reply, 'sender_name': chatSenderName(reply)}};
          setState(() => _messages = upsertChatMessage(_messages, fillChatSender({'user_id': _me, ...withReply}, _messages)));
        }
        setState(() => _replyTo = null);
        _scrollToBottom();
      }
      _controller.clear();
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFiles(List<ChatPickedFile> files, {String text = ''}) async {
    setState(() => _sending = true);
    final uploaded = <Map<String, dynamic>>[];
    try {
      for (final f in files) {
        uploaded.add(await _api.uploadChatFile(_id, MultipartFile.fromBytes(f.bytes, filename: f.name)));
      }
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _snack(formatApiError(e));
      return;
    }
    if (mounted) setState(() => _sending = false);
    await _send(text, const {}, attachments: uploaded);
  }

  // ---- actions ------------------------------------------------------------

  Future<void> _onLongPress(Map<String, dynamic> m) async {
    if (m['deleted_at'] != null) return;
    final mine = isOwnChatMessage(m, _me);
    final text = chatPlainText(m['body']?.toString());
    final action = await showChatMessageActions(context, mine: mine, pinned: _isPinned(m), hasText: text.isNotEmpty, canThread: !_isThread);
    if (action == null || !mounted) return;
    final id = '${m['id']}';
    switch (action) {
      case ChatReact(:final emoji):
        await _react(m, emoji);
      case ChatSimpleAction(:final kind):
        switch (kind) {
          case ChatActionKind.reply:
            setState(() {
              _replyTo = m;
              _editing = null;
            });
          case ChatActionKind.thread:
            await nxPush<void>(context, ChatRoomScreen(room: _room, threadRoot: m));
            _refreshLatest();
          case ChatActionKind.copy:
            await Clipboard.setData(ClipboardData(text: text));
            _snack('คัดลอกข้อความแล้ว');
          case ChatActionKind.forward:
            final n = await showChatForwardSheet(context, fromRoomId: _id, message: m);
            if (n != null) _snack('ส่งต่อแล้ว $n ห้อง');
          case ChatActionKind.pin || ChatActionKind.unpin:
            try {
              await _api.setChatPin(_id, id, pinned: kind == ChatActionKind.pin);
              _snack(kind == ChatActionKind.pin ? 'ปักหมุดแล้ว' : 'เลิกปักหมุดแล้ว');
              await _loadPins();
            } catch (e) {
              _snack(formatApiError(e));
            }
          case ChatActionKind.save:
            try {
              await _api.saveChatMessage(_id, id);
              _snack('บันทึกไว้ดูภายหลังแล้ว');
            } catch (e) {
              _snack(formatApiError(e));
            }
          case ChatActionKind.edit:
            setState(() {
              _editing = m;
              _replyTo = null;
            });
            _controller.text = text;
            _controller.selection = TextSelection.collapsed(offset: text.length);
          case ChatActionKind.delete:
            if (!await confirmChatDelete(context)) return;
            try {
              await _api.deleteChatMessage(_id, id);
              if (mounted) {
                setState(() => _messages = [for (final x in _messages) '${x['id']}' == id ? {...x, 'deleted_at': DateTime.now().toIso8601String(), 'body': ''} : x]);
              }
            } catch (e) {
              _snack(formatApiError(e));
            }
        }
    }
  }

  Future<void> _react(Map<String, dynamic> m, String emoji) async {
    final already = chatReactions(m).any((r) => r['emoji'] == emoji && r['me'] == true);
    try {
      await _api.reactChatMessage(_id, '${m['id']}', emoji, remove: already);
      await _refreshLatest();
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _call(bool video) async {
    final start = ChatCallHooks.start;
    if (start == null) return;
    await start(context, _room, video: video);
  }

  Future<void> _showPins() async {
    final theme = Theme.of(context);
    final jump = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
          child: ListView(shrinkWrap: true, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(tr('ข้อความที่ปักหมุด (${_pins.length})'), style: theme.textTheme.titleMedium)),
            for (final p in _pins)
              ListTile(
                leading: const Icon(NxI.pushPin),
                title: Text(chatPlainText(asStringKeyedMap(p['message'])?['body']?.toString()), maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(chatSenderName(fillChatSender(asStringKeyedMap(p['message']) ?? <String, dynamic>{}, _messages))),
                onTap: () => Navigator.pop(ctx, p['message_id']?.toString()),
              ),
          ]),
        ),
      ),
    );
    if (jump != null) _jumpTo(jump);
  }

  // ---- UI -----------------------------------------------------------------

  static String _day(dynamic raw) {
    final d = parseThai(raw?.toString() ?? '');
    if (d == null) return '';
    final now = thaiNow();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'วันนี้';
    if (day == today.subtract(const Duration(days: 1))) return 'เมื่อวาน';
    return '${d.day}/${d.month}/${uiYear(d.year)}';
  }

  PreferredSizeWidget _header() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typingNames = _typing.values.toSet().toList();
    final title = _isThread ? tr('เธรด') : chatRoomTitle(_room);
    final sub = typingNames.isNotEmpty
        ? '${typingNames.join(', ')} ${tr('กำลังพิมพ์…')}'
        : !RealtimeService.instance.connected
            ? tr('ออฟไลน์ — กำลังเชื่อมต่อ')
            : _isThread
                ? chatRoomTitle(_room)
                : chatRoomIsDm(_room)
                    ? ''
                    : tr('${_members.isNotEmpty ? _members.length : (_room['member_count'] ?? '')} สมาชิก');
    return AppBar(
      automaticallyImplyLeading: !widget.embedded,
      titleSpacing: widget.embedded ? 16 : 0,
      title: InkWell(
        key: const ValueKey('chat-room-title'),
        onTap: _isThread
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChatRoomInfoScreen(room: _room, onChanged: (r) => setState(() => _room = r)),
                )),
        child: Row(children: [
          if (!_isThread) ...[NxAvatar(label: chatRoomTitle(_room), size: 36), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                if (_room['muted'] == true) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(NxI.bellSlash, size: 14, color: cs.onSurfaceVariant)),
              ]),
              if (sub.isNotEmpty)
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: typingNames.isNotEmpty ? cs.primary : cs.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
      actions: [
        if (!_isThread)
          IconButton(
            key: const ValueKey('chat-ai-summary'),
            tooltip: tr('ISAAC สรุปแชท'),
            icon: const Icon(NxI.sparkle, color: Color(0xFF7C3AED)),
            onPressed: () => showChatSummarySheet(context, roomId: _id, roomName: chatRoomTitle(_room)),
          ),
        if (!_isThread && ChatCallHooks.available) ...[
          IconButton(key: const ValueKey('chat-call-voice'), tooltip: tr('โทรด้วยเสียง'), icon: const Icon(NxI.phone), onPressed: () => _call(false)),
          IconButton(key: const ValueKey('chat-call-video'), tooltip: tr('วิดีโอคอล'), icon: const Icon(NxI.videoCamera), onPressed: () => _call(true)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final items = <Widget>[];
    String? prevDay;
    String? prevUser;
    final byId = {for (final m in _messages) '${m['id']}': m};
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final id = '${m['id']}';
      final key = _keys.putIfAbsent(id, GlobalKey.new);
      final day = _day(m['created_at']);
      if (day.isNotEmpty && day != prevDay) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(tr(day), style: theme.textTheme.labelSmall),
            ),
          ),
        ));
        prevUser = null;
      }
      prevDay = day;
      if (m['kind']?.toString() == 'call_summary' && m['call'] is Map) {
        items.add(KeyedSubtree(key: key, child: CallSummaryBubble(message: m)));
        prevUser = null;
        continue;
      }
      if (m['kind']?.toString() == 'call' && m['call'] is Map) {
        items.add(KeyedSubtree(
          key: key,
          child: ChatCallLogPill(message: m, me: _me, onCallBack: ChatCallHooks.available ? (video) => _call(video) : null),
        ));
        prevUser = null;
        continue;
      }
      final uid = m['user_id']?.toString();
      final next = i + 1 < _messages.length ? _messages[i + 1] : null;
      final lastOfRun = next == null || next['user_id']?.toString() != uid || _day(next['created_at']) != day || next['kind'] == 'call';
      final replyId = m['reply_to_id']?.toString();
      items.add(KeyedSubtree(
        key: key,
        child: ChatMessageBubble(
          message: m,
          me: _me,
          showName: uid != prevUser,
          showAvatar: lastOfRun,
          highlighted: _highlight == id,
          inThread: _isThread,
          replyFallback: replyId == null ? null : byId[replyId],
          onLongPress: () => _onLongPress(m),
          onReply: () => setState(() {
            _replyTo = m;
            _editing = null;
          }),
          onJumpTo: _jumpTo,
          onReact: (e) => _react(m, e),
          onOpenThread: () async {
            await nxPush<void>(context, ChatRoomScreen(room: _room, threadRoot: m));
            _refreshLatest();
          },
        ),
      ));
      prevUser = uid;
    }
    if (!_isThread) {
      final seen = readCountForLastOwn(_messages, _readers, _me);
      if (_messages.isNotEmpty && isOwnChatMessage(_messages.last, _me)) {
        items.add(Padding(
          padding: const EdgeInsets.only(top: 2, right: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(seen == 0 ? NxI.check : NxI.checks, size: 14, color: seen == 0 ? cs.onSurfaceVariant : cs.primary),
              const SizedBox(width: 3),
              Text(tr(seen == 0 ? 'ส่งแล้ว' : 'อ่านแล้ว${seen > 1 ? ' $seen' : ''}'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ));
      }
    }

    return Scaffold(
      appBar: _header(),
      body: Column(children: [
        if (_pins.isNotEmpty && !_isThread)
          Material(
            color: cs.primary.withValues(alpha: 0.08),
            child: InkWell(
              onTap: _showPins,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(NxI.pushPin, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      chatPlainText(asStringKeyedMap(_pins.first['message'])?['body']?.toString()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (_pins.length > 1) Text('+${_pins.length - 1}', style: theme.textTheme.labelMedium?.copyWith(color: cs.primary)),
                ]),
              ),
            ),
          ),
        Expanded(
          child: _loading && _messages.isEmpty
              ? const NxSkeletonChat()
              : _messages.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(NxI.chatCircle, size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text(tr('เริ่มบทสนทนาได้เลย'), style: theme.textTheme.bodyLarge),
                      ]),
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      children: [
                        if (_loadingOlder)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                          ),
                        ...items,
                      ],
                    ),
        ),
        ChatComposer(
          controller: _controller,
          draftKey: 'chat_draft_${context.read<AppConfig>().businessScope}_$_id${_threadId == null ? '' : '_t$_threadId'}',
          members: [for (final m in _members) if ('${m['user_id']}' != _me) m],
          sending: _sending,
          replyTo: _replyTo,
          onCancelReply: () => setState(() => _replyTo = null),
          editing: _editing,
          onCancelEdit: () {
            setState(() => _editing = null);
            _controller.clear();
          },
          onSend: (text, mentions) => _send(text, mentions),
          onFiles: (files) => _sendFiles(files),
          onVoice: (file, _) => _sendFiles([file]),
        ),
      ]),
    );
  }
}
