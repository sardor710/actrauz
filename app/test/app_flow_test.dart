import 'package:actra/app.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/competitive.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sunday 22 Nov 2026, 10:00 in Tashkent (UTC+5).
final sundayMorning = DateTime.utc(2026, 11, 22, 5, 0);

/// The demo player's sports in most tests: level 3 in every simple sport and
/// an established 3.50 in padel and tennis (level 3 there too), as before
/// the demo player started with no sports.
final _level3Everywhere = (
  levels: {for (final s in kSampleSports) s.id: 3},
  ratings: {
    for (final s in kSampleSports)
      if (s.competitiveRating) s.id: const SportRating(rating: 3.5, ratedGames: 12),
  },
);

/// [withSports] false starts the demo player with no sports, as a new player.
/// [backend] replaces the sample backend (a test double built on it).
Future<void> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  DateTime? utcNow,
  bool withSports = true,
  SampleBackend Function(DateTime Function() clock)? backend,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  await initializeDateFormatting();

  // A tall phone, so lists show without scrolling.
  tester.view.physicalSize = const Size(900, 3400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sharedPrefs),
        if (utcNow != null) clockProvider.overrideWithValue(() => utcNow),
        if (withSports) demoSportsProvider.overrideWithValue(_level3Everywhere),
        if (backend != null) sampleBackendProvider.overrideWith((ref) => backend(ref.watch(clockProvider))),
      ],
      child: const ActraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// `sports_prompted`: the one-time "My sports" offer has been seen already.
