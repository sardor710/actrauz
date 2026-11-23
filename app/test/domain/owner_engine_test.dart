import 'package:actra/core/markets.dart';
import 'package:actra/data/owner_repository.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/owner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late Venue venue;
  late BookingEngine engine;

  // Sunday evening: every Monday slot is in the future. Sunday's 17:30 slot
  // has ended, the 19:00 one is under way, the 20:30 one has not started.
  final now = DateTime.utc(2026, 11, 22, 20, 0);
  final sunday = DateTime.utc(2026, 11, 22);

  setUp(() {
    venue = testVenue(
      courts: [
        testCourt(
          rules: const [PriceRule(weekdays: {1, 2, 3, 4, 5}, fromMinute: 1080, toMinute: 1380, price: 250000)],
        ),
      ],
    );
    engine = BookingEngine(venueById: (_) => venue);
  });

  BookingError errorOf(void Function() action) {
    try {
      action();
    } on BookingException catch (e) {
      return e.error;
    }
    fail('expected a BookingException');
  }

  Booking walkIn(
    List<SlotTime> slots, {
    String name = 'Rustam',
    String? phone = '+998 90 123 45 67',
    int? players = 4,
    WalkInPayment payment = WalkInPayment.cash,
    DateTime? at,
  }) => engine.createWalkIn(
    venueId: 'v1',
    courtId: 'c1',
    slots: slots,
    name: name,
    phone: phone,
    players: players,
    payment: payment,
    now: at ?? now,
  );

  Booking block(List<SlotTime> slots, {String? reason = 'Repairs', DateTime? at}) =>
      engine.blockSlots(venueId: 'v1', courtId: 'c1', slots: slots, reason: reason, now: at ?? now);

  Booking appBooking(String user, List<SlotTime> slots, {DateTime? at}) {
    final held = engine.hold(userId: user, venueId: 'v1', courtId: 'c1', slots: slots, now: at ?? now);
    return engine.confirm(held.id, now: at ?? now);
  }

  SlotState playerState(SlotTime slot, {String? user = 'vali'}) =>
      engine.availability('v1', 'c1', slot.start, now: now, userId: user).firstWhere((v) => v.time == slot).state;

  OwnerCalendar calendar({DateTime? from, int days = 7, DateTime? at, String Function(String)? nameOf}) =>
      engine.ownerCalendar('v1', 'c1', from ?? monday, days, now: at ?? now, nameOf: nameOf);

  OwnerSlot ownerSlot(OwnerCalendar cal, SlotTime slot) => cal.slots.firstWhere((s) => s.time == slot);

  group('walk-in', () {
    test('is confirmed at once with the summed price and the guest details', () {
      final b = walkIn([slotAt(monday, 17, 30), slotAt(monday, 19, 0)], payment: WalkInPayment.card);
      expect(b.status, BookingStatus.confirmed);
      expect(b.source, BookingSource.walkIn);
      expect(b.userId, '');
      expect(b.totalPrice, 180000 + 250000);
      expect(b.slotCount, 2);
      expect(b.start, DateTime.utc(2026, 11, 23, 17, 30));
      expect(b.end, DateTime.utc(2026, 11, 23, 20, 30));
      expect(b.guestName, 'Rustam');
      expect(b.guestPhone, '+998 90 123 45 67');
      expect(b.players, 4);
      expect(b.walkInPayment, WalkInPayment.card);
      expect(b.paymentStatus, PaymentStatus.unpaid);
      expect(b.holdExpiresAt, isNull);
    });

    test('shows as taken to players, and a player cannot hold it', () {
      final slot = slotAt(monday, 7, 0);
      walkIn([slot]);
      expect(playerState(slot), SlotState.taken);
      expect(
        errorOf(() => engine.hold(userId: 'vali', venueId: 'v1', courtId: 'c1', slots: [slot], now: now)),
        BookingError.slotTaken,
      );
    });

    test('cannot take a slot a player already has, held or confirmed', () {
      final held = slotAt(monday, 7, 0);
      engine.hold(userId: 'ali', venueId: 'v1', courtId: 'c1', slots: [held], now: now);
      expect(errorOf(() => walkIn([held])), BookingError.slotTaken);

      final confirmed = slotAt(monday, 8, 30);
      appBooking('ali', [confirmed]);
      expect(errorOf(() => walkIn([confirmed])), BookingError.slotTaken);
      expect(errorOf(() => walkIn([slotAt(monday, 10, 0)]..insert(0, confirmed))), BookingError.slotTaken);
    });

    test('needs a name', () {
      expect(errorOf(() => walkIn([slotAt(monday, 7, 0)], name: '')), BookingError.nameRequired);
      expect(errorOf(() => walkIn([slotAt(monday, 7, 0)], name: '   ')), BookingError.nameRequired);
    });

    test('name is trimmed, and phone and players are optional', () {
      final b = walkIn([slotAt(monday, 7, 0)], name: '  Rustam ', phone: null, players: null);
      expect(b.guestName, 'Rustam');
      expect(b.guestPhone, isNull);
      expect(b.players, isNull);
    });

    test('is allowed on a slot that has started but not ended', () {
      final b = walkIn([slotAt(sunday, 19, 0)]);
      expect(b.status, BookingStatus.confirmed);
    });

    test('is refused on a slot that has ended', () {
      expect(errorOf(() => walkIn([slotAt(sunday, 17, 30)])), BookingError.inPast);
    });

    test('is refused when the first slot has ended, even if a later one has not', () {
      expect(errorOf(() => walkIn([slotAt(sunday, 17, 30), slotAt(sunday, 19, 0)])), BookingError.inPast);
      expect(errorOf(() => block([slotAt(sunday, 17, 30), slotAt(sunday, 19, 0)])), BookingError.inPast);
      // An under-way first slot is still fine.
      expect(walkIn([slotAt(sunday, 19, 0), slotAt(sunday, 20, 30)]).slotCount, 2);
    });

    test('limits: name length, players, slot count', () {
      final slot = slotAt(monday, 7, 0);
      expect(errorOf(() => walkIn([slot], name: 'a' * 81)), BookingError.invalidArgument);
      expect(errorOf(() => walkIn([slot], players: 0)), BookingError.invalidArgument);
      expect(errorOf(() => walkIn([slot], players: 101)), BookingError.invalidArgument);
      final many = [for (var i = 0; i < 25; i++) slot];
      expect(errorOf(() => walkIn(many)), BookingError.invalidArgument);
      expect(errorOf(() => block(many)), BookingError.invalidArgument);
      expect(walkIn([slot], name: 'a' * 80, players: 100).players, 100);
      expect(walkIn([slotAt(monday, 8, 30)], players: 1).players, 1);
    });

    test('is refused on a time that is not one of the court slots', () {
      expect(errorOf(() => walkIn([slotAt(monday, 7, 30)])), BookingError.notFound);
    });

    test('needs contiguous, non-empty slots within 14 days', () {
      expect(errorOf(() => walkIn([slotAt(monday, 7, 0), slotAt(monday, 10, 0)])), BookingError.notContiguous);
      expect(errorOf(() => walkIn([])), BookingError.emptySelection);
      expect(errorOf(() => walkIn([slotAt(monday.add(const Duration(days: 14)), 7, 0)])), BookingError.tooFarAhead);
      expect(walkIn([slotAt(monday.add(const Duration(days: 13)), 7, 0)]).status, BookingStatus.confirmed);
    });

    test('has no cap on upcoming bookings', () {
      for (final hm in const [(7, 0), (8, 30), (10, 0), (11, 30), (13, 0)]) {
        walkIn([slotAt(monday, hm.$1, hm.$2)]);
      }
      expect(calendar(days: 1).slots.where((s) => s.state == OwnerSlotState.booked), hasLength(5));
    });
  });

  group('block', () {
    test('is a confirmed, free-of-charge row with a reason', () {
      final b = block([slotAt(monday, 7, 0), slotAt(monday, 8, 30)]);
      expect(b.status, BookingStatus.confirmed);
      expect(b.source, BookingSource.block);
      expect(b.userId, '');
      expect(b.totalPrice, 0);
      expect(b.slotCount, 2);
      expect(b.blockReason, 'Repairs');
      expect(b.guestName, isNull);
    });

    test('shows as taken to players and stops walk-ins', () {
      final slot = slotAt(monday, 7, 0);
      block([slot], reason: null);
      expect(playerState(slot), SlotState.taken);
      expect(errorOf(() => walkIn([slot])), BookingError.slotTaken);
      expect(errorOf(() => block([slot])), BookingError.slotTaken);
    });

    test('follows the same slot rules as a walk-in', () {
      expect(errorOf(() => block([slotAt(sunday, 17, 30)])), BookingError.inPast);
      expect(errorOf(() => block([slotAt(monday, 7, 30)])), BookingError.notFound);
      expect(errorOf(() => block([slotAt(monday, 7, 0), slotAt(monday, 10, 0)])), BookingError.notContiguous);
      expect(errorOf(() => block([])), BookingError.emptySelection);
      expect(block([slotAt(sunday, 19, 0)]).status, BookingStatus.confirmed);
    });

    test('a reason over 200 characters is refused', () {
      expect(errorOf(() => block([slotAt(monday, 7, 0)], reason: 'r' * 201)), BookingError.invalidArgument);
      expect(block([slotAt(monday, 7, 0)], reason: 'r' * 200).blockReason, hasLength(200));
    });
  });

  group('player cancel', () {
    test('a player cannot cancel a walk-in or a block', () {
      final w = walkIn([slotAt(monday, 7, 0)]);
      final b = block([slotAt(monday, 8, 30)]);
      expect(errorOf(() => engine.cancel(w.id, now: now)), BookingError.notCancellable);
      expect(errorOf(() => engine.cancel(b.id, now: now)), BookingError.notCancellable);
      expect(engine.byId(w.id)!.status, BookingStatus.confirmed);
      expect(engine.byId(b.id)!.status, BookingStatus.confirmed);
    });
  });

  group('cancel by venue', () {
    test('frees the slot at once and never flags the player', () {
      final slot = slotAt(sunday, 20, 30); // starts in 30 minutes
      final b = appBooking('ali', [slot]);
      final cancelled = engine.cancelByVenue(b.id, now: now);
      expect(cancelled.status, BookingStatus.cancelledByVenue);
      expect(cancelled.lateCancellation, isFalse);
      expect(playerState(slot), SlotState.free);
      expect(ownerSlot(calendar(from: sunday, days: 1), slot).state, OwnerSlotState.free);
    });

    test('a second cancel is refused', () {
      final b = walkIn([slotAt(monday, 7, 0)]);
      engine.cancelByVenue(b.id, now: now);
      expect(errorOf(() => engine.cancelByVenue(b.id, now: now)), BookingError.notCancellable);
    });

    test('a cancelled block frees its slots; cancelling it again is refused', () {
      final slots = [slotAt(monday, 7, 0), slotAt(monday, 8, 30)];
      final b = block(slots);
      expect(engine.cancelByVenue(b.id, now: now).status, BookingStatus.cancelledByVenue);
      for (final s in slots) {
        expect(playerState(s), SlotState.free);
      }
      expect(walkIn(slots).status, BookingStatus.confirmed);
      expect(errorOf(() => engine.cancelByVenue(b.id, now: now)), BookingError.notCancellable);
    });

    test('is allowed while under way, refused once ended', () {
      final running = walkIn([slotAt(sunday, 19, 0)]);
      expect(engine.cancelByVenue(running.id, now: now).status, BookingStatus.cancelledByVenue);

      final b = walkIn([slotAt(monday, 7, 0)]);
      expect(
        errorOf(() => engine.cancelByVenue(b.id, now: DateTime.utc(2026, 11, 23, 8, 30))),
        BookingError.notCancellable,
      );
    });

    test('a player-cancelled booking and an unknown id are refused', () {
      final b = appBooking('ali', [slotAt(monday, 7, 0)]);
      engine.cancel(b.id, now: now);
      expect(errorOf(() => engine.cancelByVenue(b.id, now: now)), BookingError.notCancellable);
      expect(errorOf(() => engine.cancelByVenue('nope', now: now)), BookingError.notFound);
    });
  });

  group('mark', () {
    final afterStart = DateTime.utc(2026, 11, 23, 7, 15);

    test('paid before the start is refused', () {
      final b = walkIn([slotAt(monday, 7, 0)]);
      expect(errorOf(() => engine.mark(b.id, BookingOutcome.paid, now: now)), BookingError.notMarkable);
      expect(engine.byId(b.id)!.status, BookingStatus.confirmed);
    });

    test('paid after the start sets status and payment', () {
      final b = appBooking('ali', [slotAt(monday, 7, 0)]);
      final paid = engine.mark(b.id, BookingOutcome.paid, now: afterStart);
      expect(paid.status, BookingStatus.paid);
      expect(paid.paymentStatus, PaymentStatus.paid);
    });

    test('no-show leaves it unpaid, and a marked booking can be re-marked', () {
      final b = walkIn([slotAt(monday, 7, 0)]);
      engine.mark(b.id, BookingOutcome.paid, now: afterStart);
      final noShow = engine.mark(b.id, BookingOutcome.noShow, now: afterStart);
      expect(noShow.status, BookingStatus.noShow);
      expect(noShow.paymentStatus, PaymentStatus.unpaid);
      expect(engine.mark(b.id, BookingOutcome.paid, now: afterStart).status, BookingStatus.paid);
    });

    test('is allowed long after the end, on completed bookings too', () {
      final b = walkIn([slotAt(monday, 7, 0)]);
      final later = DateTime.utc(2026, 11, 30, 12, 0);
      expect(engine.mark(b.id, BookingOutcome.paid, now: later).status, BookingStatus.paid);
    });

    test('blocks, cancelled bookings and unknown ids cannot be marked', () {
      final blocked = block([slotAt(monday, 8, 30)]);
      expect(errorOf(() => engine.mark(blocked.id, BookingOutcome.paid, now: afterStart.add(const Duration(hours: 2)))), BookingError.notMarkable);

      final cancelled = walkIn([slotAt(monday, 10, 0)]);
      engine.cancelByVenue(cancelled.id, now: now);
      expect(errorOf(() => engine.mark(cancelled.id, BookingOutcome.paid, now: afterStart.add(const Duration(hours: 4)))), BookingError.notMarkable);

      expect(errorOf(() => engine.mark('nope', BookingOutcome.paid, now: afterStart)), BookingError.notFound);
    });

    test('a marked booking keeps the slot taken', () {
      final slot = slotAt(sunday, 19, 0);
      final b = walkIn([slot]);
      engine.mark(b.id, BookingOutcome.noShow, now: now);
      expect(ownerSlot(calendar(from: sunday, days: 1), slot).state, OwnerSlotState.booked);
    });
  });

  group('owner calendar', () {
    test('covers the requested days, one slot list per day', () {
      final cal = calendar();
      // 07:00 to 20:30, every 90 minutes: 10 slots a day.
      for (var d = 0; d < 7; d++) {
        final day = monday.add(Duration(days: d));
        expect(cal.slotsOn(day), hasLength(10), reason: '$day');
        expect(cal.slotsOn(day).every((s) => dateOnly(s.time.start) == day), isTrue);
      }
      expect(cal.slots, hasLength(70));
      expect(cal.slotsOn(monday.add(const Duration(days: 7))), isEmpty);
      expect(cal.slotsOn(DateTime.utc(2026, 11, 23, 15, 45)), hasLength(10));
    });

    test('prices come from the court rules', () {
      final cal = calendar(days: 1);
      expect(ownerSlot(cal, slotAt(monday, 7, 0)).price, 180000);
      expect(ownerSlot(cal, slotAt(monday, 19, 0)).price, 250000);
    });

    test('free, past, booked and blocked', () {
      final booked = slotAt(sunday, 20, 30);
      final blocked = slotAt(monday, 7, 0);
      appBooking('ali', [booked]);
      block([blocked]);
      final cal = calendar(from: sunday, days: 2);

      expect(ownerSlot(cal, slotAt(sunday, 17, 30)).state, OwnerSlotState.past);
      expect(ownerSlot(cal, slotAt(sunday, 17, 30)).bookingId, isNull);
      // Under way and nobody on it: still free to sell.
      expect(ownerSlot(cal, slotAt(sunday, 19, 0)).state, OwnerSlotState.free);
      expect(ownerSlot(cal, booked).state, OwnerSlotState.booked);
      expect(ownerSlot(cal, booked).bookingId, isNotNull);
      expect(ownerSlot(cal, blocked).state, OwnerSlotState.blocked);
      expect(ownerSlot(cal, slotAt(monday, 8, 30)).state, OwnerSlotState.free);
      expect(ownerSlot(cal, slotAt(monday, 8, 30)).bookingId, isNull);
    });

    test('a booked slot stays booked after it has ended', () {
      final slot = slotAt(monday, 7, 0);
      walkIn([slot]);
      final cal = calendar(days: 1, at: DateTime.utc(2026, 11, 23, 12, 0));
      expect(ownerSlot(cal, slot).state, OwnerSlotState.booked);
      expect(ownerSlot(cal, slotAt(monday, 8, 30)).state, OwnerSlotState.past);
    });

    test('a booked slot carries the customer name', () {
      final app = slotAt(monday, 7, 0);
      final guest = slotAt(monday, 8, 30);
      final blocked = slotAt(monday, 10, 0);
      appBooking('ali', [app]);
      walkIn([guest], name: 'Rustam', phone: '+998 90 000 00 00');
      block([blocked], reason: 'Tournament');
      final cal = calendar(days: 1, nameOf: (id) => id == 'ali' ? 'Ali Valiyev' : '?');

      final appBooked = cal.bookings[ownerSlot(cal, app).bookingId]!;
      expect(appBooked.customerName, 'Ali Valiyev');
      expect(appBooked.source, BookingSource.app);
      expect(appBooked.walkInPayment, isNull);

      final guestBooked = cal.bookings[ownerSlot(cal, guest).bookingId]!;
      expect(guestBooked.customerName, 'Rustam');
      expect(guestBooked.customerPhone, '+998 90 000 00 00');
      expect(guestBooked.source, BookingSource.walkIn);
      expect(guestBooked.walkInPayment, WalkInPayment.cash);
      expect(guestBooked.players, 4);
      expect(guestBooked.totalPrice, 180000);

      final block_ = cal.bookings[ownerSlot(cal, blocked).bookingId]!;
      expect(block_.customerName, isNull);
      expect(block_.reason, 'Tournament');
      expect(block_.source, BookingSource.block);
      expect(block_.isBlock, isTrue);
    });

    test('a multi-slot booking is one entry referenced by every slot it covers', () {
      final slots = [slotAt(monday, 7, 0), slotAt(monday, 8, 30)];
      final b = walkIn(slots);
      final cal = calendar(days: 1);
      expect(ownerSlot(cal, slots[0]).bookingId, b.id);
      expect(ownerSlot(cal, slots[1]).bookingId, b.id);
      expect(cal.bookings.keys, [b.id]);
      expect(cal.bookings[b.id]!.slotCount, 2);
    });

    test('cancelled rows do not appear', () {
      final b = walkIn([slotAt(monday, 7, 0)]);
      engine.cancelByVenue(b.id, now: now);
      final cal = calendar(days: 1);
      expect(cal.bookings, isEmpty);
      expect(cal.slots.every((s) => s.state == OwnerSlotState.free), isTrue);
    });

    test('app bookings without a name lookup have no customer name', () {
      appBooking('ali', [slotAt(monday, 7, 0)]);
      final cal = calendar(days: 1);
      expect(cal.bookings.values.single.customerName, isNull);
    });
  });

  group('sample backend as owner', () {
    // Sunday 22 Nov 2026, 10:00 in all three cities.
    final utcNow = DateTime.utc(2026, 11, 22, 5, 0);
    late SampleBackend backend;
    late OwnerRepository owner;

    setUp(() {
      backend = SampleBackend(utcNow: () => utcNow, meName: 'Demo Player');
      owner = backend.owner;
    });

    Future<BookingError> asyncErrorOf(Future<void> Function() action) async {
      try {
        await action();
      } on BookingException catch (e) {
        return e.error;
      }
      fail('expected a BookingException');
    }

    test('my venues are the owned sample venues', () async {
      final venues = await owner.myVenues();
      expect(venues.map((v) => v.id).toSet(), kSampleOwnedVenueIds);
    });

    test('a player booking made in the demo shows in the owner calendar with the session name', () async {
      final v = kSampleVenues.firstWhere((v) => v.id == 'v1');
      final court = v.courts.first;
      final today = dateOnly(venueNow(cityById(v.cityId), utcNow: utcNow));
      final tomorrow = today.add(const Duration(days: 1));
      final slot = (await backend.availability(v.id, court.id, tomorrow)).firstWhere((s) => s.state == SlotState.free);
      final held = await backend.hold(v.id, court.id, [slot.time]);
      await backend.confirm(held.id);

      final cal = await owner.calendar(v.id, court.id, today, 7);
      final cell = cal.slots.firstWhere((s) => s.time == slot.time);
      expect(cell.state, OwnerSlotState.booked);
      expect(cal.bookings[cell.bookingId]!.customerName, 'Demo Player');
      expect(cal.slots.map((s) => dateOnly(s.time.start)).toSet().length, lessThanOrEqualTo(7));
    });

    test('sample game bookings carry the sample player name', () async {
      final seed = kGameSeeds.firstWhere((g) => kSampleOwnedVenueIds.contains(g.venueId) && g.daysAhead <= 5);
      final v = kSampleVenues.firstWhere((v) => v.id == seed.venueId);
      final today = dateOnly(venueNow(cityById(v.cityId), utcNow: utcNow));
      final cal = await owner.calendar(v.id, seed.courtId, today, 7);
      final hostName = kSamplePlayers.firstWhere((p) => p.id == seed.participantIds.first).name;
      expect(cal.bookings.values.map((b) => b.customerName), contains(hostName));
    });

    test('walk-in, block, mark and cancel go through the shared engine', () async {
      final v = kSampleVenues.firstWhere((v) => v.id == 'v1');
      final court = v.courts.first;
      final tomorrow = dateOnly(venueNow(cityById(v.cityId), utcNow: utcNow)).add(const Duration(days: 1));
      final free = (await backend.availability(v.id, court.id, tomorrow)).where((s) => s.state == SlotState.free).toList();

      final w = await owner.createWalkIn(v.id, court.id, [free[0].time], name: 'Rustam', payment: WalkInPayment.transfer);
      expect(w.source, BookingSource.walkIn);
      expect(w.customerName, 'Rustam');
      expect(w.walkInPayment, WalkInPayment.transfer);
      expect(
        (await backend.availability(v.id, court.id, tomorrow)).firstWhere((s) => s.time == free[0].time).state,
        SlotState.taken,
      );

      final b = await owner.blockSlots(v.id, court.id, [free[1].time], reason: 'Repairs');
      expect(b.source, BookingSource.block);
      expect(b.reason, 'Repairs');

      expect(await asyncErrorOf(() => owner.mark(w.id, BookingOutcome.paid)), BookingError.notMarkable);
      expect((await owner.cancel(b.id)).status, BookingStatus.cancelledByVenue);
      expect(await asyncErrorOf(() => owner.cancel(b.id)), BookingError.notCancellable);
    });

    test('venues the demo player does not manage are refused', () async {
      final v = kSampleVenues.firstWhere((v) => !kSampleOwnedVenueIds.contains(v.id));
      final court = v.courts.first;
      final today = dateOnly(venueNow(cityById(v.cityId), utcNow: utcNow));
      expect(await asyncErrorOf(() => owner.calendar(v.id, court.id, today, 7)), BookingError.notAllowed);
      final slot = (await backend.availability(v.id, court.id, today.add(const Duration(days: 1))))
          .firstWhere((s) => s.state == SlotState.free);
      expect(
        await asyncErrorOf(() => owner.createWalkIn(v.id, court.id, [slot.time], name: 'X', payment: WalkInPayment.cash)),
        BookingError.notAllowed,
      );
      expect(await asyncErrorOf(() => owner.blockSlots(v.id, court.id, [slot.time])), BookingError.notAllowed);
      expect(
        (await backend.availability(v.id, court.id, today.add(const Duration(days: 1))))
            .firstWhere((s) => s.time == slot.time)
            .state,
        SlotState.free,
      );

      // A booking at that venue cannot be cancelled or marked either.
      final held = await backend.hold(v.id, court.id, [slot.time]);
      await backend.confirm(held.id);
      expect(await asyncErrorOf(() => owner.cancel(held.id)), BookingError.notAllowed);
      expect(await asyncErrorOf(() => owner.mark(held.id, BookingOutcome.paid)), BookingError.notAllowed);
      expect(await asyncErrorOf(() => owner.cancel('nope')), BookingError.notFound);
    });
  });
}
