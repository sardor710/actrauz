import 'package:flutter/material.dart' show TimeOfDay;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/brackets.dart';
import '../../domain/tournaments.dart';
import '../organizer_repository.dart';
import 'errors.dart';
import 'mappers.dart';

/// The organiser's draw, schedule and score calls (M8a). The database checks
/// that the caller organises the tournament and does all the validation.
class SupabaseOrganizerRepository implements OrganizerRepository {
  SupabaseOrganizerRepository(this._client);

  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  Map<String, dynamic> _map(Object? json) => Map<String, dynamic>.from(json as Map);

  /// A draw call. The wrappers return the draw as the caller sees it; null
  /// (no draw any more, or a draft the caller may not see) is `notFound`.
  Future<CategoryDraw> _draw(String fn, Map<String, dynamic> params) => guardTournament(() async {
    final json = await _client.rpc(fn, params: params);
    if (json == null) throw const TournamentException(TournamentError.notFound);
    return categoryDrawFromJson(_map(json), myUserId: _me);
  });

  @override
  Future<List<TournamentSummary>> organizedTournaments() => guardTournament(() async {
    final rows = await _client.rpc('my_organized_tournaments');
    return [for (final row in rows as List) tournamentSummaryFromJson(_map(row))];
  });

  @override
  Future<List<AdminRegistration>> entries(String tournamentId) => guardTournament(() async {
    final rows = await _client.rpc('organizer_entries', params: {'p_tournament_id': tournamentId});
    return [for (final row in rows as List) adminRegistrationFromJson(_map(row), myUserId: _me)];
  });

  @override
  Future<CategoryDraw> makeDraw(String categoryId, DrawFormat format, {int? groupSize, int? advance}) => _draw(
    'make_draw',
    {'p_category_id': categoryId, 'p_format': drawFormatCode(format), 'p_group_size': groupSize, 'p_advance': advance},
  );

  @override
  Future<CategoryDraw> swapEntries(String categoryId, String registrationA, String registrationB) => _draw(
    'swap_draw_entries',
    {'p_category_id': categoryId, 'p_registration_a': registrationA, 'p_registration_b': registrationB},
  );

  @override
  Future<CategoryDraw> publish(String categoryId) => _draw('publish_draw', {'p_category_id': categoryId});

  @override
  Future<CategoryDraw> redo(String categoryId) => _draw('redo_draw', {'p_category_id': categoryId});

  @override
  Future<TournamentMatch> scheduleMatch(String matchId, {String? courtId, DateTime? startsAt, String? placeNote}) =>
      guardTournament(() async {
        final json = await _client.rpc(
          'schedule_match',
          params: {
            'p_match_id': matchId,
            'p_court_id': courtId,
            'p_starts_at': startsAt == null ? null : isoLocal(startsAt),
            'p_place_note': placeNote,
          },
        );
        if (json == null) throw const TournamentException(TournamentError.notFound);
        return tournamentMatchFromJson(_map(json));
      });

  @override
  Future<FillResult> fillDay(
    String tournamentId,
    DateTime day,
    List<String> courtIds,
    TimeOfDay from, {
    List<String>? categoryIds,
  }) => guardTournament(() async {
    final json = await _client.rpc(
      'fill_day',
      params: {
        'p_tournament_id': tournamentId,
        'p_day': isoDate(day),
        'p_court_ids': courtIds,
        'p_from': timeOfDayJson(from),
        'p_category_ids': categoryIds,
      },
    );
    return fillResultFromJson(_map(json));
  });

  @override
  Future<CategoryDraw> enterScore(String matchId, MatchOutcome outcome, {Side? winner, List<List<int>>? sets}) =>
      _draw('enter_match_score', {
        'p_match_id': matchId,
        'p_outcome': matchOutcomeCode(outcome),
        'p_winner': winner == null ? null : sideCode(winner),
        'p_sets': sets,
      });

  @override
  Future<CategoryDraw> withdraw(String registrationId) =>
      _draw('withdraw_entry', {'p_registration_id': registrationId});
}
