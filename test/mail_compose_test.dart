import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/screens/mail/mail_compose_screen.dart';
import 'package:nextx_mobile/screens/mail/mail_home_screen.dart';

void main() {
  final original = <String, dynamic>{
    'id': 10,
    'from_user_id': 7,
    'from_display': 'สมชาย ใจดี',
    'subject': 'ประชุมพรุ่งนี้',
    'body_html': '<p>เจอกัน 9 โมง</p>',
    'sent_at': '2026-11-05 10:00',
  };

  test('reply addresses the sender and prefixes Re: once', () {
    final seed = MailComposeSeed.from(MailComposeMode.reply, original);
    expect(seed.to.single.userId, '7');
    expect(seed.to.single.display, 'สมชาย ใจดี');
    expect(seed.subject, 'Re: ประชุมพรุ่งนี้');
    expect(seed.quotedHtml, contains('<blockquote><p>เจอกัน 9 โมง</p></blockquote>'));

    final again = MailComposeSeed.from(MailComposeMode.reply, {...original, 'subject': 're: x'});
    expect(again.subject, 're: x');
  });

  test('forward has no recipients and carries the original', () {
    final seed = MailComposeSeed.from(MailComposeMode.forward, original);
    expect(seed.to, isEmpty);
    expect(seed.subject, 'Fwd: ประชุมพรุ่งนี้');
    expect(seed.quotedHtml, contains('เจอกัน 9 โมง'));
    expect(seed.quotedHtml, contains('สมชาย ใจดี'));
  });

  test('draft restores recipients, body and id', () {
    final seed = MailComposeSeed.from(MailComposeMode.draft, {
      'id': 55,
      'subject': 'ร่าง',
      'body': 'ข้อความ',
      'to': [
        {'user_id': 3, 'display': 'A'},
      ],
      'cc': [
        {'user_id': 4, 'display': 'B'},
      ],
    });
    expect(seed.draftId, '55');
    expect(seed.to.map((r) => r.userId), ['3']);
    expect(seed.cc.map((r) => r.userId), ['4']);
    expect(seed.body, 'ข้อความ');
    expect(seed.quotedHtml, isNull);
  });

  test('plain text is escaped into paragraphs', () {
    expect(plainTextToHtml('a<b>\nc\n\nd'), '<p>a&lt;b&gt;<br>c</p><p>d</p>');
    expect(plainTextToHtml('   '), '');
  });

  test('recipient from /api/mail/users row', () {
    final r = MailRecipient.fromUser({'id': 9, 'first_name': 'Ann', 'last_name': 'Lee', 'email1': 'a@x.co'});
    expect(r.userId, '9');
    expect(r.display, 'Ann Lee');
    expect(r.email, 'a@x.co');
  });

  test('unread only applies to inbox rows with null read_at', () {
    expect(isMailUnread({'read_at': null}, 'inbox'), isTrue);
    expect(isMailUnread({'read_at': '2026-11-05'}, 'inbox'), isFalse);
    expect(isMailUnread({'read_at': null}, 'sent'), isFalse);
    expect(isMailUnread({'subject': 'x'}, 'inbox'), isFalse);
  });

  test('counterparty shows sender for inbox and recipients for sent', () {
    expect(mailCounterparty({'from_first_name': 'Ann', 'from_last_name': 'Lee'}, 'inbox'), 'Ann Lee');
    expect(mailCounterparty({'to_display': 'Bob'}, 'sent'), 'ถึง Bob');
  });
}
