import 'package:flutter/material.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_search_debounce.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/html_display.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import 'chat_room_screen.dart';
import '../../core/i18n.dart';

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
  final _wait = NxSearchDebounce();
  List<Map<String, dynamic>>? _hits;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _wait.dispose();
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
    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ค้นหาข้อความ'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => _wait.schedule(() {
              if (mounted) _run();
            }),
            onSubmitted: (_) {
              _wait.cancel();
              _run();
            },
            decoration: InputDecoration(
              hintText: tr('ค้นหาในทุกห้อง'),
              prefixIcon: const Icon(NxI.magnifyingGlass),
              filled: true,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) Text(tr('$_error'), style: TextStyle(color: theme.colorScheme.error)),
          if (_hits != null && _hits!.isEmpty)
            Padding(padding: EdgeInsets.all(32), child: Center(child: Text(tr('ไม่พบข้อความ')))),
          for (final m in _hits ?? const <Map<String, dynamic>>[])
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(NxI.chatCircle),
                title: Text(tr(stripHtmlPreview(m['body']?.toString() ?? '', maxLen: 120))),
                subtitle: Text(
                  tr([
                    _roomFor(m['room_id'])['name']?.toString() ?? '',
                    thaiDate(m['created_at'], year: uiYear),
                  ].where((e) => e.isNotEmpty).join(' · ')),
                ),
                onTap: () => nxPush<void>(context, ChatRoomScreen(room: _roomFor(m['room_id']))),
              ),
            ),
        ],
      ),
    );
  }
}
