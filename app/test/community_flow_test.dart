import 'package:actra/app.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ActraApp)));

/// The demo player hosts a running game and Aziz (p1) joins it, so the inbox
/// gets a `game_joined`. Returns the game id.
Future<String> aziJoinsMyGame(WidgetTester tester) async {
  final c = containerOf(tester);
  final backend = c.read(sampleBackendProvider);
  final game = await backend.create(
    GameDraft(
      sportId: 'running',
      spots: 4,
      meetingPoint: 'Bunyodkor park, main gate',
      meetingLat: 41.3,
      meetingLng: 69.2,
      start: DateTime.utc(2026, 11, 23, 7),
      end: DateTime.utc(2026, 11, 23, 8),
    ),
  );
  await backend.joinAs('p1', game.id);
  c.invalidate(unreadCountProvider);
  c.invalidate(inboxProvider);
  await tester.pumpAndSettle();
  return game.id;
}

Finder bell() => find.byKey(const ValueKey('inbox-bell'));

void main() {
  testWidgets('the home bell shows the unread count', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    expect(find.descendant(of: bell(), matching: find.text('1')), findsOneWidget);

    await aziJoinsMyGame(tester);
    expect(find.descendant(of: bell(), matching: find.text('2')), findsOneWidget);
  });

  testWidgets('the inbox lists newest first, in the current language', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await aziJoinsMyGame(tester);
    await tap(tester, bell());

    expect(find.text('Notifications'), findsOneWidget);
    final joined = find.text('Aziz joined your game');
    final booked = find.text('Aziz booked Court 1');
    final confirmed = find.text('Your booking at Lochin Padel Club is confirmed');
    expect(joined, findsOneWidget);
    expect(booked, findsOneWidget);
    expect(confirmed, findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(joined), lessThan(top(booked)));
    expect(top(booked), lessThan(top(confirmed)));
  });

  testWidgets('the inbox is rendered in Russian', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'ru'}, utcNow: sundayMorning);
    await tap(tester, bell());

    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.text('Новая бронь: Корт 1 (Aziz)'), findsOneWidget);
    expect(find.text('Бронь подтверждена: Lochin Padel Club'), findsOneWidget);
  });

  testWidgets('tapping a game_joined opens the game and marks it read', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final gameId = await aziJoinsMyGame(tester);
    await tap(tester, bell());

    await tap(tester, find.text('Aziz joined your game'));
    expect(find.text('Notifications'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);

    final unread = await containerOf(tester).read(unreadCountProvider.future);
    expect(unread, 1, reason: 'only the venue booking is still unread');
    final inbox = await containerOf(tester).read(inboxProvider.future);
    expect(inbox.firstWhere((n) => n.payload['game_id'] == gameId).read, isTrue);
  });

  testWidgets('Mark all read clears the badge', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await aziJoinsMyGame(tester);
    expect(find.descendant(of: bell(), matching: find.text('2')), findsOneWidget);

    await tap(tester, bell());
    await tap(tester, find.text('Mark all read'));
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read')).onPressed, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.descendant(of: bell(), matching: find.byType(Badge)), findsNothing);
    expect(await containerOf(tester).read(unreadCountProvider.future), 0);
  });

  testWidgets('a notification that arrives after Mark all read shows as unread', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final gameId = await aziJoinsMyGame(tester);
    await tap(tester, bell());
    await tap(tester, find.text('Mark all read'));
    expect(find.byKey(const ValueKey('unread-dot')), findsNothing);

    // Another sample player (p2) joins while the inbox is open.
    final c = containerOf(tester);
    await c.read(sampleBackendProvider).joinAs('p2', gameId);
    c.invalidate(inboxProvider);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read')).onPressed, isNotNull);
  });

  testWidgets('muting Games and saving persists the setting', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await tap(tester, bell());
    await tap(tester, find.byTooltip('Notification settings'));
    expect(find.text('Notifications and privacy'), findsOneWidget);

    final games = find.widgetWithText(SwitchListTile, 'Games');
    expect(tester.widget<SwitchListTile>(games).value, isTrue);
    await tap(tester, games);
    expect(tester.widget<SwitchListTile>(games).value, isFalse);
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));

    final saved = await containerOf(tester).read(communitySettingsProvider.future);
    expect(saved.mutedCategories, {'games'});
    expect(saved.hiddenFromSearch, isFalse);
  });

  testWidgets('the hidden-from-search switch saves', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await tap(tester, find.byType(InitialAvatar).first);
    await tap(tester, find.text('Notifications and privacy'));

    final hidden = find.widgetWithText(SwitchListTile, 'Hide me from player search');
    await tap(tester, hidden);
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));

    final saved = await containerOf(tester).read(communitySettingsProvider.future);
    expect(saved.hiddenFromSearch, isTrue);
    expect(saved.mutedCategories, isEmpty);
  });

  testWidgets('the profile shows the reliability badge', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await tap(tester, find.byType(InitialAvatar).first);
    expect(find.text('Reliable'), findsOneWidget);
  });
}
