import '../../domain/admin.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';

/// The demo player's sports and ratings in memory, with the database's rules
/// (`app.set_my_sport`, `app.remove_my_sport`, `app.my_sports`,
/// `app.sync_level` in supabase/migrations/20261127100000_ratings.sql).
///
/// Levels are the ticked sports; a rated sport's level is derived from its
/// rating. A rating outlives its level: unticking a sport keeps it, and it
/// comes back when the sport is ticked again.
class SampleSports {
  /// Every rating gets its derived level, as `app.sync_level` writes it.
  SampleSports({
    required Map<String, int> levels,
    required Map<String, SportRating> ratings,
    required this.sportOf,
  }) : levels = {...levels, for (final e in ratings.entries) e.key: levelOfRating(e.value.rating)},
       ratings = {...ratings};

  /// Ticked sports: sport id → level 1–5.
  final Map<String, int> levels;

  /// Rated sport id → rating, ticked or not.
  final Map<String, SportRating> ratings;

  /// The catalogue entry for a sport id, or null for an unknown one.
  final AdminSport? Function(String sportId) sportOf;

  /// The ticked sports in catalogue order (sort order, then id).
  List<MySport> mySports() {
    final ticked = [
      for (final id in levels.keys)
        if (sportOf(id) case final sport?) sport,
    ]..sort((a, b) {
        final bySort = a.sortOrder.compareTo(b.sortOrder);
        return bySort != 0 ? bySort : a.sport.id.compareTo(b.sport.id);
      });
    return [
      for (final s in ticked)
        s.sport.competitiveRating
            ? MySport(
                sportId: s.sport.id,
                level: levels[s.sport.id],
                rating: ratings[s.sport.id],
                canRetake: (ratings[s.sport.id]?.ratedGames ?? 0) == 0,
              )
            : MySport(sportId: s.sport.id, level: levels[s.sport.id]),
    ];
  }

  /// A level 1–5 for a simple sport; the questionnaire answers for a rated
  /// one until its first rated game, after which the rating stays and only
  /// the level comes back. Anything else is [JoinError.invalidArgument].
  void set(String sportId, {int? level, List<int>? answers}) {
    final sport = sportOf(sportId);
    if (sport == null || !sport.active) throw const JoinException(JoinError.invalidArgument);

    if (!sport.sport.competitiveRating) {
      if (level == null || level < 1 || level > 5 || answers != null) {
        throw const JoinException(JoinError.invalidArgument);
      }
      levels[sportId] = level;
      return;
    }

    if (level != null) throw const JoinException(JoinError.invalidArgument);
    final current = ratings[sportId];
    if (current == null || current.ratedGames == 0) {
      final double rating;
      try {
        rating = questionnaireRating(answers ?? const []);
      } on ArgumentError {
        throw const JoinException(JoinError.invalidArgument);
      }
      ratings[sportId] = SportRating(rating: rating);
    }
    levels[sportId] = levelOfRating(ratings[sportId]!.rating);
  }

  /// Unticks a sport; its rating stays.
  void remove(String sportId) => levels.remove(sportId);
}

/// The rating range of a new game or Game Request, as `app.rating_range`
/// decides it: null in a simple sport; in a rated one the range given (both
/// ends, 1.00–7.00, low to high, two decimals) or else the one the level range
/// stands for. Anything else is [JoinError.invalidArgument].
({double min, double max})? ratingRangeFor(
  AdminSport sport, {
  required double? minRating,
  required double? maxRating,
  required int minLevel,
  required int maxLevel,
}) {
  if (!sport.sport.competitiveRating) return null;
  if (minRating == null && maxRating == null) return ratingRangeOfLevels(minLevel, maxLevel);
  if (minRating == null || maxRating == null) throw const JoinException(JoinError.invalidArgument);
  final min = roundRating(minRating);
  final max = roundRating(maxRating);
  if (min < RatingRules.min || max > RatingRules.max || min > max) {
    throw const JoinException(JoinError.invalidArgument);
  }
  return (min: min, max: max);
}
