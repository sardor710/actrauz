import 'localized_text.dart';

enum Currency { uzs, kzt }

class City {
  const City({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.currency,
    required this.utcOffsetMinutes,
  });

  final String id;
  final LocalizedText name;
  final String countryCode;
  final Currency currency;

  /// Offset of the city's local time from UTC. Data, not a constant: logic
  /// must read it from the city (product spec §3).
  final int utcOffsetMinutes;
}

const List<City> kCities = [
  City(
    id: 'tashkent',
    name: LocalizedText(uz: 'Toshkent', ru: 'Ташкент', en: 'Tashkent'),
    countryCode: 'UZ',
    currency: Currency.uzs,
    utcOffsetMinutes: 300,
  ),
  City(
    id: 'almaty',
    name: LocalizedText(uz: 'Olmaota', ru: 'Алматы', en: 'Almaty'),
    countryCode: 'KZ',
    currency: Currency.kzt,
    utcOffsetMinutes: 300,
  ),
  City(
    id: 'astana',
    name: LocalizedText(uz: 'Ostona', ru: 'Астана', en: 'Astana'),
    countryCode: 'KZ',
    currency: Currency.kzt,
    utcOffsetMinutes: 300,
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
