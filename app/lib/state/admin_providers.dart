import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/admin_repository.dart';
import '../data/supabase/supabase_admin_repository.dart';
import '../domain/admin.dart';
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

/// The newest 50 audit entries.
final adminAuditProvider = FutureProvider<List<AuditEntry>>((ref) => ref.watch(adminRepositoryProvider).auditLog());

/// Refreshes the admin lists and everything that shows catalog or booking
/// data, so player and owner screens see an admin change at once.
void refreshAdmin(WidgetRef ref) {
  ref.invalidate(isAdminProvider);
  ref.invalidate(adminVenuesProvider);
  ref.invalidate(adminSportsProvider);
  ref.invalidate(adminBannersProvider);
  ref.invalidate(adminAuditProvider);
  ref.invalidate(sportsProvider);
  ref.invalidate(bannersProvider);
  refreshOwner(ref);
}
