import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nextx_mobile/screens/calendar/fast_take_screen.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/photo_pipeline.dart';
import 'package:nextx_mobile/services/shutter_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemFile extends XFile {
  _MemFile(this._bytes, String path) : super(path);
  final Uint8List _bytes;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Future<DateTime> lastModified() async => DateTime.now();
}

Uint8List _jpeg(int w, int h) {
  final i = img.Image(width: w, height: h);
  img.fill(i, color: img.ColorRgb8(40, 120, 200));
  return Uint8List.fromList(img.encodeJpg(i, quality: 70));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ShutterSound.debugOnPlay = null;
    debugFastTakeCapture = null;
    debugNativeJpeg = null;
  });

  test('jpegSize reads the SOF header without decoding', () {
    expect(jpegSize(_jpeg(640, 480)), (640, 480));
    expect(jpegSize(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('client ids are unique UUID-like strings', () {
    final ids = {for (var i = 0; i < 200; i++) newClientId()};
    expect(ids, hasLength(200));
    expect(ids.first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  testWidgets('Fast Take: rapid taps are all kept (queued), each plays the shutter, shots stream out at once', (tester) async {
    final played = <ShutterStyle>[];
    ShutterSound.debugOnPlay = played.add;
    var n = 0;
    final pending = <Completer<XFile>>[];
    // Slow camera: every capture waits until the test releases it.
    debugFastTakeCapture = () {
      final c = Completer<XFile>();
      pending.add(c);
      return c.future;
    };
    final streamed = <XFile>[];
    List<XFile>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<List<XFile>>(
              MaterialPageRoute(builder: (_) => FastTakeScreen(onShot: streamed.add)),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 5 quick taps while the first capture is still running.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('fast-take-shutter')));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(played, hasLength(5), reason: 'sound on every tap, immediately');
    expect(find.text('5/$kFastTakeMax'), findsOneWidget, reason: 'queued taps count at once');
    // Release captures one by one (the screen captures sequentially).
    while (n < 5) {
      await tester.pump(const Duration(milliseconds: 10));
      if (pending.length > n) {
        pending[n].complete(_MemFile(Uint8List(0), 'shot$n.jpg'));
        n++;
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(streamed.map((f) => f.path), ['shot0.jpg', 'shot1.jpg', 'shot2.jpg', 'shot3.jpg', 'shot4.jpg']);
    await tester.tap(find.byKey(const ValueKey('fast-take-done')));
    await tester.pumpAndSettle();
    expect(result, hasLength(5));
  });

  testWidgets('shutter off: no sound', (tester) async {
    final played = <ShutterStyle>[];
    ShutterSound.debugOnPlay = played.add;
    await ShutterSound.instance.setStyle(ShutterStyle.off);
    ShutterSound.instance.play();
    expect(played, isEmpty);
    await ShutterSound.instance.setStyle(ShutterStyle.slr);
    ShutterSound.instance.play();
    expect(played, [ShutterStyle.slr]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nx_shutter_style_v1'), 'slr');
    await ShutterSound.instance.setStyle(ShutterStyle.rangefinder);
  });

  test('PhotoBatch: uploads start before the user finishes, failures retry with the same client id', () async {
    debugNativeJpeg = (src, maxSide, q) async => src;
    final sent = <String>[];
    final ids = <String>[];
    var fail = true;
    final batch = PhotoBatch(
      const PhotoTarget('job', '7'),
      withLocation: false,
      uploader: (t, p) async {
        ids.add(p.clientId);
        if (p.filename == 'b.jpg' && fail) throw ApiException(400, 'bad'); // not retryable
        sent.add(p.filename);
        return {'photo': {'id': 'ph_${p.clientId}'}};
      },
    )..shooting = true;
    batch.add(_MemFile(_jpeg(64, 48), 'a.jpg'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sent, ['a.jpg'], reason: 'sent while still shooting');
    batch.add(_MemFile(_jpeg(64, 48), 'b.jpg'));
    batch.add(_MemFile(_jpeg(64, 48), 'c.jpeg'));
    final finished = Completer<void>();
    batch.addListener(() {
      if (batch.value.done && !finished.isCompleted) finished.complete();
    });
    batch.close();
    await finished.future;
    expect(batch.value.uploaded, 2);
    expect(batch.value.failed, 1);
    expect(sent, containsAll(['a.jpg', 'c.jpg']));
    final failedId = batch.failed.single.clientId;
    fail = false;
    await batch.retryFailed();
    expect(batch.value.failed, 0);
    expect(batch.value.uploaded, 3);
    expect(ids.where((i) => i == failedId), hasLength(2), reason: 'retry reuses the client id (server de-duplicates)');
  });

  test('PhotoBatch: network errors retry automatically', () async {
    debugNativeJpeg = (src, maxSide, q) async => src;
    var calls = 0;
    final batch = PhotoBatch(
      const PhotoTarget('job', '7'),
      withLocation: false,
      uploader: (t, p) async {
        calls++;
        if (calls < 2) throw ApiException(0, 'offline');
        return null;
      },
    );
    final done = Completer<void>();
    batch.addListener(() {
      if (batch.value.done && !done.isCompleted) done.complete();
    });
    batch.add(_MemFile(_jpeg(32, 32), 'x.jpg'));
    batch.close();
    await done.future;
    expect(calls, 2);
    expect(batch.value.uploaded, 1);
  });
}
