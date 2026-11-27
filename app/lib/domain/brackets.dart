import '../core/localized_text.dart';
import 'tournaments.dart';

/// Tournament draws, matches and the bracket rules (M8a design §6–§7,
/// §14a).
///
/// The database owns the rules; [BracketRules] repeats them so the sample
/// backend draws the same brackets and tables. Times are venue wall-clock,
/// as everywhere in the domain.

enum DrawFormat { knockout, groups }

enum MatchStage { group, knockout }

/// `waiting`: a side is not known yet; `ready`: both are; `done`: scored, a
/// walkover or a bye.
enum MatchStatus { waiting, ready, done }

/// `decider`: a level score whose winner the organiser picked (penalties, a
/// deciding game). `none`: both sides withdrew, nobody won.
enum MatchOutcome { played, walkover, retired, decider, bye, none }

/// Who won a match; `draw` only in a group.
enum Side { a, b, draw }

/// One entry of a draw.
class DrawEntry {
  const DrawEntry({
    required this.registrationId,
    required this.seed,
    required this.strength,
    this.groupId,
    this.withdrawn = false,
    this.players = const [],
  });

  final String registrationId;

  /// 1 = strongest.
  final int seed;

  /// A rated sport's rating, otherwise the level 1–5 (pairs: the average);
  /// 0 without one.
  final double strength;
  final String? groupId;

  /// The organiser withdrew it after publishing.
  final bool withdrawn;

  /// The registrant, then the partner.
  final List<PlayerRef> players;
}

class TournamentMatch {
  const TournamentMatch({
    required this.id,
    required this.stage,
    required this.round,
    required this.position,
    required this.status,
    this.groupId,
    this.sideA,
    this.sideB,
    this.aEmpty = false,
    this.bEmpty = false,
    this.outcome,
    this.winner,
    this.sets,
    this.courtId,
    this.courtName,
    this.startsAt,
    this.endsAt,
    this.placeNote,
    this.clash = false,
  });

  final String id;
  final MatchStage stage;

  /// Group matches only.
  final String? groupId;
  final int round;
  final int position;

  /// Registration ids; null while not known yet.
  final String? sideA;
  final String? sideB;

  /// A bracket slot nobody fills (a bye).
  final bool aEmpty;
  final bool bEmpty;
  final MatchStatus status;
  final MatchOutcome? outcome;
  final Side? winner;

  /// Rated sports: 1–5 sets of (side a, side b). Other sports: one pair, the
  /// score. Null for walkovers and byes.
  final List<List<int>>? sets;
  final String? courtId;
  final LocalizedText? courtName;

  /// Wall-clock.
  final DateTime? startsAt;

  /// Wall-clock; only with a court (one slot of it).
  final DateTime? endsAt;

  /// Without a venue: where it is played.
  final String? placeNote;

  /// A player of it is in another match of the tournament at an overlapping
  /// time (advancing can cause it); the organiser should move it.
  final bool clash;

  /// The winning registration, if any.
  String? get winnerEntry => switch (winner) {
    Side.a => sideA,
    Side.b => sideB,
    _ => null,
  };
}

/// One row of a group's table.
class GroupStanding {
  const GroupStanding({
    required this.registrationId,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.points,
    required this.setsFor,
    required this.setsAgainst,
    required this.gamesFor,
    required this.gamesAgainst,
    required this.place,
    required this.advancing,
    required this.withdrawn,
  });

  final String registrationId;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int points;
  final int setsFor;
  final int setsAgainst;
  final int gamesFor;
  final int gamesAgainst;

  /// 1-based.
  final int place;

  /// Within the places that go through, and not withdrawn.
  final bool advancing;
  final bool withdrawn;
}

class DrawGroup {
  const DrawGroup({required this.id, required this.label, this.standings = const []});

  final String id;

  /// `A`, `B`, …
  final String label;

  /// In place order.
  final List<GroupStanding> standings;
}

/// A category's draw as the caller may see it: drafts only for organisers.
class CategoryDraw {
  const CategoryDraw({
    required this.categoryId,
    required this.format,
    required this.published,
    this.groupSize,
    this.advance,
    this.outdated = false,
    this.entries = const [],
    this.groups = const [],
    this.matches = const [],
    this.winner,
    this.runnerUp,
    this.finished = false,
  });

