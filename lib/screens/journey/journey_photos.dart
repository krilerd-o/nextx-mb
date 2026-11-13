import 'package:cached_network_image/cached_network_image.dart';
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
import '../calendar/visit_photo_grid.dart' show confirmDeleteVisitPhoto, showVisitPhotoActions;
import '../../widgets/nx_attachments.dart';
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
    this.compact = false,
  });

  /// Gallery look (job summary): slim add buttons in the header row, the
  /// grid underneath; photos can be deleted (long-press or the viewer's trash).
  final bool compact;

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

  /// Remove one job photo (`PUT /jobs/:id/photos {remove}` — atomic, does not
  /// touch uploads still in flight).
  Future<bool> _delete(Map<String, dynamic> photo) async {
    final id = '${photo['id'] ?? ''}';
    if (id.isEmpty) return false;
    final api = context.read<AppConfig>().apiClient;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await api.editJobPhotos(widget.id, remove: [id]);
      HapticFeedback.mediumImpact();
      widget.onChanged();
      messenger?.showSnackBar(SnackBar(content: Text(tr('ลบรูปแล้ว'))));
      return true;
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(tr(formatApiError(e)))));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = _batch?.value;
    final busy = v != null && v.busy;
    final images = widget.photos.where(nxIsImageAttachment).toList();
    final files = widget.photos.where((a) => !nxIsImageAttachment(a)).toList();
    final pending = v == null ? 0 : (v.total - v.uploaded - v.failed).clamp(0, 99);
    final failed = v == null || busy ? 0 : v.failed;
    return JourneySection(
      title: tr(widget.title),
      icon: NxI.images,
      trailing: images.isEmpty
          ? null
          : Container(
              key: const ValueKey('journey-photo-count'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
              child: Text('${images.length}', style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.canEdit && widget.compact)
            Row(children: [
              Expanded(child: _SlimAction(key: const ValueKey('journey-photo-camera'), icon: NxI.camera, label: 'ถ่ายรูป', color: cs.primary, primary: true, onTap: () => _take(PhotoSource.camera))),
              const SizedBox(width: 6),
              Expanded(child: _SlimAction(key: const ValueKey('journey-photo-fast'), icon: NxI.lightning, label: 'ต่อเนื่อง', color: const Color(0xFFF59E0B), onTap: () => _take(PhotoSource.fastTake))),
              const SizedBox(width: 6),
              Expanded(child: _SlimAction(key: const ValueKey('journey-photo-gallery'), icon: NxI.image, label: 'คลังภาพ', color: const Color(0xFF0D9488), onTap: () => _take(PhotoSource.gallery))),
            ])
          else if (widget.canEdit)
            Row(children: [
              Expanded(
                child: _PhotoAction(
                  key: const ValueKey('journey-photo-camera'),
                  icon: NxI.camera,
                  label: 'ถ่ายรูป',
                  hint: 'ทีละรูป',
                  color: cs.primary,
                  primary: true,
                  onTap: () => _take(PhotoSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PhotoAction(
                  key: const ValueKey('journey-photo-fast'),
                  icon: NxI.lightning,
                  label: 'ถ่ายต่อเนื่อง',
                  hint: 'สูงสุด 30 รูป',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _take(PhotoSource.fastTake),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PhotoAction(
                  key: const ValueKey('journey-photo-gallery'),
                  icon: NxI.image,
                  label: 'คลังภาพ',
                  hint: 'เลือกหลายรูป',
                  color: const Color(0xFF0D9488),
                  onTap: () => _take(PhotoSource.gallery),
                ),
              ),
            ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: v != null && (busy || v.failed > 0)
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(
                        children: [
                          Icon(busy ? NxI.cloud : NxI.warning, size: 16, color: busy ? cs.primary : cs.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              v.locating && v.prepared == 0
                                  ? tr('กำลังหาพิกัด…')
                                  : v.shooting
                                      ? tr('กำลังถ่าย · อัปโหลดแล้ว ${v.uploaded}/${v.total}')
                                      : tr('อัปโหลด ${v.uploaded}/${v.total}'),
                              key: const ValueKey('journey-photo-progress'),
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: v.total == 0 ? 0 : v.fraction),
                          duration: const Duration(milliseconds: 300),
                          builder: (_, f, _) => LinearProgressIndicator(value: v.total == 0 ? null : f, minHeight: 6),
                        ),
                      ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          if (images.isEmpty && pending == 0 && failed == 0)
            _EmptyPhotos(canEdit: widget.canEdit)
          else
            JourneyPhotoGrid(
              items: images,
              pending: pending,
              failed: failed,
              onRetry: () => _batch?.retryFailed(),
              onDelete: widget.compact && widget.canEdit && widget.module == 'job' ? _delete : null,
            ),
          if (files.isNotEmpty) ...[
            const SizedBox(height: 10),
            NxAttachmentStrip(items: files),
          ],
        ],
      ),
    );
  }
}

/// Slim add button: tinted pill, icon + label on one line.
class _SlimAction extends StatelessWidget {
  const _SlimAction({super.key, required this.icon, required this.label, required this.color, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final fg = primary ? cs.onPrimary : color;
    return Material(
      color: primary ? color : color.withValues(alpha: dark ? 0.16 : 0.09),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tr(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: primary ? cs.onPrimary : cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Big tap target: tinted tile, icon in a circle, label + small hint.
class _PhotoAction extends StatefulWidget {
  const _PhotoAction({super.key, required this.icon, required this.label, required this.hint, required this.color, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final String hint;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_PhotoAction> createState() => _PhotoActionState();
}

class _PhotoActionState extends State<_PhotoAction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final c = widget.color;
    final fg = widget.primary ? cs.onPrimary : c;
    return Semantics(
      button: true,
      label: tr(widget.label),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: widget.primary ? c : c.withValues(alpha: dark ? 0.16 : 0.09),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onHighlightChanged: (v) => setState(() => _down = v),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primary ? Colors.white.withValues(alpha: 0.2) : c.withValues(alpha: dark ? 0.24 : 0.16),
                    ),
                    child: Icon(widget.icon, size: 21, color: fg),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(widget.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: widget.primary ? cs.onPrimary : cs.onSurface),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tr(widget.hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: widget.primary ? cs.onPrimary.withValues(alpha: 0.8) : cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPhotos extends StatelessWidget {
  const _EmptyPhotos({required this.canEdit});
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: const ValueKey('journey-photo-empty'),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(NxI.images, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              tr(canEdit ? 'ยังไม่มีรูป — ถ่ายหรือเลือกจากคลังภาพ' : 'ยังไม่มีรูป'),
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 5 square photos per row. Tap = the photo grows into the full-screen viewer
/// (Hero). More than two rows fold into "+N" and "ดูทั้งหมด"; uploads in
/// progress show as placeholder squares.
class JourneyPhotoGrid extends StatefulWidget {
  const JourneyPhotoGrid({super.key, required this.items, this.pending = 0, this.failed = 0, this.onRetry, this.columns = 5, this.foldRows = 2, this.onDelete});
  final List<Map<String, dynamic>> items;

  /// Delete one photo (true = deleted). Long-press a thumbnail or the
  /// viewer's trash; both ask "ลบรูปนี้?" first.
  final Future<bool> Function(Map<String, dynamic> photo)? onDelete;
  final int pending;
  final int failed;
  final VoidCallback? onRetry;
  final int columns;
  final int foldRows;

  @override
  State<JourneyPhotoGrid> createState() => _JourneyPhotoGridState();
}

class _JourneyPhotoGridState extends State<JourneyPhotoGrid> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final urls = [for (final a in widget.items) api.absoluteUrl(nxAttachmentUrl(a))];
    final names = [for (final a in widget.items) nxAttachmentName(a)];
    final extra = widget.pending + widget.failed;
    final fold = widget.columns * widget.foldRows;
    final total = urls.length + extra;
    final folded = !_all && total > fold;
    final shownPhotos = folded ? (fold - 1 - extra).clamp(0, urls.length) : urls.length;
    final hidden = urls.length - shownPhotos;
    const gap = 6.0;
    final del = widget.onDelete;
    Future<bool> confirmAndDelete(int i) async {
      if (del == null || i < 0 || i >= widget.items.length) return false;
      final ok = await confirmDeleteVisitPhoto(context, url: urls[i], message: 'รูปจะถูกลบออกจากใบสั่งงานนี้ และกู้คืนไม่ได้');
      if (!ok) return false;
      return del(widget.items[i]);
    }

    return LayoutBuilder(builder: (context, box) {
      final side = (box.maxWidth - gap * (widget.columns - 1)) / widget.columns;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      Widget square(Widget child) => SizedBox(width: side, height: side, child: child);
      final tiles = <Widget>[
        for (var i = 0; i < widget.pending; i++)
          square(Container(
            key: ValueKey('journey-photo-pending-$i'),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
          )),
        for (var i = 0; i < widget.failed; i++)
          square(Material(
            color: cs.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('journey-photo-failed-$i'),
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onRetry,
              child: Icon(NxI.arrowsClockwise, size: 18, color: cs.error),
            ),
          )),
        for (var i = 0; i < shownPhotos; i++)
          square(_PhotoThumb(
            key: ValueKey('journey-photo-$i'),
            url: urls[i],
            heroTag: 'nx-att-${urls[i]}-$i',
            cacheWidth: (side * dpr).round(),
            index: i,
            onTap: () => openNxImageViewer(context, urls, i, names: names, onDelete: del == null ? null : confirmAndDelete),
            onLongPress: del == null
                ? null
                : () async {
                    HapticFeedback.mediumImpact();
                    final action = await showVisitPhotoActions(context, urls[i]);
                    if (action == 'delete' && context.mounted) await confirmAndDelete(i);
                  },
          )),
        if (folded && hidden > 0)
          square(Material(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('journey-photo-more'),
              onTap: () => setState(() => _all = true),
              child: Stack(fit: StackFit.expand, children: [
                if (shownPhotos < urls.length)
                  Opacity(
                    opacity: 0.35,
                    child: Image(
                      image: ResizeImage(CachedNetworkImageProvider(urls[shownPhotos]), width: (side * dpr).round()),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                Center(child: Text('+$hidden', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              ]),
            ),
          )),
      ];
      return AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: gap, runSpacing: gap, children: tiles),
            if (_all && total > fold)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('journey-photo-less'),
                  onPressed: () => setState(() => _all = false),
                  icon: const Icon(NxI.caretUp, size: 16),
                  label: Text(tr('ย่อ')),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _PhotoThumb extends StatefulWidget {
  const _PhotoThumb({super.key, required this.url, required this.heroTag, required this.cacheWidth, required this.index, required this.onTap, this.onLongPress});
  final VoidCallback? onLongPress;
  final String url;
  final String heroTag;
  final int cacheWidth;
  final int index;
  final VoidCallback onTap;

  @override
  State<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<_PhotoThumb> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Pop in one after another the first time the grid shows.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (widget.index % 10) * 30),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: 0.85 + 0.15 * t, child: child)),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                setState(() => _down = false);
                widget.onLongPress!();
              },
        onTap: () {
          setState(() => _down = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 110),
          child: Hero(
            tag: widget.heroTag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(
                image: ResizeImage(CachedNetworkImageProvider(widget.url), width: widget.cacheWidth),
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : Container(color: cs.surfaceContainerHighest),
                errorBuilder: (_, _, _) => Container(color: cs.surfaceContainerHighest, child: Icon(NxI.image, color: cs.onSurfaceVariant)),
              ),
            ),
          ),
        ),
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
