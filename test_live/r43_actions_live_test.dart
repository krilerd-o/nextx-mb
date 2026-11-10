// Manual tool (not part of `flutter test`): R43 list-row commands against a
// local NEXTX backend (nextx_qa), using only [QA] records this test creates.
// ignore_for_file: invalid_use_of_visible_for_testing_member, avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/core/entity_form_rules.dart';
import 'package:nextx_mobile/screens/crm/entity_record_actions.dart';
import 'package:nextx_mobile/services/api_client.dart';
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';

void main() {
  test('status / comment / edit / duplicate / delete on new [QA] records', () async {
    HttpOverrides.global = null; // real network
    final token = File(Platform.environment['QA_TOKEN_FILE']!).readAsStringSync().trim();
    final api = ApiClient()..attachSession(baseUrl: 'http://127.0.0.1:4000', accessToken: token, businessId: '1');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final created = <(String, String)>[];
    try {
      for (final module in ['lead', 'deal', 'job', 'quotation']) {
        final schema = await api.getFieldSchema(module, fresh: true);
        final key = EntityRecordActions.statusKey(module, schema.picklists);
        final options = EntityRecordActions.statusOptions(module, key, schema.picklists);
        print('[$module] status key=$key options=${options.map((o) => o.value).toList()}');
        expect(key, isNotNull, reason: module);
        expect(options.length, greaterThan(1), reason: module);

        final names = {for (final f in schema.fields) fieldName(f)};
        final nameField = ['lead_name', 'deal_name', 'job_name', 'title_th', 'quotation_name', 'subject', 'name'].firstWhere(names.contains);
        final title = '[QA] R43 $module $stamp';
        // Fill every required field like the create form would.
        final body = <String, dynamic>{};
        for (final f in schema.fields) {
          if (!fieldIsRequired(f)) continue;
          final n = fieldName(f);
          final pl = schema.picklists[n] ?? const [];
          final t = resolveFieldUiType(f);
          body[n] = pl.isNotEmpty
              ? '${pl.first['value']}'
              : t == FieldUiType.date
                  ? '2026-11-09'
                  : t == FieldUiType.dateTime
                      ? '2026-11-09T10:00:00'
                      : t == FieldUiType.number || t == FieldUiType.currency
                          ? 0
                          : '[QA] R43';
        }
        body[nameField] = title;
        body[key!] = options.first.value;
        print('[$module] create body keys=${body.keys.toList()}');
        final res = await api.postEntity(module, body);
        final id = '${res['id'] ?? res['insertId'] ?? ''}';
        print('[$module] created id=$id');
        expect(id, isNotEmpty);
        created.add((module, id));

        // Status (what the status sheet sends).
        final next = options[1].value;
        await api.putEntity(module, id, {key: next});
        var row = await api.getEntity(module, id);
        expect('${row[key]}', next, reason: '$module status saved');
        // Undo = send the old value back.
        await api.putEntity(module, id, {key: options.first.value});
        row = await api.getEntity(module, id);
        expect('${row[key]}', options.first.value);

        // Comment.
        await api.postEntityComment(module, id, '[QA] R43 คอมเมนต์จากรายการ');
        final comments = await api.getEntityComments(module, id);
        expect(comments.any((c) => '${c['body'] ?? c['comment'] ?? ''}'.contains('[QA] R43')), isTrue);

        // Edit: form fields exist and a change saves.
        final editable = EntityRecordActions.editableFields(schema.fields, row);
        expect(editable, isNotEmpty);
        await api.putEntity(module, id, {nameField: '$title (แก้ไข)'});
        row = await api.getEntity(module, id);
        expect('${row[nameField]}', contains('(แก้ไข)'));

        // Duplicate (form values → create), like saving the copy form.
        if (!kServerDuplicateModules.contains(module)) {
          final values = duplicateFormValues(module, row, userId: '2', picklists: schema.picklists);
          values[nameField] = '$title (สำเนา)';
          values.removeWhere((k, v) => v is Map);
          final copy = await api.postEntity(module, values);
          final copyId = '${copy['id'] ?? copy['insertId'] ?? ''}';
          expect(copyId, isNotEmpty);
          created.add((module, copyId));
          print('[$module] duplicate id=$copyId');
        } else {
          final copyId = await api.duplicateEntity(module, id);
          expect(copyId, isNotEmpty);
          created.add((module, copyId));
          print('[$module] server duplicate id=$copyId');
        }
      }
    } finally {
      // Delete only what this test created (the list's delete after the undo window).
      for (final (m, id) in created.reversed) {
        await api.deleteEntity(m, id);
        print('deleted $m/$id');
      }
    }
  });
}
