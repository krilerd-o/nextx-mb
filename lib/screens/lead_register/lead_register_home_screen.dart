import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/nx_page_route.dart';
import '../../services/lead_register_queue.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_skeleton.dart';
import 'lead_form_builder_screen.dart';
import 'lead_form_detail_screen.dart';
import 'lead_form_fill_screen.dart';
import 'lead_form_renderer.dart';

/// Lead Register — every form of the business, with quick Fill / Kiosk.
class LeadRegisterHomeScreen extends StatefulWidget {
  const LeadRegisterHomeScreen({super.key});

  @override
  State<LeadRegisterHomeScreen> createState() => _LeadRegisterHomeScreenState();
}

class _LeadRegisterHomeScreenState extends State<LeadRegisterHomeScreen> {
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    LeadRegisterQueue.instance.load();
  }

  Future<void> _create() async {
    final api = context.read<AppConfig>().apiClient;
    final templates = await api.getLeadFormTemplates();
    if (!mounted) return;
    final key = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(tr('เริ่มจากเทมเพลต'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(tr('คำถาม การบันทึกลง Lead และ Flow ตั้งไว้ให้แล้ว'), style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final (i, t) in templates.indexed)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: i == 0 ? Colors.amber.shade400 : Theme.of(ctx).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(backgroundColor: leadAccent({'accent': t['accent']}), child: const Icon(NxI.clipboardText, color: Colors.white, size: 20)),
                  title: Text(t['name_th']?.toString() ?? t['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${t['question_count']} ${tr('คำถาม')} · ${t['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: i == 0 ? Chip(label: Text(tr('แนะนำ')), visualDensity: VisualDensity.compact) : null,
                  onTap: () => Navigator.pop(ctx, t['key'].toString()),
                ),
              ),
          ],
        ),
      ),
    );
    if (key == null || !mounted) return;
    final form = await api.createLeadForm(templateKey: key);
    if (!mounted) return;
    final id = (form['id'] as num).toInt();
    await nxPush<void>(context, LeadFormBuilderScreen(formId: id));
    if (mounted) setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    return NxScrollScaffold(
      header: NxAppHeader(
        title: tr('ลงทะเบียน Lead'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: LeadRegisterQueue.instance.pending,
            builder: (_, n, _) => n == 0
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: tr('รอส่ง'),
                    onPressed: () async {
                      final sent = await LeadRegisterQueue.instance.flush(context.read<AppConfig>().apiClient);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('ส่งแล้ว')} $sent')));
                    },
                    icon: Badge(label: Text('$n'), child: const Icon(NxI.uploadSimple)),
                  ),
          ),
        ],
      ),
      floatingActionButton: FilledButton.icon(
        onPressed: _create,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 20), shape: const StadiumBorder(), elevation: 3),
        icon: const Icon(NxI.plus),
        label: Text(tr('สร้างแบบฟอร์ม')),
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        cacheKey: 'lead-register-forms',
        load: () => context.read<AppConfig>().apiClient.getLeadForms(),
        skeleton: const NxSkeletonList(),
        isEmpty: (l) => l.isEmpty,
        empty: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(NxI.clipboardText, size: 44),
              const SizedBox(height: 10),
              Text(tr('ยังไม่มีแบบฟอร์ม'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(tr('กด “สร้างแบบฟอร์ม” แล้วเลือกเทมเพลตลงทะเบียนหน้าบูธ'), textAlign: TextAlign.center),
            ]),
          ),
        ),
        builder: (context, list) => RefreshIndicator(
          onRefresh: () async => setState(() => _revision++),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _FormCard(
              f: list[i],
              onChanged: () => setState(() => _revision++),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.f, required this.onChanged});
  final Map<String, dynamic> f;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = (f['id'] as num).toInt();
    final accent = leadAccent(f['theme'] is Map ? Map<String, dynamic>.from(f['theme'] as Map) : const {});
    final status = f['status']?.toString() ?? 'draft';
    final flow = (f['flow_enabled'] as List?)?.map((e) => '$e').toSet() ?? const <String>{};
    Widget stat(String label, dynamic n) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${n ?? 0}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: theme.textTheme.labelSmall),
            ]),
          ),
        );
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await nxPush<void>(context, LeadFormDetailScreen(formId: id, name: f['name']?.toString() ?? ''));
          onChanged();
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 5, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(children: [
              CircleAvatar(radius: 20, backgroundColor: accent, child: const Icon(NxI.clipboardText, color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(NxI.circle, size: 8, color: status == 'published' ? Colors.green : status == 'closed' ? Colors.grey : Colors.amber),
                    const SizedBox(width: 4),
                    Text(tr(status == 'published' ? 'เปิดรับ' : status == 'closed' ? 'ปิดรับ' : 'ฉบับร่าง'), style: theme.textTheme.labelSmall),
                    Text('  ·  ${f['question_count'] ?? 0} ${tr('คำถาม')}', style: theme.textTheme.labelSmall),
                  ]),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(children: [
              stat(tr('คำตอบ'), f['response_count']),
              const SizedBox(width: 8),
              stat(tr('วันนี้'), f['today_count']),
              const SizedBox(width: 8),
              stat('Leads', f['lead_count']),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(children: [
              for (final (step, icon) in [('lead', NxI.userPlus), ('email', NxI.envelope), ('deal', NxI.handshake), ('activity', NxI.calendarCheck)])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(icon, size: 16, color: flow.contains(step) ? accent : theme.disabledColor),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => nxPush<void>(context, LeadFormFillScreen(formId: id)),
                icon: const Icon(NxI.penLine, size: 16),
                label: Text(tr('กรอก')),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => LeadFormFillScreen(formId: id, kiosk: true))),
                icon: const Icon(NxI.tablet, size: 16),
                label: const Text('Kiosk'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
