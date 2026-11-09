import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/app_config.dart';
import '../../../core/chat_format.dart';
import '../../../core/i18n.dart';
import '../../../widgets/nx_attachments.dart' show openNxImageViewer;
import '../../../widgets/nx_icons.dart';
import '../../../widgets/nx_media.dart';

/// Attachments of one message: images as a grid, then videos, voice messages and files.
class ChatAttachments extends StatelessWidget {
  const ChatAttachments({super.key, required this.attachments, required this.mine});
  final List<Map<String, dynamic>> attachments;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    String kindOf(Map<String, dynamic> a) => chatAttachmentKind(a['mime_type']?.toString(), a['file_name']?.toString());
    final images = attachments.where((a) => kindOf(a) == 'image').toList();
    final others = attachments.where((a) => kindOf(a) != 'image').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty) ChatImageGrid(images: images),
        for (final a in others)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: switch (kindOf(a)) {
              'audio' => ChatVoicePlayer(url: api.chatFileUrl(a['file_path']?.toString()), name: a['file_name']?.toString(), mine: mine),
              'video' => SizedBox(width: 240, child: NxVideoTile(url: api.chatFileUrl(a['file_path']?.toString()), name: a['file_name']?.toString())),
              _ => ChatFileCard(attachment: a, mine: mine),
            },
          ),
      ],
    );
  }
}

/// 1 image large, 2 side by side, 3+ in a 2-column grid ("+N" on the 4th).
class ChatImageGrid extends StatelessWidget {
  const ChatImageGrid({super.key, required this.images});
  final List<Map<String, dynamic>> images;

  @override
  Widget build(BuildContext context) {
    final api = context.read<AppConfig>().apiClient;
    final urls = [for (final a in images) api.chatFileUrl(a['file_path']?.toString())];
    final names = [for (final a in images) a['file_name']?.toString() ?? ''];
    Widget tile(int i, {double? w, double? h, int extra = 0}) => GestureDetector(
          key: ValueKey('chat-img-$i'),
          onTap: () => openNxImageViewer(context, urls, i, names: names),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(fit: StackFit.expand, children: [
                ChatNetworkImage(urls: api.chatFileUrls(images[i]['file_path']?.toString())),
                if (extra > 0)
                  Container(
                    color: Colors.black45,
                    alignment: Alignment.center,
                    child: Text('+$extra', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        );
    if (images.length == 1) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240, maxHeight: 260), child: tile(0)),
      );
    }
    const size = 118.0;
    final shown = images.length > 4 ? 4 : images.length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: size * 2 + 4,
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < shown; i++) tile(i, w: size, h: size, extra: i == 3 ? images.length - 4 : 0),
          ],
        ),
      ),
    );
  }
}

/// Tries each URL in turn until one loads (static /uploads first, then /api/chat/upload).
class ChatNetworkImage extends StatefulWidget {
  const ChatNetworkImage({super.key, required this.urls, this.fit = BoxFit.cover});
  final List<String> urls;
  final BoxFit fit;

  @override
  State<ChatNetworkImage> createState() => _ChatNetworkImageState();
}

class _ChatNetworkImageState extends State<ChatNetworkImage> {
  var _i = 0;

  @override
  Widget build(BuildContext context) {
    if (_i >= widget.urls.length) {
      return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Center(child: Icon(NxI.image)));
    }
    return Image(
      image: ResizeImage(CachedNetworkImageProvider(widget.urls[_i]), width: 720, policy: ResizeImagePolicy.fit),
      key: ValueKey(widget.urls[_i]),
      fit: widget.fit,
      errorBuilder: (_, _, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _i++);
        });
        return const SizedBox(width: 48, height: 48);
      },
    );
  }
}

String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Voice message: play / pause, seekable bars, time and speed (only one plays at a time).
class ChatVoicePlayer extends StatefulWidget {
  const ChatVoicePlayer({super.key, required this.url, this.name, this.mine = false});
  final String url;
  final String? name;
  final bool mine;

  @override
  State<ChatVoicePlayer> createState() => _ChatVoicePlayerState();
}

class _ChatVoicePlayerState extends State<ChatVoicePlayer> {
  static _ChatVoicePlayerState? _playing;
  VideoPlayerController? _c;
  var _loading = false;
  var _failed = false;
  var _rate = 1.0;
  late final List<double> _bars = _shape(widget.name ?? widget.url);

  static List<double> _shape(String seed) {
    var h = 2166136261;
    for (final c in seed.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xffffffff;
    }
    return List.generate(28, (_) {
      h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff;
      return 0.25 + (h % 1000) / 1333;
    });
  }

