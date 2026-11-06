import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/ai/ai_chat_screen.dart';
import 'package:nextx_mobile/screens/calendar/calendar_home_screen.dart';
import 'package:nextx_mobile/screens/commerce/commerce_home_screen.dart';
import 'package:nextx_mobile/screens/dashboard/mobile_dashboard_screen.dart';
import 'package:nextx_mobile/screens/files/files_home_screen.dart';
import 'package:nextx_mobile/screens/profile_edit_screen.dart';
import 'package:nextx_mobile/widgets/nx_icons.dart';

void main() {
  test('AI history keeps successful turns, newest last, capped', () {
    final turns = [
      for (var i = 0; i < 30; i++) AiTurn(i.isEven ? 'user' : 'assistant', 'm$i'),
      const AiTurn('assistant', 'boom', error: true),
    ];
    final msgs = aiRequestMessages(turns, max: 20);
    expect(msgs.length, 20);
    expect(msgs.last['content'], 'm29');
    expect(msgs.any((m) => m['content'] == 'boom'), isFalse);
  });

  test('AI reply extraction', () {
    expect(extractAiReply({'content': 'hi'}), 'hi');
    expect(
      extractAiReply({
        'choices': [
          {'message': {'content': 'yo'}},
        ],
      }),
      'yo',
    );
    expect(extractAiReply({'message': {'content': 'nested'}}), 'nested');
  });

  test('profile sends only changed fields', () {
    final changes = profileChanges(
      {'first_name': 'Ann', 'title': 'Sales'},
      {'first_name': 'Ann ', 'title': 'Manager', 'department': ''},
    );
    expect(changes, {'title': 'Manager'});
  });

  test('activities group by local day; date-only stays as is', () {
    final g = groupActivitiesByDay([
      {'id': 1, 'date_start': '2026-11-06'},
      {'id': 2, 'date_start': '2026-11-06'},
      {'id': 3, 'date_start': '2026-11-07'},
      {'id': 4},
    ]);
    expect(g['2026-11-06']?.length, 2);
    expect(g['2026-11-07']?.length, 1);
    expect(g.length, 2);
  });

  test('dashboard greeting and Thai date', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'สวัสดีตอนเช้า');
    expect(greetingFor(DateTime(2026, 1, 1, 14)), 'สวัสดีตอนบ่าย');
    expect(greetingFor(DateTime(2026, 1, 1, 20)), 'สวัสดีตอนเย็น');
    expect(thaiLongDate(DateTime(2026, 11, 6)), 'วันศุกร์ที่ 6 พ.ย. 2569');
  });

  test('file size and icon helpers', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(20 * 1024 * 1024), '20 MB');
    expect(formatBytes(null), '');
    expect(fileIconFor('image/png', 'a.png'), NxI.image);
    expect(fileIconFor(null, 'report.PDF'), NxI.filePdf);
  });

  test('baht and payment labels', () {
    expect(formatBaht(1234567.5), '฿1,234,567.50');
    expect(formatBaht('99'), '฿99.00');
    expect(formatBaht(null), '');
    expect(paymentStatusLabel('paid'), 'ชำระแล้ว');
    expect(paymentStatusLabel(null), 'ยังไม่ชำระ');
  });
}
