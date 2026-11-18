import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/session_ended.dart';

void main() {
  test('reason from header + info', () {
    final info = Uri.encodeComponent('{"reason":"replaced","at":"2026-11-18T14:49:00Z","by_device":"Safari · macOS"}');
    final e = SessionEnded.fromHeaders('replaced', info)!;
    expect(e.reason, 'replaced');
    expect(e.byDevice, 'Safari · macOS');
    final t = sessionEndedText(e);
    expect(t.title, 'มีการเข้าสู่ระบบจากอุปกรณ์อื่น');
    expect(t.body, contains('Safari · macOS'));
  });

  test('older servers send 1 → admin; no header → null', () {
    expect(SessionEnded.fromHeaders('1', null)!.reason, 'admin');
    expect(SessionEnded.fromHeaders(null, null), isNull);
    expect(SessionEnded.fromHeaders('', null), isNull);
  });

  test('limit and idle wording', () {
    final l = SessionEnded.fromMap({'reason': 'limit', 'limit': 3, 'client': 'mobile'});
    expect(sessionEndedText(l).body, contains('แอปมือถือพร้อมกัน 3 คน'));
    final i = SessionEnded.fromMap({'reason': 'idle', 'idle_minutes': 360});
    expect(sessionEndedText(i).body, contains('6 ชั่วโมง'));
    expect(idleDurationTh(30), '30 นาที');
    expect(idleDurationTh(1440 * 90), '90 วัน');
  });

  test('force_logout reasons and unknown values', () {
    expect(SessionEnded.fromMap({'reason': 'suspended'}).reason, 'admin');
    expect(SessionEnded.fromMap({'reason': 'something'}).reason, 'admin');
  });

  test('policy blocks keep the server message', () {
    final p = SessionEnded.policyBlock('IP_NOT_ALLOWED', 'ธุรกิจนี้อนุญาตให้ใช้งานจากเครือข่ายที่กำหนดเท่านั้น');
    expect(p.isPolicyBlock, isTrue);
    final t = sessionEndedText(p);
    expect(t.title, 'เข้าใช้งานจากเครือข่ายนี้ไม่ได้');
    expect(t.body, startsWith('ธุรกิจนี้อนุญาต'));
    expect(kPolicyBlockCodes.contains('TWO_FA_REQUIRED'), isTrue);
  });
}
