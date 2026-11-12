import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/i18n.dart';
import 'nx_icons.dart';
import 'nx_media.dart';

/// Attachments the way the web shows them: image thumbnails (tap = full-screen
/// viewer with zoom and swipe) and file cards with a type icon (tap = preview).
/// Accepts the shapes used across NEXTX (`url|path|file_url`,
/// `name|file_name|original_name`, `mime|mime_type`).

String nxAttachmentUrl(Map<String, dynamic> a) => '${a['url'] ?? a['path'] ?? a['file_url'] ?? a['file_path'] ?? ''}';

String nxAttachmentName(Map<String, dynamic> a) {
  final n = '${a['name'] ?? a['file_name'] ?? a['original_name'] ?? a['filename'] ?? ''}'.trim();
  if (n.isNotEmpty) return n;
  final u = nxAttachmentUrl(a);
  return u.isEmpty ? 'ไฟล์' : Uri.decodeComponent(u.split('/').last.split('?').first);
}

String _ext(Map<String, dynamic> a) {
  final n = '${nxAttachmentName(a)} ${nxAttachmentUrl(a)}'.toLowerCase();
  final m = RegExp(r'\.([a-z0-9]{2,5})(?:\?|$|\s)').allMatches(n).map((e) => e.group(1)!).toList();
  return m.isEmpty ? '' : m.first;
}

bool nxIsImageAttachment(Map<String, dynamic> a) {
  final mime = '${a['mime'] ?? a['mime_type'] ?? a['content_type'] ?? ''}'.toLowerCase();
  if (mime.startsWith('image/')) return true;
  return const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'bmp'}.contains(_ext(a));
}

/// A comment body worth showing: not empty and not just the "—" the web saves
/// for an attachment-only comment (inline images are shown as thumbnails).
bool nxCommentHasText(String html) {
  final t = html.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '').replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
  return t.isNotEmpty && t != '—' && t != '-';
}

/// Images inside rich-text HTML (`<img src="...">`), e.g. pasted into a comment.
List<Map<String, dynamic>> nxInlineImages(String html) => [
  for (final m in RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false).allMatches(html))
    if (!m.group(1)!.startsWith('data:')) {'url': m.group(1), 'name': m.group(1)!.split('/').last, 'mime': 'image/*'},
];

({IconData icon, Color color, String label}) nxFileStyle(Map<String, dynamic> a) {
  final e = _ext(a);
  return switch (e) {
    'pdf' => (icon: NxI.file, color: const Color(0xFFDC2626), label: 'PDF'),
    'doc' || 'docx' => (icon: NxI.file, color: const Color(0xFF2563EB), label: 'Word'),
    'xls' || 'xlsx' || 'csv' => (icon: NxI.file, color: const Color(0xFF16A34A), label: e == 'csv' ? 'CSV' : 'Excel'),
    'ppt' || 'pptx' => (icon: NxI.file, color: const Color(0xFFEA580C), label: 'PowerPoint'),
    'zip' || 'rar' || '7z' => (icon: NxI.file, color: const Color(0xFF7C3AED), label: e.toUpperCase()),
    'mp4' || 'mov' || 'webm' => (icon: NxI.videoCamera, color: const Color(0xFF0EA5E9), label: 'Video'),
    'mp3' || 'm4a' || 'wav' || 'ogg' => (icon: NxI.microphone, color: const Color(0xFFDB2777), label: 'Audio'),
    _ => (icon: NxI.paperclip, color: const Color(0xFF64748B), label: e.isEmpty ? 'ไฟล์' : e.toUpperCase()),
  };
}

