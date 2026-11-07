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

class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  var _revision = 0;
  var _query = '';
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'งานภาคสนาม',
        actions: [
          IconButton(
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: () => setState(() => _revision++),
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        // Server returns at most 100 assigned jobs (no offset) — fetch them all, filter locally.
        load: () => context.read<AppConfig>().apiClient.getMyJobs(limit: 100),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: Center(child: Text(tr('ไม่มีงานที่ได้รับมอบหมาย'))),
        builder: (context, all) {
          final needle = _query.trim().toLowerCase();
          final list = needle.isEmpty
              ? all
              : all
                  .where((r) => '${entityTitle(r, module: 'job')} ${entitySubtitle(r) ?? ''}'.toLowerCase().contains(needle))
                  .toList();
          final items = RefreshIndicator(
            onRefresh: () async => setState(() => _revision++),
            child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: list.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: tr('ค้นหางาน (${all.length})'),
                      prefixIcon: const Icon(NxI.magnifyingGlass),
                      filled: true,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
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
                          nxPush<void>(
                            context,
                            ActivityDetailScreen(row: {'id': strId(row['related_activity_id'])}),
                          );
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
          ),
          );
          return NxSplitView(
            list: items,
            detail: _selected == null
                ? null
                : EntityDetailScreen(
                    key: ValueKey(_selected!['id']),
                    module: 'job',
                    row: _selected!,
                    embedded: true,
                  ),
          );
        },
      ),
    );
  }
}
