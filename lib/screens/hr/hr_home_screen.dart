import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/dense_card_tile.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_avatar.dart';
import '../../widgets/nx_surface_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/nx_icons.dart';

class HrHomeScreen extends StatelessWidget {
  const HrHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        NxAppHeader.hub(),
        Expanded(
          child: _HrShortcuts(),
        ),
      ],
    );
  }
}

class _HrShortcuts extends StatelessWidget {
  const _HrShortcuts();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bp = NxBreakpoint.of(context);
    return ListView(
      padding: bp.scrollPadding(context, inShell: true),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final w = (c.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: w,
                  child: NxSurfaceCard(
                    onTap: () => context.push(AppRoutes.attendance),
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: nxAvatarColor('ลงเวลา').withOpacity(0.16),
                          child: Icon(NxI.clock, color: nxAvatarColor('ลงเวลา')),
                        ),
                        const SizedBox(height: 12),
                        Text('ลงเวลา', style: theme.textTheme.titleMedium),
                        Text('GPS + ที่อยู่', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: w,
                  child: NxSurfaceCard(
                    onTap: () => context.push(AppRoutes.leaveList),
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: nxAvatarColor('การลา').withOpacity(0.16),
                          child: Icon(NxI.note, color: nxAvatarColor('การลา')),
                        ),
                        const SizedBox(height: 12),
                        Text('การลา', style: theme.textTheme.titleMedium),
                        Text('ยอดคงเหลือ / ยื่นลา', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const SectionHeader('ทางลัด'),
        DenseCardTile(
          leading: const Icon(NxI.clock),
          title: 'Clock In / Out',
          subtitle: 'GPS + ที่อยู่',
          onTap: () => context.push(AppRoutes.attendance),
        ),
        DenseCardTile(
          leading: const Icon(NxI.note),
          title: 'การลา',
          subtitle: 'ยอดคงเหลือ / ยื่นลา / อนุมัติ',
          onTap: () => context.push(AppRoutes.leaveList),
        ),
      ],
    );
  }
}
