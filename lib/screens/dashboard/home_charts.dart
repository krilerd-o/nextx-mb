import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/home_layout.dart';
import '../../core/i18n.dart';
import '../../core/nx_number.dart';
import '../../widgets/nx_icons.dart';
import '../../widgets/nx_skeleton.dart';
import 'home_boxes.dart' show HomeCardShadow, homeCardFill, kHomeCardRadius;
import 'home_chart_data.dart';
import 'home_widgets.dart';

// ─────────────────────────── tokens ───────────────────────────

/// Categorical series colours (fixed order, never cycled) — light and dark steps.
const _seriesLight = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100), Color(0xFFE87BA4), Color(0xFF6250D6)];
const _seriesDark = [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500), Color(0xFFD55181), Color(0xFF9085E9)];

List<Color> chartSeries(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _seriesDark : _seriesLight;

/// Status colours (good / critical) — reserved, always shipped with a label.
Color chartGood(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF34C77B) : const Color(0xFF0F9D58);
Color chartBad(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFF07171) : const Color(0xFFD93B3B);

/// 1,250,000 → "1.25M"; 35,400 → "35.4K"; 920 → "920".
String chartCompact(double v, {bool baht = false}) {
  final a = v.abs();
  String s;
  if (a >= 1e9) {
    s = '${_trim(v / 1e9)}B';
  } else if (a >= 1e6) {
    s = '${_trim(v / 1e6)}M';
  } else if (a >= 1e4) {
    s = '${_trim(v / 1e3)}K';
  } else {
    s = nxInt(v);
  }
  return baht ? '฿$s' : s;
}

String _trim(double v) {
  final s = v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(v.abs() >= 10 ? 1 : 2);
  return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
}

String _pct(double? r) => r == null ? '—' : '${(r * 100).round()}%';

/// Fixed card heights so half cards in one row line up.
const double kHalfChartHeight = 196;
const double kFullChartHeight = 252;

// ─────────────────────────── card ───────────────────────────

/// Last parsed data per chart + period + scope → instant paint on return.
final Map<String, Object> _lastData = {};

/// Test / debug: forget painted data.
void resetHomeChartMemory() => _lastData.clear();

/// One chart widget on Home: header, period · scope pill, chart, states.
class HomeChartCard extends StatefulWidget {
  const HomeChartCard({super.key, required this.entry, this.revision = 0, this.editing = false, this.onEntryChanged, this.sample});

  final HomeEntry entry;

  /// Bumps on pull-to-refresh → reload without cache.
  final int revision;
  final bool editing;
  final ValueChanged<HomeEntry>? onEntryChanged;

  /// Preview data (gallery) — no requests.
  final Object? sample;

  @override
  State<HomeChartCard> createState() => _HomeChartCardState();
}

class _HomeChartCardState extends State<HomeChartCard> {
  Object? _data;
  Object? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.sample != null) {
      _data = widget.sample;
    } else {
      _load(force: false);
    }
  }

  @override
  void didUpdateWidget(HomeChartCard old) {
    super.didUpdateWidget(old);
    if (widget.sample != null) {
      _data = widget.sample;
      return;
    }
    if (old.revision != widget.revision) {
      _load(force: true);
    } else if (old.entry.period != widget.entry.period || old.entry.team != widget.entry.team) {
      _load(force: false);
    }
  }

  ChartRequest _request() {
    final config = context.read<AppConfig>();
    return ChartRequest(api: config.apiClient, session: config.session, entry: widget.entry, scope: config.businessScope, now: chartNow());
  }

  Future<void> _load({required bool force}) async {
    final r = _request();
    final key = chartCacheKey(r);
    final seq = ++_seq;
    setState(() {
      _data = _lastData[key];
      _error = null;
    });
    try {
      final d = await loadChartData(r, force: force);
      _lastData[key] = d;
      if (mounted && seq == _seq) setState(() => _data = d);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = HomeWidgetInfo.of(widget.entry.id);
    final half = widget.entry.size == HomeSize.half;
    final body = _error != null && _data == null
        ? _ErrorState(onRetry: () => _load(force: true))
        : _data == null
        ? const Padding(padding: EdgeInsets.only(top: 6), child: NxSkeletonBox(rows: 2))
        : ChartBody(id: widget.entry.id, data: _data!, half: half);
    return HomeCardShadow(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('home-chart-${widget.entry.id}'),
          borderRadius: BorderRadius.circular(kHomeCardRadius),
          onTap: widget.editing || widget.sample != null || info.route == null ? null : () => context.push(info.route!),
          child: Ink(
            height: half ? kHalfChartHeight : kFullChartHeight,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: homeCardFill(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: info.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                      child: Icon(info.icon, size: 15, color: info.color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(info.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _PeriodPill(entry: widget.entry, enabled: !widget.editing && widget.sample == null, onChanged: widget.onEntryChanged),
                const SizedBox(height: 8),
                // Fixed card height: cap the text size inside the chart.
                Expanded(child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15, child: body)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "เดือนนี้ · ของฉัน ▾" → menu of periods and (for managers) ของฉัน | ทีม.
class _PeriodPill extends StatelessWidget {
  const _PeriodPill({required this.entry, required this.enabled, this.onChanged});
  final HomeEntry entry;
  final bool enabled;
  final ValueChanged<HomeEntry>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = HomeLayout.chartMeta(entry.id)!;
    final session = context.select((AppConfig c) => c.session);
    final team = meta.teamable && canSeeTeam(session);
    final period = entry.period ?? meta.defaultPeriod;
    final parts = [
      if (meta.periods.isNotEmpty) tr(kChartPeriodLabels[period] ?? period),
      if (meta.id == 'chart_leave') tr('ปีนี้'),
      if (meta.id == 'chart_closing') tr('ดีลที่เปิดอยู่'),
      if (team) tr(entry.team ? 'ทีม' : 'ของฉัน') else if (meta.teamable) tr('ของฉัน'),
    ];
    final canOpen = enabled && onChanged != null && (meta.periods.length > 1 || team);
    final label = Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
    );
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: label),
          if (canOpen) ...[const SizedBox(width: 2), Icon(NxI.caretDown, size: 12, color: cs.onSurfaceVariant)],
        ],
      ),
    );
    if (!canOpen) return Align(alignment: Alignment.centerLeft, child: pill);
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        key: ValueKey('chart-pill-${entry.id}'),
        tooltip: tr('ช่วงเวลา'),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (v) {
          HapticFeedback.selectionClick();
          if (v == 'scope:me') {
            onChanged!(entry.copyWith(team: false));
          } else if (v == 'scope:team') {
            onChanged!(entry.copyWith(team: true));
          } else {
            onChanged!(entry.copyWith(period: v));
          }
        },
        itemBuilder: (_) => [
          for (final p in meta.periods) CheckedPopupMenuItem(value: p, checked: p == period, child: Text(tr(kChartPeriodLabels[p] ?? p))),
          if (team) ...[
            const PopupMenuDivider(),
            CheckedPopupMenuItem(key: const ValueKey('chart-scope-me'), value: 'scope:me', checked: !entry.team, child: Text(tr('ของฉัน'))),
            CheckedPopupMenuItem(key: const ValueKey('chart-scope-team'), value: 'scope:team', checked: entry.team, child: Text(tr('ทีม'))),
          ],
        ],
        child: pill,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('โหลดไม่สำเร็จ'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          TextButton.icon(onPressed: onRetry, icon: const Icon(NxI.arrowClockwise, size: 16), label: Text(tr('ลองใหม่'))),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(NxI.chartBar, size: 26, color: cs.onSurfaceVariant.withValues(alpha: 0.45)),
          const SizedBox(height: 6),
          Text(
            tr(text),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Appear animation: 0 → 1 once per data (bars grow, lines draw, rings fill).
class _Appear extends StatelessWidget {
  const _Appear({required this.data, required this.builder});
  final Object data;
  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return builder(1);
    return TweenAnimationBuilder<double>(
      key: ValueKey(identityHashCode(data)),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => builder(t),
    );
  }
}

// ─────────────────────────── bodies ───────────────────────────

/// Draws [data] for chart [id] (also used for gallery previews).
class ChartBody extends StatelessWidget {
  const ChartBody({super.key, required this.id, required this.data, this.half = false});
  final String id;
  final Object data;
  final bool half;

  @override
  Widget build(BuildContext context) {
    final d = data;
    switch (id) {
      case 'chart_won':
        return _WonBody(d as WonData, half: half);
      case 'chart_winrate':
      case 'chart_case_sla':
        return _RingBody(d as RateData, half: half, semi: false, empty: id == 'chart_winrate' ? 'ยังไม่มีดีลที่ปิดในช่วงนี้' : 'ยังไม่มีเคสที่ปิดในช่วงนี้');
      case 'chart_lead_conv':
        return _RingBody(d as RateData, half: half, semi: true, empty: 'ยังไม่มี Lead ในช่วงนี้');
      case 'chart_sales_trend':
        return ColumnsChart(d as SeriesData, baht: true, empty: 'ยังไม่มียอดปิดการขาย');
      case 'chart_work':
        return _LineBody(d as SeriesData, empty: 'ยังไม่มีงานในช่วงนี้');
      case 'chart_activity':
        if (d is SeriesData) return _StackBody(d, empty: 'ยังไม่มีกิจกรรมในช่วงนี้');
        return _BarsBody((d as SlicesData).slices, empty: 'ยังไม่มีกิจกรรมในช่วงนี้');
      case 'chart_pipeline':
        return _BarsBody((d as SlicesData).slices, showAmount: true, empty: 'ยังไม่มีดีลในช่วงนี้');
      case 'chart_closing':
        return _BarsBody((d as SlicesData).slices, showAmount: true, firstIsBad: true, keepZeros: true, empty: 'ไม่มีดีลที่เปิดอยู่');
      case 'chart_quote':
        return _DonutBody(d as SlicesData, half: half, empty: 'ยังไม่มีใบเสนอราคาในช่วงนี้');
      case 'chart_lead_source':
        return _DonutBody(d as SlicesData, half: half, empty: 'ยังไม่มี Lead ในช่วงนี้');
      case 'chart_case_status':
        return _DonutBody(d as SlicesData, half: half, empty: 'ยังไม่มีเคสในช่วงนี้');
      case 'chart_leave':
        return _LeaveBody(d as List<LeaveRow>, half: half);
    }
    return const SizedBox.shrink();
  }
}

class _WonBody extends StatelessWidget {
  const _WonBody(this.d, {required this.half});
  final WonData d;
  final bool half;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final delta = d.deltaPct;
    final up = (delta ?? 0) >= 0;
    final spark = d.trend.length >= 2 && d.trend.any((v) => v > 0) ? d.trend : null;
    return _Appear(
      data: d,
      builder: (t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              chartCompact(d.amount * t, baht: true),
              key: const ValueKey('won-amount'),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (delta != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (up ? chartGood(context) : chartBad(context)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scaleY: up ? 1 : -1,
                        child: Icon(NxI.trendUp, size: 13, color: up ? chartGood(context) : chartBad(context)),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${up ? '+' : '−'}${delta.abs().round()}%',
                        key: const ValueKey('won-delta'),
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: up ? chartGood(context) : chartBad(context)),
                      ),
                    ],
                  ),
                ),
              Text(tr('${nxInt(d.count)} ดีล'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              if (delta != null && !half) Text(tr('เทียบช่วงก่อน'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
          const Spacer(),
          if (spark != null)
            SizedBox(
              height: half ? 38 : 64,
              child: _Sparkline(values: spark, t: t, color: chartSeries(context)[2]),
            )
          else if (d.amount == 0)
            Text(tr('ยังไม่มีดีลที่ปิดได้ในช่วงนี้'), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.t, required this.color});
  final List<double> values;
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxY = values.fold<double>(0, math.max);
    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i] * t)],
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingBody extends StatelessWidget {
  const _RingBody(this.d, {required this.half, required this.semi, required this.empty});
  final RateData d;
  final bool half;
  final bool semi;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (d.rate == null) return _Empty(empty);
    final color = chartSeries(context)[semi ? 2 : 0];
    Widget legend(Color c, String label, double v) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${tr(label)} ${nxInt(v)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
    return _Appear(
      data: d,
      builder: (t) {
        final ring = LayoutBuilder(
          builder: (context, c) {
            final side = math.min(c.maxWidth, semi ? c.maxHeight * 2 : c.maxHeight);
            return Center(
              child: SizedBox(
                width: side,
                height: semi ? side / 2 + 8 : side,
                child: CustomPaint(
                  painter: _RingPainter(value: (d.rate! * t).clamp(0, 1), color: color, track: cs.surfaceContainerHighest, semi: semi),
                  child: Align(
                    alignment: semi ? const Alignment(0, 0.9) : Alignment.center,
                    child: Text(
                      _pct(d.rate! * t),
                      key: ValueKey('rate-${d.aLabel}'),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: half ? 18 : 22),
                    ),
                  ),
                ),
              ),
            );
          },
        );
        final legends = [legend(color, d.aLabel, d.a), legend(cs.outlineVariant, d.bLabel, d.b)];
        if (half) {
          return Column(
            children: [
              Expanded(child: ring),
              const SizedBox(height: 6),
              Wrap(spacing: 10, runSpacing: 2, alignment: WrapAlignment.center, children: legends),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: ring),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final l in legends) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: l)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track, required this.semi});
  final double value;
  final Color color;
  final Color track;
  final bool semi;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(8.0, size.width * 0.1);
    final r = size.width / 2 - stroke / 2;
    final center = semi ? Offset(size.width / 2, size.width / 2) : Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    final start = semi ? math.pi : -math.pi / 2;
    final sweep = semi ? math.pi : 2 * math.pi;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, p..color = track);
    if (value > 0) canvas.drawArc(rect, start, sweep * value, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

class _LineBody extends StatelessWidget {
  const _LineBody(this.d, {required this.empty});
  final SeriesData d;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (d.labels.isEmpty || d.isEmpty) return _Empty(empty);
    final cs = Theme.of(context).colorScheme;
    final colors = chartSeries(context);
    final names = d.series.keys.toList();
    final maxY = d.series.values.expand((e) => e).fold<double>(0, math.max);
    final step = (d.labels.length / 6).ceil().clamp(1, 99);
    return Column(
      children: [
        if (names.length > 1) _Legend(names: names, colors: colors),
        if (names.length > 1) const SizedBox(height: 6),
        Expanded(
          child: _Appear(
            data: d,
            builder: (t) => LineChart(
              duration: Duration.zero,
              LineChartData(
                minY: 0,
                maxY: maxY <= 0 ? 1 : maxY * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.35), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, meta) =>
                          v == meta.max ? const SizedBox.shrink() : Text(chartCompact(v), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i < 0 || i >= d.labels.length || i % step != 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(tr(d.labels[i]), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${s.barIndex == 0 ? '${tr(d.labels[s.x.round()])}\n' : ''}${tr(names[s.barIndex])} ${nxInt(d.series[names[s.barIndex]]![s.x.round()])}',
                          TextStyle(color: cs.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  for (var si = 0; si < names.length; si++)
                    LineChartBarData(
                      spots: [for (var i = 0; i < d.labels.length; i++) FlSpot(i.toDouble(), d.series[names[si]]![i] * t)],
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: colors[si % colors.length],
                      barWidth: 2,
                      dotData: FlDotData(
                        show: d.labels.length <= 8,
                        getDotPainter: (_, _, _, _) =>
                            FlDotCirclePainter(radius: 3, color: colors[si % colors.length], strokeWidth: 2, strokeColor: cs.surface),
                      ),
                      belowBarData: BarAreaData(
                        show: names.length == 1,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colors[si % colors.length].withValues(alpha: 0.25), colors[si % colors.length].withValues(alpha: 0)],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.names, required this.colors});
  final List<String> names;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        for (var i = 0; i < names.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 3,
                decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Text(tr(names[i]), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ],
          ),
      ],
    );
  }
}

class _StackBody extends StatelessWidget {
  const _StackBody(this.d, {required this.empty});
  final SeriesData d;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (d.labels.isEmpty || d.isEmpty) return _Empty(empty);
    final cs = Theme.of(context).colorScheme;
    final names = d.series.keys.toList();
    final colors = [chartGood(context), chartBad(context), chartSeries(context)[0]];
    final totals = [for (var i = 0; i < d.labels.length; i++) names.fold<double>(0, (a, n) => a + d.series[n]![i])];
    final maxY = totals.fold<double>(0, math.max);
    final step = (d.labels.length / 7).ceil().clamp(1, 99);
    final barW = d.labels.length > 20
        ? 5.0
        : d.labels.length > 10
        ? 8.0
        : 14.0;
    return Column(
      children: [
        _Legend(names: names, colors: colors),
        const SizedBox(height: 6),
        Expanded(
          child: _Appear(
            data: d,
            builder: (t) => BarChart(
              duration: Duration.zero,
              BarChartData(
                maxY: maxY <= 0 ? 1 : maxY * 1.15,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.35), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, meta) => v == meta.max || v != v.roundToDouble()
                          ? const SizedBox.shrink()
                          : Text(nxInt(v), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i < 0 || i >= d.labels.length || i % step != 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(d.labels[i], style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => cs.inverseSurface,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                      '${d.labels[g.x]}\n${[for (final n in names) '${tr(n)} ${nxInt(d.series[n]![g.x])}'].join('\n')}',
                      TextStyle(color: cs.onInverseSurface, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < d.labels.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: totals[i] * t,
                          width: barW,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(barW / 2)),
                          color: Colors.transparent,
                          rodStackItems: () {
                            var acc = 0.0;
                            return [
                              for (var n = 0; n < names.length; n++)
                                () {
                                  final v = d.series[names[n]]![i] * t;
                                  final item = BarChartRodStackItem(
                                    acc,
                                    acc + v,
                                    colors[n],
                                    borderSide: BorderSide(color: cs.surface, width: v > 0 ? 1 : 0),
                                  );
                                  acc += v;
                                  return item;
                                }(),
                            ];
                          }(),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Horizontal bars (pipeline stages, close window, activity statuses).
class _BarsBody extends StatelessWidget {
  const _BarsBody(this.rows, {this.showAmount = false, this.firstIsBad = false, this.keepZeros = false, required this.empty});
  final List<ChartSlice> rows;
  final bool showAmount;
  final bool firstIsBad;
  final bool keepZeros;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final list = keepZeros ? rows : rows.where((r) => r.value > 0).toList();
    if (list.every((r) => r.value <= 0)) return _Empty(empty);
    final cs = Theme.of(context).colorScheme;
    final base = chartSeries(context)[showAmount && !firstIsBad ? 5 : 0];
    final maxV = list.fold<double>(0, (a, r) => math.max(a, r.value));
    final shown = list.take(6).toList();
    return _Appear(
      data: rows,
      builder: (t) => Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < shown.length; i++)
            Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    tr(shown[i].label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: Tooltip(
                    message: '${tr(shown[i].label)}: ${nxInt(shown[i].value)}${showAmount ? ' · ${nxBaht(shown[i].amount)}' : ''}',
                    child: LayoutBuilder(
                      builder: (_, c) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 14,
                          width: math.max(shown[i].value > 0 ? 4.0 : 0.0, c.maxWidth * (maxV <= 0 ? 0 : shown[i].value / maxV) * t),
                          decoration: BoxDecoration(
                            color: firstIsBad && i == 0 ? chartBad(context) : base.withValues(alpha: 1 - i * 0.1),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: showAmount ? 76 : 34,
                  child: Text(
                    showAmount ? '${nxInt(shown[i].value)} · ${chartCompact(shown[i].amount, baht: true)}' : nxInt(shown[i].value),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DonutBody extends StatefulWidget {
  const _DonutBody(this.d, {required this.half, required this.empty});
  final SlicesData d;
  final bool half;
  final String empty;

  @override
  State<_DonutBody> createState() => _DonutBodyState();
}

class _DonutBodyState extends State<_DonutBody> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    if (d.isEmpty) return _Empty(widget.empty);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = chartSeries(context);
    final sel = _touched != null && _touched! < d.slices.length ? d.slices[_touched!] : null;
    final donut = LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: _Appear(
              data: d,
              builder: (t) => Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    duration: Duration.zero,
                    PieChartData(
                      startDegreeOffset: -90,
                      centerSpaceRadius: side * 0.3,
                      sectionsSpace: 2,
                      pieTouchData: PieTouchData(
                        touchCallback: (e, r) {
                          if (!e.isInterestedForInteractions) return;
                          final i = r?.touchedSection?.touchedSectionIndex;
                          if (i != null && i >= 0 && i != _touched) setState(() => _touched = i);
                        },
                      ),
                      sections: [
                        for (var i = 0; i < d.slices.length; i++)
                          PieChartSectionData(
                            value: d.slices[i].value,
                            color: colors[i % colors.length],
                            radius: side * (i == _touched ? 0.2 : 0.17),
                            showTitle: false,
                          ),
                        if (t < 1) PieChartSectionData(value: d.total * (1 - t) / math.max(t, 0.001), color: Colors.transparent, radius: 1, showTitle: false),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nxInt(sel?.value ?? d.total),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: widget.half ? 15 : 18),
                      ),
                      if (!widget.half || sel != null)
                        SizedBox(
                          width: side * 0.5,
                          child: Text(
                            sel == null ? tr('ทั้งหมด') : tr(sel.label),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    Widget legendRow(int i) => InkWell(
      onTap: () => setState(() => _touched = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr(d.slices[i].label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
            Text(
              nxInt(d.slices[i].value),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
    if (widget.half) {
      return Row(
        children: [
          Expanded(flex: 5, child: donut),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < math.min(3, d.slices.length); i++) legendRow(i),
                if (d.slices.length > 3) Text(tr('+${d.slices.length - 3} อื่นๆ'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 4, child: donut),
        const SizedBox(width: 14),
        Expanded(
          flex: 5,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < d.slices.length; i++) legendRow(i)]),
        ),
      ],
    );
  }
}

class _LeaveBody extends StatelessWidget {
  const _LeaveBody(this.rows, {required this.half});
  final List<LeaveRow> rows;
  final bool half;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _Empty('ยังไม่มีสิทธิ์ลาในปีนี้');
    final cs = Theme.of(context).colorScheme;
    final shown = rows.take(half ? 3 : 5).toList();
    final color = chartSeries(context)[5];
    return _Appear(
      data: rows,
      builder: (t) => Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final r in shown)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(r.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('เหลือ ${_days(r.left)}/${_days(r.total)}'),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (r.total <= 0 ? 0 : r.left / r.total) * t,
                    minHeight: 6,
                    color: color,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _days(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

// ─────────────────────────── gallery samples ───────────────────────────

/// Fake data for gallery previews (no requests).
Object sampleChartData(String id) {
  const months = ['มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.'];
  switch (id) {
    case 'chart_won':
      return const WonData(amount: 1250000, prevAmount: 1040000, count: 8, trend: [2, 4, 3, 6, 5, 8]);
    case 'chart_winrate':
      return const RateData(rate: 0.62, a: 13, b: 8, aLabel: 'ปิดได้', bLabel: 'ไม่สำเร็จ');
    case 'chart_case_sla':
      return const RateData(rate: 0.91, a: 41, b: 4, aLabel: 'ทันเวลา', bLabel: 'เกินเวลา');
    case 'chart_lead_conv':
      return const RateData(rate: 0.34, a: 17, b: 50, aLabel: 'แปลงแล้ว', bLabel: 'Lead ใหม่');
    case 'chart_sales_trend':
      return const SeriesData(
        labels: months,
        series: {
          'ยอดปิดการขาย': [420000, 610000, 380000, 890000, 760000, 1250000],
        },
      );
    case 'chart_work':
      return const SeriesData(
        labels: ['5/10', '12/10', '19/10', '26/10', '2/11', '9/11'],
        series: {
          'สร้าง': [6, 9, 7, 11, 8, 10],
          'เคลียร์': [4, 7, 8, 9, 10, 9],
        },
      );
    case 'chart_activity':
      return const SeriesData(
        labels: ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'],
        series: {
          'เสร็จ': [3, 4, 2, 5, 4, 1, 0],
          'พลาด': [1, 0, 1, 0, 1, 0, 0],
          'กำลังมา': [0, 0, 0, 1, 2, 1, 0],
        },
      );
    case 'chart_pipeline':
      return const SlicesData([
        ChartSlice('Qualification', 14, amount: 2800000),
        ChartSlice('Value Proposition', 9, amount: 2100000),
        ChartSlice('Proposal Sent', 6, amount: 1650000),
        ChartSlice('Negotiation', 3, amount: 900000),
      ]);
    case 'chart_closing':
      return const SlicesData([
        ChartSlice('เลยกำหนด', 2, amount: 350000),
        ChartSlice('≤ 7 วัน', 4, amount: 820000),
        ChartSlice('8–30 วัน', 7, amount: 1400000),
        ChartSlice('31–90 วัน', 5, amount: 980000),
        ChartSlice('> 90 วัน', 3, amount: 450000),
      ]);
    case 'chart_quote':
      return const SlicesData([ChartSlice('Sent', 12), ChartSlice('Accepted', 7), ChartSlice('Draft', 4), ChartSlice('Rejected', 2)]);
    case 'chart_lead_source':
      return const SlicesData([ChartSlice('Website', 18), ChartSlice('Facebook', 11), ChartSlice('LINE', 8), ChartSlice('งานแสดงสินค้า', 5)]);
    case 'chart_case_status':
      return const SlicesData([ChartSlice('เปิดเคส', 6), ChartSlice('กำลังดำเนินการ', 9), ChartSlice('รอปิด', 3), ChartSlice('ปิดแล้ว', 21)]);
    case 'chart_leave':
      return const [LeaveRow('ลาป่วย', 30, 4), LeaveRow('ลากิจ', 3, 1), LeaveRow('ลาพักร้อน', 6, 2)];
  }
  return const SlicesData([]);
}

/// Index a column chart selects first: the latest column with a value
/// (else the last one); -1 when there are no columns.
int defaultColumnIndex(List<double> values) {
  for (var i = values.length - 1; i >= 0; i--) {
    if (values[i] > 0) return i;
  }
  return values.length - 1;
}

/// Modern single-series column chart: rounded pill columns on a soft track;
/// the selected column is filled with a gradient and carries a floating value
/// label. Tap a column to select it. Respects reduced motion (via [_Appear]).
class ColumnsChart extends StatefulWidget {
  const ColumnsChart(this.d, {super.key, this.baht = false, required this.empty});
  final SeriesData d;
  final bool baht;
  final String empty;

  @override
  State<ColumnsChart> createState() => _ColumnsChartState();
}

class _ColumnsChartState extends State<ColumnsChart> {
  int? _selected;

  @override
  void didUpdateWidget(ColumnsChart old) {
    super.didUpdateWidget(old);
    if (old.d != widget.d) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    if (d.labels.isEmpty || d.isEmpty) return _Empty(widget.empty);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final values = d.series.values.first;
    final n = math.min(values.length, d.labels.length);
    final maxV = values.take(n).fold<double>(0, math.max);
    final sel = (_selected ?? defaultColumnIndex(values.take(n).toList())).clamp(0, n - 1);
    final base = chartSeries(context)[0];
    final dark = theme.brightness == Brightness.dark;
    final top = Color.lerp(base, Colors.white, dark ? 0.25 : 0.35)!;
    final step = (n / 7).ceil().clamp(1, 99);
    String fmt(double v) => widget.baht ? chartCompact(v, baht: true) : chartCompact(v);
    return _Appear(
      data: d,
      builder: (t) => LayoutBuilder(
        builder: (context, c) {
          const labelH = 18.0;
          const tipH = 26.0;
          final gap = n > 8 ? 6.0 : 10.0;
          final colW = ((c.maxWidth - gap * (n - 1)) / n).clamp(4.0, 34.0);
          final barArea = math.max(0.0, c.maxHeight - labelH - tipH);
          final usedW = colW * n + gap * (n - 1);
          final left = (c.maxWidth - usedW) / 2;
          final selH = maxV <= 0 ? 0.0 : barArea * values[sel] / maxV * t;
          final tipCenter = left + sel * (colW + gap) + colW / 2;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                top: tipH,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      Semantics(
                        button: true,
                        selected: i == sel,
                        label: '${tr(d.labels[i])} ${widget.baht ? nxBaht(values[i]) : nxInt(values[i])}',
                        child: GestureDetector(
                          key: ValueKey('col-$i'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = i);
                          },
                          child: SizedBox(
                            width: colW,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                SizedBox(
                                  height: barArea,
                                  child: Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      // Track: the full height, very light.
                                      Container(
                                        decoration: BoxDecoration(
                                          color: cs.onSurface.withValues(alpha: dark ? 0.06 : 0.045),
                                          borderRadius: BorderRadius.circular(colW / 2),
                                        ),
                                      ),
                                      Container(
                                        height: maxV <= 0 ? 0 : math.max(values[i] > 0 ? colW * 0.6 : 0, barArea * values[i] / maxV * t),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(colW / 2),
                                          color: i == sel ? null : base.withValues(alpha: dark ? 0.32 : 0.22),
                                          gradient: i == sel
                                              ? LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, base])
                                              : null,
                                          boxShadow: i == sel
                                              ? [BoxShadow(color: base.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))]
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: labelH,
                                  child: (i % step == 0 || i == sel)
                                      ? Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            tr(d.labels[i]),
                                            maxLines: 1,
                                            overflow: TextOverflow.visible,
                                            softWrap: false,
                                            textScaler: TextScaler.noScaling,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: i == sel ? FontWeight.w700 : FontWeight.w500,
                                              color: i == sel ? cs.onSurface : cs.onSurfaceVariant,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Floating value label above the selected column.
              Positioned(
                left: 0,
                right: 0,
                top: math.max(0.0, tipH + barArea - selH - tipH - 4),
                height: tipH,
                child: CustomSingleChildLayout(
                  delegate: _TipLayout(centerX: tipCenter),
                  child: Container(
                    key: const ValueKey('col-tip'),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.inverseSurface,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: Text(
                      fmt(values[sel]),
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(color: cs.onInverseSurface, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Centres the tooltip on [centerX], kept inside the chart.
class _TipLayout extends SingleChildLayoutDelegate {
  _TipLayout({required this.centerX});
  final double centerX;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (centerX - child.width / 2).clamp(0.0, math.max(0.0, size.width - child.width)).toDouble();
    return Offset(x, (size.height - child.height) / 2);
  }

  @override
  bool shouldRelayout(_TipLayout old) => old.centerX != centerX;
}
