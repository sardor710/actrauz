import 'dart:async';

import 'package:actra/core/localized_text.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/brackets.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_flow_test.dart' show key;
import '../app_flow_test.dart';
import '../games_host_flow_test.dart' show containerOf;
import '../owner_flow_test.dart' show cell, openCalendar;
import 'organizer_draw_test.dart' show FlakyBackend;

/// The tournament manager's Schedule and Scores tabs (M8a design §7.2–§7.5,
/// §11), and tournament blocks in the owner's calendar.
///
/// Sunday 22 Nov 2026, 10:00 in Tashkent. Sample t1 (padel, 4–5 Dec at
/// Lochin Padel Club: courts v1c1 and v1c2, 90-minute slots from 07:00):
/// men's pairs t1c2 is a published 8-entry knockout, quarter-finals played,
/// semi-finals at 10:00 on 4 Dec on both courts, the final not scheduled.
/// The test cups are on Wednesday 25 Nov.

SampleBackend _backend(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

Future<void> _go(WidgetTester tester, String location) async {
  containerOf(tester).read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

final _cupDay = DateTime.utc(2026, 11, 25);

/// A one-day cup on 25 Nov with two singles categories (A, B), run by the
/// demo player ([venueId] null: without a venue). Returns the tournament and
/// its two categories.
Future<(String, String, String)> _cup(WidgetTester tester, {String sportId = 'padel', String? venueId = 'v1'}) async {
  final backend = _backend(tester);
  final id = await backend.admin.saveTournament(
    TournamentDraft(
      cityId: 'tashkent',
      sportId: sportId,
      venueId: venueId,
      start: _cupDay,
      end: _cupDay,
      title: const LocalizedText.all('Test Cup'),
      categories: [
        CategoryDraft(name: const LocalizedText.all('A'), cap: 16),
        CategoryDraft(name: const LocalizedText.all('B'), cap: 16),
      ],
    ),
  );
  await backend.admin.setOrganizer(id, kMeId, add: true);
  return (id, '${id}c1', '${id}c2');
}

/// A published knockout of [players] in [categoryId].
Future<CategoryDraw> _published(WidgetTester tester, String categoryId, List<String> players) async {
  final backend = _backend(tester);
  for (final p in players) {
    await backend.admin.addRegistration(categoryId, p);
  }
  await backend.organizer.makeDraw(categoryId, DrawFormat.knockout);
  return backend.organizer.publish(categoryId);
}

Future<CategoryDraw> _draw(WidgetTester tester, String tournamentId, String categoryId) async =>
    (await _backend(tester).tournament.bracket(tournamentId)).draw(categoryId)!;

TournamentMatch _ko(CategoryDraw d, int round, int position) =>
    d.matches.firstWhere((m) => m.stage == MatchStage.knockout && m.round == round && m.position == position);

Future<void> _openTab(WidgetTester tester, String tournamentId, String tab) async {
  await _go(tester, '/tournaments/$tournamentId/manage');
  expect(key('tournament-manage-screen'), findsOneWidget);
  await tap(tester, key('manage-tab-$tab'));
}

/// Taps [finder] after scrolling it into view.
Future<void> _tapIn(WidgetTester tester, Finder finder, {int times = 1}) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  for (var i = 0; i < times; i++) {
    await tester.tap(finder);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  group('schedule', () {
    testWidgets('schedules the final on court 1 at 10:00 on the second day, then clears it', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final before = await _draw(tester, 't1', 't1c2');
      final finalMatch = _ko(before, 3, 1);
      await _openTab(tester, 't1', 'schedule');
      expect(key('manage-schedule'), findsOneWidget);

      // The first day: the semi-finals, one per court.
      final sf1 = _ko(before, 2, 1);
      expect(
        find.descendant(of: key('schedule-court-v1c1'), matching: key('schedule-match-${sf1.id}')),
        findsOneWidget,
      );
      // The final has no time yet.
      expect(
        find.descendant(of: key('schedule-unscheduled'), matching: key('schedule-match-${finalMatch.id}')),
        findsOneWidget,
      );

      await _tapIn(tester, key('schedule-match-${finalMatch.id}'));
      await _tapIn(tester, key('sheet-day-2026-12-05'));
      await _tapIn(tester, key('sheet-court-v1c1'));
      await _tapIn(tester, key('sheet-slot-10:00'));
      await _tapIn(tester, key('schedule-save'));

      var after = _ko(await _draw(tester, 't1', 't1c2'), 3, 1);
      expect((after.courtId, after.startsAt), ('v1c1', DateTime.utc(2026, 12, 5, 10)));
      // The tab moved to that day and shows it on court 1.
      expect(
        find.descendant(of: key('schedule-court-v1c1'), matching: key('schedule-match-${finalMatch.id}')),
        findsOneWidget,
      );

      // Clear time.
      await _tapIn(tester, key('schedule-match-${finalMatch.id}'));
      await _tapIn(tester, key('schedule-clear'));
      after = _ko(await _draw(tester, 't1', 't1c2'), 3, 1);
      expect((after.courtId, after.startsAt), (null, null));
      expect(
        find.descendant(of: key('schedule-unscheduled'), matching: key('schedule-match-${finalMatch.id}')),
        findsOneWidget,
      );
    });

    testWidgets('a player busy in another category at that time is refused (playerBusy)', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final (t, a, b) = await _cup(tester);
      final da = await _published(tester, a, ['p1', 'p2']);
      final db = await _published(tester, b, ['p1', 'p3']);
      await _backend(
        tester,
      ).organizer.scheduleMatch(_ko(da, 1, 1).id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 10));
      await _openTab(tester, t, 'schedule');

      final other = _ko(db, 1, 1);
      await _tapIn(tester, key('schedule-match-${other.id}'));
      await _tapIn(tester, key('sheet-court-v1c2'));
      await _tapIn(tester, key('sheet-slot-10:00'));
      await _tapIn(tester, key('schedule-save'));

      expect(find.text('A player in this match is in another match at that time'), findsOneWidget);
      expect(_ko(await _draw(tester, t, b), 1, 1).startsAt, isNull);
    });

    testWidgets('fill the day places what fits and reports the rest', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _backend(tester).owner.setVenueHours(
        'v1',
        weekHours(weekdays: const DayHours.hm(9, 0, 12, 0), weekend: const DayHours.hm(9, 0, 12, 0)),
      );
      final (t, a, _) = await _cup(tester);
      final d = await _published(tester, a, ['p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8']);
      await _openTab(tester, t, 'schedule');

      await _tapIn(tester, key('fill-day'));
      // Both courts, from the first slot, every category: the defaults.
      expect(find.text('Fill the day'), findsWidgets);
      await _tapIn(tester, key('fill-run'));

      expect(key('fill-result'), findsOneWidget);
      expect(find.text('Matches placed: 4'), findsOneWidget);
      for (final m in [_ko(d, 2, 1), _ko(d, 2, 2), _ko(d, 3, 1)]) {
        expect(key('fill-unscheduled-${m.id}'), findsOneWidget);
      }
      await _tapIn(tester, key('fill-done'));

      final after = await _draw(tester, t, a);
      expect(
        [for (var p = 1; p <= 4; p++) (_ko(after, 1, p).courtId, _ko(after, 1, p).startsAt)],
        [
          ('v1c1', DateTime.utc(2026, 11, 25, 9)),
          ('v1c2', DateTime.utc(2026, 11, 25, 9)),
          ('v1c1', DateTime.utc(2026, 11, 25, 10, 30)),
          ('v1c2', DateTime.utc(2026, 11, 25, 10, 30)),
        ],
      );
      expect(
        find.descendant(of: key('schedule-court-v1c2'), matching: key('schedule-match-${_ko(d, 1, 4).id}')),
        findsOneWidget,
      );
    });

    testWidgets('a match whose player is in two places at once shows a clash on Schedule and Scores', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final (t, a, b) = await _cup(tester);
      final org = _backend(tester).organizer;
      final da = await _published(tester, a, ['p1', 'p2', 'p3', 'p4']);
      final db = await _published(tester, b, ['p1', 'p5']);
      await org.scheduleMatch(_ko(da, 2, 1).id, courtId: 'v1c1', startsAt: DateTime.utc(2026, 11, 25, 11, 30));
      await org.scheduleMatch(_ko(db, 1, 1).id, courtId: 'v1c2', startsAt: DateTime.utc(2026, 11, 25, 11, 30));
      final after = await org.enterScore(
        _ko(da, 1, 1).id,
        MatchOutcome.played,
        sets: const [
          [6, 2],
        ],
      );
      final clashed = _ko(after, 2, 1);
      expect(clashed.clash, isTrue);

      await _openTab(tester, t, 'schedule');
      expect(key('schedule-clash-${clashed.id}'), findsOneWidget);
      await tap(tester, key('manage-tab-scores'));
      await tester.ensureVisible(key('scores-clash-${clashed.id}'));
      expect(key('scores-clash-${clashed.id}'), findsOneWidget);
    });
  });

  group('without a venue', () {
    testWidgets('a match gets a time and a place note; no courts and no Fill the day', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final (t, a, _) = await _cup(tester, venueId: null);
      final d = await _published(tester, a, ['p1', 'p2']);
      final m = _ko(d, 1, 1);
      await _openTab(tester, t, 'schedule');
      expect(key('fill-day'), findsNothing);
      expect(key('schedule-court-v1c1'), findsNothing);

      await _tapIn(tester, key('schedule-match-${m.id}'));
      expect(key('sheet-court-v1c1'), findsNothing);
      expect(tester.widget<FilledButton>(key('schedule-save')).onPressed, isNull);
      // The picker opens at 10:00.
      await _tapIn(tester, key('schedule-pick-time'));
      await tap(tester, find.text('OK'));
      expect(find.text('10:00'), findsOneWidget);
      await tester.enterText(key('schedule-place-note'), 'Yunusobod park, court 3');
      await _tapIn(tester, key('schedule-save'));

      final after = _ko(await _draw(tester, t, a), 1, 1);
      expect(
        (after.courtId, after.startsAt, after.placeNote),
        (null, DateTime.utc(2026, 11, 25, 10), 'Yunusobod park, court 3'),
      );
      // The day's list shows it with its place.
      expect(
        find.descendant(of: key('schedule-match-${m.id}'), matching: find.text('10:00 · Yunusobod park, court 3')),
        findsOneWidget,
      );
    });
  });

  group('scores', () {
    testWidgets('6–2 6–3 in a semi-final moves the winner into the final', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final before = await _draw(tester, 't1', 't1c2');
      final sf1 = _ko(before, 2, 1);
      await _openTab(tester, 't1', 'scores');
      expect(key('manage-scores'), findsOneWidget);

      await _tapIn(tester, key('score-match-${sf1.id}'));
      // Padel is rated: the sets of M7's score sheet.
      await _tapIn(tester, key('set-0-mine-plus'), times: 6);
      await _tapIn(tester, key('set-0-theirs-plus'), times: 2);
      await _tapIn(tester, key('score-add-set'));
      await _tapIn(tester, key('set-1-mine-plus'), times: 6);
      await _tapIn(tester, key('set-1-theirs-plus'), times: 3);
      await _tapIn(tester, key('match-score-save'));

      final after = await _draw(tester, 't1', 't1c2');
      expect(_ko(after, 2, 1).sets, [
        [6, 2],
        [6, 3],
      ]);
      expect(_ko(after, 2, 1).winner, Side.a);
      expect(_ko(after, 3, 1).sideA, sf1.sideA);
      expect(find.descendant(of: key('score-match-${sf1.id}'), matching: find.text('6–2 6–3')), findsOneWidget);
    });

    testWidgets('a level football score in a knockout asks who won the decider', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final (t, a, _) = await _cup(tester, sportId: 'football', venueId: 'v2');
      final d = await _published(tester, a, ['p3', 'p1', 'p6', kMeId]);
      final sf1 = _ko(d, 1, 1);
      await _openTab(tester, t, 'scores');

      await _tapIn(tester, key('score-match-${sf1.id}'));
      // One score per side, no sets.
      expect(key('set-0-mine-plus'), findsNothing);
      await _tapIn(tester, key('points-a-plus'), times: 2);
      await _tapIn(tester, key('points-b-plus'), times: 2);
      expect(key('decider-prompt'), findsOneWidget);
      // Not saved until the decider's winner is picked.
      expect(tester.widget<FilledButton>(key('match-score-save')).onPressed, isNull);
      await _tapIn(tester, key('winner-b'));
      await _tapIn(tester, key('match-score-save'));

      final after = _ko(await _draw(tester, t, a), 1, 1);
      expect((after.outcome, after.winner), (MatchOutcome.decider, Side.b));
      expect(after.sets, [
        [2, 2],
      ]);
    });

    testWidgets('a walkover names its winner', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final sf2 = _ko(await _draw(tester, 't1', 't1c2'), 2, 2);
      await _openTab(tester, 't1', 'scores');

      await _tapIn(tester, key('score-match-${sf2.id}'));
      await _tapIn(tester, key('outcome-walkover'));
      expect(key('set-0-mine-plus'), findsNothing);
      expect(tester.widget<FilledButton>(key('match-score-save')).onPressed, isNull);
      await _tapIn(tester, key('winner-b'));
      await _tapIn(tester, key('match-score-save'));

      final after = await _draw(tester, 't1', 't1c2');
      expect((_ko(after, 2, 2).outcome, _ko(after, 2, 2).winner), (MatchOutcome.walkover, Side.b));
      expect(_ko(after, 3, 1).sideB, sf2.sideB);
    });

    testWidgets('a correction once the next match has a score is refused (errNextMatchPlayed)', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final before = await _draw(tester, 't1', 't1c2');
      await _backend(tester).organizer.enterScore(
        _ko(before, 2, 1).id,
        MatchOutcome.played,
        sets: const [
          [6, 1],
          [6, 1],
        ],
      );
      final qf1 = _ko(before, 1, 1);
      await _openTab(tester, 't1', 'scores');

      // The sheet opens again with the score entered.
      await _tapIn(tester, key('score-match-${qf1.id}'));
      expect(tester.widget<Text>(key('set-0-mine')).data, '6');
      expect(tester.widget<Text>(key('set-0-theirs')).data, '3');
      await _tapIn(tester, key('set-1-theirs-plus'));
      await _tapIn(tester, key('match-score-save'));

      expect(find.text('The next match already has a score: this result can no longer change'), findsOneWidget);
      expect(_ko(await _draw(tester, 't1', 't1c2'), 1, 1).sets, qf1.sets);
    });

    testWidgets("withdrawing an entry makes its opponent's match a walkover", (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final sf2 = _ko(await _draw(tester, 't1', 't1c2'), 2, 2);
      await _openTab(tester, 't1', 'scores');

      await _tapIn(tester, key('match-menu-${sf2.id}'));
      await _tapIn(tester, key('withdraw-${sf2.sideA}'));
      expect(find.text('Withdraw this entry?'), findsOneWidget);
      // Cancel keeps it.
      await tap(tester, find.text('Cancel'));
      expect(_ko(await _draw(tester, 't1', 't1c2'), 2, 2).outcome, isNull);

      await _tapIn(tester, key('match-menu-${sf2.id}'));
      await _tapIn(tester, key('withdraw-${sf2.sideA}'));
      await tap(tester, key('confirm-dialog-ok'));

      final after = await _draw(tester, 't1', 't1c2');
      expect((_ko(after, 2, 2).outcome, _ko(after, 2, 2).winner), (MatchOutcome.walkover, Side.b));
      expect(after.entry(sf2.sideA!).withdrawn, isTrue);
      await settleSnackbars(tester);
    });
  });

  group('the owner calendar', () {
    testWidgets('a tournament block reads "Tournament: <title>" and the owner cannot cancel it', (tester) async {
      await openCalendar(tester);
      await tap(tester, find.byTooltip('Next week'));
      await tap(tester, find.byTooltip('Next week'));
      expect(find.text('30 Nov – 6 Dec'), findsOneWidget);
      await tester.ensureVisible(cell('2026-12-04T10:00'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell('2026-12-04T10:00'), matching: find.text('Tournament: Tashkent Padel Cup')),
        findsOneWidget,
      );

      await tap(tester, cell('2026-12-04T10:00'));
      expect(find.text('Tournament: Tashkent Padel Cup'), findsWidgets);
      await tap(tester, find.text('Open this time again'));
      expect(find.text('This time is held for a tournament match. Only the organiser can move it'), findsOneWidget);
      // Still there.
      final semi = _ko(await _draw(tester, 't1', 't1c2'), 2, 1);
      expect(semi.courtId, 'v1c1');
    });
  });

  group('account switches', () {
    testWidgets("another account never sees the previous one's matches on Schedule or Scores", (tester) async {
      final gate = Completer<void>();
      final backends = <FlakyBackend>[];
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) {
          final b = FlakyBackend(utcNow: clock)..gate = backends.isEmpty ? null : gate;
          backends.add(b);
          return b;
        },
      );
      final sf1 = _ko(await _draw(tester, 't1', 't1c2'), 2, 1);
      await _openTab(tester, 't1', 'scores');
      expect(key('score-match-${sf1.id}'), findsOneWidget);
      await tap(tester, key('manage-tab-schedule'));
      expect(key('schedule-match-${sf1.id}'), findsOneWidget);

      await containerOf(tester).read(sessionProvider.notifier).signIn('Other');
      await tester.pump();
      await tester.pump();
      expect(key('schedule-match-${sf1.id}'), findsNothing);

      backends.last.offline = true;
      gate.complete();
      await tester.pumpAndSettle();
      expect(key('tournament-manage-screen'), findsOneWidget);
      expect(key('schedule-match-${sf1.id}'), findsNothing);
      await tap(tester, key('manage-tab-scores'));
      expect(key('score-match-${sf1.id}'), findsNothing);
      await tap(tester, key('manage-tab-schedule'));
      expect(key('schedule-match-${sf1.id}'), findsNothing);
    });
  });

  group('fits a phone', () {
    for (final lang in ['uz', 'ru', 'kk']) {
      testWidgets('Schedule, Scores, their sheets and a tournament block in $lang', (tester) async {
        await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpAndSettle();
        final d = await _draw(tester, 't1', 't1c2');
        final sf1 = _ko(d, 2, 1);
        final finalMatch = _ko(d, 3, 1);

        Future<void> closeSheet() async {
          await tester.tapAt(const Offset(180, 40));
          await tester.pumpAndSettle();
        }

        await _openTab(tester, 't1', 'schedule');
        expect(key('schedule-court-v1c2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tapIn(tester, key('schedule-match-${finalMatch.id}'));
        await _tapIn(tester, key('sheet-court-v1c1'));
        expect(key('sheet-slot-10:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeSheet();
        expect(key('schedule-save'), findsNothing);

        await _tapIn(tester, key('fill-day'));
        expect(key('fill-run'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeSheet();
        expect(key('fill-run'), findsNothing);

        await tap(tester, key('manage-tab-scores'));
        expect(tester.takeException(), isNull);
        await _tapIn(tester, key('score-match-${sf1.id}'));
        await _tapIn(tester, key('outcome-retired'));
        expect(key('winner-a'), findsOneWidget);
        expect(key('set-0-mine-plus'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeSheet();
        expect(key('match-score-save'), findsNothing);
        await _tapIn(tester, key('match-menu-${sf1.id}'));
        expect(key('withdraw-${sf1.sideA}'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // The owner's calendar: the semi-final's block on Friday 4 Dec.
        await _go(tester, '/owner/v1');
        await tap(tester, find.byIcon(Icons.chevron_right_rounded));
        await tap(tester, find.byIcon(Icons.chevron_right_rounded));
        await tester.ensureVisible(cell('2026-12-04T10:00'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: cell('2026-12-04T10:00'), matching: find.byIcon(Icons.lock_outline_rounded)),
          findsNothing,
        );
        expect(find.descendant(of: cell('2026-12-04T10:00'), matching: find.byType(Text)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, cell('2026-12-04T10:00'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
