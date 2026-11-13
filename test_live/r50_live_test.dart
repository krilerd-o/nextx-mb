// Manual tool (not part of `flutter test`): R50 Service Journey against a local
// NEXTX backend (nextx_qa, develop ≥ PR #10) with [QA] records this test creates.
// QA_TOKEN_FILE=… flutter test test_live/r50_live_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:dio/dio.dart' show MultipartFile, DioMediaType;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nextx_mobile/core/journey_rules.dart';
import 'package:nextx_mobile/core/doc_form/doc_form_rules.dart';
import 'package:nextx_mobile/core/thai_time.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/services/photo_pipeline.dart';

class _Mem extends XFile {
  _Mem(this._b, String p) : super(p);
  final Uint8List _b;
  @override
  Future<Uint8List> readAsBytes() async => _b;
  @override
  Future<DateTime> lastModified() async => DateTime.now();
}

void main() {
  testWidgets('quotation journey + job workflow + 12 photos', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
      final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final cleanup = <(String, String)>[];
      try {
        expect(await api.probeServiceJourney(), isTrue);

        // ---- Quotation: create → offer status → close won (job created) → duplicate.
        final saved = await api.saveQuotation(fields: {
          'title_th': '[QA] R50 ใบเสนอราคา $stamp',
          'valid_until': DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10),
        }, lines: [
          {'line_type': 'text', 'description': '[QA] งานติดตั้ง', 'qty': 2, 'price': 1500},
        ]);
        final qtId = '${saved['id']}';
        cleanup.add(('quotation', qtId));
        var qt = await api.getEntity('quotation', qtId);
        print('[qt] created ${qt['quotation_no']} status=${qt['quotation_status']} offer=${qt['offer_status']}');
        expect(canonicalQuotationStatus(qt['quotation_status']), QS.open);
        final next0 = quotationNextAction(qt, lineCount: 1);
        print('[qt] next=${next0.key}/${next0.action}');

        final offer = await api.setQuotationOfferStatus(qtId, Offer.comparing);
        expect(offer['offer_status'], Offer.comparing);
        // Closing through the generic PUT is refused (must use the outcome dialog).
        try {
          await api.putEntity('quotation', qtId, {'offer_status': Offer.closed});
          fail('expected QUOTATION_OUTCOME_REQUIRED');
        } on ApiEnvelopeException catch (e) {
          print('[qt] generic close refused: ${e.errorCode}');
          expect(e.errorCode, 'QUOTATION_OUTCOME_REQUIRED');
        }
        final out = await api.setQuotationOutcome(qtId, status: 'Won', reason: 'ราคาเหมาะสม', poReference: 'PO-QA-$stamp');
        print('[qt] outcome job_id=${out['job_id']} created=${out['job_created']}');
        qt = await api.getEntity('quotation', qtId);
        expect(isQuotationClosed(qt), isTrue);
        expect(quotationResult(qt), 'Won');
        final nextWon = quotationNextAction(qt, hasJob: out['job_id'] != null);
        print('[qt] next after won=${nextWon.key}');

        // ทำซ้ำ like the step form: the copy rules + POST /quotation/save.
        final copy = await api.saveQuotation(
          fields: {for (final e in quotationDuplicateValues(qt, userId: null, today: thaiNow()).entries) if (e.value is! List) e.key: e.value},
          lines: quotationLinesPayload(copyQuotationLines(await api.getQuotationLines(qtId))),
        );
        final String? dupId = copy['id']?.toString();
        expect(dupId, isNotNull);
        cleanup.add(('quotation', dupId!));
        final dup = await api.getEntity('quotation', dupId);
        print('[qt] duplicate ${dup['quotation_no']} status=${dup['quotation_status']} outcome=${dup['outcome_result']}');
        expect(canonicalQuotationStatus(dup['quotation_status']), QS.open);
        expect(quotationResult(dup), isNull);
        expect((await api.getQuotationLines(dupId)).length, 1);

        // ---- Job: the one created from the quotation, or a new one.
        var jobId = out['job_id']?.toString();
        if (jobId == null || jobId.isEmpty) {
          final j = await api.postEntity('job', {'job_name': '[QA] R50 งาน $stamp'});
          jobId = '${j['id']}';
        }
        cleanup.add(('job', jobId));
        var job = await api.getEntity('job', jobId);
        var ov = await api.getJobOverview(jobId);
        print('[job] ${job['job_no']} status=${job['job_status']} next=${jobNextAction(job, ov).key} actions=${ov['workflow_actions']}');
        if (canonicalJobStatus(job['job_status']) != 'In Progress') {
          final r = await api.jobWorkflowAction(jobId, 'accept', expectedStatus: job['job_status']?.toString(), skipEmail: true);
          print('[job] accept → ${r['job_status']}');
          expect(r['job_status'], 'In Progress');
        }
        // Stale expected status → 409.
        try {
          await api.jobWorkflowAction(jobId, 'wait', expectedStatus: 'Open');
          fail('expected VERSION_CONFLICT');
        } on ApiEnvelopeException catch (e) {
          print('[job] stale expected_status: ${e.statusCode} ${e.errorCode}');
          expect(e.errorCode, 'VERSION_CONFLICT');
        }

        // 12 photos through the pipeline (uploads while "shooting").
        final shot = img.Image(width: 1600, height: 1200);
        img.fill(shot, color: img.ColorRgb8(30, 110, 170));
        final jpg = Uint8List.fromList(img.encodeJpg(shot, quality: 80));
        debugNativeJpeg = (src, maxSide, q) async => src; // no native plugin in the test VM
        final sw = Stopwatch()..start();
        final batch = PhotoBatch(PhotoTarget('job', jobId), withLocation: false, uploader: defaultPhotoUploader(api))..shooting = true;
        for (var i = 0; i < 12; i++) {
          batch.add(_Mem(jpg, 'qa_r50_$i.jpg'));
        }
        batch.close();
        while (!batch.value.done) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        print('[photos] uploaded=${batch.value.uploaded} failed=${batch.value.failed} in ${sw.elapsedMilliseconds} ms');
        expect(batch.value.uploaded, 12);
        // Same client id again → server reports a duplicate, no new photo.
        MultipartFile part() => MultipartFile.fromBytes(jpg, filename: 'again.jpg', contentType: DioMediaType('image', 'jpeg'));
        await api.uploadJobPhoto(jobId, part(), clientId: 'qa-r50-$stamp');
        final again = await api.uploadJobPhoto(jobId, part(), clientId: 'qa-r50-$stamp');
        print('[photos] resend same client id → duplicate=${again['duplicate']} count=${again['count']}');
        expect(again['duplicate'], isTrue);
        job = await api.getEntity('job', jobId);
        expect((job['evidence_photos'] as List).length, 13);

        // Signatures + close + reopen.
        final sigs = await api.getJobSignatures(jobId);
        final slots = [for (final s in (sigs['slots'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
        print('[job] signature slots=${slots.map((s) => s['slot_key']).toList()}');
        const dot = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
        for (final s in slots) {
          await api.putJobSignature(jobId, '${s['slot_key']}', signerName: '[QA] ผู้เซ็น', signature: dot);
        }
        ov = await api.getJobOverview(jobId);
        print('[job] overview before close: ${ov['signatures']} activities=${ov['activities']} can_close=${ov['can_close']}');
        final closed = await api.closeJob(jobId, scope: 'job_and_activities', note: '[QA] ปิดงานจากแอป', expectedStatus: 'In Progress', skipEmail: true);
        print('[job] close → ${closed['job_status']}');
        expect(closed['job_status'], 'Completed');
        final re = await api.reopenJob(jobId, note: '[QA] เปิดกลับ');
        print('[job] reopen → ${re['job_status']}');
        expect(re['job_status'], 'In Progress');

        final inbox = await api.getApprovalInbox();
        print('[inbox] count=${inbox['count']}');
        final links = await api.getJourneyLinks('quotation', qtId);
        print('[links] jobs=${(links['jobs'] as List?)?.length}');
      } finally {
        for (final (m, id) in cleanup.reversed) {
          try {
            await api.deleteEntity(m, id);
          } catch (e) {
            print('[cleanup] $m/$id: $e');
          }
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
