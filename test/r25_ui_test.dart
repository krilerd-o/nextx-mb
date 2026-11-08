import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nextx_mobile/core/app_theme.dart';
import 'package:nextx_mobile/widgets/nx_scroll_scaffold.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('dark mode: filter chips stand out from cards and sheets', () {
    final t = AppTheme.dark;
    final chip = t.chipTheme.backgroundColor!;
    final sheet = t.bottomSheetTheme.backgroundColor ?? t.cardColor;
    expect(chip, isNot(sheet), reason: 'unselected pill must not melt into the sheet');
    final side = t.chipTheme.side!;
    expect(side.color, isNot(Colors.transparent));
    expect(side.width, greaterThan(0), reason: 'hairline outline makes the pill shape visible');
    expect(_contrast(t.chipTheme.selectedColor!, Colors.white), greaterThan(3), reason: 'selected = solid accent, white text');
  });

  test('full blur ramps in small even steps (no visible bands)', () {
    const b = NxEdgeBlur(fromTop: true);
    for (var i = 1; i < b.steps; i++) {
      expect(b.sigma(i) - b.sigma(i - 1), lessThan(1.5), reason: 'step $i');
      expect(b.bandHeight(i), lessThan(b.bandHeight(i - 1)));
    }
    expect(b.sigma(0), lessThan(1), reason: 'the outermost band is barely blurred');
  });

  test('required fields: the group card is not outlined red, only the field', () {
    // Source check keeps the rule from coming back.
    const src = 'lib/widgets/fields/nx_entity_form.dart';
    final code = File(src).readAsStringSync();
    expect(code.contains('hasError ? cs.error'), isFalse);
  });
}
