import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/community.dart';
import '../../domain/games.dart';
import '../repositories.dart';
import '../sample/sample_data.dart' show kMeId;
import 'errors.dart';
import 'mappers.dart';

/// Games and Game Requests through the database functions, which guarantee a
/// game never has more players than spots and apply who may see what.
///
/// User ids cross this boundary both ways: the signed-in player is [kMeId]
/// in everything returned, and [kMeId] in an argument becomes their real id.
class SupabaseGameRepository implements GameRepository {
  SupabaseGameRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  Game _game(Object? json) => gameFromJson(Map<String, dynamic>.from(json as Map), myUserId: _me);

  GameRequest _gameRequest(Object? json) => gameRequestFromJson(Map<String, dynamic>.from(json as Map), myUserId: _me);

  /// Calls [function] and reads one game back. Every failure is a [JoinException].
  Future<Game> _callGame(String function, [Map<String, dynamic>? params]) =>
      guardJoin(() async => _game(await _client.rpc(function, params: params)));

  Future<GameRequest> _callRequest(String function, [Map<String, dynamic>? params]) =>
      guardJoin(() async => _gameRequest(await _client.rpc(function, params: params)));

  @override
  Future<List<Game>> games(String cityId) async {
    final rows = await _client.rpc('list_games', params: {'p_city_id': cityId});
    return [for (final row in rows as List) _game(row)];
  }

  @override
  Future<Game> game(String id) async {
    final json = await _client.rpc('get_game', params: {'p_game_id': id});
    if (json == null) throw StateError('Unknown game $id');
    return _game(json);
  }

  @override
  Future<Game> join(String id) => _callGame('join_game', {'p_game_id': id});

  @override
  Future<Game> leave(String id) => _callGame('leave_game', {'p_game_id': id});

  @override
  Future<Player> player(String id) async {
    final userId = userIdOut(id, _me);
    if (id == kMeId && _me == null) return Player(id: id, name: '');
    final row = await _client
        .from('profiles')
        .select('id, full_name, deleted_at, player_levels!player_levels_user_id_fkey(sport_id, level)')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return Player(id: id, name: '');
    return playerFromRow(row, myUserId: _me);
  }

  @override
  Future<Game> create(GameDraft draft) => _callGame('create_game', {'p_game': gameDraftJson(draft)});

  @override
  Future<Game> requestToJoin(String gameId) => _callGame('request_to_join', {'p_game_id': gameId});

  @override
  Future<Game> withdrawRequest(String requestId) => _callGame('withdraw_join_request', {'p_request_id': requestId});

  @override
  Future<Game> decideRequest(String requestId, {required bool approve}) =>
      _callGame('decide_join_request', {'p_request_id': requestId, 'p_approve': approve});

  @override
  Future<Game> invite(String gameId, String userId) =>
      _callGame('invite_to_game', {'p_game_id': gameId, 'p_user_id': userIdOut(userId, _me)});

  @override
  Future<Game> declineInvite(String gameId) => _callGame('decline_invite', {'p_game_id': gameId});

  @override
  Future<Game> removeParticipant(String gameId, String userId) =>
      _callGame('host_remove_participant', {'p_game_id': gameId, 'p_user_id': userIdOut(userId, _me)});

  @override
  Future<Game> updateGame(String gameId, {String? note, required int spots}) =>
      _callGame('host_update_game', {'p_game_id': gameId, 'p_note': note, 'p_spots': spots});

  @override
  Future<Game> cancelGame(String gameId, {required bool cancelBooking}) =>
      _callGame('host_cancel_game', {'p_game_id': gameId, 'p_cancel_booking': cancelBooking});

  @override
  Future<List<GameRequest>> requests(String cityId) async {
    final rows = await _client.rpc('list_game_requests', params: {'p_city_id': cityId});
    return [for (final row in rows as List) _gameRequest(row)];
  }

  @override
  Future<GameRequest> request(String id) async {
    final json = await _client.rpc('get_game_request', params: {'p_request_id': id});
    if (json == null) throw StateError('Unknown request $id');
    return _gameRequest(json);
  }

  @override
  Future<GameRequest> createRequest(GameRequestDraft draft) =>
      _callRequest('create_game_request', {'p_request': gameRequestDraftJson(draft)});

  @override
  Future<GameRequest> imIn(String id) => _callRequest('request_interest', {'p_request_id': id});

  @override
  Future<GameRequest> withdrawInterest(String id) => _callRequest('withdraw_interest', {'p_request_id': id});

  @override
  Future<GameRequest> removeInterested(String id, String userId) =>
      _callRequest('remove_interested', {'p_request_id': id, 'p_user_id': userIdOut(userId, _me)});

  @override
  Future<GameRequest> cancelRequest(String id) => _callRequest('cancel_game_request', {'p_request_id': id});

  @override
  Future<Game> convertRequest(String id, PlacePick place) =>
      _callGame('convert_game_request', {'p_request_id': id, 'p_place': placePickJson(place)});
}
