import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_icons.dart';
import 'call_summary_screen.dart';

/// Chat message `kind: 'call_summary'` — posted after a call with AI notes; opens the summary.
class CallSummaryBubble extends StatelessWidget {
  const CallSummaryBubble({super.key, required this.message});
  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final meta = message['call'] is Map ? Map<String, dynamic>.from(message['call'] as Map) : const <String, dynamic>{};
    final headline = '${meta['headline'] ?? message['body'] ?? ''}'.replaceFirst(RegExp(r'^✨\s*สรุปการสนทนา:\s*'), '');
    final video = meta['media'] == 'video';
    final actions = (meta['action_count'] as num?)?.toInt() ?? 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Material(
          key: const ValueKey('chat-call-summary'),
          borderRadius: BorderRadius.circular(18),
          color: dark ? const Color(0x336366F1) : const Color(0xFFEEF2FF),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: meta['call_id'] == null ? null : () => nxPush<void>(context, CallSummaryScreen(callId: '${meta['call_id']}')),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                  child: const Icon(NxI.sparkle, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr(video ? 'สรุปการวิดีโอคอลด้วย AI' : 'สรุปการโทรด้วย AI'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4F46E5))),
                    Text(headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (actions > 0) Text(tr('$actions งานที่ต้องทำต่อ'), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
