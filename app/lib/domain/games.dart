class Player {
  const Player({required this.id, required this.name, this.levels = const {}});

  final String id;
  final String name;

  /// Self-selected level 1–5 per sport id (product spec §8.1).
  final Map<String, int> levels;

  /// A player who has not set a level for a sport counts as a beginner.
  int levelFor(String sportId) => levels[sportId] ?? 1;
}

/// An Available Game: place and time are already fixed (product spec §9.1).
class Game {
  const Game({
    required this.id,
    required this.sportId,
    required this.cityId,
    required this.venueId,
    required this.hostId,
    required this.start,
    required this.end,
    required this.spots,
    required this.participantIds,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.pricePerPlayer,
    this.bookingId,
    this.note,
  });

  final String id;
  final String sportId;
  final String cityId;
  final String venueId;
  final String hostId;
  final DateTime start;
  final DateTime end;

  /// Total spots, the host included.
  final int spots;
  final List<String> participantIds;
  final int minLevel;
  final int maxLevel;
  final int? pricePerPlayer;
  final String? bookingId;
  final String? note;

  int get spotsLeft => spots - participantIds.length;
  bool get isFull => spotsLeft <= 0;

  Game copyWith({List<String>? participantIds}) => Game(
    id: id,
    sportId: sportId,
    cityId: cityId,
    venueId: venueId,
    hostId: hostId,
    start: start,
    end: end,
    spots: spots,
    participantIds: participantIds ?? this.participantIds,
    minLevel: minLevel,
    maxLevel: maxLevel,
    pricePerPlayer: pricePerPlayer,
    bookingId: bookingId,
    note: note,
  );
}

enum JoinError {
  full,
  alreadyJoined,
  levelOutOfRange,
  notParticipant,
  hostCannotLeave,

  /// The backend could not be reached or answered with something unexpected.
  unavailable,
}

class JoinException implements Exception {
  const JoinException(this.error);

  final JoinError error;

  @override
  String toString() => 'JoinException(${error.name})';
}

/// One-tap join for players inside the level range. Players outside it will
/// send a join request instead (Milestone 4).
Game joinGame(Game game, Player player) {
  if (game.participantIds.contains(player.id)) throw const JoinException(JoinError.alreadyJoined);
  if (game.isFull) throw const JoinException(JoinError.full);
  final level = player.levelFor(game.sportId);
  if (level < game.minLevel || level > game.maxLevel) throw const JoinException(JoinError.levelOutOfRange);
  return game.copyWith(participantIds: [...game.participantIds, player.id]);
}

Game leaveGame(Game game, String playerId) {
  if (playerId == game.hostId) throw const JoinException(JoinError.hostCannotLeave);
  if (!game.participantIds.contains(playerId)) throw const JoinException(JoinError.notParticipant);
  return game.copyWith(participantIds: game.participantIds.where((id) => id != playerId).toList());
}
