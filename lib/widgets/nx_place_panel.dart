import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../screens/calendar/visit_check_sheet.dart' show CheckInfoRow, thaiDateTime;
import '../services/geo_address.dart';
import 'nx_icons.dart';
import 'nx_map_view.dart';
import 'nx_overlay_panel.dart';

/// "Where" panel for a punch / check-in: small map, time, coordinates and
/// place (looked up when not given), with open-in-maps and copy.
Future<void> showNxPlacePanel(
  BuildContext context, {
  required String title,
  DateTime? at,
  Object? lat,
  Object? lng,
  Object? address,
}) {
  final la = double.tryParse('${lat ?? ''}'), lo = double.tryParse('${lng ?? ''}');
  return showNxBlurPanel<void>(
    context: context,
    builder: (ctx) => _PlacePanel(title: title, at: at, lat: la, lng: lo, address: address?.toString()),
  );
}

/// `"13.7133,100.7407"` → (lat, lng).
(double, double)? parseLatLngText(Object? raw) {
  final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)').firstMatch('${raw ?? ''}');
  if (m == null) return null;
  return (double.parse(m.group(1)!), double.parse(m.group(2)!));
}

class _PlacePanel extends StatefulWidget {
  const _PlacePanel({required this.title, this.at, this.lat, this.lng, this.address});

  final String title;
  final DateTime? at;
  final double? lat;
  final double? lng;
  final String? address;

  @override
  State<_PlacePanel> createState() => _PlacePanelState();
}

class _PlacePanelState extends State<_PlacePanel> {
  String? _address;
  bool _looking = false;

  bool get _hasPoint => widget.lat != null && widget.lng != null;

  @override
  void initState() {
    super.initState();
    _address = (widget.address ?? '').trim().isEmpty ? null : widget.address;
    if (_address == null && _hasPoint) {
      _looking = true;
      GeoAddress.lookup(widget.lat!, widget.lng!).then((a) {
        if (mounted) setState(() {
          _address = a;
          _looking = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coords = _hasPoint ? '${widget.lat!.toStringAsFixed(6)}, ${widget.lng!.toStringAsFixed(6)}' : null;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr(widget.title), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (_hasPoint) NxMapView(me: LatLng(widget.lat!, widget.lng!), height: 180),
          if (widget.at != null) CheckInfoRow(icon: NxI.clock, label: 'เวลา', value: thaiDateTime(widget.at!), strong: true),
          if (coords != null) CheckInfoRow(icon: NxI.crosshair, label: 'พิกัด', value: coords),
          if (_address != null)
            CheckInfoRow(icon: NxI.mapPin, label: 'สถานที่', value: _address!.replaceAll('\n', ' '))
          else if (_looking)
            CheckInfoRow(icon: NxI.mapPin, label: 'สถานที่', value: tr('กำลังค้นหาที่อยู่…')),
          if (!_hasPoint)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('ไม่มีพิกัด'), style: theme.textTheme.bodyMedium),
            ),
          if (coords != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('place-copy'),
                    icon: const Icon(NxI.copySimple, size: 18),
                    label: Text(tr('คัดลอก'), maxLines: 1),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '${widget.lat},${widget.lng}'));
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('คัดลอกพิกัดแล้ว'))));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('place-maps'),
                    icon: const Icon(NxI.mapTrifold, size: 18),
                    label: Text(tr('แผนที่'), maxLines: 1),
                    onPressed: () => launchUrl(
                      Uri.parse('https://www.google.com/maps/search/?api=1&query=${widget.lat},${widget.lng}'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
