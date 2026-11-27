// Ratings 1.00-7.00 in the rated sports (padel and tennis), the starting
// questionnaire and "My sports" (design 2026-11-27-actra-m7-competitive
// §5.1-§5.3). The database computes and stores ratings; these mirror its
// rules for the sample backend and the screens.

import 'dart:math' as math;

import 'games.dart';

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

// ---- Match results (design §5.4-§5.6) ----

/// Where a result stands. [voided]: cancelled by an admin, or because a player
/// in it deleted their account (`void` in the database).
enum ResultStatus { pending, confirmed, disputed, voided }

enum MatchWinner { a, b, draw }

/// More sets won; equal sets, more games; equal games, a draw (as
/// `app.score_winner`). Each set is (games of side a, games of side b).
MatchWinner matchWinner(List<(int, int)> sets) {
  var setsA = 0, setsB = 0, gamesA = 0, gamesB = 0;
  for (final (a, b) in sets) {
    if (a > b) setsA++;
    if (b > a) setsB++;
    gamesA += a;
    gamesB += b;
  }
  if (setsA != setsB) return setsA > setsB ? MatchWinner.a : MatchWinner.b;
  if (gamesA != gamesB) return gamesA > gamesB ? MatchWinner.a : MatchWinner.b;
  return MatchWinner.draw;
}

/// One player's rating before and after a confirmed result.
class RatingChange {
  const RatingChange({required this.oldRating, required this.newRating});

  final double oldRating;
  final double newRating;

  /// Rounded, so 3.63 − 3.50 reads 0.13 and not 0.12999….
  double get delta => roundRating(newRating - oldRating);
}

/// The score of a game: who played on each side, the sets, and how it stands.
class MatchResult {
  const MatchResult({
    required this.id,
    required this.status,
    required this.sets,
    required this.winner,
    required this.enteredBy,
    required this.sideA,
    required this.sideB,
    this.confirmedBy = const [],
    this.disputeReason,
    this.flaggedNoShow = false,
    this.changes = const {},
  });

  final String id;
  final ResultStatus status;

  /// (games of side a, games of side b) per set, 1–5 sets.
  final List<(int, int)> sets;
  final MatchWinner winner;
  final String enteredBy;

  /// 1 or 2 player ids each.
  final List<String> sideA;
  final List<String> sideB;

  /// The players who confirmed it, first confirmation first.
  final List<String> confirmedBy;
  final String? disputeReason;

  /// A majority marked a player in it as a no-show (design §6.2).
  final bool flaggedNoShow;

  /// Player id → rating change; only once confirmed.
  final Map<String, RatingChange> changes;
}

/// The rating changes a confirmed result makes, as `app.apply_result` computes
/// them; each list follows the order of its side. A player passed as null has
/// no rating yet: they start at the average of the players who have one,
/// rounded to two decimals and capped at [RatingRules.questionnaireCap], or at
/// [RatingRules.unratedDefault] when nobody has one, with no rated games.
///
/// The database works in exact decimals, so this does too: ratings and side
/// averages in whole hundredths, and the change rounded half away from zero
/// after removing binary noise (0.30 × 0.85 × 0.5 = 0.1275 → 0.13).
({List<RatingChange> a, List<RatingChange> b}) ratingChanges({
  required List<SportRating?> sideA,
  required List<SportRating?> sideB,
  required List<(int, int)> sets,
}) {
  int hundredths(double rating) => (rating * 100).round();

  final known = [for (final r in [...sideA, ...sideB]) if (r != null) hundredths(r.rating)];
  final cap = hundredths(RatingRules.questionnaireCap);
  final start = known.isEmpty
      ? hundredths(RatingRules.unratedDefault)
      : math.min(_divideRounded(known.fold(0, (s, r) => s + r), known.length), cap);
  SportRating rated(SportRating? r) => r ?? SportRating(rating: start / 100);

  final a = [for (final r in sideA) rated(r)];
  final b = [for (final r in sideB) rated(r)];
  final sumA = a.fold(0, (s, r) => s + hundredths(r.rating));
  final sumB = b.fold(0, (s, r) => s + hundredths(r.rating));
  // Ra − Rb in rating points; exactly 0 for equal sides.
  final strengthGap = (sumA * b.length - sumB * a.length) / (100 * a.length * b.length);
  final expectedA = strengthGap == 0 ? 0.5 : 1 / (1 + math.pow(10, -strengthGap));

  final winner = matchWinner(sets);
  final actualA = switch (winner) {
    MatchWinner.a => 1.0,
    MatchWinner.b => 0.0,
    MatchWinner.draw => 0.5,
  };
  // The margin factor as a fraction marginTop / marginBottom: 1 for a draw,
  // else min + span × share of games won by the winner.
  var gamesA = 0, gamesB = 0;
  for (final (x, y) in sets) {
    gamesA += x;
    gamesB += y;
  }
  final won = winner == MatchWinner.a ? gamesA : gamesB;
  final lost = winner == MatchWinner.a ? gamesB : gamesA;
  final total = won + lost;
  final minH = hundredths(RatingRules.marginMin);
  final spanH = hundredths(RatingRules.marginSpan);
  final (marginTop, marginBottom) = winner == MatchWinner.draw || total == 0
      ? (1, 1)
      : (minH * total + spanH * math.max(0, won - lost), 100 * total);

  RatingChange change(SportRating r, double actual, double expected) {
    final kH = hundredths(r.provisional ? RatingRules.kProvisional : RatingRules.kEstablished);
    final deltaH = _roundHalfAway(kH * marginTop * (actual - expected) / marginBottom);
    final old = hundredths(r.rating);
    final next = math.max(hundredths(RatingRules.min), math.min(hundredths(RatingRules.max), old + deltaH));
    return RatingChange(oldRating: old / 100, newRating: next / 100);
  }

  return (
    a: [for (final r in a) change(r, actualA, expectedA)],
    b: [for (final r in b) change(r, 1 - actualA, 1 - expectedA)],
  );
}

