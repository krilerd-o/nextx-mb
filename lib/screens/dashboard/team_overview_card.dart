import 'package:flutter/material.dart';

import '../../widgets/nx_icons.dart';
import '../../widgets/nx_surface_card.dart';

num _num(Object? v) => num.tryParse(v?.toString() ?? '') ?? 0;

/// ฿1.2M / ฿350k / ฿900
String compactBaht(Object? raw) {
  final v = _num(raw).toDouble();
  final a = v.abs();
  String f(double x, String unit) => '฿${x.toStringAsFixed(x >= 10 ? 0 : 1).replaceAll(RegExp(r'\.0$'), '')}$unit';
  if (a >= 1e6) return f(v / 1e6, 'M');
  if (a >= 1e3) return f(v / 1e3, 'k');
  return '฿${v.round()}';
}

/// One figure on the team card.
class TeamFigure {
  const TeamFigure(this.label, this.value, {this.hint});
  final String label;
  final String value;
  final String? hint;
}

/// `GET /api/dashboard/sales` → figures (deal + quotation; each part only
/// when the server says the module is visible to this user).
List<TeamFigure> salesFigures(Map<String, dynamic>? data) {
  if (data == null) return const [];
  final modules = (data['modules'] as List?)?.map((e) => e.toString()).toSet();
  final deal = data['deal'] is Map ? (data['deal'] as Map) : const {};
  final quote = data['quotation'] is Map ? (data['quotation'] as Map) : const {};
  final out = <TeamFigure>[];
  if (modules == null || modules.contains('deal')) {
    out.add(TeamFigure('ดีลเปิดอยู่', '${_num(deal['openCount'])}', hint: compactBaht(deal['openAmount'])));
    out.add(TeamFigure('ปิดได้', compactBaht(deal['wonAmount']), hint: '${_num(deal['wonCount'])} ดีล'));
    final rate = deal['winRate'];
    if (rate != null) {
      final r = _num(rate).toDouble();
      out.add(TeamFigure('อัตราปิดได้', '${(r <= 1 ? r * 100 : r).round()}%'));
    }
    if (_num(deal['atRiskCount']) > 0) out.add(TeamFigure('ดีลเสี่ยง', '${_num(deal['atRiskCount'])}'));
  }
  if (modules == null || modules.contains('quotation')) {
    out.add(TeamFigure('ใบเสนอรอตอบ', '${_num(quote['awaitingCount'])}', hint: compactBaht(quote['totalAmount'])));
  }
  return out;
}

/// `GET /api/dashboard/case` → total + the largest statuses.
List<TeamFigure> caseFigures(Map<String, dynamic>? data) {
  final rows = (data?['byStatus'] as List?)?.whereType<Map>().toList() ?? const [];
  if (rows.isEmpty) return const [];
  final total = rows.fold<num>(0, (s, r) => s + _num(r['value']));
  return [
    TeamFigure('เคสทั้งหมด', '$total'),
    for (final r in rows.take(3)) TeamFigure(r['name']?.toString() ?? '—', '${_num(r['value'])}'),
  ];
}

/// "ยอดขายและเคส (ปีนี้)" — scoped by the server to the people this user can see.
class TeamOverviewCard extends StatelessWidget {
  const TeamOverviewCard({super.key, this.sales, this.cases, this.onOpenSales, this.onOpenCases});

  final Map<String, dynamic>? sales;
  final Map<String, dynamic>? cases;
  final VoidCallback? onOpenSales;
  final VoidCallback? onOpenCases;

  @override
  Widget build(BuildContext context) {
    final s = salesFigures(sales);
    final c = caseFigures(cases);
    if (s.isEmpty && c.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.isNotEmpty) _FigureCard(title: 'ยอดขาย', icon: NxI.handshake, figures: s, onTap: onOpenSales),
        if (s.isNotEmpty && c.isNotEmpty) const SizedBox(height: 12),
        if (c.isNotEmpty) _FigureCard(title: 'เคสบริการ', icon: NxI.headset, figures: c, onTap: onOpenCases),
      ],
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({required this.title, required this.icon, required this.figures, this.onTap});
  final String title;
  final IconData icon;
  final List<TeamFigure> figures;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NxSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            Text('ปีนี้', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            if (onTap != null) Icon(NxI.caretRight, size: 16, color: cs.onSurfaceVariant),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              for (final f in figures)
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 88),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(f.label, style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                      if (f.hint != null) Text(f.hint!, style: theme.textTheme.labelSmall?.copyWith(color: cs.primary)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
