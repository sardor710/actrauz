import '../domain/booking_engine.dart';
import '../domain/community.dart';
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
  /// Games the player may see in the city: open, not started, and not full
  /// unless the player is in them; plus anywhere the player hosts, plays in or
  /// is invited to. Earliest first.
  Future<List<Game>> games(String cityId);

  /// Throws when the game does not exist or the player may not see it.
  Future<Game> game(String id);
  Future<Game> join(String id);
  Future<Game> leave(String id);
  Future<Player> player(String id);

  Future<Game> create(GameDraft draft);

  /// Asks the host to let the player in; returns the game with
  /// [MyGameStatus.requested].
  Future<Game> requestToJoin(String gameId);

  /// Takes back the player's pending request; the id is [Game.myRequestId].
  Future<Game> withdrawRequest(String requestId);

  /// Host only.
  Future<Game> decideRequest(String requestId, {required bool approve});

  /// Host only. [userId] is a player id from [SocialRepository.players].
  Future<Game> invite(String gameId, String userId);

  /// The invited player says no. Later they cannot join without a new invite.
  Future<Game> declineInvite(String gameId);

  /// Host only. No reliability event: the host chose this, not the player.
  Future<Game> removeParticipant(String gameId, String userId);

  /// Host only. A null [note] leaves the note as it is, a blank one clears it.
  Future<Game> updateGame(String gameId, {String? note, required int spots});

  /// Host only. With [cancelBooking] also the host's court booking under it.
  /// Throws [JoinError.notCancellable] once the game has started.
  Future<Game> cancelGame(String gameId, {required bool cancelBooking});

  /// Open Game Requests in the city, plus the player's own anywhere.
  Future<List<GameRequest>> requests(String cityId);
  Future<GameRequest> request(String id);
  Future<GameRequest> createRequest(GameRequestDraft draft);

  /// "I'm in".
  Future<GameRequest> imIn(String id);
  Future<GameRequest> withdrawInterest(String id);

  /// Poster only.
  Future<GameRequest> removeInterested(String id, String userId);

  /// Poster only.
  Future<GameRequest> cancelRequest(String id);

  /// Poster only: makes the game at [place] and adds the interested players,
  /// in the order they tapped, while spots remain.
  Future<Game> convertRequest(String id, PlacePick place);
}

/// The player's inbox and community settings.
abstract class NotificationRepository {
  /// Newest first; [before] pages back from the `createdAt` of the last one.
  Future<List<AppNotification>> inbox({DateTime? before});
  Future<int> unreadCount();

  /// Marks the given entries read, or all of them when [ids] is null.
  Future<void> markRead([List<String>? ids]);
  Future<CommunitySettings> settings();
  Future<void> saveSettings(CommunitySettings settings);
}
