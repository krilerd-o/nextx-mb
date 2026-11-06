import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../services/api_client.dart';
import '../../services/realtime_service.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.room, this.embedded = false});
  final Map<String, dynamic> room;
  final bool embedded;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  String get _id => strId(widget.room['id']);

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.joinChatRoom(_id);
    RealtimeService.instance.addListener(_onLive);
    _load();
  }

  @override
  void dispose() {
    RealtimeService.instance.removeListener(_onLive);
    RealtimeService.instance.leaveChatRoom(_id);
    _controller.dispose();
    super.dispose();
  }

  void _onLive() {
    final msg = RealtimeService.instance.lastChatMessage;
    if (msg == null) return;
    if (msg['room_id']?.toString() != _id) return;
    _load();
  }

  Future<void> _load({bool older = false}) async {
    try {
      String? before;
      if (older && _messages.isNotEmpty) {
        before = _messages.first['created_at']?.toString();
      }
      final list = await context.read<AppConfig>().apiClient.getChatMessages(
            _id,
            limit: 50,
            before: before,
          );
      if (list.isNotEmpty) {
        final lastId = list.last['id']?.toString();
        if (lastId != null) {
          context.read<AppConfig>().apiClient.markChatRead(_id, lastId);
        }
      }
      if (mounted) {
        setState(() {
          if (older) {
            _messages = [...list, ..._messages];
          } else {
            _messages = list;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send({List<Map<String, dynamic>>? attachments}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && (attachments == null || attachments.isEmpty)) return;
    _controller.clear();
    try {
      await context.read<AppConfig>().apiClient.postChatMessage(_id, text, attachments: attachments);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _attach() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      final uploaded = await context.read<AppConfig>().apiClient.uploadChatFile(
            _id,
            MultipartFile.fromBytes(bytes, filename: file.name),
          );
      await _send(attachments: [uploaded]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.room['name']?.toString() ?? 'แชท';
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NxAppHeader(
        title: name,
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const NxSkeletonList(rows: 5)
                : RefreshIndicator(
                    color: theme.colorScheme.primary,
                    onRefresh: () => _load(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return TextButton(onPressed: () => _load(older: true), child: const Text('โหลดก่อนหน้า'));
                        }
                        final m = _messages[i - 1];
                        final who = [
                          m['first_name'],
                          m['last_name'],
                        ].where((e) => e != null && e.toString().isNotEmpty).join(' ');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: NxSurfaceCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                NxHtmlView(
                                  html: m['body']?.toString() ?? m['content']?.toString() ?? '',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  who.isEmpty ? (m['user_id']?.toString() ?? '') : who,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: NxSurfaceCard(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'ข้อความ',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(onPressed: _attach, icon: const Icon(NxI.paperclip)),
                  IconButton(onPressed: () => _send(), icon: const Icon(NxI.paperPlaneTilt)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
