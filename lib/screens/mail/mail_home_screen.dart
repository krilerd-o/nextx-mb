import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/nx_breakpoint.dart';
import '../../core/nx_page_route.dart';
import '../../services/api_client.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_split_view.dart';
import '../../core/html_display.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';

class MailHomeScreen extends StatefulWidget {
  const MailHomeScreen({super.key});

  @override
  State<MailHomeScreen> createState() => _MailHomeScreenState();
}

class _MailHomeScreenState extends State<MailHomeScreen> {
  var _revision = 0;
  Map<String, dynamic>? _selected;

  @override
  Widget build(BuildContext context) {
    final twoPane = NxBreakpoint.of(context).twoPane;
    return Scaffold(
      appBar: NxAppHeader(
        title: 'เมล',
        subtitle: 'อ่านอย่างเดียว',
        actions: [
          IconButton(
            onPressed: () => setState(() => _revision++),
            icon: const Icon(NxI.arrowCounterClockwise),
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getMail(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ไม่มีจดหมาย')),
        builder: (context, list) {
          final items = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in list)
                DenseCardTile(
                  title: m['subject']?.toString() ?? '(ไม่มีหัวข้อ)',
                  subtitle: [
                    m['from_name']?.toString() ?? m['from']?.toString() ?? '',
                    stripHtmlPreview(m['snippet']?.toString() ?? m['body_text']?.toString() ?? ''),
                  ].where((e) => e.isNotEmpty).join(' · '),
                  leading: const Icon(NxI.envelope),
                  onTap: () {
                    if (twoPane) {
                      setState(() => _selected = m);
                      return;
                    }
                    nxPush<void>(
                      context,
                      MailDetailScreen(id: m['id']?.toString() ?? '', preview: m),
                    );
                  },
                ),
            ],
          );
          return NxSplitView(
            list: items,
            detail: _selected == null
                ? null
                : MailDetailScreen(
                    key: ValueKey(_selected!['id']),
                    id: _selected!['id']?.toString() ?? '',
                    preview: _selected!,
                    embedded: true,
                  ),
          );
        },
      ),
    );
  }
}

class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.id,
    required this.preview,
    this.embedded = false,
  });
  final String id;
  final Map<String, dynamic> preview;
  final bool embedded;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  Map<String, dynamic>? _item;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MailDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _item = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final item = await context.read<AppConfig>().apiClient.getMailItem(widget.id);
      if (mounted) setState(() => _item = item);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _item ?? widget.preview;
    return Scaffold(
      appBar: NxAppHeader(
        title: data['subject']?.toString() ?? 'เมล',
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(formatApiError(_error!)),
          Text(data['from']?.toString() ?? data['from_name']?.toString() ?? ''),
          const SizedBox(height: 12),
          NxHtmlView(
            html: data['body_html']?.toString() ??
                data['body']?.toString() ??
                data['body_text']?.toString() ??
                data['snippet']?.toString() ??
                '',
          ),
        ],
      ),
    );
  }
}
