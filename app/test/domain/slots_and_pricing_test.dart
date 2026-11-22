import 'package:actra/domain/models.dart';
import 'package:actra/domain/pricing.dart';
import 'package:actra/domain/slot_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('slot generation', () {
    test('07:00–23:00 with 90-minute slots gives 07:00 … 20:30', () {
      final slots = generateSlots(testVenue(), testCourt(slot: 90), monday);
      expect(slots.length, 10);
      expect(slots.first.start, DateTime.utc(2026, 11, 23, 7, 0));
      expect(slots.last.start, DateTime.utc(2026, 11, 23, 20, 30));
      expect(slots.last.end, DateTime.utc(2026, 11, 23, 22, 0));
    });

    test('slots are back to back', () {
      final slots = generateSlots(testVenue(), testCourt(slot: 60), monday);
      expect(slots.length, 16);
      for (var i = 0; i < slots.length - 1; i++) {
        expect(slots[i].end, slots[i + 1].start);
      }
    });

    test('a slot ending exactly at closing time is offered', () {
      final slots = generateSlots(testVenue(open: 8 * 60, close: 10 * 60), testCourt(slot: 120), monday);
      expect(slots.single.end, DateTime.utc(2026, 11, 23, 10, 0));
    });

    test('closed day gives no slots', () {
      final venue = testVenue(hours: weekHours(weekdays: null, weekend: const DayHours(480, 1320)));
      expect(generateSlots(venue, testCourt(), monday), isEmpty);
      expect(generateSlots(venue, testCourt(), saturday), isNotEmpty);
    });

    test('court override replaces venue hours, including closed', () {
      final open = testCourt(slot: 60, override: {1: const DayHours(600, 720)});
      expect(generateSlots(testVenue(), open, monday).length, 2);

      final closed = testCourt(override: {1: null});
      expect(generateSlots(testVenue(), closed, monday), isEmpty);
      // Tuesday has no override, so venue hours apply.
      expect(generateSlots(testVenue(), closed, monday.add(const Duration(days: 1))), isNotEmpty);
    });

    test('hours shorter than a slot, or close before open, give no slots', () {
      expect(generateSlots(testVenue(open: 420, close: 480), testCourt(slot: 90), monday), isEmpty);
      expect(generateSlots(testVenue(open: 1200, close: 480), testCourt(slot: 60), monday), isEmpty);
    });

    test('the time of day on the requested date is ignored', () {
      final slots = generateSlots(testVenue(), testCourt(), DateTime.utc(2026, 11, 23, 15, 45));
      expect(slots.first.start, DateTime.utc(2026, 11, 23, 7, 0));
    });
  });

  group('pricing', () {
    final court = testCourt(
      basePrice: 180000,
      rules: const [
        PriceRule(weekdays: {1, 2, 3, 4, 5}, fromMinute: 18 * 60, toMinute: 23 * 60, price: 250000),
        PriceRule(weekdays: {6, 7}, fromMinute: 0, toMinute: 24 * 60, price: 300000),
      ],
    );

    test('rule matching the start time wins', () {
      expect(priceForSlot(court, slotAt(monday, 18, 0)), 250000);
      expect(priceForSlot(court, slotAt(monday, 20, 30)), 250000);
    });

    test('no matching rule uses base price', () {
      expect(priceForSlot(court, slotAt(monday, 10, 0)), 180000);
    });

    test('rule start is inclusive and end is exclusive', () {
      expect(priceForSlot(court, slotAt(monday, 17, 30)), 180000);
      expect(priceForSlot(court, slotAt(monday, 23, 0)), 180000);
    });

    test('weekend rule applies all day', () {
      expect(priceForSlot(court, slotAt(saturday, 9, 0)), 300000);
    });

    test('fee range spans the cheapest and dearest slot of the week', () {
      final venue = testVenue(courts: [court]);
      expect(feeRange(venue, 'padel', monday), (min: 180000, max: 300000));
      expect(feeRange(venue, 'tennis', monday), isNull);
    });
  });
}
