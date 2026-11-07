import 'package:flutter/material.dart';
import '../../widgets/nx_scroll_scaffold.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/app_theme.dart';
import '../../core/nx_breakpoint.dart';
import '../../widgets/fields/field_ui_type.dart';
import '../../widgets/fields/nx_form_field.dart';
import '../../widgets/fields/nx_pick_option.dart';
import '../../widgets/nx_app_header.dart';
import '../../widgets/nx_icons.dart';

/// Debug gallery of every CRM UI type (light/dark toggle).
class FieldGalleryScreen extends StatefulWidget {
  const FieldGalleryScreen({super.key});

  @override
  State<FieldGalleryScreen> createState() => _FieldGalleryScreenState();
}

class _FieldGalleryScreenState extends State<FieldGalleryScreen> {
  var _dark = false;
  final _values = <String, dynamic>{
    'YesNo': '1',
    'Percent': '40',
    'Progress': '65',
    'Color': '#6366F1',
    'EmotionalEmoji': 'happy',
    'Enum': 'new',
    'Picklist': 'new',
    'Currency': '1200',
    'Number': '42',
  };

  static const _options = [
    NxPickOption(value: 'new', label: 'ใหม่', color: Color(0xFF0EA5E9)),
    NxPickOption(value: 'won', label: 'ปิดการขาย', color: Color(0xFF10B981)),
    NxPickOption(value: 'lost', label: 'เสียโอกาส'),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('th', 'TH'),
      supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: NxScrollScaffold(
        header: NxAppHeader(
          title: 'UI Type',
          actions: [
            IconButton(
              tooltip: 'สลับธีม',
              onPressed: () => setState(() => _dark = !_dark),
              icon: Icon(_dark ? NxI.sun : NxI.moon),
            ),
          ],
        ),
        body: NxContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final name in kUitypeOptionValues) ...[
                NxFormField(
                  uiType: fieldUiTypeFromName(name)!,
                  canonicalName: name,
                  label: name,
                  value: _values[name],
                  options: _options,
                  onChanged: (v) => setState(() => _values[name] = v),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
