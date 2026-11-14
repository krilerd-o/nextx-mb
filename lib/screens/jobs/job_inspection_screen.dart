import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/nx_skeleton.dart';
import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/i18n.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_icons.dart';
import '../fsm/inspection_lines.dart';

/// Inspection of a job, from "My Service Job": shows the job's existing
/// inspections (opens the latest), or creates one (the server adds the
/// template's checklist), then the checklist editor right here.
class JobInspectionScreen extends StatefulWidget {
  const JobInspectionScreen({super.key, required this.job});
  final Map<String, dynamic> job;

  @override
  State<JobInspectionScreen> createState() => _JobInspectionScreenState();
}

class _JobInspectionScreenState extends State<JobInspectionScreen> {
  List<Map<String, dynamic>>? _list;
  String? _current;
  bool _creating = false;
  Object? _error;

  String get _jobId => strId(widget.job['id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<AppConfig>().apiClient.getEntityList('inspection', limit: 50, extra: {'filter[related_job_id]': _jobId});
      final list = page.items.where((r) => '${r['related_job_id'] ?? _jobId}' == _jobId).toList()
        ..sort((a, b) => strId(b['id']).compareTo(strId(a['id'])));
      if (!mounted) return;
      setState(() {
        _list = list;
        _error = null;
        _current ??= list.isEmpty ? null : strId(list.first['id']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final created = await context.read<AppConfig>().apiClient.createJobInspection(_jobId);
      final id = strId(created['id'] ?? (created['inspection'] is Map ? created['inspection']['id'] : null));
      if (id.isEmpty) throw StateError(tr('สร้างใบตรวจรับไม่สำเร็จ'));
      _current = id;
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('สร้างใบตรวจรับแล้ว — กดผล ผ่าน / ไม่ผ่าน ได้เลย'))));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final list = _list;
    final current = _current;
    return Scaffold(
      appBar: NxAppHeader(title: 'ใบตรวจรับ', subtitle: entityTitle(widget.job, module: 'job')),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14)),
              child: Text(error(_error!), style: TextStyle(color: cs.onErrorContainer)),
            ),
          if (list == null && _error == null)
            // Inspection cards: number + status pill, title, counters line.
            const NxSkeletonEntityCards(key: ValueKey('job-insp-skeleton'), count: 3, padded: false),
          if (list != null && list.isEmpty) ...[
            Container(
              key: const ValueKey('job-insp-empty'),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Icon(NxI.clipboardText, size: 40, color: cs.primary),
                const SizedBox(height: 10),
                Text(tr('งานนี้ยังไม่มีใบตรวจรับ'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('สร้างแล้วจะได้รายการตรวจตามเทมเพลตของงาน แก้ไข/เพิ่มรายการได้'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
              ]),
            ),
            const SizedBox(height: 14),
            NxHeroCta(key: const ValueKey('job-insp-create'), label: 'สร้างใบตรวจรับ', busy: _creating, onPressed: _creating ? null : _create),
          ],
          if (list != null && list.isNotEmpty) ...[
            if (list.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final r in list)
                    ChoiceChip(
                      key: ValueKey('job-insp-pick-${r['id']}'),
                      label: Text('${r['inspection_no'] ?? '#${r['id']}'} · ${thaiDate(r['createdtime'])}'),
                      selected: strId(r['id']) == current,
                      onSelected: (_) => setState(() => _current = strId(r['id'])),
                    ),
                ]),
              ),
            if (current != null) InspectionLinesEditor(key: ValueKey('insp-$current'), inspectionId: current),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('job-insp-new'),
              onPressed: _creating ? null : _create,
              icon: const Icon(NxI.plus, size: 18),
              label: Text(tr('สร้างใบตรวจรับใบใหม่')),
            ),
          ],
        ],
      ),
    );
  }

  String error(Object e) => e is StateError ? e.message : formatApiError(e);
}
