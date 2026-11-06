import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/screens/workspace/task_detail_screen.dart';
import 'package:nextx_mobile/widgets/nx_html_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('task detail renders HTML instead of raw tags', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: MaterialApp(
          home: TaskDetailScreen(
            task: {
              'id': 63222,
              'title': 'คู่มือ',
              'status': 'TO DO',
              'description':
                  '<div data-moai-file="" data-file-name="manual.docx" class="moai-file-attachment"><a href="/uploads/manual.docx">manual.docx</a></div><p>ทำต่อจากเดิม</p>',
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(NxHtmlView), findsWidgets);
    expect(find.textContaining('data-moai-file'), findsNothing);
    expect(find.textContaining('<div'), findsNothing);
    expect(find.textContaining('manual.docx'), findsWidgets);
    expect(find.textContaining('ทำต่อจากเดิม'), findsOneWidget);
  });
}
