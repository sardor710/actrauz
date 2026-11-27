import '../domain/community.dart';
import '../domain/competitive.dart';
import '../domain/games.dart';
import 'sample/sample_data.dart';

/// A standing group of players (product spec §9.3).
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.sportId,
    required this.cityId,
    required this.memberCount,
    required this.upcomingGames,
  });

  final String id;
  final String name;
  final String sportId;
  final String cityId;
  final int memberCount;
  final int upcomingGames;
}

/// Teams, finding players, public profiles and the signed-in player's own
/// sports (product spec §9.3, §9.4; M7 design §5.1). Teams are still sample
/// data; players come from the backend. Never returns a phone number. The
/// signed-in player is not in [players], and has id `kMeId` in [profile].
abstract class SocialRepository {
  Future<List<Team>> teams(String cityId);

  /// In the city, by name and by level in [sportId] (no level counts as 1),
  /// leaving out players who hid themselves. Name order. In a rated sport a
  /// rating bound ([minRating], [maxRating]; no rating counts as 1.0) is used
  /// instead of the level range.
  Future<List<PlayerProfile>> players(
    String cityId, {
    String? sportId,
    int minLevel = 1,
    int maxLevel = 5,
    double? minRating,
    double? maxRating,
    String? query,
  });
  Future<PlayerProfile> profile(String userId);

  /// The sports the signed-in player has ticked, in catalogue order.
  Future<List<MySport>> mySports();

  /// Ticks a sport or changes it: a level 1–5 for a simple sport, the five
  /// questionnaire [answers] (0–3 each) for a rated one. Answers sent after
  /// the first rated game are ignored: the rating stays. Returns
  /// [mySports]; a wrong combination is [JoinError.invalidArgument].
  Future<List<MySport>> setSport(String sportId, {int? level, List<int>? answers});

  /// Unticks a sport. A rating is kept and comes back with the sport.
  Future<List<MySport>> removeSport(String sportId);

  /// Players of [cityId] with at least one confirmed result in the rated sport
  /// [sportId], best rating first (then more rated games): the top
  /// [Leaderboard.maxRows], and the signed-in player's own row when they are
  /// in that city and have a result. Players who hid themselves and deleted
  /// accounts are not listed.
  Future<Leaderboard> leaderboard(String sportId, String cityId);
}

/// Fictional sample teams.
const kSampleTeams = <Team>[
  Team(id: 'tm1', name: 'Yunusobod Padel', sportId: 'padel', cityId: 'tashkent', memberCount: 24, upcomingGames: 2),
  Team(id: 'tm2', name: 'Chilonzor FC', sportId: 'football', cityId: 'tashkent', memberCount: 31, upcomingGames: 1),
  Team(id: 'tm3', name: 'Tennis Crew', sportId: 'tennis', cityId: 'tashkent', memberCount: 12, upcomingGames: 0),
  Team(id: 'tm4', name: 'Hoops TAS', sportId: 'basketball', cityId: 'tashkent', memberCount: 17, upcomingGames: 0),
  Team(id: 'tm5', name: 'Alatau Smash', sportId: 'padel', cityId: 'almaty', memberCount: 18, upcomingGames: 1),
  Team(id: 'tm6', name: 'Medeu Volley', sportId: 'volleyball', cityId: 'almaty', memberCount: 22, upcomingGames: 0),
  Team(id: 'tm7', name: 'Esil Ballers', sportId: 'basketball', cityId: 'astana', memberCount: 15, upcomingGames: 1),
  Team(id: 'tm8', name: 'Astana Five', sportId: 'football', cityId: 'astana', memberCount: 27, upcomingGames: 0),
];

/// Players matching a search, from [pool], as profiles with [reliabilityOf].
/// Shared by the stand-alone sample repository and the sample backend.
List<PlayerProfile> searchPlayers(
  Iterable<Player> pool, {
  String? sportId,
  int minLevel = 1,
  int maxLevel = 5,
  double? minRating,
  double? maxRating,
  String? query,
  Reliability Function(String id)? reliabilityOf,
}) {
  final needle = query?.trim().toLowerCase() ?? '';
  final byRating = minRating != null || maxRating != null;
  bool fits(Player p) {
    if (sportId == null) return true;
    if (byRating) {
      final rating = p.ratingFor(sportId);
      return rating >= (minRating ?? RatingRules.min) && rating <= (maxRating ?? RatingRules.max);
    }
    return p.levelFor(sportId) >= minLevel && p.levelFor(sportId) <= maxLevel;
  }

  return [
    for (final p in pool)
      if ((needle.isEmpty || p.name.toLowerCase().contains(needle)) && fits(p))
        profileOf(p, reliability: reliabilityOf?.call(p.id) ?? Reliability.fresh),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

/// As the backend shows a player: a rating only for a sport they have ticked.
PlayerProfile profileOf(Player p, {Reliability reliability = Reliability.fresh, int gamesPlayed = 0}) =>
    PlayerProfile(
      id: p.id,
      name: p.name,
      levels: p.levels,
      ratings: {
        for (final e in p.ratings.entries)
          if (p.levels.containsKey(e.key)) e.key: e.value,
      },
      reliability: reliability,
      gamesPlayed: gamesPlayed,
      deleted: p.deleted,
    );

class SampleSocialRepository implements SocialRepository {
  const SampleSocialRepository();

  @override
  Future<List<Team>> teams(String cityId) async => kSampleTeams.where((t) => t.cityId == cityId).toList();

  /// Sample players are not tied to a city yet.
  @override
  Future<List<PlayerProfile>> players(
    String cityId, {
    String? sportId,
    int minLevel = 1,
    int maxLevel = 5,
    double? minRating,
    double? maxRating,
    String? query,
  }) async => searchPlayers(
    kSamplePlayers,
    sportId: sportId,
    minLevel: minLevel,
    maxLevel: maxLevel,
    minRating: minRating,
    maxRating: maxRating,
    query: query,
  );

  @override
  Future<PlayerProfile> profile(String userId) async => profileOf(
    kSamplePlayers.firstWhere(
      (p) => p.id == userId,
      orElse: () => Player(id: userId, name: userId),
    ),
  );

  /// The stand-alone repository has no signed-in player: no sports, and
  /// nothing can be ticked (the app uses the sample backend for that).
  @override
  Future<List<MySport>> mySports() async => const [];

  @override
  Future<List<MySport>> setSport(String sportId, {int? level, List<int>? answers}) async =>
      throw const JoinException(JoinError.unavailable);

  @override
  Future<List<MySport>> removeSport(String sportId) async => const [];

  @override
  Future<Leaderboard> leaderboard(String sportId, String cityId) async => const Leaderboard(rows: []);
}
