import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_repository.dart';
import '../data/supabase/supabase_admin_repository.dart';
import '../domain/admin.dart';
import '../domain/tournaments.dart';
import 'owner_providers.dart';
import 'providers.dart';

/// Admin operations: the sample backend's (the demo player is an admin)
/// without a Supabase project, the database functions with one.
final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  if (!ref.watch(backendEnabledProvider)) return ref.watch(sampleBackendProvider).admin;
  // Depending on the signed-in name reloads everything for the next user.
  ref.watch(sessionProvider.select((s) => s.userName));
  return SupabaseAdminRepository(ref.watch(supabaseClientProvider));
});

/// Whether the signed-in user may open the admin screens.
final isAdminProvider = FutureProvider<bool>((ref) => ref.watch(adminRepositoryProvider).isAdmin());

/// Every venue, active or not, newest first.
final adminVenuesProvider = FutureProvider<List<AdminVenue>>((ref) => ref.watch(adminRepositoryProvider).venues());

/// Every sport, by sort order.
final adminSportsProvider = FutureProvider<List<AdminSport>>((ref) => ref.watch(adminRepositoryProvider).sports());

/// Every banner, by sort order.
final adminBannersProvider = FutureProvider<List<AdminBanner>>((ref) => ref.watch(adminRepositoryProvider).banners());

/// Disputed and flagged scores and open reports, for the Review screen and
/// the count on the admin home.
final adminReviewProvider = FutureProvider<AdminReview>((ref) => ref.watch(adminRepositoryProvider).review());

/// The newest 50 audit entries.
final adminAuditProvider = FutureProvider<List<AuditEntry>>((ref) => ref.watch(adminRepositoryProvider).auditLog());

/// Every tournament, active or not, latest start first.
final adminTournamentsProvider = FutureProvider<List<AdminTournament>>(
  (ref) => ref.watch(adminRepositoryProvider).tournaments(),
);

/// Every entry of one tournament, any state.
final adminRegistrationsProvider = FutureProvider.family<List<AdminRegistration>, String>(
  (ref, tournamentId) => ref.watch(adminRepositoryProvider).registrations(tournamentId),
);

/// The admin dashboard's period: [cityId] `null` = every city; [from] and
/// [to] are the first and last day (the time of day is ignored).
typedef DashboardQuery = ({String? cityId, DateTime from, DateTime to});

final adminDashboardProvider = FutureProvider.family<AdminDashboard, DashboardQuery>(
  (ref, query) => ref.watch(adminRepositoryProvider).dashboard(cityId: query.cityId, from: query.from, to: query.to),
);

/// Refreshes the admin lists and everything that shows catalog or booking
/// data, so player and owner screens see an admin change at once.
void refreshAdmin(WidgetRef ref) {
  ref.invalidate(isAdminProvider);
  ref.invalidate(adminVenuesProvider);
  ref.invalidate(adminSportsProvider);
  ref.invalidate(adminBannersProvider);
  ref.invalidate(adminAuditProvider);
  ref.invalidate(adminReviewProvider);
  ref.invalidate(adminTournamentsProvider);
  ref.invalidate(adminRegistrationsProvider);
  ref.invalidate(adminDashboardProvider);
  ref.invalidate(sportsProvider);
  ref.invalidate(bannersProvider);
  refreshTournaments(ref);
  refreshOwner(ref);
}
