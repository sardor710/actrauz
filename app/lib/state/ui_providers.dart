import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/social.dart';
import '../domain/games.dart';
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

final socialRepositoryProvider = Provider<SocialRepository>((ref) => const SampleSocialRepository());

final teamsProvider = FutureProvider<List<Team>>(
  (ref) => ref.watch(socialRepositoryProvider).teams(ref.watch(currentCityProvider).id),
);

final playersProvider = FutureProvider<List<Player>>(
  (ref) => ref.watch(socialRepositoryProvider).players(ref.watch(currentCityProvider).id),
);
