import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/markets.dart';
import '../data/auth/auth_repository.dart';
import '../data/repositories.dart';
import '../data/sample/sample_repositories.dart';
import '../data/social.dart';
import '../data/supabase/supabase_auth_repository.dart';
import '../data/supabase/supabase_booking_repository.dart';
import '../data/supabase/supabase_catalog_repository.dart';
import '../data/supabase/supabase_game_repository.dart';
import '../data/supabase/supabase_notification_repository.dart';
import '../data/supabase/supabase_social_repository.dart';
import '../domain/booking_engine.dart';
import '../domain/community.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import '../domain/pricing.dart';
import 'session.dart';

/// Overridden in `main()` with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('sharedPrefsProvider'));

/// Current UTC time. Overridden in tests to fix the clock.
final clockProvider = Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());

/// Whether the app was built with a Supabase project. Without one it runs on
/// the sample data with the demo sign-in (tests, offline demo).
final backendEnabledProvider = Provider<bool>((ref) => AppConfig.hasBackend);

/// Initialised in `main()` when the backend is enabled.
final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(backendEnabledProvider)
      ? SupabaseAuthRepository(ref.watch(supabaseClientProvider))
      : const DemoAuthRepository(),
);

/// Opens a link outside the app (the Telegram bot). Overridden in tests.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

final currentCityProvider = Provider<City>((ref) {
  final id = ref.watch(sessionProvider.select((s) => s.cityId));
  return kCities.firstWhere((c) => c.id == id, orElse: () => kCities.first);
});

/// Wall-clock time in the selected city.
final cityNowProvider = Provider<DateTime Function()>((ref) {
  final city = ref.watch(currentCityProvider);
  final clock = ref.watch(clockProvider);
  return () => venueNow(city, utcNow: clock());
});

final sampleBackendProvider = Provider<SampleBackend>((ref) {
  final name = ref.watch(sessionProvider.select((s) => s.userName)) ?? '';
  return SampleBackend(utcNow: ref.watch(clockProvider), meName: name);
});

/// The Supabase client for whoever is signed in now. Depending on the
/// signed-in name makes everything loaded for one player reload for the next.
SupabaseClient _clientForCurrentPlayer(Ref ref) {
  ref.watch(sessionProvider.select((s) => s.userName));
  return ref.watch(supabaseClientProvider);
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => ref.watch(backendEnabledProvider)
      ? SupabaseCatalogRepository(ref.watch(supabaseClientProvider))
      : ref.watch(sampleBackendProvider),
);

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => ref.watch(backendEnabledProvider)
      ? SupabaseBookingRepository(_clientForCurrentPlayer(ref))
      : ref.watch(sampleBackendProvider),
);

final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => ref.watch(backendEnabledProvider)
      ? SupabaseGameRepository(_clientForCurrentPlayer(ref))
      : ref.watch(sampleBackendProvider),
);

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => ref.watch(backendEnabledProvider)
      ? SupabaseSocialRepository(_clientForCurrentPlayer(ref))
      : ref.watch(sampleBackendProvider),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => ref.watch(backendEnabledProvider)
      ? SupabaseNotificationRepository(_clientForCurrentPlayer(ref))
      : ref.watch(sampleBackendProvider),
);

final sportsProvider = FutureProvider<List<Sport>>((ref) => ref.watch(catalogRepositoryProvider).sports());

final venuesProvider = FutureProvider<List<Venue>>(
  (ref) => ref.watch(catalogRepositoryProvider).venues(ref.watch(currentCityProvider).id),
);

final venueProvider = FutureProvider.family<Venue, String>((ref, id) => ref.watch(catalogRepositoryProvider).venue(id));

final bannersProvider = FutureProvider<List<BannerItem>>(
  (ref) => ref.watch(catalogRepositoryProvider).banners(ref.watch(currentCityProvider).id),
);

final tournamentsProvider = FutureProvider<List<TournamentItem>>(
  (ref) => ref.watch(catalogRepositoryProvider).tournaments(ref.watch(currentCityProvider).id),
);

typedef AvailabilityKey = ({String venueId, String courtId, DateTime date});

final availabilityProvider = FutureProvider.family<List<SlotView>, AvailabilityKey>(
  (ref, key) => ref.watch(bookingRepositoryProvider).availability(key.venueId, key.courtId, key.date),
);

