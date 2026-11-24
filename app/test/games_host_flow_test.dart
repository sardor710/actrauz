import 'package:actra/app.dart';
import 'package:actra/core/money.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/features/common/formatters.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/l10n/gen/app_localizations_en.dart';
import 'package:actra/l10n/gen/app_localizations_ru.dart';
import 'package:actra/l10n/gen/app_localizations_uz.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(ActraApp)));

/// Monday 23 Nov 2026, 11:30-13:00 at Lochin Padel Club court 1: a confirmed
/// booking of the demo player, who is "now" on Sunday 10:00.
Future<Booking> bookPadel(WidgetTester tester) async {
  final c = containerOf(tester);
  final backend = c.read(sampleBackendProvider);
  final start = DateTime.utc(2026, 11, 23, 11, 30);
  final held = await backend.hold('v1', 'v1c1', [SlotTime(start, start.add(const Duration(minutes: 90)))]);
  final booking = await backend.confirm(held.id, players: 4);
  c.invalidate(myBookingsProvider);
  await tester.pumpAndSettle();
  return booking;
}

DateTime tomorrowAt(int hour) => DateTime.utc(2026, 11, 23, hour);

GameDraft running({
  int spots = 4,
  int minLevel = 1,
  int maxLevel = 5,
  GameVisibility visibility = GameVisibility.public,
}) => GameDraft(
  sportId: 'running',
  spots: spots,
  minLevel: minLevel,
  maxLevel: maxLevel,
  visibility: visibility,
  meetingPoint: 'Bunyodkor park, main gate',
  start: tomorrowAt(18),
  end: tomorrowAt(19),
);

Future<void> refresh(WidgetTester tester) async {
  final c = containerOf(tester);
  c.invalidate(gamesProvider);
  c.invalidate(gameProvider);
  c.invalidate(inboxProvider);
  await tester.pumpAndSettle();
}

Future<void> openGamesTab(WidgetTester tester) => tap(tester, find.text('Games'));

Finder submit() => find.byKey(const ValueKey('create-game-submit'));

