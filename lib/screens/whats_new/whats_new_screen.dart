import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../services/api_exceptions.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import '../../widgets/nx_html_view.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_surface_card.dart';

/// Thai label + colour for an announcement `type`.
(String, Color) whatsNewType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'feature':
    case 'new':
      return ('ฟีเจอร์ใหม่', const Color(0xFF6366F1));
    case 'improvement':
    case 'improve':
      return ('ปรับปรุง', const Color(0xFF0EA5E9));
    case 'fix':
    case 'bugfix':
      return ('แก้ไข', const Color(0xFF16A34A));
    case 'release':
      return ('เวอร์ชันใหม่', const Color(0xFFEC4899));
    default:
      return ('ประกาศ', const Color(0xFF64748B));
  }
}

/// Release notes from the web ("มีอะไรใหม่"); opening marks them viewed.
class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  List<Map<String, dynamic>>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppConfig>().apiClient;
    try {
      final rows = await api.getWhatsNew();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _error = null;
      });
      api
          .markWhatsNewViewed([
            for (final r in rows)
              if (int.tryParse('${r['id']}') case final id?) id,
          ])
          .catchError((_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _ack(Map<String, dynamic> it) async {
    final id = int.tryParse('${it['id']}');
    if (id == null) return;
    setState(() => it['acknowledged'] = true);
    try {
      await context.read<AppConfig>().apiClient.ackWhatsNew(id);
    } catch (e) {
      if (!mounted) return;
      setState(() => it['acknowledged'] = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final items = _items;
    Widget body;
    if (_error != null && items == null) {
      body = Center(
        child: TextButton(
          onPressed: _load,
          child: Text(
            '${formatApiError(_error!)}\nลองใหม่',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (items == null) {
      body = const NxSkeletonList();
    } else if (items.isEmpty) {
      body = Center(
        child: Text('ยังไม่มีประกาศ', style: theme.textTheme.bodyLarge),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) => ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              8 + NxScrollScaffold.topInset(context),
              16,
              32,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final it = items[i];
              final (label, color) = whatsNewType(it['type']?.toString());
              final acked = it['acknowledged'] == true;
              final link = it['link_path']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NxSurfaceCard(
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            it['date']?.toString().split('T').first ?? '',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        (it['title_th'] ?? it['title_en'] ?? '').toString(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      NxHtmlView(
                        html:
                            (it['description_th'] ?? it['description_en'] ?? '')
                                .toString(),
                      ),
                      Row(
                        children: [
                          if (link.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                final base = context
                                    .read<AppConfig>()
                                    .apiBaseUrl
                                    .replaceAll(RegExp(r'/+$'), '');
                                launchUrl(
                                  Uri.parse(
                                    link.startsWith('http')
                                        ? link
                                        : '$base$link',
                                  ),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                              icon: const Icon(NxI.arrowSquareOut, size: 16),
                              label: Text(
                                (it['link_label_th'] ?? 'เปิดดู').toString(),
                              ),
                            ),
                          const Spacer(),
                          acked
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'รับทราบแล้ว',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                )
                              : TextButton(
                                  onPressed: () => _ack(it),
                                  child: const Text('รับทราบ'),
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return NxScrollScaffold(
      insetBody: false,
      header: const NxAppHeader(title: 'มีอะไรใหม่'),
      body: body,
    );
  }
}
