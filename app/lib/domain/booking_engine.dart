import '../core/markets.dart';
import 'models.dart';
import 'pricing.dart';
import 'slot_generator.dart';

enum BookingStatus { held, confirmed, cancelledByPlayer, cancelledByVenue, completed, paid, noShow, released }

enum PaymentMethod { payAtVenue }

enum PaymentStatus { unpaid, paid }

class Booking {
  const Booking({
    required this.id,
    required this.userId,
    required this.venueId,
    required this.courtId,
    required this.start,
    required this.end,
    required this.slotCount,
    required this.totalPrice,
    required this.status,
    this.paymentMethod = PaymentMethod.payAtVenue,
    this.paymentStatus = PaymentStatus.unpaid,
    this.holdExpiresAt,
    this.lateCancellation = false,
    this.players,
    this.note,
  });

  final String id;
  final String userId;
  final String venueId;
  final String courtId;
  final DateTime start;
  final DateTime end;
  final int slotCount;

  /// Locked when the slots are held; later price changes do not touch it.
  final int totalPrice;
  final BookingStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final DateTime? holdExpiresAt;
  final bool lateCancellation;
  final int? players;
  final String? note;

  Booking copyWith({
    BookingStatus? status,
    bool clearHold = false,
    bool? lateCancellation,
    int? players,
    String? note,
  }) => Booking(
    id: id,
    userId: userId,
    venueId: venueId,
    courtId: courtId,
    start: start,
    end: end,
    slotCount: slotCount,
    totalPrice: totalPrice,
    status: status ?? this.status,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus,
    holdExpiresAt: clearHold ? null : holdExpiresAt,
    lateCancellation: lateCancellation ?? this.lateCancellation,
    players: players ?? this.players,
    note: note ?? this.note,
  );
}

enum SlotState { free, taken, past, mine }

class SlotView {
  const SlotView({required this.time, required this.price, required this.state});

  final SlotTime time;
  final int price;
  final SlotState state;
}

enum BookingError {
  slotTaken,
  notContiguous,
  emptySelection,
  inPast,
  tooFarAhead,
  tooManyBookings,
  holdExpired,
  notFound,
  notCancellable,
}

class BookingException implements Exception {
  const BookingException(this.error);

  final BookingError error;

  @override
  String toString() => 'BookingException(${error.name})';
}

/// Booking rules from product spec §7.6, applied to an in-memory store.
///
/// In Milestone 2 the same rules run inside the database (roadmap §3.1); this
/// engine then only backs sample data and tests.
class BookingEngine {
  BookingEngine({required this.venueById});

  static const holdDuration = Duration(minutes: 5);
  static const maxUpcoming = 3;
  static const maxDaysAhead = 14;
  static const freeCancelWindow = Duration(hours: 6);

  final Venue Function(String venueId) venueById;
  final List<Booking> _bookings = [];
  int _nextId = 1;

  bool _isActive(Booking b, DateTime now) => switch (b.status) {
    BookingStatus.held => b.holdExpiresAt != null && b.holdExpiresAt!.isAfter(now),
    BookingStatus.confirmed || BookingStatus.completed || BookingStatus.paid || BookingStatus.noShow => true,
    _ => false,
  };

  Booking? _overlapping(String courtId, DateTime start, DateTime end, DateTime now) {
    for (final b in _bookings) {
      if (b.courtId == courtId && _isActive(b, now) && b.start.isBefore(end) && start.isBefore(b.end)) return b;
    }
    return null;
  }

  void _replace(Booking updated) {
    final i = _bookings.indexWhere((b) => b.id == updated.id);
    _bookings[i] = updated;
  }

  List<SlotView> availability(String venueId, String courtId, DateTime date, {required DateTime now, String? userId}) {
    final venue = venueById(venueId);
    final court = venue.court(courtId);
    return [
      for (final slot in generateSlots(venue, court, date))
        SlotView(time: slot, price: priceForSlot(court, slot), state: _stateOf(courtId, slot, now, userId)),
    ];
  }

