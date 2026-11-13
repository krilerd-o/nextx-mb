import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/i18n.dart';
import '../../core/navigation/notification_deep_link.dart';
import '../../screens/docs/document_preview.dart';
import '../../services/file_open.dart';
import '../nx_attachments.dart';
import '../nx_icons.dart';
import '../nx_media.dart';
import '../nx_overlay_panel.dart';

/// Opens a link from a comment: NEXTX links (`/modules/…`, `/workspace/…`,
/// `/calendar…` on the same server) inside the app, anything else in the browser.
Future<void> openCommentLink(BuildContext context, String url) async {
  final config = context.read<AppConfig>();
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final base = Uri.tryParse(config.apiBaseUrl);
  final sameHost = base != null && uri.host.isNotEmpty && uri.host == base.host;
  final p = uri.path;
  if (sameHost && (p.startsWith('/modules/') || p.startsWith('/workspace') || p.startsWith('/calendar'))) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push(notificationDeepLink('${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'));
      return;
    }
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }
}

String _host(String url) => (Uri.tryParse(url)?.host ?? url).replaceFirst(RegExp(r'^www\.'), '');

/// Open Graph card for a link (title, description, image) from the server's
/// unfurl endpoint; a compact link row while loading or when the site has no meta.
class NxLinkPreviewCard extends StatelessWidget {
  const NxLinkPreviewCard({super.key, required this.url, required this.fetch, this.onClose, this.compact = false});
  final String url;
  final Future<Map<String, dynamic>> Function(String url)? fetch;

  /// Shows a close button (composer: "don't attach a preview").
  final VoidCallback? onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = fetch;
    return FutureBuilder<Map<String, dynamic>>(
      future: f == null ? Future.value(const {}) : f(url).catchError((Object _) => const <String, dynamic>{}),
      builder: (context, snap) => _card(context, snap.data ?? const {}, loading: snap.connectionState != ConnectionState.done),
    );
  }

  Widget _card(BuildContext context, Map<String, dynamic> d, {required bool loading}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = '${d['title'] ?? ''}'.trim();
    final desc = '${d['description'] ?? ''}'.trim();
    final image = '${d['image'] ?? ''}'.trim();
    final site = '${d['siteName'] ?? d['site_name'] ?? ''}'.trim();
    final hasImage = image.startsWith('http') && !compact;
    return Material(
      key: ValueKey('link-preview-$url'),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openCommentLink(context, url),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 3, height: hasImage ? 76 : 52, color: cs.primary),
            if (hasImage)
              CachedNetworkImage(
                imageUrl: image,
                width: 76,
                height: 76,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox(width: 0, height: 76),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Icon(NxI.link, size: 12, color: cs.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          site.isNotEmpty ? site : _host(url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    if (loading && title.isEmpty)
                      Container(height: 10, width: 140, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: cs.outlineVariant.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)))
                    else
                      Text(
                        title.isNotEmpty ? title : url,
                        key: ValueKey('link-preview-title-$url'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    if (desc.isNotEmpty && !compact)
                      Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                key: const ValueKey('link-preview-close'),
                visualDensity: VisualDensity.compact,
                tooltip: tr('ไม่แสดงตัวอย่างลิงก์'),
                icon: const Icon(NxI.x, size: 16),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

bool _isPdf(Map<String, dynamic> a) {
  final mime = '${a['mime'] ?? a['mime_type'] ?? ''}'.toLowerCase();
  return mime.contains('pdf') || RegExp(r'\.pdf(\?|$)', caseSensitive: false).hasMatch('${nxAttachmentName(a)} ${nxAttachmentUrl(a)}'.trim());
}

bool _isVideo(Map<String, dynamic> a, String url) =>
    '${a['mime'] ?? a['mime_type'] ?? ''}'.startsWith('video/') || nxIsVideoUrl(url) || nxIsVideoUrl(nxAttachmentName(a));

/// Tap on a comment file: PDF → the app's document preview (pages, save, share,
/// print); video → the player; other files → open / share / save sheet.
Future<void> openCommentFile(BuildContext context, Map<String, dynamic> a) async {
  final api = context.read<AppConfig>().apiClient;
  final url = api.absoluteUrl(nxAttachmentUrl(a));
  final name = nxAttachmentName(a);
  if (_isVideo(a, url)) return openNxVideoPlayer(context, url, name: name);
  if (_isPdf(a)) {
    final base = name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    return openDocumentPreview(
      context,
      DocumentSource(
        title: name,
        fileBase: base.isEmpty ? 'file' : base,
        variants: [DocVariant(id: 'file', label: tr('ไฟล์แนบ'), birt: false, fetch: (api) => api.downloadFileBytes(url))],
      ),
    );
  }
  return showCommentFileActions(context, a);
}

/// Open / share / save for any attachment (long press, or files without a preview).
Future<void> showCommentFileActions(BuildContext context, Map<String, dynamic> a) async {
  final api = context.read<AppConfig>().apiClient;
  final url = api.absoluteUrl(nxAttachmentUrl(a));
  final name = nxAttachmentName(a);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final pick = await showNxBlurPanel<String>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleSmall),
          leading: Icon(nxFileStyle(a).icon, color: nxFileStyle(a).color),
        ),
        ListTile(key: const ValueKey('file-action-open'), leading: const Icon(NxI.eye), title: Text(tr('เปิดดู')), onTap: () => Navigator.pop(ctx, 'open')),
        ListTile(key: const ValueKey('file-action-share'), leading: const Icon(NxI.shareNetwork), title: Text(tr('แชร์')), onTap: () => Navigator.pop(ctx, 'share')),
        ListTile(key: const ValueKey('file-action-save'), leading: const Icon(NxI.downloadSimple), title: Text(tr('บันทึกลงเครื่อง')), onTap: () => Navigator.pop(ctx, 'save')),
      ],
    ),
  );
  if (pick == null) return;
  if (pick == 'open') return openNxFile(url);
  try {
    final bytes = await api.downloadFileBytes(url);
    if (pick == 'share') {
      await shareFileBytes(bytes, name);
    } else {
      final path = await saveFileToDevice(bytes, name);
      if (path != null) messenger?.showSnackBar(SnackBar(content: Text(tr('บันทึกไฟล์แล้ว'))));
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(tr('ดาวน์โหลดไฟล์ไม่สำเร็จ'))));
  }
}
