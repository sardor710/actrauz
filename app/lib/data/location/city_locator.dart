import 'package:geolocator/geolocator.dart';

import '../../core/markets.dart';

/// Works out which city the player is in, once, for onboarding.
abstract class CityLocator {
  /// The id of the supported city the player is in, or null when it cannot be
  /// told (permission denied, location off, timeout, outside every city).
  Future<String?> detectCityId();
}

/// A fixed answer: tests and sample mode (no backend compiled in).
class FixedCityLocator implements CityLocator {
  const FixedCityLocator(this.cityId);

  final String? cityId;

  @override
  Future<String?> detectCityId() async => cityId;
}

/// Uses the device's coarse location. Asks for permission once; any denial or
/// error is simply "unknown".
class GeolocatorCityLocator implements CityLocator {
  const GeolocatorCityLocator();

  static const timeout = Duration(seconds: 8);

  @override
  Future<String?> detectCityId() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: timeout),
      ).timeout(timeout);
      return nearestCity(position.latitude, position.longitude)?.id;
    } catch (_) {
      return null;
    }
  }
}
