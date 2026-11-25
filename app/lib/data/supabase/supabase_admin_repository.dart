import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/admin.dart';
import '../../domain/tournaments.dart';
import '../admin_repository.dart';
import 'errors.dart';
import 'mappers.dart';

/// Admin operations through the `admin_*` database functions, which check
/// that the caller is in `app_admins` and do all the validation.
class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<T>> _list<T>(String fn, T Function(Map<String, dynamic>) map, {Map<String, dynamic>? params}) =>
      guardBooking(() async {
        final rows = await _client.rpc(fn, params: params);
        return [for (final row in (rows as List? ?? const [])) map(Map<String, dynamic>.from(row as Map))];
      });

  Future<String> _id(String fn, Map<String, dynamic> params) => guardBooking(() async {
    return (await _client.rpc(fn, params: params)).toString();
  });

  Future<void> _call(String fn, Map<String, dynamic> params) => guardBooking(() async {
    await _client.rpc(fn, params: params);
  });

  @override
  Future<bool> isAdmin() async {
    try {
      return await _client.rpc('am_i_admin') == true;
    } catch (_) {
      // Signed out, offline or an older backend: no admin screens.
      return false;
    }
  }

  @override
  Future<List<AdminVenue>> venues() => _list('admin_list_venues', adminVenueFromJson);

  @override
  Future<String> saveVenue(VenueDraft draft) => _id('admin_save_venue', {'p_venue': venueDraftJson(draft)});

  @override
  Future<void> deleteVenue(String venueId) => _call('admin_delete_venue', {'p_venue_id': venueId});

  @override
  Future<String> saveCourt(CourtDraft draft) => _id('admin_save_court', {'p_court': courtDraftJson(draft)});

  @override
  Future<String> duplicateCourt(String courtId) => _id('admin_duplicate_court', {'p_court_id': courtId});

  @override
  Future<void> deleteCourt(String courtId) => _call('admin_delete_court', {'p_court_id': courtId});

  @override
  Future<List<OwnerRef>> searchUsers(String query) async {
    // The backend returns nothing for a query this short anyway.
    if (query.trim().length < 2) return const [];
    return _list('admin_search_users', ownerRefFromJson, params: {'p_query': query.trim()});
  }

  @override
  Future<void> setOwner(String venueId, String userId, {required bool assigned}) =>
      _call('admin_set_owner', {'p_venue_id': venueId, 'p_user_id': userId, 'p_assigned': assigned});

  @override
  Future<List<AdminSport>> sports() => _list('admin_list_sports', adminSportFromJson);

  @override
  Future<String> saveSport(SportDraft draft, {required bool create}) =>
      _id('admin_save_sport', {'p_sport': sportDraftJson(draft), 'p_create': create});

  @override
  Future<List<AdminBanner>> banners() => _list('admin_list_banners', adminBannerFromJson);

  @override
  Future<String> saveBanner(BannerDraft draft) => _id('admin_save_banner', {'p_banner': bannerDraftJson(draft)});

  @override
  Future<void> deleteBanner(String bannerId) => _call('admin_delete_banner', {'p_banner_id': bannerId});

  @override
  Future<List<AuditEntry>> auditLog({int limit = 50, DateTime? before}) => _list(
    'admin_audit_log',
    auditEntryFromJson,
    params: {'p_limit': limit, 'p_before': before?.toUtc().toIso8601String()},
  );

  // ---- Tournaments ----

  String? get _me => _client.auth.currentUser?.id;

  Map<String, dynamic> _map(Object? json) => Map<String, dynamic>.from(json as Map);

  Future<AdminRegistration> _entry(String fn, Map<String, dynamic> params) => guardTournament(
    () async => adminRegistrationFromJson(_map(await _client.rpc(fn, params: params)), myUserId: _me),
  );

  @override
  Future<List<AdminTournament>> tournaments() => guardTournament(() async {
    final rows = await _client.rpc('admin_list_tournaments');
    return [for (final row in rows as List) adminTournamentFromJson(_map(row), myUserId: _me)];
  });

  @override
  Future<String> saveTournament(TournamentDraft draft) => guardTournament(
    () async => (await _client.rpc('admin_save_tournament', params: {'p_tournament': tournamentDraftJson(draft)})).toString(),
  );

  @override
  Future<String> saveCategory(CategoryDraft draft) => guardTournament(
    () async => (await _client.rpc('admin_save_category', params: {'p_category': categoryDraftJson(draft)})).toString(),
  );

  @override
  Future<void> deleteCategory(String categoryId) => guardTournament(() async {
    await _client.rpc('admin_delete_category', params: {'p_category_id': categoryId});
  });

  @override
  Future<List<AdminRegistration>> registrations(String tournamentId) => guardTournament(() async {
    final rows = await _client.rpc('admin_list_registrations', params: {'p_tournament_id': tournamentId});
    return [for (final row in rows as List) adminRegistrationFromJson(_map(row), myUserId: _me)];
  });

  @override
  Future<AdminRegistration> setPaid(String registrationId, bool paid) =>
      _entry('admin_set_paid', {'p_registration_id': registrationId, 'p_paid': paid});

  @override
  Future<AdminRegistration> removeRegistration(String registrationId) =>
      _entry('admin_remove_registration', {'p_registration_id': registrationId});

  @override
  Future<AdminRegistration> moveRegistration(String registrationId, String categoryId) =>
      _entry('admin_move_registration', {'p_registration_id': registrationId, 'p_category_id': categoryId});

  @override
  Future<AdminRegistration> addRegistration(String categoryId, String userId, {String? partnerId}) =>
      _entry('admin_add_registration', {
        'p_category_id': categoryId,
        'p_user_id': userIdOut(userId, _me),
        'p_partner_id': partnerId == null ? null : userIdOut(partnerId, _me),
      });

  @override
  Future<int> offerNext(String categoryId) => guardTournament(
    () async => (await _client.rpc('admin_offer_next', params: {'p_category_id': categoryId})) as int,
  );

  @override
  Future<AdminDashboard> dashboard({String? cityId, required DateTime from, required DateTime to}) =>
      guardTournament(() async {
        final json = await _client.rpc(
          'admin_dashboard',
          params: {'p_city_id': cityId, 'p_from': isoDate(from), 'p_to': isoDate(to)},
        );
        return adminDashboardFromJson(_map(json));
      });
}
