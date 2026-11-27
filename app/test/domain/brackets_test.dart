import 'package:actra/domain/brackets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A finished group match between [a] and [b].
TournamentMatch played(
  String a,
  String b,
  List<List<int>> sets, {
  MatchOutcome outcome = MatchOutcome.played,
  Side? winner,
  int position = 1,
}) {
  final won =
      winner ??
      () {
        var forA = 0, forB = 0;
        for (final s in sets) {
          if (s[0] > s[1]) forA++;
          if (s[1] > s[0]) forB++;
        }
        if (sets.length == 1 && sets.first[0] == sets.first[1]) return Side.draw;
        return forA > forB ? Side.a : Side.b;
      }();
  return TournamentMatch(
    id: '$a-$b',
    stage: MatchStage.group,
    groupId: 'g',
    round: 1,
    position: position,
    sideA: a,
    sideB: b,
    status: MatchStatus.done,
    outcome: outcome,
    winner: won,
    sets: outcome == MatchOutcome.walkover ? null : sets,
  );
}

GroupStanding row(
  String id, {
  required int place,
  int points = 0,
  int played = 3,
  int setsFor = 0,
  int setsAgainst = 0,
}) => GroupStanding(
  registrationId: id,
  played: played,
  won: 0,
  drawn: 0,
  lost: 0,
  points: points,
  setsFor: setsFor,
  setsAgainst: setsAgainst,
  gamesFor: 0,
  gamesAgainst: 0,
  place: place,
  advancing: place <= 2,
  withdrawn: false,
);

