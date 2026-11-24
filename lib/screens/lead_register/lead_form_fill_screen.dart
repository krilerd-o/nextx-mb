import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/lead_register/lead_form.dart';
import '../../services/api_exceptions.dart';
import '../../services/lead_register_queue.dart';
import '../../widgets/fields/nx_entity_form.dart' show nxFieldHostFor;
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_icons.dart';
import '../crm/card_scan/card_capture_screen.dart';
import '../crm/card_scan/card_ocr.dart';
import '../crm/card_scan/card_scan_models.dart';
import 'lead_form_renderer.dart';

String _uuid() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${h(4)}-${h(12)}';
}

/// Native form fill — staff filling in for a visitor, or a booth kiosk.
/// Layout follows the form's UI type (classic / card / conversational / kiosk).
/// Answers that cannot be sent are queued on the phone and sent later.
class LeadFormFillScreen extends StatefulWidget {
  const LeadFormFillScreen({super.key, required this.formId, this.kiosk = false, this.leadId});
  final int formId;
  final bool kiosk;
  final int? leadId;

  @override
  State<LeadFormFillScreen> createState() => _LeadFormFillScreenState();
}

class _LeadFormFillScreenState extends State<LeadFormFillScreen> {
  LeadFormDef? _form;
  Object? _loadError;
  LeadAnswers _answers = {};
  Map<String, String> _errors = {};
  Set<String> _aiFilled = {};
  int _step = 0;
  final List<int> _history = [];
  bool _busy = false;
  bool _scanning = false;
  bool _started = false;
  ({String title, String message, bool offline})? _done;
  DateTime? _startAt;
  Timer? _resetTimer;
  Timer? _idleTimer;
  final _scroll = ScrollController();
  NxFieldHost? _host;
  Map<String, dynamic>? _cardImage;
  int? _serverDraftId;
  Timer? _draftTimer;

  String get _draftKey => 'lr_draft_v1:${widget.formId}:${widget.leadId ?? 0}';

