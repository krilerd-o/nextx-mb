import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';

/// One turn in the AI conversation (OpenAI-style role/content).
class AiTurn {
  const AiTurn(this.role, this.content, {this.error = false});
  final String role; // 'user' | 'assistant'
  final String content;
  final bool error;

  Map<String, dynamic> toJson() => {'role': role, 'content': content, if (error) 'error': true};

  factory AiTurn.fromJson(Map<String, dynamic> j) =>
      AiTurn(j['role']?.toString() ?? 'user', j['content']?.toString() ?? '', error: j['error'] == true);
}

/// Pulls the assistant text out of the various NEXTX AI response shapes.
String extractAiReply(Map<String, dynamic> data) {
  for (final key in ['content', 'reply', 'text', 'message', 'output', 'answer']) {
    final v = data[key];
    if (v is String && v.trim().isNotEmpty) return v;
    if (v is Map && v['content'] is String) return v['content'] as String;
  }
  final choices = data['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final msg = first['message'];
      if (msg is Map && msg['content'] != null) return msg['content'].toString();
    }
  }
  return data.isEmpty ? '' : data.toString();
}

/// History sent to the server: successful turns only, newest [max] kept.
List<Map<String, dynamic>> aiRequestMessages(List<AiTurn> turns, {int max = 20}) {
  final ok = turns.where((t) => !t.error && t.content.trim().isNotEmpty).toList();
  final tail = ok.length > max ? ok.sublist(ok.length - max) : ok;
  return [for (final t in tail) {'role': t.role, 'content': t.content}];
}

const _suggestions = [
  'สรุปงานที่ต้องทำวันนี้ให้หน่อย',
  'ช่วยร่างอีเมลติดตามลูกค้า',
  'ลีดไหนควรติดตามก่อน',
  'เขียนสรุปการประชุมจากโน้ตนี้',
];

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<AiTurn> _turns = [];
  String? _conversationId;
  bool _busy = false;

  String get _storeKey {
    final s = context.read<AppConfig>().session;
    return 'ai_chat_${s.businessId}_${s.userId}';
  }

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storeKey);
      if (raw == null || !mounted) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _conversationId = j['conversation_id']?.toString();
        _turns = [
          for (final t in (j['turns'] as List? ?? const []))
            if (t is Map) AiTurn.fromJson(Map<String, dynamic>.from(t)),
        ];
      });
      _toBottom();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keep = _turns.length > 60 ? _turns.sublist(_turns.length - 60) : _turns;
      await prefs.setString(
        _storeKey,
        jsonEncode({'conversation_id': _conversationId, 'turns': [for (final t in keep) t.toJson()]}),
      );
    } catch (_) {}
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _busy = true;
      _turns = [..._turns, AiTurn('user', prompt)];
    });
    _toBottom();
    try {
      final data = await context.read<AppConfig>().apiClient.postAiChat(
            messages: aiRequestMessages(_turns),
            conversationId: _conversationId,
          );
      final cid = data['conversation_id']?.toString();
      if (!mounted) return;
      setState(() {
        if (cid != null && cid.isNotEmpty) _conversationId = cid;
        final reply = extractAiReply(data);
        _turns = [..._turns, AiTurn('assistant', reply.isEmpty ? '(ไม่มีคำตอบ)' : reply)];
      });
    } catch (e) {
      if (mounted) setState(() => _turns = [..._turns, AiTurn('assistant', formatApiError(e), error: true)]);
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
      _persist();
    }
  }

  Future<void> _clear() async {
    setState(() {
      _turns = [];
      _conversationId = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storeKey);
    } catch (_) {}
  }

  Widget _bubble(AiTurn t) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mine = t.role == 'user';
    final bg = mine ? cs.primary : (t.error ? cs.errorContainer : cs.surfaceContainerHighest);
    final fg = mine ? cs.onPrimary : (t.error ? cs.onErrorContainer : cs.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: CircleAvatar(radius: 14, backgroundColor: cs.primaryContainer, child: Icon(NxI.robot, size: 16, color: cs.onPrimaryContainer)),
            ),
          Flexible(
            child: GestureDetector(
              onLongPress: () async {
                await Clipboard.setData(ClipboardData(text: t.content));
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คัดลอกแล้ว')));
              },
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 18),
                  ),
                ),
                child: mine
                    ? Text(t.content, style: theme.textTheme.bodyMedium?.copyWith(color: fg))
                    : NxHtmlView(html: t.content, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: NxAppHeader(
        title: 'AI Assistant',
        subtitle: 'ผู้ช่วย MOAI NEXT',
        menu: [
          NxHeaderMenuItem(label: 'เริ่มบทสนทนาใหม่', icon: NxI.arrowCounterClockwise, onTap: _clear),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 32),
                      CircleAvatar(radius: 32, backgroundColor: cs.primaryContainer, child: Icon(NxI.robot, size: 32, color: cs.onPrimaryContainer)),
                      const SizedBox(height: 16),
                      Text('มีอะไรให้ช่วยไหม?', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text('ถามเรื่องงาน ลูกค้า หรือให้ช่วยร่างข้อความได้เลย',
                          textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                        ],
                      ),
                    ],
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    children: [
                      for (final t in _turns) _bubble(t),
                      if (_busy)
                        Padding(
                          padding: const EdgeInsets.only(left: 36, top: 8),
                          child: Row(children: [
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('กำลังคิด…', style: theme.textTheme.bodySmall),
                          ]),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์คำถาม…',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
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
