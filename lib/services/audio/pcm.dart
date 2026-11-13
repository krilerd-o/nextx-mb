import 'dart:math' as math;
import 'dart:typed_data';

/// PCM16 mono 24 kHz: the format every recorder here produces (live captions, call tapes,
/// notebook recordings) and the server's realtime transcriber expects.
const kPcmSampleRate = 24000;

/// Bytes per second of PCM16 mono 24 kHz.
const kPcmBytesPerSecond = kPcmSampleRate * 2;

/// Re-slices a byte stream into fixed-size packets (the server expects even-length PCM16 frames).
Stream<Uint8List> rechunk(Stream<Uint8List> input, int size) async* {
  final buf = BytesBuilder(copy: false);
  await for (final part in input) {
    buf.add(part);
    while (buf.length >= size) {
      final all = buf.takeBytes();
      yield Uint8List.sublistView(all, 0, size);
      if (all.length > size) buf.add(Uint8List.sublistView(all, size));
    }
  }
  final rest = buf.takeBytes();
  if (rest.length >= 2) yield Uint8List.sublistView(rest, 0, rest.length - rest.length % 2);
}

/// 44-byte RIFF header of a PCM16 mono WAV holding [dataBytes] of samples.
Uint8List wavHeader(int dataBytes, {int sampleRate = kPcmSampleRate}) {
  final b = ByteData(44);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}

/// Loudness of a PCM16 packet for a level meter: 0 (silence) … 1 (loud), on a dB scale
/// from −50 dBFS so quiet speech still moves the waveform.
double pcmLevel(Uint8List pcm) {
  final n = pcm.length ~/ 2;
  if (n == 0) return 0;
  final d = ByteData.sublistView(pcm);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final s = d.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  final rms = math.sqrt(sum / n);
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 50) / 50).clamp(0.0, 1.0);
}
