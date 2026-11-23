import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../owner_repository.dart';
import '../repositories.dart';
import 'errors.dart';
import 'mappers.dart';

/// Owner operations through the `owner_*` database functions. Who manages
/// which venue, and every booking rule, is decided there; a venue the caller
/// does not manage comes back as `not_allowed`.
class SupabaseOwnerRepository implements OwnerRepository {
  SupabaseOwnerRepository(this._client, this._catalog);

  final SupabaseClient _client;

  /// Loads each managed venue the same way the player screens do.
  final CatalogRepository _catalog;

  OwnerBooking _booking(Object? json) => ownerBookingFromJson(Map<String, dynamic>.from(json as Map));

  List<String> _starts(List<SlotTime> slots) => [for (final slot in slots) isoLocal(slot.start)];

  @override
  Future<List<Venue>> myVenues() => guardBooking(() async {
    final ids = await _client.rpc('my_venue_ids');
    return Future.wait([for (final id in (ids as List? ?? const [])) _catalog.venue(id as String)]);
  });

  @override
  Future<OwnerCalendar> calendar(String venueId, String courtId, DateTime from, int days) => guardBooking(() async {
    final json = await _client.rpc(
      'owner_calendar',
      params: {'p_court_id': courtId, 'p_from': isoDate(from), 'p_days': days},
    );
    return ownerCalendarFromJson(Map<String, dynamic>.from(json as Map));
  });

  @override
  Future<OwnerBooking> createWalkIn(
    String venueId,
    String courtId,
    List<SlotTime> slots, {
    required String name,
    String? phone,
    int? players,
    required WalkInPayment payment,
  }) => guardBooking(() async {
    return _booking(
      await _client.rpc(
        'owner_create_walk_in',
        params: {
          'p_court_id': courtId,
          'p_starts': _starts(slots),
          'p_name': name,
          'p_phone': phone,
          'p_players': players,
          'p_payment_method': walkInPaymentCode(payment),
        },
      ),
    );
  });

  @override
  Future<OwnerBooking> blockSlots(String venueId, String courtId, List<SlotTime> slots, {String? reason}) =>
      guardBooking(() async {
        return _booking(
          await _client.rpc(
            'owner_block_slots',
            params: {'p_court_id': courtId, 'p_starts': _starts(slots), 'p_reason': reason},
          ),
        );
      });

  @override
  Future<OwnerBooking> cancel(String bookingId) => guardBooking(() async {
    return _booking(await _client.rpc('owner_cancel_booking', params: {'p_booking_id': bookingId}));
  });

  @override
  Future<void> setVenueHours(String venueId, WeekHours hours) => guardBooking(() async {
    await _client.rpc('owner_set_venue_hours', params: {'p_venue_id': venueId, 'p_hours': venueHoursJson(hours)});
  });

  @override
  Future<void> setCourtHours(String venueId, String courtId, WeekHours override) => guardBooking(() async {
    await _client.rpc('owner_set_court_hours', params: {'p_court_id': courtId, 'p_hours': courtHoursJson(override)});
  });

  @override
  Future<void> setCourtPricing(
    String venueId,
    String courtId, {
    required int slotMinutes,
    required int basePrice,
    required List<PriceRule> rules,
  }) => guardBooking(() async {
    await _client.rpc(
      'owner_set_court_pricing',
      params: {
        'p_court_id': courtId,
        'p_slot_minutes': slotMinutes,
        'p_base_price': basePrice,
        'p_rules': priceRulesJson(rules),
      },
    );
  });

  @override
  Future<OwnerDashboard> dashboard(String venueId, {String? courtId, required DateTime from, required DateTime to}) =>
      guardBooking(() async {
        final json = await _client.rpc(
          'owner_dashboard',
          params: {'p_venue_id': venueId, 'p_court_id': courtId, 'p_from': isoDate(from), 'p_to': isoDate(to)},
        );
        return ownerDashboardFromJson(Map<String, dynamic>.from(json as Map));
      });

  @override
  Future<OwnerBooking> mark(String bookingId, BookingOutcome outcome) => guardBooking(() async {
    return _booking(
      await _client.rpc(
        'owner_mark_booking',
        params: {'p_booking_id': bookingId, 'p_outcome': bookingOutcomeCode(outcome)},
      ),
    );
  });
}