  final String categoryId;
  final DrawFormat format;

  /// Groups only: 3 or 4, and 1 or 2 advancing.
  final int? groupSize;
  final int? advance;
  final bool published;

  /// A draft whose entries changed after it was made: make it again before
  /// publishing.
  final bool outdated;

  /// By seed.
  final List<DrawEntry> entries;
  final List<DrawGroup> groups;

  /// Group matches, then knockout, each by round.
  final List<TournamentMatch> matches;

  /// Registration ids, once the final (or the single group) is done.
  final String? winner;
  final String? runnerUp;
  final bool finished;

  DrawEntry entry(String registrationId) => entries.firstWhere((e) => e.registrationId == registrationId);
}

/// A court of the tournament's venue, for scheduling.
class CourtRef {
  const CourtRef({required this.id, required this.name, required this.slotMinutes});

  final String id;
  final LocalizedText name;
  final int slotMinutes;
}

/// The signed-in player's first match still to play in a tournament.
class NextMatch {
  const NextMatch({required this.match, required this.categoryId});

  final TournamentMatch match;
  final String categoryId;
}

/// What the tournament page shows of the brackets.
class TournamentBracket {
  const TournamentBracket({
    required this.organizer,
    this.draws = const [],
    this.myNextMatch,
    this.finished = false,
    this.courts = const [],
  });

  /// The caller organises it (or is an admin): drafts and courts included.
  final bool organizer;

  /// In category order.
  final List<CategoryDraw> draws;
  final NextMatch? myNextMatch;

  /// At least one category has a draw, and every one with a draw is finished.
  final bool finished;

  /// Organisers only; empty for everyone else.
  final List<CourtRef> courts;

  CategoryDraw? draw(String categoryId) {
    for (final d in draws) {
      if (d.categoryId == categoryId) return d;
    }
    return null;
  }
}

/// One of the signed-in player's matches, anywhere ("My matches").
class MyMatch {
  const MyMatch({required this.match, required this.tournamentId, required this.title, required this.categoryId});

  final TournamentMatch match;
  final String tournamentId;
  final LocalizedText title;
  final String categoryId;
}

/// What "fill the day" did.
class FillResult {
  const FillResult({required this.scheduled, this.unscheduled = const []});

  final int scheduled;

  /// Match ids that did not fit.
  final List<String> unscheduled;
}

/// The bracket rules as the database applies them (`app.seed_order`,
/// `app.build_draw`, `app.build_matches`, `app.group_table`,
/// `app.fill_knockout`).
abstract final class BracketRules {
  /// The smallest power of two at or above [n], at least 2.
  static int bracketSize(int n) {
    var size = 2;
    while (size < n) {
      size *= 2;
    }
    return size;
  }

  /// Seeds in bracket slot order: `[1, 2]`, and each doubling maps every s
  /// to `[s, 2·len + 1 − s]` (4 → `[1, 4, 2, 3]`).
  static List<int> seedOrder(int size) {
    var order = [1, 2];
    while (order.length < size) {
      final len = order.length;
      order = [
        for (final s in order) ...[s, 2 * len + 1 - s],
      ];
    }
    return order;
  }

  /// The sizes of the groups for [n] entries and the organiser's
  /// [groupSize]: as many groups as the size asks for, fewer while the
  /// smallest would have under three; sizes differ by at most one.
  ///
  /// Largest first. These are sizes, not label order: the snake seeding
  /// decides which group gets the extra entries.
  static List<int> groupSizes(int n, int groupSize) {
    var groups = (n / groupSize).ceil();
    while (groups > 1 && n ~/ groups < 3) {
      groups--;
    }
    return [for (var i = 0; i < groups; i++) n ~/ groups + (i < n % groups ? 1 : 0)];
  }

