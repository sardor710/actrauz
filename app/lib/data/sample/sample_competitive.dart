import 'dart:math' as math;

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

/// Match scores in memory, with the database's rules (`app.enter_score`,
/// `app.confirm_score`, `app.dispute_score`, `app.auto_confirm_scores`,
/// `app.apply_result` in supabase/migrations/20261127110000_scores.sql). One
/// result per game, with the id `r-<game id>`. Failures are the
/// [JoinException]s the Supabase repository maps the same codes to.
class SampleScores {
  SampleScores({
    required this.utcNow,
    required this.ratingOf,
    required this.setRating,
    required this.isDeleted,
    required this.noShowIn,
    required this.notify,
  });

  /// Scores open at the end of a game and close this long after it.
  static const openFor = Duration(days: 7);

  /// Only the host may enter a score until this long after the end.
  static const hostOnlyFor = Duration(hours: 24);

  /// A pending score nobody disputed confirms itself after this long.
  static const confirmWithin = Duration(hours: 24);

  /// 1 to 5 sets of 0–30 games, none 0–0 (as `app.whole_sets`).
  static bool wholeSets(List<(int, int)> sets) {
    bool games(int n) => n >= 0 && n <= 30;
    return sets.isNotEmpty &&
        sets.length <= 5 &&
        sets.every((s) => games(s.$1) && games(s.$2) && (s.$1 != 0 || s.$2 != 0));
  }

  /// Deadlines are kept in UTC.
  final DateTime Function() utcNow;

  /// A player's rating in a sport, null when they have none.
  final SportRating? Function(String userId, String sportId) ratingOf;

  /// Writes a player's rating (and the level derived from it).
  final void Function(String userId, String sportId, SportRating rating) setRating;
  final bool Function(String userId) isDeleted;

  /// Whether a no-show majority was recorded against the player in the game.
  final bool Function(String gameId, String userId) noShowIn;
  final void Function(String userId, String kind, String category, Map<String, Object?> payload) notify;

  final Map<String, _SampleResult> _byGame = {};

  /// The result of a game as the screens see it, or null before any score.
  MatchResult? resultOf(String gameId) => _byGame[gameId]?.view;

  /// [userId] enters (or corrects) the score of [game]. [rated]: the game's
  /// sport is rated; [localNow]: the venue's wall-clock time; [note]: what
  /// notices about the game carry.
  void enter(
    String userId,
    Game game, {
    required bool rated,
    required DateTime localNow,
    required Map<String, Object?> note,
    required List<String> sideA,
    required List<String> sideB,
    required List<(int, int)> sets,
  }) {
    if (game.cancelled || !rated || !game.participantIds.contains(userId)) {
      throw const JoinException(JoinError.notFound);
    }
    if (localNow.isBefore(game.end) || !localNow.isBefore(game.end.add(openFor))) {
      throw const JoinException(JoinError.scoreClosed);
    }
    if (game.hostId != userId && localNow.isBefore(game.end.add(hostOnlyFor))) {
      throw const JoinException(JoinError.forbidden);
    }
    final players = [...sideA, ...sideB];
    if (sideA.isEmpty ||
        sideA.length > 2 ||
        sideA.length != sideB.length ||
        players.toSet().length != players.length ||
        !players.contains(userId) ||
        !players.every(game.participantIds.contains) ||
        players.any(isDeleted) ||
        // Nor does a player recorded as not having shown up.
        players.any((id) => noShowIn(game.id, id))) {
      throw const JoinException(JoinError.invalidArgument);
    }
    if (!wholeSets(sets)) throw const JoinException(JoinError.invalidArgument);

    final existing = _byGame[game.id];
    // already_exists and not_allowed in the database.
    if (existing != null && existing.status != ResultStatus.pending) throw const JoinException(JoinError.scoreClosed);
    if (existing != null && existing.enteredBy != userId) throw const JoinException(JoinError.forbidden);

    final result = existing ?? _SampleResult(game.id, game.sportId, userId, note);
    _byGame[game.id] = result
      ..sideA = [...sideA]
      ..sideB = [...sideB]
      ..sets = [...sets]
      ..deadline = utcNow().add(confirmWithin);
    result.confirmedBy.clear();
    for (final id in players) {
      if (id != userId) notify(id, 'score_entered', 'ratings', result.note);
    }
  }

