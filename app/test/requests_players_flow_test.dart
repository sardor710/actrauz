import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/common/rating_pill.dart';
import 'package:actra/features/games/game_request_screen.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/features/social/player_profile_screen.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show bookPadel, containerOf, openGamesTab, refresh, tomorrowAt;

Future<void> openRequestsTab(WidgetTester tester) async {
  await openGamesTab(tester);
  await tap(tester, find.byKey(const ValueKey('games-tab-requests')));
}

Future<void> openSocialTab(WidgetTester tester) => tap(tester, find.text('Social'));

/// The demo player posts a request for [sportId] tomorrow evening.
Future<GameRequest> postRequest(
  WidgetTester tester,
  String sportId, {
  int needed = 2,
  List<String> interested = const [],
}) async {
  final backend = containerOf(tester).read(sampleBackendProvider);
  final request = await backend.createRequest(
    GameRequestDraft(
      sportId: sportId,
      playersNeeded: needed,
      start: tomorrowAt(18),
      end: tomorrowAt(21),
      area: 'Yunusobod',
    ),
  );
  for (final id in interested) {
    await backend.interestAs(id, request.id);
  }
  containerOf(tester).invalidate(gameRequestsProvider);
  await refresh(tester);
  return request;
}

void main() {
  testWidgets('home shows a Game Requests section with the interested count and a See all', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    expect(find.text('GAME REQUESTS'), findsOneWidget);
    expect(find.text('Aziz wants to play Padel'), findsOneWidget);
    expect(find.text('1 of 2 interested'), findsOneWidget);
    // A padel request shows its rating range: levels 2–4 are 2.00–4.99, shown truncated to one decimal.
    final rq1 = await containerOf(tester).read(gameRepositoryProvider).request('rq1');
    expect((rq1.minRating, rq1.maxRating), (2.0, 4.99));
    expect(find.text('2.0–4.9'), findsWidgets);

    await tap(tester, find.descendant(of: find.byKey(const ValueKey('home-requests')), matching: find.text('See all')));
    // The Games tab, on its Requests list.
    expect(find.text('Aziz wants to play Padel'), findsOneWidget);
    expect(find.text('POST A REQUEST'), findsOneWidget);
  });

  testWidgets('"I\'m in" adds the player and the count goes up; Leave takes them off again', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openRequestsTab(tester);
    await tap(tester, find.text('Aziz wants to play Padel'));

    expect(find.byType(GameRequestScreen), findsOneWidget);
    expect(find.text('1 of 2 interested'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, "I'm in"));

    expect(find.text('2 of 2 interested'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, "I'm in"), findsNothing);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Leave'));
    expect(find.text('1 of 2 interested'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, "I'm in"), findsOneWidget);
  });

  testWidgets('a blocked player is told why "I\'m in" is refused', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    for (final ref in ['b1', 'b2', 'b3']) {
      backend.recordReliability(kMeId, ReliabilityKind.noShow, ref);
    }
    await openRequestsTab(tester);
    await tap(tester, find.text('Aziz wants to play Padel'));
    await tap(tester, find.widgetWithText(FilledButton, "I'm in"));

    expect(find.textContaining('You cannot book, join or post'), findsOneWidget);
    expect(find.text('1 of 2 interested'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('the poster sees no "I\'m in", removes a player and cancels the request', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await postRequest(tester, 'running', needed: 3, interested: ['p1', 'p5']);
    await openRequestsTab(tester);
    await tap(tester, find.text('Test wants to play Running'));

    expect(find.widgetWithText(FilledButton, "I'm in"), findsNothing);
    expect(find.text('2 of 3 interested'), findsOneWidget);
    expect(find.text('Aziz'), findsOneWidget);
    expect(find.text('Arman'), findsOneWidget);

    await tap(tester, find.byTooltip('Remove player').first);
    expect(find.text('Remove Aziz?'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Remove'));
    expect(find.text('1 of 3 interested'), findsOneWidget);
    expect(find.text('Aziz'), findsNothing);

    await tap(tester, find.text('Cancel request'));
    await tap(tester, find.widgetWithText(FilledButton, 'Cancel request'));
    expect(find.byType(GameRequestScreen), findsNothing);
    expect(find.text('Test wants to play Running'), findsNothing);
    await settleSnackbars(tester);
  });

  testWidgets('posting a Game Request opens it', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openRequestsTab(tester);
    await tap(tester, find.text('POST A REQUEST'));

    await tap(tester, find.text('Padel'));
    await tester.enterText(find.byKey(const ValueKey('request-area')), 'Chilonzor');
    await tap(tester, find.byKey(const ValueKey('post-request-submit')));

    expect(find.byType(GameRequestScreen), findsOneWidget);
    expect(find.text('Test wants to play Padel'), findsOneWidget);
    expect(find.text('Chilonzor'), findsOneWidget);
    expect(find.text('0 of 2 interested'), findsOneWidget);
  });

  testWidgets('the poster converts a padel request with a booking: the interested players are in', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final booking = await bookPadel(tester);
    await postRequest(tester, 'padel', needed: 2, interested: ['p1', 'p5']);

    await openRequestsTab(tester);
    await tap(tester, find.text('Test wants to play Padel'));
    await tap(tester, find.text('Make it a game'));
    // A bookable sport needs one of the poster's own bookings.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('convert-submit'))).onPressed, isNull);
    await tap(tester, find.byKey(ValueKey('booking-${booking.id}')));
    await tap(tester, find.byKey(const ValueKey('convert-submit')));

    expect(find.byType(GameScreen), findsOneWidget);
    // Spots default to 1 + players needed, and both interested players are in.
    expect(find.text('PLAYERS · 3/3'), findsOneWidget);
    expect(find.text('Aziz'), findsOneWidget);
    expect(find.text('Arman'), findsOneWidget);
    expect(find.text('Padel with Test'), findsOneWidget);

    // The request is gone from the list.
    containerOf(tester).invalidate(gameRequestsProvider);
    final open = await containerOf(tester).read(gameRequestsProvider.future);
    expect(open.where((r) => r.hostId == kMeId), isEmpty);
  });

  testWidgets('a padel request without a booking points to booking a court', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await postRequest(tester, 'padel');
    await openRequestsTab(tester);
    await tap(tester, find.text('Test wants to play Padel'));
    await tap(tester, find.text('Make it a game'));

    expect(find.textContaining('no upcoming confirmed booking'), findsOneWidget);
    expect(find.text('Book a court'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('convert-submit'))).onPressed, isNull);
  });

  testWidgets('a place-only request converts at a meeting point, with times defaulting to its window', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await postRequest(tester, 'running', needed: 3, interested: ['p3']);
    await openRequestsTab(tester);
    await tap(tester, find.text('Test wants to play Running'));
    await tap(tester, find.text('Make it a game'));

    // The window is 18:00–21:00; the poster can change both ends.
    expect(
      find.descendant(of: find.byKey(const ValueKey('convert-start')), matching: find.text('18:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('convert-end')), matching: find.text('21:00')),
      findsOneWidget,
    );

    // A meeting point or venue is required.
    await tap(tester, find.byKey(const ValueKey('convert-submit')));
    expect(find.text('Enter a meeting point'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('meeting-point')), 'Bunyodkor park, main gate');
    await tap(tester, find.byKey(const ValueKey('convert-submit')));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Bunyodkor park, main gate'), findsOneWidget);
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);
    expect(find.text('Timur'), findsOneWidget);
  });

  testWidgets('Find players lists everyone, then filters by name, sport and level', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openSocialTab(tester);

    expect(find.text('FIND PLAYERS'), findsOneWidget);
    // Nobody is left out unless they hid themselves.
    for (final name in ['Aziz', 'Dilnoza', 'Timur', 'Madina', 'Arman', 'Aigerim', 'Bekzod', 'Kamila']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('New player'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('player-search')), 'az');
    await tester.pumpAndSettle();
    expect(find.text('Aziz'), findsOneWidget);
    expect(find.text('Timur'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('player-search')), '');
    await tester.pumpAndSettle();

    // Football takes the level slider.
    await tap(tester, find.byKey(const ValueKey('players-sport')));
    await tap(tester, find.text('Football'));
    expect(find.byKey(const ValueKey('players-level')), findsOneWidget);
    expect(find.text('Level 1–5'), findsOneWidget);

    // Padel, rating 2.5 and up: players without a padel rating count as 1.0.
    await tap(tester, find.byKey(const ValueKey('players-sport')));
    // The Leaderboards card also lists Padel: pick the one in the sport sheet.
    await tap(tester, find.descendant(of: find.byType(BottomSheet), matching: find.text('Padel')));
    expect(find.byKey(const ValueKey('players-level')), findsNothing);
    expect(find.text('Timur'), findsOneWidget);

    final slider = find.byKey(const ValueKey('players-rating'));
    final box = tester.getRect(slider);
    // Drag the lower thumb a quarter of the way along the 1.0–7.0 track: 2.5.
    await tester.dragFrom(Offset(box.left + 24, box.center.dy), Offset((box.width - 48) * 0.25, 0));
    await tester.pumpAndSettle();

    expect(find.text('Rating 2.5–7.0'), findsOneWidget);
    expect(find.text('Aziz'), findsOneWidget);
    expect(find.text('Dilnoza'), findsOneWidget);
    expect(find.text('Bekzod'), findsOneWidget);
    expect(find.text('Timur'), findsNothing);
    expect(find.text('Madina'), findsNothing);
    expect(find.text('Aigerim'), findsNothing);
  });

  testWidgets('a player profile shows levels, reliability and games played', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openSocialTab(tester);
    await tap(tester, find.text('Bekzod'));

    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    expect(find.text('Bekzod'), findsWidgets);
    // Padel is rated: the rating, and no provisional tag after 12 rated games.
    final padel = kSamplePlayers.firstWhere((p) => p.id == 'p7').ratings['padel']!;
    expect(padel.provisional, isFalse);
    expect(find.text('Padel'), findsOneWidget);
    expect(find.text(formatRating(padel.rating)), findsOneWidget);
    expect(find.text('${padel.ratedGames} rated games'), findsOneWidget);
    expect(find.text('Provisional'), findsNothing);
    expect(find.text('Football · Level 3'), findsOneWidget);
    expect(find.text('New player'), findsOneWidget);
    expect(find.text('0 games played'), findsOneWidget);
    expect(find.text('Invite to a game'), findsOneWidget);
  });

  testWidgets('inviting from a profile invites the player to the chosen hosted game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.create(
      GameDraft(
        sportId: 'running',
        spots: 4,
        visibility: GameVisibility.inviteOnly,
        meetingPoint: 'Riverside',
        start: tomorrowAt(18),
        end: tomorrowAt(19),
      ),
    );
    // A full game and somebody else's game are not offered.
    final full = await backend.create(
      GameDraft(sportId: 'running', spots: 2, meetingPoint: 'Old town', start: tomorrowAt(10), end: tomorrowAt(11)),
    );
    await backend.joinAs('p2', full.id);
    await backend.createAs(
      'p3',
      GameDraft(sportId: 'running', spots: 4, meetingPoint: 'Elsewhere', start: tomorrowAt(8), end: tomorrowAt(9)),
    );
    await refresh(tester);

    await openSocialTab(tester);
    await tap(tester, find.text('Aziz'));
    await tap(tester, find.text('Invite to a game'));

    expect(find.text('Choose a game'), findsOneWidget);
    expect(find.text('Running with You'), findsOneWidget, reason: 'only the open game with a free spot');
    await tap(tester, find.text('Running with You'));

    expect(find.text('Aziz was invited'), findsOneWidget);
    await settleSnackbars(tester);

    // The invite is real: an invite-only game accepts Aziz only because he was invited.
    final joined = await backend.joinAs('p1', game.id);
    expect(joined.participantIds, contains('p1'));
  });

  testWidgets('with no open game of their own the host is told to create one first', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openSocialTab(tester);
    await tap(tester, find.text('Aziz'));
    await tap(tester, find.text('Invite to a game'));

    expect(find.textContaining('no open game with a free spot'), findsOneWidget);
  });

  testWidgets("a profile opens by id, whether or not the player shows up in search", (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    containerOf(tester).read(routerProvider).go('/players/p5');
    await tester.pumpAndSettle();

    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    expect(find.text('Arman'), findsWidgets);
  });

  testWidgets('a request link opens the request, not a game, and "new" opens the form', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final router = containerOf(tester).read(routerProvider);

    router.go('/games/requests/rq1');
    await tester.pumpAndSettle();
    expect(find.byType(GameRequestScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Aziz wants to play Padel'), findsWidgets);

    router.go('/games/requests/new');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-request-submit')), findsOneWidget);
  });
}
