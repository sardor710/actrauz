import '../core/markets.dart';
import 'models.dart';
import 'slot_generator.dart';

/// Price of one slot (product spec §11.4): the rule matching the slot's start
/// time, otherwise the court's base price.
int priceForSlot(Court court, SlotTime slot) {
  for (final rule in court.priceRules) {
    if (rule.matches(slot.start)) return rule.price;
  }
  return court.basePrice;
}

/// Cheapest and dearest slot for [sportId] at [venue] over the seven days
/// starting at [weekStart]. `null` when the sport has no slots that week.
({int min, int max})? feeRange(Venue venue, String sportId, DateTime weekStart) {
  int? min;
  int? max;
  final first = dateOnly(weekStart);
  for (final court in venue.courts.where((c) => c.sportId == sportId)) {
    for (var d = 0; d < 7; d++) {
      for (final slot in generateSlots(venue, court, first.add(Duration(days: d)))) {
        final price = priceForSlot(court, slot);
        if (min == null || price < min) min = price;
        if (max == null || price > max) max = price;
      }
    }
  }
  if (min == null || max == null) return null;
  return (min: min, max: max);
}
