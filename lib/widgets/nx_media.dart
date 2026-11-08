import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../core/i18n.dart';
import 'nx_icons.dart';

/// Video by extension (`.mp4`, `.mov`, …; query string ignored).
bool nxIsVideoUrl(String url) {
  final path = url.split('?').first.split('#').first.toLowerCase();
  return RegExp(r'\.(mp4|mov|m4v|webm|3gp|mkv)$').hasMatch(path);
}

String _fileName(String url, {required bool video}) {
  final last = Uri.decodeComponent(url.split('?').first.split('/').last);
  if (last.contains('.')) return last;
  return video ? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4' : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
}

/// Downloads [url] and saves it to the phone's photo gallery (falls back to the
/// share sheet — "Save to Files" etc. — when the gallery is not available).
Future<void> nxSaveMedia(BuildContext context, String url, {required bool video}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String m) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tr(m))));
  say('กำลังดาวน์โหลด…');
  try {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${_fileName(url, video: video)}';
    await Dio().download(url, path);
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      video ? await Gal.putVideo(path) : await Gal.putImage(path);
      say(video ? 'บันทึกวิดีโอลงคลังภาพแล้ว' : 'บันทึกรูปลงคลังภาพแล้ว');
    } catch (_) {
      messenger?.hideCurrentSnackBar();
      await Share.shareXFiles([XFile(path)]);
    }
  } catch (_) {
    say('ดาวน์โหลดไม่สำเร็จ');
  }
}

/// Full-screen video player: play / pause, seek, time, download and share.
Future<void> openNxVideoPlayer(BuildContext context, String url, {String? name}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (context, _, _) => NxVideoPlayerScreen(url: url, name: name),
    transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

class NxVideoPlayerScreen extends StatefulWidget {
  const NxVideoPlayerScreen({super.key, required this.url, this.name});
  final String url;
  final String? name;

  @override
  State<NxVideoPlayerScreen> createState() => _NxVideoPlayerScreenState();
}

class _NxVideoPlayerScreenState extends State<NxVideoPlayerScreen> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  Object? _error;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
      _scheduleHide();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _toggle() {
    _c.value.isPlaying ? _c.pause() : _c.play();
    setState(() => _controls = true);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  static String _t(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final name = widget.name ?? _fileName(widget.url, video: true);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            key: const ValueKey('video-download'),
            tooltip: tr('ดาวน์โหลด'),
            icon: const Icon(NxI.downloadSimple),
            onPressed: () => nxSaveMedia(context, widget.url, video: true),
          ),
          IconButton(tooltip: tr('แชร์'), icon: const Icon(NxI.shareNetwork), onPressed: () => Share.share(widget.url)),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(NxI.videoCamera, color: Colors.white54, size: 48),
                  const SizedBox(height: 12),
                  Text(tr('เล่นวิดีโอนี้ไม่ได้'), style: const TextStyle(color: Colors.white70)),
                  TextButton(
                    onPressed: () => nxSaveMedia(context, widget.url, video: true),
                    child: Text(tr('ดาวน์โหลด')),
                  ),
                ]),
              )
            : !v.isInitialized
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _controls = !_controls);
                      if (_controls) _scheduleHide();
                    },
                    child: Stack(children: [
                      Center(child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c))),
                      AnimatedOpacity(
                        opacity: _controls || !v.isPlaying ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Stack(children: [
                          Center(
                            child: Material(
                              color: Colors.black45,
                              shape: const CircleBorder(),
                              child: IconButton(
                                key: const ValueKey('video-play'),
                                iconSize: 44,
                                color: Colors.white,
                                icon: Icon(v.isPlaying ? NxI.pause : NxI.play),
                                onPressed: _toggle,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 12,
                            child: Row(children: [
                              Text(_t(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: VideoProgressIndicator(
                                  _c,
                                  allowScrubbing: true,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38, backgroundColor: Colors.white12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(_t(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ]),
                          ),
                        ]),
                      ),
                    ]),
                  ),
      ),
    );
  }
}

/// Inline video card (description / comment): dark tile with a play button;
/// tap = full-screen player.
class NxVideoTile extends StatelessWidget {
  const NxVideoTile({super.key, required this.url, this.name});
  final String url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final n = name ?? _fileName(url, video: true);
    return Material(
      color: const Color(0xFF111114),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('video-tile-$url'),
        onTap: () => openNxVideoPlayer(context, url, name: n),
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: Stack(children: [
            const Center(
              child: CircleAvatar(radius: 26, backgroundColor: Colors.white24, child: Icon(NxI.play, color: Colors.white, size: 26)),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Row(children: [
                const Icon(NxI.videoCamera, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
