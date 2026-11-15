import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ai_fill.dart';
import '../core/i18n.dart';
import '../services/api_client.dart' show formatApiError;
import '../services/nx_speech.dart';
import 'nx_icons.dart';

/// "ไอแซคช่วยกรอก" at the top of a create form: type, speak or paste what
/// you know (or take it from the chat) and Isaac fills the fields below.
class AiFillBox extends StatefulWidget {
  const AiFillBox({super.key, required this.extract, required this.onResult, this.chatText, this.initialText, this.autoRun = false});

  final AiFillFn extract;
  final ValueChanged<AiFillResult> onResult;

  /// The chat so far, for "เติมจากแชทนี้" (null hides the button).
  final String Function()? chatText;
  final String? initialText;

  /// Run once on open with [initialText] (text typed after the /command).
  final bool autoRun;

  @override
  State<AiFillBox> createState() => _AiFillBoxState();
}

class _AiFillBoxState extends State<AiFillBox> {
  late final _text = TextEditingController(text: widget.initialText ?? '');
  bool _busy = false;
  bool _listening = false;
  String? _error;
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    if (widget.autoRun && (widget.initialText ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    if (_listening) NxSpeech.instance.stop();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run([String? override]) async {
    final t = (override ?? _text.text).trim();
    if (t.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.extract(t);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      widget.onResult(r);
      setState(() => _open = r.isEmpty);
      if (r.isEmpty) setState(() => _error = 'ไอแซคหาข้อมูลที่ใช้กรอกไม่พบ — ลองพิมพ์รายละเอียดเพิ่ม');
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) return;
    _text.text = _text.text.trim().isEmpty ? t : '${_text.text.trim()}\n$t';
  }

  Future<void> _mic() async {
    if (_listening) {
      await NxSpeech.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final base = _text.text.trim().isEmpty ? '' : '${_text.text.trim()} ';
    final ok = await NxSpeech.instance.start(
      localeId: L10n.isEn ? 'en_US' : 'th_TH',
      onText: (t, done) {
        if (!mounted) return;
        _text.text = '$base$t';
        if (done) setState(() => _listening = false);
      },
      onStop: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _listening = ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('ai-fill-box'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0.10), const Color(0xFF8B5CF6).withValues(alpha: 0.08)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                Icon(NxI.sparkle, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('ไอแซคช่วยกรอก'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                Icon(_open ? NxI.caretUp : NxI.caretDown, size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            Text(
              tr('พิมพ์ พูด หรือวางข้อความที่รู้ เช่น ชื่อ บริษัท เบอร์ เรื่อง วันเวลา ผู้รับผิดชอบ แล้วไอแซคจะกรอกให้'),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('ai-fill-text'),
              controller: _text,
              minLines: 2,
              maxLines: 6,
              enabled: !_busy,
              decoration: InputDecoration(
                hintText: tr('เช่น คุณสมชาย บริษัท ABC 081-234-5678 สนใจระบบ CRM ให้คุณเอดูแล'),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('ai-fill-mic'),
                  tooltip: tr(_listening ? 'หยุดฟัง' : 'พูดแทนพิมพ์'),
                  onPressed: _busy ? null : _mic,
                  icon: Icon(_listening ? NxI.stop : NxI.microphone, size: 20, color: _listening ? cs.error : null),
                ),
                IconButton(tooltip: tr('วาง'), onPressed: _busy ? null : _paste, icon: const Icon(NxI.clipboardText, size: 20)),
                if (widget.chatText != null)
                  TextButton.icon(
                    key: const ValueKey('ai-fill-from-chat'),
                    onPressed: _busy ? null : () => _run(widget.chatText!()),
                    icon: const Icon(NxI.chatCircle, size: 16),
                    label: Text(tr('เติมจากแชทนี้')),
                  ),
                FilledButton.icon(
                  key: const ValueKey('ai-fill-run'),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  onPressed: _busy || _text.text.trim().isEmpty ? null : _run,
                  icon: const Icon(NxI.sparkle, size: 16),
                  label: Text(tr('ให้ไอแซคกรอก')),
                ),
              ],
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr(_error!), style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
            ),
        ],
      ),
    );
  }
}

/// After Isaac filled: how many fields, people / customers it could not
/// match (pick from candidates), required fields left, maybe-duplicates.
class AiFilledBanner extends StatelessWidget {
  const AiFilledBanner({super.key, required this.result, required this.labelOf, required this.onPick, this.onOpenDuplicate});

  final AiFillResult result;
  final String Function(String field) labelOf;

  /// A candidate picked for an unmatched field.
  final void Function(String field, Map<String, dynamic> candidate) onPick;
  final ValueChanged<Map<String, dynamic>>? onOpenDuplicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('ai-filled-banner'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NxI.sparkle, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('ไอแซคกรอกให้ ${result.filled.length} ช่อง — ตรวจสอบก่อนบันทึก'),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          for (final e in result.hints.entries) ...[
            const SizedBox(height: 8),
            Text(tr('${labelOf(e.key)}: ไอแซคเดาว่า "${e.value.text}" — เลือกให้ถูกต้อง'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface)),
            if (e.value.candidates.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final c in e.value.candidates)
                    ActionChip(key: ValueKey('ai-hint-${e.key}-${c['id']}'), label: Text('${c['label'] ?? c['id']}'), onPressed: () => onPick(e.key, c)),
                ],
              ),
          ],
          if (result.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr('ยังต้องกรอก: ${result.missing.map((m) => '${m['label'] ?? m['field']}').join(', ')}'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          for (final d in result.duplicates)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: onOpenDuplicate == null ? null : () => onOpenDuplicate!(d),
                child: Row(
                  children: [
                    Icon(NxI.warningCircle, size: 14, color: cs.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('อาจซ้ำกับ ${d['name'] ?? ''} (${d['reason'] ?? ''})'),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.error, decoration: onOpenDuplicate == null ? null : TextDecoration.underline),
                      ),
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
