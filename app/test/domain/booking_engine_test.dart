import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late Venue venue;
  late BookingEngine engine;

  // Sunday evening: every Monday slot is in the future.
  final now = DateTime.utc(2026, 11, 22, 20, 0);

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

  Booking hold(String user, List<SlotTime> slots, {DateTime? at}) =>
      engine.hold(userId: user, venueId: 'v1', courtId: 'c1', slots: slots, now: at ?? now);

  SlotState stateOf(SlotTime slot, {String? user, DateTime? at}) => engine
      .availability('v1', 'c1', slot.start, now: at ?? now, userId: user)
      .firstWhere((v) => v.time == slot)
      .state;

  test('hold then confirm locks the summed price', () {
    // 17:30 is base price, 19:00 falls under the evening rule.
    final held = hold('ali', [slotAt(monday, 17, 30), slotAt(monday, 19, 0)]);
    expect(held.status, BookingStatus.held);
    expect(held.totalPrice, 180000 + 250000);
    expect(held.holdExpiresAt, now.add(const Duration(minutes: 5)));

    final confirmed = engine.confirm(held.id, now: now.add(const Duration(minutes: 2)), players: 4);
    expect(confirmed.status, BookingStatus.confirmed);
    expect(confirmed.paymentMethod, PaymentMethod.payAtVenue);
    expect(confirmed.paymentStatus, PaymentStatus.unpaid);
    expect(confirmed.slotCount, 2);
    expect(confirmed.players, 4);
    expect(confirmed.start, DateTime.utc(2026, 11, 23, 17, 30));
    expect(confirmed.end, DateTime.utc(2026, 11, 23, 20, 30));
  });

  test('a second player cannot hold a held slot', () {
    final slot = slotAt(monday, 7, 0);
    hold('ali', [slot]);
    expect(errorOf(() => hold('vali', [slot])), BookingError.slotTaken);
    expect(stateOf(slot, user: 'vali'), SlotState.taken);
    expect(stateOf(slot, user: 'ali'), SlotState.mine);
  });

  test('overlap is caught when only part of the selection is taken', () {
    hold('ali', [slotAt(monday, 8, 30)]);
    expect(errorOf(() => hold('vali', [slotAt(monday, 7, 0), slotAt(monday, 8, 30)])), BookingError.slotTaken);
  });

  test('a confirmed slot stays taken for everyone', () {
    final slot = slotAt(monday, 7, 0);
    engine.confirm(hold('ali', [slot]).id, now: now);
    expect(stateOf(slot, user: 'ali'), SlotState.taken);
    expect(errorOf(() => hold('vali', [slot])), BookingError.slotTaken);
  });

  test('an expired hold cannot be confirmed and frees the slot', () {
    final slot = slotAt(monday, 7, 0);
    final held = hold('ali', [slot]);
    final later = now.add(const Duration(minutes: 5));
    expect(stateOf(slot, user: 'vali', at: later), SlotState.free);
    expect(errorOf(() => engine.confirm(held.id, now: later)), BookingError.holdExpired);
    expect(hold('vali', [slot], at: later).status, BookingStatus.held);
  });

  test('release frees a held slot', () {
    final slot = slotAt(monday, 7, 0);
    engine.release(hold('ali', [slot]).id);
    expect(stateOf(slot, user: 'vali'), SlotState.free);
  });

  test('a new hold replaces the same player\'s previous hold', () {
    final first = slotAt(monday, 7, 0);
    hold('ali', [first]);
    hold('ali', [slotAt(monday, 10, 0)]);
    expect(stateOf(first, user: 'vali'), SlotState.free);
  });

  test('non-adjacent slots are refused', () {
    expect(errorOf(() => hold('ali', [slotAt(monday, 7, 0), slotAt(monday, 10, 0)])), BookingError.notContiguous);
  });

  test('slots may be passed in any order', () {
    final held = hold('ali', [slotAt(monday, 8, 30), slotAt(monday, 7, 0)]);
    expect(held.start, DateTime.utc(2026, 11, 23, 7, 0));
  });

  test('an empty selection is refused', () {
    expect(errorOf(() => hold('ali', [])), BookingError.emptySelection);
  });

  test('a time that is not one of the court\'s slots is refused', () {
    expect(errorOf(() => hold('ali', [slotAt(monday, 7, 15)])), BookingError.notFound);
  });

  test('past slots cannot be held and show as past', () {
    final midday = DateTime.utc(2026, 11, 23, 12, 0);
    final slot = slotAt(monday, 7, 0);
    expect(errorOf(() => hold('ali', [slot], at: midday)), BookingError.inPast);
    expect(stateOf(slot, at: midday), SlotState.past);
    // A slot that has already started is past too.
    expect(stateOf(slotAt(monday, 11, 30), at: midday), SlotState.past);
  });

  test('more than 14 days ahead is refused, 14 is allowed', () {
    final day14 = DateTime.utc(2026, 12, 6);
    final day15 = DateTime.utc(2026, 12, 7);
    expect(hold('ali', [slotAt(day14, 8, 30)]).status, BookingStatus.held);
    expect(errorOf(() => hold('ali', [slotAt(day15, 7, 0)])), BookingError.tooFarAhead);
  });

  test('a fourth upcoming booking is refused', () {
    for (final hour in [7, 10, 13]) {
      engine.confirm(hold('ali', [slotAt(monday, hour, 0)]).id, now: now);
    }
    expect(errorOf(() => hold('ali', [slotAt(monday, 16, 0)])), BookingError.tooManyBookings);
    // Another player is unaffected.
    expect(hold('vali', [slotAt(monday, 16, 0)]).status, BookingStatus.held);
  });

  test('cancelling early is free and reopens the slot', () {
    final slot = slotAt(monday, 7, 0);
    final booking = engine.confirm(hold('ali', [slot]).id, now: now);
    final cancelled = engine.cancel(booking.id, now: DateTime.utc(2026, 11, 23, 0, 0));
    expect(cancelled.status, BookingStatus.cancelledByPlayer);
    expect(cancelled.lateCancellation, isFalse);
    expect(stateOf(slot, user: 'vali'), SlotState.free);
  });

  test('cancelling inside 6 hours is flagged late', () {
    final booking = engine.confirm(hold('ali', [slotAt(monday, 7, 0)]).id, now: now);
    final cancelled = engine.cancel(booking.id, now: DateTime.utc(2026, 11, 23, 5, 0));
    expect(cancelled.lateCancellation, isTrue);
  });

  test('a started or already cancelled booking cannot be cancelled', () {
    final booking = engine.confirm(hold('ali', [slotAt(monday, 7, 0)]).id, now: now);
    expect(errorOf(() => engine.cancel(booking.id, now: DateTime.utc(2026, 11, 23, 7, 0))), BookingError.notCancellable);
    engine.cancel(booking.id, now: now);
    expect(errorOf(() => engine.cancel(booking.id, now: now)), BookingError.notCancellable);
    expect(errorOf(() => engine.cancel('nope', now: now)), BookingError.notFound);
  });

  test('a later price change does not touch an existing booking', () {
    final booking = engine.confirm(hold('ali', [slotAt(monday, 7, 0)]).id, now: now);
    venue = venue.copyWith(courts: [venue.courts.single.copyWith(basePrice: 999000)]);
    expect(engine.byId(booking.id)!.totalPrice, 180000);
    expect(hold('vali', [slotAt(monday, 10, 0)]).totalPrice, 999000);
  });

  test('bookingsOf lists confirmed and cancelled bookings, not holds', () {
    engine.confirm(hold('ali', [slotAt(monday, 7, 0)]).id, now: now);
    hold('ali', [slotAt(monday, 10, 0)]);
    expect(engine.bookingsOf('ali').length, 1);
    expect(engine.bookingsOf('vali'), isEmpty);
  });
}
