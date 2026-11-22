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

/// Teams and players for the Social tab. Kept apart from the booking and game
/// repositories so it can gain a backend implementation on its own.
abstract class SocialRepository {
  Future<List<Team>> teams(String cityId);
  Future<List<Player>> players(String cityId);
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

class SampleSocialRepository implements SocialRepository {
  const SampleSocialRepository();

  @override
  Future<List<Team>> teams(String cityId) async => kSampleTeams.where((t) => t.cityId == cityId).toList();

  /// Sample players are not tied to a city yet.
  @override
  Future<List<Player>> players(String cityId) async => kSamplePlayers;
}
