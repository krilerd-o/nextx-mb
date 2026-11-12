import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_attachments.dart';
import '../../widgets/nx_icons.dart';

/// URL of a visit photo from `GET /api/activity/:id/visit` (`{id, url, path}`).
String visitPhotoUrl(Map<String, dynamic> p) => '${p['url'] ?? '/uploads/${p['path']}'}';

/// Visit photos as a grid of [perRow] square thumbnails. Tap = full-screen
/// viewer; with [onDelete], long-press a thumbnail (or the viewer's trash
/// button) asks "ลบรูปนี้?" and then calls [onDelete] (returns true when the
/// photo was deleted on the server).
class VisitPhotoGrid extends StatelessWidget {
  const VisitPhotoGrid({super.key, required this.photos, this.onDelete, this.perRow = 5, this.gap = 6});

  final List<Map<String, dynamic>> photos;
  final Future<bool> Function(Map<String, dynamic> photo)? onDelete;
  final int perRow;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final cs = Theme.of(context).colorScheme;
    final urls = [for (final p in photos) api.absoluteUrl(visitPhotoUrl(p))];
    final names = [
      for (final p in photos) nxAttachmentName({'url': visitPhotoUrl(p), 'name': p['name']}),
    ];
    final del = onDelete;

    Future<bool> confirmAndDelete(int i) async {
      if (del == null || i < 0 || i >= photos.length) return false;
      final ok = await confirmDeleteVisitPhoto(context, url: urls[i]);
      if (!ok) return false;
      return del(photos[i]);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final size = ((c.maxWidth - gap * (perRow - 1)) / perRow).floorToDouble().clamp(24.0, 200.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < photos.length; i++)
              GestureDetector(
                key: ValueKey('visit-photo-$i'),
                onTap: () => openNxImageViewer(context, urls, i, names: names, onDelete: del == null ? null : confirmAndDelete),
                onLongPress: del == null
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        final action = await _photoActions(context, urls[i]);
                        if (action == 'delete' && context.mounted) await confirmAndDelete(i);
                      },
                child: Hero(
                  tag: 'nx-att-${urls[i]}-$i',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image(
                      image: ResizeImage(CachedNetworkImageProvider(urls[i]), width: (size * 3).round()),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: size,
                        height: size,
                        color: cs.surfaceContainerHighest,
                        child: Icon(NxI.image, color: cs.onSurfaceVariant, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Widget _preview(BuildContext context, String url) {
  final cs = Theme.of(context).colorScheme;
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image(
      image: ResizeImage(CachedNetworkImageProvider(url), width: 240),
      width: 72,
      height: 72,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: 72,
        height: 72,
        color: cs.surfaceContainerHighest,
        child: Icon(NxI.image, color: cs.onSurfaceVariant),
      ),
    ),
  );
}

/// Long-press menu of a photo: "ดูรูป" / "ลบรูป".
Future<String?> _photoActions(BuildContext context, String url) {
  return showAppBottomSheet<String>(
    context: context,
    title: null,
    child: Builder(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _preview(ctx, url)),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('visit-photo-action-delete'),
              leading: Icon(NxI.trash, color: cs.error),
              title: Text(
                tr('ลบรูป'),
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        );
      },
    ),
  );
}

/// "ลบรูปนี้?" confirm sheet. True = the user confirmed.
Future<bool> confirmDeleteVisitPhoto(BuildContext context, {String? url}) async {
  final ok = await showAppBottomSheet<bool>(
    context: context,
    title: 'ลบรูปนี้?',
    child: Builder(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (url != null) ...[_preview(ctx, url), const SizedBox(width: 12)],
                Expanded(
                  child: Text(tr('รูปจะถูกลบออกจากการเข้าพบนี้ และกู้คืนไม่ได้'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(key: const ValueKey('visit-photo-delete-cancel'), onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('ยกเลิก'))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('visit-photo-delete-confirm'),
                    style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: const Icon(NxI.trash, size: 18),
                    label: Text(tr('ลบรูป')),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  return ok == true;
}
