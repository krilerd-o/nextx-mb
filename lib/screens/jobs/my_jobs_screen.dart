import 'package:flutter/material.dart';
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

class MyJobsScreen extends StatefulWidget {
  const MyJobsScreen({super.key});

  @override
  State<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends State<MyJobsScreen> {
  var _revision = 0;
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return Scaffold(
      appBar: NxAppHeader(
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
        load: () => context.read<AppConfig>().apiClient.getMyJobs(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ไม่มีงานที่ได้รับมอบหมาย')),
        builder: (context, list) {
          final items = ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final row = list[i];
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
                        tooltip: 'เช็คอิน',
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
