import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../services/photo_pipeline.dart';
import '../../widgets/nx_icons.dart';
import '../calendar/fast_take_screen.dart';
import '../calendar/visit_photo_flow.dart' show askPhotoTagMode, PhotoSource, PhotoTagMode;
import '../crm/entity_detail_parts.dart' show AttachmentStrip;
import 'journey_widgets.dart';

/// Test hooks.
@visibleForTesting
Future<List<XFile>> Function(PhotoSource source)? debugJourneyPick;
@visibleForTesting
PhotoUploader? debugJourneyUploader;

/// Photos card for a record page (job evidence photos / quotation attachments):
/// camera · Fast Take · gallery, then resize + watermark + upload in the
/// background with a live progress bar; failures can be retried.
class JourneyPhotosSection extends StatefulWidget {
  const JourneyPhotosSection({
    super.key,
    required this.module,
    required this.id,
    required this.photos,
    required this.onChanged,
    this.canEdit = true,
    this.title = 'รูปงาน',
  });

  final String module;
  final String id;

  /// Existing photos: `{url|path, name, mime}`.
  final List<Map<String, dynamic>> photos;

  /// Called after uploads (reload the record).
  final VoidCallback onChanged;
  final bool canEdit;
  final String title;

  @override
  State<JourneyPhotosSection> createState() => _JourneyPhotosSectionState();
}

class _JourneyPhotosSectionState extends State<JourneyPhotosSection> {
  PhotoBatch? _batch;

  @override
  void dispose() {
    // Uploads continue in the background; just stop listening.
    _batch?.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  PhotoBatch _newBatch(bool withLocation) {
    final api = context.read<AppConfig>().apiClient;
    final target = PhotoTarget(widget.module, widget.id);
    _batch?.removeListener(_tick);
    final b = PhotoBatch(
      target,
      withLocation: withLocation,
      uploader: debugJourneyUploader ?? defaultPhotoUploader(api),
      onFinished: (b) => _finished(api, b),
    )..addListener(_tick);
    _batch = b;
    return b;
  }

  Future<void> _finished(ApiClient api, PhotoBatch b) async {
    // Non-job records: post one comment with every uploaded photo.
    if (widget.module != 'job' && widget.module != 'activity' && b.commentAttachments.isNotEmpty) {
      try {
        await api.postEntityComment(widget.module, widget.id, tr('รูปถ่าย ${b.commentAttachments.length} รูป'), attachments: List.of(b.commentAttachments));
        b.commentAttachments.clear();
      } catch (_) {}
    }
    final v = b.value;
    if (v.uploaded > 0) HapticFeedback.mediumImpact();
    widget.onChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(v.failed == 0 ? tr('อัปโหลด ${v.uploaded} รูปแล้ว') : tr('อัปโหลดสำเร็จ ${v.uploaded} รูป ค้าง ${v.failed} รูป — แตะลองใหม่')),
    ));
  }

  Future<void> _take(PhotoSource source) async {
    if (source == PhotoSource.gallery) {
      final files = debugJourneyPick != null
          ? await debugJourneyPick!(source)
          : await ImagePicker().pickMultiImage(imageQuality: 90, maxWidth: 2560, requestFullMetadata: false);
      if (files.isEmpty || !mounted) return;
      final mode = await askPhotoTagMode(context, source: source, count: files.length);
      if (mode == null || !mounted) return;
      _newBatch(mode == PhotoTagMode.withLocation)
        ..addAll(files)
        ..close();
      return;
    }
    final mode = await askPhotoTagMode(context, source: source);
    if (mode == null || !mounted) return;
    final b = _newBatch(mode == PhotoTagMode.withLocation);
    if (debugJourneyPick != null) {
      b
        ..addAll(await debugJourneyPick!(source), fresh: true)
        ..close();
      return;
    }
    if (source == PhotoSource.camera) {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2560, requestFullMetadata: false);
      if (shot != null) b.add(shot);
      b.close();
      return;
    }
    b.shooting = true;
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<List<XFile>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => FastTakeScreen(onShot: b.add, title: widget.title)),
    );
    b.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = _batch?.value;
    final busy = v != null && v.busy;
    Widget btn(String key, IconData icon, String label, PhotoSource s) => Expanded(
          child: OutlinedButton.icon(
            key: ValueKey(key),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: widget.canEdit ? () => _take(s) : null,
            icon: Icon(icon, size: 18),
            label: Text(tr(label), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    return JourneySection(
      title: '${tr(widget.title)}${widget.photos.isEmpty ? '' : ' (${widget.photos.length})'}',
      icon: NxI.images,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.canEdit)
            Row(children: [
              btn('journey-photo-camera', NxI.camera, 'ถ่ายรูป', PhotoSource.camera),
              const SizedBox(width: 8),
              btn('journey-photo-fast', NxI.lightning, 'ถ่ายต่อเนื่อง', PhotoSource.fastTake),
              const SizedBox(width: 8),
              btn('journey-photo-gallery', NxI.image, 'คลังภาพ', PhotoSource.gallery),
            ]),
          if (v != null && (busy || v.failed > 0)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    v.locating && v.prepared == 0
                        ? tr('กำลังหาพิกัด…')
                        : v.shooting
                            ? tr('กำลังถ่าย · อัปโหลดแล้ว ${v.uploaded}/${v.total}')
                            : tr('อัปโหลด ${v.uploaded}/${v.total}'),
                    key: const ValueKey('journey-photo-progress'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (v.failed > 0 && !busy)
                  TextButton.icon(
                    key: const ValueKey('journey-photo-retry'),
                    onPressed: () => _batch?.retryFailed(),
                    icon: const Icon(NxI.arrowsClockwise, size: 16),
                    label: Text(tr('ลองใหม่ (${v.failed})')),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: v.total == 0 ? null : v.fraction, minHeight: 6),
            ),
          ],
          const SizedBox(height: 12),
          if (widget.photos.isEmpty)
            Text(tr('ยังไม่มีรูป'), style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          else
            AttachmentStrip(items: widget.photos),
        ],
      ),
    );
  }
}

/// Job evidence photos from the record (`evidence_photos` JSON).
List<Map<String, dynamic>> jobEvidencePhotos(Map<String, dynamic> row) {
  final raw = row['evidence_photos'];
  final list = raw is List ? raw : const [];
  return [
    for (final p in list)
      if (p is Map && (p['url'] ?? p['path']) != null)
        {
          'url': (p['url'] ?? '/uploads/${p['path']}').toString(),
          'name': p['name'] ?? p['caption'] ?? 'photo.jpg',
          'mime': p['mime'] ?? 'image/jpeg',
          if (p['id'] != null) 'id': p['id'],
        },
  ];
}
