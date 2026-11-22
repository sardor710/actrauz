import '../domain/booking_engine.dart';
import '../domain/games.dart';
import '../domain/models.dart';

/// What screens need from the backend. Milestone 1 ships a sample-data
/// implementation; Milestone 2 adds a Supabase one behind the same interfaces.

abstract class CatalogRepository {
  Future<List<Sport>> sports();
  Future<List<Venue>> venues(String cityId);
  Future<Venue> venue(String id);
  Future<List<BannerItem>> banners(String cityId);
  Future<List<TournamentItem>> tournaments(String cityId);
}

abstract class BookingRepository {
  Future<List<SlotView>> availability(String venueId, String courtId, DateTime date);
  Future<Booking> hold(String venueId, String courtId, List<SlotTime> slots);
  Future<Booking> confirm(String bookingId, {int? players, String? note});
  Future<void> release(String bookingId);
  Future<Booking> cancel(String bookingId);
  Future<List<Booking>> myBookings();
}

abstract class GameRepository {
  /// Open games in the city, plus full ones the current player is in.
  Future<List<Game>> games(String cityId);
  Future<Game> game(String id);
  Future<Game> join(String id);
  Future<Game> leave(String id);
  Future<Player> player(String id);
}
