import 'package:actra/domain/competitive.dart';
import 'package:actra/features/common/rating_pill.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/features/profile/my_sports_screen.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show bookPadel, containerOf;

/// Signed in, but the one-time "Pick your sports" offer has not been seen.
final _neverPrompted = {...signedIn}..remove('sports_prompted');

/// The answers of the padel questionnaire used below: the 2nd, 3rd, 2nd, 1st
/// and 3rd option.
const _answers = [1, 2, 1, 0, 2];
const _padelAnswerTexts = [
  '6–24 months',
  'Weekly',
  'Friendly matches with score',
  'I avoid it',
  'I hold the net and volley with direction',
];

Future<void> _openMySports(WidgetTester tester) async {
  containerOf(tester).read(routerProvider).push('/sports');
  await tester.pumpAndSettle();
  expect(find.byType(MySportsScreen), findsOneWidget);
}

Future<void> _openProfile(WidgetTester tester) => tap(tester, find.byType(InitialAvatar).first);

Future<void> _answerPadel(WidgetTester tester) async {
  expect(find.text('How long have you played?'), findsOneWidget);
  for (final text in _padelAnswerTexts) {
    await tap(tester, find.text(text));
  }
}

Finder _switchOf(String sportId) => find.byKey(ValueKey('sport-switch-$sportId'));

