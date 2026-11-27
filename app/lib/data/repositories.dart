import '../domain/booking_engine.dart';
import '../domain/community.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import '../domain/tournaments.dart';

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

  /// The player's games that ended in the last 30 days and were not
  /// cancelled, the latest end first.
  Future<List<Game>> pastGames();

  /// The score of a finished game in a rated sport: 1 against 1 or 2 against
  /// 2 of its participants, the player among them, and 1–5 sets of
  /// (games of side a, games of side b). The host may enter it from the end,
  /// anyone in the game 24 hours after; whoever entered a pending score may
  /// enter it again to correct it. Throws [JoinError.scoreClosed] before the
  /// end, 7 days after, or once the result is confirmed, disputed or void;
  /// [JoinError.forbidden] when it is not the player's turn or someone else's
  /// pending score is there; [JoinError.notFound] for a game the player is not
  /// in or a simple sport.
  Future<Game> enterScore(
    String gameId, {
    required List<String> sideA,
    required List<String> sideB,
    required List<(int, int)> sets,
  });

  /// A player in a pending result, other than whoever entered it, agrees. A
  /// confirmation from the other side confirms the result and moves ratings.
  Future<Game> confirmScore(String resultId);

  /// Any player in a pending result freezes it for an admin.
  Future<Game> disputeScore(String resultId, {String? reason});

  /// Thumbs up (true) or down (false) for [targetId], another participant of
  /// the finished game; null takes the vote back. Changeable until 7 days
  /// after the end ([JoinError.scoreClosed] after); [JoinError.notFound] when
  /// the game has not ended, was cancelled, or either of them is not in it.
  Future<Game> vote(String gameId, String targetId, bool? up);

  /// Marks [targetId], another participant of the finished game, as not
  /// having shown up ([reported]) or takes it back, until 48 hours after the
  /// end. When most of the other players agree, the server records the
  /// no-show. Errors as [vote].
  Future<Game> reportNoShow(String gameId, String targetId, {required bool reported});

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

/// Tournaments and the signed-in player's registrations in them (product spec
/// §14). Every failure is a [TournamentException]. Partner ids are player ids
/// from [SocialRepository.players] or [findPlayerByPhone].
abstract class TournamentRepository {
  /// Active tournaments in the city that have not ended, first day first
  /// ([TournamentSort.date]) or by title ([TournamentSort.az]); [from] hides
  /// those that end before that day.
  Future<List<Tournament>> list(
    String cityId, {
    String? sportId,
    DateTime? from,
    TournamentSort sort = TournamentSort.date,
  });

  /// Throws [TournamentError.notFound] when there is no such active tournament.
  Future<Tournament> get(String id);

  /// Singles are registered at once while there is room (else
  /// [TournamentError.full]). Pairs wait for [partnerId] to accept.
  Future<Registration> register(String categoryId, {String? partnerId});

  /// The invited partner answers a pair's invitation.
  Future<Registration> respondPartner(String registrationId, {required bool accept});

  /// The registrant or the confirmed partner, until the deadline.
  Future<Registration> cancel(String registrationId);

  /// Only into a full category that has the waitlist on.
  Future<Registration> joinWaitlist(String categoryId, {String? partnerId});

  /// Takes a spot offered from the waitlist while the offer runs.
  Future<Registration> claimOffer(String registrationId);

  /// Every entry of the player (as registrant or partner, any state) in
  /// tournaments that have not ended, newest first.
  Future<List<Registration>> myRegistrations();

  /// Whether an account has this exact phone number. Never returns the
  /// phone; at most 20 calls an hour ([TournamentError.rateLimited]).
  Future<PlayerRef?> findPlayerByPhone(String phone);
}

/// The player's inbox and community settings.
abstract class NotificationRepository {
  /// Newest first. The next page: [before] and [beforeId] are the `createdAt`
  /// and `id` of the last entry shown (several entries can share a
  /// `createdAt`, so the id breaks the tie).
  Future<List<AppNotification>> inbox({DateTime? before, String? beforeId});
  Future<int> unreadCount();

  /// Marks the given entries read, or all of them when [ids] is null.
  Future<void> markRead([List<String>? ids]);
  Future<CommunitySettings> settings();
  Future<void> saveSettings(CommunitySettings settings);
}
