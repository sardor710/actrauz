import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/booking/booking_screen.dart';
import 'features/bookings/bookings_screen.dart';
import 'features/games/game_screen.dart';
import 'features/games/games_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/shell/home_shell.dart';
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (context, state) => const HomeScreen())],
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
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [GoRoute(path: 'bookings', builder: (context, state) => const BookingsScreen())],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
