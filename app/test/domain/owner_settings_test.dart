import 'package:actra/core/markets.dart';
import 'package:actra/data/owner_repository.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/owner.dart';
import 'package:actra/domain/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('overlapping rules', () {
    PriceRule rule(Set<int> days, int from, int to) =>
        PriceRule(weekdays: days, fromMinute: from, toMinute: to, price: 1);

    test('rules on different days, or back to back, do not overlap', () {
      expect(overlappingRules([rule({1, 2}, 600, 1200), rule({3}, 600, 1200)]), isEmpty);
      expect(overlappingRules([rule({1}, 600, 1080), rule({1}, 1080, 1440)]), isEmpty);
      expect(overlappingRules(const []), isEmpty);
    });

    test('a shared weekday and intersecting times overlap, reported in order', () {
      final a = rule({1, 2, 3}, 1080, 1440);
      final b = rule({6, 7}, 0, 1440);
      final c = rule({3, 4}, 1200, 1260);
      final d = rule({7}, 600, 700);
      final pairs = overlappingRules([a, b, c, d]);
      expect(pairs, hasLength(2));
      expect(identical(pairs[0].$1, a) && identical(pairs[0].$2, c), isTrue);
      expect(identical(pairs[1].$1, b) && identical(pairs[1].$2, d), isTrue);
    });
  });

  group('dashboard numbers', () {
    test('derived numbers', () {
      const d = OwnerDashboard(
        currency: Currency.uzs,
        days: 7,
        bookingsApp: 2,
        bookingsWalkIn: 2,
        revenuePaid: 100,
        revenueUnconfirmed: 0,
        noShows: 1,
        slotsAvailable: 50,
        slotsBooked: 10,
        heatmap: {},
      );
      expect(d.bookings, 4);
      expect(d.dailyAverage, closeTo(4 / 7, 1e-9));
      expect(d.utilisation, closeTo(0.2, 1e-9));
      expect(d.noShowRate, closeTo(0.25, 1e-9));
    });

    test('nothing offered and nothing booked gives zeros, not NaN', () {
      const d = OwnerDashboard(
        currency: Currency.kzt,
        days: 1,
        bookingsApp: 0,
        bookingsWalkIn: 0,
        revenuePaid: 0,
        revenueUnconfirmed: 0,
        noShows: 0,
        slotsAvailable: 0,
        slotsBooked: 0,
        heatmap: {},
      );
      expect(d.utilisation, 0);
      expect(d.noShowRate, 0);
      expect(d.dailyAverage, 0);
    });
  });

  group('engine dashboard', () {
    late BookingEngine engine;
    final now = DateTime.utc(2026, 11, 22, 20, 0); // Sunday evening
    final sunday = DateTime.utc(2026, 11, 22);
    final tuesday = DateTime.utc(2026, 11, 24);
    final wednesday = DateTime.utc(2026, 11, 25);
    final thursday = DateTime.utc(2026, 11, 26);
    final afterMondayMorning = DateTime.utc(2026, 11, 23, 13, 30);

    setUp(() {
      final venue = testVenue(courts: [
        testCourt(rules: const [PriceRule(weekdays: {1, 2, 3, 4, 5}, fromMinute: 1080, toMinute: 1380, price: 250000)]),
        testCourt(id: 'c2', slot: 60),
      ]);
      engine = BookingEngine(venueById: (_) => venue);

      Booking walkIn(String court, List<SlotTime> slots) => engine.createWalkIn(
        venueId: 'v1',
        courtId: court,
        slots: slots,
        name: 'Guest',
        payment: WalkInPayment.cash,
        now: now,
      );
      Booking app(String user, SlotTime slot) => engine.confirm(
        engine.hold(userId: user, venueId: 'v1', courtId: 'c1', slots: [slot], now: now).id,
        now: now,
      );

      // Counted.
      final paid = app('ali', slotAt(monday, 7, 0));
      engine.mark(paid.id, BookingOutcome.paid, now: afterMondayMorning);
      final noShow = walkIn('c1', [slotAt(monday, 8, 30), slotAt(monday, 10, 0)]);
      engine.mark(noShow.id, BookingOutcome.noShow, now: afterMondayMorning);
      walkIn('c1', [slotAt(tuesday, 19, 0)]);
      walkIn('c2', [slotAt(monday, 7, 0, length: 60)]);

      // Not counted.
      engine.cancel(app('vali', slotAt(wednesday, 7, 0)).id, now: now);
      engine.cancelByVenue(walkIn('c1', [slotAt(wednesday, 8, 30)]).id, now: now);
      engine.blockSlots(venueId: 'v1', courtId: 'c1', slots: [slotAt(monday, 11, 30), slotAt(monday, 13, 0)], now: now);
      final cancelledBlock = engine.blockSlots(venueId: 'v1', courtId: 'c1', slots: [slotAt(thursday, 7, 0)], now: now);
      engine.cancelByVenue(cancelledBlock.id, now: now);
      engine.hold(userId: 'sami', venueId: 'v1', courtId: 'c1', slots: [slotAt(thursday, 8, 30)], now: now);
      walkIn('c1', [slotAt(sunday, 19, 0)]); // the day before the range
    });

    test('one court', () {
      final d = engine.ownerDashboard('v1', courtId: 'c1', from: monday, to: monday.add(const Duration(days: 6)));
      expect(d.currency, Currency.uzs);
      expect(d.days, 7);
      expect(d.bookingsApp, 1);
      expect(d.bookingsWalkIn, 2);
      expect(d.revenuePaid, 180000);
      expect(d.revenueUnconfirmed, 0);
      expect(d.noShows, 1);
      // 10 slots a day for 7 days, minus the two blocked ones.
      expect(d.slotsAvailable, 68);
      expect(d.slotsBooked, 4);
      expect(d.heatmap, {
        (weekday: 1, hour: 7): 1,
        (weekday: 1, hour: 8): 1,
        (weekday: 2, hour: 19): 1,
      });
    });

    test('every court', () {
      final d = engine.ownerDashboard('v1', from: monday, to: monday.add(const Duration(days: 6)));
      expect(d.bookingsWalkIn, 3);
      expect(d.slotsAvailable, 68 + 16 * 7);
      expect(d.slotsBooked, 5);
      expect(d.heatmap[(weekday: 1, hour: 7)], 2);
    });

    test('a single day, and a range in the past', () {
      final d = engine.ownerDashboard('v1', courtId: 'c1', from: sunday, to: sunday);
      expect(d.days, 1);
      expect(d.bookingsWalkIn, 1);
      expect(d.heatmap, {(weekday: 7, hour: 19): 1});
    });

    test('a reversed range or one over 92 days is refused', () {
      expect(
        () => engine.ownerDashboard('v1', from: tuesday, to: monday),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.invalidArgument)),
      );
      expect(
        () => engine.ownerDashboard('v1', from: monday, to: monday.add(const Duration(days: 92))),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.invalidArgument)),
      );
      expect(engine.ownerDashboard('v1', from: monday, to: monday.add(const Duration(days: 91))).days, 92);
    });
  });

  group('sample settings', () {
    // Sunday 22 Nov 2026, 10:00 in Tashkent.
    final utcNow = DateTime.utc(2026, 11, 22, 5, 0);
    final today = DateTime.utc(2026, 11, 22);
    final nextMonday = DateTime.utc(2026, 11, 23);
    late SampleBackend backend;
    late OwnerRepository owner;

    setUp(() {
      backend = SampleBackend(utcNow: () => utcNow, meName: 'Demo');
      owner = backend.owner;
    });

    Future<BookingError> errorOf(Future<void> Function() action) async {
      try {
        await action();
      } on BookingException catch (e) {
        return e.error;
      }
      fail('expected a BookingException');
    }

    WeekHours allWeek(DayHours? h) => {for (var d = 1; d <= 7; d++) d: h};

    test('closing a weekday for the venue empties it for players and the owner', () async {
      await owner.setVenueHours('v1', {...allWeek(const DayHours.hm(8, 0, 22, 0)), 1: null});
      expect(await backend.availability('v1', 'v1c1', nextMonday), isEmpty);
      expect((await owner.calendar('v1', 'v1c1', today, 7)).slotsOn(nextMonday), isEmpty);
      final tuesday = await backend.availability('v1', 'v1c1', nextMonday.add(const Duration(days: 1)));
      expect(tuesday.first.time.start.hour, 8);
      expect((await backend.venue('v1')).hours[1], isNull);
      expect((await owner.myVenues()).firstWhere((v) => v.id == 'v1').hours[2]!.openMinute, 480);
    });

    test('venue hours must cover all seven days with opening before closing', () async {
      final before = (await backend.availability('v1', 'v1c1', nextMonday)).length;
      expect(await errorOf(() => owner.setVenueHours('v1', {...allWeek(const DayHours(420, 1380))}..remove(7))),
          BookingError.invalidHours);
      expect(await errorOf(() => owner.setVenueHours('v1', {...allWeek(const DayHours(420, 1380)), 2: const DayHours(600, 600)})),
          BookingError.invalidHours);
      expect(await errorOf(() => owner.setVenueHours('v1', {...allWeek(const DayHours(420, 1380)), 3: const DayHours(-10, 600)})),
          BookingError.invalidHours);
      expect(await errorOf(() => owner.setVenueHours('v1', {...allWeek(const DayHours(420, 1441))})), BookingError.invalidHours);
      expect(await errorOf(() => owner.setVenueHours('v1', {...allWeek(null), 8: null})), BookingError.invalidHours);
      expect((await backend.availability('v1', 'v1c1', nextMonday)).length, before);
    });

    test('court hours override some days; an empty map follows the venue again', () async {
      await owner.setCourtHours('v1', 'v1c2', {1: const DayHours.hm(10, 0, 13, 0), 2: null});
      expect((await backend.availability('v1', 'v1c2', nextMonday)).map((s) => s.time.start.hour), [10, 11]);
      expect(await backend.availability('v1', 'v1c2', nextMonday.add(const Duration(days: 1))), isEmpty);
      expect(await backend.availability('v1', 'v1c1', nextMonday), hasLength(10));

      await owner.setCourtHours('v1', 'v1c2', const {});
      expect(await backend.availability('v1', 'v1c2', nextMonday), hasLength(10));
      expect(await errorOf(() => owner.setCourtHours('v1', 'v1c2', {1: const DayHours(700, 600)})), BookingError.invalidHours);
      expect(await errorOf(() => owner.setCourtHours('v1', 'v1c2', {0: null})), BookingError.invalidHours);
    });

    test('pricing changes what new bookings cost; existing ones keep their price', () async {
      final slot = (await backend.availability('v1', 'v1c1', nextMonday)).first;
      final held = await backend.hold('v1', 'v1c1', [slot.time]);
      final booked = await backend.confirm(held.id);
      expect(booked.totalPrice, 180000);

      await owner.setCourtPricing('v1', 'v1c1', slotMinutes: 60, basePrice: 150000, rules: const [
        PriceRule(weekdays: {1}, fromMinute: 1200, toMinute: 1440, price: 220000),
      ]);
      final slots = await backend.availability('v1', 'v1c1', nextMonday);
      expect(slots, hasLength(16));
      expect(slots.first.price, 150000);
      expect(slots.last.price, 220000);
      expect((await backend.myBookings()).single.totalPrice, 180000);
      final venue = await backend.venue('v1');
      expect(venue.court('v1c1').slotMinutes, 60);
      expect(venue.court('v1c1').priceRules.single.price, 220000);
      expect(venue.court('v1c2').basePrice, 180000);
    });

    test('pricing validation', () async {
      Future<BookingError> price({int slot = 90, int base = 100, List<PriceRule> rules = const []}) =>
          errorOf(() => owner.setCourtPricing('v1', 'v1c1', slotMinutes: slot, basePrice: base, rules: rules));
      expect(await price(slot: 45), BookingError.invalidArgument);
      expect(await price(base: -1), BookingError.invalidArgument);
      expect(await price(rules: const [PriceRule(weekdays: {}, fromMinute: 0, toMinute: 60, price: 1)]),
          BookingError.invalidArgument);
      expect(await price(rules: const [PriceRule(weekdays: {1}, fromMinute: 0, toMinute: 60, price: -5)]),
          BookingError.invalidArgument);
      expect(await price(rules: const [PriceRule(weekdays: {8}, fromMinute: 0, toMinute: 60, price: 5)]),
          BookingError.invalidArgument);
      expect(await price(rules: const [PriceRule(weekdays: {1}, fromMinute: 600, toMinute: 600, price: 5)]),
          BookingError.invalidArgument);
      expect(
        await price(rules: const [
          PriceRule(weekdays: {1, 2}, fromMinute: 1080, toMinute: 1440, price: 5),
          PriceRule(weekdays: {2}, fromMinute: 1200, toMinute: 1300, price: 6),
        ]),
        BookingError.rulesOverlap,
      );
      expect(await price(base: BookingEngine.maxPrice + 1), BookingError.invalidArgument);
      expect(
        await price(rules: const [PriceRule(weekdays: {1}, fromMinute: 0, toMinute: 60, price: BookingEngine.maxPrice + 1)]),
        BookingError.invalidArgument,
      );
      // Nothing was saved.
      expect((await backend.venue('v1')).court('v1c1').basePrice, 180000);
    });

    test('settings and the dashboard of a venue the demo player does not manage are refused', () async {
      expect(await errorOf(() => owner.setVenueHours('v2', allWeek(null))), BookingError.notAllowed);
      expect(await errorOf(() => owner.setCourtHours('v2', 'v2c1', const {})), BookingError.notAllowed);
      expect(
        await errorOf(() => owner.setCourtPricing('v2', 'v2c1', slotMinutes: 60, basePrice: 1, rules: const [])),
        BookingError.notAllowed,
      );
      expect(await errorOf(() => owner.dashboard('v2', from: today, to: today)), BookingError.notAllowed);
      expect((await backend.venue('v2')).hours[1], isNotNull);
    });

    test("the dashboard counts today's walk-in", () async {
      final free = (await backend.availability('v1', 'v1c1', today)).firstWhere((s) => s.state == SlotState.free);
      await owner.createWalkIn('v1', 'v1c1', [free.time], name: 'Rustam', payment: WalkInPayment.cash);
      final d = await owner.dashboard('v1', courtId: 'v1c1', from: today, to: today);
      expect(d.bookingsWalkIn, 1);
      expect(d.currency, Currency.uzs);
      expect(d.heatmap[(weekday: today.weekday, hour: free.time.start.hour)], 1);
      final all = await owner.dashboard('v1', from: today, to: today.add(const Duration(days: 6)));
      expect(all.bookingsWalkIn, greaterThanOrEqualTo(1));
      expect(all.days, 7);
    });
  });
}
