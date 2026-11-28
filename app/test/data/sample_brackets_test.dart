import 'package:actra/core/localized_text.dart';
import 'package:actra/data/organizer_repository.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/brackets.dart';
import 'package:actra/domain/competitive.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

/// Brackets in sample mode: the rules of the M8a migrations (draws, schedule,
/// match scores, tournament ratings) in memory, on [BracketRules].
///
/// Padel ratings: the demo player 3.50 here; p7 4.50; p1, p5 and p8 3.50;
/// p2 2.50; p3, p4 and p6 have none (1.00 for seeding).
void main() {
  // Sunday 22 Nov 2026, 10:00 in Tashkent. The test tournaments are on
  // Wednesday 25 Nov at Lochin Padel Club (v1: courts v1c1 and v1c2, 90-minute
  // slots from 07:00).
  var utcNow = DateTime.utc(2026, 11, 22, 5);
  final day = DateTime.utc(2026, 11, 25);
  late SampleBackend backend;
  late OrganizerRepository org;

  setUp(() {
    utcNow = DateTime.utc(2026, 11, 22, 5);
    backend = SampleBackend(
      utcNow: () => utcNow,
      meName: 'Sam',
      meRatings: const {'padel': SportRating(rating: 3.5, ratedGames: 12)},
    );
    org = backend.organizer;
  });

  Matcher refuses(TournamentError error) => throwsA(isA<TournamentException>().having((e) => e.error, 'error', error));

  /// A one-day padel tournament at v1 with two singles categories (A, B).
  Future<(String, String, String)> makeTournament({String? venueId = 'v1', String sportId = 'padel'}) async {
    final id = await backend.admin.saveTournament(
      TournamentDraft(
        cityId: 'tashkent',
        sportId: sportId,
        venueId: venueId,
        start: day,
        end: day,
        title: const LocalizedText.all('Test Cup'),
        categories: [
          CategoryDraft(name: const LocalizedText.all('A'), cap: 16),
          CategoryDraft(name: const LocalizedText.all('B'), cap: 16),
        ],
      ),
    );
    return (id, '${id}c1', '${id}c2');
  }

  /// Registers [players] (admin adds) and returns their registration ids.
  Future<Map<String, String>> enter(String categoryId, List<String> players) async => {
    for (final p in players) p: (await backend.admin.addRegistration(categoryId, p)).registration.id,
  };

  const eight = ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];

  TournamentMatch ko(CategoryDraw d, int round, int position) =>
      d.matches.firstWhere((m) => m.stage == MatchStage.knockout && m.round == round && m.position == position);

  /// The entry's (single) player.
  String playerOf(CategoryDraw d, String? registrationId) =>
      registrationId == null ? '-' : d.entry(registrationId).players.first.id;

  List<String> sides(CategoryDraw d, TournamentMatch m) => [playerOf(d, m.sideA), playerOf(d, m.sideB)];

  Future<CategoryDraw> published(String cat, {List<String> players = eight}) async {
    await enter(cat, players);
    await org.makeDraw(cat, DrawFormat.knockout);
    return org.publish(cat);
  }

  group('draws', () {
    test('make: the strongest first, ties in entry order, top seeds apart', () async {
      final (_, a, _) = await makeTournament();
      await enter(a, eight);
      final d = await org.makeDraw(a, DrawFormat.knockout);
      expect(d.published, isFalse);
      expect([for (final e in d.entries) e.players.single.id], ['p7', 'p1', 'p5', 'p8', 'p2', 'p3', 'p4', 'p6']);
      expect(d.entries.first.strength, 4.5);
      // Slots 1,8 | 4,5 | 2,7 | 3,6.
      expect(
        [for (var p = 1; p <= 4; p++) sides(d, ko(d, 1, p))],
        [
          ['p7', 'p6'],
          ['p8', 'p2'],
          ['p1', 'p4'],
          ['p5', 'p3'],
        ],
      );
      expect(d.matches.where((m) => m.stage == MatchStage.knockout), hasLength(7));
      expect(ko(d, 2, 1).status, MatchStatus.waiting);
    });

    test('make: with 7 entries seed 1 has a bye and waits in the semi-final', () async {
      final (_, a, _) = await makeTournament();
      await enter(a, eight.take(7).toList());
      final d = await org.makeDraw(a, DrawFormat.knockout);
      final bye = ko(d, 1, 1);
      expect((bye.status, bye.outcome, bye.winner, bye.bEmpty), (MatchStatus.done, MatchOutcome.bye, Side.a, true));
      expect(playerOf(d, ko(d, 2, 1).sideA), 'p7');
      expect(ko(d, 2, 1).status, MatchStatus.waiting);
    });

    test(
      'make: groups by snake seeding (the extra entry in the last group), a round robin, a waiting knockout',
      () async {
        final (_, a, _) = await makeTournament();
        await enter(a, eight.take(7).toList());
        final d = await org.makeDraw(a, DrawFormat.groups, groupSize: 3, advance: 2);
        expect([for (final g in d.groups) g.label], ['A', 'B']);
        List<int> seedsIn(String groupId) => [
          for (final e in d.entries)
            if (e.groupId == groupId) e.seed,
        ];
        expect(seedsIn(d.groups[0].id), [1, 4, 5]);
        expect(seedsIn(d.groups[1].id), [2, 3, 6, 7]);
        expect(d.matches.where((m) => m.stage == MatchStage.group && m.groupId == d.groups[0].id), hasLength(3));
        expect(d.matches.where((m) => m.stage == MatchStage.group && m.groupId == d.groups[1].id), hasLength(6));
        final knockout = d.matches.where((m) => m.stage == MatchStage.knockout).toList();
        expect(knockout, hasLength(3));
        expect(knockout.every((m) => m.status == MatchStatus.waiting && m.sideA == null), isTrue);
        // Standings before any match: everyone level, in seed order.
        expect(d.groups[0].standings.map((s) => s.place), [1, 2, 3]);
        expect(d.groups[0].standings.first.advancing, isTrue);
      },
    );

    test('make refuses too few entries and bad group settings', () async {
      final (_, a, b) = await makeTournament();
      await enter(a, ['p1']);
      await expectLater(org.makeDraw(a, DrawFormat.knockout), refuses(TournamentError.tooFewEntries));
      await enter(b, ['p1', 'p2']);
      await expectLater(
        org.makeDraw(b, DrawFormat.groups, groupSize: 3, advance: 1),
        refuses(TournamentError.tooFewEntries),
      );
      await expectLater(
        org.makeDraw(b, DrawFormat.groups, groupSize: 5, advance: 1),
        refuses(TournamentError.invalidArgument),
      );
    });

    test('swap exchanges two seeds of a draft; refused once published', () async {
      final (_, a, _) = await makeTournament();
      final regs = await enter(a, eight);
      await org.makeDraw(a, DrawFormat.knockout);
      final d = await org.swapEntries(a, regs['p7']!, regs['p6']!);
      expect(d.entry(regs['p6']!).seed, 1);
      expect(sides(d, ko(d, 1, 1)), ['p6', 'p7']);
      await org.publish(a);
      await expectLater(org.swapEntries(a, regs['p7']!, regs['p6']!), refuses(TournamentError.drawPublished));
      await expectLater(org.makeDraw(a, DrawFormat.knockout), refuses(TournamentError.drawPublished));
    });

    test('publish shows the draw to everyone, tells the players and locks the entries', () async {
      final (t, a, _) = await makeTournament();
      final regs = await enter(a, [...eight.take(7), kMeId]);
      await org.makeDraw(a, DrawFormat.knockout);
      // A draft is for organisers only.
      expect((await backend.bracketAs('p1', t)).draws, isEmpty);
      expect((await backend.tournament.bracket(t)).draws.single.published, isFalse);

      final d = await org.publish(a);
      expect(d.published, isTrue);
      expect((await backend.bracketAs('p1', t)).draws.single.published, isTrue);
      expect((await backend.inbox()).where((n) => n.kind == 'draw_published').single.payload['category_id'], a);

      await expectLater(backend.admin.addRegistration(a, 'p8'), refuses(TournamentError.drawPublished));
      await expectLater(backend.admin.removeRegistration(regs['p1']!), refuses(TournamentError.drawPublished));
    });

    test('an outdated draft refuses publish until it is made again', () async {
      final (t, a, _) = await makeTournament();
      await enter(a, eight.take(4).toList());
      await org.makeDraw(a, DrawFormat.knockout);
      await enter(a, ['p5']);
      expect((await backend.tournament.bracket(t)).draw(a)!.outdated, isTrue);
      await expectLater(org.publish(a), refuses(TournamentError.drawOutdated));
      final again = await org.makeDraw(a, DrawFormat.knockout);
      expect((again.outdated, again.entries.length), (false, 5));
      expect((await org.publish(a)).published, isTrue);
    });

    test('redo makes a new draft until the first score, then the draw is final', () async {
      final (_, a, _) = await makeTournament();
      await published(a);
      final redone = await org.redo(a);
      expect(redone.published, isFalse);
      // Still locked.
      await expectLater(backend.admin.addRegistration(a, kMeId), refuses(TournamentError.drawPublished));
      final d = await org.publish(a);
      await org.enterScore(ko(d, 1, 1).id, MatchOutcome.walkover, winner: Side.a);
      await expectLater(org.redo(a), refuses(TournamentError.drawFinal));
    });
  });

  group('schedule', () {
    test('a court slot on the tournament dates; the block takes the slot; clearing frees it', () async {
      final (_, a, _) = await makeTournament();
      final d = await published(a);
      final qf = ko(d, 1, 1);
      final m = await org.scheduleMatch(qf.id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10));
      expect(
        (m.courtId, m.startsAt, m.endsAt),
        ('v1c1', DateTime.utc(2026, 11, 25, 10), DateTime.utc(2026, 11, 25, 11, 30)),
      );
      expect(m.courtName?.en, 'Court 1');
      Future<SlotState> at10(String court) async => (await backend.availability(
        'v1',
        court,
        day,
      )).firstWhere((s) => s.time.start == DateTime.utc(2026, 11, 25, 10)).state;
      expect(await at10('v1c1'), SlotState.taken);
      expect(
        (await backend.inbox()).where((n) => n.kind == 'match_scheduled'),
        isEmpty,
        reason: 'the demo is not in it',
      );

      // Not a slot, not on the dates, or in the past.
      await expectLater(
        org.scheduleMatch(qf.id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 9)),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        org.scheduleMatch(qf.id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 26, 10)),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        org.scheduleMatch(qf.id, courtId: 'v3c1', startsAt: DateTime.utc(2026, 11, 25, 10)),
        refuses(TournamentError.invalidArgument),
      );

      // Another match in the same slot: taken; the refused move keeps its block.
      final other = ko(d, 1, 2);
      await org.scheduleMatch(other.id, courtId: 'v1c2', startsAt: DateTime.utc(2026, 11, 25, 10));
      await expectLater(
        org.scheduleMatch(other.id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10)),
        refuses(TournamentError.slotTaken),
      );
      expect(await at10('v1c2'), SlotState.taken);

      final cleared = await org.scheduleMatch(qf.id);
      expect((cleared.courtId, cleared.startsAt), (null, null));
      expect(await at10('v1c1'), SlotState.free);

      utcNow = DateTime.utc(2026, 11, 25, 6); // 11:00 on the day
      await expectLater(
        org.scheduleMatch(qf.id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10)),
        refuses(TournamentError.inPast),
      );
    });

    test('the owner cannot cancel a tournament block', () async {
      final (_, a, _) = await makeTournament();
      final d = await published(a);
      await org.scheduleMatch(ko(d, 1, 1).id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10));
      final cal = await backend.owner.calendar('v1', 'v1c1', day, 1);
      final slot = cal.slots.firstWhere((s) => s.time.start == DateTime.utc(2026, 11, 25, 10));
      expect((slot.tournament?.title.en, slot.tournament?.matchId), ('Test Cup', ko(d, 1, 1).id));
      expect(cal.slots.where((s) => s.tournament != null), hasLength(1));
      await expectLater(
        backend.owner.cancel(slot.bookingId!),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.tournamentBlock)),
      );
    });

    test(
      'fill the day: 2 courts from 09:00 put the four quarter-finals at 09:00 ×2 and 10:30 ×2, the rest reported',
      () async {
        final (t, a, _) = await makeTournament();
        await backend.owner.setVenueHours(
          'v1',
          weekHours(weekdays: const DayHours.hm(9, 0, 12, 0), weekend: const DayHours.hm(9, 0, 12, 0)),
        );
        final d = await published(a);
        final result = await org.fillDay(t, day, ['v1c1', 'v1c2'], const TimeOfDay(hour: 9, minute: 0));
        expect(result.scheduled, 4);
        expect(result.unscheduled.toSet(), {ko(d, 2, 1).id, ko(d, 2, 2).id, ko(d, 3, 1).id});
        final after = (await backend.tournament.bracket(t)).draw(a)!;
        expect(
          [for (var p = 1; p <= 4; p++) (ko(after, 1, p).courtId, ko(after, 1, p).startsAt)],
          [
            ('v1c1', DateTime.utc(2026, 11, 25, 9)),
            ('v1c2', DateTime.utc(2026, 11, 25, 9)),
            ('v1c1', DateTime.utc(2026, 11, 25, 10, 30)),
            ('v1c2', DateTime.utc(2026, 11, 25, 10, 30)),
          ],
        );
      },
    );

    test('a player is never in two overlapping matches, across categories (playerBusy)', () async {
      final (t, a, b) = await makeTournament();
      final da = await published(a, players: ['p1', 'p2']);
      final db = await published(b, players: ['p1', 'p3']);
      await org.scheduleMatch(ko(da, 1, 1).id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10));
      await expectLater(
        org.scheduleMatch(ko(db, 1, 1).id, courtId: 'v1c2', startsAt: DateTime.utc(2026, 11, 25, 10)),
        refuses(TournamentError.playerBusy),
      );
      // Fill the day puts it in the next slot instead.
      final result = await org.fillDay(t, day, ['v1c1', 'v1c2'], const TimeOfDay(hour: 10, minute: 0));
      expect(result.scheduled, 1);
      final after = (await backend.tournament.bracket(t)).draw(b)!;
      expect(ko(after, 1, 1).startsAt, DateTime.utc(2026, 11, 25, 11, 30));
    });
  });

  group('scores', () {
    test('scores move the winners on to a category winner; played padel moves ratings', () async {
      final (t, a, _) = await makeTournament();
      final regs = await enter(a, ['p7', 'p1', 'p5', kMeId]);
      await org.makeDraw(a, DrawFormat.knockout);
      var d = await org.publish(a);
      // Seeds: p7 (4.5), p1 (3.5), p5 (3.5), the demo (3.5): p7 v demo, p1 v p5.
      expect(sides(d, ko(d, 1, 1)), ['p7', kMeId]);
      d = await org.enterScore(
        ko(d, 1, 1).id,
        MatchOutcome.played,
        sets: [
          [4, 6],
          [3, 6],
        ],
      );
      expect((ko(d, 1, 1).winner, playerOf(d, ko(d, 2, 1).sideA)), (Side.b, kMeId));
      expect((await backend.mySports()).firstWhere((s) => s.sportId == 'padel').rating!.rating, greaterThan(3.5));
      expect((await backend.inbox()).where((n) => n.kind == 'rating_updated'), hasLength(1));

      d = await org.enterScore(ko(d, 1, 2).id, MatchOutcome.walkover, winner: Side.a);
      expect(ko(d, 2, 1).status, MatchStatus.ready);
      await expectLater(
        org.enterScore(
          ko(d, 2, 1).id,
          MatchOutcome.played,
          sets: [
            [6, 6],
          ],
        ),
        refuses(TournamentError.drawNotAllowed),
      );
      d = await org.enterScore(
        ko(d, 2, 1).id,
        MatchOutcome.played,
        sets: [
          [6, 2],
          [6, 1],
        ],
      );
      expect((d.winner, d.runnerUp, d.finished), (regs[kMeId], regs['p1'], true));
      expect((await backend.inbox()).where((n) => n.kind == 'category_won'), hasLength(1));
      final bracket = await backend.tournament.bracket(t);
      expect(bracket.finished, isTrue, reason: 'category B has no draw: it is left out');
      expect(
        [
          for (final m in await backend.tournament.myMatches())
            if (m.tournamentId == t) m.match.status,
        ],
        [MatchStatus.done, MatchStatus.done],
      );
    });

    test('a correction moves the new winner on, and is refused once the next match is scored', () async {
      final (_, a, _) = await makeTournament();
      final regs = await enter(a, ['p7', 'p1', 'p5', kMeId]);
      await org.makeDraw(a, DrawFormat.knockout);
      var d = await org.publish(a);
      final qf = ko(d, 1, 1).id;
      d = await org.enterScore(
        qf,
        MatchOutcome.played,
        sets: [
          [6, 4],
        ],
      );
      final ratingAfterLoss = (await backend.mySports()).firstWhere((s) => s.sportId == 'padel').rating!;
      expect(ratingAfterLoss.rating, lessThan(3.5));
      // Corrected before the semi-final has a score: the demo goes through,
      // the old change is taken back once and the new one applied once.
      d = await org.enterScore(
        qf,
        MatchOutcome.played,
        sets: [
          [4, 6],
        ],
      );
      expect(ko(d, 2, 1).sideA, regs[kMeId]);
      final rating = (await backend.mySports()).firstWhere((s) => s.sportId == 'padel').rating!;
      expect(rating.rating, greaterThan(3.5));
      expect(rating.ratedGames, 13);

      d = await org.enterScore(ko(d, 1, 2).id, MatchOutcome.walkover, winner: Side.b);
      d = await org.enterScore(
        ko(d, 2, 1).id,
        MatchOutcome.played,
        sets: [
          [6, 0],
        ],
      );
      await expectLater(
        org.enterScore(
          qf,
          MatchOutcome.played,
          sets: [
            [6, 4],
          ],
        ),
        refuses(TournamentError.nextMatchPlayed),
      );
      expect((await org.withdraw(regs['p1']!)).finished, isTrue, reason: 'a finished category keeps its result');
    });

    test('a withdrawal makes walkovers; both sides gone leaves no winner, and the next is a walkover', () async {
      final (_, a, _) = await makeTournament();
      final regs = await enter(a, eight);
      await org.makeDraw(a, DrawFormat.knockout);
      var d = await org.publish(a);
      // QF1 p7 v p6.
      d = await org.withdraw(regs['p6']!);
      final qf1 = ko(d, 1, 1);
      expect((qf1.status, qf1.outcome, qf1.winner), (MatchStatus.done, MatchOutcome.walkover, Side.a));
      expect(d.entry(regs['p6']!).withdrawn, isTrue);
      expect(playerOf(d, ko(d, 2, 1).sideA), 'p7');
      d = await org.withdraw(regs['p7']!);
      expect((ko(d, 1, 1).outcome, ko(d, 1, 1).winner), (MatchOutcome.none, null));
      expect(ko(d, 2, 1).aEmpty, isTrue);
      // QF2 p8 v p2: its winner gets the semi-final as a walkover.
      d = await org.enterScore(
        ko(d, 1, 2).id,
        MatchOutcome.played,
        sets: [
          [6, 3],
        ],
      );
      final sf = ko(d, 2, 1);
      expect((sf.status, sf.outcome, playerOf(d, sf.winnerEntry)), (MatchStatus.done, MatchOutcome.walkover, 'p8'));
      await expectLater(org.withdraw(regs['p7']!), refuses(TournamentError.notFound));
    });

    test('a bracket full of withdrawals still finishes, with no match left waiting', () async {
      final (_, a, _) = await makeTournament();
      final regs = await enter(a, eight);
      await org.makeDraw(a, DrawFormat.knockout);
      var d = await org.publish(a);
      // Both sides of QF1 (p7, p6) withdraw; p1 (QF3) withdraws while waiting
      // in the semi-final for an opponent not yet known.
      d = await org.withdraw(regs['p7']!);
      d = await org.withdraw(regs['p6']!);
      d = await org.enterScore(
        ko(d, 1, 3).id,
        MatchOutcome.played,
        sets: [
          [6, 0],
        ],
      );
      d = await org.withdraw(regs['p1']!);
      d = await org.enterScore(
        ko(d, 1, 2).id,
        MatchOutcome.played,
        sets: [
          [6, 1],
        ],
      );
      d = await org.enterScore(
        ko(d, 1, 4).id,
        MatchOutcome.played,
        sets: [
          [6, 2],
        ],
      );
      expect(d.matches.where((m) => m.status != MatchStatus.done).map((m) => (m.round, m.position)), [(3, 1)]);
      d = await org.enterScore(ko(d, 3, 1).id, MatchOutcome.walkover, winner: Side.a);
      expect(d.matches.every((m) => m.status == MatchStatus.done), isTrue);
      expect((d.finished, playerOf(d, d.winner)), (true, 'p8'));
    });

    test('a group correction is refused once a knockout match has a score', () async {
      final (_, a, _) = await makeTournament();
      await enter(a, ['p7', 'p1', 'p5', 'p8', 'p2', 'p3']);
      await org.makeDraw(a, DrawFormat.groups, groupSize: 3, advance: 1);
      var d = await org.publish(a);
      final groupMatches = d.matches.where((m) => m.stage == MatchStage.group).toList();
      for (final m in groupMatches) {
        d = await org.enterScore(m.id, MatchOutcome.walkover, winner: Side.a);
      }
      d = await org.enterScore(ko(d, 1, 1).id, MatchOutcome.walkover, winner: Side.a);
      await expectLater(
        org.enterScore(groupMatches.first.id, MatchOutcome.walkover, winner: Side.b),
        refuses(TournamentError.nextMatchPlayed),
      );
    });

    test('a winner advancing into a slot that overlaps their match elsewhere is flagged clash', () async {
      final (_, a, b) = await makeTournament();
      final da = await published(a, players: ['p1', 'p2', 'p3', 'p4']);
      final db = await published(b, players: ['p1', 'p5']);
      // A's final at 11:30 before anyone is in it; B's match with p1 at 11:30.
      await org.scheduleMatch(ko(da, 2, 1).id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 11, 30));
      await org.scheduleMatch(ko(db, 1, 1).id, courtId: 'v1c2', startsAt: DateTime.utc(2026, 11, 25, 11, 30));
      // A's semi-final: p1 (seed 1) beats p4.
      expect(sides(da, ko(da, 1, 1)), ['p1', 'p4']);
      final after = await org.enterScore(
        ko(da, 1, 1).id,
        MatchOutcome.played,
        sets: [
          [6, 2],
        ],
      );
      expect(ko(after, 2, 1).clash, isTrue);
    });

    test('a deleted account is withdrawn: its unplayed matches become walkovers', () async {
      final (t, a, _) = await makeTournament();
      await published(a);
      backend.markDeleted('p6');
      final d = (await backend.tournament.bracket(t)).draw(a)!;
      expect((ko(d, 1, 1).outcome, playerOf(d, ko(d, 2, 1).sideA)), (MatchOutcome.walkover, 'p7'));
    });

    test('group standings decide the knockout', () async {
      final (_, a, _) = await makeTournament();
      await enter(a, ['p7', 'p1', 'p5', 'p8', 'p2', 'p3']);
      await org.makeDraw(a, DrawFormat.groups, groupSize: 3, advance: 1);
      var d = await org.publish(a);
      for (final m in d.matches.where((m) => m.stage == MatchStage.group).toList()) {
        // The better seed wins every group match.
        final aSeed = d.entry(m.sideA!).seed, bSeed = d.entry(m.sideB!).seed;
        d = await org.enterScore(
          m.id,
          MatchOutcome.played,
          sets: [
            aSeed < bSeed ? [6, 1] : [1, 6],
          ],
        );
      }
      final finalMatch = ko(d, 1, 1);
      expect(finalMatch.status, MatchStatus.ready);
      expect({playerOf(d, finalMatch.sideA), playerOf(d, finalMatch.sideB)}, {'p7', 'p1'});
      expect(d.groups.every((g) => g.standings.first.points == 4 && g.standings.first.advancing), isTrue);
    });

    test('a walkover before the start gives the slot back; from the start on the slot stays', () async {
      final (_, a, _) = await makeTournament();
      final d = await published(a);
      final qf1 = ko(d, 1, 1).id, qf2 = ko(d, 1, 2).id;
      await org.scheduleMatch(qf1, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10));
      await org.scheduleMatch(qf2, courtId: 'v1c2', startsAt: DateTime.utc(2026, 11, 25, 10));
      var after = await org.enterScore(qf1, MatchOutcome.walkover, winner: Side.a);
      expect((ko(after, 1, 1).courtId, ko(after, 1, 1).startsAt), (null, null));
      final slots = await backend.availability('v1', 'v1c1', day);
      expect(slots.firstWhere((s) => s.time.start == DateTime.utc(2026, 11, 25, 10)).state, SlotState.free);

      utcNow = DateTime.utc(2026, 11, 25, 5, 30); // 10:30 on the day
      after = await org.enterScore(qf2, MatchOutcome.walkover, winner: Side.a);
      expect((ko(after, 1, 2).courtId, ko(after, 1, 2).startsAt), ('v1c2', DateTime.utc(2026, 11, 25, 10)));
    });

    test('a withdrawal in a locked draft (after a redo) only marks it out of date', () async {
      final (t, a, _) = await makeTournament();
      final regs = await enter(a, eight);
      await org.makeDraw(a, DrawFormat.knockout);
      await org.publish(a);
      await org.redo(a);
      final d = await org.withdraw(regs['p6']!);
      expect((d.published, d.outdated, d.entries.length), (false, true, 8));
      final row = (await backend.admin.registrations(t)).firstWhere((r) => r.registration.id == regs['p6']);
      expect((row.registration.status, row.adminOverride), (RegistrationStatus.removed, true));
      await expectLater(org.publish(a), refuses(TournamentError.drawOutdated));
      expect((await org.makeDraw(a, DrawFormat.knockout)).entries, hasLength(7));
    });

    test('padel: no decider, and a retirement moves no rating', () async {
      final (_, a, _) = await makeTournament();
      final d = await published(a, players: ['p1', kMeId]);
      final f = ko(d, 1, 1).id;
      await expectLater(
        org.enterScore(
          f,
          MatchOutcome.decider,
          winner: Side.a,
          sets: [
            [3, 3],
          ],
        ),
        refuses(TournamentError.invalidArgument),
      );
      await org.enterScore(
        f,
        MatchOutcome.retired,
        winner: Side.a,
        sets: [
          [2, 1],
        ],
      );
      expect((await backend.inbox()).where((n) => n.kind == 'rating_updated'), isEmpty);
      expect((await backend.mySports()).firstWhere((s) => s.sportId == 'padel').rating!.rating, 3.5);
    });

    test('a sport without sets: one score each, deciders in the knockout, draws in groups, no ratings', () async {
      final (_, a, b) = await makeTournament(venueId: 'v2', sportId: 'football');
      // Football levels: p3 4, p1 3, p6 2, the demo player none (0).
      await enter(a, ['p3', 'p1', 'p6', kMeId]);
      await org.makeDraw(a, DrawFormat.knockout);
      var d = await org.publish(a);
      expect(sides(d, ko(d, 1, 1)), ['p3', kMeId]);
      expect(sides(d, ko(d, 1, 2)), ['p1', 'p6']);
      final sf1 = ko(d, 1, 1).id, sf2 = ko(d, 1, 2).id;
      await expectLater(
        org.enterScore(
          sf1,
          MatchOutcome.played,
          sets: [
            [2, 2],
          ],
        ),
        refuses(TournamentError.drawNotAllowed),
      );
      await expectLater(
        org.enterScore(
          sf1,
          MatchOutcome.played,
          sets: [
            [100, 1],
          ],
        ),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        org.enterScore(
          sf1,
          MatchOutcome.played,
          sets: [
            [2, 1],
            [1, 0],
          ],
        ),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        org.enterScore(
          sf2,
          MatchOutcome.decider,
          winner: Side.a,
          sets: [
            [3, 1],
          ],
        ),
        refuses(TournamentError.invalidArgument),
      );
      d = await org.enterScore(
        sf1,
        MatchOutcome.decider,
        winner: Side.b,
        sets: [
          [2, 2],
        ],
      );
      expect((ko(d, 1, 1).outcome, playerOf(d, ko(d, 2, 1).sideA)), (MatchOutcome.decider, kMeId));
      expect((await backend.inbox()).where((n) => n.kind == 'match_result'), hasLength(1));
      expect((await backend.inbox()).where((n) => n.kind == 'rating_updated'), isEmpty);

      await enter(b, ['p3', 'p1', 'p6']);
      await org.makeDraw(b, DrawFormat.groups, groupSize: 3, advance: 1);
      final g = await org.publish(b);
      final drawn = await org.enterScore(
        g.matches.first.id,
        MatchOutcome.played,
        sets: [
          [1, 1],
        ],
      );
      expect(drawn.matches.first.winner, Side.draw);
      expect(drawn.groups.single.standings.where((s) => s.drawn == 1), hasLength(2));
    });
  });

  group('without a venue', () {
    test('a time and a place note, no court or block; one instant per match for clashes', () async {
      final (t, a, b) = await makeTournament(venueId: null);
      final da = await published(a, players: ['p1', 'p2']);
      final db = await published(b, players: ['p1', 'p3']);
      final at = DateTime.utc(2026, 11, 25, 10, 15);
      await expectLater(
        org.scheduleMatch(ko(da, 1, 1).id, courtId: 'v1c1', startsAt: at),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        org.scheduleMatch(ko(da, 1, 1).id, startsAt: at, placeNote: 'x' * 101),
        refuses(TournamentError.invalidArgument),
      );
      final m = await org.scheduleMatch(ko(da, 1, 1).id, startsAt: at, placeNote: ' Central park ');
      expect((m.courtId, m.startsAt, m.endsAt, m.placeNote), (null, at, null, 'Central park'));
      await expectLater(org.scheduleMatch(ko(db, 1, 1).id, startsAt: at), refuses(TournamentError.playerBusy));
      // A minute later is another instant.
      await org.scheduleMatch(ko(db, 1, 1).id, startsAt: at.add(const Duration(minutes: 1)));
      await expectLater(
        org.fillDay(t, day, ['v1c1'], const TimeOfDay(hour: 9, minute: 0)),
        refuses(TournamentError.invalidArgument),
      );
    });
  });

  group('organisers', () {
    test('a named organiser runs the tournament; anyone else is not allowed', () async {
      final (t, a, _) = await makeTournament();
      await enter(a, eight.take(4).toList());
      final p1 = backend.organizerAs('p1');
      await expectLater(p1.makeDraw(a, DrawFormat.knockout), refuses(TournamentError.notAllowed));
      await expectLater(p1.entries(t), refuses(TournamentError.notAllowed));
      expect((await backend.bracketAs('p1', t)).organizer, isFalse);

      await backend.admin.setOrganizer(t, 'p1', add: true);
      expect((await p1.organizedTournaments()).map((x) => x.id), [t]);
      await p1.makeDraw(a, DrawFormat.knockout);
      final seen = await backend.bracketAs('p1', t);
      expect((seen.organizer, seen.draws.single.published), (true, false));
      expect(seen.courts.map((c) => c.id), ['v1c1', 'v1c2']);
      expect((await backend.bracketAs('p2', t)).draws, isEmpty, reason: 'a draft is for organisers');

      await backend.admin.setOrganizer(t, 'p1', add: false);
      await expectLater(p1.publish(a), refuses(TournamentError.notAllowed));
    });
  });

  group('fill the day with groups', () {
    // One group of four, two advancing: three rounds of two, then the final.
    // v1's slots: 07:00, 08:30, 10:00, 11:30, 13:00, 14:30, 16:00, 17:30, …
    Future<(String, CategoryDraw)> groupOfFour() async {
      final (t, a, _) = await makeTournament();
      await enter(a, ['p7', 'p1', 'p5', 'p8']);
      await org.makeDraw(a, DrawFormat.groups, groupSize: 4, advance: 2);
      return (t, await org.publish(a));
    }

    List<(int, int, String?, DateTime?)> times(CategoryDraw d) => [
      for (final m in d.matches) (m.round, m.position, m.courtId, m.startsAt),
    ];

    test('a free slot between an entry\'s group matches; the final after the last of them', () async {
      final (t, d) = await groupOfFour();
      final result = await org.fillDay(t, day, ['v1c1', 'v1c2'], const TimeOfDay(hour: 9, minute: 0));
      expect(result.scheduled, 7);
      expect(result.unscheduled, isEmpty);
      final after = (await backend.tournament.bracket(t)).draw(d.categoryId)!;
      DateTime at(int h, int m) => DateTime.utc(2026, 11, 25, h, m);
      expect(times(after), [
        (1, 1, 'v1c1', at(10, 0)),
        (1, 2, 'v1c2', at(10, 0)),
        (2, 1, 'v1c1', at(13, 0)),
        (2, 2, 'v1c2', at(13, 0)),
        (3, 1, 'v1c1', at(16, 0)),
        (3, 2, 'v1c2', at(16, 0)),
        (1, 1, 'v1c1', at(17, 30)),
      ]);
    });

    test('without room for the gap, the last round goes back to back; the final is reported', () async {
      // Slots 10:00, 11:30 and 13:00. With the gap rounds 1 and 2 take 10:00 and
      // 13:00; round 3 then fits only without it, at 11:30.
      await backend.owner.setVenueHours(
        'v1',
        weekHours(weekdays: const DayHours.hm(10, 0, 14, 30), weekend: const DayHours.hm(10, 0, 14, 30)),
      );
      final (t, d) = await groupOfFour();
      final result = await org.fillDay(t, day, ['v1c1', 'v1c2'], const TimeOfDay(hour: 9, minute: 0));
      final finalId = d.matches.firstWhere((m) => m.stage == MatchStage.knockout).id;
      expect(result.scheduled, 6);
      expect(result.unscheduled, [finalId]);
      final after = (await backend.tournament.bracket(t)).draw(d.categoryId)!;
      expect(times(after).where((r) => r.$1 == 3).map((r) => r.$4), everyElement(DateTime.utc(2026, 11, 25, 11, 30)));
    });
  });

  group('the sample data', () {
    test(
      't1 has a published 8-entry knockout: quarter-finals played, semi-finals scheduled, the demo in one',
      () async {
        final bracket = await backend.tournament.bracket('t1');
        expect(bracket.organizer, isTrue);
        final d = bracket.draws.single;
        expect((d.published, d.format, d.entries.length), (true, DrawFormat.knockout, 8));
        expect([for (var p = 1; p <= 4; p++) ko(d, 1, p).outcome], everyElement(MatchOutcome.played));
        for (final sf in [ko(d, 2, 1), ko(d, 2, 2)]) {
          expect(sf.status, MatchStatus.ready);
          expect(sf.courtId, startsWith('v1c'));
          expect(sf.startsAt, isNotNull);
        }
        expect(bracket.myNextMatch?.match.id, ko(d, 2, 1).id);
        expect((await backend.tournament.myMatches()).map((m) => m.tournamentId), everyElement('t1'));
        expect((await org.organizedTournaments()).map((t) => t.id), ['t1']);
        expect((await backend.admin.organizers('t1')).map((p) => p.id), [kMeId]);
        for (final id in ['t2', 't3']) {
          expect((await backend.tournament.bracket(id)).draws, isEmpty, reason: id);
        }
        // The demo player's entry is locked in, and t1 keeps its sport, venue and dates.
        await expectLater(backend.tournament.cancel('t1c2-e1'), refuses(TournamentError.drawPublished));
        final t1 = await backend.tournament.get('t1');
        await expectLater(
          backend.admin.saveTournament(TournamentDraft.from(t1)..venueId = null),
          refuses(TournamentError.drawExists),
        );
        await expectLater(
          backend.admin.saveTournament(TournamentDraft.from(t1)..start = t1.start.add(const Duration(days: 1))),
          refuses(TournamentError.matchesOutsideDates),
        );
      },
    );

    test('admins name organisers, who hear about it', () async {
      final list = await backend.admin.setOrganizer('t2', 'p1', add: true);
      expect(list.map((p) => p.id), ['p1']);
      expect((await backend.admin.setOrganizer('t2', 'p1', add: false)), isEmpty);
      await expectLater(backend.admin.setOrganizer('nope', 'p1', add: true), refuses(TournamentError.notFound));
    });

    test('the organiser sees every entry of the tournament with phones', () async {
      final entries = await org.entries('t1');
      expect(entries.where((e) => e.registration.categoryId == 't1c2'), hasLength(8));
    });
  });
}
