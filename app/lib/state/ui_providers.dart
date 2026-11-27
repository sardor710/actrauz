import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/teams.dart';
import 'providers.dart';

/// Venues the player has marked with a heart. Kept for this app run only
/// until favourites are stored on the backend.
class FavouritesController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String venueId) {
    state = state.contains(venueId) ? ({...state}..remove(venueId)) : {...state, venueId};
  }
}

final favouritesProvider = NotifierProvider<FavouritesController, Set<String>>(FavouritesController.new);

/// Sport chosen on the Games tab, or from "Games by sport" on Home. `null` = all.
final gamesSportFilterProvider = StateProvider<String?>((ref) => null);

/// Day chosen on the Games tab as days from today. `null` = every day.
final gamesDayProvider = StateProvider<int?>((ref) => null);

/// The Social tab's teams: the player's own first, then the city's others.
final teamsProvider = FutureProvider<List<Team>>(
  (ref) => ref.watch(socialRepositoryProvider).teams(ref.watch(currentCityProvider).id),
);

/// Refreshes everything that shows teams after a team call: the lists, the
/// team pages, the profiles that list a player's teams, and the inbox.
void refreshTeams(WidgetRef ref) {
  ref.invalidate(teamsProvider);
  ref.invalidate(teamProvider);
  ref.invalidate(playerProfileProvider);
  ref.invalidate(inboxProvider);
  ref.invalidate(unreadCountProvider);
}


/// The Games tab list: 0 = games, 1 = Game Requests.
final gamesTabProvider = StateProvider<int>((ref) => 0);
