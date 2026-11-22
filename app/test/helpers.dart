import 'package:actra/core/localized_text.dart';
import 'package:actra/domain/models.dart';

/// Monday.
final monday = DateTime.utc(2026, 11, 23);
final saturday = DateTime.utc(2026, 11, 28);

const _t = LocalizedText.all('x');

Court testCourt({
  String id = 'c1',
  int slot = 90,
  int basePrice = 180000,
  List<PriceRule> rules = const [],
  WeekHours override = const {},
  String sportId = 'padel',
}) => Court(
  id: id,
  venueId: 'v1',
  sportId: sportId,
  name: _t,
  slotMinutes: slot,
  basePrice: basePrice,
  priceRules: rules,
  hoursOverride: override,
);

Venue testVenue({int open = 7 * 60, int close = 23 * 60, WeekHours? hours, List<Court>? courts}) => Venue(
  id: 'v1',
  cityId: 'tashkent',
  name: _t,
  description: _t,
  address: _t,
  district: _t,
  phone: '',
  hours: hours ?? weekHours(weekdays: DayHours(open, close), weekend: DayHours(open, close)),
  courts: courts ?? [testCourt()],
);

SlotTime slotAt(DateTime day, int hour, int minute, {int length = 90}) {
  final start = DateTime.utc(day.year, day.month, day.day, hour, minute);
  return SlotTime(start, start.add(Duration(minutes: length)));
}
