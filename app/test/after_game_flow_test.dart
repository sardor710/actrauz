import 'package:actra/core/theme.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/games/finished_section.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/features/games/report_sheet.dart';
import 'package:actra/features/profile/profile_screen.dart';
import 'package:actra/features/social/player_profile_screen.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf;

Future<void> _go(WidgetTester tester, String path) async {
  containerOf(tester).read(routerProvider).go(path);
  await tester.pumpAndSettle();
}

Future<void> _openGame(WidgetTester tester, String id) async {
  await _go(tester, '/games/$id');
  expect(find.byType(GameScreen), findsOneWidget);
}

Future<Game> _backendGame(WidgetTester tester, String id) => containerOf(tester).read(sampleBackendProvider).game(id);

IconButton _button(WidgetTester tester, String key) => tester.widget<IconButton>(find.byKey(ValueKey(key)));

Future<void> _openMenu(WidgetTester tester, String playerId) async {
  await tester.ensureVisible(find.byKey(ValueKey('player-menu-$playerId')));
  await tap(tester, find.byKey(ValueKey('player-menu-$playerId')));
}

/// [home] on its own, with the app's localisations and theme.
Future<void> _pumpAlone(WidgetTester tester, Widget home, {List<Override> overrides = const []}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildTheme(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('thumbs up a player after the game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    // gf3: football, hosted by Aziz, with me, Dilnoza and Timur.
    await _openGame(tester, 'gf3');

    expect(find.byKey(const ValueKey('finished-section')), findsOneWidget);
    expect(find.text('Rate the other players. Votes are anonymous'), findsOneWidget);
    for (final id in ['p1', 'p2', 'p3']) {
      expect(find.byKey(ValueKey('after-game-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('after-game-me')), findsNothing);
    expect(_button(tester, 'vote-up-p1').isSelected, isFalse);

    await tap(tester, find.byKey(const ValueKey('vote-up-p1')));
    expect((await _backendGame(tester, 'gf3')).afterGame!.myVotes, {'p1': true});
    expect(_button(tester, 'vote-up-p1').isSelected, isTrue);
    expect(_button(tester, 'vote-down-p1').isSelected, isFalse);

    // Down replaces up; tapping it again takes the vote back.
    await tap(tester, find.byKey(const ValueKey('vote-down-p1')));
    expect((await _backendGame(tester, 'gf3')).afterGame!.myVotes, {'p1': false});
    expect(_button(tester, 'vote-down-p1').isSelected, isTrue);
    await tap(tester, find.byKey(const ValueKey('vote-down-p1')));
    expect((await _backendGame(tester, 'gf3')).afterGame!.myVotes, isEmpty);
    expect(_button(tester, 'vote-down-p1').isSelected, isFalse);
  });

  testWidgets('mark a no-show and undo it', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf3');

    await _openMenu(tester, 'p2');
    final item = find.byKey(const ValueKey('menu-no-show'));
    final check = find.byKey(const ValueKey('menu-no-show-check'));
    expect(check, findsNothing);
    await tap(tester, item);
    expect((await _backendGame(tester, 'gf3')).afterGame!.myNoShows, {'p2'});

    await _openMenu(tester, 'p2');
    expect(check, findsOneWidget);
    await tap(tester, item);
    expect((await _backendGame(tester, 'gf3')).afterGame!.myNoShows, isEmpty);
  });

  testWidgets('report a player', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf3');

    await _openMenu(tester, 'p2');
    await tap(tester, find.text('Report'));
    expect(find.byType(ReportSheet), findsOneWidget);
    expect(find.text('Report Dilnoza'), findsOneWidget);
    final send = find.byKey(const ValueKey('report-send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'no reason picked');

    await tap(tester, find.text('Abusive language'));
    await tester.enterText(find.byKey(const ValueKey('report-details')), 'Shouted at everyone');
    await tester.pumpAndSettle();
    expect(find.text('19/500'), findsOneWidget);
    await tap(tester, send);

    expect(find.byType(ReportSheet), findsNothing);
    expect(find.text('Report sent'), findsOneWidget);
    await settleSnackbars(tester);

    // The same player and game again: refused, inside the sheet.
    await _openMenu(tester, 'p2');
    await tap(tester, find.text('Report'));
    await tap(tester, find.text('Other'));
    await tap(tester, send);
    expect(find.byType(ReportSheet), findsOneWidget);
    expect(find.text('You have already reported this player').hitTestable(), findsOneWidget);
  });

  testWidgets("a player's profile has Report in its menu", (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _go(tester, '/players/p1');
    expect(find.byType(PlayerProfileScreen), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('profile-menu')));
    await tap(tester, find.text('Report'));
    expect(find.text('Report Aziz'), findsOneWidget);
    await tap(tester, find.text('Aggressive behaviour'));
    await tap(tester, find.byKey(const ValueKey('report-send')));
    expect(find.text('Report sent'), findsOneWidget);
    await settleSnackbars(tester);

    // Not on my own profile.
    await _go(tester, '/players/$kMeId');
    expect(find.byKey(const ValueKey('profile-menu')), findsNothing);
  });

  testWidgets('sportsmanship appears after five votes', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    await backend.voteAs('p2', 'gf1', 'p1', true);
    await backend.voteAs('p3', 'gf1', 'p1', false);
    await backend.voteAs('p2', 'gf3', 'p1', true);
    await backend.voteAs('p3', 'gf3', 'p1', true);

    await _go(tester, '/players/p1');
    expect(find.byKey(const ValueKey('sportsmanship')), findsNothing, reason: 'four votes');

    // My vote is the fifth, from the game page.
    await _openGame(tester, 'gf1');
    await tester.ensureVisible(find.byKey(const ValueKey('vote-up-p1')));
    await tap(tester, find.byKey(const ValueKey('vote-up-p1')));
    await _go(tester, '/players/p1');
    expect(find.byKey(const ValueKey('sportsmanship')), findsOneWidget);
    expect(find.text('80% · 5 votes'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('sportsmanship')),
        matching: find.byIcon(Icons.thumb_up_alt_outlined),
      ),
      findsOneWidget,
    );

    // My own profile shows mine the same way.
    for (final (voter, game, up) in [
      ('p1', 'gf1', true),
      ('p2', 'gf1', true),
      ('p3', 'gf1', true),
      ('p1', 'gf3', true),
      ('p2', 'gf3', false),
    ]) {
      await backend.voteAs(voter, game, kMeId, up);
    }
    await _go(tester, '/profile');
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('80% · 5 votes'), findsOneWidget);
  });

  testWidgets("\"Didn't show up\" and \"Report\" line up in the player menu", (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _openGame(tester, 'gf1');
    await tester.ensureVisible(find.byKey(const ValueKey('player-menu-p1')));
    await tap(tester, find.byKey(const ValueKey('player-menu-p1')));
    expect(
      tester.getTopLeft(find.text("Didn't show up")).dx,
      tester.getTopLeft(find.text('Report')).dx,
    );

    // Marked: the check is shown, and the two still line up.
    await tap(tester, find.text("Didn't show up"));
    await tap(tester, find.byKey(const ValueKey('player-menu-p1')));
    expect(find.byKey(const ValueKey('menu-no-show-check')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text("Didn't show up")).dx,
      tester.getTopLeft(find.text('Report')).dx,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  });

  testWidgets('my own row on the game page keeps its pills whole on a 375-wide phone in ru', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'ru'}, utcNow: sundayMorning);
    tester.view.physicalSize = const Size(375, 2400);
    await tester.pumpAndSettle();
    await _openGame(tester, 'gf1');
    final row = find.byKey(const ValueKey('game-player-me'));
    await tester.ensureVisible(row);
    for (final text in ['Организатор', 'Надёжный']) {
      final label = find.descendant(of: row, matching: find.textContaining(text));
      expect(label, findsOneWidget, reason: text);
      expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse, reason: text);
    }
  });

  group('by time', () {
    // Played Saturday 18:00-19:30 in Tashkent (UTC+5); the demo player is not the host.
    final end = DateTime.utc(2026, 11, 21, 19, 30);
    DateTime utcAfterEnd(Duration d) => end.subtract(const Duration(hours: 5)).add(d);
    final game = Game(
      id: 'gx',
      sportId: 'football',
      cityId: 'tashkent',
      hostId: 'p1',
      start: end.subtract(const Duration(minutes: 90)),
      end: end,
      spots: 4,
      participantIds: const ['p1', kMeId, 'p2'],
      participants: const [
        GameMember(id: 'p1', name: 'Aziz'),
        GameMember(id: kMeId, name: 'Test'),
        GameMember(id: 'p2', name: '', deleted: true),
      ],
      myStatus: MyGameStatus.participant,
      afterGame: const AfterGame(myVotes: {'p1': true}),
    );

    Future<void> pumpAt(WidgetTester tester, Duration afterEnd, {Game? g}) => _pumpAlone(
      tester,
      Scaffold(
        body: ListView(children: [FinishedSection(game: g ?? game)]),
      ),
      overrides: [
        clockProvider.overrideWithValue(() => utcAfterEnd(afterEnd)),
        sportsProvider.overrideWith((ref) async => kSampleSports),
      ],
    );

    testWidgets('no "didn\'t show up" after 48 hours; no votes after 7 days', (tester) async {
      await pumpAt(tester, const Duration(hours: 47));
      expect(_button(tester, 'vote-up-p1').onPressed, isNotNull);
      expect(_button(tester, 'vote-up-p1').isSelected, isTrue);
      await tap(tester, find.byKey(const ValueKey('player-menu-p1')));
      expect(find.text("Didn't show up"), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);

      await pumpAt(tester, const Duration(hours: 49));
      expect(_button(tester, 'vote-up-p1').onPressed, isNotNull);
      await tap(tester, find.byKey(const ValueKey('player-menu-p1')));
      expect(find.text("Didn't show up"), findsNothing);
      expect(find.text('Report'), findsOneWidget);

      await pumpAt(tester, const Duration(days: 8));
      expect(_button(tester, 'vote-up-p1').onPressed, isNull);
      expect(_button(tester, 'vote-down-p1').onPressed, isNull);
      expect(_button(tester, 'vote-up-p1').isSelected, isTrue, reason: 'my vote still shows');
      expect(find.byKey(const ValueKey('player-menu-p1')), findsOneWidget, reason: 'reports have no deadline');
    });

    testWidgets('a player who did not play, or was only invited, sees no finished section', (tester) async {
      Game as(MyGameStatus? status) => Game(
        id: 'gx',
        sportId: 'football',
        cityId: 'tashkent',
        hostId: 'p1',
        start: game.start,
        end: game.end,
        spots: 4,
        participantIds: const ['p1', 'p2'],
        participants: const [GameMember(id: 'p1', name: 'Aziz'), GameMember(id: 'p2', name: 'Dilnoza')],
        myStatus: status,
      );
      for (final status in [null, MyGameStatus.invited, MyGameStatus.requested]) {
        await pumpAt(tester, const Duration(hours: 2), g: as(status));
        expect(find.byKey(const ValueKey('finished-section')), findsNothing, reason: '$status');
      }
    });

    testWidgets('a deleted player gets no row, and a game alone has no section', (tester) async {
      await pumpAt(tester, const Duration(hours: 2));
      expect(find.byKey(const ValueKey('after-game-p1')), findsOneWidget);
      expect(find.byKey(const ValueKey('after-game-p2')), findsNothing);

      final alone = Game(
        id: 'gy',
        sportId: 'football',
        cityId: 'tashkent',
        hostId: kMeId,
        start: game.start,
        end: game.end,
        spots: 4,
        participantIds: const [kMeId],
        participants: const [GameMember(id: kMeId, name: 'Test')],
        myStatus: MyGameStatus.host,
      );
      await pumpAt(tester, const Duration(hours: 2), g: alone);
      expect(find.byKey(const ValueKey('finished-section')), findsNothing);
    });
  });

  for (final lang in ['ru', 'kk', 'uz']) {
    testWidgets('the after-game rows, menu and report sheet fit a phone in $lang', (tester) async {
      await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();

      // A rated game (score block and rows) and a simple one (rows only).
      await _openGame(tester, 'gf1');
      await tester.ensureVisible(find.byKey(const ValueKey('after-game-p1')));
      await tester.pumpAndSettle();
      await _openGame(tester, 'gf3');
      await tester.ensureVisible(find.byKey(const ValueKey('after-game-p2')));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('vote-up-p2')));

      await _openMenu(tester, 'p2');
      expect(find.byKey(const ValueKey('menu-no-show')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('menu-no-show')));
      await _openMenu(tester, 'p2');
      await tap(tester, find.byKey(const ValueKey('menu-report')));
      expect(find.byType(ReportSheet), findsOneWidget);
      for (final reason in ReportReason.values) {
        expect(find.byKey(ValueKey('report-reason-${reason.name}')), findsOneWidget);
      }
      await tap(tester, find.byKey(const ValueKey('report-reason-falseScore')));
      await tap(tester, find.byKey(const ValueKey('report-send')));
      await settleSnackbars(tester);

      // The profile line with its menu.
      final backend = containerOf(tester).read(sampleBackendProvider);
      for (final (voter, game) in [('p2', 'gf1'), ('p3', 'gf1'), ('p2', 'gf3'), ('p3', 'gf3'), (kMeId, 'gf1')]) {
        await backend.voteAs(voter, game, 'p1', true);
      }
      await _go(tester, '/players/p1');
      expect(find.byKey(const ValueKey('sportsmanship')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('profile-menu')));
    });
  }
}
