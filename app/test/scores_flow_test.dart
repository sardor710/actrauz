import 'package:actra/core/theme.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/competitive.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/common/rating_pill.dart';
import 'package:actra/features/games/finished_section.dart';
import 'package:actra/features/games/game_card.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/features/games/past_games_screen.dart';
import 'package:actra/features/games/score_sheet.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf, refresh;

const _sixFourTwice = [(6, 4), (6, 4)];

/// The sample backend, with a confirm that takes a moment, as over a network.
class _SlowConfirm extends SampleBackend {
  _SlowConfirm({required super.utcNow}) : super(meName: 'Test');

  @override
  Future<Game> confirmScore(String resultId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.confirmScore(resultId);
  }
}

/// The demo player's padel rating under `pumpApp(withSports: true)`.
const _myPadel = SportRating(rating: 3.5, ratedGames: 12);

SportRating? _seededPadel(String id) =>
    id == kMeId ? _myPadel : kSamplePlayers.singleWhere((p) => p.id == id).ratings['padel'];

String _changeText(RatingChange c) => '${formatRating(c.oldRating)} → ${formatRating(c.newRating)}';

Future<void> _openGame(WidgetTester tester, String id) async {
  containerOf(tester).read(routerProvider).go('/games/$id');
  await tester.pumpAndSettle();
  expect(find.byType(GameScreen), findsOneWidget);
}

Future<void> _openPastGames(WidgetTester tester) async {
  await tap(tester, find.text('Games'));
  await tap(tester, find.byKey(const ValueKey('games-past')));
  expect(find.byType(PastGamesScreen), findsOneWidget);
}

Future<void> _tapTimes(WidgetTester tester, String key, int times) async {
  for (var i = 0; i < times; i++) {
    await tap(tester, find.byKey(ValueKey(key)));
  }
}

/// Fills set [index] of the open score sheet, from 0–0.
Future<void> _fillSet(WidgetTester tester, int index, int mine, int theirs) async {
  await _tapTimes(tester, 'set-$index-mine-plus', mine);
  await _tapTimes(tester, 'set-$index-theirs-plus', theirs);
}

