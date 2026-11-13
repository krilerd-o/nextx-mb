part of 'api_client.dart';

/// NEXTX Service Journey (Quotation / Job) API — available on servers with
/// `develop` ≥ PR #10. Detect with [ApiClient.probeServiceJourney].
extension JourneyApi on ApiClient {
  /// true when the server has the Service Journey endpoints (job settings route).
  Future<bool> probeServiceJourney() async {
    try {
      await _send('GET', '/api/settings/job');
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 0) rethrow; // offline — decide later
      if (e.statusCode == 404) return false;
      return e.statusCode == 403; // route exists, only the role blocks it
    } on ApiEnvelopeException catch (e) {
      return e.statusCode != 404;
    }
  }

  Future<Map<String, dynamic>> getJobSettings() async => _dataMap(await _send('GET', '/api/settings/job'));
  Future<Map<String, dynamic>> getQuotationSettings() async => _dataMap(await _send('GET', '/api/settings/quotation'));

  // ------------------------------------------------------------------ Job

  Future<Map<String, dynamic>> getJobOverview(String id) async =>
      _dataMap(await _send('GET', '/api/field-service/jobs/$id/overview'));

  /// accept | forward | wait | resume | cancel | close | reopen
  Future<Map<String, dynamic>> jobWorkflowAction(
    String id,
    String action, {
    String? expectedStatus,
    String? note,
    String? reason,
    String? ownerId,
    bool? skipEmail,
    Map<String, dynamic> extra = const {},
  }) async {
    return _dataMap(await _send('POST', '/api/entity/job/$id/workflow-action', data: {
      'action': action,
      if (expectedStatus != null && expectedStatus.isNotEmpty) 'expected_status': expectedStatus,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (ownerId != null && ownerId.isNotEmpty) 'smownerid': ownerId,
      if (skipEmail != null) 'skip_email': skipEmail,
      ...extra,
    }));
  }

  Future<Map<String, dynamic>> getJobClosePreview(String id) async =>
      _dataMap(await _send('GET', '/api/field-service/jobs/$id/close-preview'));

  Future<Map<String, dynamic>> closeJob(
    String id, {
    required String scope,
    String? note,
    String? expectedStatus,
    bool skipEmail = false,
  }) async {
    return _dataMap(await _send('POST', '/api/field-service/jobs/$id/close', data: {
      'scope': scope,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (expectedStatus != null) 'expected_status': expectedStatus,
      if (skipEmail) 'skip_email': true,
    }));
  }

  Future<Map<String, dynamic>> reopenJob(String id, {String status = 'In Progress', bool reopenActivities = false, String? note}) async {
    return _dataMap(await _send('POST', '/api/field-service/jobs/$id/reopen', data: {
      'status': status,
      'reopen_activities': reopenActivities,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    }));
  }

  Future<Map<String, dynamic>> getJobSignatures(String id) async =>
      _dataMap(await _send('GET', '/api/field-service/jobs/$id/signatures'));

  /// [signature] is a `data:image/png;base64,…` URL or an upload path; null clears the slot.
  Future<Map<String, dynamic>> putJobSignature(String id, String slot, {String? signerName, String? signature}) async {
    return _dataMap(await _send('PUT', '/api/field-service/jobs/$id/signatures/${Uri.encodeComponent(slot)}', data: {
      'signer_name': signerName,
      'signature_path': signature,
    }));
  }

  Future<List<Map<String, dynamic>>> getJobActivityTemplates() async {
    final env = await _send('GET', '/api/settings/job/activity-templates', query: {'active': 1});
    final d = env['data'];
    // The server answers `{templates: […], owner_rules: […]}`.
    if (d is Map && d['templates'] is List) return extractMapList(d['templates']);
    return extractMapList(d);
  }

  /// `{template_id}` or `{items:[…]}` (+ `overrides`).
  Future<Map<String, dynamic>> generateJobActivities(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/field-service/jobs/$id/generate-activities', data: body));

  /// One photo per request; [clientId] makes retries idempotent.
  Future<Map<String, dynamic>> uploadJobPhoto(
    String id,
    MultipartFile file, {
    required String clientId,
    DateTime? takenAt,
    double? lat,
    double? lng,
    String? caption,
    CancelToken? cancel,
  }) async {
    final form = FormData()
      ..files.add(MapEntry('file', file))
      ..fields.add(MapEntry('client_id', clientId));
    if (takenAt != null) form.fields.add(MapEntry('taken_at', takenAt.toUtc().toIso8601String()));
    if (lat != null) form.fields.add(MapEntry('location_lat', '$lat'));
    if (lng != null) form.fields.add(MapEntry('location_lng', '$lng'));
    if (caption != null && caption.isNotEmpty) form.fields.add(MapEntry('caption', caption));
    return _dataMap(await _send('POST', '/api/field-service/jobs/$id/photos', data: form, cancel: cancel));
  }

  Future<List<Map<String, dynamic>>> editJobPhotos(String id, {List<String> remove = const [], Map<String, String> captions = const {}}) async {
    final env = await _send('PUT', '/api/field-service/jobs/$id/photos', data: {
      if (remove.isNotEmpty) 'remove': remove,
      if (captions.isNotEmpty) 'captions': captions,
    });
    final d = env['data'];
    if (d is Map && d['photos'] is List) return extractMapList(d['photos']);
    return extractMapList(d);
  }

  Future<Map<String, dynamic>> jobPublicLink(String id) async =>
      _dataMap(await _send('POST', '/api/field-service/jobs/$id/public-link'));

  Future<List<Map<String, dynamic>>> getJobsAwaitingMe() async {
    final env = await _send('GET', '/api/field-service/jobs/awaiting-me');
    final d = env['data'];
    if (d is Map && d['list'] is List) return extractMapList(d['list']);
    return extractMapList(d);
  }

  Future<List<Map<String, dynamic>>> getJobTimeline(String id, {int limit = 100}) async {
    final env = await _send('GET', '/api/entity/job/$id/timeline', query: {'limit': limit});
    return extractMapList(env['data']);
  }

  // ------------------------------------------------------------ Quotation

  Future<Map<String, dynamic>> getQuotationApprovalHistory(String id) async =>
      _dataMap(await _send('GET', '/api/quotation/$id/approval-history'));

  Future<List<Map<String, dynamic>>> getQuotationRevisions(String id) async {
    final env = await _send('GET', '/api/quotation/$id/revisions');
    final d = env['data'];
    if (d is Map && d['list'] is List) return extractMapList(d['list']);
    return extractMapList(d);
  }

  Future<Map<String, dynamic>> getQuotationCustomerActivity(String id) async =>
      _dataMap(await _send('GET', '/api/quotation/$id/customer-activity'));

  Future<Map<String, dynamic>> compareQuotations(String id, String otherId) async =>
      _dataMap(await _send('GET', '/api/quotation/$id/compare/$otherId'));

  Future<List<Map<String, dynamic>>> getQuotationOfferLog(String id) async {
    final env = await _send('GET', '/api/quotation/$id/offer-log');
    final d = env['data'];
    if (d is Map && d['list'] is List) return extractMapList(d['list']);
    return extractMapList(d);
  }

  /// Not for "ปิดการขาย" — use [setQuotationOutcome].
  Future<Map<String, dynamic>> setQuotationOfferStatus(String id, String offerStatus, {String? note}) async {
    return _dataMap(await _send('PUT', '/api/quotation/$id/offer-status', data: {
      'offer_status': offerStatus,
      if (note != null && note.isNotEmpty) 'note': note,
    }));
  }

  /// Close sale: [status] `Won` | `Lost`; [reason] required.
  Future<Map<String, dynamic>> setQuotationOutcome(
    String id, {
    required String status,
    required String reason,
    String? note,
    String? poReference,
    String? sourceModule,
    String? sourceId,
    bool? createJob,
  }) async {
    return _dataMap(await _send('PUT', '/api/quotation/$id/outcome', data: {
      'status': status,
      'reason': reason,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (poReference != null && poReference.trim().isNotEmpty) 'po_reference': poReference.trim(),
      if (sourceModule != null) 'source_module': sourceModule,
      if (sourceId != null) 'source_id': sourceId,
      if (createJob != null) 'create_job': createJob,
    }));
  }

  Future<Map<String, dynamic>> quotationCreateJob(String id) async =>
      _dataMap(await _send('POST', '/api/quotation/$id/create-job'));

  /// levels: `[{level:1, user_ids:[…]}, …]`
  Future<Map<String, dynamic>> submitQuotationApprovalLevels(String id, List<Map<String, dynamic>> levels) async =>
      _dataMap(await _send('POST', '/api/quotation/$id/approval/submit', data: {'levels': levels}));

  Future<Map<String, dynamic>> quotationPublicLink(String id) async =>
      _dataMap(await _send('POST', '/api/quotation/$id/public-link'));

  /// Atomic header + lines save. Without [id] creates (used for duplicate).
  Future<Map<String, dynamic>> saveQuotation({String? id, required Map<String, dynamic> fields, required List<Map<String, dynamic>> lines}) async {
    return _dataMap(await _send('POST', '/api/quotation/save', data: {
      if (id != null) 'id': id,
      'fields': fields,
      'lines': lines,
    }));
  }

  Future<Map<String, dynamic>> reviseQuotationWith(String id, {Map<String, dynamic>? fields, List<Map<String, dynamic>>? lines, String? note}) async {
    return _dataMap(await _send('POST', '/api/quotation/$id/revise', data: {
      if (fields != null) 'fields': fields,
      if (lines != null) 'lines': lines,
      if (note != null && note.trim().isNotEmpty) 'revision_note': note.trim(),
    }));
  }

  /// The web form's context: users, document templates, allowed layouts
  /// (Template-1/2 per Business / Package), new-quotation defaults, branding.
  Future<Map<String, dynamic>> getQuotationContext() async => _dataMap(await _send('GET', '/api/quotation/context'));

  /// My default text blocks for a new quotation (`{intro|terms|footer|…: {html, templateIds, locale}}`).
  Future<Map<String, dynamic>> resolveQuotationTextDefaults({String locale = 'th'}) async =>
      _dataMap(await _send('GET', '/api/quotation/text-templates/defaults/resolve', query: {'locale': locale}));

  /// Job form context: document templates, allowed layouts, job settings' document defaults.
  Future<Map<String, dynamic>> getJobFormContext() async => _dataMap(await _send('GET', '/api/field-service/job-form-context'));

  Future<Map<String, dynamic>> getQuotationEmailStatus(String id) async =>
      _dataMap(await _send('GET', '/api/approvals/quotation/$id/email-status'));

  Future<Map<String, dynamic>> resendQuotationApprovalEmail(String id) async =>
      _dataMap(await _send('POST', '/api/approvals/quotation/$id/resend-email'));

  // ------------------------------------------------------------------ Case

  /// accept | forward | wait | resume | cancel | close (NEXTX case workflow).
  // --- Service contract extras ------------------------------------------
  /// Renew: preview (`commit=false`) or create the Draft on the server.
  Future<Map<String, dynamic>> renewServiceContract(String id, {bool commit = false}) async =>
      _dataMap(await _send('POST', '/api/entity/service_contract/$id/renew', data: {if (commit) 'commit': 1}));
  Future<Map<String, dynamic>> getContractRenewalSeries(String id) async =>
      _dataMap(await _send('GET', '/api/entity/service_contract/$id/renewal-series'));
  Future<Map<String, dynamic>> resendServiceContractSign(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/entity/service_contract/$id/resend-sign', data: body));
  Future<Map<String, dynamic>> getContractMandayTransferPreview(String id) async =>
      _dataMap(await _send('GET', '/api/entity/service_contract/$id/manday/transfer-preview'));
  Future<Map<String, dynamic>> transferContractMandayToAccount(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/entity/service_contract/$id/manday/transfer-to-account', data: body));

  // --- Case / Job → Workspace --------------------------------------------
  Future<List<Map<String, dynamic>>> getCaseWorkTemplates() async {
    final env = await _send('GET', '/api/case-work-templates', query: {'active': '1'});
    final d = env['data'];
    return extractMapList(d is Map ? d['list'] : d);
  }
  Future<Map<String, dynamic>> generateCaseWork(String caseId, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/entity/case/$caseId/generate-work', data: body));
  Future<Map<String, dynamic>> createCaseWorkspaceTask(String caseId, {required int boardId, String? title}) async =>
      _dataMap(await _send('POST', '/api/field-service/cases/$caseId/workspace-task', data: {'board_id': boardId, if (title != null && title.isNotEmpty) 'title': title}));
  Future<Map<String, dynamic>> createJobWorkspace(String jobId, {required int boardId, required String mode, String? title}) async =>
      _dataMap(await _send('POST', '/api/field-service/jobs/$jobId/workspace', data: {'board_id': boardId, 'mode': mode, if (title != null && title.isNotEmpty) 'title': title}));

  // --- Deal → Workspace ---------------------------------------------------
  Future<Map<String, dynamic>> getDealWorkspace(String dealId) async => _dataMap(await _send('GET', '/api/entity/deal/$dealId/workspace'));
  Future<Map<String, dynamic>> linkDealWorkspace(String dealId, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/entity/deal/$dealId/workspace', data: body));
  Future<void> unlinkDealWorkspace(String dealId) async => _send('DELETE', '/api/entity/deal/$dealId/workspace');

  // --- Workspace bulk change (preview → job → undo) -----------------------
  Future<Map<String, dynamic>> previewWorkspaceBulk(Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/workspace/bulk/preview', data: body));
  Future<Map<String, dynamic>> startWorkspaceBulk(Map<String, dynamic> body) async => _dataMap(await _send('POST', '/api/workspace/bulk/jobs', data: body));
  Future<Map<String, dynamic>> getWorkspaceBulkJob(String jobId) async => _dataMap(await _send('GET', '/api/workspace/bulk/jobs/$jobId'));
  Future<Map<String, dynamic>> cancelWorkspaceBulkJob(String jobId) async => _dataMap(await _send('POST', '/api/workspace/bulk/jobs/$jobId/cancel'));
  Future<Map<String, dynamic>> undoWorkspaceBulkJob(String jobId) async => _dataMap(await _send('POST', '/api/workspace/bulk/jobs/$jobId/undo'));

  /// Save a job's activities as a template (`{name, category?}`).
  Future<Map<String, dynamic>> saveJobActivitiesAsTemplate(String jobId, {required String name, String? category}) async =>
      _dataMap(await _send('POST', '/api/field-service/jobs/$jobId/activity-template', data: {'name': name, if (category != null && category.isNotEmpty) 'category': category}));

  /// Service contract status change (`{action, ...}`) — the only way the
  /// server accepts a new `contract_status`.
  Future<Map<String, dynamic>> serviceContractWorkflowAction(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/entity/service_contract/$id/workflow-action', data: body));

  Future<Map<String, dynamic>> caseWorkflowAction(String id, Map<String, dynamic> body) async =>
      _dataMap(await _send('POST', '/api/entity/case/$id/workflow-action', data: body));

  Future<Map<String, dynamic>> previewCaseWorkflow(String id, String action, {String? ownerId}) async =>
      _dataMap(await _send('GET', '/api/entity/case/$id/workflow-preview', query: {
        'action': action,
        if (ownerId != null) 'smownerid': ownerId,
      }));

  Future<List<Map<String, dynamic>>> getCaseOpenJobs(String id) async {
    final env = await _send('GET', '/api/field-service/cases/$id/open-jobs');
    final d = env['data'];
    if (d is Map && d['list'] is List) return extractMapList(d['list']);
    if (d is Map && d['jobs'] is List) return extractMapList(d['jobs']);
    return extractMapList(d);
  }

  /// Status changes of a case, newest first: `{action, from_status, to_status, details, at, user_name}`.
  Future<List<Map<String, dynamic>>> getCaseStatusEvents(String id) async {
    final env = await _send('GET', '/api/entity/case/$id/status-events', query: {'limit': '50'});
    final d = env['data'];
    return extractMapList(d is Map ? d['list'] : d);
  }

  /// Contacts of a customer account (direct + linked), for picking an email.
  Future<List<Map<String, dynamic>>> getAccountContacts(String accountId) async {
    final page = await getEntityList('contact', limit: 50, extra: {'filter[account_id_any]': accountId});
    return page.items;
  }

  /// One page of a quotation picker (customer / contact / product / service):
  /// searches the real name columns ([kPickerSearchCols]) — `q` alone only
  /// matched the running number of products on the server.
  Future<EntityListPage> searchPicker(
    String module, {
    String q = '',
    int page = 1,
    int limit = 30,
    Map<String, String> filters = const {},
    bool sellableOnly = false,
    CancelToken? cancel,
  }) =>
      getEntityList(module, q: q, page: page, limit: limit, extra: pickerQueryParams(module, q: q, filters: filters, sellableOnly: sellableOnly), cancel: cancel);

  // --------------------------------------------------------------- shared

  /// `{quotations, jobs, activities}` linked to a quotation / job / activity.
  Future<Map<String, dynamic>> getJourneyLinks(String module, String id) async =>
      _dataMap(await _send('GET', '/api/links/$module/$id'));

  Future<Map<String, dynamic>> addJourneyLink(String fromModule, String fromId, String toModule, String toId) async =>
      _dataMap(await _send('POST', '/api/links', data: {'from_module': fromModule, 'from_id': fromId, 'to_module': toModule, 'to_id': toId}));

  Future<void> removeJourneyLink(String fromModule, String fromId, String toModule, String toId) async =>
      _send('DELETE', '/api/links', data: {'from_module': fromModule, 'from_id': fromId, 'to_module': toModule, 'to_id': toId});

  /// `{quotations, activities, jobs, count}` waiting for me.
  Future<Map<String, dynamic>> getApprovalInbox() async => _dataMap(await _send('GET', '/api/approvals/inbox'));

  Future<Map<String, dynamic>> approveActivity(String id, {String? note}) async =>
      _dataMap(await _send('POST', '/api/activity-approval/$id/approve', data: {if (note != null && note.isNotEmpty) 'note': note}));

  Future<Map<String, dynamic>> rejectActivity(String id, {String? note}) async =>
      _dataMap(await _send('POST', '/api/activity-approval/$id/reject', data: {if (note != null && note.isNotEmpty) 'note': note}));

  // ------------------------------------------------- Document e-mail (compose)
  // The web's "ส่งอีเมล" window: quotation → /api/quotation/:id/…,
  // job → /api/field-service/jobs/:id/… (same fields and answers).

  String _composeBase(String kind, String id) =>
      kind == 'job' ? '/api/field-service/jobs/${Uri.encodeComponent(id)}' : '/api/quotation/${Uri.encodeComponent(id)}';

  /// Recipients, subject, body (HTML), templates, suggestions, limits, mail_ready.
  Future<Map<String, dynamic>> getDocComposeDefaults(String kind, String id) async =>
      _dataMap(await _send('GET', '${_composeBase(kind, id)}/compose-defaults'));

  /// Sends like the web (multipart): the server builds the PDF from the
  /// document template (BIRT) when [includePdf]; [files] ride along (≤10 × 15 MB).
  Future<({Map<String, dynamic> data, String message})> sendDocCompose(
    String kind,
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String bodyHtml,
    bool includePdf = true,
    bool includeLink = false,
    String? templateId,
    List<MultipartFile> files = const [],
    ProgressCallback? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'to': to.join(','),
      'cc': cc.join(','),
      'bcc': bcc.join(','),
      'subject': subject,
      'body_html': bodyHtml,
      'include_pdf': includePdf ? 'true' : 'false',
      'include_link': includeLink ? 'true' : 'false',
      'template_id': templateId ?? '',
      'file_ids': '',
    });
    for (final f in files) {
      form.files.add(MapEntry('files', f));
    }
    final env = await _send('POST', '${_composeBase(kind, id)}/compose-send', data: form, onSendProgress: onSendProgress, options: Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 3)));
    return (data: _dataMap(env), message: env['message']?.toString() ?? env['messagestatus']?.toString() ?? '');
  }

  /// E-mails sent from the window (newest first).
  Future<List<Map<String, dynamic>>> getDocEmailLog(String kind, String id) async {
    final env = await _send('GET', '${_composeBase(kind, id)}/email-log');
    final d = env['data'];
    return extractMapList(d is Map ? d['items'] : d);
  }
}
