import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../services/api_client.dart';
import '../../services/geo_address.dart';
import '../nx_icons.dart';
import '../nx_map_pin_picker.dart';
import 'field_format.dart';
import 'nx_field_chrome.dart';
import 'nx_pick_option.dart';
import 'nx_picker_sheet.dart';

/// Column names of one Thai address set in a create / edit form, e.g.
/// `address_province` / `address_district` (อำเภอ/เขต) /
/// `address_sub_district` (ตำบล/แขวง) / `address_postal_code` — the web's
/// `ADDRESS_FIELD_MAP` (`crmEntityFormLayout.js`).
class ThaiAddressSetFields {
  const ThaiAddressSetFields({required this.province, this.district, this.subdistrict, this.postal, this.line, this.latLng});

  final String province;
  final String? district;
  final String? subdistrict;
  final String? postal;

  /// Street line (บ้านเลขที่ ถนน) filled from a map pin when still empty.
  final String? line;

  /// "lat,lng" column (e.g. `lead_locationmap`) the map pin is written to.
  final String? latLng;

  /// Fields the set draws itself (the form skips them).
  List<String> get members => [province, district, subdistrict, postal].whereType<String>().toList();
}

/// Finds the address sets among a form's column [names]: a `…province`
/// column plus at least one of its `…district` / `…sub_district` /
/// `…postal_code` siblings (same prefix).
List<ThaiAddressSetFields> detectThaiAddressSets(Iterable<String> names) {
  final all = names.where((n) => n.isNotEmpty).toList();
  final byLower = {for (final n in all) n.toLowerCase(): n};
  String? find(String prefix, List<String> suffixes) {
    for (final s in suffixes) {
      final hit = byLower['$prefix$s'];
      if (hit != null) return hit;
    }
    return null;
  }

  final latLng = all.where((n) => n.toLowerCase().endsWith('locationmap')).toList();
  final out = <ThaiAddressSetFields>[];
  for (final n in all) {
    final l = n.toLowerCase();
    if (!l.endsWith('province')) continue;
    final prefix = l.substring(0, l.length - 'province'.length);
    final sub = find(prefix, const ['sub_district', 'subdistrict', 'tambon']);
    final dist = find(prefix, const ['district', 'amphoe', 'city']);
    final zip = find(prefix, const ['postal_code', 'postalcode', 'postcode', 'zipcode', 'zip_code', 'zip']);
    if (sub == null && dist == null && zip == null) continue;
    out.add(
      ThaiAddressSetFields(
        province: n,
        district: dist,
        subdistrict: sub,
        postal: zip,
        line: find(prefix, const ['line1', 'line_1', 'address_line1', 'street']),
        latLng: latLng.length == 1 ? latLng.first : null,
      ),
    );
  }
  return out;
}

/// Match key for Thai area names: no จังหวัด/อำเภอ/เขต/ตำบล/แขวง prefix,
/// no spaces or punctuation, lower case (web `normalizeAddressMatchKey`).
String thaiAreaKey(String? value) {
  var s = (value ?? '').trim();
  s = s.replaceFirst(RegExp(r'^(จังหวัด|จ\.|อำเภอ|อ\.|เขต|ตำบล|ต\.|แขวง|khwaeng|amphoe|amphur|tambon|changwat)\s*', caseSensitive: false), '');
  return s.toLowerCase().replaceAll(RegExp(r'[\s.,\-()]'), '');
}

const _provinceAliases = {
  'bangkok': 'กรุงเทพมหานคร',
  'krungthepmahanakhon': 'กรุงเทพมหานคร',
  'krungthep': 'กรุงเทพมหานคร',
  'กทม': 'กรุงเทพมหานคร',
  'กรุงเทพ': 'กรุงเทพมหานคร',
  'กรุงเทพฯ': 'กรุงเทพมหานคร',
};

/// [name] matched against [options] (exact key first, then contains).
String? matchThaiArea(Iterable<String> options, String? name) {
  var target = thaiAreaKey(name);
  if (target.isEmpty) return null;
  target = thaiAreaKey(_provinceAliases[target] ?? target);
  for (final o in options) {
    if (thaiAreaKey(o) == target) return o;
  }
  for (final o in options) {
    final k = thaiAreaKey(o);
    if (k.isNotEmpty && (k.contains(target) || target.contains(k))) return o;
  }
  return null;
}