/// [home] on its own, with the app's localisations and theme.
Future<void> _pumpAlone(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  String lang = 'en',
}) async {
  // A fresh scope each time: overrides cannot change on a live one.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildTheme(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inBoard(String text) =>
    find.descendant(of: find.byKey(const ValueKey('score-board')), matching: find.text(text));

void main() {
  testWidgets('host enters a score', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openPastGames(tester);
    // gf2, gf1, gf3: the latest end first.
    expect(find.byType(GameCard), findsNWidgets(3));
    await tap(tester, find.byType(GameCard).at(1));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('GAME FINISHED'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('score-enter')));
    expect(find.byType(ScoreSheet), findsOneWidget);
    // Four players: me with the first other one against the other two.
    expect(find.text('Your side: You, Aziz', findRichText: true), findsOneWidget);
    expect(find.text('Other side: Dilnoza, Timur', findRichText: true), findsOneWidget);
    // Another partner swaps the sides; it stays 2 against 2.
    await tap(tester, find.byKey(const ValueKey('score-partner-p2')));
    expect(find.text('Your side: You, Dilnoza', findRichText: true), findsOneWidget);
    expect(find.text('Other side: Aziz, Timur', findRichText: true), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('score-partner-p1')));
    expect(find.text('Your side: You, Aziz', findRichText: true), findsOneWidget);

    final save = find.byKey(const ValueKey('score-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: '0–0 is not a set');
    await _fillSet(tester, 0, 6, 4);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tap(tester, find.byKey(const ValueKey('score-add-set')));
    await _fillSet(tester, 1, 6, 4);
    await tap(tester, save);

    expect(find.byType(ScoreSheet), findsNothing);
    expect(_inBoard('6'), findsNWidgets(2));
    expect(_inBoard('4'), findsNWidgets(2));
    expect(find.text('Waiting for the other side'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('score-confirm')), findsNothing);

    final result = (await containerOf(tester).read(sampleBackendProvider).game('gf1')).result!;
    expect(result.status, ResultStatus.pending);
    expect(result.enteredBy, kMeId);
    expect(result.sideA, [kMeId, 'p1']);
    expect(result.sideB, ['p2', 'p3']);
    expect(result.sets, _sixFourTwice);

    // Edit opens the sheet with the score as entered.
    await tap(tester, find.byKey(const ValueKey('score-edit')));
    expect(tester.widget<Text>(find.byKey(const ValueKey('set-1-mine'))).data, '6');
    expect(tester.widget<Text>(find.byKey(const ValueKey('set-1-theirs'))).data, '4');
  });

  testWidgets('rating change is shown after confirmation', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: _sixFourTwice);
    await _openGame(tester, 'gf1');
    expect(find.text('Waiting for the other side'), findsOneWidget);

    await backend.confirmScoreAs('p2', 'r-gf1');
    await refresh(tester);

    // Ruling R2: the expected numbers follow from the seeded ratings.
    final expected = ratingChanges(
      sideA: [_seededPadel(kMeId), _seededPadel('p1')],
      sideB: [_seededPadel('p2'), _seededPadel('p3')],
      sets: _sixFourTwice,
    );
    final changes = {'me': expected.a[0], 'p1': expected.a[1], 'p2': expected.b[0], 'p3': expected.b[1]};
    final stored = (await backend.game('gf1')).result!.changes;
    expect(find.text('Score confirmed'), findsOneWidget);
    for (final MapEntry(key: id, value: change) in changes.entries) {
      expect(_changeText(stored[id]!), _changeText(change));
      expect(tester.widget<Text>(find.byKey(ValueKey('rating-change-$id'))).data, _changeText(change));
    }

    // The inbox has the rating notice, which opens the game.
    containerOf(tester).read(routerProvider).go('/inbox');
    await tester.pumpAndSettle();
    final mine = changes['me']!;
    final notice = find.text(
      'Your rating changed: ${formatRating(mine.oldRating)} → ${formatRating(mine.newRating)}',
    );
    expect(notice, findsOneWidget);
    await tap(tester, notice);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Score confirmed'), findsOneWidget);
  });

  testWidgets('opponent can confirm', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openPastGames(tester);
    await tap(tester, find.byType(GameCard).first);
    expect(find.text('Waiting for confirmation'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-edit')), findsNothing);

    await tap(tester, find.byKey(const ValueKey('score-confirm')));

    expect(find.text('Score confirmed'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-confirm')), findsNothing);
    final expected = ratingChanges(
      sideA: [_seededPadel('p1'), _seededPadel('p3')],
      sideB: [_seededPadel(kMeId), _seededPadel('p2')],
      sets: const [(6, 3), (6, 4)],
    );
    expect(tester.widget<Text>(find.byKey(const ValueKey('rating-change-me'))).data, _changeText(expected.b[0]));
    final result = (await containerOf(tester).read(sampleBackendProvider).game('gf2')).result!;
    expect(result.status, ResultStatus.confirmed);
  });

  testWidgets('a double tap on Confirm confirms once, without an error', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, backend: (clock) => _SlowConfirm(utcNow: clock));
    await _openGame(tester, 'gf2');

    await tester.tap(find.byKey(const ValueKey('score-confirm')));
    await tester.tap(find.byKey(const ValueKey('score-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Score confirmed'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'the second tap did not confirm again');
  });

  testWidgets('opponent can dispute', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf2');

    await tap(tester, find.byKey(const ValueKey('score-dispute')));
    expect(find.text('Dispute the score?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('score-dispute-reason')), 'It was 6–4 7–5');
    await tap(tester, find.byKey(const ValueKey('score-dispute-send')));

    expect(find.text('Disputed — an Actra admin will review'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-confirm')), findsNothing);
    final result = (await containerOf(tester).read(sampleBackendProvider).game('gf2')).result!;
    expect(result.status, ResultStatus.disputed);
    expect(result.disputeReason, 'It was 6–4 7–5');
  });

  testWidgets('past games is empty for a new player', (tester) async {
    // Ruling R10: the sample's finished games always include the demo player.
    await _pumpAlone(
      tester,
      const PastGamesScreen(),
      overrides: [pastGamesProvider.overrideWith((ref) async => const <Game>[])],
    );

    expect(find.text('Past games'), findsOneWidget);
    expect(find.text('No games in the last 30 days'), findsOneWidget);
    expect(find.byType(GameCard), findsNothing);
  });

  testWidgets("the enterer's partner waits for the other side after confirming", (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    // Aziz corrects his score of gf2 with the demo player as his partner.
    await backend.enterScoreAs('p1', 'gf2', sideA: ['p1', kMeId], sideB: ['p2', 'p3'], sets: const [(6, 3), (6, 4)]);
    await _openGame(tester, 'gf2');

    await tap(tester, find.byKey(const ValueKey('score-confirm')));

    expect(find.text('Waiting for the other side'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('score-dispute')), findsNothing);
    final result = (await backend.game('gf2')).result!;
    expect(result.status, ResultStatus.pending, reason: 'a partner does not finish it');
    expect(result.confirmedBy, [kMeId]);
  });

  testWidgets("a score another player entered shows when its notice is opened", (tester) async {
    // Sunday 22:00: more than 24 hours after gf1, so any of its players may enter it.
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning.add(const Duration(hours: 12)));
    await _openGame(tester, 'gf1');
    expect(find.byKey(const ValueKey('score-enter')), findsOneWidget);

    final backend = containerOf(tester).read(sampleBackendProvider);
    await backend.enterScoreAs('p2', 'gf1', sideA: ['p2', 'p3'], sideB: [kMeId, 'p1'], sets: _sixFourTwice);
    containerOf(tester).read(routerProvider).go('/inbox');
    await tester.pumpAndSettle();
    await tap(tester, find.text('The score of your game was entered. Confirm or dispute it').first);

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('score-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('score-dispute')), findsOneWidget);
  });

  testWidgets('pulling the game page down shows what other players changed', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning.add(const Duration(hours: 12)));
    await _openGame(tester, 'gf1');
    await containerOf(tester)
        .read(sampleBackendProvider)
        .enterScoreAs('p2', 'gf1', sideA: ['p2', 'p3'], sideB: [kMeId, 'p1'], sets: _sixFourTwice);

    expect(find.byType(RefreshIndicator), findsOneWidget);
    // Far enough on the tall test screen to start a reload.
    await tester.fling(find.byType(GameScreen), const Offset(0, 1500), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('score-confirm')), findsOneWidget);
  });

  testWidgets('a refused confirm reloads the game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf2');
    // Meanwhile another player disputed it.
    await containerOf(tester).read(sampleBackendProvider).disputeScoreAs('p2', 'r-gf2');

    await tap(tester, find.byKey(const ValueKey('score-confirm')));

    expect(find.byKey(const ValueKey('score-confirm')), findsNothing);
    expect(find.text('Disputed — an Actra admin will review'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('a refused score shows in the sheet', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf1');
    await tap(tester, find.byKey(const ValueKey('score-enter')));
    // Meanwhile the score was entered elsewhere and disputed.
    final backend = containerOf(tester).read(sampleBackendProvider);
    await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: _sixFourTwice);
    await backend.disputeScoreAs('p2', 'r-gf1');

    await _fillSet(tester, 0, 6, 3);
    await tap(tester, find.byKey(const ValueKey('score-save')));

    expect(find.text('A score can no longer be entered for this game').hitTestable(), findsOneWidget);
    expect(find.byType(ScoreSheet), findsOneWidget);
  });

  group('score block by time and state', () {
    // Played Saturday 18:00-19:30 in Tashkent (UTC+5); the demo player is not the host.
    final end = DateTime.utc(2026, 11, 21, 19, 30);
    DateTime utcAfterEnd(Duration d) => end.subtract(const Duration(hours: 5)).add(d);
    Game game({MatchResult? result}) => Game(
      id: 'gx',
      sportId: 'padel',
      cityId: 'tashkent',
      hostId: 'p1',
      start: end.subtract(const Duration(minutes: 90)),
      end: end,
      spots: 2,
      participantIds: const ['p1', kMeId],
      participants: const [GameMember(id: 'p1', name: 'Aziz'), GameMember(id: kMeId, name: 'Test')],
      myStatus: MyGameStatus.participant,
      result: result,
    );
    const voided = MatchResult(
      id: 'r-gx',
      status: ResultStatus.voided,
      sets: [(6, 4)],
      winner: MatchWinner.a,
      enteredBy: 'p1',
      sideA: ['p1'],
      sideB: [kMeId],
    );

    Future<void> pumpBlock(WidgetTester tester, Game g, Duration afterEnd, {String lang = 'en'}) => _pumpAlone(
      tester,
      Scaffold(body: ListView(children: [FinishedSection(game: g)])),
      lang: lang,
      overrides: [
        clockProvider.overrideWithValue(() => utcAfterEnd(afterEnd)),
        sportsProvider.overrideWith((ref) async => kSampleSports),
      ],
    );

    testWidgets('only the host enters it in the first 24 hours, then anyone', (tester) async {
      await pumpBlock(tester, game(), const Duration(hours: 10));
      expect(find.text('The host enters the score. After 24 hours any player can'), findsOneWidget);
      expect(find.byKey(const ValueKey('score-enter')), findsNothing);

      await pumpBlock(tester, game(), const Duration(hours: 25));
      expect(find.byKey(const ValueKey('score-enter')), findsOneWidget);
    });

    testWidgets('entry closes after 7 days', (tester) async {
      await pumpBlock(tester, game(), const Duration(days: 8));
      expect(find.text('Score entry closed'), findsOneWidget);
      expect(find.byKey(const ValueKey('score-enter')), findsNothing);
    });

    testWidgets('a voided result', (tester) async {
      await pumpBlock(tester, game(result: voided), const Duration(days: 2));
      expect(find.text('Result cancelled by Actra'), findsOneWidget);
      expect(find.byKey(const ValueKey('score-board')), findsOneWidget);
    });

    testWidgets('nothing before the end', (tester) async {
      await pumpBlock(tester, game(), const Duration(minutes: -1));
      expect(find.text('GAME FINISHED'), findsNothing);
    });

    for (final lang in ['ru', 'kk']) {
      testWidgets('the states fit a phone in $lang', (tester) async {
        tester.view.physicalSize = const Size(360, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        for (final (g, after) in [
          (game(), const Duration(hours: 10)),
          (game(), const Duration(days: 8)),
          (game(result: voided), const Duration(days: 2)),
        ]) {
          await pumpBlock(tester, g, after, lang: lang);
          expect(find.byType(FinishedSection), findsOneWidget);
        }
      });
    }
  });

  testWidgets('a football game has the finished section without a score block', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf3');

    // The votes and reports of every sport (design §5.8), but no score.
    expect(find.text('GAME FINISHED'), findsOneWidget);
    expect(find.byKey(const ValueKey('finished-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('score-enter')), findsNothing);
    expect(find.byKey(const ValueKey('score-board')), findsNothing);
    expect(find.text('The host enters the score. After 24 hours any player can'), findsNothing);
  });

  for (final lang in ['ru', 'kk']) {
    testWidgets('the score screens fit a phone in $lang', (tester) async {
      await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();

      // The Games tab with its Past games link, then the list.
      containerOf(tester).read(routerProvider).go('/games');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('games-past')));
      await tap(tester, find.byKey(const ValueKey('games-past')));
      expect(find.byType(GameCard), findsNWidgets(3));

      // Pending, with Confirm and Dispute; then confirmed with four changes.
      await _openGame(tester, 'gf2');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('score-confirm')), 200);
      await tap(tester, find.byKey(const ValueKey('score-confirm')));
      for (final id in ['p1', 'p3', kMeId, 'p2']) {
        expect(find.byKey(ValueKey('rating-change-$id')), findsOneWidget);
      }

      // The score sheet with all five sets.
      await _openGame(tester, 'gf1');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('score-enter')), 200);
      await tap(tester, find.byKey(const ValueKey('score-enter')));
      for (var i = 0; i < 4; i++) {
        await tap(tester, find.byKey(const ValueKey('score-add-set')));
      }
      await _tapTimes(tester, 'set-4-mine-plus', 2);
      expect(find.byKey(const ValueKey('set-4-remove')), findsOneWidget);
    });
  }
}
