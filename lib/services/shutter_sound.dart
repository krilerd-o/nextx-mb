import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shutter sound styles (original sounds made by `tool/gen_shutter.py`).
enum ShutterStyle { rangefinder, slr, minimal, off }

extension ShutterStyleText on ShutterStyle {
  String get labelTh => switch (this) {
        ShutterStyle.rangefinder => 'Rangefinder นุ่ม',
        ShutterStyle.slr => 'SLR กระจกพับ',
        ShutterStyle.minimal => 'Minimal ดิจิทัล',
        ShutterStyle.off => 'ปิดเสียง',
      };

  String get hintTh => switch (this) {
        ShutterStyle.rangefinder => 'คลิกกลไกเบา ๆ แบบกล้อง Rangefinder',
        ShutterStyle.slr => 'เสียงกระจกพับ 2 จังหวะแบบกล้อง DSLR',
        ShutterStyle.minimal => 'ติ๊กสั้น ๆ แบบดิจิทัล',
        ShutterStyle.off => 'ถ่ายเงียบ (ยังมีแฟลชจอและการสั่น)',
      };

  String? get asset => switch (this) {
        ShutterStyle.rangefinder => 'sounds/shutter_rangefinder.wav',
        ShutterStyle.slr => 'sounds/shutter_slr.wav',
        ShutterStyle.minimal => 'sounds/shutter_minimal.wav',
        ShutterStyle.off => null,
      };
}

/// Plays the shutter instantly (low-latency pool, preloaded). Respects the
/// iPhone silent switch and mixes with other audio (does not stop music/calls).
class ShutterSound {
  ShutterSound._();
  static final ShutterSound instance = ShutterSound._();

  static const _pref = 'nx_shutter_style_v1';

  ShutterStyle _style = ShutterStyle.rangefinder;
  bool _loaded = false;
  AudioPool? _pool;
  ShutterStyle? _poolStyle;

  /// Test hook: counts plays instead of using the platform player.
  @visibleForTesting
  static void Function(ShutterStyle style)? debugOnPlay;

  ShutterStyle get style => _style;

  Future<ShutterStyle> load() async {
    if (_loaded) return _style;
    try {
      final v = (await SharedPreferences.getInstance()).getString(_pref);
      _style = ShutterStyle.values.where((s) => s.name == v).firstOrNull ?? ShutterStyle.rangefinder;
    } catch (_) {}
    _loaded = true;
    return _style;
  }

  Future<void> setStyle(ShutterStyle s) async {
    _style = s;
    _loaded = true;
    try {
      (await SharedPreferences.getInstance()).setString(_pref, s.name);
    } catch (_) {}
    await preload();
  }

  /// Call when a camera opens so the first shot has no delay.
  Future<void> preload() async {
    await load();
    if (debugOnPlay != null) return;
    final asset = _style.asset;
    if (asset == null || (_pool != null && _poolStyle == _style)) return;
    try {
      final old = _pool;
      _pool = await AudioPool.create(
        source: AssetSource(asset),
        maxPlayers: 4,
        minPlayers: 2,
        playerMode: PlayerMode.lowLatency,
        audioContext: AudioContextConfig(
          respectSilence: true,
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      _poolStyle = _style;
      await old?.dispose();
    } catch (e) {
      debugPrint('[shutter] preload failed: $e');
      _pool = null;
    }
  }

  Future<void> _startAfterPreload() async {
    try {
      await preload();
      final stop = await _pool?.start();
      if (stop != null) Future<void>.delayed(const Duration(milliseconds: 400), stop);
    } catch (_) {}
  }

  /// Fire-and-forget: never blocks or throws into the capture path.
  void play([ShutterStyle? preview]) {
    final s = preview ?? _style;
    if (s == ShutterStyle.off) return;
    final hook = debugOnPlay;
    if (hook != null) {
      hook(s);
      return;
    }
    if (preview != null && preview != _poolStyle) {
      final asset = preview.asset;
      if (asset == null) return;
      final p = AudioPlayer(playerId: 'shutter-preview');
      p.setPlayerMode(PlayerMode.lowLatency).then((_) => p.play(AssetSource(asset))).catchError((Object _) {});
      Future<void>.delayed(const Duration(seconds: 2), p.dispose);
      return;
    }
    final pool = _pool;
    if (pool == null) {
      unawaited(_startAfterPreload());
      return;
    }
    pool.start().then((stop) => Future<void>.delayed(const Duration(milliseconds: 400), stop)).catchError((Object _) {});
  }
}
