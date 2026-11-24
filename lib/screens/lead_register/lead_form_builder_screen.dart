import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/lead_register/lead_form.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_icons.dart';
import 'lead_form_fill_screen.dart';
import 'lead_form_renderer.dart';

/// Native form builder: questions of every UI type (add / edit / reorder /
/// duplicate / delete), sections, layout + settings, and the auto flow.
/// Changes save automatically.
class LeadFormBuilderScreen extends StatefulWidget {
  const LeadFormBuilderScreen({super.key, required this.formId});
  final int formId;
  @override
  State<LeadFormBuilderScreen> createState() => _LeadFormBuilderScreenState();
}

class _LeadFormBuilderScreenState extends State<LeadFormBuilderScreen> {
  Map<String, dynamic>? _f;
  Timer? _debounce;
  bool _saving = false;
  bool _dirty = false;
  List<Map<String, dynamic>> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_dirty) _save();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    final f = await api.getLeadForm(widget.formId);
    if (mounted) setState(() => _f = f);
    try {
      final u = await api.getUsers(q: '');
      if (mounted) setState(() => _users = u);
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _sections {
    final q = _f!['questions'];
    final list = q is Map ? q['sections'] : null;
    return (list as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  void _setSections(List<Map<String, dynamic>> s) => _change(() => _f!['questions'] = {'sections': s});

  void _change(VoidCallback fn) {
    setState(fn);
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_f == null || !_dirty) return;
    _dirty = false;
    if (mounted) setState(() => _saving = true);
    try {
      final body = {for (final k in ['name', 'description', 'ui_type', 'theme', 'settings', 'questions', 'flow', 'smownerid']) k: _f![k]};
      final saved = await context.read<AppConfig>().apiClient.updateLeadForm(widget.formId, body);
      if (mounted) setState(() => _f!['status'] = saved['status']);
    } catch (e) {
      _dirty = true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('บันทึกไม่สำเร็จ'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    return DefaultTabController(
      length: 3,
      child: NxScrollScaffold(
        motionBlur: false,
        header: NxAppHeader(
          title: tr('แก้ไขแบบฟอร์ม'),
          subtitle: _saving ? tr('กำลังบันทึก…') : _dirty ? tr('มีการแก้ไข…') : tr('บันทึกแล้ว'),
          actions: [
            IconButton(
              tooltip: tr('ทดลองกรอก'),
              icon: const Icon(NxI.eye),
              onPressed: f == null
                  ? null
                  : () async {
                      await _save();
                      if (context.mounted) nxPush<void>(context, LeadFormFillScreen(formId: widget.formId));
                    },
            ),
            if (f != null && f['status'] != 'published')
              TextButton(
                onPressed: () async {
                  await _save();
                  if (!context.mounted) return;
                  final nf = await context.read<AppConfig>().apiClient.setLeadFormStatus(widget.formId, publish: true);
                  setState(() => _f!['status'] = nf['status']);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('เผยแพร่แล้ว'))));
                },
                child: Text(tr('เผยแพร่')),
              ),
          ],
        ),
        headerBottomHeight: 46,
        headerBottom: TabBar(dividerColor: Colors.transparent, tabs: [Tab(text: tr('คำถาม')), Tab(text: tr('ตั้งค่า')), const Tab(text: 'Flow')]),
        body: f == null ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [_questionsTab(), _settingsTab(), _flowTab()]),
      ),
    );
  }

  // ------------------------------------------------------------------ questions

  Widget _questionsTab() {
    final f = _f!;
    final sections = _sections;
    final theme = Theme.of(context);
    final accent = leadAccent(f['theme'] is Map ? Map<String, dynamic>.from(f['theme'] as Map) : const {});
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(height: 6, color: accent),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                TextFormField(
                  initialValue: f['name']?.toString(),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, hintText: tr('ชื่อแบบฟอร์ม')),
                  onChanged: (v) => _change(() => f['name'] = v),
                ),
                TextFormField(
                  initialValue: f['description']?.toString(),
                  maxLines: null,
                  decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, hintText: tr('คำอธิบาย')),
                  onChanged: (v) => _change(() => f['description'] = v),
                ),
              ]),
            ),
          ]),
        ),
        for (final (si, s) in sections.indexed) ...[
          const SizedBox(height: 12),
          _sectionHeader(si, s, sections),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (a, b) {
              final qs = [...(s['questions'] as List? ?? const [])];
              qs.insert(b, qs.removeAt(a));
              sections[si] = {...s, 'questions': qs};
              _setSections(sections);
            },
            children: [
              for (final (qi, raw) in ((s['questions'] as List?) ?? const []).whereType<Map>().indexed)
                _questionTile(key: ValueKey('b-${raw['id']}'), si: si, qi: qi, q: LeadQuestion(Map<String, dynamic>.from(raw)), sections: sections),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => _addQuestion(si), icon: const Icon(NxI.plus, size: 18), label: Text(tr('เพิ่มคำถาม'))),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final s = _sections..add({'id': 's_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}', 'title': tr('ส่วนใหม่'), 'questions': <Map<String, dynamic>>[]});
            _setSections(s);
          },
          icon: const Icon(NxI.plus),
          label: Text(tr('เพิ่มส่วน')),
        ),
      ],
    );
  }

  Widget _sectionHeader(int si, Map<String, dynamic> s, List<Map<String, dynamic>> sections) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Text('${si + 1}', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            key: ValueKey('st-${s['id']}'),
            initialValue: s['title']?.toString(),
            decoration: InputDecoration(border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, hintText: tr('ชื่อส่วน')),
            style: const TextStyle(fontWeight: FontWeight.w600),
            onChanged: (v) {
              sections[si] = {...s, 'title': v};
              _setSections(sections);
            },
          ),
        ),
        if (sections.length > 1)
          IconButton(
            icon: const Icon(NxI.trash, size: 18),
            onPressed: () {
              sections.removeAt(si);
              _setSections(sections);
            },
          ),
      ]),
    );
  }

  Widget _questionTile({required Key key, required int si, required int qi, required LeadQuestion q, required List<Map<String, dynamic>> sections}) {
    final theme = Theme.of(context);
    final mapLabel = q.mapTo != null ? kLeadMapTargets[q.mapTo] : null;
    return Card(
      key: key,
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 4),
        leading: ReorderableDragStartListener(index: qi, child: const Padding(padding: EdgeInsets.all(8), child: Icon(NxI.dotsSixVertical))),
        title: Text('${q.label}${q.required ? ' *' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [tr(leadTypeLabel(q.uitype)), if (q.options.isNotEmpty) '${q.options.length} ${tr('ตัวเลือก')}', if (mapLabel != null) '→ ${tr(mapLabel)}', if (q.staffOnly) tr('เฉพาะพนักงาน'), if (q.showIf != null) tr('มีเงื่อนไข')].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _editQuestion(si, qi),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            final qs = [...(sections[si]['questions'] as List)];
            if (v == 'dup') qs.insert(qi + 1, {...q.raw, 'id': 'q_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}', 'label': '${q.label} (copy)'});
            if (v == 'del') qs.removeAt(qi);
            sections[si] = {...sections[si], 'questions': qs};
            _setSections(sections);
          },
          itemBuilder: (_) => [PopupMenuItem(value: 'dup', child: Text(tr('ทำสำเนา'))), PopupMenuItem(value: 'del', child: Text(tr('ลบ')))],
        ),
      ),
    );
  }

  Future<void> _addQuestion(int si) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(tr('เลือกชนิดคำถาม'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            for (final e in kLeadTypeGroups.entries) ...[
              Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(tr(e.key), style: Theme.of(ctx).textTheme.labelMedium?.copyWith(color: Theme.of(ctx).hintColor))),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (t, l) in e.value) ActionChip(label: Text(tr(l)), onPressed: () => Navigator.pop(ctx, t)),
              ]),
            ],
          ],
        ),
      ),
    );
    if (type == null) return;
    final sections = _sections;
    final qs = [...(sections[si]['questions'] as List? ?? const []), leadNewQuestion(type)];
    sections[si] = {...sections[si], 'questions': qs};
    _setSections(sections);
    _editQuestion(si, qs.length - 1);
  }

  Future<void> _editQuestion(int si, int qi) async {
    final sections = _sections;
    final raw = Map<String, dynamic>.from((sections[si]['questions'] as List)[qi] as Map);
    final all = sections.expand((s) => (s['questions'] as List? ?? const []).whereType<Map>()).map((m) => LeadQuestion(Map<String, dynamic>.from(m))).toList();
    final out = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => _QuestionEditor(initial: raw, others: all.where((q) => q.id != raw['id'] && !q.displayOnly).toList())),
    );
    if (out == null) return;
    final s2 = _sections;
    final qs = [...(s2[si]['questions'] as List)];
    qs[qi] = out;
    s2[si] = {...s2[si], 'questions': qs};
    _setSections(s2);
  }

  // ------------------------------------------------------------------ settings

  Widget _settingsTab() {
    final f = _f!;
    final s = f['settings'] is Map ? Map<String, dynamic>.from(f['settings'] as Map) : <String, dynamic>{};
    final theme = f['theme'] is Map ? Map<String, dynamic>.from(f['theme'] as Map) : <String, dynamic>{};
    void setS(String k, dynamic v) => _change(() => f['settings'] = {...s, k: v});
    const layouts = [('classic', 'คลาสสิก', 'คำถามทั้งหมดในหน้าเดียว'), ('card', 'การ์ดทีละส่วน', 'ทีละส่วนพร้อมแถบความคืบหน้า'), ('conversational', 'ทีละคำถาม', 'ถามทีละข้อ'), ('kiosk', 'คีออสก์', 'ปุ่มใหญ่ รีเซ็ตอัตโนมัติ')];
    const colors = ['#0F1C33', '#6366F1', '#0253CD', '#06B6D4', '#10B981', '#F59E0B', '#F97316', '#E11D48', '#DB2777', '#7C3AED'];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      Text(tr('รูปแบบการแสดงผล (UI Type)'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      RadioGroup<String>(
        groupValue: f['ui_type']?.toString() ?? 'classic',
        onChanged: (v) => _change(() => f['ui_type'] = v),
        child: Column(children: [
          for (final (k, l, d) in layouts) RadioListTile<String>(value: k, title: Text(tr(l)), subtitle: Text(tr(d)), contentPadding: EdgeInsets.zero),
        ]),
      ),
      const Divider(),
      Text(tr('สีหลัก'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in colors)
          GestureDetector(
            onTap: () => _change(() => f['theme'] = {...theme, 'accent': c}),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: leadAccent({'accent': c}),
              child: theme['accent'] == c ? const Icon(NxI.check, color: Colors.white, size: 18) : null,
            ),
          ),
      ]),
      const Divider(height: 32),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: s['accept_responses'] != false, onChanged: (v) => setS('accept_responses', v), title: Text(tr('เปิดรับคำตอบ'))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: s['allow_multiple'] != false, onChanged: (v) => setS('allow_multiple', v), title: Text(tr('ตอบได้หลายครั้ง')), subtitle: Text(tr('Lead เดิมตอบซ้ำได้ ทุกคำตอบผูกกับ Lead เดียวกัน'))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: s['allow_edit'] != false, onChanged: (v) => setS('allow_edit', v), title: Text(tr('ให้ผู้ตอบแก้ไขคำตอบได้'))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: s['require_consent'] == true, onChanged: (v) => setS('require_consent', v), title: Text(tr('บังคับยินยอม PDPA'))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: s['show_progress'] != false, onChanged: (v) => setS('show_progress', v), title: Text(tr('แสดงแถบความคืบหน้า'))),
      const SizedBox(height: 8),
      TextFormField(initialValue: s['thank_you_title']?.toString(), decoration: InputDecoration(labelText: tr('หัวข้อหน้าขอบคุณ')), onChanged: (v) => setS('thank_you_title', v)),
      const SizedBox(height: 8),
      TextFormField(initialValue: s['thank_you_message']?.toString(), maxLines: 2, decoration: InputDecoration(labelText: tr('ข้อความหน้าขอบคุณ')), onChanged: (v) => setS('thank_you_message', v)),
      const SizedBox(height: 16),
      Text(tr('โหมดคีออสก์'), style: const TextStyle(fontWeight: FontWeight.w700)),
      Row(children: [
        Expanded(child: TextFormField(initialValue: '${s['kiosk_reset_seconds'] ?? 10}', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('เริ่มใหม่หลังส่ง (วินาที)')), onChanged: (v) => setS('kiosk_reset_seconds', int.tryParse(v) ?? 10))),
        const SizedBox(width: 12),
        Expanded(child: TextFormField(initialValue: s['kiosk_exit_pin']?.toString(), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: tr('PIN ออก')), onChanged: (v) => setS('kiosk_exit_pin', v))),
      ]),
    ]);
  }

  // ------------------------------------------------------------------ flow

  Widget _flowTab() {
    final f = _f!;
    final flow = f['flow'] is Map ? Map<String, dynamic>.from(f['flow'] as Map) : <String, dynamic>{};
    Map<String, dynamic> step(String k) => flow[k] is Map ? Map<String, dynamic>.from(flow[k] as Map) : <String, dynamic>{};
    void setStep(String k, Map<String, dynamic> patch) => _change(() => f['flow'] = {...flow, k: {...step(k), ...patch}});
    final lead = step('lead');
    final owner = lead['owner'] is Map ? Map<String, dynamic>.from(lead['owner'] as Map) : <String, dynamic>{'mode': 'form_owner'};
    String uname(Map<String, dynamic> u) => [u['first_name'], u['last_name']].where((x) => x != null && '$x'.isNotEmpty).join(' ').trim().isEmpty ? '${u['user_name'] ?? u['id']}' : [u['first_name'], u['last_name']].where((x) => x != null).join(' ');
    final users = [for (final u in _users) DropdownMenuItem<int>(value: (u['id'] as num?)?.toInt(), child: Text(uname(u), overflow: TextOverflow.ellipsis))];
    Widget card(String k, String title, IconData icon, Color color, List<Widget> children) {
      final on = step(k)['enabled'] != false;
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Column(children: [
            SwitchListTile(
              value: on,
              onChanged: (v) => setStep(k, {'enabled': v}),
              secondary: CircleAvatar(backgroundColor: on ? color : Theme.of(context).disabledColor, child: Icon(icon, size: 18, color: Colors.white)),
              title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (on) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(children: children)),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      card('lead', 'สร้าง Lead อัตโนมัติ', NxI.userPlus, const Color(0xFF6366F1), [
        DropdownButtonFormField<String>(
          initialValue: owner['mode']?.toString() ?? 'form_owner',
          decoration: InputDecoration(labelText: tr('เจ้าของ Lead')),
          items: [
            DropdownMenuItem(value: 'form_owner', child: Text(tr('เจ้าของแบบฟอร์ม'))),
            DropdownMenuItem(value: 'user', child: Text(tr('ผู้ใช้ที่กำหนด'))),
            DropdownMenuItem(value: 'round_robin', child: Text(tr('วนตามคิว (Round-robin)'))),
            DropdownMenuItem(value: 'by_answer', child: Text(tr('ตามคำตอบ'))),
          ],
          onChanged: (v) => setStep('lead', {'owner': {...owner, 'mode': v}}),
        ),
        if (owner['mode'] == 'user')
          DropdownButtonFormField<int>(initialValue: (owner['user_id'] as num?)?.toInt(), items: users, decoration: InputDecoration(labelText: tr('ผู้ใช้')), onChanged: (v) => setStep('lead', {'owner': {...owner, 'user_id': v}})),
        if (owner['mode'] == 'form_owner')
          DropdownButtonFormField<int>(initialValue: (f['smownerid'] as num?)?.toInt(), items: users, decoration: InputDecoration(labelText: tr('เจ้าของแบบฟอร์ม')), onChanged: (v) => _change(() => f['smownerid'] = v)),
        DropdownButtonFormField<String>(
          initialValue: lead['duplicate']?.toString() ?? 'attach',
          decoration: InputDecoration(labelText: tr('ถ้ามี Lead อีเมล/เบอร์เดียวกัน')),
          items: [
            DropdownMenuItem(value: 'attach', child: Text(tr('ผูกกับ Lead เดิม (แนะนำ)'))),
            DropdownMenuItem(value: 'create', child: Text(tr('สร้าง Lead ใหม่ทุกครั้ง'))),
          ],
          onChanged: (v) => setStep('lead', {'duplicate': v}),
        ),
        TextFormField(initialValue: lead['lead_source']?.toString(), decoration: InputDecoration(labelText: tr('แหล่งที่มา (Lead source)')), onChanged: (v) => setStep('lead', {'lead_source': v})),
      ]),
      card('email', 'ส่งอีเมล Salesheet', NxI.envelope, const Color(0xFF0EA5E9), [
        TextFormField(initialValue: step('email')['subject']?.toString(), decoration: InputDecoration(labelText: tr('หัวเรื่อง')), onChanged: (v) => setStep('email', {'subject': v})),
        TextFormField(initialValue: step('email')['intro']?.toString(), maxLines: 3, decoration: InputDecoration(labelText: tr('ข้อความ'), helperText: '{first_name} {company} {form}'), onChanged: (v) => setStep('email', {'intro': v})),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: step('email')['notify_owner'] != false, onChanged: (v) => setStep('email', {'notify_owner': v}), title: Text(tr('แจ้งเตือนเจ้าของ Lead'))),
        Text(tr('อัปโหลดไฟล์ Salesheet ได้จากหน้าเว็บ (แท็บ Flow)'), style: Theme.of(context).textTheme.bodySmall),
      ]),
      card('deal', 'สร้าง Deal อัตโนมัติ', NxI.handshake, const Color(0xFFF59E0B), [
        TextFormField(initialValue: step('deal')['name_template']?.toString(), decoration: InputDecoration(labelText: tr('ชื่อ Deal'), helperText: '{company} {name} {form}'), onChanged: (v) => setStep('deal', {'name_template': v})),
        DropdownButtonFormField<String>(
          initialValue: step('deal')['stage']?.toString() ?? 'Qualification',
          decoration: InputDecoration(labelText: tr('สเตจเริ่มต้น')),
          items: [for (final s in ['Qualification', 'Needs Analysis', 'Proposal', 'Negotiation']) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (v) => setStep('deal', {'stage': v}),
        ),
      ]),
      card('activity', 'สร้าง Activity ติดตาม', NxI.calendarCheck, const Color(0xFF10B981), [
        Row(children: [
          Expanded(child: TextFormField(initialValue: '${step('activity')['due_days'] ?? 3}', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('ครบกำหนดใน (วัน)')), onChanged: (v) => setStep('activity', {'due_days': int.tryParse(v) ?? 3}))),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: step('activity')['activitytype']?.toString() ?? 'Task',
              decoration: InputDecoration(labelText: tr('ประเภท')),
              items: [for (final s in ['Task', 'Call', 'Meeting', 'Email', 'Visit']) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setStep('activity', {'activitytype': v}),
            ),
          ),
        ]),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: step('activity')['business_days'] != false, onChanged: (v) => setStep('activity', {'business_days': v}), title: Text(tr('นับเฉพาะวันทำการ'))),
        TextFormField(initialValue: step('activity')['subject_template']?.toString(), decoration: InputDecoration(labelText: tr('หัวข้อ')), onChanged: (v) => setStep('activity', {'subject_template': v})),
      ]),
    ]);
  }
}

