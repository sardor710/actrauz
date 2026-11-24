import '../domain/community.dart';
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

/// Teams, finding players and public profiles (product spec §9.3, §9.4).
/// Teams are still sample data; players come from the backend. Never returns
/// a phone number. The signed-in player is not in [players], and has id
/// `kMeId` in [profile].
abstract class SocialRepository {
  Future<List<Team>> teams(String cityId);

  /// In the city, by name and by level in [sportId] (no level counts as 1),
  /// leaving out players who hid themselves. Name order.
  Future<List<PlayerProfile>> players(
    String cityId, {
    String? sportId,
    int minLevel = 1,
    int maxLevel = 5,
    String? query,
  });
  Future<PlayerProfile> profile(String userId);
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
  String? query,
  Reliability Function(String id)? reliabilityOf,
}) {
  final needle = query?.trim().toLowerCase() ?? '';
  return [
    for (final p in pool)
      if ((needle.isEmpty || p.name.toLowerCase().contains(needle)) &&
          (sportId == null || (p.levelFor(sportId) >= minLevel && p.levelFor(sportId) <= maxLevel)))
        profileOf(p, reliability: reliabilityOf?.call(p.id) ?? Reliability.fresh),
  ]..sort((a, b) => a.name.compareTo(b.name));
}

PlayerProfile profileOf(Player p, {Reliability reliability = Reliability.fresh, int gamesPlayed = 0}) =>
    PlayerProfile(id: p.id, name: p.name, levels: p.levels, reliability: reliability, gamesPlayed: gamesPlayed);

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
    String? query,
  }) async => searchPlayers(kSamplePlayers, sportId: sportId, minLevel: minLevel, maxLevel: maxLevel, query: query);

  @override
  Future<PlayerProfile> profile(String userId) async => profileOf(
    kSamplePlayers.firstWhere(
      (p) => p.id == userId,
      orElse: () => Player(id: userId, name: userId),
    ),
  );
}
