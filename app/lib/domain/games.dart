import 'community.dart';
import 'competitive.dart';
import 'teams.dart';

export 'community.dart' show GameMember, Reliability, ReliabilityBadge;
export 'competitive.dart' show AfterGame, MatchResult, MatchWinner, RatingChange, ReportReason, ResultStatus, SportRating;

class Player {
  const Player({
    required this.id,
    required this.name,
    this.levels = const {},
    this.ratings = const {},
    this.deleted = false,
  });

  final String id;
  final String name;

  /// The account was deleted: the screens show "Deleted player" (the name is
  /// empty by then).
  final bool deleted;

  /// Self-selected level 1–5 per sport id (product spec §8.1).
  final Map<String, int> levels;

  /// Rating per rated sport id (padel, tennis).
  final Map<String, SportRating> ratings;

  /// A player who has not set a level for a sport counts as a beginner.
  int levelFor(String sportId) => levels[sportId] ?? 1;

  /// A player with no rating in a rated sport counts as the minimum, 1.0.
  double ratingFor(String sportId) => ratings[sportId]?.rating ?? RatingRules.min;
}

/// Where a game happens (product spec §9.1).
enum GameKind {
  /// On the host's own court booking: time, venue and price come from it.
  booked,

  /// At a venue, for sports that have no slots (running, gym).
  place,

  /// At a meeting point on the map.
  mapPoint,
}

enum GameVisibility {
  public,

  /// Only the host, the people in it and the people invited or asking can see it.
  inviteOnly,
}

/// How the signed-in player stands in a game; null when they have no part in it.
enum MyGameStatus { host, participant, invited, requested }

/// A player asking to join a game, waiting for the host.
class JoinRequest {
  const JoinRequest({required this.id, required this.member, required this.createdAt});

  final String id;
  final GameMember member;
  final DateTime createdAt;
}

/// A game: place and time are fixed (product spec §9.1).
class Game {
  const Game({
    required this.id,
    required this.sportId,
    required this.cityId,
    required this.hostId,
    required this.start,
    required this.end,
    required this.spots,
    required this.participantIds,
    this.venueId,
    this.kind = GameKind.booked,
    this.visibility = GameVisibility.public,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.minRating,
    this.maxRating,
    this.pricePerPlayer,
    this.bookingId,
    this.note,
    this.meetingPoint,
    this.meetingLat,
    this.meetingLng,
    this.distanceKm,
    this.pace,
    this.myStatus,
    this.myRequestId,
    this.participants = const [],
    this.joinRequests = const [],
    this.cancelled = false,
    this.result,
    this.afterGame,
    this.team,
    this.publicFrom,
  });

  final String id;
  final String sportId;
  final String cityId;

  /// Null for a game on a map point.
  final String? venueId;
  final String hostId;
  final GameKind kind;
  final GameVisibility visibility;
  final DateTime start;
  final DateTime end;

  /// Total spots, the host included.
  final int spots;
  final List<String> participantIds;
  final int minLevel;
  final int maxLevel;

  /// The rating range of a game in a rated sport (null in a simple sport);
  /// [minLevel] and [maxLevel] are derived from it.
  final double? minRating;
  final double? maxRating;
  final int? pricePerPlayer;
  final String? bookingId;
  final String? note;
  final String? meetingPoint;
  final double? meetingLat;
  final double? meetingLng;
  final double? distanceKm;
  final String? pace;

  /// The signed-in player's part in it.
  final MyGameStatus? myStatus;

  /// The id of the player's pending request to join, to withdraw it.
  final String? myRequestId;

  /// Name, level and reliability of each participant, the host first. Empty
  /// when only [participantIds] are known.
  final List<GameMember> participants;

  /// Pending requests to join. Only the host receives them.
  final List<JoinRequest> joinRequests;
  final bool cancelled;

  /// The score, once someone has entered one (rated sports only).
  final MatchResult? result;

  /// The signed-in player's own votes and no-show marks, once the game has
  /// ended and they played in it; null otherwise.
  final AfterGame? afterGame;

