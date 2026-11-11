import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/card_layout.dart' show formatMoney;
import '../../core/i18n.dart';
import '../../core/thai_time.dart';
import '../../services/api_client.dart';
import '../../widgets/app_bottom_sheet.dart';
import '../../widgets/nx_icons.dart';
import 'status_followups.dart' show journeyErrorText;

num _n(Object? v) => num.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0;
String _s(Object? v) => '${v ?? ''}'.trim() == 'null' ? '' : '${v ?? ''}'.trim();

String lineDescription(Map<String, dynamic> l) =>
    _s(l['description']).isNotEmpty ? _s(l['description']) : _s(l['product_name'] ?? l['service_name'] ?? l['item_label'] ?? l['name']);
num lineQty(Map<String, dynamic> l) => _n(l['quantity'] ?? l['qty']);
num linePrice(Map<String, dynamic> l) => _n(l['unit_price'] ?? l['price']);
num lineDiscountPct(Map<String, dynamic> l) => _n(l['discount_pct']);

/// Line amount (server value when present, else qty × price − discount).
num lineAmount(Map<String, dynamic> l) {
  final a = l['line_amount'] ?? l['amount'] ?? l['line_total'];
  if (a != null && '$a'.isNotEmpty) return _n(a);
  final gross = lineQty(l) * linePrice(l);
  return gross - gross * lineDiscountPct(l) / 100;
}

// ---------------------------------------------------------------- compare

enum LineChange { same, changed, added, removed }

@immutable
class LineDiff {
  const LineDiff(this.change, {this.a, this.b, this.fields = const []});
  final LineChange change;
  final Map<String, dynamic>? a;
  final Map<String, dynamic>? b;

  /// Changed parts: description / quantity / unit_price / discount_pct / amount.
  final List<String> fields;
}

@immutable
class HeaderDiff {
  const HeaderDiff(this.key, this.label, this.a, this.b, {this.money = false});
  final String key;
  final String label;
  final String a;
  final String b;
  final bool money;
  bool get changed => a != b;
}

String _lineKey(Map<String, dynamic> l) {
  final p = _s(l['product_id']), sv = _s(l['service_id']);
  if (p.isNotEmpty && p != '0') return 'p:$p';
  if (sv.isNotEmpty && sv != '0') return 's:$sv';
  return 'd:${lineDescription(l).toLowerCase()}';
}

/// Matches lines of two versions (same product / service / description) and
/// says what changed — what the web compare modal shows, computed here.
List<LineDiff> diffQuotationLines(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  final rest = List.of(b);
  final out = <LineDiff>[];
  for (final la in a) {
    final i = rest.indexWhere((lb) => _lineKey(lb) == _lineKey(la));
    if (i < 0) {
      out.add(LineDiff(LineChange.removed, a: la));
      continue;
    }
    final lb = rest.removeAt(i);
    final f = <String>[
      if (lineDescription(la) != lineDescription(lb)) 'description',
      if (lineQty(la) != lineQty(lb)) 'quantity',
      if (linePrice(la) != linePrice(lb)) 'unit_price',
      if (lineDiscountPct(la) != lineDiscountPct(lb)) 'discount_pct',
      if (lineAmount(la) != lineAmount(lb)) 'amount',
    ];
    out.add(LineDiff(f.isEmpty ? LineChange.same : LineChange.changed, a: la, b: lb, fields: f));
  }
  for (final lb in rest) {
    out.add(LineDiff(LineChange.added, b: lb));
  }
  return out;
}

