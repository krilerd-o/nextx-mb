import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';

import '../../core/app_config.dart';
import '../../core/entity_display.dart';
import '../../core/entity_modules.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_search_field.dart';
import '../../widgets/nx_skeleton.dart';
import '../crm/entity_detail_screen.dart';
import 'search_modules.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  bool _searching = false;
  final _results = <_Hit>[];

  List<String> get _modules => globalSearchModulesFor(context.read<AppConfig>().session);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    final config = context.read<AppConfig>();
    await config.addSearchHistory(query);
    if (!mounted) return;
    setState(() => _searching = true);
    final api = config.apiClient;
    // Query every allowed module at once; keep module order in the results.
    final pages = await Future.wait(_modules.map((m) async {
      try {
        final page = await api.getEntityList(m, limit: 8, q: query);
        return [for (final row in page.items) _Hit(module: m, row: row)];
      } catch (e) {
        debugPrint('[search] $m: $e');
        return const <_Hit>[];
      }
    }));
    final next = [for (final hits in pages) ...hits];
    if (mounted) {
      setState(() {
        _results
          ..clear()
          ..addAll(next);
        _searching = false;
      });
    }
  }

  void _openHit(_Hit h) {
    final id = strId(h.row['id']);
    final loc = EntityModules.isFsm(h.module)
        ? AppRoutes.fsmRecord(h.module, id)
        : AppRoutes.crmRecord(h.module, id);
    if (GoRouter.maybeOf(context) != null) {
      context.push(loc);
      return;
    }
    nxPush<void>(context, EntityDetailScreen(module: h.module, row: h.row));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfig>();

    return NxScrollScaffold(
      header: const NxAppHeader.hub(),
      body: ListView(
        padding: NxBreakpoint.of(context).scrollPadding(context, inShell: true),
        children: [
          NxSearchField(
            controller: _controller,
            hint: 'ค้นหาลูกค้า งาน สินค้า…',
            onSubmitted: _run,
            suffix: IconButton(
              icon: const Icon(NxI.arrowRight),
              onPressed: () => _run(_controller.text),
            ),
          ),
          const SizedBox(height: 16),
          if (_searching && _results.isEmpty) const NxSkeletonList(rows: 4),
          if (_searching && _results.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
          ..._results.map(
            (h) => DenseCardTile(
              title: entityTitle(h.row, module: h.module),
              subtitle: [
                EntityModules.titleOf(h.module),
                entitySubtitle(h.row, module: h.module) ?? '',
              ].where((e) => e.isNotEmpty).join(' · '),
              onTap: () => _openHit(h),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ล่าสุด', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              TextButton(
                onPressed: () async {
                  await config.clearSearchHistory();
                  setState(() {});
                },
                child: const Text('ล้าง'),
              ),
            ],
          ),
          ...config.searchHistory.map(
            (q) => DenseCardTile(
              title: q,
              leading: const Icon(NxI.clockCounterClockwise),
              onTap: () {
                _controller.text = q;
                _run(q);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Hit {
  _Hit({required this.module, required this.row});
  final String module;
  final Map<String, dynamic> row;
}
