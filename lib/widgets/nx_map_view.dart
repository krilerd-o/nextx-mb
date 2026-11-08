import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import 'nx_icons.dart';
import '../core/build_target.dart';
import '../core/i18n.dart';

/// True when the build has a Google Maps key (`--dart-define=NX_MAPS=1`).
/// Without it a coordinate card is shown instead of a blank grey map.
const bool kMapsEnabled = bool.fromEnvironment('NX_MAPS', defaultValue: false);

/// OpenStreetMap tile URL (Huawei build, or no Google Maps key). Can point to
/// your own tile server with `--dart-define=NX_OSM_TILES=https://.../{z}/{x}/{y}.png`.
const String kOsmTiles = String.fromEnvironment('NX_OSM_TILES', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

/// Which map NxMapView draws.
enum NxMapKind { google, osm, card }

NxMapKind nxMapKind({bool? huawei, bool? mapsKey, bool? underTest}) {
  if (kIsWeb) return NxMapKind.card;
  // Widget tests have no network: keep the coordinate card there.
  final testing = underTest ?? (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'));
  if ((mapsKey ?? kMapsEnabled) && !(huawei ?? isHuaweiBuild)) return NxMapKind.google;
  return testing ? NxMapKind.card : NxMapKind.osm;
}

/// Map with "me" + destination pins and the allowed check-in radius.
/// Google Maps when the build has a key (Play / iOS); OpenStreetMap on Huawei
/// (no Google services) and on builds without a key.
class NxMapView extends StatelessWidget {
  const NxMapView({
    super.key,
    required this.me,
    this.accuracy,
    this.dest,
    this.rangeMeters,
    this.height = 220,
  });

  final LatLng me;
  final double? accuracy;
  final LatLng? dest;
  final double? rangeMeters;
  final double height;

  static Uri googleMapsLink(LatLng p) =>
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '${p.latitude},${p.longitude}'});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(22);
    final kind = nxMapKind();
    if (kind == NxMapKind.card) return _Fallback(me: me, dest: dest, height: height);
    if (kind == NxMapKind.osm) {
      return _OsmMap(me: me, accuracy: accuracy, dest: dest, rangeMeters: rangeMeters, height: height);
    }
    final d = dest;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: me, zoom: 16.5),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          liteModeEnabled: false,
          markers: {
            Marker(markerId: const MarkerId('me'), position: me, infoWindow: const InfoWindow(title: 'ตำแหน่งของคุณ')),
            if (d != null)
              Marker(
                markerId: const MarkerId('dest'),
                position: d,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                infoWindow: const InfoWindow(title: 'สถานที่นัด'),
              ),
          },
          circles: {
            if (accuracy != null)
              Circle(
                circleId: const CircleId('acc'),
                center: me,
                radius: accuracy!,
                strokeWidth: 1,
                strokeColor: cs.primary.withValues(alpha: 0.5),
                fillColor: cs.primary.withValues(alpha: 0.12),
              ),
            if (d != null && rangeMeters != null)
              Circle(
                circleId: const CircleId('range'),
                center: d,
                radius: rangeMeters!,
                strokeWidth: 2,
                strokeColor: const Color(0xFF8B5CF6),
                fillColor: const Color(0x148B5CF6),
              ),
          },
        ),
      ),
    );
  }
}

class _OsmMap extends StatelessWidget {
  const _OsmMap({required this.me, this.accuracy, this.dest, this.rangeMeters, required this.height});
  final LatLng me;
  final double? accuracy;
  final LatLng? dest;
  final double? rangeMeters;
  final double height;

  static ll.LatLng _p(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = dest;
    Widget pin(Color color, IconData icon) => Icon(icon, color: color, size: 36, shadows: const [Shadow(blurRadius: 6, color: Color(0x55000000))]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: height,
        child: fm.FlutterMap(
          options: fm.MapOptions(initialCenter: _p(me), initialZoom: 16.5),
          children: [
            fm.TileLayer(urlTemplate: kOsmTiles, userAgentPackageName: 'com.moai.nextt.mobile'),
            fm.CircleLayer(circles: [
              if (accuracy != null)
                fm.CircleMarker(
                  point: _p(me),
                  radius: accuracy!,
                  useRadiusInMeter: true,
                  color: cs.primary.withValues(alpha: 0.12),
                  borderColor: cs.primary.withValues(alpha: 0.5),
                  borderStrokeWidth: 1,
                ),
              if (d != null && rangeMeters != null)
                fm.CircleMarker(
                  point: _p(d),
                  radius: rangeMeters!,
                  useRadiusInMeter: true,
                  color: const Color(0x148B5CF6),
                  borderColor: const Color(0xFF8B5CF6),
                  borderStrokeWidth: 2,
                ),
            ]),
            fm.MarkerLayer(markers: [
              if (d != null) fm.Marker(point: _p(d), width: 40, height: 40, alignment: Alignment.topCenter, child: pin(const Color(0xFF8B5CF6), NxI.mapPin)),
              fm.Marker(point: _p(me), width: 40, height: 40, alignment: Alignment.topCenter, child: pin(cs.primary, NxI.mapPin)),
            ]),
            // OpenStreetMap licence: attribution must stay visible.
            const fm.SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
          ],
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.me, this.dest, required this.height});
  final LatLng me;
  final LatLng? dest;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withValues(alpha: 0.14), const Color(0xFF93C5FD).withValues(alpha: 0.22)],
        ),
      ),
      child: Stack(
        children: [
          // Map-like grid so the card reads as "location".
          Positioned.fill(child: CustomPaint(painter: _GridPainter(cs.primary.withValues(alpha: 0.10)))),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: 4)],
                  ),
                  child: const Icon(NxI.mapPin, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('${me.latitude.toStringAsFixed(6)}, ${me.longitude.toStringAsFixed(6)}'),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(NxMapView.googleMapsLink(me), mode: LaunchMode.externalApplication),
                  icon: const Icon(NxI.arrowSquareOut, size: 16),
                  label: Text(tr('ดูใน Google Maps')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}
