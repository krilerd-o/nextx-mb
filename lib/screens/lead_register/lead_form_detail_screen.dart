import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/lead_register/lead_form.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/nx_icons.dart';
import '../journey/job_sign_link.dart' show NxQrCode;
import 'lead_form_builder_screen.dart';
import 'lead_form_fill_screen.dart';
import 'lead_form_renderer.dart';
import 'lead_response_detail_screen.dart';

String leadFlowStatusLabel(String s) => switch (s) {
      'done' => 'สำเร็จ',
      'partial' => 'บางส่วน',
      'failed' => 'ล้มเหลว',
      'running' => 'กำลังทำ',
      'skipped' => 'ข้าม',
      _ => 'รอดำเนินการ',
    };

Color leadFlowStatusColor(String s) => switch (s) {
      'done' => const Color(0xFF10B981),
      'partial' => const Color(0xFFF59E0B),
      'failed' => const Color(0xFFE11D48),
      'running' => const Color(0xFF0EA5E9),
      _ => const Color(0xFF94A3B8),
    };

/// One form: responses (with flow status), summary dashboard, share (QR) and
/// flow switches. Edit opens the native builder.
class LeadFormDetailScreen extends StatefulWidget {
  const LeadFormDetailScreen({super.key, required this.formId, this.name = ''});
  final int formId;
  final String name;

  @override
  State<LeadFormDetailScreen> createState() => _LeadFormDetailScreenState();
}

class _LeadFormDetailScreenState extends State<LeadFormDetailScreen> {
  LeadFormDef? _form;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await context.read<AppConfig>().apiClient.getLeadForm(widget.formId);
    if (mounted) setState(() => _form = LeadFormDef(f));
  }

  Future<void> _setStatus(bool publish) async {
    final f = await context.read<AppConfig>().apiClient.setLeadFormStatus(widget.formId, publish: publish);
    if (mounted) setState(() => _form = LeadFormDef(f));
  }

  @override
  Widget build(BuildContext context) {
    final f = _form;
    final accent = f == null ? Theme.of(context).colorScheme.primary : leadAccent(f.theme);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(f?.name ?? widget.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: tr('แก้ไขแบบฟอร์ม'),
              icon: const Icon(NxI.pencilSimple),
              onPressed: () async {
                await nxPush<void>(context, LeadFormBuilderScreen(formId: widget.formId));
                _load();
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'publish') _setStatus(true);
                if (v == 'close') _setStatus(false);
                if (v == 'kiosk') Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => LeadFormFillScreen(formId: widget.formId, kiosk: true)));
              },
              itemBuilder: (_) => [
                if (f?.status != 'published') PopupMenuItem(value: 'publish', child: Text(tr('เผยแพร่'))),
                if (f?.status == 'published') PopupMenuItem(value: 'close', child: Text(tr('ปิดรับคำตอบ'))),
                PopupMenuItem(value: 'kiosk', child: Text(tr('โหมดคีออสก์'))),
              ],
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: accent,
            tabs: [Tab(text: tr('คำตอบ')), Tab(text: tr('สรุป')), const Tab(text: 'Flow'), Tab(text: tr('แชร์'))],
          ),
        ),
        floatingActionButton: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 20), shape: const StadiumBorder(), elevation: 3),
          onPressed: () => nxPush<void>(context, LeadFormFillScreen(formId: widget.formId)),
          icon: const Icon(NxI.penLine),
          label: Text(tr('กรอกแทนลูกค้า')),
        ),
        body: f == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [
                _ResponsesTab(formId: widget.formId),
                _SummaryTab(formId: widget.formId, accent: accent),
                _FlowTab(form: f, onChanged: (nf) => setState(() => _form = nf)),
                _ShareTab(form: f, onPublish: () => _setStatus(true)),
              ]),
      ),
    );
  }
}

class _ResponsesTab extends StatefulWidget {
  const _ResponsesTab({required this.formId});
  final int formId;
  @override
  State<_ResponsesTab> createState() => _ResponsesTabState();
}