  SlotState _stateOf(String courtId, SlotTime slot, DateTime now, String? userId) {
    if (!slot.start.isAfter(now)) return SlotState.past;
    final blocker = _overlapping(courtId, slot.start, slot.end, now);
    if (blocker == null) return SlotState.free;
    final heldByMe = blocker.status == BookingStatus.held && blocker.userId == userId;
    return heldByMe ? SlotState.mine : SlotState.taken;
  }

  /// Holds [slots] for [userId] for [holdDuration]. A player has one hold at a
  /// time: a new hold replaces their previous one.
  Booking hold({
    required String userId,
    required String venueId,
    required String courtId,
    required List<SlotTime> slots,
    required DateTime now,
  }) {
    if (slots.isEmpty) throw const BookingException(BookingError.emptySelection);

    final venue = venueById(venueId);
    final court = venue.court(courtId);
    final sorted = [...slots]..sort((a, b) => a.start.compareTo(b.start));

    final offered = generateSlots(venue, court, sorted.first.start).toSet();
    if (!sorted.every(offered.contains)) throw const BookingException(BookingError.notFound);
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].start != sorted[i - 1].end) throw const BookingException(BookingError.notContiguous);
    }

    final start = sorted.first.start;
    final end = sorted.last.end;
    if (!start.isAfter(now)) throw const BookingException(BookingError.inPast);
    if (dateOnly(start).difference(dateOnly(now)).inDays > maxDaysAhead) {
      throw const BookingException(BookingError.tooFarAhead);
    }

    final upcoming = _bookings.where(
      (b) => b.userId == userId && b.status == BookingStatus.confirmed && b.start.isAfter(now),
    );
    if (upcoming.length >= maxUpcoming) throw const BookingException(BookingError.tooManyBookings);

    for (final b in _bookings.where((b) => b.userId == userId && b.status == BookingStatus.held).toList()) {
      _replace(b.copyWith(status: BookingStatus.released, clearHold: true));
    }

    if (_overlapping(courtId, start, end, now) != null) throw const BookingException(BookingError.slotTaken);

    final booking = Booking(
      id: 'b${_nextId++}',
      userId: userId,
      venueId: venueId,
      courtId: courtId,
      start: start,
      end: end,
      slotCount: sorted.length,
      totalPrice: sorted.fold(0, (sum, s) => sum + priceForSlot(court, s)),
      status: BookingStatus.held,
      holdExpiresAt: now.add(holdDuration),
    );
    _bookings.add(booking);
    return booking;
  }

  Booking confirm(String bookingId, {required DateTime now, int? players, String? note}) {
    final booking = byId(bookingId);
    if (booking == null || booking.status != BookingStatus.held) {
      throw const BookingException(BookingError.notFound);
    }
    if (!_isActive(booking, now)) {
      _replace(booking.copyWith(status: BookingStatus.released, clearHold: true));
      throw const BookingException(BookingError.holdExpired);
    }
    final confirmed = booking.copyWith(
      status: BookingStatus.confirmed,
      clearHold: true,
      players: players,
      note: note,
    );
    _replace(confirmed);
    return confirmed;
  }

  /// Gives a held slot back, e.g. when the player leaves the summary screen.
  void release(String bookingId) {
    final booking = byId(bookingId);
    if (booking != null && booking.status == BookingStatus.held) {
      _replace(booking.copyWith(status: BookingStatus.released, clearHold: true));
    }
  }

  /// Player cancellation. Free until [freeCancelWindow] before the start;
  /// later ones are flagged as late.
  Booking cancel(String bookingId, {required DateTime now}) {
    final booking = byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    if (booking.status != BookingStatus.confirmed || !booking.start.isAfter(now)) {
      throw const BookingException(BookingError.notCancellable);
    }
    final cancelled = booking.copyWith(
      status: BookingStatus.cancelledByPlayer,
      lateCancellation: booking.start.difference(now) < freeCancelWindow,
    );
    _replace(cancelled);
    return cancelled;
  }

  /// A player's bookings, newest start first. Holds are not bookings yet.
  List<Booking> bookingsOf(String userId) =>
      _bookings
          .where((b) => b.userId == userId && b.status != BookingStatus.held && b.status != BookingStatus.released)
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start));

  Booking? byId(String id) {
    for (final b in _bookings) {
      if (b.id == id) return b;
    }
    return null;
  }
}