/// Full-screen editor for one question (every UI type).
class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor({required this.initial, required this.others});
  final Map<String, dynamic> initial;
  final List<LeadQuestion> others;
  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late Map<String, dynamic> q = Map<String, dynamic>.from(widget.initial);
  List<Map<String, dynamic>> get _options => (q['options'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  bool get _hasOptions => kLeadChoiceTypes.contains(q['uitype']) || kLeadSnapshotSelect.contains(q['uitype']);

  @override
  Widget build(BuildContext context) {
    final t = q['uitype']?.toString() ?? 'Text';
    final cond = q['show_if'] is Map ? Map<String, dynamic>.from(q['show_if'] as Map) : null;
    return NxScrollScaffold(
      motionBlur: false,
      header: NxAppHeader(
        title: tr('แก้ไขคำถาม'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, q), child: Text(tr('เสร็จ')))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 48), children: [
        TextFormField(initialValue: q['label']?.toString(), maxLines: null, decoration: InputDecoration(labelText: tr('คำถาม')), onChanged: (v) => q['label'] = v),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: t,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('ชนิดคำถาม (UI Type)')),
          items: [
            for (final g in kLeadTypeGroups.values)
              for (final (v, l) in g) DropdownMenuItem(value: v, child: Text('${tr(l)}  ·  $v', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v == null) return;
            final fresh = leadNewQuestion(v);
            setState(() => q = {...fresh, 'id': q['id'], 'label': q['label'], 'required': q['required'], 'description': q['description'], if (_hasOptions && (kLeadChoiceTypes.contains(v) || kLeadSnapshotSelect.contains(v))) 'options': q['options'], 'map_to': q['map_to'] ?? fresh['map_to']});
          },
        ),
        const SizedBox(height: 8),
        TextFormField(initialValue: q['description']?.toString(), decoration: InputDecoration(labelText: tr('คำอธิบาย (ไม่บังคับ)')), onChanged: (v) => q['description'] = v),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: q['required'] == true, onChanged: (v) => setState(() => q['required'] = v), title: Text(tr('ต้องตอบ'))),
        if (_hasOptions) ...[
          const SizedBox(height: 4),
          Text(tr('ตัวเลือก'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (a, b) {
              final o = _options;
              o.insert(b, o.removeAt(a));
              setState(() => q['options'] = o);
            },
            children: [
              for (final (i, o) in _options.indexed)
                ListTile(
                  key: ValueKey('opt-$i-${o['value']}'),
                  contentPadding: EdgeInsets.zero,
                  title: TextFormField(
                    initialValue: o['label']?.toString(),
                    onChanged: (v) {
                      final list = _options;
                      final keep = list[i]['value'] != list[i]['label'];
                      list[i] = {...list[i], 'label': v, if (!keep) 'value': v};
                      q['options'] = list;
                    },
                  ),
                  trailing: IconButton(icon: const Icon(NxI.x, size: 18), onPressed: () => setState(() => q['options'] = _options..removeAt(i))),
                ),
            ],
          ),
          Row(children: [
            TextButton(onPressed: () => setState(() => q['options'] = [..._options, {'value': '${tr('ตัวเลือก')} ${_options.length + 1}', 'label': '${tr('ตัวเลือก')} ${_options.length + 1}'}]), child: Text('+ ${tr('เพิ่มตัวเลือก')}')),
            const Spacer(),
            Text(tr('มี “อื่นๆ”')),
            Switch(value: q['allow_other'] == true, onChanged: (v) => setState(() => q['allow_other'] = v)),
          ]),
        ],
        if (t == 'FormLinearScale' || t == 'FormRating')
          Row(children: [
            if (t == 'FormLinearScale')
              Expanded(child: TextFormField(initialValue: '${(q['scale'] as Map?)?['min'] ?? 1}', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('ต่ำสุด')), onChanged: (v) => q['scale'] = {...?(q['scale'] as Map?), 'min': int.tryParse(v) ?? 1})),
            if (t == 'FormLinearScale') const SizedBox(width: 12),
            Expanded(child: TextFormField(initialValue: '${(q['scale'] as Map?)?['max'] ?? 5}', keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('สูงสุด')), onChanged: (v) => q['scale'] = {...?(q['scale'] as Map?), 'max': int.tryParse(v) ?? 5})),
          ]),
        if (t == 'FormChoiceGrid' || t == 'FormCheckboxGrid') ...[
          TextFormField(initialValue: ((q['rows'] as List?) ?? const []).join('\n'), maxLines: 4, decoration: InputDecoration(labelText: tr('แถว (บรรทัดละ 1)')), onChanged: (v) => q['rows'] = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
          TextFormField(initialValue: ((q['columns'] as List?) ?? const []).join('\n'), maxLines: 4, decoration: InputDecoration(labelText: tr('คอลัมน์ (บรรทัดละ 1)')), onChanged: (v) => q['columns'] = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
        ],
        if (t == 'FormConsent') TextFormField(initialValue: q['consent_text']?.toString(), maxLines: 4, decoration: InputDecoration(labelText: tr('ข้อความยินยอม')), onChanged: (v) => q['consent_text'] = v),
        if (t == 'FormMedia') TextFormField(initialValue: q['media_url']?.toString(), decoration: InputDecoration(labelText: tr('ลิงก์รูป / วิดีโอ')), onChanged: (v) => q['media_url'] = v),
        const Divider(height: 32),
        DropdownButtonFormField<String>(
          initialValue: kLeadMapTargets.containsKey(q['map_to']) ? q['map_to']?.toString() ?? '' : '',
          decoration: InputDecoration(labelText: tr('บันทึกลงฟิลด์ Lead')),
          items: [for (final e in kLeadMapTargets.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value)))],
          onChanged: (v) => setState(() => (v == null || v.isEmpty) ? q.remove('map_to') : q['map_to'] = v),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: q['staff_only'] == true || kLeadStaffOnly.contains(t), onChanged: kLeadStaffOnly.contains(t) ? null : (v) => setState(() => q['staff_only'] = v), title: Text(tr('เฉพาะพนักงาน (ซ่อนบนลิงก์สาธารณะ)'))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: cond?['question_id']?.toString() ?? '',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('แสดงเมื่อ')),
          items: [
            DropdownMenuItem(value: '', child: Text(tr('แสดงเสมอ'))),
            for (final o in widget.others) DropdownMenuItem(value: o.id, child: Text(o.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => (v == null || v.isEmpty) ? q.remove('show_if') : q['show_if'] = {'question_id': v, 'op': 'eq', 'value': ''}),
        ),
        if (cond != null) ...[
          DropdownButtonFormField<String>(
            initialValue: cond['op']?.toString() ?? 'eq',
            decoration: InputDecoration(labelText: tr('เงื่อนไข')),
            items: [
              DropdownMenuItem(value: 'eq', child: Text(tr('เท่ากับ'))),
              DropdownMenuItem(value: 'not_eq', child: Text(tr('ไม่เท่ากับ'))),
              DropdownMenuItem(value: 'includes', child: Text(tr('มีคำว่า'))),
              DropdownMenuItem(value: 'answered', child: Text(tr('ตอบแล้ว'))),
            ],
            onChanged: (v) => setState(() => q['show_if'] = {...cond, 'op': v}),
          ),
          if (cond['op'] != 'answered')
            Builder(builder: (_) {
              final src = widget.others.where((o) => o.id == cond['question_id']).firstOrNull;
              if (src != null && src.options.isNotEmpty) {
                return DropdownButtonFormField<String>(
                  initialValue: src.options.any((o) => o['value'] == cond['value']) ? cond['value']?.toString() : null,
                  decoration: InputDecoration(labelText: tr('ค่า')),
                  items: [for (final o in src.options) DropdownMenuItem(value: o['value'].toString(), child: Text(o['label']?.toString() ?? ''))],
                  onChanged: (v) => setState(() => q['show_if'] = {...cond, 'value': v}),
                );
              }
              return TextFormField(initialValue: cond['value']?.toString(), decoration: InputDecoration(labelText: tr('ค่า')), onChanged: (v) => q['show_if'] = {...cond, 'value': v});
            }),
        ],
      ]),
    );
  }
}
