import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/chat_merge.dart';
import '../../core/entity_display.dart';
import '../../core/html_display.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';
import '../../core/error_reporting.dart';

const _quickReactions = ['👍', '❤️', '😂', '🎉', '🙏', '👀'];

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.room, this.embedded = false});
  final Map<String, dynamic> room;
  final bool embedded;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
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

  String get _id => strId(widget.room['id']);
  String? get _me => context.read<AppConfig>().session.userId;

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.joinChatRoom(_id);
    _sub = RealtimeService.instance.events.listen(_onEvent);
    _scroll.addListener(_onScroll);
    _controller.addListener(_onTextChanged);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _typingDebounce?.cancel();
    for (final t in _typingExpiry.values) {
      t.cancel();
    }
    if (_iAmTyping) RealtimeService.instance.typing(_id, active: false);
    RealtimeService.instance.leaveChatRoom(_id);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- realtime ---------------------------------------------------------

  void _onEvent(RealtimeEvent e) {
    if (!mounted) return;
    final forRoom = e.roomId == null || e.roomId == _id;
    switch (e.type) {
      case 'new_message':
        if (e.roomId != _id) return;
        final nearBottom = _isNearBottom();
        setState(() => _messages = upsertChatMessage(_messages, fillChatSender(e.data, _messages)));
        final id = e.data['id']?.toString();
        if (id != null) _markRead(id);
        if (nearBottom || isOwnChatMessage(e.data, _me)) _scrollToBottom();
      case 'message_edited':
        if (!forRoom) return;
        setState(() => _messages = upsertChatMessage(_messages, e.data));
      case 'message_deleted':
        if (!forRoom) return;
        setState(() => _messages = removeChatMessage(_messages, e.data['id']?.toString()));
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
    setState(() {}); // toggles send button state
  }

  // ---- loading ----------------------------------------------------------

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
    if (_scroll.hasClients && _scroll.offset < 80 && !_loadingOlder && _hasOlder && !_loading) {
      _loadOlder();
    }
  }

  void _markRead(String messageId) {
    final api = context.read<AppConfig>().apiClient;
    api.markChatRead(_id, messageId).catchError((Object e) {
      debugPrint('[chat] mark read: $e');
    });
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AppConfig>().apiClient.getChatMessages(_id, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _hasOlder = list.length >= 50;
      });
      final lastId = list.isEmpty ? null : list.last['id']?.toString();
      if (lastId != null) _markRead(lastId);
      _scrollToBottom(jump: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(formatApiError(e));
    }
  }

  /// Picks up reaction counts on the newest page without losing scroll position.
  Future<void> _refreshLatest() async {
    try {
      final list = await context.read<AppConfig>().apiClient.getChatMessages(_id, limit: 50);
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
      final list = await context.read<AppConfig>().apiClient.getChatMessages(_id, limit: 50, before: before);
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
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.offset + (_scroll.position.maxScrollExtent - oldExtent));
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- actions ----------------------------------------------------------

  Future<void> _send({List<Map<String, dynamic>>? attachments}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && (attachments == null || attachments.isEmpty)) return;
    final api = context.read<AppConfig>().apiClient;
    setState(() => _sending = true);
    try {
      final editing = _editing;
      if (editing != null) {
        final updated = await api.editChatMessage(_id, editing['id'].toString(), text);
        if (!mounted) return;
        setState(() {
          _messages = upsertChatMessage(_messages, {...editing, 'body': text, ...updated});
          _editing = null;
        });
      } else {
        final sent = await api.postChatMessage(_id, text, attachments: attachments);
        if (!mounted) return;
        if (sent['id'] != null) {
          setState(() => _messages = upsertChatMessage(_messages, fillChatSender({'user_id': _me, ...sent}, _messages)));
        }
        _scrollToBottom();
      }
      _controller.clear();
    } catch (e) {
      _snack(formatApiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _upload(List<int> bytes, String name) async {
    setState(() => _sending = true);
    try {
      final uploaded = await context.read<AppConfig>().apiClient.uploadChatFile(
            _id,
            MultipartFile.fromBytes(bytes, filename: name),
          );
      if (mounted) setState(() => _sending = false);
      await _send(attachments: [uploaded]);
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      _snack(formatApiError(e));
    }
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(NxI.camera), title: const Text('ถ่ายรูป'), onTap: () => Navigator.pop(ctx, 'camera')),
            ListTile(leading: const Icon(NxI.images), title: const Text('รูปจากคลัง'), onTap: () => Navigator.pop(ctx, 'gallery')),
            ListTile(leading: const Icon(NxI.file), title: const Text('ไฟล์'), onTap: () => Navigator.pop(ctx, 'file')),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'file') {
        final picked = await FilePicker.platform.pickFiles(withData: true);
        final f = picked?.files.firstOrNull;
        if (f?.bytes == null) return;
        await _upload(f!.bytes!, f.name);
      } else {
        final file = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 85,
        );
        if (file == null) return;
        await _upload(await file.readAsBytes(), file.name);
      }
    } catch (e) {
      _snack(formatApiError(e));
    }
  }

  Future<void> _messageActions(Map<String, dynamic> m) async {
    final mine = isOwnChatMessage(m, _me);
    final text = stripHtmlPreview(m['body']?.toString() ?? '', maxLen: 1 << 20);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _quickReactions)
                    InkResponse(
                      onTap: () => Navigator.pop(ctx, 'react:$emoji'),
                      radius: 24,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(leading: const Icon(NxI.clipboard), title: const Text('คัดลอก'), onTap: () => Navigator.pop(ctx, 'copy')),
            if (mine)
              ListTile(leading: const Icon(NxI.pencilSimple), title: const Text('แก้ไข'), onTap: () => Navigator.pop(ctx, 'edit')),
            if (mine)
              ListTile(
                leading: Icon(NxI.trash, color: Theme.of(ctx).colorScheme.error),
                title: Text('ลบ', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final api = context.read<AppConfig>().apiClient;
    final id = m['id']?.toString() ?? '';
    if (action.startsWith('react:')) {
      final emoji = action.substring(6);
      final mineAlready = _reactions(m).any((r) => r['emoji'] == emoji && r['me'] == true);
      try {
        await api.reactChatMessage(_id, id, emoji, remove: mineAlready);
        await _refreshLatest();
      } catch (e) {
        _snack(formatApiError(e));
      }
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      _snack('คัดลอกแล้ว');
    } else if (action == 'edit') {
      setState(() => _editing = m);
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    } else if (action == 'delete') {
      try {
        await api.deleteChatMessage(_id, id);
        if (mounted) setState(() => _messages = removeChatMessage(_messages, id));
      } catch (e) {
        _snack(formatApiError(e));
      }
    }
  }

  List<Map<String, dynamic>> _reactions(Map<String, dynamic> m) {
    final raw = m['reactions'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ---- UI ---------------------------------------------------------------

  String _who(Map<String, dynamic> m) {
    final who = [m['first_name'], m['last_name']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .join(' ');
    return who.isEmpty ? 'User #${m['user_id'] ?? ''}' : who;
  }

  static String _time(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _day(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'วันนี้';
    if (day == today.subtract(const Duration(days: 1))) return 'เมื่อวาน';
    return '${d.day}/${d.month}/${d.year + 543}';
  }

  Widget _attachmentView(Map<String, dynamic> a, bool mine) {
    final theme = Theme.of(context);
    final api = context.read<AppConfig>().apiClient;
    final url = api.chatFileUrl(a['file_path']?.toString() ?? a['url']?.toString());
    final mime = a['mime_type']?.toString() ?? '';
    final name = a['file_name']?.toString() ?? 'ไฟล์';
    Future<void> open() async {
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    if (mime.startsWith('image/') && url.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GestureDetector(
          onTap: open,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 240),
              child: _FallbackNetworkImage(urls: api.chatFileUrls(a['file_path']?.toString() ?? a['url']?.toString())),
            ),
          ),
        ),
      );
    }
    final fg = mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(NxI.paperclip, size: 18, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: fg, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m, {required bool showName, required bool showAvatar}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mine = isOwnChatMessage(m, _me);
    final body = m['body']?.toString() ?? m['content']?.toString() ?? '';
    final attachments = (m['attachments'] is List ? m['attachments'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final reactions = _reactions(m);
    final edited = m['edited_at'] != null || m['is_edited'] == true;
    final bg = mine ? cs.primary : cs.surfaceContainerHighest;
    final fg = mine ? cs.onPrimary : cs.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine ? 18 : 4),
      bottomRight: Radius.circular(mine ? 4 : 18),
    );

    final bubble = GestureDetector(
      onLongPress: () => _messageActions(m),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (body.trim().isNotEmpty)
              NxHtmlView(html: body, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
            for (final a in attachments) _attachmentView(a, mine),
            const SizedBox(height: 2),
            Text(
              '${edited ? 'แก้ไขแล้ว · ' : ''}${_time(m['created_at'])}',
              style: theme.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: showName ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine)
            SizedBox(
              width: 36,
              child: showAvatar ? NxAvatar(label: _who(m), size: 30) : null,
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (showName && !mine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(_who(m), style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                bubble,
                if (reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final r in reactions)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: r['me'] == true ? cs.primaryContainer : cs.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Text('${r['emoji']} ${r['count'] ?? 1}', style: theme.textTheme.labelSmall),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.room['name']?.toString() ?? 'แชท';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typingNames = _typing.values.toSet().toList();

    final items = <Widget>[];
    String? prevDay;
    String? prevUser;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final day = _day(m['created_at']);
      if (day.isNotEmpty && day != prevDay) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(day, style: theme.textTheme.labelSmall),
            ),
          ),
        ));
        prevUser = null;
      }
      prevDay = day;
      final uid = m['user_id']?.toString();
      final next = i + 1 < _messages.length ? _messages[i + 1] : null;
      final lastOfRun = next == null || next['user_id']?.toString() != uid || _day(next['created_at']) != day;
      items.add(_bubble(m, showName: uid != prevUser, showAvatar: lastOfRun));
      prevUser = uid;
    }

    return Scaffold(
      appBar: NxAppHeader(
        title: name,
        subtitle: typingNames.isNotEmpty
            ? '${typingNames.join(', ')} กำลังพิมพ์…'
            : (RealtimeService.instance.connected ? null : 'ออฟไลน์ — กำลังเชื่อมต่อ'),
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const NxSkeletonList(rows: 5)
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(NxI.chatCircle, size: 48, color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text('เริ่มบทสนทนาได้เลย', style: theme.textTheme.bodyLarge),
                          ],
                        ),
                      )
                    : ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
          if (_editing != null)
            Container(
              color: cs.surfaceContainer,
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
              child: Row(
                children: [
                  Icon(NxI.pencilSimple, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('กำลังแก้ไขข้อความ')),
                  IconButton(
                    icon: const Icon(NxI.x, size: 18),
                    onPressed: () {
                      setState(() => _editing = null);
                      _controller.clear();
                    },
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'แนบไฟล์',
                    onPressed: _sending || _editing != null ? null : _attach,
                    icon: const Icon(NxI.plus),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความ…',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: 'ส่ง',
                    onPressed: _sending || _controller.text.trim().isEmpty ? null : () => _send(),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_editing != null ? NxI.check : NxI.paperPlaneTilt),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tries each URL in turn until one loads.
class _FallbackNetworkImage extends StatefulWidget {
  const _FallbackNetworkImage({required this.urls});
  final List<String> urls;

  @override
  State<_FallbackNetworkImage> createState() => _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends State<_FallbackNetworkImage> {
  var _i = 0;

  @override
  Widget build(BuildContext context) {
    if (_i >= widget.urls.length) {
      return const Padding(padding: EdgeInsets.all(12), child: Icon(NxI.image));
    }
    return Image.network(
      widget.urls[_i],
      key: ValueKey(widget.urls[_i]),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _i++);
        });
        return const SizedBox(width: 48, height: 48);
      },
    );
  }
}
