import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/html_display.dart';
import '../../core/navigation/notification_deep_link.dart';
import '../../services/realtime_service.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.addListener(_onLive);
  }

  @override
  void dispose() {
    RealtimeService.instance.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    if (!mounted) return;
    setState(() => _revision++);
  }

  void _open(Map<String, dynamic> item) {
    final path = item['link_path']?.toString() ?? '';
    context.read<AppConfig>().apiClient.markNotificationRead(item['id'].toString());
    context.push(
      notificationDeepLink(
        path,
        linkId: item['link_id']?.toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NxAppHeader(
        title: 'การแจ้งเตือน',
        menu: [
          NxHeaderMenuItem(
            label: 'อ่านทั้งหมด',
            icon: NxI.checkCircle,
            onTap: () async {
              await context.read<AppConfig>().apiClient.markAllNotificationsRead();
              if (mounted) setState(() => _revision++);
            },
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getNotifications(),
        skeleton: const NxSkeletonList(),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ไม่มีการแจ้งเตือน')),
        builder: (context, items) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final it in items)
                DenseCardTile(
                  leading: Icon(
                    it['read_at'] == null
                        ? NxI.bellRinging
                        : NxI.bell,
                  ),
                  title: stripHtmlPreview(it['title']?.toString() ?? '', maxLen: 80),
                  subtitle: stripHtmlPreview(it['body']?.toString() ?? '', maxLen: 120),
                  onTap: () => _open(it),
                ),
            ],
          );
        },
      ),
    );
  }
}
