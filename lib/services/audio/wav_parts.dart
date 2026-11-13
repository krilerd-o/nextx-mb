import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'pcm.dart';

/// One finished WAV part of a recording.
class WavPart {
  const WavPart({required this.path, required this.part, required this.isFinal, required this.parts, required this.durationMs});
  final String path;

  /// 0-based.
  final int part;
  final bool isFinal;

  /// Total number of parts (only on the final part, else 0).
  final int parts;

  /// Length of the whole recording so far (the total on the final part).
  final int durationMs;
}

/// Writes PCM16 mono 24 kHz into WAV parts of [partBytes] (~5 minutes) and hands each finished part
/// to [onPart] (in order), so a long recording is never one huge file and nothing is lost if the app
/// dies. Used by call tapes and notebook recordings.
class WavPartWriter {
  WavPartWriter(this.dir, {required String prefix, required this.onPart, this.partBytes = defaultPartBytes, this.minTotalBytes = kPcmBytesPerSecond})
      : prefix = prefix.replaceAll(RegExp(r'[^\w-]'), '');

  final Directory dir;
  final String prefix;
  final Future<void> Function(WavPart part) onPart;
  final int partBytes;

  /// A final recording shorter than this (in total) is thrown away (default 1 s); 0 keeps everything.
  final int minTotalBytes;

  static const defaultPartBytes = kPcmBytesPerSecond * 300; // 5 minutes

  IOSink? _sink;
  File? _file;
  int _bytes = 0; // in the current part
  int _total = 0;
  int _part = 0;
  bool _closed = false;

  /// Parts are closed and handed over one after another (a roll-over and the final part never race).
  Future<void> _chain = Future.value();

  int get durationMs => _total * 1000 ~/ kPcmBytesPerSecond;
  int get totalBytes => _total;

  /// Parts handed over (or being handed over) so far.
  int get partsStarted => _part;

  void add(Uint8List pcm) {
    if (_closed) return;
    if (_sink == null) {
      _file = File('${dir.path}/$prefix-${DateTime.now().millisecondsSinceEpoch}-$_part.wav');
      _sink = _file!.openWrite()..add(Uint8List(44));
      _bytes = 0;
    }
    _sink!.add(pcm);
    _bytes += pcm.length;
    _total += pcm.length;
    if (_bytes >= partBytes) _roll(isFinal: false);
  }

  Future<void> _roll({required bool isFinal}) {
    final sink = _sink;
    final file = _file;
    final bytes = _bytes;
    _sink = null;
    _file = null;
    final total = _total;
    final keep = file != null && (!isFinal || total >= minTotalBytes);
    final n = keep ? _part++ : -1;
    final parts = _part;
    final dur = durationMs;
    return _chain = _chain.then((_) async {
      if (sink != null && file != null) {
        await sink.flush();
        await sink.close();
        final raf = await file.open(mode: FileMode.writeOnlyAppend);
        await raf.setPosition(0);
        await raf.writeFrom(wavHeader(bytes));
        await raf.close();
      }
      if (file == null) return;
      if (!keep) {
        // Final recording too short: nothing worth keeping.
        file.delete().ignore();
        return;
      }
      await onPart(WavPart(path: file.path, part: n, isFinal: isFinal, parts: isFinal ? parts : 0, durationMs: dur));
    });
  }

  /// Throws the unsent recording away (parts already handed over stay where they are).
  Future<void> discard() async {
    _closed = true;
    final sink = _sink;
    final file = _file;
    _sink = null;
    _file = null;
    await _chain;
    await sink?.close();
    file?.delete().ignore();
  }

  /// Closes the last part (marked final, with the total part count).
  Future<void> close() async {
    if (_closed) return _chain;
    if (_sink == null && _part > 0) {
      // The last part was just rolled over: send a tiny closing part so the server knows the total.
      add(Uint8List(4800));
    }
    _closed = true;
    await _roll(isFinal: true);
  }
}
