import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_cached_future.dart';
import '../../widgets/nx_select_tile.dart';
import '../../widgets/nx_skeleton.dart';
import '../../widgets/nx_icons.dart';

class BusinessHubScreen extends StatefulWidget {
  const BusinessHubScreen({super.key});

  @override
  State<BusinessHubScreen> createState() => _BusinessHubScreenState();
}

class _BusinessHubScreenState extends State<BusinessHubScreen> {
  var _revision = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NxAppHeader(
        title: 'เลือกพื้นที่ทำงาน',
        subtitle: 'ธุรกิจที่คุณเข้าถึงได้',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(onPressed: () => setState(() => _revision++), icon: const Icon(NxI.arrowCounterClockwise), tooltip: 'รีเฟรช'),
          TextButton(
            onPressed: () => context.read<AppConfig>().logout(),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
      body: NxCachedFuture<List<Map<String, dynamic>>>(
        revision: _revision,
        load: () => context.read<AppConfig>().apiClient.getBusinesses(),
        skeleton: const NxSkeletonList(rows: 4),
        isEmpty: (list) => list.isEmpty,
        empty: const Center(child: Text('ยังไม่มีธุรกิจที่เข้าถึงได้')),
        builder: (context, businesses) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              for (final b in businesses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NxSelectTile(
                    title: b['business_name']?.toString() ?? 'ธุรกิจ',
                    subtitle: [
                      if ((b['business_code']?.toString() ?? '').isNotEmpty) 'รหัส: ${b['business_code']}',
                      b['default_package_code']?.toString() ?? b['user_default_package_code']?.toString(),
                    ].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
                    onTap: () async {
                      await context.read<AppConfig>().selectBusiness(
                            businessId: b['id']?.toString() ?? '',
                            businessName: b['business_name']?.toString() ?? 'ธุรกิจ',
                            packageCode: b['default_package_code']?.toString() ??
                                b['user_default_package_code']?.toString(),
                          );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
