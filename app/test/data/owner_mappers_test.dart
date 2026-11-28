import 'package:actra/core/markets.dart';
import 'package:actra/data/supabase/errors.dart';
import 'package:actra/data/supabase/mappers.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/owner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The JSON `app.owner_booking_json` returns: every key of a player booking,
/// plus the owner-only ones.
Map<String, dynamic> ownerBookingJson({
  String id = 'booking-1',
  String source = 'walk_in',
  String status = 'confirmed',
  String? payment = 'cash',
  String? name = 'Rustam',
  String? phone = '+998 90 123 45 67',
  String? reason,
  String starts = '2026-11-23T17:30:00',
  String ends = '2026-11-23T20:30:00',
}) => {
  'id': id,
  'user_id': source == 'app' ? '22222222-2222-2222-2222-222222222222' : null,
  'venue_id': 'venue-1',
  'court_id': 'court-a',
  'starts_local': starts,
  'ends_local': ends,
  'slot_count': 2,
  'total_price': source == 'block' ? 0 : 430000,
  'currency': 'UZS',
  'status': status,
  'payment_method': 'pay_at_venue',
  'payment_status': status == 'paid' ? 'paid' : 'unpaid',
  'hold_expires_local': null,
  'late_cancellation': false,
  'players': source == 'block' ? null : 4,
  'note': null,
  'source': source,
  'walk_in_payment': payment,
  'customer_name': name,
  'customer_phone': phone,
  'reason': reason,
};

Map<String, dynamic> slotJson(String starts, String ends, String state, {String? bookingId, int price = 180000}) => {
  'starts_local': starts,
  'ends_local': ends,
  'price': price,
  'state': state,
  'booking_id': bookingId,
};

