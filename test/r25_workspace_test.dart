import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/workspace_models.dart';

void main() {
  test('deal boards show their short name as the key; links keep the real code', () {
    wsBoardNames['D26110500003'] = 'KFDN';
    final item = {'board_code': 'D26110500003', 'item_no': 5, 'title': '[KFDN]: Kickoff Project Onsite'};
    expect(wsKey(item), 'KFDN-5');
    expect(wsLinkKey(item), 'D26110500003-5');
    expect(wsKey({'board_code': 'BAFCSI', 'item_no': 3}), 'BAFCSI-3');
    // A long or non-code name keeps the real code.
    expect(wsDisplayCode('D26101900001', name: 'Annual Tasks for MA'), 'D26101900001');
  });

  test('share text: key, title, web link (like the web)', () {
    final t = wsShareText({'board_code': 'BAFCSI', 'item_no': 3, 'title': '[BAFCSI]: Test Phase - Sales Insight'}, 'https://moainext.moai-crm.com/workspace/BAFCSI-3');
    expect(t, 'BAFCSI-3\n[BAFCSI]: Test Phase - Sales Insight\nhttps://moainext.moai-crm.com/workspace/BAFCSI-3');
  });

  test('quick add defaults like the web: me, today, medium', () {
    final b = wsQuickAddBody(title: ' [QA] งานเร็ว ', statusId: '12', me: '2', now: DateTime(2026, 11, 8, 10));
    expect(b, {
      'title': '[QA] งานเร็ว',
      'type': 'task',
      'status_id': 12,
      'priority': 'medium',
      'start_date': '2026-11-08',
      'end_date': '2026-11-08',
      'due_date': '2026-11-08',
      'assignee_id': 2,
      'reporter_id': 2,
    });
  });
}
