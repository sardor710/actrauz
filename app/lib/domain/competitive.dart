// Ratings 1.00-7.00 in the rated sports (padel and tennis), the starting
// questionnaire and "My sports" (design 2026-11-27-actra-m7-competitive
// §5.1-§5.3). The database computes and stores ratings; these mirror its
// rules for the sample backend and the screens.

/// Every tuning number of the rating system, the same values as the
/// database's `app.rating_const` (supabase/migrations/20261127100000_ratings.sql).
class RatingRules {
  RatingRules._();

  /// Step size of a rating change while provisional, and after.
  static const kProvisional = 0.30;
  static const kEstablished = 0.12;

  /// A rating is provisional until this many confirmed results.
  static const provisionalGames = 10;

  /// The margin factor runs from [marginMin] to [marginMin] + [marginSpan].
  static const marginMin = 0.75;
  static const marginSpan = 0.50;

  /// The questionnaire never places a player higher than this.
  static const questionnaireCap = 5.00;

  /// Where everyone in a result starts when nobody in it has a rating.
  static const unratedDefault = 2.50;

  static const min = 1.00;
  static const max = 7.00;
}

/// Points per answer (index 0-3) of the five questions: years played, how
/// often, competition, and two skill questions.
const _questionnairePoints = [
  [0, 30, 60, 80],
  [0, 20, 40, 60],
  [0, 40, 80, 120],
  [0, 30, 60, 70],
  [0, 30, 60, 70],
];

/// The starting rating for five answers of 0-3, as the database computes it:
/// the minimum plus the points, capped at [RatingRules.questionnaireCap].
/// Throws [ArgumentError] for anything else.
double questionnaireRating(List<int> answers) {
  if (answers.length != _questionnairePoints.length) {
    throw ArgumentError.value(answers, 'answers', 'needs five answers');
  }
  // In hundredths, so the sum is exact.
  var hundredths = (RatingRules.min * 100).round();
  for (final (i, answer) in answers.indexed) {
    if (answer < 0 || answer > 3) throw ArgumentError.value(answers, 'answers', 'each answer is 0-3');
    hundredths += _questionnairePoints[i][answer];
  }
  final cap = (RatingRules.questionnaireCap * 100).round();
  return (hundredths < cap ? hundredths : cap) / 100;
}

/// The 1-5 level of a rated sport: the whole part of the rating, capped at 5.
int levelOfRating(double rating) {
  final whole = rating.floor();
  return whole > 5 ? 5 : whole;
}

/// The rating range a level range stands for, as the database converts a
/// range sent by an old build: 2-4 is 2.00-4.99, a top of 5 reaches 7.00.
({double min, double max}) ratingRangeOfLevels(int minLevel, int maxLevel) =>
    (min: minLevel.toDouble(), max: maxLevel == 5 ? RatingRules.max : (maxLevel * 100 + 99) / 100);

/// [value] rounded to two decimals, as the database stores a rating.
double roundRating(double value) => (value * 100).round() / 100;

/// A player's rating in one rated sport.
class SportRating {
  const SportRating({required this.rating, this.ratedGames = 0});

  /// 1.00-7.00, two decimals.
  final double rating;

  /// Confirmed results behind it.
  final int ratedGames;

  bool get provisional => ratedGames < RatingRules.provisionalGames;
}

/// A sport the signed-in player has ticked in "My sports".
class MySport {
  const MySport({required this.sportId, this.level, this.rating, this.canRetake = false});

  final String sportId;

  /// 1-5: chosen in a simple sport, derived from the rating in a rated one.
  final int? level;

  /// Only in a rated sport, and only once the player has one.
  final SportRating? rating;

  /// The questionnaire can be answered again (a rated sport before its first
  /// rated game).
  final bool canRetake;
}
