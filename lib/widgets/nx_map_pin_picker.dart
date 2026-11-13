import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;

import '../core/i18n.dart';
import '../services/location_service.dart';
import 'fields/nx_lift_sheet.dart';
import 'nx_icons.dart';
import 'nx_map_view.dart';

/// Opens the "ปักหมุดบนแผนที่" sheet; the chosen point, or null.
Future<({double lat, double lng})?> showNxMapPinPicker(
  BuildContext context, {
  double? lat,
  double? lng,
  String title = 'แตะแผนที่เพื่อปักหมุด',
}) {
  return showNxLiftSheet<({double lat, double lng})>(
    context: context,
    builder: (ctx, scroll) => NxMapPinPicker(lat: lat, lng: lng, title: title),
  );
}

/// Tap the map to drop the pin, or use the current position. Pops the sheet
/// with `(lat:, lng:)` on "ใช้ตำแหน่งนี้". Shared by the activity form and
/// the address set of create / edit forms.
class NxMapPinPicker extends StatefulWidget {
  const NxMapPinPicker({super.key, this.lat, this.lng, this.title = 'แตะแผนที่เพื่อปักหมุด'});
  final double? lat;
  final double? lng;
  final String title;

  @override
  State<NxMapPinPicker> createState() => _NxMapPinPickerState();
}

class _NxMapPinPickerState extends State<NxMapPinPicker> {
  final _map = fm.MapController();
  ll.LatLng? _pin;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.lat != null && widget.lng != null) {
      _pin = ll.LatLng(widget.lat!, widget.lng!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _here(move: true));
    }
  }

  Future<void> _here({bool move = true}) async {
    setState(() => _locating = true);
    try {
      final fix = await LocationService().currentFix();
      if (!mounted) return;
      final p = ll.LatLng(fix.latitude, fix.longitude);
      setState(() => _pin = p);
      if (move && nxMapKind() != NxMapKind.card) _map.move(p, 16);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('หาตำแหน่งปัจจุบันไม่ได้'))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final center = _pin ?? const ll.LatLng(13.7563, 100.5018); // Bangkok
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Row(children: [
          Expanded(child: Text(tr(widget.title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          TextButton(
            key: const ValueKey('pin-done'),
            onPressed: _pin == null ? null : () => Navigator.of(context).pop((lat: _pin!.latitude, lng: _pin!.longitude)),
            child: Text(tr('ใช้ตำแหน่งนี้')),
          ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: nxMapKind() == NxMapKind.card
                ? ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: Center(child: Text(_pin == null ? tr('ยังไม่ได้ปักหมุด') : '${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}')),
                  )
                : fm.FlutterMap(
                    mapController: _map,
                    options: fm.MapOptions(
                      initialCenter: center,
                      initialZoom: _pin == null ? 11 : 16,
                      onTap: (_, p) => setState(() => _pin = p),
                    ),
                    children: [
                      fm.TileLayer(urlTemplate: kOsmTiles, userAgentPackageName: 'com.moai.nextt.mobile'),
                      if (_pin != null)
                        fm.MarkerLayer(markers: [
                          fm.Marker(point: _pin!, width: 44, height: 44, alignment: Alignment.topCenter, child: Icon(NxI.mapPin, size: 40, color: cs.error)),
                        ]),
                    ],
                  ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: OutlinedButton.icon(
          key: const ValueKey('pin-here'),
          onPressed: _locating ? null : () => _here(),
          icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(NxI.crosshair, size: 18),
          label: Text(tr('ใช้ตำแหน่งปัจจุบัน')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
      ),
    ]);
  }
}
