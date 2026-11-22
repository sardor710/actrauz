import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/booking_engine.dart';
import '../../domain/models.dart';
import '../repositories.dart';
import 'errors.dart';
import 'mappers.dart';

/// Bookings through the database functions. The rules (and the guarantee
/// that a slot is never booked twice) are enforced there, not here.
class SupabaseBookingRepository implements BookingRepository {
  SupabaseBookingRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  Booking _booking(Object? json) => bookingFromJson(Map<String, dynamic>.from(json as Map), myUserId: _me);

  @override
  Future<List<SlotView>> availability(String venueId, String courtId, DateTime date) async {
    final rows = await _client.rpc('court_availability', params: {'p_court_id': courtId, 'p_date': isoDate(date)});
    return [for (final row in rows as List) slotFromRow(Map<String, dynamic>.from(row as Map))];
  }

  @override
  Future<Booking> hold(String venueId, String courtId, List<SlotTime> slots) => guardBooking(() async {
    return _booking(
      await _client.rpc(
        'hold_slots',
        params: {
          'p_court_id': courtId,
          'p_starts': [for (final slot in slots) isoLocal(slot.start)],
        },
      ),
    );
  });

  @override
  Future<Booking> confirm(String bookingId, {int? players, String? note}) => guardBooking(() async {
    return _booking(
      await _client.rpc('confirm_booking', params: {'p_booking_id': bookingId, 'p_players': players, 'p_note': note}),
    );
  });

  @override
  Future<void> release(String bookingId) async {
    try {
      await _client.rpc('release_hold', params: {'p_booking_id': bookingId});
    } catch (_) {
      // Leaving the summary screen must never fail: an unreleased hold
      // expires on its own after five minutes.
    }
  }

  @override
  Future<Booking> cancel(String bookingId) => guardBooking(() async {
    return _booking(await _client.rpc('cancel_booking', params: {'p_booking_id': bookingId}));
  });

  @override
  Future<List<Booking>> myBookings() async {
    final rows = await _client.rpc('my_bookings');
    return [for (final row in rows as List) _booking(row)];
  }
}