class _ResponsesTabState extends State<_ResponsesTab> {
  final List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  int _total = 0;
  bool _loading = true;
  String _q = '';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 && !_loading && _cursor != null) _load(more: true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final res = await context.read<AppConfig>().apiClient.getLeadFormResponses(widget.formId, q: _q, cursor: more ? _cursor : null);
      final list = (res['list'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        if (!more) _rows.clear();
        _rows.addAll(list);
        _cursor = res['next_cursor']?.toString();
        if (res['total'] != null) _total = (res['total'] as num).toInt();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _rows.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(NxI.magnifyingGlass, size: 18),
                  hintText: tr('ค้นหาชื่อ อีเมล เบอร์ บริษัท'),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixText: '$_total',
                ),
                onSubmitted: (s) {
                  _q = s;
                  _load();
                },
              ),
            );
          }
          if (i == _rows.length + 1) {
            if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            if (_rows.isEmpty) return Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('ยังไม่มีคำตอบ'))));
            return const SizedBox.shrink();
          }
          final r = _rows[i - 1];
          final st = r['flow_status']?.toString() ?? 'pending';
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
            child: ListTile(
              onTap: () async {
                await nxPush<void>(context, LeadResponseDetailScreen(responseId: (r['id'] as num).toInt()));
                _load();
              },
              title: Text(r['respondent_name']?.toString() ?? r['respondent_email']?.toString() ?? '#${r['id']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [r['respondent_company'], r['lead_no'], r['deal_no'], if (r['lead_attached'] == 1) tr('ตอบซ้ำ')].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: leadFlowStatusColor(st).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                  child: Text(tr(leadFlowStatusLabel(st)), style: TextStyle(fontSize: 11, color: leadFlowStatusColor(st), fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(r['channel']?.toString() ?? '', style: theme.textTheme.labelSmall),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.formId, required this.accent});
  final int formId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: context.read<AppConfig>().apiClient.getLeadFormSummary(formId),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final k = Map<String, dynamic>.from(d['kpi'] as Map? ?? const {});
        final theme = Theme.of(context);
        // One point per day for the last 14 days (days without answers = 0) so the chart always draws.
        final byDay = {for (final t in (d['trend'] as List? ?? const []).whereType<Map>()) '${t['day']}': ((t['n'] as num?) ?? 0).toDouble()};
        final today = DateTime.now().toUtc().add(const Duration(hours: 7));
        final trend = [
          for (var i = 13; i >= 0; i--)
            byDay[today.subtract(Duration(days: i)).toIso8601String().substring(0, 10)] ?? 0.0,
        ];
        final funnel = (d['funnel'] as List? ?? const []).whereType<Map>().toList();
        final questions = (d['questions'] as List? ?? const []).whereType<Map>().toList();
        final funnelMax = funnel.isEmpty ? 1 : ((funnel.first['n'] as num?) ?? 1).clamp(1, 1 << 30);
        const funnelLabels = {'responses': 'คำตอบ', 'lead': 'Lead', 'emailed': 'ส่ง Salesheet', 'deal': 'Deal', 'followed_up': 'ติดตามแล้ว', 'won': 'ปิดได้'};
        Widget kpi(String l, dynamic n, IconData icon) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 16, color: theme.hintColor),
                  const SizedBox(height: 6),
                  Text('${n ?? 0}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(l, style: theme.textTheme.labelSmall),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Row(children: [kpi(tr('คำตอบ'), k['responses'], NxI.tray), const SizedBox(width: 8), kpi(tr('วันนี้'), k['today'], NxI.plus), const SizedBox(width: 8), kpi('Leads', k['leads'], NxI.userPlus), const SizedBox(width: 8), kpi('Deals', k['deals'], NxI.handshake)]),
          const SizedBox(height: 16),
          Text(tr('คำตอบรายวัน'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(
            height: 140,
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  color: accent,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: accent.withValues(alpha: 0.12)),
                  spots: [for (final (i, n) in trend.indexed) FlSpot(i.toDouble(), n)],
                ),
              ],
            )),
          ),
          const SizedBox(height: 16),
          Text(tr('Funnel หลังลงทะเบียน'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final f in funnel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [Expanded(child: Text(tr(funnelLabels[f['key']] ?? '${f['key']}'))), Text('${f['n']}')]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: ((f['n'] as num?) ?? 0) / funnelMax, minHeight: 8, color: accent, backgroundColor: accent.withValues(alpha: 0.1)),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          for (final q in questions)
            if (q['kind'] == 'choice' || q['kind'] == 'number')
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${q['label']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${q['answered']} ${tr('คำตอบ')}${q['avg'] != null ? ' · ${tr('เฉลี่ย')} ${q['avg']}' : ''}${q['nps'] != null ? ' · NPS ${q['nps']}' : ''}', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 8),
                    for (final c in (q['counts'] as List? ?? const []).whereType<Map>().where((c) => ((c['n'] as num?) ?? 0) > 0))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [Expanded(child: Text('${c['label']}', maxLines: 1, overflow: TextOverflow.ellipsis)), Text('${c['n']}')]),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: ((c['n'] as num?) ?? 0) / ((q['answered'] as num?) ?? 1).clamp(1, 1 << 30),
                              minHeight: 6,
                              color: accent,
                              backgroundColor: accent.withValues(alpha: 0.08),
                            ),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
        ]);
      },
    );
  }
}

class _FlowTab extends StatelessWidget {
  const _FlowTab({required this.form, required this.onChanged});
  final LeadFormDef form;
  final ValueChanged<LeadFormDef> onChanged;

