import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/nx_form_field.dart';
import 'package:nextx_mobile/widgets/fields/nx_pick_option.dart';

void main() {
  testWidgets('select / date / person fields are as tall as a text input; icons on the left', (tester) async {
    const types = [FieldUiType.text, FieldUiType.email, FieldUiType.picklist, FieldUiType.date, FieldUiType.dateTime, FieldUiType.time, FieldUiType.picklistUser];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          for (final t in types)
            Padding(
              padding: const EdgeInsets.all(8),
              child: NxFormField(
                key: ValueKey('f-${t.name}'),
                uiType: t,
                label: 'ช่อง ${t.name}',
                name: t.name,
                options: const [NxPickOption(value: 'a', label: 'A')],
                onChanged: (_) {},
              ),
            ),
        ]),
      ),
    ));
    await tester.pump();
    final h = {for (final t in types) t: tester.getSize(find.byKey(ValueKey('f-${t.name}'))).height};
    for (final t in types) {
      expect(h[t], closeTo(h[FieldUiType.text]!, 1.5), reason: '${t.name} ${h[t]} vs text ${h[FieldUiType.text]}');
    }
    // Date icon sits left of the label text.
    final field = find.byKey(const ValueKey('f-date'));
    final icon = tester.getCenter(find.descendant(of: field, matching: find.byType(Icon)).first);
    final label = tester.getCenter(find.descendant(of: field, matching: find.textContaining('ช่อง date')).first);
    expect(icon.dx, lessThan(label.dx));
  });
}