int _rowScore(Map<String, dynamic> row, {String? district, String? subdistrict}) {
  bool near(String? a, String? b) {
    final x = thaiAreaKey(a), y = thaiAreaKey(b);
    return x.isNotEmpty && y.isNotEmpty && (x == y || x.contains(y) || y.contains(x));
  }

  var score = 0;
  if (near('${row['subdistrict'] ?? ''}', subdistrict)) score += 4;
  if (near('${row['district'] ?? ''}', district)) score += 3;
  return score;
}

/// "ตำบล • อำเภอ • จังหวัด" for a by-postal-code row.
String thaiPostalRowLabel(Map<String, dynamic> row) =>
    [row['subdistrict'], row['district'], row['province']].map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).join(' • ');

List<String> _zipsOf(Map<String, dynamic>? entry) {
  if (entry == null) return const [];
  final many = entry['postal_codes'];
  if (many is List && many.isNotEmpty) return [for (final z in many) '$z'];
  final one = '${entry['postal_code'] ?? ''}'.trim();
  return one.isEmpty ? const [] : [one];
}

/// The address group of a create / edit form, made easy like the NEXTX web
/// (`ThaiAddressPicker` + `AddressMapField`):
/// * จังหวัด → อำเภอ/เขต → ตำบล/แขวง cascade; the postcode fills itself,
/// * or type a postcode → pick the matching ตำบล • อำเภอ • จังหวัด,
/// * or drop a pin on the map → the fields are filled from that spot.
/// Uses the web's endpoints (`GET /api/thai-address/*`). If they can't be
/// reached the fields fall back to plain text inputs.
class NxThaiAddressSet extends StatefulWidget {
  const NxThaiAddressSet({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.api,
    this.labels = const {},
    this.required = const {},
    this.errors = const {},
    this.enabled = true,
    this.decorate,
  });

  final ThaiAddressSetFields fields;
  final Map<String, dynamic> values;
  final void Function(String name, dynamic value) onChanged;
  final ApiClient? api;

  /// Column → label from the schema (falls back to Thai defaults).
  final Map<String, String> labels;
  final Set<String> required;
  final Map<String, String> errors;
  final bool enabled;

  /// Wraps each sub-field (the form adds its scroll / shake keys).
  final Widget Function(String name, Widget child)? decorate;

  @override
  State<NxThaiAddressSet> createState() => _NxThaiAddressSetState();
}

class _NxThaiAddressSetState extends State<NxThaiAddressSet> {
  final _zip = TextEditingController();
  final _zipFocus = FocusNode();
  Timer? _zipTimer;
  int _zipGen = 0;
  bool _zipSearching = false;
  String _zipSearched = '';
  List<Map<String, dynamic>> _zipRows = const [];

  /// Several postcodes for the chosen ตำบล: pick one.
  List<String> _zipChoices = const [];
  bool _locating = false;

  /// The address endpoints failed: plain text inputs instead of pickers.
  bool _plain = false;

  ThaiAddressSetFields get f => widget.fields;
  ApiClient? get api => widget.api;

  String _v(String? name) {
    if (name == null) return '';
    final raw = widget.values[name];
    if (raw == null) return '';
    if (raw is Map) return '${raw['label'] ?? raw['value'] ?? ''}'.trim();
    return '$raw'.trim();
  }

  String get _province => _v(f.province);
  String get _district => _v(f.district);
  String get _subdistrict => _v(f.subdistrict);
  String get _postal => _v(f.postal);

  @override
  void initState() {
    super.initState();
    _plain = api == null;
    _zip.text = _postal;
  }

  @override
  void didUpdateWidget(covariant NxThaiAddressSet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = _postal;
    if (!_zipFocus.hasFocus && _zip.text != p) _zip.text = p;
  }

  @override
  void dispose() {
    _zipTimer?.cancel();
    _zip.dispose();
    _zipFocus.dispose();
    super.dispose();
  }

  void _set(Map<String?, String> patch) {
    for (final e in patch.entries) {
      final name = e.key;
      if (name == null) continue;
      if (_v(name) == e.value) continue;
      widget.onChanged(name, e.value);
    }
    final zip = patch[f.postal];
    if (zip != null && _zip.text != zip) _zip.text = zip;
  }

