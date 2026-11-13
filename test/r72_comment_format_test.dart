import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/navigation/notification_deep_link.dart';
import 'package:nextx_mobile/widgets/comments/nx_comment_format.dart';

void main() {
  group('R72 mention payload = web CommentComposer (commentTextToHtml)', () {
    test('picked mentions become spans with data-id; text escaped; line breaks → <br>', () {
      final html = commentToHtml('ช่วยดู @Somchai Jaidee หน่อย\nราคา <5,000> & VAT', mentions: {'Somchai Jaidee': '7'});
      expect(
        html,
        'ช่วยดู <span data-type="mention" data-id="7" class="moai-mention">@Somchai Jaidee</span> หน่อย<br>ราคา &lt;5,000&gt; &amp; VAT',
      );
      expect(commentMentionIds(html), ['7']);
    });

    test('web tokens @[id:Name] are accepted; a removed mention is plain text', () {
      expect(commentToHtml('hi @[12:Ann]'), 'hi <span data-type="mention" data-id="12" class="moai-mention">@Ann</span>');
      expect(commentToHtml('no one here', mentions: {'Ann': '12'}), 'no one here');
      // Longest name first: "Ann Lee" is not split into "Ann".
      final h = commentToHtml('@Ann Lee and @Ann', mentions: {'Ann': '1', 'Ann Lee': '2'});
      expect(commentMentionIds(h), ['2', '1']);
      expect(RegExp('data-type').allMatches(h).length, 2);
    });

    test('Thai names mention without a space after them', () {
      final h = commentToHtml('@สมชายช่วยดู', mentions: {'สมชาย': '3'});
      expect(h, startsWith('<span data-type="mention" data-id="3" class="moai-mention">@สมชาย</span>'));
    });

    test('HTML → editable text keeps mentions; round trip is stable', () {
      const stored = '<p>สวัสดี <span data-type="mention" data-id="9" class="moai-mention">@นที</span></p><p>บรรทัด 2 &amp; 3</p>';
      final p = commentFromHtml(stored);
      expect(p.text, 'สวัสดี @นที\nบรรทัด 2 & 3');
      expect(p.mentions, {'นที': '9'});
      final again = commentToHtml(p.text, mentions: p.mentions);
      expect(commentMentionIds(again), ['9']);
      expect(commentFromHtml(again).text, p.text);
    });

    test('display segments: text, mention chip, link (trailing punctuation peeled)', () {
      final segs = commentSegments('ดู <span data-type="mention" data-id="4" class="moai-mention">@Ann</span> ที่ https://example.com/a?b=1).');
      expect(segs.map((s) => s.toString()).toList(), ['text:ดู ', 'mention:Ann#4', 'text: ที่ ', 'url:https://example.com/a?b=1', 'text:).']);
      expect(commentUrls('a https://x.test/1, b https://x.test/1 c http://y.test'), ['https://x.test/1', 'http://y.test']);
      expect(commentNeedsRichView('<ul><li>a</li></ul>'), isTrue);
      expect(commentNeedsRichView('a<br>b <span data-type="mention" data-id="1">@x</span>'), isFalse);
    });

    test('@query at the caret', () {
      expect(mentionQueryAt('hello @som', 10), (start: 6, query: 'som'));
      expect(mentionQueryAt('@', 1), (start: 0, query: ''));
      expect(mentionQueryAt('mail a@b.com', 12), isNull);
      expect(mentionQueryAt('hello @som chai', 15), isNull);
    });

    test('people filter: name, username, e-mail; no duplicates', () {
      final users = [
        {'id': 1, 'first_name': 'Somchai', 'last_name': 'Jaidee', 'email1': 'somchai@demo.local'},
        {'id': 2, 'user_name': 'wipa', 'email1': 'wipa@demo.local'},
        {'id': 1, 'first_name': 'Somchai'},
      ];
      expect(filterMentionUsers(users, 'som').map((u) => u['id']), [1]);
      expect(filterMentionUsers(users, 'demo').map((u) => u['id']), [1, 2]);
      expect(filterMentionUsers(users, '', excludeId: '1').map((u) => u['id']), [2]);
      expect(mentionUserLabel(users[1]), 'wipa');
    });
  });

  group('R72 threads', () {
    Map<String, dynamic> c(int id, {int? parent, int min = 0}) =>
        {'id': id, 'parent_id': parent, 'created_at': '2026-11-13T03:${min.toString().padLeft(2, '0')}:00Z'};

    test('roots oldest first, replies nested oldest first, orphans become roots', () {
      final tree = buildCommentTree([c(3, min: 3), c(1, min: 1), c(4, parent: 1, min: 5), c(2, parent: 1, min: 4), c(5, parent: 2, min: 6), c(9, parent: 99, min: 9)]);
      expect(tree.map((n) => n.id), ['1', '3', '9']);
      expect(tree.first.replies.map((n) => n.id), ['2', '4']);
      expect(tree.first.replies.first.replies.single.id, '5');
      expect(tree.first.replyCount, 3);
      expect(tree.first.descendants.map((n) => n.depth), [1, 2, 1]);
    });

    test('depth is capped and cycles do not loop', () {
      final rows = [c(1), for (var i = 2; i <= 8; i++) c(i, parent: i - 1, min: i)];
      final tree = buildCommentTree(rows, maxDepth: 5);
      expect(tree.single.descendants.map((n) => n.depth).reduce((a, b) => a > b ? a : b), 4);
      final cyc = buildCommentTree([c(1, parent: 2), c(2, parent: 1, min: 1)]);
      expect(cyc.length, 2);
    });
  });

  group('R72 mention notification deep link', () {
    test('web comment link → record comments tab with the comment', () {
      expect(notificationDeepLink('/modules/lead?open=5&section=comments&comment=77', linkId: '5', extra: 'comment_mention'), '/crm/lead/5?tab=comments&comment=77');
      expect(notificationDeepLink('/modules/job?open=8&section=comments&comment=3', extra: 'comment_mention'), '/fsm/job/8?tab=comments&comment=3');
      expect(notificationDeepLink('/calendar?open=9&section=comments&comment=4', extra: 'comment_mention'), '/calendar/9?tab=comments&comment=4');
      expect(notificationDeepLink('/modules/activity?open=9&section=comments&comment=4'), '/calendar/9?tab=comments&comment=4');
      // Without a comment the old links are unchanged.
      expect(notificationDeepLink('/modules/case?open=12'), '/crm/case/12');
      // FCM data payload (url + extra).
      expect(notificationDeepLinkFromData({'url': '/modules/deal?open=2&section=comments&comment=6', 'extra': 'comment_mention', 'link_id': '2'}), '/crm/deal/2?tab=comments&comment=6');
      expect(notificationTab('comment_mention'), 'comments');
    });
  });
}
