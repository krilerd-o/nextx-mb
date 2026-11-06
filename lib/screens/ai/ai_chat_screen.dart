import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/nx_icons.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final List<String> _lines = ['ผู้ช่วย AI ของ MOAINEXT'];
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _extractReply(Map<String, dynamic> data) {
    for (final key in ['content', 'reply', 'text', 'message', 'output']) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v;
    }
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final msg = first['message'];
        if (msg is Map && msg['content'] != null) return msg['content'].toString();
      }
    }
    return data.toString();
  }

  Future<void> _send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _busy = true;
      _lines.add('คุณ: $prompt');
    });
    try {
      final data = await context.read<AppConfig>().apiClient.postAiChat(
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      if (mounted) {
        setState(() => _lines.add(_extractReply(data)));
      }
    } catch (e) {
      if (mounted) setState(() => _lines.add(formatApiError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const NxAppHeader(title: 'AI Assistant'),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _lines.length,
              itemBuilder: (context, i) {
                final mine = _lines[i].startsWith('คุณ: ');
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NxSurfaceCard(
                        color: mine ? theme.colorScheme.primary.withOpacity(0.12) : null,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: NxHtmlView(html: _lines[i], style: theme.textTheme.bodyMedium),
                      ),
                    ),
                  ),
                );
              },
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
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        hintText: 'ถาม AI',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => _send(_controller.text),
                    icon: const Icon(NxI.paperPlaneTilt),
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
