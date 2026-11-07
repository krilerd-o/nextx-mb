import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/workspace_models.dart';

void main() {
  test('parseDuration understands web and Thai units', () {
    expect(parseDuration('1h 30m'), 90);
    expect(parseDuration('90m'), 90);
    expect(parseDuration('45'), 45);
    expect(parseDuration('1.5h'), 90);
    expect(parseDuration('1d'), 480);
    expect(parseDuration('1ชม 30นาที'), 90);
    expect(parseDuration('abc'), isNull);
    expect(parseDuration('1h foo'), isNull);
    expect(parseDuration(''), isNull);
  });

  test('formatMinutes', () {
    expect(formatMinutes(90), '1h 30m');
    expect(formatMinutes(120), '2h');
    expect(formatMinutes(15), '15m');
    expect(formatMinutes(null), '0m');
  });

  test('keys, titles, statuses', () {
    expect(wsKey({'item_no': 12}, boardCode: 'QAM'), 'QAM-12');
    expect(wsTitle({'title': '[QAM]: Fix login'}), 'Fix login');
    final st = WsStatus.list([
      {'id': 2, 'sequence': 2, 'label_th': 'กำลังทำ', 'color': '#EA580C'},
      {'id': 1, 'sequence': 1, 'label_th': 'รอทำ', 'is_initial': 1},
    ]);
    expect(st.first.id, '1');
    expect(st.first.isInitial, isTrue);
    expect(st.last.color.toARGB32(), 0xFFEA580C);
    expect(wsKind({'_kind': 'epic'}), 'epic');
    expect(wsKind({'type': 'bug'}), 'task');
  });
}
