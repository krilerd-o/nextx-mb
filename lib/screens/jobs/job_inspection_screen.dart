import 'package:flutter/material.dart';
import '../../widgets/nx_icons.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/nx_breakpoint.dart';
import '../../services/api_client.dart';
import '../../services/file_open.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_hero_cta.dart';
import '../../widgets/nx_surface_card.dart';
import '../../core/i18n.dart';

class JobInspectionScreen extends StatefulWidget {
  const JobInspectionScreen({super.key, required this.job});
  final Map<String, dynamic> job;

  @override
  State<JobInspectionScreen> createState() => _JobInspectionScreenState();
}

class _JobInspectionScreenState extends State<JobInspectionScreen> {
  String? _inspectionId;
  List<Map<String, dynamic>> _lines = [];
  bool _busy = false;
  Object? _error;

  String get _jobId => strId(widget.job['id']);

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await context.read<AppConfig>().apiClient.createJobInspection(_jobId);
      final id = strId(created['id'] ?? created['inspection']?['id']);
      final lines = id.isEmpty ? <Map<String, dynamic>>[] : await context.read<AppConfig>().apiClient.getInspectionLines(id);
      if (mounted) {
        setState(() {
          _inspectionId = id.isEmpty ? null : id;
          _lines = lines;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final id = _inspectionId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final lines = _lines
          .map(
            (l) => {
              'line_no': l['line_no'],
              'item_label': l['item_label'],
              'item_result': l['item_result'],
              'remark': l['remark'],
            },
          )
          .toList();
      final saved = await context.read<AppConfig>().apiClient.putInspectionLines(id, lines);
      if (mounted) setState(() => _lines = saved.isEmpty ? _lines : saved);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf() async {
    final id = _inspectionId;
    if (id == null) return;
    try {
      final bytes = await context.read<AppConfig>().apiClient.getInspectionPdf(id);
      await openPdfBytes(bytes, 'inspection-$id.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NxAppHeader(title: entityTitle(widget.job, module: 'job')),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context),
        children: [
          if (_error != null) Text(tr(formatApiError(_error!)), style: TextStyle(color: theme.colorScheme.error)),
          NxHeroCta(
            label: 'สร้างใบตรวจ',
            busy: _busy && _inspectionId == null,
            onPressed: _busy ? null : _create,
          ),
          const SizedBox(height: 12),
          if (_inspectionId != null)
            Text(tr('ใบตรวจ #$_inspectionId'), style: theme.textTheme.titleMedium),
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NxSurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(_lines[i]['item_label']?.toString() ?? 'รายการ ${i + 1}')),
                    DropdownButtonFormField<String>(
        icon: const Icon(NxI.caretDown, size: 18),
                      key: ValueKey('result-$i-${_lines[i]['id']}'),
                      value: () {
                        final v = (_lines[i]['item_result'] ?? '').toString();
                        if (v == 'pass' || v == 'fail' || v == 'na') return v;
                        return '';
                      }(),
                      decoration: InputDecoration(labelText: tr('ผลตรวจ')),
                      items: [
                        DropdownMenuItem(value: '', child: Text(tr('—'))),
                        DropdownMenuItem(value: 'pass', child: Text(tr('Pass'))),
                        DropdownMenuItem(value: 'fail', child: Text(tr('Fail'))),
                        DropdownMenuItem(value: 'na', child: Text(tr('N/A'))),
                      ],
                      onChanged: (v) => _lines[i]['item_result'] = v,
                    ),
                    TextFormField(
                      key: ValueKey('remark-$i-${_lines[i]['id']}'),
                      initialValue: _lines[i]['remark']?.toString() ?? '',
                      decoration: InputDecoration(labelText: tr('หมายเหตุ')),
                      onChanged: (v) => _lines[i]['remark'] = v,
                    ),
                  ],
                ),
              ),
            ),
          if (_inspectionId != null) ...[
            NxHeroCta(
              label: 'บันทึกบรรทัด',
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pdf,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              child: Text(tr('เปิด PDF')),
            ),
          ],
        ],
      ),
    );
  }
}
