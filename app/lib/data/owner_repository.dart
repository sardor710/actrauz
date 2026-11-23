import '../domain/models.dart';
import '../domain/owner.dart';

/// What the venue-owner screens need from the backend. Every call is refused
/// with `BookingException(BookingError.notAllowed)` for a venue the signed-in
/// user does not manage; rule violations surface as other [BookingError]s.
abstract class OwnerRepository {
  /// Venues the signed-in user manages; every active venue for an admin.
  Future<List<Venue>> myVenues();

  Future<OwnerCalendar> calendar(String venueId, String courtId, DateTime from, int days);

  Future<OwnerBooking> createWalkIn(
    String venueId,
    String courtId,
    List<SlotTime> slots, {
    required String name,
    String? phone,
    int? players,
    required WalkInPayment payment,
  });

  Future<OwnerBooking> blockSlots(String venueId, String courtId, List<SlotTime> slots, {String? reason});

  Future<OwnerBooking> cancel(String bookingId);

  Future<OwnerBooking> mark(String bookingId, BookingOutcome outcome);

  /// All seven weekdays; a weekday mapped to `null` is closed. Existing
  /// bookings keep their times and prices.
  Future<void> setVenueHours(String venueId, WeekHours hours);

  /// Only the weekdays that differ from the venue (`null` = closed that day);
  /// an empty map follows the venue every day.
  Future<void> setCourtHours(String venueId, String courtId, WeekHours override);

  /// Replaces the court's slot length, base price and rules (in order).
  Future<void> setCourtPricing(
    String venueId,
    String courtId, {
    required int slotMinutes,
    required int basePrice,
    required List<PriceRule> rules,
  });

  /// [from] to [to] are wall-clock dates, inclusive, at most 92 days.
  /// [courtId] `null` = every court of the venue.
  Future<OwnerDashboard> dashboard(String venueId, {String? courtId, required DateTime from, required DateTime to});
}