  static const _steps = [
    ('lead', 'สร้าง Lead อัตโนมัติ', NxI.userPlus, Color(0xFF6366F1)),
    ('email', 'ส่งอีเมล Salesheet', NxI.envelope, Color(0xFF0EA5E9)),
    ('deal', 'สร้าง Deal อัตโนมัติ', NxI.handshake, Color(0xFFF59E0B)),
    ('activity', 'สร้าง Activity ติดตาม', NxI.calendarCheck, Color(0xFF10B981)),
  ];

  String _summary(String step, Map<String, dynamic> s) => switch (step) {
        'lead' => '${s['duplicate'] == 'create' ? tr('สร้างใหม่ทุกครั้ง') : tr('ผูก Lead เดิม (อีเมล/เบอร์)')} · ${s['lead_source'] ?? ''}',
        'email' => s['subject']?.toString() ?? '',
        'deal' => s['stage']?.toString() ?? 'Qualification',
        _ => '+${s['due_days'] ?? 3} ${s['business_days'] == false ? tr('วัน') : tr('วันทำการ')} · ${s['activitytype'] ?? 'Task'}',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: theme.colorScheme.inverseSurface, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(NxI.clipboardText, color: theme.colorScheme.onInverseSurface),
          const SizedBox(width: 10),
          Expanded(child: Text('${tr('เมื่อมีคนส่ง')}: ${form.name}', style: TextStyle(color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.w600))),
        ]),
      ),
      for (final (i, (step, label, icon, color)) in _steps.indexed) ...[
        Padding(padding: EdgeInsets.only(left: i == 0 ? 28 : 48), child: Container(width: 2, height: 16, color: theme.colorScheme.outlineVariant)),
        Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 20),
          child: Builder(builder: (context) {
            final s = form.flow[step] is Map ? Map<String, dynamic>.from(form.flow[step] as Map) : <String, dynamic>{};
            final on = s['enabled'] != false;
            return Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
              child: SwitchListTile(
                value: on,
                secondary: CircleAvatar(backgroundColor: on ? color : theme.disabledColor, child: Icon(icon, color: Colors.white, size: 18)),
                title: Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(on ? _summary(step, s) : tr('ปิดอยู่ — ขั้นนี้จะถูกข้าม'), maxLines: 2, overflow: TextOverflow.ellipsis),
                onChanged: (v) async {
                  HapticFeedback.selectionClick();
                  final f = await context.read<AppConfig>().apiClient.setLeadFormFlowStep(form.id, step, {'enabled': v});
                  onChanged(LeadFormDef(f));
                },
              ),
            );
          }),
        ),
      ],
      const SizedBox(height: 16),
      Text(tr('ตั้งค่าเจ้าของ ผู้รับผิดชอบ ไฟล์ Salesheet และจำนวนวันได้ใน “แก้ไขแบบฟอร์ม” → Flow'), style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
    ]);
  }
}

class _ShareTab extends StatelessWidget {
  const _ShareTab({required this.form, required this.onPublish});
  final LeadFormDef form;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final base = context.read<AppConfig>().apiClient.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = '$base/f/${form.token}';
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
      if (form.status != 'published')
        Card(
          elevation: 0,
          color: Colors.amber.withValues(alpha: 0.12),
          child: ListTile(
            leading: const Icon(NxI.lock),
            title: Text(tr('ยังไม่เผยแพร่')),
            subtitle: Text(tr('เผยแพร่เพื่อเปิดลิงก์และ QR ให้ลูกค้ากรอกเอง')),
            trailing: FilledButton(onPressed: onPublish, child: Text(tr('เผยแพร่'))),
          ),
        ),
      const SizedBox(height: 12),
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: theme.colorScheme.outlineVariant)),
          child: NxQrCode(data: '$url?src=qr', size: 240),
        ),
      ),
      const SizedBox(height: 10),
      Center(child: Text(form.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
      const SizedBox(height: 16),
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: ListTile(
          title: Text(url, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          trailing: IconButton(
            icon: const Icon(NxI.copySimple),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('คัดลอกลิงก์แล้ว'))));
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: () => Share.share('${form.name}\n$url'), icon: const Icon(NxI.shareNetwork), label: Text(tr('แชร์ลิงก์')))),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => _QrFullScreen(url: '$url?src=qr', name: form.name))),
            icon: const Icon(NxI.qrCode),
            label: Text(tr('QR เต็มจอ')),
          ),
        ),
      ]),
    ]);
  }
}

/// Full-screen QR to hold up at the booth.
class _QrFullScreen extends StatelessWidget {
  const _QrFullScreen({required this.url, required this.name});
  final String url;
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, foregroundColor: Colors.black),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('สแกนเพื่อลงทะเบียน'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.black)),
            const SizedBox(height: 24),
            NxQrCode(data: url, size: MediaQuery.sizeOf(context).shortestSide * 0.72),
            const SizedBox(height: 20),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.black87))),
          ]),
        ),
      );
}