  /// The team the captain posted it for; null for an ordinary game, and once
  /// the team is deleted. A team game reads as [GameVisibility.inviteOnly]
  /// (as builds made before teams see it), so this is what marks it.
  final TeamRef? team;

  /// When a team game opens to everyone while spots remain, in the venue's
  /// wall-clock time like [start]; null when it never does.
  final DateTime? publicFrom;

  int get spotsLeft => spots - participantIds.length;
  bool get isFull => spotsLeft <= 0;

  /// Whether the game is over at [now], the venue's wall-clock time (like
  /// every time of a game).
  bool endedAt(DateTime now) => !end.isAfter(now);

  Game copyWith({
    List<String>? participantIds,
    int? spots,
    String? note,
    bool clearNote = false,
    int? pricePerPlayer,
    MyGameStatus? myStatus,
    bool clearMyStatus = false,
    String? myRequestId,
    bool clearMyRequestId = false,
    List<GameMember>? participants,
    List<JoinRequest>? joinRequests,
    bool? cancelled,
    MatchResult? result,
    AfterGame? afterGame,
    TeamRef? team,
    bool clearTeam = false,
    DateTime? publicFrom,
    bool clearPublicFrom = false,
  }) => Game(
    id: id,
    sportId: sportId,
    cityId: cityId,
    venueId: venueId,
    hostId: hostId,
    kind: kind,
    visibility: visibility,
    start: start,
    end: end,
    spots: spots ?? this.spots,
    participantIds: participantIds ?? this.participantIds,
    minLevel: minLevel,
    maxLevel: maxLevel,
    minRating: minRating,
    maxRating: maxRating,
    pricePerPlayer: pricePerPlayer ?? this.pricePerPlayer,
    bookingId: bookingId,
    note: clearNote ? null : (note ?? this.note),
    meetingPoint: meetingPoint,
    meetingLat: meetingLat,
    meetingLng: meetingLng,
    distanceKm: distanceKm,
    pace: pace,
    myStatus: clearMyStatus ? null : (myStatus ?? this.myStatus),
    myRequestId: clearMyRequestId ? null : (myRequestId ?? this.myRequestId),
    participants: participants ?? this.participants,
    joinRequests: joinRequests ?? this.joinRequests,
    cancelled: cancelled ?? this.cancelled,
    result: result ?? this.result,
    afterGame: afterGame ?? this.afterGame,
    team: clearTeam ? null : (team ?? this.team),
    publicFrom: clearPublicFrom ? null : (publicFrom ?? this.publicFrom),
  );
}

/// What a host fills in to start a game (the keys of `create_game`). A booked
/// sport sets [bookingId]; a place-only sport sets [venueId] or a meeting
/// point, and its own [start] and [end].
class GameDraft {
  const GameDraft({
    required this.sportId,
    required this.spots,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.minRating,
    this.maxRating,
    this.visibility = GameVisibility.public,
    this.note,
    this.pace,
    this.distanceKm,
    this.bookingId,
    this.venueId,
    this.meetingPoint,
    this.meetingLat,
    this.meetingLng,
    this.start,
    this.end,
    this.teamId,
    this.openHoursBefore,
  });

  /// Hours before the start a team game may open to everyone.
  static const openHoursChoices = [12, 24, 48];

  final String sportId;
  final int spots;
  final int minLevel;
  final int maxLevel;

  /// A rated sport: both ends, or neither (the level range is then converted).
  final double? minRating;
  final double? maxRating;
  final GameVisibility visibility;
  final String? note;
  final String? pace;
  final double? distanceKm;
  final String? bookingId;
  final String? venueId;
  final String? meetingPoint;
  final double? meetingLat;
  final double? meetingLng;

  /// Venue or city wall-clock time; not used with [bookingId].
  final DateTime? start;
  final DateTime? end;

  /// A team game: a team the host captains, in this sport and city. The
  /// backend stores it as invite-only whatever [visibility] says.
  final String? teamId;

