import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/brackets.dart';
import '../../domain/tournaments.dart';
import '../repositories.dart';
import 'errors.dart';
import 'mappers.dart';

/// Tournaments and registration through the database functions, which keep a
/// category from ever counting more entries than its cap.
///
/// User ids cross this boundary both ways: the signed-in player is `kMeId`
/// in everything returned, and `kMeId` as a partner id becomes their real id.
class SupabaseTournamentRepository implements TournamentRepository {
  SupabaseTournamentRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  Map<String, dynamic> _map(Object? json) => Map<String, dynamic>.from(json as Map);

  Future<Registration> _entry(String function, Map<String, dynamic> params) => guardTournament(
    () async => registrationFromJson(_map(await _client.rpc(function, params: params)), myUserId: _me),
  );

  @override
  Future<List<Tournament>> list(
    String cityId, {
    String? sportId,
    DateTime? from,
    TournamentSort sort = TournamentSort.date,
  }) => guardTournament(() async {
    final rows = await _client.rpc(
      'list_tournaments',
      params: {
        'p_city_id': cityId,
        'p_sport_id': sportId,
        'p_from': from == null ? null : isoDate(from),
        'p_sort': sort == TournamentSort.az ? 'az' : 'date',
      },
    );
    return [for (final row in rows as List) tournamentFromJson(_map(row), myUserId: _me)];
  });

  @override
  Future<Tournament> get(String id) => guardTournament(() async {
    final json = await _client.rpc('get_tournament', params: {'p_tournament_id': id});
    if (json == null) throw const TournamentException(TournamentError.notFound);
    return tournamentFromJson(_map(json), myUserId: _me);
  });

  @override
  Future<Registration> register(String categoryId, {String? partnerId}) => _entry('register_tournament', {
    'p_category_id': categoryId,
    'p_partner_id': partnerId == null ? null : userIdOut(partnerId, _me),
  });

  @override
  Future<Registration> respondPartner(String registrationId, {required bool accept}) =>
      _entry('respond_partner', {'p_registration_id': registrationId, 'p_accept': accept});

  @override
  Future<Registration> cancel(String registrationId) =>
      _entry('cancel_registration', {'p_registration_id': registrationId});

  @override
  Future<Registration> joinWaitlist(String categoryId, {String? partnerId}) => _entry('join_waitlist', {
    'p_category_id': categoryId,
    'p_partner_id': partnerId == null ? null : userIdOut(partnerId, _me),
  });

  @override
  Future<Registration> claimOffer(String registrationId) =>
      _entry('claim_offer', {'p_registration_id': registrationId});

  @override
  Future<List<Registration>> myRegistrations() => guardTournament(() async {
    final rows = await _client.rpc('my_registrations');
    return [for (final row in rows as List) registrationFromJson(_map(row), myUserId: _me)];
  });

  @override
  Future<PlayerRef?> findPlayerByPhone(String phone) => guardTournament(() async {
    final json = await _client.rpc('find_player_by_phone', params: {'p_phone': phone});
    return json == null ? null : playerRefFromJson(_map(json), myUserId: _me);
  });

  @override
  Future<TournamentBracket> bracket(String tournamentId) => guardTournament(() async {
    final json = await _client.rpc('tournament_bracket', params: {'p_tournament_id': tournamentId});
    return tournamentBracketFromJson(_map(json), myUserId: _me);
  });

  @override
  Future<List<MyMatch>> myMatches() => guardTournament(() async {
    final rows = await _client.rpc('my_tournament_matches');
    return [for (final row in rows as List) myMatchFromJson(_map(row))];
  });
}
