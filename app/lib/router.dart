import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_audit_screen.dart';
import 'features/admin/admin_banners_screen.dart';
import 'features/admin/admin_home_screen.dart';
import 'features/admin/admin_sports_screen.dart';
import 'features/admin/admin_venues_screen.dart';
import 'features/admin/venue_editor_screen.dart';
import 'features/booking/booking_screen.dart';
import 'features/bookings/bookings_screen.dart';
import 'features/games/game_screen.dart';
import 'features/games/games_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/owner/owner_calendar_screen.dart';
import 'features/owner/owner_dashboard_screen.dart';
import 'features/owner/owner_settings_screen.dart';
import 'features/owner/owner_venues_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/social/social_screen.dart';
import 'features/tournaments/tournaments_screen.dart';
import 'features/venues/venue_screen.dart';
import 'features/venues/venues_screen.dart';
import 'state/providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect when the player finishes onboarding or signs out.
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider.select((s) => s.onboarded), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final onboarded = ref.read(sessionProvider).onboarded;
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!onboarded) return atOnboarding ? null : '/onboarding';
      return atOnboarding ? '/home' : null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      // Opened on top of the tabs from the header, so "back" returns to them.
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/bookings', builder: (context, state) => const BookingsScreen()),
      // Venue owners and admins only; the screens show nothing to anyone else.
      GoRoute(
        path: '/owner',
        builder: (context, state) => const OwnerVenuesScreen(),
        routes: [
          GoRoute(
            path: ':venueId',
            builder: (context, state) => OwnerCalendarScreen(venueId: state.pathParameters['venueId']!),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (context, state) => OwnerSettingsScreen(venueId: state.pathParameters['venueId']!),
              ),
              GoRoute(
                path: 'dashboard',
                builder: (context, state) => OwnerDashboardScreen(venueId: state.pathParameters['venueId']!),
              ),
            ],
          ),
        ],
      ),
      // Actra admins only; the screens show a locked state to anyone else.
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomeScreen(),
        routes: [
          GoRoute(
            path: 'venues',
            builder: (context, state) => const AdminVenuesScreen(),
            routes: [
              GoRoute(path: 'new', builder: (context, state) => const VenueEditorScreen()),
              GoRoute(
                path: ':venueId',
                builder: (context, state) => VenueEditorScreen(venueId: state.pathParameters['venueId']),
              ),
            ],
          ),
          GoRoute(path: 'sports', builder: (context, state) => const AdminSportsScreen()),
          GoRoute(path: 'banners', builder: (context, state) => const AdminBannersScreen()),
          GoRoute(path: 'audit', builder: (context, state) => const AdminAuditScreen()),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (context, state) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/games',
                builder: (context, state) => const GamesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => GameScreen(gameId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/venues',
                builder: (context, state) => const VenuesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => VenueScreen(venueId: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'book/:courtId',
                        builder: (context, state) => BookingScreen(
                          venueId: state.pathParameters['id']!,
                          courtId: state.pathParameters['courtId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/tournaments', builder: (context, state) => const TournamentsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/social', builder: (context, state) => const SocialScreen())],
          ),
        ],
      ),
    ],
  );
});