void main() {
  testWidgets('create a padel game from my booking: it opens with the per-player share', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final booking = await bookPadel(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('CREATE A GAME'));
    await tap(tester, find.text('Padel'));
    // The sport has a booking to pick, and nothing is created until one is chosen.
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    await tap(tester, find.byKey(ValueKey('booking-${booking.id}')));

    final share = (booking.totalPrice + 3) ~/ 4;
    expect(find.textContaining('≈ ${groupThousands(share)}'), findsOneWidget);
    await tap(tester, submit());

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('PLAYERS · 1/4'), findsOneWidget);
    expect(find.textContaining('per player'), findsOneWidget);
    expect(find.text('Padel with Test'), findsOneWidget);
  });

  testWidgets('a bookable sport without a booking points to booking a court', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openGamesTab(tester);
    await tap(tester, find.text('CREATE A GAME'));
    await tap(tester, find.text('Football'));

    expect(find.textContaining('no upcoming confirmed booking'), findsOneWidget);
    expect(find.text('Book a court'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
  });

  testWidgets('create a running game with a meeting point', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openGamesTab(tester);
    await tap(tester, find.text('CREATE A GAME'));
    await tap(tester, find.text('Running'));

    // The meeting point is required.
    await tap(tester, submit());
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Enter a meeting point'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('meeting-point')), 'Bunyodkor park, main gate');
    await tester.enterText(find.byKey(const ValueKey('distance-km')), '5');
    await tap(tester, submit());

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Bunyodkor park, main gate'), findsOneWidget);
    expect(find.text('5 km'), findsOneWidget);
    expect(find.text('Running with Test'), findsOneWidget);
    expect(find.textContaining('PLAYERS · 1/'), findsOneWidget);
  });

  testWidgets('an invite-only game shows its lock on the list', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openGamesTab(tester);
    await tap(tester, find.text('CREATE A GAME'));
    await tap(tester, find.text('Running'));
    await tester.enterText(find.byKey(const ValueKey('meeting-point')), 'Riverside');
    await tap(tester, find.text('Invite only'));
    await tap(tester, submit());
    expect(find.text('Invite only'), findsOneWidget);

    await tap(tester, find.byIcon(Icons.arrow_back_rounded));
    expect(find.text('Riverside'), findsOneWidget);
    expect(find.text('Invite only'), findsOneWidget);
  });

  testWidgets('a player outside the level range asks to join and can withdraw', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    // The demo player is level 3 in every sport.
    await containerOf(tester).read(sampleBackendProvider).createAs('p1', running(minLevel: 4));
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with Aziz'));
    expect(find.widgetWithText(FilledButton, 'Join'), findsNothing);

    await tap(tester, find.text('Ask to join'));
    expect(find.widgetWithText(FilledButton, 'Requested'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Requested')).onPressed, isNull);

    await tap(tester, find.text('Withdraw request'));
    expect(find.text('Ask to join'), findsOneWidget);
    expect(find.text('Requested'), findsNothing);
  });

  testWidgets('the host sees a request with level and reliability, and approving adds the player', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.create(running());
    await backend.requestToJoinAs('p1', game.id);
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with You'));

    expect(find.text('REQUESTS · 1'), findsOneWidget);
    expect(find.text('Aziz'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('New player'), findsWidgets);
    expect(find.text('PLAYERS · 1/4'), findsOneWidget);

    await tap(tester, find.text('Approve'));
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);
    expect(find.text('REQUESTS · 1'), findsNothing);
    expect(find.text('Aziz'), findsOneWidget);
  });

  testWidgets('declining a request removes it and adds nobody', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.create(running());
    await backend.requestToJoinAs('p1', game.id);
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with You'));
    await tap(tester, find.text('Decline'));

    expect(find.textContaining('REQUESTS'), findsNothing);
    expect(find.text('PLAYERS · 1/4'), findsOneWidget);
  });

  testWidgets('an invited player accepts and joins; declining hides the game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.createAs('p1', running(visibility: GameVisibility.inviteOnly, minLevel: 5));
    await backend.inviteAs('p1', game.id, kMeId);
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with Aziz'));
    expect(find.text('You are invited to this game'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Accept'));
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Leave game'), findsOneWidget);
  });

  testWidgets('an invited player can decline', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.createAs('p1', running(visibility: GameVisibility.inviteOnly));
    await backend.inviteAs('p1', game.id, kMeId);
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with Aziz'));
    await tap(tester, find.widgetWithText(OutlinedButton, 'Decline'));

    // Back on the list, no longer invited.
    expect(find.byType(GameScreen), findsNothing);
    final seen = await containerOf(tester).read(sampleBackendProvider).game(game.id);
    expect(seen.myStatus, isNull);
  });

  testWidgets('editing spots below the players in the game shows an error; a valid edit saves', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.create(running());
    await backend.joinAs('p1', game.id);
    await backend.joinAs('p5', game.id);
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with You'));
    await tap(tester, find.text('Edit game'));

    // 4 spots, 3 players: two steps down is 2.
    await tap(tester, find.byTooltip('Fewer spots'));
    await tap(tester, find.byTooltip('Fewer spots'));
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Spots cannot be fewer than the players already in the game'), findsOneWidget);
    expect(find.text('PLAYERS · 3/4'), findsOneWidget);

    await tap(tester, find.byTooltip('More spots'));
    await tap(tester, find.byTooltip('More spots'));
    await tap(tester, find.byTooltip('More spots'));
    await tester.enterText(find.byKey(const ValueKey('edit-note')), 'Bring water');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));

    expect(find.text('PLAYERS · 3/5'), findsOneWidget);
    expect(find.text('Bring water'), findsOneWidget);
  });

  testWidgets('the host removes a player after confirming', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final game = await backend.create(running());
    await backend.joinAs('p1', game.id);
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Running with You'));
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);

    await tap(tester, find.byTooltip('Remove player'));
    expect(find.text('Remove Aziz?'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Remove'));
    expect(find.text('PLAYERS · 1/4'), findsOneWidget);
  });

  testWidgets('cancelling a game but keeping the booking leaves it in My bookings', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final booking = await bookPadel(tester);
    final game = await containerOf(
      tester,
    ).read(sampleBackendProvider).create(GameDraft(sportId: 'padel', spots: 4, bookingId: booking.id));
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Padel with You'));
    await tap(tester, find.text('Cancel game'));

    expect(find.text('Also cancel my court booking'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    await tap(tester, find.widgetWithText(FilledButton, 'Cancel game'));

    // Back on the list: the game is gone.
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Padel with You'), findsNothing);
    expect(await containerOf(tester).read(sampleBackendProvider).game(game.id).then((g) => g.cancelled), isTrue);
    await settleSnackbars(tester);

    containerOf(tester).read(routerProvider).go('/bookings');
    await tester.pumpAndSettle();
    expect(find.text('Lochin Padel Club'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('cancelling a game together with its booking cancels the booking', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final booking = await bookPadel(tester);
    await containerOf(
      tester,
    ).read(sampleBackendProvider).create(GameDraft(sportId: 'padel', spots: 4, bookingId: booking.id));
    await refresh(tester);

    await openGamesTab(tester);
    await tap(tester, find.text('Padel with You'));
    await tap(tester, find.text('Cancel game'));
    await tap(tester, find.byType(CheckboxListTile));
    await tap(tester, find.widgetWithText(FilledButton, 'Cancel game'));
    await settleSnackbars(tester);

    containerOf(tester).read(routerProvider).go('/bookings');
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('My bookings offers to create a game from a booking', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await bookPadel(tester);
    containerOf(tester).read(routerProvider).go('/bookings');
    await tester.pumpAndSettle();

    await tap(tester, find.text('Create a game from this booking'));
    // The booking and its sport are already chosen.
    expect(tester.widget<FilledButton>(submit()).onPressed, isNotNull);
    await tap(tester, submit());

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Padel with Test'), findsOneWidget);
  });

  testWidgets('a blocked player is told why they cannot create a game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    backend.recordReliability(kMeId, ReliabilityKind.noShow, 'b1');
    backend.recordReliability(kMeId, ReliabilityKind.noShow, 'b2');
    backend.recordReliability(kMeId, ReliabilityKind.noShow, 'b3');

    await openGamesTab(tester);
    await tap(tester, find.text('CREATE A GAME'));
    await tap(tester, find.text('Running'));
    await tester.enterText(find.byKey(const ValueKey('meeting-point')), 'Riverside');
    await tap(tester, submit());

    expect(find.byType(GameScreen), findsNothing);
    expect(find.textContaining('You cannot book, join or post'), findsOneWidget);
  });

  test('every join error has a translated message in every language', () {
    for (final l in [AppLocalizationsEn(), AppLocalizationsRu(), AppLocalizationsUz()]) {
      for (final error in JoinError.values) {
        final text = joinErrorText(l, JoinException(error));
        expect(text.trim(), isNotEmpty, reason: '${error.name} in ${l.localeName}');
        if (error != JoinError.unavailable) {
          expect(text, isNot(l.errGeneric), reason: '${error.name} falls back to the generic text in ${l.localeName}');
        }
      }
    }
  });
}