void main() {
  group('owner booking', () {
    test('a walk-in keeps the guest details and its payment method', () {
      final b = ownerBookingFromJson(ownerBookingJson(payment: 'card'));
      expect(b.id, 'booking-1');
      expect(b.venueId, 'venue-1');
      expect(b.courtId, 'court-a');
      expect(b.start, DateTime.utc(2026, 11, 23, 17, 30));
      expect(b.end, DateTime.utc(2026, 11, 23, 20, 30));
      expect(b.start.isUtc, isTrue);
      expect(b.slotCount, 2);
      expect(b.totalPrice, 430000);
      expect(b.status, BookingStatus.confirmed);
      expect(b.source, BookingSource.walkIn);
      expect(b.paymentStatus, PaymentStatus.unpaid);
      expect(b.walkInPayment, WalkInPayment.card);
      expect(b.customerName, 'Rustam');
      expect(b.customerPhone, '+998 90 123 45 67');
      expect(b.players, 4);
      expect(b.note, isNull);
      expect(b.reason, isNull);
      expect(b.isBlock, isFalse);
    });

    test('every source and payment method', () {
      expect(ownerBookingFromJson(ownerBookingJson(source: 'app', payment: null)).source, BookingSource.app);
      expect(ownerBookingFromJson(ownerBookingJson(source: 'walk_in')).source, BookingSource.walkIn);
      expect(ownerBookingFromJson(ownerBookingJson(source: 'block')).source, BookingSource.block);
      expect(ownerBookingFromJson(ownerBookingJson(payment: 'cash')).walkInPayment, WalkInPayment.cash);
      expect(ownerBookingFromJson(ownerBookingJson(payment: 'transfer')).walkInPayment, WalkInPayment.transfer);
      expect(ownerBookingFromJson(ownerBookingJson(payment: null)).walkInPayment, isNull);
      expect(() => ownerBookingFromJson(ownerBookingJson(source: 'carrier_pigeon')), throwsFormatException);
    });

    test('a missing source means an app booking', () {
      final json = ownerBookingJson(source: 'app')..remove('source');
      expect(ownerBookingFromJson(json).source, BookingSource.app);
    });

    test('a block has a reason and no customer', () {
      final b = ownerBookingFromJson(
        ownerBookingJson(source: 'block', payment: null, name: null, phone: null, reason: 'Repairs'),
      );
      expect(b.isBlock, isTrue);
      expect(b.totalPrice, 0);
      expect(b.reason, 'Repairs');
      expect(b.customerName, isNull);
      expect(b.customerPhone, isNull);
    });

    test('marked statuses, including unverified', () {
      final paid = ownerBookingFromJson(ownerBookingJson(status: 'paid'));
      expect(paid.status, BookingStatus.paid);
      expect(paid.paymentStatus, PaymentStatus.paid);
      expect(ownerBookingFromJson(ownerBookingJson(status: 'no_show')).status, BookingStatus.noShow);
      expect(ownerBookingFromJson(ownerBookingJson(status: 'unverified')).status, BookingStatus.completed);
      expect(ownerBookingFromJson(ownerBookingJson(status: 'cancelled_by_venue')).status, BookingStatus.cancelledByVenue);
    });
  });

  group('owner calendar', () {
    Map<String, dynamic> calendarJson() => {
      'slots': [
        slotJson('2026-11-23T07:00:00', '2026-11-23T08:30:00', 'past'),
        slotJson('2026-11-23T17:30:00', '2026-11-23T19:00:00', 'booked', bookingId: 'booking-1'),
        slotJson('2026-11-23T19:00:00', '2026-11-23T20:30:00', 'booked', bookingId: 'booking-1', price: 250000),
        slotJson('2026-11-24T07:00:00', '2026-11-24T08:30:00', 'blocked', bookingId: 'booking-2'),
        slotJson('2026-11-24T08:30:00', '2026-11-24T10:00:00', 'free'),
      ],
      'bookings': [
        ownerBookingJson(),
        ownerBookingJson(
          id: 'booking-2',
          source: 'block',
          payment: null,
          name: null,
          phone: null,
          reason: 'Repairs',
          starts: '2026-11-24T07:00:00',
          ends: '2026-11-24T08:30:00',
        ),
      ],
    };

    test('slots and bookings map to the Dart types', () {
      final cal = ownerCalendarFromJson(calendarJson());
      expect(cal.slots, hasLength(5));
      expect(cal.slots.map((s) => s.state), [
        OwnerSlotState.past,
        OwnerSlotState.booked,
        OwnerSlotState.booked,
        OwnerSlotState.blocked,
        OwnerSlotState.free,
      ]);
      final second = cal.slots[2];
      expect(second.time, SlotTime(DateTime.utc(2026, 11, 23, 19), DateTime.utc(2026, 11, 23, 20, 30)));
      expect(second.price, 250000);
      expect(second.bookingId, 'booking-1');
      expect(cal.slots.first.bookingId, isNull);

      expect(cal.bookings.keys, unorderedEquals(['booking-1', 'booking-2']));
      expect(cal.bookings[second.bookingId]!.customerName, 'Rustam');
      expect(cal.bookings['booking-2']!.reason, 'Repairs');
    });

    test('slots on one day', () {
      final cal = ownerCalendarFromJson(calendarJson());
      expect(cal.slotsOn(DateTime.utc(2026, 11, 23)), hasLength(3));
      expect(cal.slotsOn(DateTime.utc(2026, 11, 24, 12)), hasLength(2));
      expect(cal.slotsOn(DateTime.utc(2026, 11, 25)), isEmpty);
    });

    test('an empty calendar', () {
      final cal = ownerCalendarFromJson({'slots': <Object>[], 'bookings': <Object>[]});
      expect(cal.slots, isEmpty);
      expect(cal.bookings, isEmpty);
      expect(ownerCalendarFromJson(<String, dynamic>{}).slots, isEmpty);
    });

    test("a tournament match's block names the tournament (M8a)", () {
      final json = calendarJson();
      (json['slots'] as List).add({
        ...slotJson('2026-11-24T10:00:00', '2026-11-24T11:30:00', 'blocked', bookingId: 'booking-2'),
        'tournament': {
          'title': {'uz': 'Kubok', 'ru': 'Кубок', 'kk': null, 'en': 'Cup'},
          'match_id': 'match-1',
        },
      });
      final slots = ownerCalendarFromJson(json).slots;
      expect(slots.take(5).map((s) => s.tournament), everyElement(isNull));
      expect((slots.last.tournament!.title.en, slots.last.tournament!.title.ru), ('Cup', 'Кубок'));
      expect(slots.last.tournament!.matchId, 'match-1');
    });

    test('an unknown slot state is a format error', () {
      final json = calendarJson();
      (json['slots'] as List).add(slotJson('2026-11-24T10:00:00', '2026-11-24T11:30:00', 'haunted'));
      expect(() => ownerCalendarFromJson(json), throwsFormatException);
    });
  });

  group('requests', () {
    test('payment methods and outcomes as the backend spells them', () {
      expect(WalkInPayment.values.map(walkInPaymentCode), ['cash', 'card', 'transfer']);
      expect(bookingOutcomeCode(BookingOutcome.paid), 'paid');
      expect(bookingOutcomeCode(BookingOutcome.noShow), 'no_show');
    });
  });

  group('settings requests', () {
    test('venue hours are always seven objects; closed days have null minutes', () {
      final json = venueHoursJson({
        for (var d = 1; d <= 5; d++) d: const DayHours(420, 1380),
        6: const DayHours(480, 1320),
        7: null,
      });
      expect(json, hasLength(7));
      expect(json.first, {'weekday': 1, 'open_minute': 420, 'close_minute': 1380});
      expect(json[5], {'weekday': 6, 'open_minute': 480, 'close_minute': 1320});
      expect(json.last, {'weekday': 7, 'open_minute': null, 'close_minute': null});
      // A weekday missing from the map is sent as closed.
      expect(venueHoursJson(const {}).map((h) => h['open_minute']), everyElement(isNull));
    });

    test('court hours list only the overridden days, in weekday order', () {
      expect(courtHoursJson(const {}), isEmpty);
      expect(courtHoursJson({3: null, 1: const DayHours(600, 720)}), [
        {'weekday': 1, 'open_minute': 600, 'close_minute': 720},
        {'weekday': 3, 'open_minute': null, 'close_minute': null},
      ]);
    });

    test('price rules keep their order, weekdays sorted', () {
      expect(
        priceRulesJson(const [
          PriceRule(weekdays: {5, 1, 3}, fromMinute: 1080, toMinute: 1440, price: 250000),
          PriceRule(weekdays: {7, 6}, fromMinute: 0, toMinute: 1440, price: 300000),
        ]),
        [
          {'weekdays': [1, 3, 5], 'from_minute': 1080, 'to_minute': 1440, 'price': 250000},
          {'weekdays': [6, 7], 'from_minute': 0, 'to_minute': 1440, 'price': 300000},
        ],
      );
      expect(priceRulesJson(const []), isEmpty);
    });
  });

  group('dashboard', () {
    Map<String, dynamic> dashboardJson({String currency = 'UZS'}) => {
      'currency': currency,
      'days': 7,
      'bookings_app': 12,
      'bookings_walk_in': 8,
      'revenue_paid': 3600000,
      'revenue_unconfirmed': 430000,
      'no_shows': 2,
      'slots_available': 140,
      'slots_booked': 35,
      'heatmap': [
        {'weekday': 1, 'hour': 19, 'count': 4},
        {'weekday': 6, 'hour': 10, 'count': 1},
      ],
    };

    test('maps every number and the heatmap', () {
      final d = ownerDashboardFromJson(dashboardJson());
      expect(d.currency, Currency.uzs);
      expect(d.days, 7);
      expect(d.bookingsApp, 12);
      expect(d.bookingsWalkIn, 8);
      expect(d.bookings, 20);
      expect(d.revenuePaid, 3600000);
      expect(d.revenueUnconfirmed, 430000);
      expect(d.noShows, 2);
      expect(d.slotsAvailable, 140);
      expect(d.slotsBooked, 35);
      expect(d.heatmap, {(weekday: 1, hour: 19): 4, (weekday: 6, hour: 10): 1});
      expect(d.utilisation, closeTo(0.25, 1e-9));
      expect(d.noShowRate, closeTo(0.1, 1e-9));
    });

    test('currency codes, an empty heatmap, and an unknown currency', () {
      expect(ownerDashboardFromJson(dashboardJson(currency: 'KZT')).currency, Currency.kzt);
      expect(ownerDashboardFromJson(dashboardJson(currency: 'kzt')).currency, Currency.kzt);
      expect(ownerDashboardFromJson(dashboardJson()..['heatmap'] = <Object>[]).heatmap, isEmpty);
      expect(() => ownerDashboardFromJson(dashboardJson(currency: 'XYZ')), throwsFormatException);
    });
  });

  group('errors', () {
    PostgrestException raised(String message) => PostgrestException(message: message, code: 'P0001');

    test('owner rule violations', () {
      expect(bookingExceptionFor(raised('not_allowed')).error, BookingError.notAllowed);
      expect(bookingExceptionFor(raised('not_markable')).error, BookingError.notMarkable);
      expect(bookingExceptionFor(raised('name_required')).error, BookingError.nameRequired);
      expect(bookingExceptionFor(raised('not_cancellable')).error, BookingError.notCancellable);
      expect(bookingExceptionFor(raised('invalid_argument')).error, BookingError.invalidArgument);
      expect(bookingExceptionFor(raised('invalid_hours')).error, BookingError.invalidHours);
      expect(bookingExceptionFor(raised('rules_overlap')).error, BookingError.rulesOverlap);
      expect(bookingExceptionFor(raised('tournament_block')).error, BookingError.tournamentBlock);
    });
  });
}
