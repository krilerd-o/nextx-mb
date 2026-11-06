import 'package:geolocator/geolocator.dart';

class GeoFix {
  const GeoFix({required this.latitude, required this.longitude, this.address});
  final double latitude;
  final double longitude;
  final String? address;
}

class LocationService {
  Future<GeoFix> currentFix() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('ไม่ได้รับสิทธิ์ตำแหน่ง');
    }
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('กรุณาเปิด GPS');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return GeoFix(latitude: pos.latitude, longitude: pos.longitude);
  }
}
