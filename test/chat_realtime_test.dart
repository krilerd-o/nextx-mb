import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/chat_merge.dart';
import 'package:nextx_mobile/services/realtime_service.dart';

void main() {
  test('upsert inserts in id order and replaces existing', () {
    var list = <Map<String, dynamic>>[
      {'id': 1, 'body': 'a'},
      {'id': 3, 'body': 'c'},
    ];
    list = upsertChatMessage(list, {'id': 2, 'body': 'b'});
    expect(list.map((m) => m['id']), [1, 2, 3]);
    list = upsertChatMessage(list, {'id': 3, 'body': 'c2'});
    expect(list.length, 3);
    expect(list.last['body'], 'c2');
    expect(upsertChatMessage(list, {'body': 'no id'}), same(list));
  });

  test('remove drops by id', () {
    final list = removeChatMessage([
      {'id': 1},
      {'id': 2},
    ], '1');
    expect(list.map((m) => m['id']), [2]);
  });

  test('sender names are filled from earlier messages', () {
    final known = [
      {'id': 1, 'user_id': 5, 'first_name': 'Ann', 'last_name': 'Lee'},
    ];
    final filled = fillChatSender({'id': 2, 'user_id': 5}, known);
    expect(filled['first_name'], 'Ann');
    expect(fillChatSender({'id': 3, 'user_id': 9}, known)['first_name'], isNull);
  });

  test('own message detection', () {
    expect(isOwnChatMessage({'user_id': 5}, '5'), isTrue);
    expect(isOwnChatMessage({'user_id': 5}, '6'), isFalse);
    expect(isOwnChatMessage({'user_id': 5}, null), isFalse);
  });

  test('realtime events are streamed without dropping bursts', () async {
    final rt = RealtimeService.instance;
    final got = <String>[];
    final sub = rt.on('new_message').listen((e) => got.add(e.data['id'].toString()));
    rt.dispatchForTest('new_message', {'id': 1, 'room_id': 7});
    rt.dispatchForTest('new_message', {'id': 2, 'room_id': 7});
    rt.dispatchForTest('notification', {'id': 'n'});
    rt.dispatchForTest('new_message', 'not a map');
    await Future<void>.delayed(Duration.zero);
    expect(got, ['1', '2']);
    expect(rt.lastChatMessage?['id'], 2);
    expect(rt.lastNotification?['id'], 'n');
    await sub.cancel();
  });

  test('read receipts mark every message up to the id', () {
    final msgs = [
      {'id': 1, 'user_id': 5},
      {'id': 2, 'user_id': 5},
      {'id': 3, 'user_id': 9},
    ];
    var readers = applyReadReceipt({}, msgs, '9', '2');
    expect(readers['1'], ['9']);
    expect(readers['2'], ['9']);
    expect(readers['3'], isNull);
    readers = applyReadReceipt(readers, msgs, '9', '2');
    expect(readers['2'], ['9']);
    expect(readCountForLastOwn(msgs, readers, '5'), 1);
    expect(readCountForLastOwn(msgs, readers, '7'), 0);
  });

  test('reactions accept reaction_summary and reactions', () {
    expect(chatReactions({'reaction_summary': [{'emoji': '👍', 'count': 2}]}).single['count'], 2);
    expect(chatReactions({'reactions': [{'emoji': '🎉'}]}).single['emoji'], '🎉');
    expect(chatReactions({}), isEmpty);
  });
}