  /// One of [openHoursChoices], or null for never; only with [teamId].
  final int? openHoursBefore;
}

/// Where a Game Request becomes a game: a booking of the poster's own, a
/// venue, or a meeting point. Anything left out takes the request's own value
/// (spots: the poster and the players needed; times: the request's window).
class PlacePick {
  const PlacePick({
    this.bookingId,
    this.venueId,
    this.meetingPoint,
    this.meetingLat,
    this.meetingLng,
    this.spots,
    this.start,
    this.end,
    this.visibility,
    this.pace,
    this.distanceKm,
  });

  final String? bookingId;
  final String? venueId;
  final String? meetingPoint;
  final double? meetingLat;
  final double? meetingLng;
  final int? spots;
  final DateTime? start;
  final DateTime? end;
  final GameVisibility? visibility;
  final String? pace;
  final double? distanceKm;
}

enum JoinError {
  full,
  alreadyJoined,
  levelOutOfRange,
  notParticipant,
  hostCannotLeave,

  /// The game does not exist for this player: unknown, already started,
  /// invite-only without an invite, or not the host's to run.
  notFound,

  /// A request to join is already waiting for the host.
  alreadyRequested,

  /// Reliability is too low to join, ask, create or post (spec §8.3).
  reliabilityTooLow,

  /// The booking is not the player's own confirmed booking for this sport.
  bookingNotUsable,

  /// The booking already has an open game.
  gameExists,
  invalidArgument,
  inPast,
  tooFarAhead,
  forbidden,

  /// The game has started: it can no longer be cancelled.
  notCancellable,

  /// The game can no longer take a score: not a rated sport, not finished
  /// yet, more than 7 days past, or its result was voided.
  scoreClosed,

  /// The player already has an open report about this player (and game).
  alreadyReported,

  /// The player already captains the most teams they can create
  /// (`Team.maxCaptained`).
  teamLimit,

  /// The captain hands the team to a member before leaving it.
  captainCannotLeave,

  /// Another team in the same city and sport has this name.
  nameTaken,

  /// The backend could not be reached or answered with something unexpected.
  unavailable,
}

class JoinException implements Exception {
  const JoinException(this.error);

  final JoinError error;

  @override
  String toString() => 'JoinException(${error.name})';
}

/// One-tap join for players inside the level range, or the rating range in a
/// rated sport. An invited player ([invited]) opens an invite-only game and
/// skips the check; a team game open to the player ([teamOpen]: a member, or
/// anyone once it opened) is joined like a public one, with the check;
/// everyone else outside the range sends a join request instead.
Game joinGame(Game game, Player player, {bool invited = false, bool teamOpen = false}) {
  // As in the database: without an open invite an invite-only game does not exist for the player, even for a
  // player already in it.
  if (game.visibility == GameVisibility.inviteOnly && !invited && !teamOpen) {
    throw const JoinException(JoinError.notFound);
  }
  if (game.participantIds.contains(player.id)) throw const JoinException(JoinError.alreadyJoined);
  if (game.isFull) throw const JoinException(JoinError.full);
  if (!invited && !fitsRange(game, player)) throw const JoinException(JoinError.levelOutOfRange);
  return game.copyWith(participantIds: [...game.participantIds, player.id]);
}

/// Whether [player] is inside the game's rating range (a rated sport) or
/// level range (otherwise).
bool fitsRange(Game game, Player player) {
  final minRating = game.minRating;
  final maxRating = game.maxRating;
  if (minRating != null && maxRating != null) {
    final rating = player.ratingFor(game.sportId);
    return rating >= minRating && rating <= maxRating;
  }
  final level = player.levelFor(game.sportId);
  return level >= game.minLevel && level <= game.maxLevel;
}

Game leaveGame(Game game, String playerId) {
  if (playerId == game.hostId) throw const JoinException(JoinError.hostCannotLeave);
  if (!game.participantIds.contains(playerId)) throw const JoinException(JoinError.notParticipant);
  return game.copyWith(participantIds: game.participantIds.where((id) => id != playerId).toList());
}