String _size(dynamic bytes) {
  final b = num.tryParse('${bytes ?? ''}');
  if (b == null || b <= 0) return '';
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Preview a file: PDFs / Office / media open in the in-app browser (like a
/// new tab on the web); anything else outside the app.
Future<void> openNxFile(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class NxAttachmentStrip extends StatelessWidget {
  const NxAttachmentStrip({super.key, required this.items, this.onRemove, this.thumb = 84});
  final List<Map<String, dynamic>> items;

  /// Shows a remove button on each item.
  final ValueChanged<Map<String, dynamic>>? onRemove;
  final double thumb;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final images = items.where(nxIsImageAttachment).toList();
    final files = items.where((a) => !nxIsImageAttachment(a)).toList();
    final urls = [for (final a in images) api.absoluteUrl(nxAttachmentUrl(a))];
    final names = [for (final a in images) nxAttachmentName(a)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < images.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      key: ValueKey('nx-att-img-$i'),
                      onTap: () => openNxImageViewer(context, urls, i, names: names),
                      child: Hero(
                        tag: 'nx-att-${urls[i]}-$i',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image(
                            image: ResizeImage(CachedNetworkImageProvider(urls[i]), width: (thumb * 3).round()),
                            width: thumb,
                            height: thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: thumb,
                              height: thumb,
                              color: cs.surfaceContainerHighest,
                              child: Icon(NxI.image, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (onRemove != null) _removeBadge(cs, () => onRemove!(images[i])),
                  ],
                ),
            ],
          ),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 8),
        for (final f in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: ValueKey('nx-att-file-${nxAttachmentName(f)}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  final url = api.absoluteUrl(nxAttachmentUrl(f));
                  // Videos play in the app; other files open in the preview browser.
                  nxIsVideoUrl(url) || nxIsVideoUrl(nxAttachmentName(f)) || '${f['mime'] ?? f['mime_type'] ?? ''}'.startsWith('video/')
                      ? openNxVideoPlayer(context, url, name: nxAttachmentName(f))
                      : openNxFile(url);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Row(
                    children: [
                      Builder(
                        builder: (_) {
                          final st = nxFileStyle(f);
                          return Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: st.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(st.icon, size: 15, color: st.color),
                                Text(
                                  st.label.length > 5 ? st.label.substring(0, 4) : st.label,
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: st.color),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nxAttachmentName(f),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (_size(f['size'] ?? f['file_size']).isNotEmpty) Text(_size(f['size'] ?? f['file_size']), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (onRemove != null)
                        IconButton(tooltip: tr('นำออก'), icon: const Icon(NxI.x, size: 18), onPressed: () => onRemove!(f))
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(NxI.arrowSquareOut, size: 16, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _removeBadge(ColorScheme cs, VoidCallback onTap) => Positioned(
    top: -6,
    right: -6,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: cs.surface,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: const Icon(NxI.x, size: 13),
      ),
    ),
  );
}

Future<void> openNxImageViewer(BuildContext context, List<String> urls, int initial, {List<String>? names}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, _, _) => _NxImageViewer(urls: urls, initial: initial, names: names),
      transitionsBuilder: (context, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

class _NxImageViewer extends StatefulWidget {
  const _NxImageViewer({required this.urls, required this.initial, this.names});
  final List<String> urls;
  final int initial;
  final List<String>? names;

  @override
  State<_NxImageViewer> createState() => _NxImageViewerState();
}

class _NxImageViewerState extends State<_NxImageViewer> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  final _zoom = TransformationController();
  double _dragY = 0;
  bool _zoomed = false;
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _page.dispose();
    _zoom.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final p = _doubleTap?.localPosition ?? Offset.zero;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.names != null && _i < widget.names!.length ? widget.names![_i] : '';
    // Drag down to close: the photo follows the finger and the black fades.
    final fade = (1 - (_dragY.abs() / 400)).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: fade),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty) Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            if (widget.urls.length > 1) Text('${_i + 1} / ${widget.urls.length}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(key: const ValueKey('image-download'), tooltip: tr('ดาวน์โหลด'), icon: const Icon(NxI.downloadSimple), onPressed: () => nxSaveMedia(context, widget.urls[_i], video: false)),
          IconButton(tooltip: tr('เปิดในเบราว์เซอร์'), icon: const Icon(NxI.arrowSquareOut), onPressed: () => openNxFile(widget.urls[_i])),
          IconButton(tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork), onPressed: () => Share.share(widget.urls[_i])),
        ],
      ),
      body: GestureDetector(
        key: const ValueKey('image-viewer-body'),
        onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _dragY += d.delta.dy),
        onVerticalDragEnd: _zoomed
            ? null
            : (d) {
                if (_dragY.abs() > 120 || (d.primaryVelocity ?? 0).abs() > 900) {
                  Navigator.of(context).maybePop();
                } else {
                  setState(() => _dragY = 0);
                }
              },
        onDoubleTapDown: (d) => _doubleTap = d,
        onDoubleTap: _toggleZoom,
        child: AnimatedContainer(
          duration: Duration(milliseconds: _dragY == 0 ? 200 : 0),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _dragY, 0)..scaleByDouble(1 - (_dragY.abs() / 2000).clamp(0, 0.15), 1 - (_dragY.abs() / 2000).clamp(0, 0.15), 1, 1),
          transformAlignment: Alignment.center,
          child: PageView.builder(
            controller: _page,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.urls.length,
            onPageChanged: (i) {
              _zoom.value = Matrix4.identity();
              setState(() => _i = i);
            },
            itemBuilder: (context, i) => InteractiveViewer(
              transformationController: i == _i ? _zoom : null,
              panEnabled: _zoomed,
              maxScale: 5,
              child: Center(
                child: Hero(
                  tag: 'nx-att-${widget.urls[i]}-$i',
                  child: Image(
                    image: CachedNetworkImageProvider(widget.urls[i]),
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                    errorBuilder: (_, _, _) => const Icon(NxI.image, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
