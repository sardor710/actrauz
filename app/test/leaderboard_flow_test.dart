import 'package:actra/core/theme.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/domain/competitive.dart';
import 'package:actra/features/social/leaderboard_screen.dart';
import 'package:actra/features/social/player_profile_screen.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf;

Finder _row(String id) => find.byKey(ValueKey('leaderboard-row-$id'));

Finder _in(String id, Finder what) => find.descendant(of: _row(id), matching: what);

void main() {
  testWidgets('leaderboard lists players and opens a profile', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await tap(tester, find.text('Social'));
    expect(find.text('LEADERBOARDS'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('leaderboard-link-padel')));

    expect(find.byType(LeaderboardScreen), findsOneWidget);
    expect(find.text('Leaderboard · Tashkent'), findsOneWidget);
    // Bekzod 4.50; then the demo player and the 3.50 players with 12 games by id; then Dilnoza.
    final ids = ['p7', kMeId, 'p1', 'p5', 'p8', 'p2'];
    final tops = [for (final id in ids) tester.getTopLeft(_row(id)).dy];
    expect(tops, [...tops]..sort(), reason: 'rows are in rank order');
    expect(_in('p7', find.text('1')), findsOneWidget);
    expect(_in('p7', find.text('4.50')), findsOneWidget);
    expect(_in('p7', find.text('12 games')), findsOneWidget);
    expect(_in('p2', find.text('6')), findsOneWidget);
    expect(_in('p2', find.text('4 games')), findsOneWidget);
    expect(_in('p2', find.text('Provisional')), findsOneWidget);
    expect(_in(kMeId, find.text('Test')), findsOneWidget);
    expect(find.byKey(const ValueKey('leaderboard-me')), findsNothing, reason: 'my row is within the top 100');

    // The sport switch shows the other rated sport's board.
    await tap(tester, find.byKey(const ValueKey('leaderboard-sport-tennis')));
    expect(_row('p4'), findsOneWidget);
    expect(_row('p7'), findsNothing);

    await tap(tester, find.byKey(const ValueKey('leaderboard-sport-padel')));
    await tap(tester, _row('p7'));
    expect(find.byType(PlayerProfileScreen), findsOneWidget);
    expect(find.text('Bekzod'), findsWidgets);
  });

  testWidgets('the rating on my profile opens the leaderboard', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    containerOf(tester).read(routerProvider).go('/profile');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('my-rating-tennis')));
    expect(find.byType(LeaderboardScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('leaderboard-sport-tennis')), findsOneWidget);
    expect(_row('p4'), findsOneWidget);
  });

  testWidgets('a sport nobody has a result in shows the empty state', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    containerOf(tester).read(routerProvider).go('/leaderboard/football');
    await tester.pumpAndSettle();
    expect(find.text('No confirmed results in Tashkent yet.'), findsOneWidget);
  });
  testWidgets('my row is pinned below the list when I rank lower than 100', (tester) async {
    await _pumpBoard(tester, Leaderboard(rows: _top(100), me: _me(140)));
    final pinned = find.byKey(const ValueKey('leaderboard-me'));
    expect(pinned, findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('140')), findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('3 games')), findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('2.00')), findsOneWidget);
  });

  testWidgets('a player hidden from search still sees their own row, though not in the list', (tester) async {
    await _pumpBoard(tester, Leaderboard(rows: _top(10), me: _me(5)));
    final pinned = find.byKey(const ValueKey('leaderboard-me'));
    expect(pinned, findsOneWidget);
    expect(find.descendant(of: pinned, matching: find.text('5')), findsOneWidget);
  });

  testWidgets('a hidden player on an otherwise empty board sees their row, not the empty state', (tester) async {
    await _pumpBoard(tester, Leaderboard(rows: const [], me: _me(1)));
    expect(find.byKey(const ValueKey('leaderboard-me')), findsOneWidget);
    expect(find.text('No confirmed results in Tashkent yet.'), findsNothing);
  });

  testWidgets('my row inside the list is not pinned a second time', (tester) async {
    final rows = _top(10);
    await _pumpBoard(tester, Leaderboard(rows: [...rows.take(4), _me(5), ...rows.skip(5)], me: _me(5)));
    expect(find.byKey(const ValueKey('leaderboard-me')), findsNothing);
    expect(_row(kMeId), findsOneWidget);
  });

  for (final lang in ['ru', 'kk', 'uz']) {
    testWidgets("a provisional player's row keeps the whole name on a small phone in $lang", (tester) async {
      const name = 'Dilnoza';
      await _pumpBoard(
        tester,
        const Leaderboard(
          rows: [
            LeaderboardRow(
              position: 100,
              id: 'u1',
              name: name,
              rating: SportRating(rating: 3.25, ratedGames: 4),
              isMe: false,
            ),
          ],
        ),
        lang: lang,
        width: 360,
      );
      final text = find.descendant(of: _row('u1'), matching: find.text(name));
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'the name is not cut short');
    });
  }
}

List<LeaderboardRow> _top(int count) => [
  for (var i = 1; i <= count; i++)
    LeaderboardRow(
      position: i,
      id: 'u$i',
      name: 'Player $i',
      rating: const SportRating(rating: 4, ratedGames: 12),
      isMe: false,
    ),
];

LeaderboardRow _me(int position) => LeaderboardRow(
  position: position,
  id: kMeId,
  name: 'Test',
  rating: const SportRating(rating: 2, ratedGames: 3),
  isMe: true,
);

/// The leaderboard screen on its own, showing [board].
Future<void> _pumpBoard(WidgetTester tester, Leaderboard board, {String lang = 'en', double width = 900}) async {
  SharedPreferences.setMockInitialValues(signedIn);
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = Size(width, 3400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        leaderboardProvider.overrideWith((ref, key) async => board),
      ],
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildTheme(),
        home: const LeaderboardScreen(sportId: 'padel'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