  @override
  void dispose() {
    if (_playing == this) _playing = null;
    _c?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_failed) {
      final uri = Uri.tryParse(widget.url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    var c = _c;
    if (c == null) {
      setState(() => _loading = true);
      c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      try {
        await c.initialize();
        c.addListener(() {
          if (!mounted) return;
          final v = c!.value;
          if (v.isCompleted && v.position >= v.duration) {
            c.pause();
            c.seekTo(Duration.zero);
          }
          setState(() {});
        });
        _c = c;
      } catch (_) {
        await c.dispose();
        if (mounted) setState(() => _failed = true);
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      final other = _playing;
      if (other != null && other != this) await other._c?.pause();
      _playing = this;
      await c.setPlaybackSpeed(_rate);
      await c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _c?.value;
    final pos = v?.position ?? Duration.zero;
    final dur = v?.duration ?? Duration.zero;
    final progress = dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;
    final fg = widget.mine ? cs.onPrimary : cs.onSurface;
    final active = widget.mine ? cs.onPrimary : cs.primary;
    final idle = fg.withValues(alpha: 0.3);
    return SizedBox(
      width: 236,
      child: Row(children: [
        InkResponse(
          key: const ValueKey('chat-voice-play'),
          onTap: _toggle,
          radius: 22,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: widget.mine ? cs.onPrimary.withValues(alpha: 0.2) : cs.primary,
            child: _loading
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: widget.mine ? cs.onPrimary : cs.onPrimary))
                : Icon(_failed ? NxI.downloadSimple : (v?.isPlaying == true ? NxI.pause : NxI.play), size: 18, color: cs.onPrimary),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTapDown: (d) {
              final box = context.findRenderObject() as RenderBox?;
              final c = _c;
              if (box == null || c == null || dur == Duration.zero) return;
              final w = box.size.width - 44 - 8 - 52;
              final f = ((d.localPosition.dx) / (w <= 0 ? 1 : w)).clamp(0.0, 1.0);
              c.seekTo(dur * f);
            },
            child: SizedBox(
              height: 28,
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                for (var i = 0; i < _bars.length; i++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 28 * _bars[i],
                      decoration: BoxDecoration(color: i / _bars.length <= progress ? active : idle, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          child: Text(_failed ? tr('เปิด') : _fmt(pos > Duration.zero ? pos : dur), style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8), fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        GestureDetector(
          onTap: () {
            setState(() => _rate = _rate == 1 ? 1.5 : _rate == 1.5 ? 2 : 1);
            _c?.setPlaybackSpeed(_rate);
          },
          child: Text('${_rate == _rate.roundToDouble() ? _rate.toInt() : _rate}×', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ),
      ]),
    );
  }
}

IconData _fileIcon(String name, String mime) {
  final ext = name.split('.').last.toLowerCase();
  if (mime.contains('pdf') || ext == 'pdf') return NxI.filePdf;
  if (mime.contains('sheet') || const ['xls', 'xlsx', 'csv'].contains(ext)) return NxI.fileXls;
  if (mime.contains('word') || const ['doc', 'docx'].contains(ext)) return NxI.fileDoc;
  if (const ['zip', 'rar', '7z'].contains(ext)) return NxI.fileZip;
  return NxI.file;
}

String _size(dynamic raw) {
  final n = num.tryParse('${raw ?? ''}') ?? 0;
  if (n <= 0) return '';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(n < 10240 ? 1 : 0)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

class ChatFileCard extends StatelessWidget {
  const ChatFileCard({super.key, required this.attachment, required this.mine});
  final Map<String, dynamic> attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final api = context.read<AppConfig>().apiClient;
    final name = attachment['file_name']?.toString() ?? 'ไฟล์';
    final url = api.chatFileUrl(attachment['file_path']?.toString());
    final fg = mine ? cs.onPrimary : cs.onSurface;
    return Material(
      color: mine ? cs.onPrimary.withValues(alpha: 0.14) : cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_fileIcon(name, attachment['mime_type']?.toString() ?? ''), color: fg, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
                if (_size(attachment['file_size']).isNotEmpty)
                  Text(_size(attachment['file_size']), style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(NxI.downloadSimple, size: 18, color: fg.withValues(alpha: 0.8)),
          ]),
        ),
      ),
    );
  }
}

/// Link card under a message (title, site, image). Previews are cached per URL for the session.
class ChatLinkPreview extends StatefulWidget {
  const ChatLinkPreview({super.key, required this.url, required this.mine});
  final String url;
  final bool mine;

  static final Map<String, Future<Map<String, dynamic>>> _cache = {};

  @override
  State<ChatLinkPreview> createState() => _ChatLinkPreviewState();
}

class _ChatLinkPreviewState extends State<ChatLinkPreview> {
  late final Future<Map<String, dynamic>> _f = ChatLinkPreview._cache.putIfAbsent(
    widget.url,
    () => context.read<AppConfig>().apiClient.unfurlChatLink(widget.url).catchError((Object _) => <String, dynamic>{}),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        final title = d?['title']?.toString() ?? '';
        if (d == null || title.isEmpty) return const SizedBox.shrink();
        final site = d['siteName']?.toString() ?? d['site_name']?.toString() ?? Uri.tryParse(widget.url)?.host ?? '';
        final desc = d['description']?.toString() ?? '';
        final img = d['image']?.toString() ?? '';
        final fg = widget.mine ? cs.onPrimary : cs.onSurface;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: widget.mine ? cs.onPrimary : cs.primary, width: 3)),
                color: fg.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
              ),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (site.isNotEmpty) Text(site, maxLines: 1, style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7))),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: fg, fontSize: 13)),
                if (desc.isNotEmpty) Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8))),
                if (img.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: CachedNetworkImage(imageUrl: img, height: 110, width: double.infinity, fit: BoxFit.cover, errorWidget: (_, _, _) => const SizedBox.shrink())),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Keeps a ticking clock for "recording 0:12".
class ChatTicker {
  ChatTicker(this.onTick);
  final void Function(Duration) onTick;
  Timer? _t;
  final _sw = Stopwatch();
  void start() {
    _sw
      ..reset()
      ..start();
    _t = Timer.periodic(const Duration(milliseconds: 200), (_) => onTick(_sw.elapsed));
  }

  Duration stop() {
    _t?.cancel();
    _sw.stop();
    return _sw.elapsed;
  }
}
