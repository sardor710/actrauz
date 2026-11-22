import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models.dart';
import '../repositories.dart';
import 'mappers.dart';

/// Venues, sports, banners and tournaments read straight from their tables;
/// row-level security lets everyone read the active ones.
class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client);

  final SupabaseClient _client;

  /// A venue with everything slot generation and pricing need. The
  /// constraint names say which relationship to follow.
  static const _venueColumns =
      '*, '
      'working_hours!working_hours_venue_id_fkey(*), '
      'courts!courts_venue_id_fkey(*, '
      'price_rules!price_rules_court_id_fkey(*), '
      'working_hours!working_hours_court_id_fkey(*))';

  @override
  Future<List<Sport>> sports() async {
    final rows = await _client.from('sports').select().order('sort_order');
    return rows.map(sportFromRow).toList();
  }

  @override
  Future<List<Venue>> venues(String cityId) async {
    final rows = await _client.from('venues').select(_venueColumns).eq('city_id', cityId).order('created_at').order('id');
    return rows.map(venueFromRow).toList();
  }

  @override
  Future<Venue> venue(String id) async {
    final row = await _client.from('venues').select(_venueColumns).eq('id', id).maybeSingle();
    if (row == null) throw StateError('Unknown venue $id');
    return venueFromRow(row);
  }

  @override
  Future<List<BannerItem>> banners(String cityId) async {
    final rows = await _client.from('banners').select().or('city_id.is.null,city_id.eq.$cityId').order('sort_order');
    return rows.map(bannerFromRow).toList();
  }

  @override
  Future<List<TournamentItem>> tournaments(String cityId) async {
    final rows = await _client
        .from('tournaments')
        .select('*, venues!tournaments_venue_id_fkey(name_uz, name_ru, name_en)')
        .eq('city_id', cityId)
        .order('starts_on');
    return rows.map(tournamentFromRow).toList();
  }
}
