import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/ai_assistant.dart';
import '../../../core/app_config.dart';
import '../../../core/i18n.dart';
import '../../../core/thai_time.dart';
import '../../../widgets/isaac_sticker.dart';
import '../../../widgets/nx_app_header.dart';
import '../../../widgets/nx_markdown.dart';
import '../../../widgets/nx_skeleton.dart';
import 'ai_assistant_controller.dart' show aiErrorText;
import 'ai_assistant_screen.dart' show handleInAppWebLink;

/// A chat someone shared (web `/share/ai/:token`), read-only.
class AiSharedChatScreen extends StatefulWidget {
  const AiSharedChatScreen({super.key, required this.token});
  final String token;

  @override
  State<AiSharedChatScreen> createState() => _AiSharedChatScreenState();
}

class _AiSharedChatScreenState extends State<AiSharedChatScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<AppConfig>().apiClient.getAiSharedChat(widget.token);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = aiErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final share = _data?['share'] is Map ? Map<String, dynamic>.from(_data!['share'] as Map) : const <String, dynamic>{};
    final snap = _data?['snapshot'] is Map ? Map<String, dynamic>.from(_data!['snapshot'] as Map) : const <String, dynamic>{};
    final messages = [
      for (final m in (snap['messages'] is List ? snap['messages'] as List : const []))
        if (m is Map) AiMessage.fromJson(Map<String, dynamic>.from(m)),
    ];
    final title = '${share['title'] ?? snap['title'] ?? ''}';
    final owner = '${share['owner_display'] ?? ''}';
    final at = share['shared_at']?.toString();
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          bottom: false,
          child: NxAppHeader(title: title.isEmpty ? tr('แชทที่แชร์') : title, subtitle: tr('แชร์จาก ISAAC AI · อ่านอย่างเดียว')),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const IsaacSticker(state: 'shrug', size: 96, animate: false),
                  const SizedBox(height: 12),
                  Text(tr(_error!), textAlign: TextAlign.center),
                ]),
              ),
            )
          : _data == null
              ? const NxSkeletonChat()
              : ListView(
                  key: const ValueKey('ai-shared-chat'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    if (owner.isNotEmpty || at != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          [if (owner.isNotEmpty) tr('แชร์โดย $owner'), if (at != null) formatThaiField(at, 'created_at')].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final m in messages)
                      if (m.isUser)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(top: 10, bottom: 6, left: 40),
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18)),
                            child: SelectableText(m.content, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              const IsaacSticker(state: 'happy', size: 32, animate: false),
                              const SizedBox(width: 8),
                              Text(aiModelBadge(m.provider, m.model), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                            ]),
                            const SizedBox(height: 6),
                            NxMarkdown(data: m.content, onOpenLink: (href) => handleInAppWebLink(context, href)),
                          ]),
                        ),
                  ],
                ),
    );
  }
}
