import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_exceptions.dart';
import '../../services/calls/live_transcription.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_select_tile.dart';
import '../../widgets/nx_sliding_segmented.dart';
import '../../widgets/nx_surface_card.dart';
import 'comm_ai_access.dart';
import 'comm_ai_isaac.dart';
import 'comm_ai_ops_panels.dart';
import 'comm_ai_widgets.dart';

/// Lines ISAAC can add to a prompt (same as the web settings page).
const kCommAiPromptTips = <String, List<(String, String)>>{
  'call': [
    ('สรุปสำหรับผู้บริหาร', '- เขียนใจความสำคัญให้ผู้บริหารอ่านจบใน 30 วินาที ไม่เกิน 3 ข้อ'),
    ('เน้นงานขาย', '- ระบุงบประมาณ ผู้มีอำนาจตัดสินใจ ความต้องการ และกรอบเวลาที่ลูกค้าพูดถึง (BANT)'),
    ('เน้นงานบริการ', '- ระบุอาการปัญหา อุปกรณ์/สาขาที่เกี่ยวข้อง และความเร่งด่วนของงานบริการ'),
    ('ภาษาทางการ', '- ใช้ภาษาทางการ สุภาพ เหมาะส่งต่อให้ลูกค้าได้ทันที'),
    ('ใส่ความรู้สึกลูกค้า', '- ประเมินความรู้สึกของลูกค้า (พอใจ / เฉย ๆ / ไม่พอใจ) พร้อมเหตุผลสั้น ๆ ในหัวข้อประเด็น'),
  ],
  'chat': [
    ('สรุปสำหรับผู้บริหาร', '- เขียนใจความสำคัญให้ผู้บริหารอ่านจบใน 30 วินาที ไม่เกิน 3 ข้อ'),
    ('แยกตามลูกค้า', '- ถ้าแชทพูดถึงหลายลูกค้า ให้แยกใจความสำคัญตามชื่อลูกค้า'),
    ('หาเรื่องค้าง', '- ระบุคำถามที่ยังไม่มีคนตอบ และใครควรเป็นคนตอบ'),
    ('ภาษาทางการ', '- ใช้ภาษาทางการ สุภาพ เหมาะส่งต่อในอีเมลได้ทันที'),
  ],
};

const _isaacTips = [
  'บอกว่าใครจะอ่านสรุป เช่น "ผู้จัดการฝ่ายขาย" ISAAC จะเลือกระดับรายละเอียดให้เหมาะ',
  'ระบุคำศัพท์ของธุรกิจ เช่น ชื่อสินค้า รหัสสาขา เพื่อให้สรุปใช้คำเดียวกับทีม',
  'อยากให้แนะนำงานแบบไหน เขียนไว้ได้ เช่น "ถ้าลูกค้าขอราคา ให้แนะนำเปิด Task ใบเสนอราคา"',
  'กด "ให้ ISAAC ลองสรุป" ทุกครั้งก่อนบันทึก เพื่อดูผลจริงโดยไม่กระทบผู้ใช้',
];

/// ตั้งค่า → ISAAC AI การสื่อสาร: live captions, consent, sharing / retention and the summary prompts.
/// Everyone can read it; business admins can change it (same rules as the web page).
class CommAiSettingsScreen extends StatefulWidget {
  const CommAiSettingsScreen({super.key});

  @override
  State<CommAiSettingsScreen> createState() => _CommAiSettingsScreenState();
}

class _CommAiSettingsScreenState extends State<CommAiSettingsScreen> {
  Map<String, dynamic>? _saved;
  Map<String, dynamic>? _settings;
  bool _canEdit = false;
  String? _error;
  bool _saving = false;
  final _linkDays = TextEditingController();
  final _retention = TextEditingController();
  final _summaryModel = TextEditingController();
  Map<String, dynamic>? _providers;

