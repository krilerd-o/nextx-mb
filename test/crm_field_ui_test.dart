import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextx_mobile/widgets/nx_shake.dart';
import 'package:nextx_mobile/core/app_config.dart';
import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/screens/crm/entity_create_screen.dart';
import 'package:nextx_mobile/widgets/fields/field_format.dart';
import 'package:nextx_mobile/widgets/fields/field_ui_type.dart';
import 'package:nextx_mobile/widgets/fields/field_validate.dart';
import 'package:nextx_mobile/widgets/fields/nx_canvas_field.dart';
import 'package:nextx_mobile/widgets/fields/nx_entity_form.dart';
import 'package:nextx_mobile/widgets/fields/nx_field_chrome.dart';
import 'package:nextx_mobile/widgets/fields/nx_field_value.dart';
import 'package:nextx_mobile/widgets/fields/nx_form_field.dart';
import 'package:nextx_mobile/widgets/fields/nx_pick_option.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UITYPE_OPTIONS has 52 canonical values', () {
    expect(kUitypeOptionValues.toSet().length, 52);
    expect(kUitypeOptionValues.contains('Picklist'), isTrue);
    expect(kUitypeOptionValues.contains('Enum'), isTrue);
  });

  test('every UITYPE_OPTIONS value resolves to a dedicated type', () {
    for (final name in kUitypeOptionValues) {
      final type = fieldUiTypeFromName(name);
      expect(type, isNotNull, reason: name);
      expect(type!.wireName, name);
    }
  });

  test('aliases and extras resolve', () {
    expect(resolveFieldUiType({'uitype': 'Checkbox'}), FieldUiType.yesNo);
    expect(resolveFieldUiType({'type': 'Boolean'}), FieldUiType.yesNo);
    expect(resolveFieldUiType({'type': 'Toggle'}), FieldUiType.yesNo);
    expect(resolveFieldUiType({'type': 'Decimal'}), FieldUiType.number);
    expect(resolveFieldUiType({'type': 'Price'}), FieldUiType.currency);
    expect(resolveFieldUiType({'inputType': 'taxid'}), FieldUiType.taxId);
    expect(resolveFieldUiType({'uitype': 'InspectionSelect'}).entityModule, 'inspection');
    expect(resolveFieldUiType({'uitype': 'SkillSelect'}).entityModule, 'skill');
    expect(resolveFieldUiType({'name': 'smownerid'}), FieldUiType.owner);
    expect(resolveFieldUiType({'name': 'assign_to'}), FieldUiType.assignTo);
    expect(resolveFieldUiType({'uitype': 'LocationSelect'}).entityModule, 'service_location');
    expect(resolveFieldUiType({'uitype': 'ContractSelect'}).entityModule, 'service_contract');
  });

  test('taxid and phone formatters', () {
    expect(formatTaxIdDisplay('1234567890123'), '1-2345-67890-12-3');
    expect(digitsOnly('1-2345-67890-12-3', 13), '1234567890123');
    expect(formatPhoneDisplay('0812345678'), '081-234-5678');
  });

  testWidgets('every uitype paints its own widget in light and dark', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final options = [
      const NxPickOption(value: 'new', label: 'ใหม่', color: Color(0xFF0EA5E9)),
      const NxPickOption(value: 'won', label: 'ชนะ'),
    ];

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final name in kUitypeOptionValues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NxFormField(
                        uiType: fieldUiTypeFromName(name)!,
                        canonicalName: name,
                        label: name,
                        value: name == 'YesNo'
                            ? '1'
                            : name == 'Percent' || name == 'Progress'
                                ? '40'
                                : name == 'Color'
                                    ? '#6366F1'
                                    : name == 'EmotionalEmoji'
                                        ? 'happy'
                                        : null,
                        options: options,
                        onChanged: (_) {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final name in kUitypeOptionValues) {
        expect(find.byKey(ValueKey('nx-field-$name')), findsOneWidget, reason: name);
      }

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byType(Switch), findsWidgets);
      expect(find.byType(Slider), findsWidgets);
      expect(find.byType(NxCanvasField), findsWidgets);
      expect(find.byType(ChoiceChip), findsWidgets);

      final textField = tester.widget<TextField>(find.byType(TextField).first);
      final border = textField.decoration?.enabledBorder as OutlineInputBorder?;
      expect(border?.borderRadius, BorderRadius.circular(NxFieldStyle.radius));
      expect(NxFieldStyle.radius, 14);
      expect(textField.decoration?.floatingLabelBehavior, FloatingLabelBehavior.auto);
      expect(
        textField.decoration?.labelText ?? textField.decoration?.hintText ?? textField.decoration?.hint,
        isNotNull,
      );
    }
  });

  testWidgets('empty field shows name inside, focus floats it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NxFormField(
            uiType: FieldUiType.text,
            label: 'ชื่อ',
            required: true,
            value: '',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    final empty = tester.widget<TextField>(find.byType(TextField));
    // Required + empty: bold label with a red " *" inside the field.
    final hint = empty.decoration?.hint as Text;
    final span = hint.textSpan! as TextSpan;
    expect(span.text, 'ชื่อ');
    expect(span.style?.fontWeight, FontWeight.w700);
    final star = span.children!.single as TextSpan;
    expect(star.text, ' *');
    expect(star.style?.color, AppTheme.light.colorScheme.error);
    expect(empty.decoration?.labelText, isNull);
    expect(empty.decoration?.hintStyle?.fontSize, 15);
    expect(empty.decoration?.hintStyle?.height, 1.2);
    expect(empty.textAlignVertical, TextAlignVertical.center);
    expect(empty.decoration?.suffixIconConstraints?.maxHeight, 22);
    expect(empty.decoration?.isDense, isTrue);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    final focused = tester.widget<TextField>(find.byType(TextField));
    expect(focused.decoration?.label, isA<Text>());
    expect(focused.decoration?.labelText, isNull);
    expect(focused.decoration?.hintText, isNull);
    expect(focused.decoration?.floatingLabelStyle?.fontSize, 12);
    expect(focused.decoration?.floatingLabelStyle?.fontWeight, FontWeight.w500);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('picklist values render as chips not raw ids', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: NxFieldValueView(
            uiType: FieldUiType.enumeration,
            label: 'สถานะ',
            value: 'new',
            options: [NxPickOption(value: 'new', label: 'ใหม่')],
          ),
        ),
      ),
    );
    expect(find.text('ใหม่'), findsOneWidget);
    expect(find.text('new'), findsNothing);
  });

  test('required and format validation', () {
    expect(validateFieldValue(FieldUiType.text, '', required: true), 'จำเป็นต้องกรอก');
    expect(validateFieldValue(FieldUiType.email, 'not-mail', required: false), 'อีเมลไม่ถูกต้อง');
    expect(validateFieldValue(FieldUiType.phone, '08123', required: false), 'เบอร์โทร 10 หลัก');
    expect(validateFieldValue(FieldUiType.taxId, '123', required: false), 'เลขภาษี 13 หลัก');
    expect(validateFieldValue(FieldUiType.link, 'example.com', required: false), 'ลิงก์ต้องขึ้นต้นด้วย http');
    expect(validateFieldValue(FieldUiType.email, 'a@b.com', required: true), isNull);
    expect(unwrapFieldValue({'id': '9', 'label': 'สมชาย'}), '9');
  });

  test('schema order and defaults', () {
    final fields = [
      {'name': 'lastname', 'label_th': 'นามสกุล', 'uitype': 'Text', 'sequence': 2},
      {
        'name': 'firstname',
        'label_th': 'ชื่อ',
        'uitype': 'Text',
        'sequence': 1,
        'required': true,
        'defaultvalue': 'ใหม่',
      },
    ];
    final values = <String, dynamic>{};
    applyFieldDefaults(fields, values);
    expect(values['firstname'], 'ใหม่');
    final ordered = [...fields]..sort((a, b) => fieldSequence(a).compareTo(fieldSequence(b)));
    expect(ordered.first['name'], 'firstname');
  });

  testWidgets('form follows schema order not UI group', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NxEntityForm(
            fields: <Map<String, dynamic>>[
              {'name': 'lastname', 'label_th': 'นามสกุล', 'uitype': 'Text', 'sequence': 2},
              {'name': 'firstname', 'label_th': 'ชื่อ', 'uitype': 'Text', 'sequence': 1},
            ],
            values: const {},
            onChanged: (_, _) {},
          ),
        ),
      ),
    );
    final labels = tester.widgetList<NxFormField>(find.byType(NxFormField)).map((w) => w.label).toList();
    expect(labels, ['ชื่อ', 'นามสกุล']);
  });

  testWidgets('picker sheet is draggable and keeps search above keyboard', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NxFormField(
            uiType: FieldUiType.enumeration,
            label: 'สถานะ',
            options: const [
              NxPickOption(value: 'new', label: 'ใหม่'),
              NxPickOption(value: 'won', label: 'ชนะ'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('สถานะ'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('ค้นหา'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
    expect(find.text('ค้นหา'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    tester.view.viewInsets = FakeViewPadding.zero;
  });

  Future<void> pumpLeadForm(
    WidgetTester tester, {
    required ThemeMode mode,
    required List<Map<String, dynamic>> fields,
    String? recordId,
    Map<String, dynamic>? initialValues,
    required String title,
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: EntityCreateScreen(
            module: 'lead',
            title: title,
            recordId: recordId,
            initialValues: initialValues,
            fields: fields,
          ),
        ),
      ),
    );
  }

  testWidgets('create lead blocks empty required in light and dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fields = <Map<String, dynamic>>[
      {'name': 'firstname', 'label_th': 'ชื่อ', 'uitype': 'Text', 'required': true, 'sequence': 1},
      {'name': 'email', 'label_th': 'อีเมล', 'uitype': 'Email', 'sequence': 2},
    ];

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await pumpLeadForm(tester, mode: mode, fields: fields, title: 'สร้างลีด');
      await tester.pump();
      expect(find.text('สร้างลีด'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('entity-save')));
      await tester.tap(find.byKey(const ValueKey('entity-save')));
      await tester.pump();
      expect(find.text('จำเป็นต้องกรอก'), findsWidgets);
      expect(find.text('ช่องจำเป็น 0/1'), findsOneWidget);
      // Scroll to the field, then it shakes (offset ≠ 0 mid-animation).
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 60));
      final shaking = tester.widgetList<Transform>(
        find.descendant(of: find.byType(NxShake), matching: find.byType(Transform)),
      );
      expect(shaking.any((t) => t.transform.getTranslation().x.abs() > 0.5), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('edit lead preview in light and dark', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fields = <Map<String, dynamic>>[
      {'name': 'firstname', 'label_th': 'ชื่อ', 'uitype': 'Text', 'required': true, 'sequence': 1},
      {'name': 'email', 'label_th': 'อีเมล', 'uitype': 'Email', 'sequence': 2},
    ];

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await pumpLeadForm(
        tester,
        mode: mode,
        fields: fields,
        title: 'แก้ไข',
        recordId: '1',
        initialValues: const {'firstname': 'สมชาย', 'email': 'a@b.com'},
      );
      await tester.pump();
      expect(find.text('แก้ไข'), findsOneWidget);
      expect(find.text('บันทึก'), findsOneWidget);
      final texts = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller?.text ?? '')
          .toList();
      expect(texts, contains('สมชาย'));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