final myBookingsProvider = FutureProvider<List<Booking>>((ref) => ref.watch(bookingRepositoryProvider).myBookings());

final gamesProvider = FutureProvider<List<Game>>(
  (ref) => ref.watch(gameRepositoryProvider).games(ref.watch(currentCityProvider).id),
);

final gameProvider = FutureProvider.family<Game, String>((ref, id) => ref.watch(gameRepositoryProvider).game(id));

final playerProvider = FutureProvider.family<Player, String>((ref, id) => ref.watch(gameRepositoryProvider).player(id));

/// Open Game Requests ("looking for players") in the current city, plus the
/// player's own.
final gameRequestsProvider = FutureProvider<List<GameRequest>>(
  (ref) => ref.watch(gameRepositoryProvider).requests(ref.watch(currentCityProvider).id),
);

final gameRequestProvider = FutureProvider.family<GameRequest, String>(
  (ref, id) => ref.watch(gameRepositoryProvider).request(id),
);

/// A search in the Find players list: the city is the current one.
typedef PlayerSearch = ({String? sportId, int minLevel, int maxLevel, String? query});

const PlayerSearch kAllPlayers = (sportId: null, minLevel: 1, maxLevel: 5, query: null);

final playersProvider = FutureProvider.family<List<PlayerProfile>, PlayerSearch>(
  (ref, search) => ref
      .watch(socialRepositoryProvider)
      .players(
        ref.watch(currentCityProvider).id,
        sportId: search.sportId,
        minLevel: search.minLevel,
        maxLevel: search.maxLevel,
        query: search.query,
      ),
);

final playerProfileProvider = FutureProvider.family<PlayerProfile, String>(
  (ref, id) => ref.watch(socialRepositoryProvider).profile(id),
);

/// The newest page of the inbox. Older pages are loaded with
/// `NotificationRepository.inbox(before: …)` by the screen.
final inboxProvider = FutureProvider<List<AppNotification>>(
  (ref) => ref.watch(notificationRepositoryProvider).inbox(),
);

final unreadCountProvider = FutureProvider<int>((ref) => ref.watch(notificationRepositoryProvider).unreadCount());

final communitySettingsProvider = FutureProvider<CommunitySettings>(
  (ref) => ref.watch(notificationRepositoryProvider).settings(),
);

/// A venue with its next free slots today, for the home feed.
typedef FreeToday = ({Venue venue, List<SlotView> next});

final freeTodayProvider = FutureProvider<List<FreeToday>>((ref) async {
  final venues = await ref.watch(venuesProvider.future);
  final bookings = ref.watch(bookingRepositoryProvider);
  final today = dateOnly(ref.watch(cityNowProvider)());
  final result = <FreeToday>[];
  for (final venue in venues) {
    final free = <SlotView>[];
    for (final court in venue.courts) {
      final slots = await bookings.availability(venue.id, court.id, today);
      free.addAll(slots.where((s) => s.state == SlotState.free));
    }
    if (free.isEmpty) continue;
    free.sort((a, b) => a.time.start.compareTo(b.time.start));
    final distinct = <DateTime>{};
    result.add((venue: venue, next: free.where((s) => distinct.add(s.time.start)).take(3).toList()));
  }
  return result;
});

/// Cheapest slot at a venue this week, for "from X" on venue cards.
int? venueFromPrice(Venue venue, DateTime today) {
  int? min;
  for (final sportId in venue.sportIds) {
    final range = feeRange(venue, sportId, today);
    if (range != null && (min == null || range.min < min)) min = range.min;
  }
  return min;
}

/// Refreshes everything that depends on games and Game Requests.
void refreshGames(WidgetRef ref) {
  ref.invalidate(gamesProvider);
  ref.invalidate(gameProvider);
  ref.invalidate(gameRequestsProvider);
  ref.invalidate(gameRequestProvider);
  ref.invalidate(inboxProvider);
  ref.invalidate(unreadCountProvider);
}

/// Refreshes everything that depends on bookings.
void refreshBookings(WidgetRef ref) {
  ref.invalidate(availabilityProvider);
  ref.invalidate(myBookingsProvider);
  ref.invalidate(freeTodayProvider);
  // A booking writes to the inbox (confirmed, cancelled).
  ref.invalidate(inboxProvider);
  ref.invalidate(unreadCountProvider);
}
