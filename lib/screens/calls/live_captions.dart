import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../services/calls/live_transcription.dart';
import '../../widgets/nx_icons.dart';
import '../comm_ai/call_summary_screen.dart';
import '../comm_ai/comm_ai_errors.dart';
import '../comm_ai/comm_ai_isaac.dart';

const _glass = Color(0xB3020617);

/// "ให้ AI ช่วยจดบทสนทนาไหม?" — one tap answers (incoming) or decides (in call) and the call is never delayed.
class CallConsentPanel extends StatefulWidget {
  const CallConsentPanel({super.key, required this.incoming, required this.onDecide, this.onDecline, this.recordOption = false, this.shareDefault = true, this.callerMode = false});
  final bool incoming;
  final bool recordOption;
  final bool shareDefault;
  final bool callerMode;
  final void Function(bool enabled, bool share, bool record, bool remember) onDecide;
  final VoidCallback? onDecline;

  @override
  State<CallConsentPanel> createState() => _CallConsentPanelState();
}

class _CallConsentPanelState extends State<CallConsentPanel> {
  late bool _share = widget.shareDefault;
  late bool _record = widget.recordOption;
  bool _remember = false;

  Widget _switch(IconData icon, String label, String hint, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFF10B981),
        secondary: Icon(icon, color: Colors.white70),
        title: Text(tr(label), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(tr(hint), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('call-stt-consent'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF21E293B), Color(0xF20F172A)]),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Center(child: IsaacAvatar(mood: 'listening', size: 72)),
        const SizedBox(height: 10),
        Text(tr('ให้ไอแซคช่วยจดบทสนทนาไหม?'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          tr(widget.callerMode
              ? 'คุณเป็นผู้เริ่มสาย — เมื่อเปิด ระบบจะแปลงเสียงทุกคนในสายเป็นข้อความ และทุกคนจะเห็นแจ้งเตือน'
              : 'ระบบจะแปลงเสียงพูดของคุณเป็นข้อความระหว่างคุย และสรุปประเด็น งานที่ต้องทำให้หลังวางสาย'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        _switch(NxI.eye, 'ให้คู่สายเห็นข้อความด้วย', 'ทุกคนเห็นคำพูดของกันและกันแบบสด ๆ', _share, (v) => setState(() => _share = v)),
        if (widget.recordOption) _switch(NxI.microphone, 'บันทึกเสียงไว้ฟังย้อนหลัง', 'เฉพาะเสียงของคุณ', _record, (v) => setState(() => _record = v)),
        InkWell(
          onTap: () => setState(() => _remember = !_remember),
          child: Row(children: [
            Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false), side: const BorderSide(color: Colors.white38)),
            Text(tr('จำการเลือกนี้'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          key: const ValueKey('call-stt-accept'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: () => widget.onDecide(true, _share, _record, _remember),
          icon: const Icon(NxI.fileText),
          label: Text(tr(widget.incoming ? 'รับสาย + เริ่มจดบทสนทนา' : 'เริ่มจดบทสนทนา'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('call-stt-skip'),
          style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white10, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: () => widget.onDecide(false, _share, false, _remember),
          child: Text(tr(widget.incoming ? 'รับสายอย่างเดียว' : 'ไม่ใช้ครั้งนี้')),
        ),
        if (widget.onDecline != null) TextButton(onPressed: widget.onDecline, child: Text(tr('ปฏิเสธสาย'), style: const TextStyle(color: Color(0xFFFCA5A5)))),
      ]),
    );
  }
}

/// Live captions strip over the call screen; listens on its own so the call screen does not rebuild per word.
class LiveCaptionsPanel extends StatefulWidget {
  const LiveCaptionsPanel({super.key, required this.lt});
  final LiveTranscription lt;

  @override
  State<LiveCaptionsPanel> createState() => _LiveCaptionsPanelState();
}

/// Off → English → ไทย → off. Only finished lines are translated (cached on the server).
const kCaptionLangCycle = ['', 'en', 'th'];

class _LiveCaptionsPanelState extends State<LiveCaptionsPanel> {
  bool _open = true;
  static const _colors = [Color(0xFF7DD3FC), Color(0xFF6EE7B7), Color(0xFFFCD34D), Color(0xFFF9A8D4), Color(0xFFC4B5FD)];
  String _lang = '';
  final _tr = <String, String>{}; // '$lang:$captionKey' → text
  final _asked = <String>{};
  Timer? _debounce;
  String? _trError;

  @override
  void initState() {
    super.initState();
    widget.lt.captions.addListener(_schedule);
  }

  @override
  void didUpdateWidget(LiveCaptionsPanel old) {
    super.didUpdateWidget(old);
    if (old.lt != widget.lt) {
      old.lt.captions.removeListener(_schedule);
      widget.lt.captions.addListener(_schedule);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.lt.captions.removeListener(_schedule);
    super.dispose();
  }

  void _cycleLang() {
    setState(() => _trError = null);
    setState(() => _lang = kCaptionLangCycle[(kCaptionLangCycle.indexOf(_lang) + 1) % kCaptionLangCycle.length]);
    _schedule();
  }

  void _schedule() {
    if (_lang.isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _translate);
  }

  Future<void> _translate() async {
    final lang = _lang;
    final api = widget.lt.api;
    if (lang.isEmpty || api == null) return;
    final todo = [for (final c in widget.lt.captions.value) if (c.isFinal && c.text.isNotEmpty && !_asked.contains('$lang:${c.key}')) c];
    final batch = todo.length > 30 ? todo.sublist(todo.length - 30) : todo;
    if (batch.isEmpty) return;
    for (final c in batch) {
      _asked.add('$lang:${c.key}');
    }
    try {
      final out = await api.translateCommAi([for (final c in batch) c.text], lang);
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < batch.length; i++) {
          _tr['$lang:${batch[i].key}'] = i < out.length ? out[i] : '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (isCommAiQuotaError(e)) {
        // Used up for the month: say so once and stop asking (the call goes on).
        setState(() {
          _trError = commAiErrorText(e);
          _lang = '';
        });
        return;
      }
      for (final c in batch) {
        _asked.remove('$lang:${c.key}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = widget.lt;
    return ListenableBuilder(
      listenable: lt,
      builder: (context, _) {
        if (!lt.anyoneTranscribed && !lt.running && lt.request == null && lt.error == null) return const SizedBox.shrink();
        final names = lt.speakers.values.where((s) => s.enabled).map((s) => s.userId == lt.myUserId ? tr('คุณ') : s.name).join(', ');
        final share = lt.decision?.share ?? true;
        return Padding(
          key: const ValueKey('call-captions'),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: _glass,
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (lt.request != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('🔴 ${tr('${lt.request!['by_name']} เปิดให้ไอแซคจดบทสนทนาในสายนี้')}', style: const TextStyle(color: Color(0xFFFDA4AF), fontSize: 12)),
                    ),
                  Row(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      const IsaacAvatar(mood: 'listening', size: 26, ring: false, animate: false),
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: const Color(0xFFF43F5E), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0F172A), width: 1.5)),
                        ),
                      ),
                    ]),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${tr('ไอแซคกำลังจดบทสนทนา')}${names.isEmpty ? '' : ' · $names'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                    if (lt.status == 'reconnecting' || lt.status == 'connecting') const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFCD34D))),
                    if (lt.running)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: tr(share ? 'ซ่อนข้อความของฉันจากคู่สาย' : 'ให้คู่สายเห็นข้อความของฉัน'),
                        icon: Icon(share ? NxI.eye : NxI.eyeSlash, size: 18, color: Colors.white70),
                        onPressed: () => lt.setShare(!share),
                      ),
                    if (lt.running)
                      IconButton(visualDensity: VisualDensity.compact, tooltip: tr('หยุดจดเสียงของฉัน'), icon: const Icon(NxI.stop, size: 16, color: Colors.white70), onPressed: lt.stop),
                    Tooltip(
                      message: tr('แปลคำบรรยาย'),
                      child: TextButton.icon(
                        key: const ValueKey('call-captions-translate'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(36, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          foregroundColor: _lang.isEmpty ? Colors.white70 : Colors.white,
                          backgroundColor: _lang.isEmpty ? null : const Color(0x4D0EA5E9),
                        ),
                        onPressed: _cycleLang,
                        icon: const Icon(NxI.languages, size: 18),
                        label: Text(_lang.isEmpty ? '' : _lang.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('call-captions-toggle'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(NxI.fileText, size: 18, color: _open ? Colors.white : Colors.white38),
                      onPressed: () => setState(() => _open = !_open),
                    ),
                  ]),
                  if (lt.error != null)
                    Text(
                      commAiSttErrorText(lt.error!, quota: lt.quota),
                      key: const ValueKey('call-captions-error'),
                      style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 12),
                    ),
                  if (_trError != null)
                    Text(_trError!, key: const ValueKey('call-captions-translate-error'), style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 12)),
                  if (_open)
                    ValueListenableBuilder<List<LiveCaption>>(
                      valueListenable: lt.captions,
                      builder: (_, list, _) {
                        final shown = list.length > 4 ? list.sublist(list.length - 4) : list;
                        final ids = <String>[];
                        for (final c in list) {
                          if (!ids.contains(c.userId)) ids.add(c.userId);
                        }
                        if (shown.isEmpty) {
                          return Padding(padding: const EdgeInsets.only(top: 4), child: Text(tr('เริ่มพูดได้เลย ข้อความจะขึ้นตรงนี้…'), style: const TextStyle(color: Colors.white38, fontSize: 13)));
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final c in shown)
                            AnimatedOpacity(
                              key: ValueKey(c.key),
                              opacity: c.isFinal ? 1 : 0.7,
                              duration: const Duration(milliseconds: 250),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4, right: 8),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text.rich(TextSpan(children: [
                                    TextSpan(text: '${c.userId == lt.myUserId ? tr('คุณ') : c.name}  ', style: TextStyle(color: _colors[ids.indexOf(c.userId) % _colors.length], fontWeight: FontWeight.w700, fontSize: 12)),
                                    TextSpan(text: c.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
                                  ])),
                                  if (_lang.isNotEmpty && (_tr['$_lang:${c.key}'] ?? '').isNotEmpty)
                                    Text(_tr['$_lang:${c.key}']!, key: ValueKey('call-caption-tr-${c.key}'), style: const TextStyle(color: Color(0xE6BAE6FD), fontSize: 13, fontStyle: FontStyle.italic, height: 1.3)),
                                ]),
                              ),
                            ),
                        ]);
                      },
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// In-call ask (outgoing calls, or answered from the phone's call screen) — never blocks the call.
class SttInlineAsk extends StatefulWidget {
  const SttInlineAsk({super.key, required this.lt, required this.callId});
  final LiveTranscription lt;
  final String callId;

