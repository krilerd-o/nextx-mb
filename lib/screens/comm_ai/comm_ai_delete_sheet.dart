import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'comm_ai_errors.dart';

const _danger = Color(0xFFE11D48);

/// What was deleted: `scope` 'mine' (with `recording` / `transcript`), 'all' (the whole call) or 'summary'; `result` is the server answer.
typedef CommAiDeleted = ({String scope, bool recording, bool transcript, Map<String, dynamic> result});

/// PDPA "delete my data" with confirmation (same rules as the web dialog):
///  - call, participant ([canMine]): my recording and/or the lines I said → `DELETE /calls/:id/mine`
///  - call, admin ([canAll]): the whole conversation, typed "ลบ" to confirm → `DELETE /calls/:id`
///  - chat summary (kind 'chat'): the summary → `DELETE /summaries/:id`
/// Returns what was deleted, or null when cancelled.
Future<CommAiDeleted?> showCommAiDeleteSheet(
  BuildContext context, {
  required String kind,
  required String id,
  bool canMine = false,
  bool canAll = false,
  bool hasRecording = true,
}) {
  return showAppBottomSheet<CommAiDeleted>(
    context: context,
    title: tr(kind == 'chat' ? 'ลบสรุปแชทนี้' : canMine ? 'ลบข้อมูลของฉัน' : 'ลบการสนทนาทั้งหมด'),
    child: CommAiDeleteSheet(kind: kind, id: id, canMine: canMine, canAll: canAll, hasRecording: hasRecording),
  );
}

class CommAiDeleteSheet extends StatefulWidget {
  const CommAiDeleteSheet({super.key, required this.kind, required this.id, this.canMine = false, this.canAll = false, this.hasRecording = true});
  final String kind;
  final String id;
  final bool canMine;
  final bool canAll;
  final bool hasRecording;

  @override
  State<CommAiDeleteSheet> createState() => _CommAiDeleteSheetState();
}

class _CommAiDeleteSheetState extends State<CommAiDeleteSheet> {
  late bool _recording = widget.kind == 'call' && widget.canMine && widget.hasRecording;
  bool _transcript = false;
  late bool _all = widget.kind == 'call' && !widget.canMine && widget.canAll;
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _chat => widget.kind == 'chat';
  /// The whole call needs the word typed: "ลบ" (or "DELETE" in the English UI).
  bool get _ready => _chat || (_all ? const {'ลบ', 'DELETE'}.contains(_confirm.text.trim().toUpperCase()) : _recording || _transcript);

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final api = context.read<AppConfig>().apiClient;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final CommAiDeleted out;
      if (_chat) {
        out = (scope: 'summary', recording: false, transcript: false, result: await api.deleteCommAiSummary(widget.id));
      } else if (_all) {
        out = (scope: 'all', recording: true, transcript: true, result: await api.deleteCommAiCall(widget.id));
      } else {
        out = (scope: 'mine', recording: _recording, transcript: _transcript, result: await api.deleteMyCallData(widget.id, recording: _recording, transcript: _transcript));
      }
      if (mounted) Navigator.of(context).pop(out);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = commAiErrorText(e);
        });
      }
    }
  }

  Widget _choice({required Key key, required bool value, required ValueChanged<bool> onChanged, required String title, required String desc, bool danger = false}) {
    final theme = Theme.of(context);
    final color = danger ? _danger : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        key: key,
        value: value,
        onChanged: _busy ? null : (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: color,
        tileColor: value ? color.withValues(alpha: 0.06) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: value ? color : theme.dividerColor.withValues(alpha: 0.5)),
        ),
        title: Text(tr(title), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: danger ? _danger : null)),
        subtitle: Text(tr(desc), style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: dark ? 0.18 : 0.1), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(NxI.warning, size: 18, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(_chat
                  ? 'สรุปนี้และลิงก์แชร์ของสรุปจะถูกลบถาวร ข้อความในห้องแชทยังอยู่ตามเดิม'
                  : 'ลบแล้วกู้คืนไม่ได้ สรุปเดิมยังอยู่แต่จะขึ้นว่า "แหล่งข้อมูลถูกแก้" — ให้ไอแซคสรุปใหม่ได้'),
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (!_chat && widget.canMine) ...[
        if (widget.hasRecording)
          _choice(
            key: const ValueKey('comm-ai-delete-recording'),
            value: _recording && !_all,
            onChanged: (v) => setState(() {
              _recording = v;
              if (v) _all = false;
            }),
            title: 'ลบเสียงของฉัน',
            desc: 'ไฟล์เสียงจากทุกอุปกรณ์ของฉัน — เทปรวมจะสร้างใหม่โดยไม่มีเสียงของฉัน',
          ),
        _choice(
          key: const ValueKey('comm-ai-delete-transcript'),
          value: _transcript && !_all,
          onChanged: (v) => setState(() {
            _transcript = v;
            if (v) _all = false;
          }),
          title: 'ลบข้อความที่ฉันพูด',
          desc: 'เฉพาะบรรทัดของฉันในบทสนทนา บรรทัดของคนอื่นยังอยู่',
        ),
      ],
      if (!_chat && widget.canAll)
        _choice(
          key: const ValueKey('comm-ai-delete-all'),
          value: _all,
          danger: true,
          onChanged: (v) => setState(() {
            _all = v;
            if (v) {
              _recording = false;
              _transcript = false;
            }
          }),
          title: 'ลบการสนทนาทั้งหมด (ผู้ดูแล)',
          desc: 'บทสนทนา เสียงทุกคน เทป สรุป และลิงก์แชร์ทั้งหมดของสายนี้',
        ),
      if (_all && !_chat) ...[
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('comm-ai-delete-confirm-text'),
          controller: _confirm,
          enabled: !_busy,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('พิมพ์ "ลบ" เพื่อยืนยัน')),
        ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, key: const ValueKey('comm-ai-delete-error'), style: TextStyle(color: theme.colorScheme.error)),
        ),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('comm-ai-delete-submit'),
        style: FilledButton.styleFrom(backgroundColor: _danger, foregroundColor: Colors.white),
        onPressed: _busy || !_ready ? null : _run,
        icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(NxI.trash),
        label: Text(tr('ลบถาวร')),
      ),
      TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(tr('ยกเลิก'))),
    ]);
  }
}
