import 'dart:math' as math;

import 'localized_text.dart';

enum Currency { uzs, kzt }

class City {
  const City({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.currency,
    required this.utcOffsetMinutes,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final LocalizedText name;
  final String countryCode;
  final Currency currency;

  /// Offset of the city's local time from UTC. Data, not a constant: logic
  /// must read it from the city (product spec §3).
  final int utcOffsetMinutes;

  /// City centre, used to tell which city a player is in.
  final double latitude;
  final double longitude;
}

const List<City> kCities = [
  City(
    id: 'tashkent',
    name: LocalizedText(uz: 'Toshkent', ru: 'Ташкент', kk: 'Ташкент', en: 'Tashkent'),
    countryCode: 'UZ',
    currency: Currency.uzs,
    utcOffsetMinutes: 300,
    latitude: 41.2995,
    longitude: 69.2401,
  ),
  City(
    id: 'almaty',
    name: LocalizedText(uz: 'Olmaota', ru: 'Алматы', kk: 'Алматы', en: 'Almaty'),
    countryCode: 'KZ',
    currency: Currency.kzt,
    utcOffsetMinutes: 300,
    latitude: 43.2389,
    longitude: 76.8897,
  ),
  City(
    id: 'astana',
    name: LocalizedText(uz: 'Ostona', ru: 'Астана', kk: 'Астана', en: 'Astana'),
    countryCode: 'KZ',
    currency: Currency.kzt,
    utcOffsetMinutes: 300,
    latitude: 51.1694,
    longitude: 71.4491,
  ),
];

City cityById(String id) => kCities.firstWhere((c) => c.id == id);

/// Current wall-clock time in [city].
///
/// Every `DateTime` in the domain layer is venue wall-clock time carried in a
/// UTC-flagged `DateTime`, so arithmetic never depends on the phone's zone.
DateTime venueNow(City city, {DateTime? utcNow}) =>
    (utcNow ?? DateTime.now().toUtc()).add(Duration(minutes: city.utcOffsetMinutes));

/// Midnight of the same wall-clock day.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The supported city closest to the point, or null when none is within
/// [maxKm] (great-circle distance).
City? nearestCity(double lat, double lng, {double maxKm = 150}) {
  City? best;
  var bestKm = maxKm;
  for (final city in kCities) {
    final km = _distanceKm(lat, lng, city.latitude, city.longitude);
    if (km <= bestKm) {
      best = city;
      bestKm = km;
    }
  }
  return best;
}

double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthKm = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return earthKm * 2 * math.asin(math.sqrt(a));
}
