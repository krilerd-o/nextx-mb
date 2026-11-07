import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import 'workspace_board_screen.dart';
import '../../widgets/nx_icons.dart';

class WorkspaceHomeScreen extends StatefulWidget {
  const WorkspaceHomeScreen({super.key});

  @override
  State<WorkspaceHomeScreen> createState() => _WorkspaceHomeScreenState();
}

class _WorkspaceHomeScreenState extends State<WorkspaceHomeScreen> {
  var _revision = 0;

  @override
  Widget build(BuildContext context) {
    return NxScrollScaffold(
      header: NxAppHeader(
        title: 'Workspace',
        actions: [
          IconButton(
            icon: const Icon(NxI.arrowCounterClockwise),
            onPressed: () => setState(() => _revision++),
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getBoards(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ยังไม่มีบอร์ด')),
        builder: (context, boards) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: boards.length,
            itemBuilder: (context, i) {
              final b = boards[i];
              return DenseCardTile(
                title: b['name']?.toString() ?? 'บอร์ด',
                subtitle: [
                  b['code'],
                  '${b['task_count'] ?? 0} งาน',
                ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
                leading: const Icon(NxI.kanban),
                onTap: () => nxPush<void>(context, WorkspaceBoardScreen(board: b)),
              );
            },
          );
        },
      ),
    );
  }
}
