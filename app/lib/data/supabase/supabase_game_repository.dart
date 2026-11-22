import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/games.dart';
import '../repositories.dart';
import '../sample/sample_data.dart' show kMeId;
import 'errors.dart';
import 'mappers.dart';

/// Games through the database functions, which guarantee a game never has
/// more players than spots.
class SupabaseGameRepository implements GameRepository {
  SupabaseGameRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  Game _game(Object? json) => gameFromJson(Map<String, dynamic>.from(json as Map), myUserId: _me);

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
  Future<Game> join(String id) => guardJoin(() async => _game(await _client.rpc('join_game', params: {'p_game_id': id})));

  @override
  Future<Game> leave(String id) => guardJoin(() async => _game(await _client.rpc('leave_game', params: {'p_game_id': id})));

  @override
  Future<Player> player(String id) async {
    final userId = id == kMeId ? _me : id;
    if (userId == null) return Player(id: id, name: '');
    final row = await _client
        .from('profiles')
        .select('id, full_name, player_levels!player_levels_user_id_fkey(sport_id, level)')
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return Player(id: id, name: '');
    return playerFromRow(row, myUserId: _me);
  }
}