  String _label(String? name, String fallback) {
    final l = name == null ? '' : (widget.labels[name] ?? '').trim();
    return l.isEmpty ? fallback : l;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(msg))));
  }

  /// Runs an address-list call; on failure switches to plain inputs.
  Future<T?> _call<T>(Future<T> Function(ApiClient a) run) async {
    final a = api;
    if (a == null) return null;
    try {
      return await run(a);
    } catch (_) {
      if (mounted) {
        setState(() => _plain = true);
        _snack('โหลดรายชื่อจังหวัด/อำเภอไม่ได้ — พิมพ์ที่อยู่เองได้เลย');
      }
      return null;
    }
  }

  Future<String?> _pick(String title, List<String> names, String current) {
    return showNxPickerSheet(
      context: context,
      title: title,
      value: current.isEmpty ? null : current,
      options: [for (final n in names) NxPickOption(value: n, label: n)],
    );
  }

  // ── cascade ───────────────────────────────────────────────────────────

  Future<void> _pickProvince() async {
    final list = await _call((a) => a.getThaiProvinces());
    if (list == null || !mounted) return;
    if (list.isEmpty) {
      // Older server without the address lists: type it in instead.
      setState(() => _plain = true);
      return _snack('โหลดรายชื่อจังหวัด/อำเภอไม่ได้ — พิมพ์ที่อยู่เองได้เลย');
    }
    final v = await _pick('เลือกจังหวัด', list, _province);
    if (v == null || v == _province) return;
    setState(() {
      _zipChoices = const [];
      _zipRows = const [];
    });
    _set({f.province: v, f.district: '', f.subdistrict: '', f.postal: ''});
  }

  Future<void> _pickDistrict() async {
    if (_province.isEmpty) return _snack('เลือกจังหวัดก่อน');
    final list = await _call((a) => a.getThaiDistricts(_province));
    if (list == null || !mounted) return;
    final v = await _pick('เลือกอำเภอ/เขต', list, _district);
    if (v == null || v == _district) return;
    setState(() {
      _zipChoices = const [];
      _zipRows = const [];
    });
    _set({f.district: v, f.subdistrict: '', f.postal: ''});
  }

  Future<void> _pickSubdistrict() async {
    if (_province.isEmpty || (f.district != null && _district.isEmpty)) {
      return _snack(_province.isEmpty ? 'เลือกจังหวัดก่อน' : 'เลือกอำเภอ/เขตก่อน');
    }
    final rows = await _call((a) => a.getThaiSubdistricts(_province, _district));
    if (rows == null || !mounted) return;
    final names = [for (final r in rows) '${r['name'] ?? ''}'].where((n) => n.isNotEmpty).toList();
    final v = await _pick('เลือกตำบล/แขวง', names, _subdistrict);
    if (v == null) return;
    final zips = _zipsOf(rows.where((r) => '${r['name']}' == v).firstOrNull);
    setState(() {
      _zipRows = const [];
      _zipChoices = zips.length > 1 ? zips : const [];
    });
    _set({f.subdistrict: v, if (zips.length == 1) f.postal: zips.first else if (!zips.contains(_postal)) f.postal: ''});
  }

  // ── postcode → suggestions ────────────────────────────────────────────

  void _onZipTyped(String raw) {
    final zip = raw.replaceAll(RegExp(r'\D'), '');
    if (f.postal != null) widget.onChanged(f.postal!, zip);
    _zipTimer?.cancel();
    if (zip.length != 5) {
      _zipGen++;
      if (_zipRows.isNotEmpty || _zipSearched.isNotEmpty) {
        setState(() {
          _zipRows = const [];
          _zipSearched = '';
        });
      }
      return;
    }
    if (_plain || api == null) return;
    _zipTimer = Timer(const Duration(milliseconds: 350), () => _lookupZip(zip));
  }

  Future<void> _lookupZip(String zip) async {
    final gen = ++_zipGen;
    setState(() => _zipSearching = true);
    List<Map<String, dynamic>> rows;
    try {
      rows = await api!.getThaiAddressByPostalCode(zip);
    } catch (_) {
      rows = const [];
    }
    if (!mounted || gen != _zipGen) return;
    // Already a matching area (e.g. typed the code of the chosen ตำบล).
    final same = rows.any(
      (r) =>
          '${r['province']}' == _province &&
          (f.district == null || '${r['district']}' == _district) &&
          (f.subdistrict == null || '${r['subdistrict']}' == _subdistrict),
    );
    setState(() {
      _zipSearching = false;
      _zipSearched = zip;
      _zipRows = same ? const [] : rows;
      _zipChoices = const [];
    });
  }

  void _applyRow(Map<String, dynamic> row) {
    setState(() {
      _zipRows = const [];
      _zipSearched = '';
      _zipChoices = const [];
    });
    _zipFocus.unfocus();
    _set({
      f.province: '${row['province'] ?? ''}',
      f.district: '${row['district'] ?? ''}',
      f.subdistrict: '${row['subdistrict'] ?? ''}',
      f.postal: '${row['postal_code'] ?? _zip.text}',
    });
  }

  // ── map pin → reverse geocode ─────────────────────────────────────────

  Future<void> _pickOnMap() async {
    final cur = f.latLng == null ? null : parseLatLong(widget.values[f.latLng]);
    final res = await showNxMapPinPicker(context, lat: double.tryParse(cur?.lat ?? ''), lng: double.tryParse(cur?.lng ?? ''), title: 'ปักหมุดตำแหน่งที่อยู่');
    if (res == null || !mounted) return;
    if (f.latLng != null) {
      widget.onChanged(f.latLng!, '${res.lat.toStringAsFixed(6)},${res.lng.toStringAsFixed(6)}');
    }
    setState(() => _locating = true);
    try {
      final parts = await GeoAddress.lookupParts(res.lat, res.lng);
      if (!mounted) return;
      if (parts == null || parts.isEmpty) {
        _snack('หาที่อยู่จากหมุดไม่ได้ — เลือกจังหวัด/อำเภอ/ตำบลเองได้เลย');
        return;
      }
      final r = await _resolve(parts);
      if (!mounted) return;
      final patch = <String?, String>{
        if (r.province.isNotEmpty) f.province: r.province,
        if (r.province.isNotEmpty) f.district: r.district,
        if (r.province.isNotEmpty) f.subdistrict: r.subdistrict,
        if (r.postal.isNotEmpty) f.postal: r.postal,
        if (f.line != null && _v(f.line).isEmpty && parts.street.isNotEmpty) f.line: parts.street,
      };
      setState(() {
        _zipRows = const [];
        _zipChoices = r.zipChoices;
      });
      _set(patch);
      _snack(r.province.isEmpty ? 'หาที่อยู่จากหมุดไม่ครบ — เลือกเพิ่มเองได้เลย' : 'เติมที่อยู่จากหมุดแล้ว — ตรวจสอบอีกครั้งก่อนบันทึก');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Geocoder names → names from the NEXTX lists (web `syncFromGoogleAddress`).
  Future<({String province, String district, String subdistrict, String postal, List<String> zipChoices})> _resolve(GeoAddressParts p) async {
    var prov = '', dist = '', sub = '';
    var zip = p.postalCode.length >= 5 ? p.postalCode.substring(0, 5) : '';
    var choices = const <String>[];
    final a = api;
    if (a != null && !_plain) {
      try {
        prov = matchThaiArea(await a.getThaiProvinces(), p.province) ?? '';
        if (prov.isNotEmpty) dist = matchThaiArea(await a.getThaiDistricts(prov), p.district) ?? '';
        if (prov.isNotEmpty && dist.isNotEmpty) {
          final rows = await a.getThaiSubdistricts(prov, dist);
          sub = matchThaiArea([for (final r in rows) '${r['name'] ?? ''}'], p.subdistrict) ?? '';
          final zips = _zipsOf(rows.where((r) => '${r['name']}' == sub).firstOrNull);
          if (zips.length == 1) {
            zip = zips.first;
          } else if (zips.length > 1 && !zips.contains(zip)) {
            choices = zips;
            zip = '';
          }
        }
        if (zip.length == 5) {
          final rows = await a.getThaiAddressByPostalCode(zip);
          Map<String, dynamic>? best;
          var bestScore = -1;
          for (final r in rows) {
            final s = _rowScore(r, district: dist.isEmpty ? p.district : dist, subdistrict: sub.isEmpty ? p.subdistrict : sub);
            if (s > bestScore) {
              bestScore = s;
              best = r;
            }
          }
          if (rows.length == 1) best = rows.first;
          if (best != null && (bestScore > 0 || rows.length == 1 || (dist.isEmpty && sub.isEmpty))) {
            prov = '${best['province'] ?? prov}';
            dist = '${best['district'] ?? dist}';
            sub = '${best['subdistrict'] ?? sub}';
            zip = '${best['postal_code'] ?? zip}';
          }
        }
        return (province: prov, district: dist, subdistrict: sub, postal: zip, zipChoices: choices);
      } catch (_) {
        // Fall through: the geocoder's own names.
      }
    }
    return (
      province: _provinceAliases[thaiAreaKey(p.province)] ?? p.province.replaceFirst(RegExp(r'^จังหวัด\s*'), ''),
      district: p.district.replaceFirst(RegExp(r'^(อำเภอ|เขต)\s*'), ''),
      subdistrict: p.subdistrict.replaceFirst(RegExp(r'^(ตำบล|แขวง)\s*'), ''),
      postal: zip,
      zipChoices: const <String>[],
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  Widget _wrap(String name, Widget child) => widget.decorate?.call(name, child) ?? child;

  Widget _tap({required String name, required String label, required String hint, required IconData icon, required VoidCallback onTap, bool enabled = true}) {
    final value = _v(name);
    final cs = Theme.of(context).colorScheme;
    return _wrap(
      name,
      NxOutlinedTapField(
        key: ValueKey('addr-$name'),
        label: label,
        required: widget.required.contains(name),
        errorText: widget.errors[name],
        isEmpty: value.isEmpty,
        enabled: widget.enabled && enabled,
        hint: hint,
        onTap: onTap,
        prefixIcon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        suffixIcon: nxTapFieldSuffix(context),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _plainField(String name, String label, String hint, {bool numeric = false}) {
    return _wrap(
      name,
      _PlainAddressInput(
        key: ValueKey('addr-$name'),
        value: _v(name),
        label: label,
        hint: hint,
        numeric: numeric,
        required: widget.required.contains(name),
        errorText: widget.errors[name],
        enabled: widget.enabled,
        onChanged: (v) => widget.onChanged(name, v),
      ),
    );
  }

  Widget _zipField(String name, String label) {
    final cs = Theme.of(context).colorScheme;
    return _wrap(
      name,
      TextField(
        key: ValueKey('addr-$name'),
        controller: _zip,
        focusNode: _zipFocus,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
        onChanged: _onZipTyped,
        decoration: NxFieldStyle.decoration(
          context,
          label: label,
          required: widget.required.contains(name),
          errorText: widget.errors[name],
          prefixIcon: Icon(NxI.hash, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: _zipSearching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          floatLabel: true,
        ).copyWith(hintText: tr('เช่น 10110 — พิมพ์ 5 หลักเพื่อค้นพื้นที่'), floatingLabelBehavior: FloatingLabelBehavior.always),
      ),
    );
  }

  Widget _zipSuggestions(ThemeData theme) {
    final cs = theme.colorScheme;
    if (_zipSearched.isNotEmpty && _zipRows.isEmpty && !_zipSearching && _zip.text == _zipSearched) {
      final hasArea = _province.isNotEmpty;
      if (hasArea) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          tr('ไม่พบพื้นที่สำหรับรหัสไปรษณีย์นี้'),
          key: const ValueKey('addr-zip-none'),
          style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
        ),
      );
    }
    if (_zipRows.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('addr-zip-suggestions'),
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NxFieldStyle.radius),
          side: BorderSide(color: cs.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(
                tr('พบ ${_zipRows.length} พื้นที่ของรหัส $_zipSearched — แตะเพื่อเติมตำบล อำเภอ จังหวัด'),
                style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
            for (var i = 0; i < _zipRows.length; i++)
              ListTile(
                key: ValueKey('addr-zip-opt-$i'),
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(NxI.mapPin, size: 18, color: cs.primary),
                title: Text('${_zipRows[i]['subdistrict'] ?? ''}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text([_zipRows[i]['district'], _zipRows[i]['province']].map((e) => '${e ?? ''}').where((e) => e.isNotEmpty).join(' • ')),
                onTap: widget.enabled ? () => _applyRow(_zipRows[i]) : null,
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final provLabel = _label(f.province, 'จังหวัด');
    final distLabel = _label(f.district, 'อำเภอ/เขต');
    final subLabel = _label(f.subdistrict, 'ตำบล/แขวง');
    final zipLabel = _label(f.postal, 'รหัสไปรษณีย์');
    final children = <Widget>[
      // Three ways in: pin on the map, postcode, or the cascade below.
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('addr-map'),
              onPressed: widget.enabled && !_locating ? _pickOnMap : null,
              icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.mapPin, size: 18),
              label: Text(tr(_locating ? 'กำลังหาที่อยู่…' : 'ปักหมุดบนแผนที่'), maxLines: 1, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: const StadiumBorder()),
            ),
          ),
          if (f.postal != null && !_plain) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('addr-zip-focus'),
                onPressed: widget.enabled ? () => _zipFocus.requestFocus() : null,
                icon: const Icon(NxI.magnifyingGlass, size: 18),
                label: Text(tr('ค้นจากรหัส ปณ.'), maxLines: 1, overflow: TextOverflow.ellipsis),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: const StadiumBorder()),
              ),
            ),
          ],
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(NxI.info, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr(
                  _plain
                      ? 'พิมพ์จังหวัด อำเภอ/เขต ตำบล/แขวง และรหัสไปรษณีย์ หรือปักหมุดให้ระบบเติมให้'
                      : 'เลือกจังหวัด → อำเภอ/เขต → ตำบล/แขวง แล้วรหัสไปรษณีย์จะเติมให้เอง หรือพิมพ์รหัสไปรษณีย์เพื่อเลือกพื้นที่',
                ),
                key: const ValueKey('addr-hint'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    ];
    void gap() => children.add(const SizedBox(height: 20));
    if (_plain) {
      children.add(_plainField(f.province, provLabel, 'เช่น กรุงเทพมหานคร'));
      if (f.district != null) {
        gap();
        children.add(_plainField(f.district!, distLabel, 'เช่น ปทุมวัน'));
      }
      if (f.subdistrict != null) {
        gap();
        children.add(_plainField(f.subdistrict!, subLabel, 'เช่น ลุมพินี'));
      }
      if (f.postal != null) {
        gap();
        children.add(_plainField(f.postal!, zipLabel, 'เช่น 10330', numeric: true));
      }
    } else {
      children.add(_tap(name: f.province, label: provLabel, hint: 'แตะเพื่อเลือกจังหวัด', icon: NxI.mapTrifold, onTap: _pickProvince));
      if (f.district != null) {
        gap();
        children.add(
          _tap(
            name: f.district!,
            label: distLabel,
            hint: _province.isEmpty ? 'เลือกจังหวัดก่อน' : 'แตะเพื่อเลือกอำเภอ/เขต',
            icon: NxI.buildings,
            enabled: _province.isNotEmpty,
            onTap: _pickDistrict,
          ),
        );
      }
      if (f.subdistrict != null) {
        gap();
        final ready = _province.isNotEmpty && (f.district == null || _district.isNotEmpty);
        children.add(
          _tap(
            name: f.subdistrict!,
            label: subLabel,
            hint: ready ? 'แตะเพื่อเลือกตำบล/แขวง' : (_province.isEmpty ? 'เลือกจังหวัดก่อน' : 'เลือกอำเภอ/เขตก่อน'),
            icon: NxI.house,
            enabled: ready,
            onTap: _pickSubdistrict,
          ),
        );
      }
      if (f.postal != null) {
        gap();
        children.add(_zipField(f.postal!, zipLabel));
        if (_zipChoices.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(tr('ตำบลนี้มีหลายรหัส — เลือก:'), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  for (final z in _zipChoices)
                    ChoiceChip(
                      key: ValueKey('addr-zip-choice-$z'),
                      label: Text(z),
                      selected: _postal == z,
                      onSelected: widget.enabled ? (_) => _set({f.postal: z}) : null,
                    ),
                ],
              ),
            ),
          );
        }
        children.add(_zipSuggestions(theme));
      }
    }
    return Column(key: ValueKey('addr-set-${f.province}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Text input used when the address lists can't be loaded.
class _PlainAddressInput extends StatefulWidget {
  const _PlainAddressInput({
    super.key,
    required this.value,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.numeric = false,
    this.required = false,
    this.errorText,
    this.enabled = true,
  });

  final String value;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool numeric;
  final bool required;
  final String? errorText;
  final bool enabled;

  @override
  State<_PlainAddressInput> createState() => _PlainAddressInputState();
}

class _PlainAddressInputState extends State<_PlainAddressInput> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _PlainAddressInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      enabled: widget.enabled,
      keyboardType: widget.numeric ? TextInputType.number : null,
      inputFormatters: widget.numeric ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)] : null,
      onChanged: widget.onChanged,
      decoration: NxFieldStyle.decoration(
        context,
        label: widget.label,
        required: widget.required,
        errorText: widget.errorText,
        floatLabel: true,
      ).copyWith(hintText: tr(widget.hint), floatingLabelBehavior: FloatingLabelBehavior.always),
    );
  }
}
