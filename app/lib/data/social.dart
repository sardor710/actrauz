import '../domain/community.dart';
import '../domain/competitive.dart';
import '../domain/games.dart';
import '../domain/teams.dart';

/// Teams, finding players, public profiles and the signed-in player's own
/// sports (product spec §9.3, §9.4; M7 design §5.1, §7). Never returns a
/// phone number. The signed-in player is not in [players], and has id
/// `kMeId` in [profile].
abstract class SocialRepository {
  // ---- Teams (design §7) ----

  /// The signed-in player's teams (any city) first, then the other teams of
  /// [cityId]; each group by member count, largest first, then name.
  /// Summaries: no members, requests or games.
  Future<List<Team>> teams(String cityId);

  /// The team page: members, upcoming team games and, for the captain, the
  /// pending requests. [JoinError.notFound] when it is gone.
  Future<Team> team(String id);

  /// The signed-in player becomes captain and first member.
  /// [JoinError.teamLimit] at `Team.maxCaptained` teams as captain;
  /// [JoinError.nameTaken] when the name (trimmed, any case) is taken in that
  /// city and sport; [JoinError.invalidArgument] for a name outside 3–40
  /// characters, a description over 500, or an unknown sport or city.
  Future<Team> createTeam(TeamDraft draft);

  /// Captain only ([JoinError.captainOnly]): changes the name, description and
  /// join policy; the sport and city stay. Pending requests stay when the
  /// team turns open.
  Future<Team> updateTeam(String id, TeamDraft draft);

  /// Captain only; every member hears.
  Future<void> deleteTeam(String id);

  /// An open team, or one that invited the player: a member at once. An
  /// approval team: a pending request ([JoinError.alreadyAskedTeam] when one
  /// is waiting), and the captain hears. [JoinError.alreadyInTeam] for a
  /// member.
  Future<Team> joinTeam(String id);

  /// [JoinError.captainCannotLeave] for the captain, who hands over first
  /// ([transferCaptain]); [JoinError.notFound] for a non-member.
  Future<void> leaveTeam(String id);

  /// Takes back the signed-in player's pending request (`Team.myRequestId`).
  Future<void> withdrawTeamRequest(String requestId);

  /// Captain only. Approving makes the player a member; either way they hear.
  Future<Team> decideTeamRequest(String requestId, {required bool approve});

  /// Captain only; never the captain ([JoinError.invalidArgument]). The
  /// player hears.
  Future<Team> removeTeamMember(String teamId, String userId);

  /// Captain only: a live player who is not a member. Inviting again reopens
  /// a declined invite; the player hears once per open invite.
  Future<void> inviteToTeam(String teamId, String userId);

  /// Accepting makes the signed-in player a member, whatever the join
  /// policy. [JoinError.notFound] without a pending invite.
  Future<Team> respondTeamInvite(String teamId, {required bool accept});

  /// Captain only: hands the role to another live member, who hears.
  Future<Team> transferCaptain(String teamId, String userId);

  // ---- Players ----

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

  /// Reports another player to Actra, optionally about a game both played
  /// in; [details] at most 500 characters. The reported player is told
  /// nothing. [JoinError.alreadyReported] while the player's earlier report
  /// about the same player and game is open; [JoinError.invalidArgument] for
  /// themselves or longer details; [JoinError.notFound] for a deleted player
  /// or a game they did not both play in.
  Future<void> reportPlayer(String targetId, {String? gameId, required ReportReason reason, String? details});
}

/// Players matching a search, from [pool], as profiles with [reliabilityOf].
/// Used by the sample backend.
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
PlayerProfile profileOf(
  Player p, {
  Reliability reliability = Reliability.fresh,
  int gamesPlayed = 0,
  Sportsmanship sportsmanship = Sportsmanship.none,
  List<TeamRef> teams = const [],
}) => PlayerProfile(
      id: p.id,
      name: p.name,
      levels: p.levels,
      ratings: {
        for (final e in p.ratings.entries)
          if (p.levels.containsKey(e.key)) e.key: e.value,
      },
      reliability: reliability,
      gamesPlayed: gamesPlayed,
      sportsmanship: sportsmanship,
      teams: teams,
      deleted: p.deleted,
    );
