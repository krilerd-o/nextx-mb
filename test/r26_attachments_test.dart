import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/widgets/nx_attachments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('image by mime or extension; names from any key; "—" body hidden', () {
    expect(nxIsImageAttachment({'name': 'image.png'}), isTrue);
    expect(nxIsImageAttachment({'url': '/uploads/a/b.JPG?x=1'}), isTrue);
    expect(nxIsImageAttachment({'mime': 'application/pdf', 'name': 'q.pdf'}), isFalse);
    expect(nxAttachmentName({'file_name': 'สัญญา.pdf'}), 'สัญญา.pdf');
    expect(nxAttachmentName({'url': '/uploads/x/report%20Q3.xlsx'}), 'report Q3.xlsx');
    expect(nxCommentHasText('<p>—</p>'), isFalse);
    expect(nxCommentHasText('<p><img src="/u/a.png"></p>'), isFalse);
    expect(nxCommentHasText('<p>[QA] ตกลง</p>'), isTrue);
    expect(nxInlineImages('<p><img src="/u/a.png"> <img src="data:x"></p>').single['url'], '/u/a.png');
    expect(nxFileStyle({'name': 'a.pdf'}).label, 'PDF');
  });

  testWidgets('images as thumbnails (tap = viewer), files as cards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: AppConfig(),
      child: const MaterialApp(
        home: Scaffold(
          body: NxAttachmentStrip(items: [
            {'url': '/uploads/qa/image.png', 'name': 'image.png'},
            {'url': '/uploads/qa/quote.pdf', 'name': '[QA] ใบเสนอราคา.pdf', 'size': 204800},
          ]),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('nx-att-img-0')), findsOneWidget);
    expect(find.text('[QA] ใบเสนอราคา.pdf'), findsOneWidget);
    expect(find.text('200 KB'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nx-att-img-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('image.png'), findsOneWidget, reason: 'viewer shows the file name');
  });
}
