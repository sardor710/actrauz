import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/owner_repository.dart';
import '../data/supabase/supabase_owner_repository.dart';
import '../domain/models.dart';
import '../domain/owner.dart';
import 'providers.dart';

/// Owner operations: the sample backend's (sharing its bookings) without a
/// Supabase project, the database functions with one.
final ownerRepositoryProvider = Provider<OwnerRepository>((ref) {
  if (!ref.watch(backendEnabledProvider)) return ref.watch(sampleBackendProvider).owner;
  // Depending on the signed-in name reloads everything for the next user,
  // as the player repositories do.
  ref.watch(sessionProvider.select((s) => s.userName));
  return SupabaseOwnerRepository(ref.watch(supabaseClientProvider), ref.watch(catalogRepositoryProvider));
});

/// Venues the signed-in user manages; empty for a plain player.
final myVenuesProvider = FutureProvider<List<Venue>>((ref) => ref.watch(ownerRepositoryProvider).myVenues());

typedef OwnerCalendarKey = ({String venueId, String courtId, DateTime from});

/// Days shown by [ownerCalendarProvider].
const kOwnerCalendarDays = 7;

/// One court's week from `from` (a venue wall-clock date).
final ownerCalendarProvider = FutureProvider.family<OwnerCalendar, OwnerCalendarKey>(
  (ref, key) => ref.watch(ownerRepositoryProvider).calendar(key.venueId, key.courtId, key.from, kOwnerCalendarDays),
);

typedef OwnerDashboardKey = ({String venueId, String? courtId, DateTime from, DateTime to});

/// A venue's numbers over an inclusive date range; `courtId` null = every court.
final ownerDashboardProvider = FutureProvider.family<OwnerDashboard, OwnerDashboardKey>(
  (ref, key) => ref
      .watch(ownerRepositoryProvider)
      .dashboard(key.venueId, courtId: key.courtId, from: key.from, to: key.to),
);

/// Refreshes the owner calendar and dashboard, the venues (after an hours or
/// price change) and everything else that depends on bookings.
void refreshOwner(WidgetRef ref) {
  ref.invalidate(ownerCalendarProvider);
  ref.invalidate(ownerDashboardProvider);
  ref.invalidate(myVenuesProvider);
  ref.invalidate(venuesProvider);
  ref.invalidate(venueProvider);
  refreshBookings(ref);
}
