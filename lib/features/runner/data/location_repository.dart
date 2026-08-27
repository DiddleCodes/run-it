import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/domain/auth_models.dart';

/// Reads the device's current position for the Independent Rider geofence
/// check — the one real (not mock) location integration in the app, kept
/// behind this single seam so `RunnerController` doesn't call `geolocator`
/// directly and tests can substitute a fixed [GeoPoint] via
/// [locationRepositoryProvider] instead of needing a real device/plugin.
///
/// Returns `null` on any failure — permission denied, location services
/// off, no platform implementation (as in the test harness) — mirroring
/// how `AuthController`'s biometric calls fail closed rather than throw.
class LocationRepository {
  const LocationRepository();

  Future<GeoPoint?> currentPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final position = await Geolocator.getCurrentPosition();
      return GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      return null;
    }
  }
}

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) => const LocationRepository(),
);
