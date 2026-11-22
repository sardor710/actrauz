import '../core/localized_text.dart';

/// Opening and closing time of one day, in minutes from midnight.
class DayHours {
  const DayHours(this.openMinute, this.closeMinute);

  const DayHours.hm(int openHour, int openMin, int closeHour, int closeMin)
    : openMinute = openHour * 60 + openMin,
      closeMinute = closeHour * 60 + closeMin;

  final int openMinute;
  final int closeMinute;
}

/// Hours per `DateTime.weekday` (1 = Monday … 7 = Sunday). `null` = closed.
typedef WeekHours = Map<int, DayHours?>;

WeekHours weekHours({DayHours? weekdays, DayHours? weekend}) => {
  for (var d = 1; d <= 5; d++) d: weekdays,
  6: weekend,
  7: weekend,
};

/// "These days, this time range → this price per slot" (product spec §11.4).
class PriceRule {
  const PriceRule({
    required this.weekdays,
    required this.fromMinute,
    required this.toMinute,
    required this.price,
  });

  final Set<int> weekdays;
  final int fromMinute;

  /// Exclusive.
  final int toMinute;
  final int price;

  bool matches(DateTime slotStart) {
    final minute = slotStart.hour * 60 + slotStart.minute;
    return weekdays.contains(slotStart.weekday) && minute >= fromMinute && minute < toMinute;
  }
}

class Court {
  const Court({
    required this.id,
    required this.venueId,
    required this.sportId,
    required this.name,
    required this.slotMinutes,
    required this.basePrice,
    this.priceRules = const [],
    this.hoursOverride = const {},
    this.indoor = false,
  });

  final String id;
  final String venueId;
  final String sportId;
  final LocalizedText name;

  /// 60, 90 or 120.
  final int slotMinutes;
  final int basePrice;
  final List<PriceRule> priceRules;

  /// Only the weekdays that differ from the venue. A key mapped to `null`
  /// means the court is closed that day even if the venue is open.
  final WeekHours hoursOverride;
  final bool indoor;

  Court copyWith({int? basePrice}) => Court(
    id: id,
    venueId: venueId,
    sportId: sportId,
    name: name,
    slotMinutes: slotMinutes,
    basePrice: basePrice ?? this.basePrice,
    priceRules: priceRules,
    hoursOverride: hoursOverride,
    indoor: indoor,
  );
}

class Venue {
  const Venue({
    required this.id,
    required this.cityId,
    required this.name,
    required this.description,
    required this.address,
    required this.district,
    required this.phone,
    required this.hours,
    required this.courts,
    this.amenities = const [],
    this.colorSeed = 0,
  });

  final String id;
  final String cityId;
  final LocalizedText name;
  final LocalizedText description;
  final LocalizedText address;
  final LocalizedText district;
  final String phone;
  final WeekHours hours;
  final List<Court> courts;

  /// Keys from `kAmenityKeys`.
  final List<String> amenities;

  /// Picks the placeholder colour until venues have photos.
  final int colorSeed;

  List<String> get sportIds => {for (final c in courts) c.sportId}.toList();

  Court court(String id) => courts.firstWhere((c) => c.id == id);

  Venue copyWith({List<Court>? courts}) => Venue(
    id: id,
    cityId: cityId,
    name: name,
    description: description,
    address: address,
    district: district,
    phone: phone,
    hours: hours,
    courts: courts ?? this.courts,
    amenities: amenities,
    colorSeed: colorSeed,
  );
}

const kAmenityKeys = ['parking', 'showers', 'lighting', 'cafe', 'rental'];

class Sport {
  const Sport({
    required this.id,
    required this.name,
    required this.iconKey,
    this.bookable = true,
    this.competitiveRating = false,
    this.defaultPlayers = 2,
  });

  final String id;
  final LocalizedText name;
  final String iconKey;

  /// `false` for place-only sports (running, gym): no slots, no payment.
  final bool bookable;

  /// `true` for padel and tennis: 1.0–7.0 rating instead of level 1–5.
  final bool competitiveRating;
  final int defaultPlayers;
}

/// One bookable slot, in venue wall-clock time.
class SlotTime {
  const SlotTime(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) => other is SlotTime && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SlotTime($start – $end)';
}

class BannerItem {
  const BannerItem({required this.id, required this.title, required this.subtitle, required this.url, this.colorSeed = 0});

  final String id;
  final LocalizedText title;
  final LocalizedText subtitle;
  final String url;
  final int colorSeed;
}

class TournamentItem {
  const TournamentItem({
    required this.id,
    required this.cityId,
    required this.sportId,
    required this.title,
    required this.venueName,
    required this.start,
    required this.end,
    required this.minFee,
    required this.maxFee,
    required this.slotsTotal,
    required this.slotsFilled,
  });

  final String id;
  final String cityId;
  final String sportId;
  final LocalizedText title;
  final LocalizedText venueName;
  final DateTime start;
  final DateTime end;
  final int minFee;
  final int maxFee;
  final int slotsTotal;
  final int slotsFilled;
}
