import 'package:flutter/foundation.dart';

import '../../core/journey_rules.dart' show jobReportMissing, jobRequireBothSignatures;
import '../../services/api_client.dart';

/// Extra data a Service Journey detail page needs besides the record itself.
/// Every piece is optional: a failed call leaves it empty (the page still works).
class JourneyController extends ChangeNotifier {
  JourneyController({required this.api, required this.module, required this.id});

  final ApiClient api;
  final String module;
  final String id;

  bool loading = false;

  // job
  Map<String, dynamic> overview = const {};
  Map<String, dynamic> signatures = const {};
  Map<String, dynamic> jobSettings = const {};

  // quotation
  Map<String, dynamic> qtSettings = const {};
  Map<String, dynamic> approvalHistory = const {};
  List<Map<String, dynamic>> revisions = const [];
  Map<String, dynamic> customer = const {};
  List<Map<String, dynamic>> lines = const [];
  bool linesLoaded = false;

  // shared
  Map<String, dynamic> links = const {};

  Future<T?> _try<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      if (kDebugMode) debugPrint('[journey] $module/$id: $e');
      return null;
    }
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    if (module == 'job') {
      final r = await Future.wait<Object?>([
        _try(() => api.getJobOverview(id)),
        _try(() => api.getJobSignatures(id)),
        _try(() => api.getJourneyLinks('job', id)),
        if (jobSettings.isEmpty) _try(() => api.getJobSettings()),
      ]);
      overview = (r[0] as Map<String, dynamic>?) ?? overview;
      signatures = (r[1] as Map<String, dynamic>?) ?? signatures;
      links = (r[2] as Map<String, dynamic>?) ?? links;
      if (r.length > 3) jobSettings = (r[3] as Map<String, dynamic>?) ?? jobSettings;
    } else if (module == 'quotation') {
      final r = await Future.wait<Object?>([
        _try(() => api.getQuotationApprovalHistory(id)),
        _try(() => api.getQuotationRevisions(id)),
        _try(() => api.getQuotationCustomerActivity(id)),
        _try(() => api.getJourneyLinks('quotation', id)),
        _try(() => api.getQuotationLines(id)),
        if (qtSettings.isEmpty) _try(() => api.getQuotationSettings()),
      ]);
      approvalHistory = (r[0] as Map<String, dynamic>?) ?? approvalHistory;
      revisions = (r[1] as List<Map<String, dynamic>>?) ?? revisions;
      customer = (r[2] as Map<String, dynamic>?) ?? customer;
      links = (r[3] as Map<String, dynamic>?) ?? links;
      final l = r[4] as List<Map<String, dynamic>>?;
      if (l != null) {
        lines = l;
        linesLoaded = true;
      }
      if (r.length > 5) qtSettings = (r[5] as Map<String, dynamic>?) ?? qtSettings;
    }
    loading = false;
    notifyListeners();
  }

  List<Map<String, dynamic>> linked(String key) {
    final v = links[key];
    return v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];
  }

  // ---- job settings helpers
  /// `close.require_both_signatures` (default ON, like the server).
  bool get requireBothSignatures => jobRequireBothSignatures(jobSettings);

  /// The job's signature slots (`GET /jobs/:id/signatures`).
  List<Map<String, dynamic>> get signatureSlots => [
        for (final s in (signatures['slots'] as List? ?? const []))
          if (s is Map) Map<String, dynamic>.from(s),
      ];

  /// Report signers the close still needs (empty when the setting is off).
  List<String> closeSignaturesMissing(Map<String, dynamic> row) =>
      requireBothSignatures ? jobReportMissing(row, slots: signatureSlots) : const [];

  // ---- quotation settings helpers
  Map<String, dynamic> get _qtConfig => qtSettings['config'] is Map ? Map<String, dynamic>.from(qtSettings['config']) : const {};
  Map<String, dynamic> get _approvalCfg => _qtConfig['approval'] is Map ? Map<String, dynamic>.from(_qtConfig['approval']) : const {};
  bool get approvalRequired => _approvalCfg['required'] == true;
  List<Map<String, dynamic>> get approvalLevels => [
        for (final l in (_approvalCfg['levels'] as List? ?? const []))
          if (l is Map && l['enabled'] != false) Map<String, dynamic>.from(l),
      ];
  int get staleDays {
    final f = _qtConfig['follow_up'];
    final v = f is Map ? f['stale_days'] : null;
    return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 7;
  }
}
