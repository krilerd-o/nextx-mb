import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_page_route.dart';
import '../../core/entity_display.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../calendar/activity_detail_screen.dart';
import '../crm/entity_detail_screen.dart';
import 'job_inspection_screen.dart';
import '../../widgets/nx_icons.dart';
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../widgets/nx_list_toolbar.dart';

class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  var _revision = 0;
  var _query = '';
  NxListQuery _lq = const NxListQuery();
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return NxScrollScaffold(
      header: NxAppHeader(title: 'งานภาคสนาม'),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        // Server returns at most 100 assigned jobs (no offset) — fetch them all, filter locally.
        load: () => context.read<AppConfig>().apiClient.getMyJobs(limit: 100),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: Center(child: Text(tr('ไม่มีงานที่ได้รับมอบหมาย'))),
        builder: (context, all) {
          final statuses = <String>{
            for (final r in all)
              if ('${r['job_status'] ?? ''}'.isNotEmpty) '${r['job_status']}',
          }.toList()..sort();
          String planOf(Map r) => '${r['plan_start'] ?? r['due_datetime'] ?? ''}';
          final today = thaiNow();
          bool onDay(Map r, Set<String> v) {
            final d = r['plan_start'] != null ? parseThaiField(r['plan_start'], 'plan_start') : parseThaiField(r['due_datetime'], 'due_datetime');
            if (d == null) return v.contains('none');
            final day = DateTime(d.year, d.month, d.day);
            final t0 = DateTime(today.year, today.month, today.day);
            return (v.contains('today') && day == t0) ||
                (v.contains('tomorrow') && day == t0.add(const Duration(days: 1))) ||
                (v.contains('week') && !day.isBefore(t0) && day.isBefore(t0.add(const Duration(days: 7)))) ||
                (v.contains('overdue') && day.isBefore(t0) && !RegExp(r'complete|cancel|closed|done', caseSensitive: false).hasMatch('${r['job_status']}'));
          }

          final groups = [
            if (statuses.isNotEmpty) NxFilterGroup(key: 'status', label: 'สถานะ', options: [for (final st in statuses) NxFilterOption(st, st)]),
            const NxFilterGroup(
              key: 'day',
              label: 'วันนัด',
              options: [
                NxFilterOption('today', 'วันนี้'),
                NxFilterOption('tomorrow', 'พรุ่งนี้'),
                NxFilterOption('week', '7 วันข้างหน้า'),
                NxFilterOption('overdue', 'เลยกำหนด'),
                NxFilterOption('none', 'ยังไม่นัด'),
              ],
            ),
          ];
          final list = nxApplyLocalQuery<Map<String, dynamic>>(
            all,
            _lq.copyWith(q: _query),
            text: (r) => '${entityTitle(r, module: 'job')} ${entitySubtitle(r) ?? ''} ${r['job_no'] ?? ''} ${r['customer_name'] ?? ''}',
            filters: {'status': (r, v) => v.contains('${r['job_status'] ?? ''}'), 'day': onDay},
            sorts: {
              'plan_asc': (a, b) => (planOf(a).isEmpty ? 'z' : planOf(a)).compareTo(planOf(b).isEmpty ? 'z' : planOf(b)),
              'plan_desc': (a, b) => planOf(b).compareTo(planOf(a)),
              'new': (a, b) => '${b['createdtime'] ?? b['id'] ?? ''}'.compareTo('${a['createdtime'] ?? a['id'] ?? ''}'),
            },
          );
          final items = ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: list.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return NxListToolbar(
                  query: _lq.copyWith(q: _query),
                  liveSearch: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  searchHint: 'ค้นหาเลขงาน / ลูกค้า',
                  quickGroup: 'day',
                  groups: groups,
                  resultCount: list.length,
                  sorts: const [NxSortOption('plan_asc', 'วันนัดใกล้สุด'), NxSortOption('plan_desc', 'วันนัดล่าสุด'), NxSortOption('new', 'สร้างล่าสุด')],
                  onChanged: (q) => setState(() {
                    _query = q.q;
                    _lq = q.copyWith(q: '');
                  }),
                );
              }
              final row = list[index - 1];
              return DenseCardTile(
                title: entityTitle(row, module: 'job'),
                subtitle: entitySubtitle(row),
                leading: const Icon(NxI.wrench),
                onTap: () {
                  if (twoPane) {
                    setState(() => _selected = row);
                    return;
                  }
                  nxPush<void>(context, EntityDetailScreen(module: 'job', row: row));
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (strId(row['related_activity_id']).isNotEmpty)
                      IconButton(
                        tooltip: tr('เช็คอิน'),
                        icon: const Icon(NxI.clock),
                        onPressed: () {
                          nxPush<void>(context, ActivityDetailScreen(row: {'id': strId(row['related_activity_id'])}));
                        },
                      ),
                    IconButton(
                      icon: const Icon(NxI.clipboardText),
                      onPressed: () {
                        nxPush<void>(context, JobInspectionScreen(job: row));
                      },
                    ),
                  ],
                ),
              );
            },
          );
          return NxSplitView(
            list: items,
            detail: _selected == null ? null : EntityDetailScreen(key: ValueKey(_selected!['id']), module: 'job', row: _selected!, embedded: true),
          );
        },
      ),
    );
  }
}
