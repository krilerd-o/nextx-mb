import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/photo_pipeline.dart';
import 'package:nextx_mobile/services/photo_upload_center.dart';
import 'package:nextx_mobile/widgets/nx_upload_pill.dart';

class _MemFile extends XFile {
  _MemFile(this._bytes, String path) : super(path);
  final Uint8List _bytes;
  @override
  Future<Uint8List> readAsBytes() async => _bytes;
  @override
  Future<DateTime> lastModified() async => DateTime.now();
}

Uint8List _jpeg() {
  final i = img.Image(width: 32, height: 24);
  img.fill(i, color: img.ColorRgb8(40, 120, 200));
  return Uint8List.fromList(img.encodeJpg(i, quality: 70));
}

Future<void> _finish(PhotoBatch b) async {
  final c = Completer<void>();
  void l() {
    if (b.value.done && !c.isCompleted) c.complete();
  }

  b.addListener(l);
  l();
  await c.future;
}

void main() {
  late Directory dir;
  final center = PhotoUploadCenter.instance;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('nx_photo_q');
    await center.debugReset();
    PhotoUploadCenter.debugDir = dir;
    center.scope = 'qa|u2|b1';
    debugNativeJpeg = (src, maxSide, q) async => src;
  });

  tearDown(() async {
    debugNativeJpeg = null;
    await center.debugReset();
    PhotoUploadCenter.debugDir = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('no signal: photo stays on disk, survives an app restart and is sent when back online', () async {
    final b = PhotoBatch(
      const PhotoTarget('job', '9', title: '[QA] งานทดสอบ'),
      withLocation: false,
      uploader: (t, p) async => throw ApiException(0, 'offline'),
    );
    b.add(_MemFile(_jpeg(), 'a.jpg'));
    b.close();
    await _finish(b);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(center.items, hasLength(1));
    final saved = center.items.single;
    expect(File(saved.path).existsSync(), isTrue);
    expect(saved.failed, isFalse);

    // "Restart": forget everything in memory, keep the folder.
    await center.debugReset();
    PhotoUploadCenter.debugDir = dir;
    center.scope = 'qa|u2|b1';
    await center.load();
    expect(center.items.single.clientId, saved.clientId);
    expect(center.value.waiting, 1);

    final sent = <String>[];
    final n = await center.drain(ApiClient(), uploader: (t, p) async {
      sent.add('${t.module}:${t.id}:${p.clientId}');
      return {'photo': {'id': 1}};
    });
    expect(n, 1);
    expect(sent, ['job:9:${saved.clientId}']); // same client id → no duplicate on the server
    expect(center.items, isEmpty);
    expect(File(saved.path).existsSync(), isFalse);
    expect(center.value.visible, isFalse);
  });

  test('photos of another Space wait for that Space', () async {
    final b = PhotoBatch(const PhotoTarget('job', '9'), withLocation: false, uploader: (t, p) async => throw ApiException(0, 'offline'));
    b.add(_MemFile(_jpeg(), 'a.jpg'));
    b.close();
    await _finish(b);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    center.scope = 'other|u9|b2';
    var calls = 0;
    expect(await center.drain(ApiClient(), uploader: (t, p) async => {calls++}.isEmpty ? null : null), 0);
    expect(calls, 0);
    expect(center.items, hasLength(1));
  });

  test('refused by the server: marked failed, kept for retry / discard', () async {
    final b = PhotoBatch(const PhotoTarget('job', '9'), withLocation: false, uploader: (t, p) async => throw ApiException(400, 'bad'));
    b.add(_MemFile(_jpeg(), 'a.jpg'));
    b.close();
    await _finish(b);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(center.items.single.failed, isTrue);
    expect(center.value.failed, 1);
    await center.discard(center.items.single.clientId);
    expect(center.items, isEmpty);
  });

  test('sent fine: nothing left on disk', () async {
    final b = PhotoBatch(const PhotoTarget('job', '9'), withLocation: false, uploader: (t, p) async => {'ok': 1});
    b.add(_MemFile(_jpeg(), 'a.jpg'));
    b.add(_MemFile(_jpeg(), 'b.jpg'));
    b.close();
    await _finish(b);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(center.items, isEmpty);
    expect(dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.jpg')), isEmpty);
  });

  testWidgets('floating pill: waiting / failed / sending', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [NxUploadPill(navigatorKey: GlobalKey<NavigatorState>())]))));
    expect(find.byKey(const ValueKey('upload-pill')), findsOneWidget); // laid out but hidden
    expect(tester.getRect(find.byKey(const ValueKey('upload-pill'))).top, greaterThan(600));
    await tester.runAsync(() async {
      final b = PhotoBatch(const PhotoTarget('job', '9'), withLocation: false, uploader: (t, p) async => throw ApiException(0, 'x'));
      b.add(_MemFile(_jpeg(), 'a.jpg'));
      b.close();
      await _finish(b);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    center.offline = true;
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('รอสัญญาณ · ค้างส่ง 1 รูป'), findsOneWidget);
  });
}
