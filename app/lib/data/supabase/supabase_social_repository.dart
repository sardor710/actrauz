import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/community.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/teams.dart';
import '../social.dart';
import 'errors.dart';
import 'mappers.dart';

/// Teams, players, profiles and the player's own sports from the database.
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  // ---- Teams: the team functions of 20261127130000_teams.sql ----

  Team _team(Object? json) => teamFromJson(Map<String, dynamic>.from(json as Map), myUserId: _me);

  /// A call returning `team_json`; [codes] as [guardJoin] takes them.
  Future<Team> _teamCall(String fn, Map<String, dynamic> params, {Map<String, JoinError> codes = kTeamErrors}) =>
      guardJoin(() async => _team(await _client.rpc(fn, params: params)), codes: codes);

  Future<void> _teamVoid(String fn, Map<String, dynamic> params) => guardJoin(() async {
    await _client.rpc(fn, params: params);
  }, codes: kTeamErrors);

  @override
  Future<List<Team>> teams(String cityId) => guardJoin(() async {
    final rows = await _client.rpc('list_teams', params: {'p_city_id': cityId});
    return [for (final row in rows as List) _team(row)];
  }, codes: kTeamErrors);

  /// `get_team` answers null for a team that is gone.
  @override
  Future<Team> team(String id) => guardJoin(() async {
    final json = await _client.rpc('get_team', params: {'p_team_id': id});
    if (json == null) throw const JoinException(JoinError.notFound);
    return _team(json);
  }, codes: kTeamErrors);

  /// `already_exists` is a name taken in the city and sport (ruling R1).
  @override
  Future<Team> createTeam(TeamDraft draft) =>
      _teamCall('create_team', {'p_team': teamDraftJson(draft)}, codes: kTeamEditErrors);

  @override
  Future<Team> updateTeam(String id, TeamDraft draft) =>
      _teamCall('update_team', {'p_team_id': id, 'p_team': teamDraftJson(draft)}, codes: kTeamEditErrors);

  @override
  Future<void> deleteTeam(String id) => _teamVoid('delete_team', {'p_team_id': id});

  @override
  Future<Team> joinTeam(String id) => _teamCall('join_team', {'p_team_id': id});

  @override
  Future<void> leaveTeam(String id) => _teamVoid('leave_team', {'p_team_id': id});

  @override
  Future<void> withdrawTeamRequest(String requestId) =>
      _teamVoid('withdraw_team_request', {'p_request_id': requestId});

  @override
  Future<Team> decideTeamRequest(String requestId, {required bool approve}) =>
      _teamCall('decide_team_request', {'p_request_id': requestId, 'p_approve': approve});

  @override
  Future<Team> removeTeamMember(String teamId, String userId) =>
      _teamCall('remove_team_member', {'p_team_id': teamId, 'p_member': userIdOut(userId, _me)});

  @override
  Future<void> inviteToTeam(String teamId, String userId) =>
      _teamVoid('invite_to_team', {'p_team_id': teamId, 'p_invitee': userIdOut(userId, _me)});

  @override
  Future<Team> respondTeamInvite(String teamId, {required bool accept}) =>
      _teamCall('respond_team_invite', {'p_team_id': teamId, 'p_accept': accept});

  @override
  Future<Team> transferCaptain(String teamId, String userId) =>
      _teamCall('transfer_captain', {'p_team_id': teamId, 'p_member': userIdOut(userId, _me)});

  // ---- Players ----

  /// A rating bound in a sport goes to `list_players_rated` (the database
  /// refuses it for a simple sport); otherwise `list_players` by level.
  @override
  Future<List<PlayerProfile>> players(
    String cityId, {
    String? sportId,
    int minLevel = 1,
    int maxLevel = 5,
    double? minRating,
    double? maxRating,
    String? query,
  }) async {
    final rows = sportId != null && (minRating != null || maxRating != null)
        ? await _client.rpc(
            'list_players_rated',
            params: {
              'p_city_id': cityId,
              'p_sport_id': sportId,
              'p_min_rating': minRating,
              'p_max_rating': maxRating,
              'p_query': query,
            },
          )
        : await _client.rpc(
            'list_players',
            params: {
              'p_city_id': cityId,
              'p_sport_id': sportId,
              'p_min_level': minLevel,
              'p_max_level': maxLevel,
              'p_query': query,
            },
          );
    return [
      for (final row in rows as List) playerProfileFromJson(Map<String, dynamic>.from(row as Map), myUserId: _me),
    ];
  }

  @override
  Future<PlayerProfile> profile(String userId) async {
    final json = await _client.rpc('player_profile', params: {'p_user_id': userIdOut(userId, _me)});
    if (json == null) throw StateError('Unknown player $userId');
    return playerProfileFromJson(Map<String, dynamic>.from(json as Map), myUserId: _me);
  }

  @override
  Future<List<MySport>> mySports() async => mySportsFromJson(await _client.rpc('my_sports'));

  @override
  Future<List<MySport>> setSport(String sportId, {int? level, List<int>? answers}) => guardJoin(
    () async => mySportsFromJson(
      await _client.rpc('set_my_sport', params: {'p_sport_id': sportId, 'p_level': level, 'p_answers': answers}),
    ),
  );

  @override
  Future<List<MySport>> removeSport(String sportId) =>
      guardJoin(() async => mySportsFromJson(await _client.rpc('remove_my_sport', params: {'p_sport_id': sportId})));

  @override
  Future<Leaderboard> leaderboard(String sportId, String cityId) async => leaderboardFromJson(
    await _client.rpc('leaderboard', params: {'p_sport_id': sportId, 'p_city_id': cityId}),
    myUserId: _me,
  );

  /// `already_exists` is an open report already there (ruling R1).
  @override
  Future<void> reportPlayer(String targetId, {String? gameId, required ReportReason reason, String? details}) =>
      guardJoin(() async {
        await _client.rpc(
          'report_player',
          params: {
            'p_target': userIdOut(targetId, _me),
            'p_game_id': gameId,
            'p_reason': reportReasonJson(reason),
            'p_details': details,
          },
        );
      }, codes: kReportErrors);
}