List<HeaderDiff> diffQuotationHeaders(Map<String, dynamic> a, Map<String, dynamic> b) {
  String money(Object? v) => v == null || '$v'.isEmpty ? '' : formatMoney(_n(v));
  String date(Object? v) => v == null || '$v'.isEmpty ? '' : formatThaiField(v, 'valid_until', dateOnly: true, year: uiYear);
  return [
    HeaderDiff('quotation_no', 'เลขที่', _s(a['quotation_no']), _s(b['quotation_no'])),
    HeaderDiff('title_th', 'ชื่อเรื่อง', _s(a['title_th'] ?? a['title']), _s(b['title_th'] ?? b['title'])),
    HeaderDiff('valid_until', 'ใช้ได้ถึง', date(a['valid_until']), date(b['valid_until'])),
    HeaderDiff('payment_term', 'เงื่อนไขชำระเงิน', _s(a['payment_term'] ?? a['payment_terms']), _s(b['payment_term'] ?? b['payment_terms'])),
    HeaderDiff('subtotal', 'ยอดก่อนส่วนลด', money(a['subtotal'] ?? a['sub_total']), money(b['subtotal'] ?? b['sub_total']), money: true),
    HeaderDiff('discount_total', 'ส่วนลด', money(a['discount_total']), money(b['discount_total']), money: true),
    HeaderDiff('vat_amount', 'ภาษี', money(a['vat_amount'] ?? a['tax_total']), money(b['vat_amount'] ?? b['tax_total']), money: true),
    HeaderDiff('grand_total', 'ยอดรวมสุทธิ', money(a['grand_total']), money(b['grand_total']), money: true),
  ].where((d) => d.a.isNotEmpty || d.b.isNotEmpty).toList();
}

/// Pick two versions (default: the one before vs this one) and compare.
Future<void> openQuotationCompare(BuildContext context, {required String currentId, required List<Map<String, dynamic>> revisions}) async {
  final versions = revisions.where((r) => _s(r['id']).isNotEmpty).toList();
  if (versions.length < 2) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('ยังมีฉบับเดียว — ไม่มีฉบับให้เทียบ'))));
    return;
  }
  final cur = versions.indexWhere((r) => _s(r['id']) == currentId);
  final b = cur >= 0 ? versions[cur] : versions.last;
  final a = cur > 0 ? versions[cur - 1] : versions.firstWhere((r) => r != b);
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => QuotationCompareScreen(versions: versions, aId: _s(a['id']), bId: _s(b['id'])),
  ));
}

class QuotationCompareScreen extends StatefulWidget {
  const QuotationCompareScreen({super.key, required this.versions, required this.aId, required this.bId});
  final List<Map<String, dynamic>> versions;
  final String aId;
  final String bId;

  @override
  State<QuotationCompareScreen> createState() => _QuotationCompareScreenState();
}

class _QuotationCompareScreenState extends State<QuotationCompareScreen> {
  late String _a = widget.aId, _b = widget.bId;
  Future<Map<String, dynamic>>? _future;
  bool _onlyChanges = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = context.read<AppConfig>().apiClient.compareQuotations(_a, _b);

  String _label(String id) {
    final r = widget.versions.where((v) => _s(v['id']) == id).firstOrNull;
    return r == null ? '#$id' : _s(r['quotation_no']).isEmpty ? '#$id' : _s(r['quotation_no']);
  }

