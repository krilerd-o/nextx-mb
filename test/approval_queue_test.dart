import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/approval_queue.dart';

void main() {
  test('chain prefers approval_chain JSON over approver columns', () {
    expect(
      quotationApprovalChain({'approval_chain': '[5, "8"]', 'approver_1_user_id': 1}),
      ['5', '8'],
    );
    expect(quotationApprovalChain({'approval_chain': [3]}), ['3']);
    expect(
      quotationApprovalChain({'approval_chain': '[]', 'approver_1_user_id': 1, 'approver_2_user_id': '2'}),
      ['1', '2'],
    );
    expect(quotationApprovalChain({}), isEmpty);
  });

  test('only the approver of the current level sees the item', () {
    final row = {
      'approval_state': 'pending',
      'approval_level': 2,
      'approval_chain': [5, 8],
    };
    expect(isAwaitingMyApproval(row, '8'), isTrue);
    expect(isAwaitingMyApproval(row, '5'), isFalse);
    expect(isAwaitingMyApproval({...row, 'approval_level': 1}, '5'), isTrue);
  });

  test('not pending, no chain, or unknown user is never awaiting', () {
    expect(isAwaitingMyApproval({'approval_state': 'approved', 'approver_1_user_id': 5}, '5'), isFalse);
    expect(isAwaitingMyApproval({'approval_state': 'pending'}, '5'), isFalse);
    expect(isAwaitingMyApproval({'approval_state': 'pending', 'approver_1_user_id': 5}, null), isFalse);
    expect(isAwaitingMyApproval({'approval_state': 'pending', 'approval_level': 3, 'approval_chain': [5]}, '5'), isFalse);
  });

  test('missing level defaults to the first approver', () {
    expect(isAwaitingMyApproval({'approval_state': 'PENDING', 'approver_1_user_id': '5'}, '5'), isTrue);
  });
}