  /// A pending result as sample data starts with it: no checks, no notices.
  void seedPending(
    Game game, {
    required String enteredBy,
    required DateTime enteredAt,
    required Map<String, Object?> note,
    required List<String> sideA,
    required List<String> sideB,
    required List<(int, int)> sets,
  }) {
    _byGame[game.id] = _SampleResult(game.id, game.sportId, enteredBy, note)
      ..sideA = [...sideA]
      ..sideB = [...sideB]
      ..sets = [...sets]
      ..deadline = enteredAt.add(confirmWithin);
  }

  /// A player in the result other than whoever entered it confirms it; one
  /// from the other side confirms the result. Returns the game id.
  String confirm(String userId, String resultId) {
    final result = _pending(resultId);
    if (result.enteredBy == userId || !result.includes(userId)) throw const JoinException(JoinError.notFound);
    if (!result.confirmedBy.contains(userId)) result.confirmedBy.add(userId);
    if (result.sideA.contains(userId) != result.sideA.contains(result.enteredBy)) _apply(result);
    return result.gameId;
  }

  /// Any player in a pending result freezes it for an admin. Returns the game id.
  String dispute(String userId, String resultId, {String? reason}) {
    final result = _pending(resultId);
    if (!result.includes(userId)) throw const JoinException(JoinError.notFound);
    final text = reason?.trim() ?? '';
    result
      ..status = ResultStatus.disputed
      ..disputedBy = userId
      ..disputeReason = text.isEmpty ? null : (text.length > 300 ? text.substring(0, 300) : text);
    for (final id in result.players) {
      if (id != userId) notify(id, 'score_disputed', 'ratings', result.note);
    }
    return result.gameId;
  }

  /// A no-show majority was recorded against [userId] in the game: a pending
  /// result with them in it is frozen as disputed for an admin (reason
  /// `no_show`; its players hear), a confirmed one is flagged. Nothing is
  /// voided (design §6.2), as `app.recount_no_show`.
  void noShowRecorded(String gameId, String userId) {
    final result = _byGame[gameId];
    if (result == null || !result.includes(userId)) return;
    if (result.status == ResultStatus.pending) {
      result
        ..status = ResultStatus.disputed
        ..disputeReason = 'no_show';
      for (final id in result.players) {
        notify(id, 'score_disputed', 'ratings', result.note);
      }
    } else if (result.status == ResultStatus.confirmed) {
      result.flaggedNoShow = true;
    }
  }

  /// What an admin has to look at, as `app.admin_review` lists it: disputed
  /// results, and confirmed ones flagged by a no-show majority. [disputedBy]
  /// is null for a no-show freeze.
  List<({MatchResult result, String gameId, String? disputedBy})> awaitingAdmin() => [
    for (final r in _byGame.values)
      if (r.status == ResultStatus.disputed || (r.status == ResultStatus.confirmed && r.flaggedNoShow))
        (result: r.view, gameId: r.gameId, disputedBy: r.disputedBy),
  ];

  /// An admin's decision, as `app.admin_resolve_score`; returns the result as
  /// it was and as it is now.
  /// [action] is `confirm` or `correct` (a disputed result; `correct` takes
  /// [sets]), `void` (a pending, disputed or confirmed one: a confirmed one's
  /// rating changes are taken back) or `keep` (a confirmed, flagged one).
  /// Everyone in the result is told, except for `keep`. A failed call is
  /// [JoinError.invalidArgument] or [JoinError.notFound].
  ({MatchResult before, MatchResult after}) resolve(String resultId, String action, {List<(int, int)>? sets}) {
    if (!const {'confirm', 'correct', 'void', 'keep'}.contains(action)) {
      throw const JoinException(JoinError.invalidArgument);
    }
    final result = _byGame.values.where((r) => r.id == resultId).firstOrNull;
    if (result == null) throw const JoinException(JoinError.notFound);
    final before = result.view;

    switch (action) {
      case 'keep':
        if (result.status != ResultStatus.confirmed || !result.flaggedNoShow) {
          throw const JoinException(JoinError.notFound);
        }
        result.flaggedNoShow = false;
        return (before: before, after: result.view);
      case 'confirm' || 'correct':
        if (result.status != ResultStatus.disputed) throw const JoinException(JoinError.notFound);
        if (action == 'correct') {
          if (sets == null || !wholeSets(sets)) throw const JoinException(JoinError.invalidArgument);
          result.sets = [...sets];
        }
        _apply(result);
        // A deleted player in it made it void, and _apply told the others.
        if (result.status == ResultStatus.voided) return (before: before, after: result.view);
      default:
        if (result.status == ResultStatus.voided) throw const JoinException(JoinError.notFound);
        if (result.status == ResultStatus.confirmed) _takeBack(result);
        result.status = ResultStatus.voided;
    }
    for (final id in result.players) {
      notify(id, 'score_resolved', 'ratings', {...result.note, 'action': action});
    }
    return (before: before, after: result.view);
  }