  /// A round robin of [n] entries by the circle method, as the database
  /// builds it: per round, pairs of 0-based indices into the group's entries
  /// by seed. With an odd [n], whoever meets the dummy sits the round out.
  static List<List<(int, int)>> roundRobin(int n) {
    final members = <int?>[for (var i = 0; i < n; i++) i];
    if (n.isOdd) members.add(null);
    final size = members.length;
    final rounds = <List<(int, int)>>[];
    var current = members;
    for (var r = 0; r < size - 1; r++) {
      rounds.add([
        for (var i = 0; i < size ~/ 2; i++)
          if (current[i] != null && current[size - 1 - i] != null) (current[i]!, current[size - 1 - i]!),
      ]);
      // Keep the first, rotate the rest one place.
      current = [current[0], current[size - 1], ...current.sublist(1, size - 1)];
    }
    return rounds;
  }

  /// A group's table (§7.6, §14a.3, §14a.5). [seeds] holds every entry of
  /// the group; [withdrawn] those withdrawn; [advance] how many places go
  /// through. Points: win 2, draw 1, loss 0, a walkover counts as a win or
  /// loss. Sets and games come from played and retired matches only. Order:
  /// withdrawn entries last; points; head-to-head (points from the matches
  /// against entries level on points, not withdrawn); set difference; game
  /// difference; seed.
  static List<GroupStanding> standings(
    List<TournamentMatch> groupMatches,
    Map<String, int> seeds,
    Set<String> withdrawn, {
    int advance = 0,
  }) {
    final rows = {for (final id in seeds.keys) id: _Tally()};
    // (entry, opponent, points) of every counted match side.
    final sides = <(String, String?, int)>[];
    for (final m in groupMatches) {
      if (m.status != MatchStatus.done || m.winner == null) continue;
      final counted = m.outcome == MatchOutcome.played || m.outcome == MatchOutcome.retired ? m.sets : null;
      for (final (me, opp, mine) in [(m.sideA, m.sideB, Side.a), (m.sideB, m.sideA, Side.b)]) {
        if (me == null) continue;
        final points = m.winner == Side.draw ? 1 : (m.winner == mine ? 2 : 0);
        sides.add((me, opp, points));
        final row = rows[me];
        if (row == null) continue;
        row.played++;
        row.points += points;
        if (m.winner == Side.draw) {
          row.drawn++;
        } else if (m.winner == mine) {
          row.won++;
        } else {
          row.lost++;
        }
        for (final set in counted ?? const <List<int>>[]) {
          final (ours, theirs) = mine == Side.a ? (set[0], set[1]) : (set[1], set[0]);
          if (ours > theirs) row.setsFor++;
          if (theirs > ours) row.setsAgainst++;
          row.gamesFor += ours;
          row.gamesAgainst += theirs;
        }
      }
    }
    for (final (me, opp, points) in sides) {
      final row = rows[me];
      final other = opp == null ? null : rows[opp];
      if (row == null || other == null || withdrawn.contains(opp)) continue;
      if (other.points == row.points) row.headToHead += points;
    }

    final order = rows.keys.toList()
      ..sort((x, y) {
        final a = rows[x]!, b = rows[y]!;
        final wx = withdrawn.contains(x) ? 1 : 0, wy = withdrawn.contains(y) ? 1 : 0;
        for (final c in [
          wx.compareTo(wy),
          b.points.compareTo(a.points),
          b.headToHead.compareTo(a.headToHead),
          (b.setsFor - b.setsAgainst).compareTo(a.setsFor - a.setsAgainst),
          (b.gamesFor - b.gamesAgainst).compareTo(a.gamesFor - a.gamesAgainst),
          seeds[x]!.compareTo(seeds[y]!),
        ]) {
          if (c != 0) return c;
        }
        return 0;
      });

    return [
      for (var i = 0; i < order.length; i++)
        GroupStanding(
          registrationId: order[i],
          played: rows[order[i]]!.played,
          won: rows[order[i]]!.won,
          drawn: rows[order[i]]!.drawn,
          lost: rows[order[i]]!.lost,
          points: rows[order[i]]!.points,
          setsFor: rows[order[i]]!.setsFor,
          setsAgainst: rows[order[i]]!.setsAgainst,
          gamesFor: rows[order[i]]!.gamesFor,
          gamesAgainst: rows[order[i]]!.gamesAgainst,
          place: i + 1,
          advancing: i + 1 <= advance && !withdrawn.contains(order[i]),
          withdrawn: withdrawn.contains(order[i]),
        ),
    ];
  }