/// [total] / [count] rounded half away from zero (both positive here).
int _divideRounded(int total, int count) => (2 * total + count) ~/ (2 * count);

/// [value] rounded to a whole number, half away from zero, as `round()` on a
/// numeric does. Twelve significant digits first, so a product that is
/// exactly x.5 in decimals but x.4999… in binary still rounds away from zero.
int _roundHalfAway(double value) => double.parse(value.toStringAsPrecision(12)).round();

// ---- Leaderboards (design §5.7) ----

/// One player on a leaderboard.
class LeaderboardRow {
  const LeaderboardRow({
    required this.position,
    required this.id,
    required this.name,
    required this.rating,
    required this.isMe,
  });

  /// 1 for the best rating.
  final int position;

  /// `kMeId` for the signed-in player.
  final String id;
  final String name;
  final SportRating rating;
  final bool isMe;
}

/// A sport's leaderboard in a city: the top [rows] (at most 100) and the
/// signed-in player's own row, when they have confirmed results there and
/// live in that city. [me] may also be one of [rows].
class Leaderboard {
  const Leaderboard({required this.rows, this.me});

  /// The most rows a leaderboard lists.
  static const maxRows = 100;

  final List<LeaderboardRow> rows;
  final LeaderboardRow? me;
}

// ---- Scores (design §5.4), as `app.enter_score` and `app.whole_sets` ----

/// Only the host may enter a score until this long after the end.
const kScoreHostOnlyFor = Duration(hours: 24);

/// Scores open at the end of a game and close this long after it.
const kScoreOpenFor = Duration(days: 7);

/// A pending score nobody disputed confirms itself this long after it was entered.
const kScoreConfirmWithin = Duration(hours: 24);

/// The most sets in a score.
const kMaxSets = 5;

/// The most games one side takes in a set.
const kMaxGamesPerSet = 30;

/// 1 to [kMaxSets] sets of 0 to [kMaxGamesPerSet] games each, none 0–0.
bool validSets(List<(int, int)> sets) {
  bool games(int n) => n >= 0 && n <= kMaxGamesPerSet;
  return sets.isNotEmpty &&
      sets.length <= kMaxSets &&
      sets.every((s) => games(s.$1) && games(s.$2) && (s.$1 != 0 || s.$2 != 0));
}

// ---- After a game (design §6.1-§6.3) ----

/// Thumbs can be given, and changed, until this long after a game ends.
const kVoteOpenFor = Duration(days: 7);

/// "Didn't show up" can be marked, and undone, until this long after the end.
const kNoShowOpenFor = Duration(hours: 48);

/// Whether thumbs up or down can be given in [game] at [now], the venue's
/// wall-clock time. Only decides what the app shows: the server enforces it.
bool canVote(Game game, DateTime now) => _openAfterEnd(game, now, kVoteOpenFor);

/// Whether another player can be marked as not having shown up in [game] at
/// [now], the venue's wall-clock time.
bool canReportNoShow(Game game, DateTime now) => _openAfterEnd(game, now, kNoShowOpenFor);

bool _openAfterEnd(Game game, DateTime now, Duration openFor) =>
    !game.cancelled && game.endedAt(now) && now.isBefore(game.end.add(openFor));

/// What the signed-in player has said about the others of a finished game.
class AfterGame {
  const AfterGame({this.myVotes = const {}, this.myNoShows = const {}});

  /// Player id → true for a thumbs up, false for a thumbs down.
  final Map<String, bool> myVotes;

  /// The players marked as not having shown up.
  final Set<String> myNoShows;
}

/// The thumbs a player has received over all games.
class Sportsmanship {
  const Sportsmanship({this.votes = 0, this.percent});

  /// Nothing yet.
  static const none = Sportsmanship();

  /// Players see the share only from this many votes (design §6.1).
  static const minVotes = 5;

  final int votes;

  /// Share of thumbs up, 0-100; null under [minVotes].
  final int? percent;
}

/// Why a player is reported (design §6.3).
enum ReportReason { language, aggression, falseScore, other }