  /// Subtracts each player's own change in the result from their rating, and
  /// one rated game, as the database does with the result's rating events.
  void _takeBack(_SampleResult result) {
    for (final MapEntry(key: id, value: change) in result.changes.entries) {
      final current = ratingOf(id, result.sportId);
      if (current == null) continue;
      final rating = math.min(RatingRules.max, math.max(RatingRules.min, roundRating(current.rating - change.delta)));
      setRating(id, result.sportId, SportRating(rating: rating, ratedGames: math.max(0, current.ratedGames - 1)));
    }
    result.changes.clear();
  }

  /// Confirms every pending result whose 24 hours are over; returns how many.
  int autoConfirm() {
    final due = [
      for (final r in _byGame.values)
        if (r.status == ResultStatus.pending && !r.deadline.isAfter(utcNow())) r,
    ];
    due.forEach(_apply);
    return due.length;
  }

  _SampleResult _pending(String resultId) {
    final result = _byGame.values.where((r) => r.id == resultId).firstOrNull;
    if (result == null || result.status != ResultStatus.pending) throw const JoinException(JoinError.notFound);
    return result;
  }

  /// Moves the ratings and confirms the result. One with a deleted player in
  /// it becomes void instead, and the others hear.
  void _apply(_SampleResult result) {
    if (result.players.any(isDeleted)) {
      result.status = ResultStatus.voided;
      for (final id in result.players) {
        if (!isDeleted(id)) notify(id, 'score_resolved', 'ratings', {...result.note, 'action': 'void'});
      }
      return;
    }
    final sport = result.sportId;
    final changes = ratingChanges(
      sideA: [for (final id in result.sideA) ratingOf(id, sport)],
      sideB: [for (final id in result.sideB) ratingOf(id, sport)],
      sets: result.sets,
    );
    final byPlayer = {
      for (final (i, id) in result.sideA.indexed) id: changes.a[i],
      for (final (i, id) in result.sideB.indexed) id: changes.b[i],
    };
    for (final MapEntry(key: id, value: change) in byPlayer.entries) {
      final played = ratingOf(id, sport)?.ratedGames ?? 0;
      setRating(id, sport, SportRating(rating: change.newRating, ratedGames: played + 1));
      result.changes[id] = change;
      notify(id, 'rating_updated', 'ratings', {...result.note, 'old': change.oldRating, 'new': change.newRating});
    }
    result.status = ResultStatus.confirmed;
  }
}

/// A result as [SampleScores] keeps it.
class _SampleResult {
  _SampleResult(this.gameId, this.sportId, this.enteredBy, Map<String, Object?> gameNote)
    : note = {...gameNote, 'result_id': 'r-$gameId'};

  final String gameId;
  final String sportId;
  final String enteredBy;

  /// What notices about it carry: the game's keys and `result_id`.
  final Map<String, Object?> note;

  String get id => 'r-$gameId';
  ResultStatus status = ResultStatus.pending;
  List<String> sideA = const [];
  List<String> sideB = const [];
  List<(int, int)> sets = const [];
  final List<String> confirmedBy = [];
  String? disputeReason;

  /// Who disputed it; null for a no-show freeze.
  String? disputedBy;
  bool flaggedNoShow = false;
  DateTime deadline = DateTime.utc(2000);
  final Map<String, RatingChange> changes = {};

  List<String> get players => [...sideA, ...sideB];
  bool includes(String userId) => sideA.contains(userId) || sideB.contains(userId);

  MatchResult get view => MatchResult(
    id: id,
    status: status,
    sets: List.unmodifiable(sets),
    winner: matchWinner(sets),
    enteredBy: enteredBy,
    sideA: List.unmodifiable(sideA),
    sideB: List.unmodifiable(sideB),
    confirmedBy: List.unmodifiable(confirmedBy),
    disputeReason: disputeReason,
    flaggedNoShow: flaggedNoShow,
    changes: Map.unmodifiable(changes),
  );
}