  /// The qualifiers for the knockout in rank order (§14a.6): every group's
  /// places 1..[advance]; all winners first, ordered by points per match,
  /// then set difference per match, then game difference per match (no
  /// match played sorts last), then seed, then group order; then the
  /// runners-up the same way.
  ///
  /// A withdrawn entry that is within the places (its group has too few
  /// others) keeps its rank; the database leaves its bracket slot empty, so
  /// the caller does too.
  static List<String> rankQualifiers(List<DrawGroup> groups, int advance, Map<String, int> seeds) {
    final rows = [
      for (var g = 0; g < groups.length; g++)
        for (final s in groups[g].standings)
          if (s.place <= advance) (s, g),
    ];
    int perMatch(double? a, double? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    double? avg(int value, int played) => played == 0 ? null : value / played;
    rows.sort((x, y) {
      final (a, ga) = x;
      final (b, gb) = y;
      for (final c in [
        a.place.compareTo(b.place),
        (a.withdrawn ? 1 : 0).compareTo(b.withdrawn ? 1 : 0),
        perMatch(avg(a.points, a.played), avg(b.points, b.played)),
        perMatch(avg(a.setsFor - a.setsAgainst, a.played), avg(b.setsFor - b.setsAgainst, b.played)),
        perMatch(avg(a.gamesFor - a.gamesAgainst, a.played), avg(b.gamesFor - b.gamesAgainst, b.played)),
        (seeds[a.registrationId] ?? 0).compareTo(seeds[b.registrationId] ?? 0),
        ga.compareTo(gb),
      ]) {
        if (c != 0) return c;
      }
      return 0;
    });
    return [for (final (s, _) in rows) s.registrationId];
  }

  /// The knockout's first-round slots 1..[size] (index 0 = slot 1) for the
  /// [ranked] qualifiers; null = a bye. Qualifier k takes seed k's slot
  /// ([seedOrder]), so byes go to the best-ranked. A lower qualifier in the
  /// same half as a better one from its group ([groupOf]) swaps with the
  /// nearest-ranked runner-up of another group in the other half whose own
  /// group-mate is not in this half (ties: the lower-ranked).
  static List<String?> placeQualifiers(List<String> ranked, Map<String, String> groupOf, int size) {
    final count = ranked.length;
    final groupCount = {for (final id in ranked) groupOf[id]}.length;
    final order = seedOrder(size);
    // slot (1-based) of qualifier k (0-based).
    final slot = List<int>.filled(count, 0);
    for (var i = 0; i < size; i++) {
      if (order[i] <= count) slot[order[i] - 1] = i + 1;
    }
    int half(int s) => s <= size ~/ 2 ? 1 : 2;
    String? group(int k) => groupOf[ranked[k]];

    for (var k = 0; k < count; k++) {
      final h = half(slot[k]);
      final conflict = [for (var c = 0; c < k; c++) c].any((c) => group(c) == group(k) && half(slot[c]) == h);
      if (!conflict) continue;
      int? best;
      int? bestDistance;
      for (var c = groupCount; c < count; c++) {
        if (c == k || group(c) == group(k)) continue;
        if (half(slot[c]) == h) continue;
        // c moves into this half: its own group-mate must not be here.
        final mateHere = [
          for (var o = 0; o < count; o++) o,
        ].any((o) => o != c && o != k && group(o) == group(c) && half(slot[o]) == h);
        if (mateHere) continue;
        final distance = (c - k).abs();
        if (best == null || distance < bestDistance! || (distance == bestDistance && c > best)) {
          best = c;
          bestDistance = distance;
        }
      }
      if (best != null) {
        final tmp = slot[k];
        slot[k] = slot[best];
        slot[best] = tmp;
      }
    }

    final slots = List<String?>.filled(size, null);
    for (var k = 0; k < count; k++) {
      slots[slot[k] - 1] = ranked[k];
    }
    return slots;
  }
}

class _Tally {
  int played = 0;
  int won = 0;
  int drawn = 0;
  int lost = 0;
  int points = 0;
  int setsFor = 0;
  int setsAgainst = 0;
  int gamesFor = 0;
  int gamesAgainst = 0;
  int headToHead = 0;
}
