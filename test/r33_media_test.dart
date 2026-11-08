import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/nx_html_view.dart';
import 'package:nextx_mobile/widgets/nx_media.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  test('video urls', () {
    expect(nxIsVideoUrl('https://x.example.com/a/b/clip.MP4?token=1'), isTrue);
    expect(nxIsVideoUrl('https://x.example.com/a.mov'), isTrue);
    expect(nxIsVideoUrl('https://x.example.com/a.png'), isFalse);
  });

  testWidgets('image in a description: tap → full-screen viewer with download', (tester) async {
    await tester.pumpWidget(_wrap(const NxHtmlView(
      baseUrl: 'https://qa.example.com',
      html: '<ul><li>นำปุ่มออก</li></ul><p><img src="/uploads/a.png"></p><p><img src="/uploads/b.png"></p>',
    )));
    final img = find.byKey(const ValueKey('html-img-https://qa.example.com/uploads/b.png'));
    expect(img, findsOneWidget);
    expect(find.byKey(const ValueKey('html-img-https://qa.example.com/uploads/a.png')), findsOneWidget);
    await tester.tap(img);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('image-download')), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget, reason: 'opens on the tapped image, swipe through both');
  });

  testWidgets('video in a description / comment shows a play tile', (tester) async {
    await tester.pumpWidget(_wrap(const NxHtmlView(
      baseUrl: 'https://qa.example.com',
      html: '<p>ดูวิดีโอ</p><video controls><source src="/uploads/demo.mp4" type="video/mp4"></video>',
    )));
    expect(find.byType(NxVideoTile), findsOneWidget);
    expect(find.text('demo.mp4'), findsOneWidget);
  });
}
