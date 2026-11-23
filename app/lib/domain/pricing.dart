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

/// Pairs of [rules] that share a weekday and whose time ranges intersect
/// (spec §11.4), in list order. Back-to-back ranges do not intersect.
List<(PriceRule, PriceRule)> overlappingRules(List<PriceRule> rules) => [
  for (var i = 0; i < rules.length; i++)
    for (var j = i + 1; j < rules.length; j++)
      if (rules[i].weekdays.any(rules[j].weekdays.contains) &&
          rules[i].fromMinute < rules[j].toMinute &&
          rules[j].fromMinute < rules[i].toMinute)
        (rules[i], rules[j]),
];

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
