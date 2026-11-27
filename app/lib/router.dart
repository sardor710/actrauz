import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_audit_screen.dart';
import 'features/admin/admin_banners_screen.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/admin/admin_home_screen.dart';
import 'features/admin/admin_review_screen.dart';
import 'features/admin/admin_sports_screen.dart';
import 'features/admin/admin_tournaments_screen.dart';
import 'features/admin/admin_venues_screen.dart';
import 'features/admin/tournament_editor_screen.dart';
import 'features/admin/tournament_participants_screen.dart';
import 'features/admin/venue_editor_screen.dart';
import 'features/booking/booking_screen.dart';
import 'features/bookings/bookings_screen.dart';
import 'features/games/create_game_screen.dart';
import 'features/games/create_request_screen.dart';
import 'features/games/game_request_screen.dart';
import 'features/games/game_screen.dart';
import 'features/games/games_screen.dart';
import 'features/games/past_games_screen.dart';
import 'features/home/home_screen.dart';
import 'features/inbox/inbox_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/owner/owner_calendar_screen.dart';
import 'features/owner/owner_dashboard_screen.dart';
import 'features/owner/owner_settings_screen.dart';
import 'features/owner/owner_venues_screen.dart';
import 'features/profile/my_sports_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/social/player_profile_screen.dart';
import 'features/social/leaderboard_screen.dart';
import 'features/social/social_screen.dart';
import 'features/tournaments/my_tournaments_screen.dart';
import 'features/tournaments/tournament_screen.dart';
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
      GoRoute(path: '/sports', builder: (context, state) => const MySportsScreen()),
      GoRoute(path: '/bookings', builder: (context, state) => const BookingsScreen()),
      GoRoute(path: '/inbox', builder: (context, state) => const InboxScreen()),
      GoRoute(path: '/my-tournaments', builder: (context, state) => const MyTournamentsScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const CommunitySettingsScreen()),
      // A player's public profile, opened from Find players and from a Game Request.
      GoRoute(
        path: '/players/:id',
        builder: (context, state) => PlayerProfileScreen(playerId: state.pathParameters['id']!),
      ),
      // A rated sport's leaderboard in the current city, from the Social tab
      // and from the rating on the profile.
      GoRoute(
        path: '/leaderboard/:sportId',
        builder: (context, state) => LeaderboardScreen(sportId: state.pathParameters['sportId']!),
      ),
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
          GoRoute(path: 'review', builder: (context, state) => const AdminReviewScreen()),
          GoRoute(
            path: 'tournaments',
            builder: (context, state) => const AdminTournamentsScreen(),
            routes: [
              GoRoute(path: 'new', builder: (context, state) => const TournamentEditorScreen()),
              GoRoute(
                path: ':tournamentId',
                builder: (context, state) => TournamentEditorScreen(
                  key: ValueKey(state.pathParameters['tournamentId']),
                  tournamentId: state.pathParameters['tournamentId'],
                ),
                routes: [
                  GoRoute(
                    path: 'participants',
                    builder: (context, state) =>
                        TournamentParticipantsScreen(
                          key: ValueKey(state.pathParameters['tournamentId']),
                          tournamentId: state.pathParameters['tournamentId']!,
                        ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: 'dashboard', builder: (context, state) => const AdminDashboardScreen()),
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
                  // Before ':id', which would take 'new' for a game id.
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => CreateGameScreen(bookingId: state.uri.queryParameters['booking']),
                  ),
                  // Past games, also before ':id'.
                  GoRoute(path: 'past', builder: (context, state) => const PastGamesScreen()),
                  // Game Requests, also before ':id'.
                  GoRoute(path: 'requests/new', builder: (context, state) => const CreateRequestScreen()),
                  GoRoute(
                    path: 'requests/:id',
                    builder: (context, state) => GameRequestScreen(requestId: state.pathParameters['id']!),
                  ),
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
            routes: [
              GoRoute(
                path: '/tournaments',
                builder: (context, state) => const TournamentsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => TournamentScreen(tournamentId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/social', builder: (context, state) => const SocialScreen())],
          ),
        ],
      ),
    ],
  );
});
