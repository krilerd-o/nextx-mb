import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/journey_rules.dart';

/// Mirrors NEXTX frontend/src/components/crm/recordJourney/journeyStages.test.js
void main() {
  QuotationStage qs(String st, [Map<String, dynamic> extra = const {}]) =>
      quotationStage({'quotation_status': st, ...extra});

  group('quotation stage', () {
    test('document status → stage', () {
      expect(qs('เปิดใบเสนอราคา').stage, 'open');
      expect(qs('Draft').stage, 'open');
      expect(qs('ขออนุมัติใบเสนอราคา').stage, 'approval');
      expect(qs('เปิดใบเสนอราคา', {'approval_state': 'pending'}).stage, 'approval');
      final rej = qs('ไม่อนุมัติใบเสนอราคา');
      expect([rej.stage, rej.side], ['approval', 'rejected']);
      expect(qs('อนุมัติใบเสนอราคา').stage, 'approved');
      expect(qs('อนุมัติใบเสนอราคา', {'offer_status': 'รอใบสั่งซื้อ'}).stage, 'approved');
      expect(qs('เปิดใบเสนอราคา', {'offer_status': 'รอเปรียบเทียบ'}).stage, 'open');
      final won = qs('ปิดการขาย', {'outcome_result': 'Won'});
      expect([won.stage, won.side, won.result, won.skippedApproval], ['closed', null, 'Won', true]);
      final lost = qs('ปิดการขาย', {'outcome_result': 'Lost'});
      expect([lost.side, lost.result], ['lost', 'Lost']);
      expect(qs('Won').result, 'Won');
      expect(qs('ยกเลิกใบเสนอราคา').side, 'cancelled');
      expect(qs('ยกเลิกใบเสนอราคา', {'approval_state': 'approved'}).stage, 'approved');
      expect(qs('Expired').side, 'cancelled');
      expect(qs('เปลี่ยนแปลงใบเสนอราคา').side, 'revised');
    });

    test('editable / outcome / canonical', () {
      expect(isQuotationEditable({'quotation_status': 'เปิดใบเสนอราคา'}), isTrue);
      expect(isQuotationEditable({'quotation_status': 'ไม่อนุมัติใบเสนอราคา'}), isTrue);
      expect(isQuotationEditable({'quotation_status': 'อนุมัติใบเสนอราคา'}), isFalse);
      expect(isOutcomeStatus('ปิดการขาย'), isTrue);
      expect(isOutcomeStatus('รอเปรียบเทียบ'), isFalse);
      expect(canonicalOfferStatus('negotiating'), 'รอเปรียบเทียบ');
      expect(canonicalQuotationStatus('Sent'), 'เปิดใบเสนอราคา');
      expect(quotationResult({'quotation_status': 'ปิดการขาย'}), isNull);
      expect(isQuotationWon({'quotation_status': 'ปิดการขาย', 'outcome_result': 'Won'}), isTrue);
    });

    test('approvers (multi-level + legacy)', () {
      final chain = [
        {'level': 1, 'mode': 'any', 'users': [3, 4], 'decisions': []},
        {
          'level': 3,
          'mode': 'all',
          'users': [7, 8],
          'decisions': [
            {'user_id': 7, 'decision': 'approved'},
          ],
        },
      ];
      final pending = {
        'quotation_status': 'ขออนุมัติใบเสนอราคา',
        'approval_state': 'pending',
        'approval_level': 2,
        'approval_chain': jsonEncode(chain),
      };
      expect(quotationCurrentApprovers(pending), [8]);
      expect(quotationCurrentApprovers({...pending, 'approval_level': 1}), [3, 4]);
      expect(quotationCurrentApprovers({'approval_state': 'pending', 'approval_level': 2, 'approval_chain': '[3, 7]'}), [7]);
      expect(quotationCurrentApprovers({'approval_state': 'none', 'approval_chain': [3]}), isEmpty);
      expect(quotationNextAction(pending, meId: 8).action, 'approve');
      expect(quotationNextAction(pending, meId: 7).key, 'waiting_approval');
    });
  });

  group('quotation next action', () {
    NextAction na(String st, [Map<String, dynamic> extra = const {}, Map<Symbol, dynamic> opt = const {}]) =>
        Function.apply(quotationNextAction, [
          {'quotation_status': st, ...extra},
        ], opt) as NextAction;

    test('open / approved / closed', () {
      expect(na('เปิดใบเสนอราคา', {}, {#lineCount: 0}).action, 'edit');
      expect(na('เปิดใบเสนอราคา', {}, {#lineCount: 2, #approvalRequired: true}).key, 'submit_approval');
      expect(na('เปิดใบเสนอราคา', {}, {#lineCount: 2}).secondary, ['send_email', 'close_sale']);
      expect(na('อนุมัติใบเสนอราคา', {'offer_status': 'เสนอราคา'}).action, 'send_email');
      expect(na('อนุมัติใบเสนอราคา', {'offer_status': 'รอเปรียบเทียบ'}).action, 'offer_waiting_po');
      expect(na('อนุมัติใบเสนอราคา', {'offer_status': 'รอใบสั่งซื้อ'}).action, 'close_sale');
      final won = na('ปิดการขาย', {'outcome_result': 'Won'});
      expect([won.key, won.action, won.secondary], ['won', null, ['create_job', 'duplicate']]);
      expect(na('ปิดการขาย', {'outcome_result': 'Won'}, {#jobEnabled: false}).secondary, ['duplicate']);
      expect(na('ปิดการขาย', {'outcome_result': 'Won'}, {#hasJob: true}).secondary, ['open_job', 'duplicate']);
      expect(na('ปิดการขาย', {'outcome_result': 'Lost'}).action, 'duplicate');
      expect(na('ไม่อนุมัติใบเสนอราคา').action, 'edit_quotation');
      expect(na('เปลี่ยนแปลงใบเสนอราคา').action, 'open_latest');
      expect(na('ยกเลิกใบเสนอราคา').action, 'duplicate');
      expect(na('ยกเลิกใบเสนอราคา').secondary, ['reopen_quotation']);
      expect(na('อนุมัติใบเสนอราคา', {'offer_status': 'เสนอราคา'}).secondary, contains('revise'));
      expect(na('อนุมัติใบเสนอราคา', {}, {#canEdit: false}).action, isNull);
    });

    test('expired / stale / skipped approval', () {
      final now = DateTime(2026, 1, 20);
      expect(na('เปิดใบเสนอราคา', {'valid_until': '2026-01-10'}, {#now: now}).key, 'expired');
      expect(na('เปิดใบเสนอราคา', {'valid_until': '2026-01-10'}, {#now: now}).action, 'edit_quotation');
      expect(na('อนุมัติใบเสนอราคา', {'approval_state': 'approved', 'valid_until': '2026-01-10'}, {#now: now}).action, 'revise');
      expect(na('อนุมัติใบเสนอราคา', {'approval_state': 'approved', 'valid_until': '2026-01-30'}, {#now: now}).key, 'send_customer');
      final sent = {'approval_state': 'approved', 'offer_status': 'เสนอราคา', 'public_token': 'x'};
      expect(na('อนุมัติใบเสนอราคา', sent, {#now: now, #customer: {'offer_status_at': '2026-01-05'}}).key, 'stale_follow_up');
      expect(na('อนุมัติใบเสนอราคา', sent, {#now: now, #customer: {'offer_status_at': '2026-01-18'}}).key, 'send_customer');
      expect(na('อนุมัติใบเสนอราคา', sent, {#now: now, #staleDays: 0, #customer: {'offer_status_at': '2026-01-05'}}).key, 'send_customer');
      expect(qs('เปิดใบเสนอราคา', {'public_token': 'x'}).skippedApproval, isTrue);
      expect(quotationStage({'quotation_status': 'เปิดใบเสนอราคา', 'public_token': 'x'}, approvalRequired: true).skippedApproval, isFalse);
      expect(qs('เปิดใบเสนอราคา').skippedApproval, isFalse);
      expect(qs('ปิดการขาย', {'outcome_result': 'Won', 'approval_state': 'approved'}).skippedApproval, isFalse);
      expect(na('เปิดใบเสนอราคา', {'public_token': 'x'}, {#lineCount: 2}).key, 'sent_no_approval');
    });

    test('days', () {
      expect(daysUntil('2026-01-10', now: DateTime(2026, 1, 7)), 3);
      expect(daysUntil('2026-01-05', now: DateTime(2026, 1, 7)), -2);
      expect(daysUntil(null), isNull);
    });
  });

  group('job', () {
    test('canonical + workflow', () {
      expect(canonicalJobStatus('Scheduled'), 'Open');
      expect(canonicalJobStatus('On Hold'), 'Waiting');
      expect(canonicalJobStatus('Done'), 'Completed');
      expect(kJobMain.indexOf(canonicalJobStatus('Done')), 3);
      expect(jobWorkflowActions('Open'), ['accept', 'forward', 'cancel']);
      expect(jobWorkflowActions('In Progress'), ['close', 'forward', 'wait', 'cancel']);
      expect(jobWorkflowActions('Completed'), ['reopen']);
      expect(jobWorkflowActions('Cancelled'), isEmpty);
      expect(jobStepAction('Open', 'Waiting'), 'forward');
      expect(jobStepAction('In Progress', 'Waiting'), 'wait');
      expect(jobStepAction('Waiting', 'In Progress'), 'accept');
      expect(jobStepAction('In Progress', 'Completed'), 'close');
      expect(jobStepAction('Open', 'Cancelled'), 'cancel');
    });

    test('next action', () {
      Map<String, dynamic> ov([Map<String, dynamic> o = const {}]) => {
            'has_owner': true,
            'scheduled': true,
            'can_accept': true,
            'activities': {'total': 2, 'open': 0},
            'signatures': {'total': 2, 'signed': 2},
            'can_close': true,
            ...o,
          };
      expect(jobNextAction({'job_status': 'Open'}, ov({'has_owner': false})).action, 'forward');
      expect(jobNextAction({'job_status': 'Open'}, ov()).action, 'accept');
      expect(jobNextAction({'job_status': 'Open'}, ov({'can_accept': false})).action, isNull);
      expect(jobNextAction({'job_status': 'Waiting'}, ov()).action, 'accept');
      expect(jobNextAction({'job_status': 'In Progress'}, ov({'activities': {'total': 0, 'open': 0}})).action, 'gen_activity');
      expect(jobNextAction({'job_status': 'In Progress'}, ov({'activities': {'total': 3, 'open': 1}})).action, 'open_activities');
      expect(jobNextAction({'job_status': 'In Progress'}, ov({'signatures': {'total': 3, 'signed': 1}})).action, 'open_signatures');
      expect(jobNextAction({'job_status': 'In Progress'}, ov()).action, 'close');
      expect(jobNextAction({'job_status': 'In Progress'}, ov({'can_close': false})).action, isNull);
      expect(jobNextAction({'job_status': 'Completed'}, ov({'can_reopen': true})).action, 'reopen');
      expect(jobNextAction({'job_status': 'Cancelled'}, ov()).key, 'cancelled');
      expect(jobNextAction({'job_status': 'Open'}, ov(), canEdit: false).key, 'read_only');
    });

    test('close checklist', () {
      final c = jobCloseChecklist({'smownerid': 5}, {
        'activities': {'total': 3, 'open': 1},
        'signatures': {'total': 2, 'signed': 2},
        'parts': 0,
      });
      expect(c.map((e) => e.key), ['owner', 'activities', 'signatures', 'parts']);
      expect(c[0].ok, isTrue);
      expect([c[1].ok, c[1].value], [false, '2/3']);
      expect(c[2].ok, isTrue);
      expect(c[3].info, isTrue);
    });
  });

  test('texts come from the web i18n', () {
    expect(nextTitle('job', const NextAction('accept', 'primary', 'accept')), 'รอรับงาน');
    expect(actionLabel('quotation', 'close_sale'), 'ปิดการขาย');
    expect(jt('journey.nope', fallback: 'x'), 'x');
  });
}
