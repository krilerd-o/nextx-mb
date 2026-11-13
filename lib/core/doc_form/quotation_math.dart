/// Quotation line + header totals — a line-for-line port of the NEXTX
/// backend (`services/quotationLineService.js`: `computeLineAmounts`,
/// `aggregateHeaderTotals`), which the web's `quotationPricing.js` mirrors.
/// The server recomputes every amount on save; this keeps what the user sees
/// while typing identical to what gets stored.
library;

/// JS `Number(v) || 0`: empty / non-numeric → 0.
double qNum(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  if (v is bool) return v ? 1 : 0;
  final s = '$v'.trim();
  if (s.isEmpty) return 0;
  final n = double.tryParse(s);
  return n == null || !n.isFinite ? 0 : n;
}

/// `Math.round(n * 100) / 100` (JS rounds .5 up, also for negatives).
double roundMoney(num n) => ((n * 100) + 0.5).floorToDouble() / 100;

/// VAT rate: empty / not a number = 7; 0 is allowed (no VAT).
double resolveTaxRate(Object? v) {
  if (v == null || (v is String && v.trim().isEmpty)) return 7;
  if (v is num) return v.isFinite ? v.toDouble() : 7;
  final n = double.tryParse('$v'.trim());
  return n == null || !n.isFinite ? 7 : n;
}

/// `percent` | `amount`. Old rows without a type but with a % → percent.
String lineDiscountType(Map<String, dynamic> line) {
  final raw = '${line['discount_type'] ?? ''}'.toLowerCase();
  if (raw == '%' || raw == 'percent' || raw == 'pct') return 'percent';
  if (raw == 'amount') return 'amount';
  return qNum(line['discount_pct']) > 0 && !(qNum(line['discount_amount']) > 0) ? 'percent' : 'amount';
}

/// Remarks / headings / sub-totals carry no price.
bool isPricedLine(Map<String, dynamic> line) {
  final t = line['line_type'];
  return t != 'remark' && t != 'head' && t != 'sub';
}

class QuotationLineAmounts {
  const QuotationLineAmounts({required this.qty, required this.gross, required this.lineDiscount, required this.afterDisc});
  final double qty;
  final double gross;
  final double lineDiscount;
  final double afterDisc;
}

/// Baht discounts: `per_unit` = per unit × quantity (default) · `per_line` = whole line.
QuotationLineAmounts computeLineAmounts(Map<String, dynamic> line, {String? discountMode}) {
  if (!isPricedLine(line)) return const QuotationLineAmounts(qty: 0, gross: 0, lineDiscount: 0, afterDisc: 0);
  final qty = qNum(line['quantity']).clamp(0, double.infinity).toDouble();
  final price = qNum(line['unit_price']);
  final gross = qty * price;
  final percent = lineDiscountType(line) == 'percent';
  final discVal = percent ? qNum(line['discount_pct']).clamp(0, 100).toDouble() : qNum(line['discount_amount']).clamp(0, double.infinity).toDouble();
  final raw = percent ? gross * discVal / 100 : (discountMode == 'per_line' ? discVal : discVal * qty);
  // A discount bigger than the line counts as the line (never negative, never eats other lines).
  final lineDiscount = gross < raw ? gross : raw;
  final after = gross - lineDiscount;
  return QuotationLineAmounts(
    qty: qty,
    gross: roundMoney(gross),
    lineDiscount: roundMoney(lineDiscount),
    afterDisc: roundMoney(after < 0 ? 0 : after),
  );
}

/// What the server stores as `line_amount`.
double lineAmount(Map<String, dynamic> line, {String? discountMode}) => computeLineAmounts(line, discountMode: discountMode).afterDisc;

class QuotationTotals {
  const QuotationTotals({
    required this.subtotal,
    required this.discountTotal,
    required this.totalLineDiscount,
    required this.billDiscountAmount,
    required this.taxTotal,
    required this.grandTotal,
    required this.priceBeforeVat,
    required this.afterDiscount,
  });

  final double subtotal;
  final double discountTotal;
  final double totalLineDiscount;
  final double billDiscountAmount;
  final double taxTotal;
  final double grandTotal;
  final double priceBeforeVat;
  final double afterDiscount;

  static const zero = QuotationTotals(
    subtotal: 0, discountTotal: 0, totalLineDiscount: 0, billDiscountAmount: 0, taxTotal: 0, grandTotal: 0, priceBeforeVat: 0, afterDiscount: 0);

  Map<String, double> toMap() => {
        'subtotal': subtotal,
        'discount_total': discountTotal,
        'total_line_discount': totalLineDiscount,
        'bill_discount_amount': billDiscountAmount,
        'tax_total': taxTotal,
        'grand_total': grandTotal,
        'price_before_vat': priceBeforeVat,
        'after_discount': afterDiscount,
      };
}

/// [headerType] `percent` | `amount` | `none` (ส่วนลดท้ายบิล); [taxType] `exclude` (VAT แยก) | `include` (รวม VAT).
QuotationTotals aggregateHeaderTotals(
  List<Map<String, dynamic>> lines, {
  String? headerType,
  Object? headerValue,
  String? taxType,
  Object? taxRate = 7,
  String? discountMode,
}) {
  var subtotal = 0.0;
  var totalLineDiscount = 0.0;
  for (final ln in lines) {
    if (!isPricedLine(ln)) continue;
    final a = computeLineAmounts(ln, discountMode: discountMode);
    subtotal += a.gross;
    totalLineDiscount += a.lineDiscount;
  }
  final afterItem = (subtotal - totalLineDiscount) < 0 ? 0.0 : subtotal - totalLineDiscount;
  final type = (headerType ?? '').toLowerCase();
  final val = qNum(headerValue) < 0 ? 0.0 : qNum(headerValue);
  var bill = 0.0;
  if (type == 'percent' && val > 0) {
    bill = roundMoney(afterItem * ((val > 100 ? 100 : val) / 100));
  } else if (type == 'amount' && val > 0) {
    bill = roundMoney(val < afterItem ? val : afterItem);
  }
  final afterDiscount = (afterItem - bill) < 0 ? 0.0 : afterItem - bill;
  final rate = resolveTaxRate(taxRate).clamp(0, 100) / 100;
  final mode = (taxType == null || taxType.isEmpty ? 'exclude' : taxType).toLowerCase();
  double before, tax, grand;
  if (mode == 'include') {
    grand = roundMoney(afterDiscount);
    before = rate > 0 ? roundMoney(grand / (1 + rate)) : grand;
    tax = roundMoney(grand - before);
  } else {
    before = roundMoney(afterDiscount);
    tax = roundMoney(before * rate);
    grand = roundMoney(before + tax);
  }
  return QuotationTotals(
    subtotal: roundMoney(subtotal),
    discountTotal: roundMoney(totalLineDiscount + bill),
    totalLineDiscount: roundMoney(totalLineDiscount),
    billDiscountAmount: roundMoney(bill),
    taxTotal: tax,
    grandTotal: grand,
    priceBeforeVat: before,
    afterDiscount: roundMoney(afterDiscount),
  );
}

/// Blank rows (no text, no catalog item, no price) are not saved (web rule).
bool isBlankQuotationLine(Map<String, dynamic> l) =>
    '${l['description'] ?? ''}'.trim().isEmpty &&
    '${l['line_comment'] ?? ''}'.trim().isEmpty &&
    (l['product_id'] == null || '${l['product_id']}'.isEmpty) &&
    (l['service_id'] == null || '${l['service_id']}'.isEmpty) &&
    !(qNum(l['unit_price']) > 0);