  /// `GET /ops/overview`: usage vs quota, my prefs, admin flag and (admins) AI health. Null until loaded / on old servers.
  Map<String, dynamic>? _ops;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOps();
  }

  Future<void> _loadOps() async {
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiOpsOverview();
      if (mounted) setState(() => _ops = r);
    } catch (_) {
      // Older server without the operations API: the page works as before.
    }
  }

  Map<String, dynamic>? get _usage => _ops?['usage'] is Map ? Map<String, dynamic>.from(_ops!['usage'] as Map) : null;

  /// Usage (everyone), AI health (admins), personal digest settings (everyone).
  List<Widget> _opsPanels() {
    final ops = _ops;
    if (ops == null) return const [];
    final health = ops['health'] is List ? [for (final x in ops['health'] as List) if (x is Map) Map<String, dynamic>.from(x)] : null;
    return [
      if (_usage != null) CommAiUsagePanel(usage: _usage!),
      if (ops['is_admin'] == true && health != null) CommAiHealthPanel(list: health),
      CommAiPersonalPanel(prefs: ops['prefs'] is Map ? Map<String, dynamic>.from(ops['prefs'] as Map) : const {}),
    ];
  }

  @override
  void dispose() {
    _linkDays.dispose();
    _retention.dispose();
    _summaryModel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiSettings();
      if (!mounted) return;
      final s = r['settings'] is Map ? Map<String, dynamic>.from(r['settings'] as Map) : <String, dynamic>{};
      setState(() {
        _saved = Map<String, dynamic>.from(s);
        _settings = s;
        _canEdit = r['can_edit'] == true;
        _linkDays.text = '${s['share_link_max_days'] ?? 30}';
        _retention.text = '${s['retention_days'] ?? 365}';
        _summaryModel.text = '${s['summary_model'] ?? ''}';
      });
      if (_canEdit) _loadProviders();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  /// AI providers / models for the admin panel (which keys are set).
  Future<void> _loadProviders() async {
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiProviders();
      if (mounted) setState(() => _providers = r);
    } catch (_) {
      if (mounted) setState(() => _providers = const {});
    }
  }

  bool get _dirty => _settings != null && jsonEncode(_settings) != jsonEncode(_saved);

  void _set(String k, dynamic v) => setState(() => _settings![k] = v);

  Future<void> _save() async {
    final s = _settings;
    if (s == null) return;
    setState(() => _saving = true);
    try {
      final r = await context.read<AppConfig>().apiClient.saveCommAiSettings(s);
      if (!mounted) return;
      final out = r['settings'] is Map ? Map<String, dynamic>.from(r['settings'] as Map) : s;
      setState(() {
        _saved = Map<String, dynamic>.from(out);
        _settings = Map<String, dynamic>.from(out);
        _linkDays.text = '${out['share_link_max_days']}';
        _retention.text = '${out['retention_days']}';
        _summaryModel.text = '${out['summary_model'] ?? ''}';
      });
      CommAiAccess.invalidate(context.read<AppConfig>().apiClient);
      // Calls on this phone pick the new rules up right away.
      LiveTranscription.instance.settings = Map<String, dynamic>.from(out);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกการตั้งค่าแล้ว'))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _switch(String key, String title, {String? desc}) {
    return SwitchListTile.adaptive(
      key: ValueKey('comm-ai-setting-$key'),
      contentPadding: EdgeInsets.zero,
      value: _settings![key] == true,
      onChanged: _canEdit ? (v) => _set(key, v) : null,
      title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: desc == null ? null : Text(tr(desc), style: const TextStyle(fontSize: 12.5)),
    );
  }

  Widget _panel({required IconData icon, required String title, String? desc, required List<Widget> children}) {
    final theme = Theme.of(context);
    return NxSurfaceCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: kIsaacIndigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: kIsaacIndigo),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(title), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (desc != null) Text(tr(desc), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _number(TextEditingController c, String key, String label, {String? helper, int min = 0, int max = 3650}) {
    return TextField(
      key: ValueKey('comm-ai-setting-$key'),
      controller: c,
      enabled: _canEdit,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: tr(label), helperText: helper == null ? null : tr(helper)),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null) _set(key, n.clamp(min, max));
      },
    );
  }

  List<Widget> _left() {
    final s = _settings!;
    return [
      _panel(icon: NxI.microphone, title: 'ถอดบทสนทนาสด', desc: 'คำบรรยายสดระหว่างโทรและวิดีโอคอล ทั้งเดี่ยวและกลุ่ม', children: [
        _switch('stt_enabled', 'เปิดให้ ISAAC จดบทสนทนา', desc: 'ปิด = ไม่ถามและไม่ถอดเสียงในทุกสาย'),
        const SizedBox(height: 6),
        Text(tr('ใครเป็นคนตัดสินใจ'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        NxSelectTile(
          key: const ValueKey('comm-ai-consent-individual'),
          title: 'แต่ละคนเลือกเอง (แนะนำ)',
          subtitle: 'ทุกคนถูกถามก่อน เสียงของใครถูกถอดเมื่อคนนั้นยินยอม — ปลอดภัยตาม PDPA',
          leading: const Icon(NxI.userCheck, color: kIsaacIndigo),
          selected: s['consent_mode'] != 'caller',
          onTap: _canEdit ? () => _set('consent_mode', 'individual') : null,
        ),
        const SizedBox(height: 8),
        NxSelectTile(
          key: const ValueKey('comm-ai-consent-caller'),
          title: 'ผู้โทรตัดสินใจ',
          subtitle: 'ผู้เริ่มสายเปิดแล้วทุกคนถูกถอด และเห็นแจ้งเตือนชัดเจนตลอดสาย',
          leading: const Icon(NxI.users, color: kIsaacIndigo),
          selected: s['consent_mode'] == 'caller',
          onTap: _canEdit ? () => _set('consent_mode', 'caller') : null,
        ),
        const SizedBox(height: 4),
        _switch('ask_every_call', 'ถามก่อนทุกครั้ง', desc: 'ปิด = ใช้ตัวเลือกที่ผู้ใช้กด "จำการเลือกนี้" ไว้'),
        _switch('share_captions_default', 'ให้คู่สายเห็นข้อความเป็นค่าเริ่มต้น'),
        _switch('record_audio', 'บันทึกเสียงไว้ฟังย้อนหลัง', desc: 'เฉพาะคนที่ยินยอม · เก็บแบบส่วนตัว เปิดได้ผ่านสิทธิ์เท่านั้น'),
        _switch('auto_summary', 'ให้ ISAAC สรุปอัตโนมัติหลังวางสาย'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: const ValueKey('comm-ai-setting-language'),
          initialValue: ['th', 'en', 'auto'].contains(s['language']) ? '${s['language']}' : 'th',
          decoration: InputDecoration(labelText: tr('ภาษาที่พูดในสาย')),
          items: [
            DropdownMenuItem(value: 'th', child: Text(tr('ไทย'))),
            const DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'auto', child: Text(tr('ตรวจจับอัตโนมัติ'))),
          ],
          onChanged: _canEdit ? (v) => _set('language', v ?? 'th') : null,
        ),
      ]),
      if (_canEdit) _aiPanel(),
      _panel(icon: NxI.shareNetwork, title: 'การแชร์และการเก็บข้อมูล', desc: 'ควบคุมการส่งบทสนทนา เสียง และสรุปออกไปภายนอก', children: [
        _switch('share_email_enabled', 'แชร์ทางอีเมล'),
        _switch('share_link_enabled', 'ลิงก์แชร์ภายนอก', desc: 'เปิดได้โดยไม่ต้องล็อกอิน ตั้งวันหมดอายุ/รหัสผ่าน และยกเลิกได้'),
        _switch('admins_see_all', 'ผู้ดูแลเห็นประวัติทั้งธุรกิจ', desc: 'ปิด = เห็นเฉพาะผู้อยู่ในสาย/ห้องแชท'),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _number(_linkDays, 'share_link_max_days', 'อายุลิงก์สูงสุด (วัน)', min: 1, max: 365)),
          const SizedBox(width: 12),
          Expanded(child: _number(_retention, 'retention_days', 'เก็บบทสนทนาและเสียง (วัน)', helper: '0 = เก็บตลอด')),
        ]),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final Widget body;
    if (_error != null) {
      body = Center(child: CommAiIsaacState(mood: 'error', title: 'โหลดการตั้งค่าไม่ได้', message: _error, action: OutlinedButton(onPressed: _load, child: Text(tr('ลองใหม่')))));
    } else if (s == null) {
      body = const Center(child: CommAiIsaacState(mood: 'loading', title: 'ISAAC กำลังเปิดการตั้งค่า…', busy: true));
    } else {
      final on = s['stt_enabled'] == true;
      final hero = CommAiHero(
        mood: on ? 'listening' : 'sleepy',
        title: 'ISAAC AI การสื่อสาร',
        subtitle: 'ให้ ISAAC ฟังสายโทรและวิดีโอคอล เขียนคำบรรยายสด สรุปหลังวางสาย และสรุปแชทตามช่วงเวลา',
        footer: Wrap(spacing: 6, runSpacing: 6, children: [
          _chip(on ? 'ISAAC พร้อมจดบทสนทนา' : 'ปิดการถอดเสียงอยู่', on ? const Color(0xFF059669) : const Color(0xFF64748B)),
          _chip(s['consent_mode'] == 'caller' ? 'ผู้โทรตัดสินใจ' : 'แต่ละคนเลือกเอง', kIsaacIndigo),
          if (s['record_audio'] == true) _chip('บันทึกเสียง', kIsaacViolet),
          if (!_canEdit) _chip('ดูอย่างเดียว — เฉพาะผู้ดูแลแก้ไขได้', const Color(0xFFD97706)),
        ]),
      );
      final prompts = PromptEditorCard(canEdit: _canEdit);
      body = LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final pad = EdgeInsets.fromLTRB(16, 8, 16, _dirty ? 96 : 32);
        if (wide) {
          return ListView(padding: pad, children: [
            CommAiQuotaNotice(usage: _usage),
            hero,
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: Column(children: [..._opsPanels(), ..._left()])),
              const SizedBox(width: 14),
              Expanded(flex: 7, child: Column(children: [prompts, _tipsPanel()])),
            ]),
          ]);
        }
        return ListView(padding: pad, children: [CommAiQuotaNotice(usage: _usage), hero, const SizedBox(height: 14), ..._opsPanels(), ..._left(), prompts, _tipsPanel()]);
      });
    }
    return NxScrollScaffold(
      header: const NxAppHeader(title: 'ISAAC AI การสื่อสาร', subtitle: 'ตั้งค่าการถอดเสียงและการสรุป'),
      body: Stack(children: [
        Positioned.fill(child: body),
        if (_dirty && _canEdit)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 16,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(children: [
                  Expanded(child: Text(tr('มีการเปลี่ยนแปลงที่ยังไม่บันทึก'), style: const TextStyle(fontWeight: FontWeight.w600))),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _settings = Map<String, dynamic>.from(_saved!);
                              _linkDays.text = '${_saved!['share_link_max_days']}';
                              _retention.text = '${_saved!['retention_days']}';
                              _summaryModel.text = '${_saved!['summary_model'] ?? ''}';
                            }),
                    child: Text(tr('ยกเลิก')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('comm-ai-settings-save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.check, size: 18),
                    label: Text(tr('บันทึก')),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /// Admins: the transcription model and the provider / model that writes summaries (same as the web).
  Widget _aiPanel() {
    final s = _settings!;
    final p = _providers;
    final providers = [for (final x in (p?['providers'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final stt = [for (final m in (p?['stt_models'] as List? ?? const ['gpt-4o-transcribe', 'gpt-4o-mini-transcribe', 'whisper-1'])) '$m'];
    final sttValue = '${s['stt_model'] ?? ''}'.isEmpty ? 'gpt-4o-transcribe' : '${s['stt_model']}';
    final provider = '${s['summary_provider'] ?? ''}';
    final models = [for (final m in (providers.where((x) => x['id'] == provider).firstOrNull?['models'] as List? ?? const [])) '$m'];
    return _panel(icon: NxI.sparkle, title: 'AI ที่ ISAAC ใช้', desc: 'เลือกโมเดลถอดเสียงและผู้ให้บริการสำหรับเขียนสรุป', children: [
      if (p == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (p != null) ...[
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          key: const ValueKey('comm-ai-stt-model'),
          isExpanded: true,
          initialValue: stt.contains(sttValue) ? sttValue : null,
          decoration: InputDecoration(
            labelText: tr('โมเดลถอดเสียง (OpenAI)'),
            helperText: tr(p['stt_ready'] == false ? 'ยังไม่ได้ใส่ OpenAI API key — ตั้งค่า → AI' : 'gpt-4o-transcribe แม่นที่สุด · mini ประหยัดกว่า'),
            helperMaxLines: 2,
          ),
          items: [for (final m in stt) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: (v) => _set('stt_model', v ?? sttValue),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('comm-ai-summary-provider'),
          isExpanded: true,
          initialValue: provider.isEmpty || providers.any((x) => x['id'] == provider) ? provider : '',
          decoration: InputDecoration(labelText: tr('ผู้ให้บริการสำหรับสรุป')),
          items: [
            DropdownMenuItem(value: '', child: Text('${tr('ค่าเริ่มต้นของระบบ')} (${p['default_provider'] ?? 'auto'})', overflow: TextOverflow.ellipsis)),
            for (final x in providers)
              DropdownMenuItem(
                value: '${x['id']}',
                child: Text('${x['label']}${x['configured'] == true ? '' : ' — ${tr('ยังไม่ได้ตั้งค่า key')}'}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if ((v ?? '') == provider) return;
            setState(() {
              _settings!['summary_provider'] = v ?? '';
              _settings!['summary_model'] = '';
              _summaryModel.text = '';
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('comm-ai-summary-model'),
          controller: _summaryModel,
          decoration: InputDecoration(
            labelText: tr('โมเดลสำหรับสรุป'),
            helperText: tr('เว้นว่าง = โมเดลเริ่มต้นของผู้ให้บริการ'),
            hintText: models.isEmpty ? null : models.first,
            suffixIcon: models.isEmpty
                ? null
                : PopupMenuButton<String>(
                    key: const ValueKey('comm-ai-summary-model-pick'),
                    tooltip: tr('โมเดลที่แนะนำ'),
                    icon: const Icon(NxI.caretDown, size: 18),
                    onSelected: (m) {
                      _summaryModel.text = m;
                      _set('summary_model', m);
                    },
                    itemBuilder: (_) => [for (final m in models) PopupMenuItem(value: m, child: Text(m))],
                  ),
          ),
          onChanged: (v) => _set('summary_model', v.trim()),
        ),
      ],
    ]);
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Text(tr(text), style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _tipsPanel() => _panel(icon: NxI.lightning, title: 'เคล็ดลับจาก ISAAC', children: [
        for (final t in _isaacTips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 2, right: 8), child: Icon(NxI.sparkle, size: 14, color: kIsaacViolet)),
              Expanded(child: Text(tr(t), style: const TextStyle(fontSize: 13, height: 1.45))),
            ]),
          ),
      ]);
}

/// The call / chat summary prompt: edit, add ISAAC's suggested lines, test on a sample (or your own text), reset.
class PromptEditorCard extends StatefulWidget {
  const PromptEditorCard({super.key, required this.canEdit});
  final bool canEdit;

  @override
  State<PromptEditorCard> createState() => _PromptEditorCardState();
}

class _PromptEditorCardState extends State<PromptEditorCard> {
  String _kind = 'call';
  Map<String, dynamic>? _prompts;
  int _max = 8000;
  final _text = TextEditingController();
  final _sample = TextEditingController();
  bool _ownSample = false;
  String? _busy;
  Map<String, dynamic>? _test;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _sample.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _cur => _prompts?[_kind] is Map ? Map<String, dynamic>.from(_prompts![_kind] as Map) : const {};

  Future<void> _load() async {
    try {
      final r = await context.read<AppConfig>().apiClient.getCommAiPrompts();
      if (!mounted) return;
      setState(() {
        _prompts = r['prompts'] is Map ? Map<String, dynamic>.from(r['prompts'] as Map) : {};
        _max = (r['max_chars'] as num?)?.toInt() ?? 8000;
        _text.text = '${_cur['prompt'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _msg = formatApiError(e));
    }
  }

  void _switchKind(String k) => setState(() {
        _kind = k;
        _text.text = '${_cur['prompt'] ?? ''}';
        _test = null;
        _msg = null;
      });

  bool get _dirty => _text.text.trim() != '${_cur['prompt'] ?? ''}'.trim();

  void _addTip(String line) {
    final t = _text.text.trimRight();
    _text.text = t.isEmpty ? line : '$t\n$line';
  }

  Future<void> _run(String what, Future<void> Function() fn) async {
    setState(() {
      _busy = what;
      _msg = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _msg = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _stored(Map<String, dynamic> out) {
    setState(() {
      _prompts = {...?_prompts, _kind: {..._cur, ...out}};
      _text.text = '${out['prompt'] ?? _text.text}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<AppConfig>().apiClient;
    final tips = kCommAiPromptTips[_kind]!;
    return NxSurfaceCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const IsaacAvatar(mood: 'explaining', size: 36, ring: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Prompt การสรุปของ ISAAC'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(tr('ISAAC ตอบเป็น 4 หัวข้อเสมอ — เขียนเพิ่มเฉพาะสิ่งที่อยากให้เน้น'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        NxSlidingSegmented<String>(
          value: _kind,
          options: const [('call', 'สรุปการโทร', NxI.phone), ('chat', 'สรุปแชท', NxI.chatCircle)],
          onChanged: _switchKind,
        ),
        const SizedBox(height: 12),
        if (_prompts == null && _msg == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          Row(children: [
            Expanded(child: Text(tr('คำสั่งให้ ISAAC สรุป'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Text(_cur['is_default'] == true ? tr('ค่าเริ่มต้น') : '${tr('ปรับแล้ว')} v${_cur['version'] ?? ''}', style: TextStyle(fontSize: 12, color: theme.hintColor)),
          ]),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('comm-ai-prompt-text'),
            controller: _text,
            enabled: widget.canEdit,
            minLines: 8,
            maxLines: 18,
            maxLength: _max,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
            decoration: const InputDecoration(alignLabelWithHint: true),
          ),
          if (widget.canEdit) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kIsaacViolet.withValues(alpha: 0.25)),
                color: kIsaacViolet.withValues(alpha: 0.04),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(NxI.sparkle, size: 14, color: kIsaacViolet),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr('ISAAC แนะนำ — แตะเพื่อเพิ่มลงใน Prompt'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kIsaacViolet))),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (label, line) in tips)
                    ActionChip(
                      label: Text('+ ${tr(label)}'),
                      onPressed: _text.text.contains(line) ? null : () => _addTip(line),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey('comm-ai-prompt-own-sample'),
              contentPadding: EdgeInsets.zero,
              value: _ownSample,
              onChanged: (v) => setState(() => _ownSample = v),
              title: Text(tr('ทดสอบกับบทสนทนาของฉัน'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(tr('ปิดไว้ = ใช้บทสนทนาตัวอย่างของระบบ'), style: const TextStyle(fontSize: 12.5)),
            ),
            if (_ownSample)
              TextField(
                key: const ValueKey('comm-ai-prompt-sample'),
                controller: _sample,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(labelText: tr('บทสนทนา'), hintText: tr('ชื่อ: ข้อความ (บรรทัดละประโยค)'), alignLabelWithHint: true),
              ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                key: const ValueKey('comm-ai-prompt-save'),
                onPressed: _busy != null || !_dirty || _text.text.trim().isEmpty
                    ? null
                    : () => _run('save', () async {
                          final out = await api.saveCommAiPrompt(_kind, prompt: _text.text.trim());
                          _stored(out);
                          _msg = tr('บันทึก Prompt แล้ว');
                        }),
                icon: _busy == 'save' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.check, size: 18),
                label: Text(tr('บันทึก')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('comm-ai-prompt-test'),
                onPressed: _busy != null || _text.text.trim().isEmpty
                    ? null
                    : () => _run('test', () async {
                          final r = await api.testCommAiPrompt(_kind, prompt: _text.text.trim(), sample: _ownSample ? _sample.text : null);
                          if (mounted) setState(() => _test = r);
                        }),
                icon: _busy == 'test' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.sparkle, size: 18),
                label: Text(tr('ให้ ISAAC ลองสรุป')),
              ),
              TextButton.icon(
                key: const ValueKey('comm-ai-prompt-reset'),
                onPressed: _busy != null || _cur['is_default'] == true
                    ? null
                    : () => _run('reset', () async {
                          final out = await api.saveCommAiPrompt(_kind, reset: true);
                          _stored({...out, 'prompt': out['prompt'] ?? _cur['default_prompt']});
                          _msg = tr('คืนค่าเริ่มต้นแล้ว');
                        }),
                icon: const Icon(NxI.arrowsClockwise, size: 18),
                label: Text(tr('คืนค่าเริ่มต้น')),
              ),
            ]),
          ],
          if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))),
          if (_busy == 'test')
            const CommAiIsaacState(mood: 'reading', title: 'ISAAC กำลังลองสรุปด้วย Prompt นี้…', busy: true, size: 72),
          if (_test != null && _busy != 'test' && _test!['result'] is Map) ...[
            const SizedBox(height: 12),
            Text('${tr('ผลทดสอบ (ไม่บันทึก)')} · ${((_test!['ms'] as num? ?? 0) / 1000).toStringAsFixed(1)} ${tr('วินาที')}', style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(height: 6),
            CommAiSummaryView(key: const ValueKey('comm-ai-prompt-result'), result: Map<String, dynamic>.from(_test!['result'] as Map), showSource: false),
          ],
        ],
      ]),
    );
  }
}