  bool _kioskOn = false;
  bool get _kiosk => widget.kiosk || _form?.uiType == 'kiosk';
  String get _layout => _kiosk ? 'kiosk' : (_form?.uiType ?? 'classic');

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.kiosk) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _keepAwake(true);
    }
    LeadRegisterQueue.instance.load();
  }

  /// Booth screens must not sleep between visitors.
  void _keepAwake(bool on) {
    try {
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _idleTimer?.cancel();
    _draftTimer?.cancel();
    _scroll.dispose();
    if (_kioskOn || widget.kiosk) _keepAwake(false);
    if (widget.kiosk) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    _host = _uploadingHost();
    try {
      final data = await api.getLeadFormFill(widget.formId);
      final f = Map<String, dynamic>.from(data['form'] as Map);
      f['id'] ??= widget.formId;
      if (!mounted) return;
      setState(() {
        _form = LeadFormDef(f);
        _started = !_kiosk;
      });
      if (_kiosk && !widget.kiosk) _keepAwake(true);
      _kioskOn = _kiosk;
      if (!_kiosk) await _restoreLocalDraft();
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Media answers go to the form's own upload endpoint (`/forms/:id/upload`).
  NxFieldHost _uploadingHost() {
    final api = context.read<AppConfig>().apiClient;
    final base = nxFieldHostFor(api);
    Future<String?> upload(List<int> bytes, String filename) async {
      try {
        final files = await api.uploadLeadFormAnswerFile(widget.formId, bytes, filename);
        return files.isEmpty ? null : files.first['url']?.toString();
      } catch (_) {
        return null;
      }
    }

    return NxFieldHost(
      loadUsers: base.loadUsers,
      loadEntities: base.loadEntities,
      loadTags: base.loadTags,
      loadPackages: base.loadPackages,
      loadPicklist: base.loadPicklist,
      pickMedia: base.pickMedia,
      uploadBytes: upload,
      captureGps: base.captureGps,
    );
  }

  // ---- local draft: a half-filled form survives app switch / restart (not in kiosk)
  Future<void> _restoreLocalDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_draftKey);
      if (raw == null) return;
      final m = jsonDecode(raw);
      if (m is! Map || m['answers'] is! Map || (m['answers'] as Map).isEmpty) return;
      if (!mounted) return;
      setState(() {
        _answers = Map<String, dynamic>.from(m['answers'] as Map);
        _cardImage = m['card_image'] is Map ? Map<String, dynamic>.from(m['card_image'] as Map) : null;
        _serverDraftId = (m['server_draft_id'] as num?)?.toInt();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('กู้คืนคำตอบที่กรอกค้างไว้แล้ว')),
        action: SnackBarAction(label: tr('ล้าง'), onPressed: () {
          _clearLocalDraft();
          _reset();
        }),
      ));
    } catch (_) {}
  }

  void _saveLocalDraftSoon() {
    if (_kiosk) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final p = await SharedPreferences.getInstance();
        if (_answers.isEmpty) {
          await p.remove(_draftKey);
        } else {
          await p.setString(_draftKey, jsonEncode({'answers': _answers, 'card_image': _cardImage, 'server_draft_id': _serverDraftId, 'at': DateTime.now().toIso8601String()}));
        }
      } catch (_) {}
    });
  }

  Future<void> _clearLocalDraft() async {
    _draftTimer?.cancel();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_draftKey);
    } catch (_) {}
  }

  /// Staff draft on the server — finish later from any device (never runs the flow).
  Future<void> _saveServerDraft() async {
    if (_answers.isEmpty) return;
    final api = context.read<AppConfig>().apiClient;
    setState(() => _busy = true);
    try {
      final out = await api.submitLeadForm(widget.formId, answers: _answers, clientUuid: _uuid(), channel: 'mobile', leadId: widget.leadId, draft: true, cardImage: _cardImage, responseId: _serverDraftId);
      _serverDraftId = (out['id'] as num?)?.toInt() ?? _serverDraftId;
      _saveLocalDraftSoon();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกร่างแล้ว'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกร่างไม่สำเร็จ'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _set(String key, dynamic value) {
    _startAt ??= DateTime.now();
    _bumpIdle();
    setState(() {
      if (value == null) {
        _answers.remove(key);
      } else {
        _answers = {..._answers, key: value};
      }
      _errors.remove(key);
      _aiFilled.remove(key);
    });
    _saveLocalDraftSoon();
  }

  void _bumpIdle() {
    if (!_kiosk) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 2), _reset);
  }

  void _reset() {
    _resetTimer?.cancel();
    _idleTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _answers = {};
      _errors = {};
      _aiFilled = {};
      _step = 0;
      _history.clear();
      _done = null;
      _startAt = null;
      _started = !_kiosk;
      _cardImage = null;
      _serverDraftId = null;
    });
  }

  List<(LeadQuestion, int)> _flat() {
    final out = <(LeadQuestion, int)>[];
    final sections = _form!.sections;
    for (var i = 0; i < sections.length; i++) {
      for (final q in leadVisibleQuestions(sections[i], _answers)) {
        out.add((q, i));
      }
    }
    return out;
  }

  Map<String, int> _numbers() {
    final m = <String, int>{};
    var n = 0;
    for (final (q, _) in _flat()) {
      if (!q.displayOnly) m[q.id] = ++n;
    }
    return m;
  }

  Map<String, String> _validateAll() {
    final errs = <String, String>{};
    for (final s in _form!.sections) {
      errs.addAll(leadValidateSection(s, _answers));
    }
    return errs;
  }

  Future<void> _submit() async {
    final errs = _validateAll();
    if (errs.isNotEmpty) {
      setState(() => _errors = errs);
      final first = errs.keys.first;
      if (_layout == 'conversational') {
        final i = _flat().indexWhere((x) => x.$1.id == first);
        if (i >= 0) setState(() => _step = i);
      } else if (_layout != 'classic') {
        final i = _form!.sections.indexWhere((s) => s.questions.any((q) => q.id == first));
        if (i >= 0) setState(() => _step = i);
      }
      HapticFeedback.heavyImpact();
      return;
    }
    final api = context.read<AppConfig>().apiClient;
    final uuid = _uuid();
    final channel = _kiosk ? 'kiosk' : 'mobile';
    final fillMs = _startAt == null ? null : DateTime.now().difference(_startAt!).inMilliseconds;
    setState(() => _busy = true);
    final s = _form!.settings;
    try {
      await api.submitLeadForm(widget.formId, answers: _answers, clientUuid: uuid, channel: channel, fillMs: fillMs, leadId: widget.leadId, cardImage: _cardImage, responseId: _serverDraftId);
      await _clearLocalDraft();
      _finish(title: s['thank_you_title']?.toString() ?? tr('ขอบคุณ!'), message: s['thank_you_message']?.toString() ?? tr('บันทึกคำตอบแล้ว'));
    } on ApiEnvelopeException catch (e) {
      final details = e.details?['errors'];
      if (details is Map) setState(() => _errors = details.map((k, v) => MapEntry('$k', '$v')));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(e.message))));
    } catch (_) {
      // No network: keep it on the phone, send later (same client_uuid = no duplicates).
      await LeadRegisterQueue.instance.add(formId: widget.formId, answers: _answers, clientUuid: uuid, channel: channel, fillMs: fillMs, leadId: widget.leadId, cardImage: _cardImage);
      await _clearLocalDraft();
      _finish(title: tr('บันทึกไว้ในเครื่องแล้ว'), message: tr('ไม่มีอินเทอร์เน็ต — ระบบจะส่งให้อัตโนมัติเมื่อกลับมาออนไลน์'), offline: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish({required String title, required String message, bool offline = false}) {
    HapticFeedback.mediumImpact();
    setState(() => _done = (title: title, message: message, offline: offline));
    if (_kiosk) {
      _resetTimer?.cancel();
      _resetTimer = Timer(Duration(seconds: _form!.kioskResetSeconds), _reset);
    }
  }

  void _nextSection() {
    final sections = _form!.sections;
    final errs = leadValidateSection(sections[_step], _answers);
    if (errs.isNotEmpty) {
      setState(() => _errors = {..._errors, ...errs});
      HapticFeedback.heavyImpact();
      return;
    }
    final j = leadNextSection(sections, _step, _answers);
    if (j >= sections.length) {
      _submit();
      return;
    }
    setState(() {
      _history.add(_step);
      _step = j;
    });
    _scroll.jumpTo(0);
  }

  void _nextQuestion() {
    final flat = _flat();
    if (_step < flat.length) {
      final e = leadValidateQuestion(flat[_step].$1, _answers);
      if (e != null) {
        setState(() => _errors = {..._errors, flat[_step].$1.id: e});
        return;
      }
    }
    if (_step + 1 >= flat.length) {
      _submit();
      return;
    }
    setState(() => _step++);
  }

  Future<void> _scanCard() async {
    final api = context.read<AppConfig>().apiClient;
    final images = await Navigator.of(context, rootNavigator: true).push<CardImages>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CardCaptureScreen()),
    );
    if (images == null || !mounted) return;
    setState(() => _scanning = true);
    try {
      Map<String, dynamic> scanned;
      try {
        var out = await api.scanLeadFormCard(widget.formId, front: images.front, back: images.back);
        if (out['card_image'] is Map) _cardImage = Map<String, dynamic>.from(out['card_image'] as Map);
        if (out['status'] == 'no_ai') {
          // No AI vision on the server: read the card on the phone and send just the text.
          final ocr = await CardOcr.read(images.front);
          if (ocr != null && ocr.trim().isNotEmpty) out = await api.scanLeadFormCard(widget.formId, ocrText: ocr);
        }
        scanned = out['answers'] is Map ? Map<String, dynamic>.from(out['answers'] as Map) : <String, dynamic>{};
      } on ApiEnvelopeException {
        rethrow;
      } catch (_) {
        // Offline: on-device OCR + simple rules (email / phone / name). AI refines when online.
        final ocr = await CardOcr.read(images.front);
        scanned = ocr == null ? <String, dynamic>{} : leadParseCardText(ocr, _form!);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ออฟไลน์ — อ่านนามบัตรในเครื่อง (ตรวจสอบข้อมูลก่อนส่ง)'))));
      }
      final merged = leadMergeScan(_answers, scanned);
      _startAt ??= DateTime.now();
      setState(() {
        _answers = merged.answers;
        _aiFilled = merged.filled;
        for (final k in merged.filled) {
          _errors.remove(k);
        }
      });
      _saveLocalDraftSoon();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(merged.filled.isEmpty ? tr('อ่านนามบัตรไม่พบข้อมูลที่ตรงกับคำถาม') : '${tr('เติมข้อมูลแล้ว')} ${merged.filled.length} ${tr('ช่อง — ตรวจสอบก่อนส่ง')}'),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สแกนนามบัตรไม่สำเร็จ'))));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _exitKiosk() async {
    final pin = _form?.kioskPin ?? '';
    if (pin.isNotEmpty) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('ใส่ PIN เพื่อออก')),
          content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, obscureText: true, maxLength: 8),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('ยกเลิก'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text == pin), child: Text(tr('ออก'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _keepAwake(false);
    _kioskOn = false;
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    if (_loadError != null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('เปิดแบบฟอร์มไม่ได้')))));
    }
    if (form == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final accent = leadAccent(form.theme);
    final big = _kiosk;
    final body = _done != null
        ? _thankYou(accent)
        : !_started
            ? _welcome(accent)
            : _layout == 'conversational'
                ? _conversational(accent, big)
                : _layout == 'classic'
                    ? _classic(accent)
                    : _cards(accent, big);
    final content = Theme(
      data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: accent)),
      child: Stack(children: [
        Listener(onPointerDown: (_) => _bumpIdle(), child: body),
        if (_kiosk)
          Positioned(
            right: 8,
            top: 4,
            child: IconButton(tooltip: tr('ออกจากโหมดคีออสก์'), onPressed: _exitKiosk, icon: Icon(NxI.lock, color: Theme.of(context).hintColor, size: 18)),
          ),
      ]),
    );
    return PopScope(
      canPop: !_kiosk,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _kiosk) _exitKiosk();
      },
      child: _kiosk
          ? Scaffold(body: SafeArea(child: content))
          : NxScrollScaffold(
              motionBlur: false,
              header: NxAppHeader(
                title: form.name,
                actions: [
                  IconButton(
                    tooltip: tr('บันทึกร่าง'),
                    onPressed: _busy || _answers.isEmpty || _done != null ? null : _saveServerDraft,
                    icon: const Icon(NxI.floppyDisk, size: 20),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: LeadRegisterQueue.instance.pending,
                    builder: (_, n, _) => n == 0
                        ? const SizedBox.shrink()
                        : TextButton.icon(
                            onPressed: () => LeadRegisterQueue.instance.flush(context.read<AppConfig>().apiClient),
                            icon: const Icon(NxI.uploadSimple, size: 18),
                            label: Text('$n'),
                          ),
                  ),
                ],
              ),
              body: SafeArea(top: false, child: content),
            ),
    );
  }

  Widget _header(Color accent, {bool big = false}) {
    final f = _form!;
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 6, decoration: BoxDecoration(gradient: LinearGradient(colors: [accent, f.theme['accent2'] != null ? leadAccent({'accent': f.theme['accent2']}) : accent]))),
        Padding(
          padding: EdgeInsets.all(big ? 24 : 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.name, style: (big ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w700)),
            if (f.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(f.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor))),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: _scanning ? null : _scanCard,
              style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.withValues(alpha: 0.1), foregroundColor: Colors.deepPurple.shade700, minimumSize: Size(0, big ? 52 : 44)),
              icon: _scanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.scanLine, size: 18),
              label: Text(_scanning ? tr('ไอแซคกำลังอ่านนามบัตร…') : tr('สแกนนามบัตร (AI) เติมข้อมูลอัตโนมัติ')),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _question(LeadQuestion q, Color accent, {bool big = false, int? number}) => LeadQuestionField(
        key: ValueKey('lr-field-${q.id}'),
        q: q,
        answers: _answers,
        onChanged: _set,
        accent: accent,
        host: _host,
        error: _errors[q.id],
        big: big,
        number: number,
        aiFilled: _aiFilled.contains(q.id),
      );

  Widget _submitButton(Color accent, {required String label, required VoidCallback onPressed, bool big = false, IconData icon = NxI.arrowRight}) => FilledButton.icon(
        onPressed: _busy ? null : onPressed,
        style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: Size(big ? 200 : 140, big ? 60 : 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, size: 20),
        label: Text(label, style: TextStyle(fontSize: big ? 18 : 15, fontWeight: FontWeight.w600)),
      );

  Widget _sectionCard(LeadSection s, Color accent, {bool big = false}) {
    final theme = Theme.of(context);
    final numbers = _numbers();
    final qs = leadVisibleQuestions(s, _answers);
    return Container(
      padding: EdgeInsets.all(big ? 22 : 18),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.title.isNotEmpty) Text(s.title, style: (big ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w700)),
        if (s.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor))),
        if (s.title.isNotEmpty || s.description.isNotEmpty) const SizedBox(height: 18),
        for (final q in qs) Padding(padding: const EdgeInsets.only(bottom: 22), child: _question(q, accent, big: big, number: numbers[q.id])),
      ]),
    );
  }

  Widget _classic(Color accent) {
    final sections = _form!.sections.where((s) => leadEvalCondition(s.showIf, _answers)).toList();
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _header(accent),
        const SizedBox(height: 12),
        for (final s in sections) Padding(padding: const EdgeInsets.only(bottom: 12), child: _sectionCard(s, accent)),
        Align(alignment: Alignment.centerLeft, child: _submitButton(accent, label: tr('ส่งคำตอบ'), onPressed: _submit, icon: NxI.check)),
      ],
    );
  }

  Widget _cards(Color accent, bool big) {
    final sections = _form!.sections;
    final s = sections[_step.clamp(0, sections.length - 1)];
    final last = leadNextSection(sections, _step, _answers) >= sections.length;
    final pct = (_step + (last ? 1 : 0)) / max(1, sections.length);
    return Column(children: [
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: big ? 820 : 720),
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(16, big ? 24 : 12, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (_step == 0) ...[_header(accent, big: big), const SizedBox(height: 12)],
                if (sections.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: max(0.06, pct), minHeight: 8, color: accent, backgroundColor: accent.withValues(alpha: 0.12)))),
                      const SizedBox(width: 10),
                      Text('${_step + 1}/${sections.length}', style: Theme.of(context).textTheme.labelMedium),
                    ]),
                  ),
                AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(s.id), child: _sectionCard(s, accent, big: big))),
              ],
            ),
          ),
        ),
      ),
      _bottomBar(
        accent,
        big: big,
        back: _history.isEmpty ? null : () => setState(() => _step = _history.removeLast()),
        next: _submitButton(accent, big: big, label: last ? tr('ส่งคำตอบ') : tr('ถัดไป'), icon: last ? NxI.paperPlaneTilt : NxI.arrowRight, onPressed: _nextSection),
      ),
    ]);
  }

  Widget _conversational(Color accent, bool big) {
    final flat = _flat();
    if (flat.isEmpty) return const SizedBox.shrink();
    final i = _step.clamp(0, flat.length - 1);
    final (q, _) = flat[i];
    final last = i >= flat.length - 1;
    return Column(children: [
      LinearProgressIndicator(value: i / flat.length, minHeight: 4, color: accent, backgroundColor: accent.withValues(alpha: 0.12)),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            if (i == 0) ...[_header(accent), const SizedBox(height: 24)] else Text(_form!.name, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).hintColor)),
            const SizedBox(height: 16),
            AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(q.id), child: _question(q, accent, big: true, number: _numbers()[q.id]))),
          ],
        ),
      ),
      _bottomBar(
        accent,
        big: big,
        back: i == 0 ? null : () => setState(() => _step = i - 1),
        next: _submitButton(accent, big: big, label: last ? tr('ส่งคำตอบ') : tr('ตกลง'), icon: last ? NxI.paperPlaneTilt : NxI.check, onPressed: _nextQuestion),
      ),
    ]);
  }

  Widget _bottomBar(Color accent, {required bool big, VoidCallback? back, required Widget next}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)))),
      child: Row(children: [
        if (back != null)
          OutlinedButton.icon(
            onPressed: back,
            style: OutlinedButton.styleFrom(minimumSize: Size(0, big ? 60 : 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(NxI.arrowLeft, size: 18),
            label: Text(tr('ย้อนกลับ')),
          ),
        const Spacer(),
        next,
      ]),
    );
  }

  Widget _welcome(Color accent) {
    final f = _form!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(f.name, textAlign: TextAlign.center, style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
          if (f.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text(f.description, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor))),
          const SizedBox(height: 40),
          _submitButton(accent, big: true, label: tr('แตะเพื่อเริ่มลงทะเบียน'), onPressed: () {
            setState(() => _started = true);
            _bumpIdle();
          }),
        ]),
      ),
    );
  }

  Widget _thankYou(Color accent) {
    final d = _done!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: (d.offline ? Colors.amber : accent).withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(d.offline ? NxI.cloud : NxI.checkCircleFill, size: 46, color: d.offline ? Colors.amber.shade700 : accent),
          ),
          const SizedBox(height: 18),
          Text(d.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(d.message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 28),
          _submitButton(accent, big: _kiosk, label: tr('ส่งคำตอบอีกครั้ง'), icon: NxI.arrowCounterClockwise, onPressed: _reset),
          if (_kiosk) Padding(padding: const EdgeInsets.only(top: 18), child: Text(tr('หน้าจอจะเริ่มใหม่อัตโนมัติ'), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))),
        ]),
      ),
    );
  }
}