  Widget _picker(String value, ValueChanged<String> onPick, Key key) => DropdownButton<String>(
        key: key,
        value: value,
        isExpanded: true,
        icon: const Icon(NxI.caretDown, size: 18),
        underline: const SizedBox(),
        items: [for (final v in widget.versions) DropdownMenuItem(value: _s(v['id']), child: Text(_label(_s(v['id'])), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            onPick(v);
            _load();
          });
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('เทียบฉบับใบเสนอราคา'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              Expanded(child: _picker(_a, (v) => _a = v, const ValueKey('cmp-a'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(NxI.arrowRight, size: 18)),
              Expanded(child: _picker(_b, (v) => _b = v, const ValueKey('cmp-b'))),
            ]),
          ),
          SwitchListTile(
            key: const ValueKey('cmp-only'),
            dense: true,
            title: Text(tr('แสดงเฉพาะจุดที่ต่าง')),
            value: _onlyChanges,
            onChanged: (v) => setState(() => _onlyChanges = v),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(journeyErrorText(snap.error!))));
                final d = snap.data ?? const {};
                final a = (d['a'] is Map ? Map<String, dynamic>.from(d['a'] as Map) : <String, dynamic>{});
                final b = (d['b'] is Map ? Map<String, dynamic>.from(d['b'] as Map) : <String, dynamic>{});
                List<Map<String, dynamic>> lines(Map<String, dynamic> m) => extractMapList(m['lines']);
                Map<String, dynamic> header(Map<String, dynamic> m) => m['header'] is Map ? Map<String, dynamic>.from(m['header'] as Map) : m;
                final heads = diffQuotationHeaders(header(a), header(b)).where((h) => !_onlyChanges || h.changed || h.key == 'grand_total').toList();
                final ls = diffQuotationLines(lines(a), lines(b)).where((l) => !_onlyChanges || l.change != LineChange.same).toList();
                final ga = _n(header(a)['grand_total']), gb = _n(header(b)['grand_total']);
                final delta = gb - ga;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    Container(
                      key: const ValueKey('cmp-total'),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Expanded(child: Text(tr('ยอดรวมเปลี่ยน'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                        Text(
                          delta == 0 ? tr('เท่าเดิม') : '${delta > 0 ? '+' : '−'}${formatMoney(delta.abs())}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: delta == 0 ? cs.onSurfaceVariant : (delta > 0 ? const Color(0xFF16A34A) : cs.error),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('หัวเอกสาร'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    for (final h in heads) _HeaderRow(h),
                    const SizedBox(height: 16),
                    Text(tr('รายการ'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if (ls.isEmpty) Text(tr('รายการเหมือนกันทุกบรรทัด'), style: TextStyle(color: cs.onSurfaceVariant)),
                    for (final l in ls) _LineRow(l),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

const _amber = Color(0xFFF59E0B);
const _green = Color(0xFF16A34A);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow(this.h);
  final HeaderDiff h;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      key: ValueKey('cmp-h-${h.key}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: h.changed ? _amber.withValues(alpha: 0.1) : null,
        border: Border.all(color: h.changed ? _amber.withValues(alpha: 0.5) : cs.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        SizedBox(width: 110, child: Text(tr(h.label), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        Expanded(
          child: h.changed
              ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                  Text(h.a.isEmpty ? '—' : h.a, style: TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)),
                  const Icon(NxI.arrowRight, size: 14),
                  Text(h.b.isEmpty ? '—' : h.b, style: const TextStyle(fontWeight: FontWeight.w800)),
                ])
              : Text(h.b),
        ),
      ]),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow(this.d);
  final LineDiff d;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (color, label) = switch (d.change) {
      LineChange.added => (_green, 'เพิ่ม'),
      LineChange.removed => (cs.error, 'ลบออก'),
      LineChange.changed => (_amber, 'แก้ไข'),
      LineChange.same => (cs.outline, 'เหมือนเดิม'),
    };
    final l = d.b ?? d.a!;
    String v(Map<String, dynamic>? m, String f) => m == null
        ? ''
        : switch (f) {
            'quantity' => '${lineQty(m)}',
            'unit_price' => formatMoney(linePrice(m)),
            'discount_pct' => '${lineDiscountPct(m)}%',
            'amount' => formatMoney(lineAmount(m)),
            _ => lineDescription(m),
          };
    const names = {'quantity': 'จำนวน', 'unit_price': 'ราคา/หน่วย', 'discount_pct': 'ส่วนลด', 'amount': 'จำนวนเงิน', 'description': 'รายละเอียด'};
    return Container(
      key: ValueKey('cmp-line-${d.change.name}-${lineDescription(l)}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        color: color.withValues(alpha: 0.07),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
            child: Text(tr(label), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              lineDescription(l),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: d.change == LineChange.removed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          Text(formatMoney(lineAmount(l)), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        if (d.change == LineChange.changed)
          for (final f in d.fields.where((f) => f != 'description' || true))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                SizedBox(width: 90, child: Text(tr(names[f] ?? f), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                Flexible(child: Text(v(d.a, f), style: TextStyle(decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(NxI.arrowRight, size: 12)),
                Flexible(child: Text(v(d.b, f), style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${tr('จำนวน')} ${lineQty(l)} × ${formatMoney(linePrice(l))}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- revise

/// Edit header + lines first, then create the new revision (-R n) in one go.
/// Returns the server result `{id, quotation_no, revision_no}`.
Future<Map<String, dynamic>?> openQuotationRevise(BuildContext context, Map<String, dynamic> row) {
  return Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => QuotationReviseScreen(row: row),
  ));
}

class QuotationReviseScreen extends StatefulWidget {
  const QuotationReviseScreen({super.key, required this.row});
  final Map<String, dynamic> row;

  @override
  State<QuotationReviseScreen> createState() => _QuotationReviseScreenState();
}

class _EditLine {
  _EditLine(this.src)
      : desc = TextEditingController(text: lineDescription(src)),
        qty = TextEditingController(text: _fmt(lineQty(src))),
        price = TextEditingController(text: _fmt(linePrice(src))),
        disc = TextEditingController(text: lineDiscountPct(src) == 0 ? '' : _fmt(lineDiscountPct(src)));
  final Map<String, dynamic> src;
  final TextEditingController desc, qty, price, disc;

  static String _fmt(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

  num get amount {
    final g = _n(qty.text) * _n(price.text);
    return g - g * _n(disc.text) / 100;
  }

  Map<String, dynamic> toJson(int no) => {
        'line_no': no,
        'line_type': src['line_type'] ?? (src['product_id'] != null ? 'product' : src['service_id'] != null ? 'service' : 'text'),
        if (src['product_id'] != null) 'product_id': src['product_id'],
        if (src['service_id'] != null) 'service_id': src['service_id'],
        'description': desc.text.trim(),
        if (src['unit'] != null) 'unit': src['unit'],
        if (src['tax_pct'] != null) 'tax_pct': src['tax_pct'],
        'quantity': _n(qty.text),
        'unit_price': _n(price.text),
        'discount_type': 'pct',
        'discount_pct': _n(disc.text),
      };

  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
    disc.dispose();
  }
}

class _QuotationReviseScreenState extends State<QuotationReviseScreen> {
  late final _title = TextEditingController(text: _s(widget.row['title_th'] ?? widget.row['title']));
  late final _note = TextEditingController();
  late DateTime? _valid = parseThaiField(widget.row['valid_until'], 'valid_until');
  final List<_EditLine> _lines = [];
  bool _loading = true, _saving = false;
  Object? _error;

  String get _id => _s(widget.row['id']);

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    try {
      final l = await context.read<AppConfig>().apiClient.getQuotationLines(_id);
      if (!mounted) return;
      setState(() {
        _lines.addAll(l.map(_EditLine.new));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  num get _total => _lines.fold<num>(0, (a, l) => a + l.amount);

  Future<void> _save() async {
    if (_lines.isEmpty || _lines.any((l) => l.desc.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('กรอกรายละเอียดทุกรายการก่อนสร้างฉบับแก้ไข'))));
      return;
    }
    setState(() => _saving = true);
    try {
      String two(int n) => n.toString().padLeft(2, '0');
      final r = await context.read<AppConfig>().apiClient.reviseQuotationWith(
        _id,
        fields: {
          'title_th': _title.text.trim(),
          if (_valid != null) 'valid_until': '${_valid!.year}-${two(_valid!.month)}-${two(_valid!.day)}',
        },
        lines: [for (var i = 0; i < _lines.length; i++) _lines[i].toJson(i + 1)],
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(journeyErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final no = _s(widget.row['quotation_no']);
    return Scaffold(
      appBar: AppBar(title: Text(tr('แก้ไขก่อนสร้างฉบับใหม่'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('ยอดรวมใหม่ (ก่อนภาษี)'), style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                Text(formatMoney(_total), key: const ValueKey('revise-total'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ]),
            ),
            FilledButton.icon(
              key: const ValueKey('revise-save'),
              onPressed: _saving || _loading ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.copySimple, size: 18),
              label: Text(tr('สร้างฉบับแก้ไข')),
            ),
          ]),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(journeyErrorText(_error!)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                      child: Text(tr('ฉบับเดิม $no จะถูกเก็บไว้เป็นประวัติ และฉบับใหม่จะต้องขออนุมัติใหม่'), style: theme.textTheme.bodySmall),
                    ),
                    const SizedBox(height: 14),
                    TextField(key: const ValueKey('revise-title'), controller: _title, decoration: InputDecoration(labelText: tr('ชื่อเรื่อง'))),
                    const SizedBox(height: 12),
                    InkWell(
                      key: const ValueKey('revise-valid'),
                      onTap: () async {
                        final now = thaiNow();
                        final d = await showDatePicker(context: context, initialDate: _valid ?? now.add(const Duration(days: 30)), firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3));
                        if (d != null) setState(() => _valid = d);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: tr('ใช้ได้ถึง'), suffixIcon: const Icon(NxI.calendarBlank, size: 18)),
                        child: Text(_valid == null ? '—' : formatThaiField(_valid!.toIso8601String(), 'valid_until', dateOnly: true, year: uiYear)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: Text(tr('รายการ (${_lines.length})'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                      TextButton.icon(
                        key: const ValueKey('revise-add-line'),
                        onPressed: () => setState(() => _lines.add(_EditLine({'line_type': 'text', 'quantity': 1, 'unit_price': 0}))),
                        icon: const Icon(NxI.plus, size: 16),
                        label: Text(tr('เพิ่มรายการ')),
                      ),
                    ]),
                    for (var i = 0; i < _lines.length; i++) _lineCard(i),
                    const SizedBox(height: 12),
                    TextField(key: const ValueKey('revise-note'), controller: _note, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('เหตุผลที่แก้ไข (ไม่บังคับ)'))),
                  ],
                ),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    InputDecoration dec(String label) => InputDecoration(labelText: tr(label), isDense: true);
    return Container(
      key: ValueKey('revise-line-$i'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: l.desc, decoration: dec('รายละเอียด'), onChanged: (_) => setState(() {}))),
          IconButton(
            key: ValueKey('revise-remove-$i'),
            tooltip: tr('ลบรายการ'),
            icon: Icon(NxI.trash, color: cs.error, size: 18),
            onPressed: () => setState(() => _lines.removeAt(i).dispose()),
          ),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            Expanded(child: TextField(key: ValueKey('revise-qty-$i'), controller: l.qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('จำนวน'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(key: ValueKey('revise-price-$i'), controller: l.price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('ราคา/หน่วย'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: l.disc, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: dec('ลด %'), onChanged: (_) => setState(() {}))),
          ]),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Text(formatMoney(l.amount), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- PDF

/// PDF language × colour, like the web download menu.
Future<({String lang, String color, bool share})?> pickQuotationPdfVariant(BuildContext context) {
  var lang = L10n.isEn ? 'en' : 'th';
  var color = 'color';
  return showAppBottomSheet<({String lang, String color, bool share})>(
    context: context,
    title: tr('ใบเสนอราคา PDF'),
    child: StatefulBuilder(builder: (ctx, setS) {
      Widget seg<T>(String label, List<(T, String)> opts, T value, ValueChanged<T> on, String keyPrefix) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(label), style: Theme.of(ctx).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<T>(
                segments: [for (final (v, l) in opts) ButtonSegment(value: v, label: Text(tr(l)), icon: null)],
                selected: {value},
                onSelectionChanged: (s) => on(s.first),
                showSelectedIcon: false,
                key: ValueKey(keyPrefix),
              ),
              const SizedBox(height: 14),
            ],
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('ภาษา', const [('th', 'ไทย'), ('en', 'English')], lang, (v) => setS(() => lang = v), 'pdf-lang'),
          seg('สี', const [('color', 'สี'), ('bw', 'ขาวดำ')], color, (v) => setS(() => color = v), 'pdf-color'),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('pdf-share'),
                onPressed: () => Navigator.pop(ctx, (lang: lang, color: color, share: true)),
                icon: const Icon(NxI.shareNetwork, size: 18),
                label: Text(tr('แชร์')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('pdf-open'),
                onPressed: () => Navigator.pop(ctx, (lang: lang, color: color, share: false)),
                icon: const Icon(NxI.filePdf, size: 18),
                label: Text(tr('เปิด PDF')),
              ),
            ),
          ]),
        ],
      );
    }),
  );
}
