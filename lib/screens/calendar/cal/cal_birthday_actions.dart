import 'package:flutter/widgets.dart';

import '../../../core/i18n.dart';
import '../../../core/nx_page_route.dart';
import '../../crm/entity_create_screen.dart';
import '../../crm/entity_detail_screen.dart';
import 'cal_birthdays.dart';
import 'cal_model.dart';

/// Opens the birthday card for [b] (calendar and Home), wired to the record
/// screen and to "plan a greeting" (a new activity at 09:00 on the birthday,
/// linked to the customer). [onChanged] runs after an activity was created.
void openCalBirthday(BuildContext context, CalBirthday b, DateTime day, {Rect? anchor, VoidCallback? onChanged}) {
  showCalBirthdayCard(
    context,
    b: b,
    day: day,
    anchor: anchor,
    onOpenRecord: () => nxOpenDetail<void>(context, EntityDetailScreen(module: b.module, row: b.row)),
    onPlanGreeting: () async {
      final at = DateTime(day.year, day.month, day.day, 9);
      await nxPush<void>(
        context,
        EntityCreateScreen(
          module: 'activity',
          title: 'นัดหมายใหม่',
          initialValues: {
            'subject': '${tr('อวยพรวันเกิด')} ${b.name}',
            'date_start': ymdhm(at),
            'date_end': ymdhm(at.add(const Duration(minutes: 30))),
            'related_module': b.module,
            'related_id': b.id,
          },
        ),
      );
      onChanged?.call();
    },
  );
}
