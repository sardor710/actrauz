import '../core/markets.dart';
import 'community.dart' show Reliability;
import 'models.dart';
import 'owner.dart';
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
    this.source = BookingSource.app,
    this.guestName,
    this.guestPhone,
    this.walkInPayment,
    this.blockReason,
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

  /// Walk-ins and blocks have no player: their [userId] is `''`.
  final BookingSource source;

  /// Walk-ins only.
  final String? guestName;
  final String? guestPhone;
  final WalkInPayment? walkInPayment;

  /// Blocks only.
  final String? blockReason;

  Booking copyWith({
    BookingStatus? status,
    PaymentStatus? paymentStatus,
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
    paymentStatus: paymentStatus ?? this.paymentStatus,
    holdExpiresAt: clearHold ? null : holdExpiresAt,
    lateCancellation: lateCancellation ?? this.lateCancellation,
    players: players ?? this.players,
    note: note ?? this.note,
    source: source,
    guestName: guestName,
    guestPhone: guestPhone,
    walkInPayment: walkInPayment,
    blockReason: blockReason,
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

  /// The caller does not manage the venue.
  notAllowed,

  /// Paid or no-show before the start, or on a block or cancelled row.
  notMarkable,

  /// A walk-in without a customer name.
  nameRequired,

  /// Malformed input: a value out of range, a text too long, a bad slot
  /// length or price, an empty weekday list.
  invalidArgument,

  /// Working hours with minutes outside 0–1440 or opening not before closing.
  invalidHours,

  /// Two price rules share a weekday and their time ranges intersect.
  rulesOverlap,

  /// A venue or court cannot be deleted while a booking references it.
  hasBookings,

  /// Creating a sport whose id is taken.
  alreadyExists,

  /// Reliability is too low to book (spec §8.3).
  reliabilityTooLow,

  /// The backend could not be reached or answered with something unexpected.
  unavailable,
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
    Reliability reliability = Reliability.fresh,
  }) {
    if (reliability.isBlocked) throw const BookingException(BookingError.reliabilityTooLow);
    final (:court, :sorted) = _checkedSlots(venueId, courtId, slots);
    final start = sorted.first.start;
    final end = sorted.last.end;
    if (!start.isAfter(now)) throw const BookingException(BookingError.inPast);
    _checkDaysAhead(start, now);

    // A limited player has one upcoming booking at a time instead of three.
    final upcoming = _bookings.where(
      (b) => b.userId == userId && b.status == BookingStatus.confirmed && b.start.isAfter(now),
    );
    if (upcoming.length >= (reliability.isLimited ? 1 : maxUpcoming)) {
      throw const BookingException(BookingError.tooManyBookings);
    }

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

  /// [slots] sorted, after checking they are real, contiguous slots of the
  /// court on one day.
  ({Court court, List<SlotTime> sorted}) _checkedSlots(String venueId, String courtId, List<SlotTime> slots) {
    if (slots.isEmpty) throw const BookingException(BookingError.emptySelection);

    final venue = venueById(venueId);
    final court = venue.court(courtId);
    final sorted = [...slots]..sort((a, b) => a.start.compareTo(b.start));

    final offered = generateSlots(venue, court, sorted.first.start).toSet();
    if (!sorted.every(offered.contains)) throw const BookingException(BookingError.notFound);
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].start != sorted[i - 1].end) throw const BookingException(BookingError.notContiguous);
    }
    return (court: court, sorted: sorted);
  }

  void _checkDaysAhead(DateTime start, DateTime now) {
    if (dateOnly(start).difference(dateOnly(now)).inDays > maxDaysAhead) {
      throw const BookingException(BookingError.tooFarAhead);
    }
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
    // Walk-ins and blocks are the venue's to cancel.
    if (booking.status != BookingStatus.confirmed ||
        booking.source != BookingSource.app ||
        !booking.start.isAfter(now)) {
      throw const BookingException(BookingError.notCancellable);
    }
    final cancelled = booking.copyWith(
      status: BookingStatus.cancelledByPlayer,
      lateCancellation: booking.start.difference(now) < freeCancelWindow,
    );
    _replace(cancelled);
    return cancelled;
  }

  // ---- Venue owner operations (product spec §11.5) ----
  //
  // The engine does not check who is calling: the repository decides who
  // manages a venue.

  /// Every slot of [courtId] on [days] days from [from], with the row
  /// covering it. [nameOf] names the player of an app booking; [isDeleted]
  /// says whether their account is gone.
  OwnerCalendar ownerCalendar(
    String venueId,
    String courtId,
    DateTime from,
    int days, {
    required DateTime now,
    String Function(String userId)? nameOf,
    bool Function(String userId)? isDeleted,
  }) {
    final venue = venueById(venueId);
    final court = venue.court(courtId);
    final first = dateOnly(from);
    final slots = <OwnerSlot>[];
    final bookings = <String, OwnerBooking>{};
    for (var d = 0; d < days; d++) {
      for (final slot in generateSlots(venue, court, first.add(Duration(days: d)))) {
        final row = _overlapping(courtId, slot.start, slot.end, now);
        final OwnerSlotState state;
        if (row != null) {
          state = row.source == BookingSource.block ? OwnerSlotState.blocked : OwnerSlotState.booked;
          bookings.putIfAbsent(row.id, () => OwnerBooking.fromBooking(row, nameOf: nameOf, isDeleted: isDeleted));
        } else {
          state = slot.end.isAfter(now) ? OwnerSlotState.free : OwnerSlotState.past;
        }
        slots.add(OwnerSlot(time: slot, price: priceForSlot(court, slot), state: state, bookingId: row?.id));
      }
    }
    return OwnerCalendar(slots: slots, bookings: bookings);
  }

  static const maxGuestNameLength = 80;
  static const maxBlockReasonLength = 200;
  static const maxPlayers = 100;
  static const maxOwnerSlots = 24;

  /// Highest base or rule price an owner or admin may set.
  static const maxPrice = 50000000;

  /// Slots for an owner-created row: the same validity checks as [hold],
  /// allowed until the first slot has ended, no cap on upcoming bookings.
  ({Court court, List<SlotTime> sorted}) _ownerSlots(
    String venueId,
    String courtId,
    List<SlotTime> slots,
    DateTime now,
  ) {
    if (slots.length > maxOwnerSlots) throw const BookingException(BookingError.invalidArgument);
    final checked = _checkedSlots(venueId, courtId, slots);
    final start = checked.sorted.first.start;
    final end = checked.sorted.last.end;
    if (!checked.sorted.first.end.isAfter(now)) throw const BookingException(BookingError.inPast);
    _checkDaysAhead(start, now);
    if (_overlapping(courtId, start, end, now) != null) throw const BookingException(BookingError.slotTaken);
    return checked;
  }

  /// A walk-in or phone booking, confirmed at once with the price locked.
  Booking createWalkIn({
    required String venueId,
    required String courtId,
    required List<SlotTime> slots,
    required String name,
    String? phone,
    int? players,
    required WalkInPayment payment,
    required DateTime now,
  }) {
    final guest = name.trim();
    if (guest.isEmpty) throw const BookingException(BookingError.nameRequired);
    if (guest.length > maxGuestNameLength || (players != null && (players < 1 || players > maxPlayers))) {
      throw const BookingException(BookingError.invalidArgument);
    }
    final (:court, :sorted) = _ownerSlots(venueId, courtId, slots, now);
    final booking = Booking(
      id: 'b${_nextId++}',
      userId: '',
      venueId: venueId,
      courtId: courtId,
      start: sorted.first.start,
      end: sorted.last.end,
      slotCount: sorted.length,
      totalPrice: sorted.fold(0, (sum, s) => sum + priceForSlot(court, s)),
      status: BookingStatus.confirmed,
      players: players,
      source: BookingSource.walkIn,
      guestName: guest,
      guestPhone: _blankToNull(phone),
      walkInPayment: payment,
    );
    _bookings.add(booking);
    return booking;
  }

  /// Takes [slots] off sale. A block is a confirmed row with no price.
  Booking blockSlots({
    required String venueId,
    required String courtId,
    required List<SlotTime> slots,
    String? reason,
    required DateTime now,
  }) {
    final blockReason = _blankToNull(reason);
    if (blockReason != null && blockReason.length > maxBlockReasonLength) {
      throw const BookingException(BookingError.invalidArgument);
    }
    final (court: _, :sorted) = _ownerSlots(venueId, courtId, slots, now);
    final booking = Booking(
      id: 'b${_nextId++}',
      userId: '',
      venueId: venueId,
      courtId: courtId,
      start: sorted.first.start,
      end: sorted.last.end,
      slotCount: sorted.length,
      totalPrice: 0,
      status: BookingStatus.confirmed,
      source: BookingSource.block,
      blockReason: blockReason,
    );
    _bookings.add(booking);
    return booking;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Venue cancellation of a booking or block that has not ended. The slots
  /// are free at once; the player is never flagged for it.
  Booking cancelByVenue(String bookingId, {required DateTime now}) {
    final booking = byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    if (booking.status != BookingStatus.confirmed || !booking.end.isAfter(now)) {
      throw const BookingException(BookingError.notCancellable);
    }
    final cancelled = booking.copyWith(status: BookingStatus.cancelledByVenue);
    _replace(cancelled);
    return cancelled;
  }

  /// Paid or no-show, once the booking has started. Blocks are never marked.
  Booking mark(String bookingId, BookingOutcome outcome, {required DateTime now}) {
    final booking = byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    final markable = switch (booking.status) {
      BookingStatus.confirmed || BookingStatus.completed || BookingStatus.paid || BookingStatus.noShow => true,
      _ => false,
    };
    if (!markable || booking.source == BookingSource.block || booking.start.isAfter(now)) {
      throw const BookingException(BookingError.notMarkable);
    }
    final marked = switch (outcome) {
      BookingOutcome.paid => booking.copyWith(status: BookingStatus.paid, paymentStatus: PaymentStatus.paid),
      BookingOutcome.noShow => booking.copyWith(status: BookingStatus.noShow, paymentStatus: PaymentStatus.unpaid),
    };
    _replace(marked);
    return marked;
  }

  static const maxDashboardDays = 92;

  /// The venue's numbers from [from] to [to] (wall-clock dates, inclusive),
  /// for one court or every court. Unmarked bookings never become
  /// `unverified` here, so [OwnerDashboard.revenueUnconfirmed] is 0.
  OwnerDashboard ownerDashboard(String venueId, {String? courtId, required DateTime from, required DateTime to}) {
    final first = dateOnly(from);
    final last = dateOnly(to);
    final days = last.difference(first).inDays + 1;
    if (days < 1 || days > maxDashboardDays) throw const BookingException(BookingError.invalidArgument);

    final venue = venueById(venueId);
    final courts = courtId == null ? venue.courts : [venue.court(courtId)];
    final courtIds = {for (final c in courts) c.id};

    bool inRange(DateTime start) {
      final day = dateOnly(start);
      return !day.isBefore(first) && !day.isAfter(last);
    }

    final rows = _bookings.where((b) => b.venueId == venueId && courtIds.contains(b.courtId));
    final blocks = rows.where((b) => b.source == BookingSource.block && b.status == BookingStatus.confirmed).toList();
    final counted = rows.where(
      (b) =>
          b.source != BookingSource.block &&
          inRange(b.start) &&
          switch (b.status) {
            BookingStatus.confirmed || BookingStatus.completed || BookingStatus.paid || BookingStatus.noShow => true,
            _ => false,
          },
    );

    var slotsAvailable = 0;
    for (final court in courts) {
      for (var d = 0; d < days; d++) {
        for (final slot in generateSlots(venue, court, first.add(Duration(days: d)))) {
          final blocked = blocks.any(
            (b) => b.courtId == court.id && b.start.isBefore(slot.end) && slot.start.isBefore(b.end),
          );
          if (!blocked) slotsAvailable++;
        }
      }
    }

    var app = 0, walkIn = 0, paid = 0, noShows = 0, slotsBooked = 0;
    final heatmap = <({int weekday, int hour}), int>{};
    for (final b in counted) {
      if (b.source == BookingSource.app) {
        app++;
      } else {
        walkIn++;
      }
      if (b.status == BookingStatus.paid) paid += b.totalPrice;
      if (b.status == BookingStatus.noShow) noShows++;
      slotsBooked += b.slotCount;
      final cell = (weekday: b.start.weekday, hour: b.start.hour);
      heatmap[cell] = (heatmap[cell] ?? 0) + 1;
    }

    return OwnerDashboard(
      currency: cityById(venue.cityId).currency,
      days: days,
      bookingsApp: app,
      bookingsWalkIn: walkIn,
      revenuePaid: paid,
      revenueUnconfirmed: 0,
      noShows: noShows,
      slotsAvailable: slotsAvailable,
      slotsBooked: slotsBooked,
      heatmap: heatmap,
    );
  }

  /// A player's bookings, newest start first. Holds are not bookings yet.
  List<Booking> bookingsOf(String userId) =>
      _bookings
          .where((b) => b.userId == userId && b.status != BookingStatus.held && b.status != BookingStatus.released)
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start));

  /// Whether any booking row, in any status, references the venue or court.
  bool hasBookings({String? venueId, String? courtId}) =>
      _bookings.any((b) => (venueId == null || b.venueId == venueId) && (courtId == null || b.courtId == courtId));

  Booking? byId(String id) {
    for (final b in _bookings) {
      if (b.id == id) return b;
    }
    return null;
  }
}
