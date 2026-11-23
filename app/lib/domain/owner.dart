import '../core/markets.dart';
import 'booking_engine.dart';
import 'models.dart';

/// Venue-owner view of the booking calendar (product spec §11.5).

/// Where a booking row came from. Walk-ins and blocks are rows in the same
/// table as app bookings, so one overlap rule covers all three.
enum BookingSource { app, walkIn, block }

/// How a walk-in or phone customer pays at the venue.
enum WalkInPayment { cash, card, transfer }

/// What the owner records once a booking has started.
enum BookingOutcome { paid, noShow }

enum OwnerSlotState { free, booked, blocked, past }

class OwnerBooking {
  const OwnerBooking({
    required this.id,
    required this.venueId,
    required this.courtId,
    required this.start,
    required this.end,
    required this.slotCount,
    required this.totalPrice,
    required this.status,
    required this.source,
    this.paymentStatus = PaymentStatus.unpaid,
    this.walkInPayment,
    this.customerName,
    this.customerPhone,
    this.note,
    this.reason,
    this.players,
  });

  /// The owner's view of an engine [booking]. [nameOf] names the player of
  /// an app booking; walk-ins carry their guest's name, blocks have none.
  factory OwnerBooking.fromBooking(Booking booking, {String Function(String userId)? nameOf}) {
    final isApp = booking.source == BookingSource.app;
    return OwnerBooking(
      id: booking.id,
      venueId: booking.venueId,
      courtId: booking.courtId,
      start: booking.start,
      end: booking.end,
      slotCount: booking.slotCount,
      totalPrice: booking.totalPrice,
      status: booking.status,
      source: booking.source,
      paymentStatus: booking.paymentStatus,
      walkInPayment: booking.walkInPayment,
      customerName: isApp ? nameOf?.call(booking.userId) : booking.guestName,
      customerPhone: isApp ? null : booking.guestPhone,
      note: booking.note,
      reason: booking.blockReason,
      players: booking.players,
    );
  }

  final String id;
  final String venueId;
  final String courtId;

  /// Venue wall-clock, UTC-flagged.
  final DateTime start;
  final DateTime end;
  final int slotCount;
  final int totalPrice;
  final BookingStatus status;
  final BookingSource source;
  final PaymentStatus paymentStatus;
  final WalkInPayment? walkInPayment;

  /// The guest's for a walk-in, the player's for an app booking, `null` for
  /// a block.
  final String? customerName;
  final String? customerPhone;
  final String? note;

  /// Blocks only.
  final String? reason;
  final int? players;

  bool get isBlock => source == BookingSource.block;
}

class OwnerSlot {
  const OwnerSlot({required this.time, required this.price, required this.state, this.bookingId});

  final SlotTime time;
  final int price;
  final OwnerSlotState state;

  /// The row covering this slot; `null` for `free` and `past`.
  final String? bookingId;
}

/// A venue's numbers over a date range (product spec §11.6). A booking
/// counts on the day and hour of its start; blocks and cancelled rows never
/// count.
class OwnerDashboard {
  const OwnerDashboard({
    required this.currency,
    required this.days,
    required this.bookingsApp,
    required this.bookingsWalkIn,
    required this.revenuePaid,
    required this.revenueUnconfirmed,
    required this.noShows,
    required this.slotsAvailable,
    required this.slotsBooked,
    required this.heatmap,
  });

  final Currency currency;
  final int days;
  final int bookingsApp;
  final int bookingsWalkIn;

  /// Sum of the locked prices of bookings marked paid.
  final int revenuePaid;

  /// Sum for bookings nobody marked within 48 hours of their end.
  final int revenueUnconfirmed;
  final int noShows;

  /// Slots the courts offer in the range, minus blocked ones.
  final int slotsAvailable;
  final int slotsBooked;

  /// Bookings by weekday (1 = Monday) and start hour; only non-zero cells.
  final Map<({int weekday, int hour}), int> heatmap;

  int get bookings => bookingsApp + bookingsWalkIn;

  double get dailyAverage => days <= 0 ? 0 : bookings / days;

  double get utilisation => slotsAvailable <= 0 ? 0 : slotsBooked / slotsAvailable;

  double get noShowRate => bookings == 0 ? 0 : noShows / bookings;
}

class OwnerCalendar {
  const OwnerCalendar({required this.slots, required this.bookings});

  /// In start order, across every day of the calendar.
  final List<OwnerSlot> slots;

  /// Every booking a slot refers to, by id.
  final Map<String, OwnerBooking> bookings;

  /// Slots starting on that wall-clock day.
  List<OwnerSlot> slotsOn(DateTime date) {
    final day = dateOnly(date);
    return [for (final s in slots) if (dateOnly(s.time.start) == day) s];
  }
}