  @override
  State<SttInlineAsk> createState() => _SttInlineAskState();
}

class _SttInlineAskState extends State<SttInlineAsk> {
  bool? _ask;

  @override
  void initState() {
    super.initState();
    widget.lt.needsConsent(widget.callId).then((v) {
      if (mounted) setState(() => _ask = v);
    });
  }

  @override
  void didUpdateWidget(SttInlineAsk old) {
    super.didUpdateWidget(old);
    if (old.callId != widget.callId) {
      _ask = null;
      widget.lt.needsConsent(widget.callId).then((v) {
        if (mounted) setState(() => _ask = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lt = widget.lt;
    if (_ask != true || lt.decision?.callId == widget.callId) return const SizedBox.shrink();
    return CallConsentPanel(
      incoming: false,
      callerMode: lt.callerMode,
      recordOption: lt.settings?['record_audio'] == true,
      shareDefault: lt.settings?['share_captions_default'] != false,
      onDecide: (enabled, share, record, remember) {
        lt.decide(widget.callId, enabled: enabled, share: share, record: record, remember: remember);
        setState(() => _ask = false);
      },
    );
  }
}

/// "สรุปการสนทนาพร้อมแล้ว" — appears on any screen after the call; opens the summary.
class CallSummaryToast extends StatelessWidget {
  const CallSummaryToast({super.key, required this.lt, required this.navigatorKey});
  final LiveTranscription lt;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: lt.summaryReady,
      builder: (context, ready, _) {
        if (ready == null) return const SizedBox.shrink();
        return Positioned(
          left: 12,
          right: 12,
          bottom: MediaQuery.paddingOf(context).bottom + 76,
          child: Material(
            key: const ValueKey('call-summary-toast'),
            elevation: 8,
            borderRadius: BorderRadius.circular(20),
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(children: [
                const IsaacAvatar(mood: 'success', size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('ไอแซคสรุปการสนทนาเสร็จแล้ว'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${ready['headline'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                  ]),
                ),
                TextButton(
                  onPressed: () {
                    lt.summaryReady.value = null;
                    navigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => CallSummaryScreen(callId: '${ready['call_id']}')));
                  },
                  child: Text(tr('ดูสรุป')),
                ),
                IconButton(icon: const Icon(NxI.x, size: 18), onPressed: () => lt.summaryReady.value = null),
              ]),
            ),
          ),
        );
      },
    );
  }
}
