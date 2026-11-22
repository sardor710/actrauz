import '../core/markets.dart';
import 'models.dart';

/// Hours that apply to [court] on [date]: the court's own override for that
/// weekday when it has one, otherwise the venue's hours. `null` = closed.
DayHours? effectiveHours(Venue venue, Court court, DateTime date) {
  final weekday = date.weekday;
  if (court.hoursOverride.containsKey(weekday)) return court.hoursOverride[weekday];
  return venue.hours[weekday];
}

/// Slots for one court on one day (product spec §11.3): back to back from
/// opening time, each [Court.slotMinutes] long. A final slot that would end
/// after closing is not offered.
List<SlotTime> generateSlots(Venue venue, Court court, DateTime date) {
  final hours = effectiveHours(venue, court, date);
  if (hours == null || court.slotMinutes <= 0) return const [];

  final day = dateOnly(date);
  final slots = <SlotTime>[];
  for (var m = hours.openMinute; m + court.slotMinutes <= hours.closeMinute; m += court.slotMinutes) {
    slots.add(SlotTime(day.add(Duration(minutes: m)), day.add(Duration(minutes: m + court.slotMinutes))));
  }
  return slots;
}