void main() {
  testWidgets('new player is asked to pick sports', (tester) async {
    await pumpApp(tester, prefs: _neverPrompted, utcNow: sundayMorning, withSports: false);

    expect(find.text('Pick your sports'), findsOneWidget);
    await tap(tester, find.text('Choose sports'));
    expect(find.byType(MySportsScreen), findsOneWidget);
    expect(find.text('Pick your sports'), findsNothing);

    // Seen once: the next launch does not ask again.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sports_prompted'), isTrue);
    final kept = {for (final key in prefs.getKeys()) key: prefs.get(key)!};

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, prefs: kept, utcNow: sundayMorning, withSports: false);
    expect(find.text('Hello, Test'), findsOneWidget);
    expect(find.text('Pick your sports'), findsNothing);
  });

  testWidgets('a player who has sports is not asked', (tester) async {
    await pumpApp(tester, prefs: _neverPrompted, utcNow: sundayMorning);
    expect(find.text('Pick your sports'), findsNothing);
  });

  testWidgets('padel questionnaire sets a rating', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await _openProfile(tester);

    // No sports yet: the card offers to pick them.
    expect(find.text('MY SPORTS'), findsOneWidget);
    expect(find.text('You have not picked any sports yet'), findsOneWidget);
    await tap(tester, find.text('Choose sports'));
    expect(find.byType(MySportsScreen), findsOneWidget);

    await tap(tester, _switchOf('padel'));
    await _answerPadel(tester);
    final expected = questionnaireRating(_answers).toStringAsFixed(2);
    expect(expected, '2.70');
    expect(find.text('Your starting rating: $expected'), findsOneWidget);
    await tap(tester, find.text('Done'));

    // The sport is on, with its rating, and it can be retaken until the first rated game.
    expect(tester.widget<Switch>(_switchOf('padel')).value, isTrue);
    expect(find.text('Retake'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Padel'), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    expect(find.text('Provisional'), findsOneWidget);
    expect(find.text('You have not picked any sports yet'), findsNothing);
  });

  testWidgets('football takes a level', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await _openMySports(tester);

    await tap(tester, _switchOf('football'));
    expect(find.text('Level 5'), findsOneWidget);
    await tap(tester, find.text('Level 4'));
    expect(tester.widget<Switch>(_switchOf('football')).value, isTrue);
    expect(find.text('Level 4'), findsOneWidget);

    // Tapping the row changes the level.
    await tap(tester, find.text('Level 4'));
    await tap(tester, find.text('Level 2'));
    expect(find.text('Level 2'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openProfile(tester);
    expect(find.text('Football · Level 2'), findsOneWidget);
  });

  testWidgets('closing the level picker leaves the sport off', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await _openMySports(tester);

    await tap(tester, _switchOf('football'));
    Navigator.of(tester.element(find.text('Level 5'))).pop();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_switchOf('football')).value, isFalse);
  });

  testWidgets('turning a sport off removes it', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await _openMySports(tester);
    await tap(tester, _switchOf('football'));
    await tap(tester, find.text('Level 3'));
    expect(tester.widget<Switch>(_switchOf('football')).value, isTrue);

    await tap(tester, _switchOf('football'));
    expect(tester.widget<Switch>(_switchOf('football')).value, isFalse);
    expect(await containerOf(tester).read(socialRepositoryProvider).mySports(), isEmpty);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openProfile(tester);
    expect(find.text('You have not picked any sports yet'), findsOneWidget);
  });

  testWidgets('joining padel without a rating opens the questionnaire', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await tap(tester, find.text('Games'));
    await tap(tester, find.text('Padel with Aziz'));
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);

    // Closing the questionnaire does nothing.
    await tap(tester, find.byKey(const ValueKey('game-join')));
    expect(find.text('How long have you played?'), findsOneWidget);
    Navigator.of(tester.element(find.text('How long have you played?'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);

    // Answering it gives a rating inside the game's range, so the player joins.
    final game = await containerOf(tester).read(gameRepositoryProvider).game('g1');
    final rating = questionnaireRating(_answers);
    expect(rating >= game.minRating! && rating <= game.maxRating!, isTrue);
    await tap(tester, find.byKey(const ValueKey('game-join')));
    await _answerPadel(tester);
    await tap(tester, find.text('Done'));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('PLAYERS · 3/4'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('padel game shows a rating range', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await containerOf(tester).read(socialRepositoryProvider).setSport('padel', answers: _answers);
    containerOf(tester).invalidate(mySportsProvider);
    final booking = await bookPadel(tester);

    await tap(tester, find.text('Games'));
    await tap(tester, find.text('CREATE A GAME'));
    await tap(tester, find.text('Padel'));
    await tap(tester, find.byKey(ValueKey('booking-${booking.id}')));

    // A rated sport takes a rating range in half steps.
    expect(find.text('RATING RANGE'), findsOneWidget);
    expect(find.text(formatRatingRange(1, 7)), findsOneWidget);
    tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(const RangeValues(3, 4.5));
    await tester.pumpAndSettle();
    expect(find.text('3.0–4.5'), findsOneWidget);
    await tap(tester, find.byKey(const ValueKey('create-game-submit')));

    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('3.0–4.5'), findsOneWidget);
    expect(find.textContaining('Level'), findsNothing);

    await tap(tester, find.text('Games'));
    expect(find.text('Padel with You'), findsOneWidget);
    expect(find.text('3.0–4.5'), findsOneWidget);
  });

  for (final lang in ['ru', 'kk', 'uz']) {
    testWidgets('the offer, My sports and both questionnaires fit in $lang', (tester) async {
      await pumpApp(tester, prefs: {..._neverPrompted, 'lang': lang}, utcNow: sundayMorning, withSports: false);
      // A phone-sized screen: long answers wrap instead of overflowing.
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget, reason: 'the offer');
      await tap(tester, find.byType(FilledButton));
      expect(find.byType(MySportsScreen), findsOneWidget);

      for (final sportId in ['padel', 'tennis']) {
        await tap(tester, _switchOf(sportId));
        for (var step = 0; step < 5; step++) {
          await tap(tester, find.byKey(ValueKey('answer-$step-3')));
        }
        expect(find.byType(RatingPill), findsWidgets);
        await tap(tester, find.byType(FilledButton));
      }
      await tap(tester, _switchOf('football'));
      await tap(tester, find.byType(ListTile).at(2));
      expect(find.byType(BottomSheet), findsNothing);

      // pageBack() looks for the English "Back" tooltip.
      await tap(tester, find.byType(BackButton));
      await _openProfile(tester);
      expect(find.byType(RatingPill), findsNWidgets(2));
    });
  }

  testWidgets('admin cannot switch rating mode', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    containerOf(tester).read(routerProvider).go('/admin/sports');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const ValueKey('admin-sport-padel')));

    final control = tester.widget<SegmentedButton<bool>>(
      find.ancestor(of: find.text('Rating 1.0–7.0'), matching: find.byType(SegmentedButton<bool>)),
    );
    expect(control.onSelectionChanged, isNull);
    expect(control.selected, {true});
    expect(find.text('Set by Actra. Ask engineering to change it.'), findsOneWidget);
  });
}
