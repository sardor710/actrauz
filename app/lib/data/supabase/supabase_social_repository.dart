import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/community.dart';
import '../../domain/competitive.dart';
import '../social.dart';
import 'errors.dart';
import 'mappers.dart';

/// Players, profiles and the player's own sports from the database. Teams are
/// still sample data (product spec §9.3 comes later).
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  @override
  Future<List<Team>> teams(String cityId) => const SampleSocialRepository().teams(cityId);

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
