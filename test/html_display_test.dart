import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/html_display.dart';
import 'package:nextx_mobile/widgets/nx_html_view.dart';

const _fileHtml = '''
<div data-moai-file="" data-src="/uploads/doc.docx" data-file-name="NSM_คู่มือการใช้งานระบบ_CRM_และ_Loyalty_ฉบับสมบูรณ์.docx" class="moai-file-attachment moai-file-card" href="/uploads/doc.docx">
<div class="moai-file-card-preview"><span>DOC</span></div>
<div class="moai-file-card-meta"><a href="/uploads/doc.docx" class="moai-file-card-link">NSM_คู่มือการใช้งานระบบ_CRM_และ_Loyalty_ฉบับสมบูรณ์.docx</a><span class="moai-file-card-date">21 ต.ค. 2569 11:30</span></div>
</div>
<p>ทำต่อจากเดิม เพิ่มหัวข้อเรื่อง</p>
''';

const _linkHtml = '''
<p><a href="https://moaistd.moai-crm.com/aisystem/index.php?action=DetailView&amp;module=Job&amp;record=75740">https://moaistd.moai-crm.com/aisystem/index.php?action=DetailView&amp;module=Job&amp;record=75740</a></p>
<p><strong>JOB69-0008</strong></p>
''';

void main() {
  test('stripHtmlPreview removes tags and entities', () {
    expect(stripHtmlPreview('<p>Hello&nbsp;world</p>'), 'Hello world');
    expect(stripHtmlPreview(_fileHtml), isNot(contains('data-moai-file')));
    expect(stripHtmlPreview(_fileHtml), contains('ทำต่อจากเดิม'));
    expect(stripHtmlPreview(_linkHtml), contains('JOB69-0008'));
    expect(stripHtmlPreview(_linkHtml), isNot(contains('&amp;')));
    expect(stripHtmlPreview(_linkHtml), isNot(contains('<a')));
  });

  test('prepareHtml extracts file cards', () {
    final p = prepareHtml(_fileHtml);
    expect(p.files, isNotEmpty);
    expect(p.files.first.name, contains('Loyalty'));
    expect(p.files.first.href, contains('/uploads/doc.docx'));
    expect(stripHtmlPreview(p.body), contains('ทำต่อจากเดิม'));
  });

  testWidgets('NxHtmlView hides raw markup', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NxHtmlView(html: '$_fileHtml$_linkHtml'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('data-moai-file'), findsNothing);
    expect(find.textContaining('<div'), findsNothing);
    expect(find.textContaining('&amp;'), findsNothing);
    expect(find.textContaining('Loyalty'), findsWidgets);
    expect(find.textContaining('JOB69-0008'), findsOneWidget);
    expect(find.textContaining('ทำต่อจากเดิม'), findsOneWidget);
  });
}
