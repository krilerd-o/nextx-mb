import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/doc_form/doc_form_rules.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/nx_page_route.dart';
import 'job_step_form.dart';
import 'quotation_step_form.dart';

export '../../core/doc_form/doc_form_rules.dart' show DocFormMode, kStepFormModules, docFormModeOf;

/// The step form of a quotation / job (create, edit, ทำซ้ำ, Revise).
Widget docFormScreen({
  required String module,
  DocFormMode mode = DocFormMode.create,
  String? id,
  Map<String, dynamic>? initialValues,
  ({String module, Map<String, dynamic> row})? parent,
  bool embedded = false,
  ValueChanged<Map<String, dynamic>?>? onFinished,
  Key? key,
}) {
  if (module == 'job') {
    return JobStepForm(
      key: key,
      mode: mode == DocFormMode.revise ? DocFormMode.create : mode,
      recordId: id,
      initialValues: initialValues,
      parent: parent,
      embedded: embedded,
      onFinished: onFinished,
    );
  }
  return QuotationStepForm(
    key: key,
    mode: mode,
    recordId: id,
    initialValues: initialValues,
    embedded: embedded,
    onFinished: onFinished,
  );
}

/// Opens the step form; `{id, …}` when saved, null when left (a draft stays on the device).
Future<Map<String, dynamic>?> openDocForm(
  BuildContext context, {
  required String module,
  DocFormMode mode = DocFormMode.create,
  String? id,
  Map<String, dynamic>? initialValues,
  ({String module, Map<String, dynamic> row})? parent,
  bool? root,
}) {
  return nxPush<Map<String, dynamic>>(
    context,
    docFormScreen(module: module, mode: mode, id: id, initialValues: initialValues, parent: parent),
    root: root,
  );
}

/// `/form/:module` (deep links of the web's form pages): leaves to the saved
/// record, or back / home when closed.
class DocFormRoutePage extends StatelessWidget {
  const DocFormRoutePage({super.key, required this.module, this.mode = DocFormMode.create, this.id});
  final String module;
  final DocFormMode mode;
  final String? id;

  @override
  Widget build(BuildContext context) => docFormScreen(
        module: module,
        mode: mode,
        id: id,
        onFinished: (r) {
          final saved = '${r?['id'] ?? ''}';
          if (saved.isNotEmpty && saved != 'null') {
            GoRouter.of(context).go(module == 'job' ? AppRoutes.fsmRecord(module, saved) : AppRoutes.crmRecord(module, saved));
          } else {
            nxLeavePage(context);
          }
        },
      );
}
