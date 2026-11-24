import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Lead Register answers that could not be sent (booth with poor signal).
/// Each keeps its `client_uuid`, so replays never create duplicates.
class LeadRegisterQueue {
  LeadRegisterQueue._();
  static final instance = LeadRegisterQueue._();

  static const prefsKey = 'offline_lead_register_v1';
  final ValueNotifier<int> pending = ValueNotifier<int>(0);
  bool _flushing = false;

  Future<List<Map<String, dynamic>>> _read() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(p.getString(prefsKey) ?? '[]');
      return raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Map<String, dynamic>> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(prefsKey, jsonEncode(items));
    pending.value = items.length;
  }

  Future<void> load() async => pending.value = (await _read()).length;

  Future<void> add({required int formId, required Map<String, dynamic> answers, required String clientUuid, required String channel, int? fillMs, int? leadId}) async {
    final items = await _read();
    items.add({'form_id': formId, 'answers': answers, 'client_uuid': clientUuid, 'channel': channel, 'fill_ms': fillMs, 'lead_id': leadId, 'at': DateTime.now().toIso8601String()});
    await _write(items);
  }

  /// Sends what it can. Network failures stay queued; answers the server
  /// rejects (closed form, invalid) are dropped so the queue never blocks.
  Future<int> flush(ApiClient api) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final items = await _read();
      if (items.isEmpty) return 0;
      final left = <Map<String, dynamic>>[];
      for (final it in items) {
        try {
          await api.submitLeadForm(
            (it['form_id'] as num).toInt(),
            answers: Map<String, dynamic>.from(it['answers'] as Map),
            clientUuid: it['client_uuid'].toString(),
            channel: it['channel']?.toString() ?? 'mobile',
            fillMs: (it['fill_ms'] as num?)?.toInt(),
            leadId: (it['lead_id'] as num?)?.toInt(),
          );
          sent++;
        } on ApiEnvelopeException {
          // server said no (validation / closed) — drop
        } on ApiException catch (e) {
          if (e.statusCode == 0 || e.statusCode >= 500) left.add(it);
        } catch (_) {
          left.add(it);
        }
      }
      await _write(left);
      return sent;
    } finally {
      _flushing = false;
    }
  }
}
