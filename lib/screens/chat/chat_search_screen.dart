import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/html_display.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import 'chat_room_screen.dart';

/// Search messages across all rooms the user belongs to.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({super.key, required this.rooms});

  /// Known rooms, to show names and open the right room.
  final List<Map<String, dynamic>> rooms;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _q = TextEditingController();
  List<Map<String, dynamic>>? _hits;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    if (q.length < 2) {
      setState(() => _error = 'พิมพ์อย่างน้อย 2 ตัวอักษร');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await context.read<AppConfig>().apiClient.searchChat(q);
      if (mounted) setState(() => _hits = hits);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _roomFor(dynamic roomId) {
    for (final r in widget.rooms) {
      if (r['id']?.toString() == roomId?.toString()) return r;
    }
    return {'id': roomId, 'name': 'แชท'};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const NxAppHeader(title: 'ค้นหาข้อความ'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: 'ค้นหาในทุกห้อง',
              prefixIcon: const Icon(NxI.magnifyingGlass),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) Text('$_error', style: TextStyle(color: theme.colorScheme.error)),
          if (_hits != null && _hits!.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('ไม่พบข้อความ'))),
          for (final m in _hits ?? const <Map<String, dynamic>>[])
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(NxI.chatCircle),
                title: Text(stripHtmlPreview(m['body']?.toString() ?? '', maxLen: 120)),
                subtitle: Text(
                  [
                    _roomFor(m['room_id'])['name']?.toString() ?? '',
                    (m['created_at']?.toString() ?? '').split('T').first,
                  ].where((e) => e.isNotEmpty).join(' · '),
                ),
                onTap: () => nxPush<void>(context, ChatRoomScreen(room: _roomFor(m['room_id']))),
              ),
            ),
        ],
      ),
    );
  }
}