const signedIn = <String, Object>{'lang': 'en', 'city': 'tashkent', 'user_name': 'Test', 'sports_prompted': true};

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets a snackbar time out so no timer outlives the test.
Future<void> settleSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding: language, city, name, then the five tabs in Russian', (tester) async {
    await pumpApp(tester);

    expect(find.text('Oʻzbekcha'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('Қазақша'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tap(tester, find.text('Русский'));
    expect(find.text('Выберите город'), findsOneWidget);

    await tap(tester, find.text('Ташкент'));
    expect(find.text('Вход'), findsOneWidget);

    // An empty name is refused.
    await tap(tester, find.text('Продолжить через Telegram'));
    expect(find.text('Введите имя'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Тест');
    await tap(tester, find.text('Продолжить через Telegram'));

    for (final label in ['Главная', 'Игры', 'Площадки', 'Турниры', 'Сообщество']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Привет, Тест'), findsOneWidget);
  });

  testWidgets('onboarding in Kazakh shows the Kazakh city step', (tester) async {
    await pumpApp(tester);
    await tap(tester, find.text('Қазақша'));
    expect(find.text('Қаланы таңдаңыз'), findsOneWidget);
    expect(find.text('Қаланы профильде кез келген уақытта өзгертуге болады'), findsOneWidget);
  });

  testWidgets('the home screen renders in Uzbek with every section', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'uz'}, utcNow: sundayMorning);
    expect(find.text('Salom, Test'), findsOneWidget);
    expect(find.text('SPORT TURLARI BOʻYICHA OʻYINLAR'), findsOneWidget);
    expect(find.text('YAQIN ATROFDAGI MAYDONLAR'), findsOneWidget);
    expect(find.text('BUGUN BOʻSH KORTLAR'), findsOneWidget);
    expect(find.text('MAVJUD OʻYINLAR'), findsOneWidget);
    expect(find.text('Maydonlar'), findsOneWidget);
    // No photo fell back to the placeholder.
    expect(find.byKey(const ValueKey('photo-fallback')), findsNothing);
  });

  testWidgets('book two adjacent slots, see the booking, cancel it', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Venues'));
    await tap(tester, find.text('Lochin Padel Club'));
    await tap(tester, find.widgetWithText(FilledButton, 'Book').first);

    // Sunday is priced by the weekend rule: 300 000 per slot.
    await tap(tester, find.text('11:30'));
    await tap(tester, find.text('13:00'));
    expect(find.textContaining('2 slots'), findsOneWidget);
    expect(find.textContaining('11:30–14:30'), findsOneWidget);
    expect(find.textContaining('600 000 UZS'), findsOneWidget);

    await tap(tester, find.text('Continue'));
    expect(find.text('Booking summary'), findsOneWidget);
    expect(find.text('600 000 UZS'), findsOneWidget);
    expect(find.text('Pay at venue'), findsOneWidget);

    await tap(tester, find.text('Confirm booking'));
    expect(find.text('Booking confirmed'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'My bookings'));

    expect(find.text('Lochin Padel Club'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.textContaining('11:30–14:30'), findsOneWidget);

    // 10:00 now, 11:30 start: inside the 6-hour window, so it is a late cancellation.
    await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel booking'));
    expect(find.textContaining('late cancellation'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Cancel booking'));

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Late cancellation'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('leaving the summary releases the hold', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Venues'));
    await tap(tester, find.text('Lochin Padel Club'));
    await tap(tester, find.widgetWithText(FilledButton, 'Book').first);
    await tap(tester, find.text('11:30'));
    await tap(tester, find.text('Continue'));
    expect(find.text('Booking summary'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // Back on the slot picker with nothing selected and the slot free again.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
    await tap(tester, find.text('11:30'));
    expect(find.textContaining('1 slot'), findsOneWidget);
  });

  testWidgets('a court closed on the chosen day says so', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Venues'));
    await tap(tester, find.text('Semurg Tennis Centre'));
    // Third court: basketball, closed on Mondays.
    await tap(tester, find.widgetWithText(FilledButton, 'Book').at(2));
    expect(find.text('The court is closed on this day'), findsNothing);

    await tap(tester, find.text('23'));
    expect(find.text('The court is closed on this day'), findsOneWidget);
  });

  testWidgets('join and leave a game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Games'));
    // Padel tomorrow 19:00 with 2 of 4 players.
    expect(find.text('2/4 going'), findsOneWidget);
    await tap(tester, find.text('Padel with Aziz'));
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);

    await tap(tester, find.widgetWithText(FilledButton, 'Join'));
    expect(find.text('PLAYERS · 3/4'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Leave game'));
    expect(find.text('PLAYERS · 2/4'), findsOneWidget);
  });

  testWidgets('a sport on Home opens Games filtered to it', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Football'));
    expect(find.text('Football with Timur'), findsOneWidget);
    expect(find.text('Padel with Aziz'), findsNothing);
  });

  testWidgets('a day with no games shows the empty state, All brings them back', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Games'));
    expect(find.text('Padel with Aziz'), findsOneWidget);

    // Sample games start tomorrow, so today has none.
    await tap(tester, find.text('Today'));
    expect(find.text('No open games yet'), findsOneWidget);
    expect(find.text('Padel with Aziz'), findsNothing);

    await tap(tester, find.text('All'));
    expect(find.text('Padel with Aziz'), findsOneWidget);
  });

  testWidgets('favourite a venue, then filter by favourites', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Venues'));
    expect(find.text('VENUES (3)'), findsOneWidget);

    // The first heart belongs to the filter chip, the second to the first venue.
    await tap(tester, find.byIcon(Icons.favorite_border_rounded).at(1));
    await tap(tester, find.text('Favourites'));

    expect(find.text('VENUES (1)'), findsOneWidget);
    expect(find.text('Lochin Padel Club'), findsOneWidget);
    expect(find.text('Bunyod Football Park'), findsNothing);
  });

  testWidgets('switching city switches venues and currency', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'city': 'almaty'}, utcNow: sundayMorning);

    await tap(tester, find.text('Venues'));
    expect(find.text('Alatau Padel & Tennis'), findsOneWidget);
    expect(find.text('Lochin Padel Club'), findsNothing);
    expect(find.textContaining('₸'), findsWidgets);
    expect(find.textContaining('UZS'), findsNothing);
  });

  testWidgets('tournaments show the city\'s events and mark the full one', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Tournaments'));
    expect(find.text('Tashkent Padel Cup'), findsOneWidget);
    expect(find.text('Amateur 5-a-side League'), findsOneWidget);
    expect(find.text('Almaty Open Tennis'), findsNothing);
    expect(find.text('Registration open'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
  });

  testWidgets('social shows teams of the selected city and players', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.text('Social'));
    expect(find.text('Yunusobod Padel'), findsOneWidget);
    expect(find.text('Alatau Smash'), findsNothing);
    // Chilonzor FC and Yunusobod Padel: a captain and three members each.
    expect(find.text('4 members'), findsNWidgets(2));
    expect(find.text('Aziz'), findsOneWidget);
  });

  testWidgets('profile opens from the avatar and switches language and city', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);

    await tap(tester, find.byType(InitialAvatar).first);
    expect(find.text('MY SPORTS'), findsOneWidget);
    expect(find.text('Football · Level 3'), findsOneWidget);
    // Padel and tennis show the 3.50 rating set above, not a level.
    expect(find.text('3.50'), findsNWidgets(2));
    expect(find.text('Padel · Level 3'), findsNothing);

    await tap(tester, find.text('Language'));
    for (final name in ['Oʻzbekcha', 'Русский', 'Қазақша', 'English']) {
      expect(find.text(name), findsWidgets);
    }
    await tap(tester, find.text('Русский'));
    expect(find.text('МОИ ВИДЫ СПОРТА'), findsOneWidget);

    await tap(tester, find.text('Город'));
    await tap(tester, find.text('Алматы'));
    expect(find.text('Алматы'), findsWidgets);
    expect(find.text('Ташкент'), findsNothing);
  });
}