void main() {
  group('seeding and groups', () {
    test('seed order puts the top seeds apart', () {
      expect(BracketRules.seedOrder(2), [1, 2]);
      expect(BracketRules.seedOrder(4), [1, 4, 2, 3]);
      expect(BracketRules.seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    });

    test('bracket size is the next power of two, at least 2', () {
      expect(BracketRules.bracketSize(2), 2);
      expect(BracketRules.bracketSize(3), 4);
      expect(BracketRules.bracketSize(5), 8);
      expect(BracketRules.bracketSize(8), 8);
    });

    test('group sizes differ by at most one and never go under three', () {
      expect(BracketRules.groupSizes(10, 3), [4, 3, 3]);
      expect(BracketRules.groupSizes(5, 4), [5]);
      expect(BracketRules.groupSizes(7, 4), [4, 3]);
      expect(BracketRules.groupSizes(8, 4), [4, 4]);
      expect(BracketRules.groupSizes(3, 3), [3]);
    });

    test('a round robin meets everyone once', () {
      final four = BracketRules.roundRobin(4);
      expect(four, hasLength(3));
      for (final round in four) {
        expect(round, hasLength(2));
        // Nobody plays twice in a round.
        expect({
          for (final (a, b) in round) ...[a, b],
        }, hasLength(4));
      }
      final pairs = {
        for (final round in four)
          for (final (a, b) in round) a < b ? '$a-$b' : '$b-$a',
      };
      expect(pairs, hasLength(6));

      // Odd: whoever meets the dummy sits the round out.
      final three = BracketRules.roundRobin(3);
      expect(three, hasLength(3));
      expect(three.every((r) => r.length == 1), isTrue);
      // The circle method as the database runs it: first round 1–4 and 2–3.
      expect(four.first, [(0, 3), (1, 2)]);
    });
  });

  group('standings', () {
    test('three on 4 points in a circle: set difference decides; a walkover counts points, not sets', () {
      final matches = [
        played('a', 'b', [
          [6, 0],
          [6, 0],
        ]),
        played('b', 'c', [
          [6, 4],
          [4, 6],
          [6, 4],
        ]),
        played('c', 'a', [
          [6, 4],
          [4, 6],
          [6, 4],
        ]),
        played('a', 'd', [
          [6, 0],
          [6, 0],
        ]),
        played('b', 'd', [
          [6, 0],
          [6, 0],
        ]),
        played('c', 'd', const [], outcome: MatchOutcome.walkover, winner: Side.a),
      ];
      final table = BracketRules.standings(matches, {'a': 1, 'b': 2, 'c': 3, 'd': 4}, const {}, advance: 2);
      expect(table.map((s) => s.registrationId), ['a', 'b', 'c', 'd']);
      expect(table.map((s) => s.points), [4, 4, 4, 0]);
      expect(table.map((s) => s.place), [1, 2, 3, 4]);
      expect(table.map((s) => s.advancing), [true, true, false, false]);
      final c = table[2];
      expect(c.played, 3);
      expect(c.won, 2);
      expect(c.lost, 1);
      expect(c.setsFor, 3);
      expect(c.setsAgainst, 3);
      expect(c.gamesFor, 16 + 14);
      expect(c.withdrawn, isFalse);
    });

    test('two level on points: head-to-head beats a better goal difference', () {
      final matches = [
        played('b', 'c', [
          [1, 0],
        ]),
        played('c', 'd', [
          [5, 0],
        ]),
        played('b', 'd', [
          [1, 0],
        ]),
        played('a', 'b', [
          [1, 0],
        ]),
        played('c', 'a', [
          [1, 0],
        ]),
        played('a', 'd', [
          [0, 0],
        ]),
      ];
      final table = BracketRules.standings(matches, {'a': 1, 'b': 2, 'c': 3, 'd': 4}, const {}, advance: 2);
      expect(table.map((s) => s.registrationId), ['b', 'c', 'a', 'd']);
      expect(table.map((s) => s.points), [4, 4, 3, 1]);
      expect(table[2].drawn, 1);
    });

    test('a withdrawn entry goes last and never advances; unplayed entries still have a row', () {
      final matches = [
        played('a', 'b', [
          [6, 0],
          [6, 0],
        ]),
      ];
      final table = BracketRules.standings(matches, {'a': 1, 'b': 2, 'c': 3}, {'a'}, advance: 2);
      // b and c level on points (the withdrawn a's points do not count for
      // head-to-head): c's set difference 0 beats b's -2.
      expect(table.map((s) => s.registrationId), ['c', 'b', 'a']);
      expect(table.last.withdrawn, isTrue);
      expect(table.last.advancing, isFalse);
      expect(table.first.played, 0);
      expect(table.map((s) => s.advancing), [true, true, false]);

      // Level on everything: the seed decides.
      final none = BracketRules.standings(const [], {'x': 2, 'y': 1}, const {});
      expect(none.map((s) => s.registrationId), ['y', 'x']);
      expect(none.every((s) => !s.advancing), isTrue);
    });
  });

  group('into the knockout', () {
    test('every group winner ranks ahead of every runner-up', () {
      final groups = [
        DrawGroup(
          id: 'A',
          label: 'A',
          standings: [
            row('a1', place: 1, points: 4, played: 2),
            row('a2', place: 2, points: 2, played: 2),
            row('a3', place: 3, played: 2),
          ],
        ),
        DrawGroup(
          id: 'B',
          label: 'B',
          standings: [
            // A weaker winner than A's, and a runner-up with more points than it.
            row('b1', place: 1, points: 4, played: 3),
            row('b2', place: 2, points: 4, played: 3, setsFor: 4),
            row('b3', place: 3, played: 3),
            row('b4', place: 4, played: 3),
          ],
        ),
      ];
      final seeds = {'a1': 1, 'b1': 2, 'b2': 3, 'a2': 4, 'a3': 5, 'b3': 6, 'b4': 7};
      expect(BracketRules.rankQualifiers(groups, 2, seeds), ['a1', 'b1', 'b2', 'a2']);
      expect(BracketRules.rankQualifiers(groups, 1, seeds), ['a1', 'b1']);
    });

    test('two groups of two: group-mates go into opposite halves', () {
      final slots = BracketRules.placeQualifiers(
        ['A1', 'B1', 'B2', 'A2'],
        {'A1': 'A', 'A2': 'A', 'B1': 'B', 'B2': 'B'},
        4,
      );
      expect(slots, ['A1', 'B2', 'B1', 'A2']);
    });

    test('three qualifiers in four slots: the bye goes next to the best', () {
      final slots = BracketRules.placeQualifiers(['A1', 'B1', 'C1'], {'A1': 'A', 'B1': 'B', 'C1': 'C'}, 4);
      expect(slots, ['A1', null, 'B1', 'C1']);
    });
  });
}
