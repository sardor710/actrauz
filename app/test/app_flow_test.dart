import 'package:actra/app.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sunday 22 Nov 2026, 10:00 in Tashkent (UTC+5).
final sundayMorning = DateTime.utc(2026, 11, 22, 5, 0);

Future<void> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}, DateTime? utcNow}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  await initializeDateFormatting();

  // A tall phone, so lists show without scrolling.
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sharedPrefs),
        if (utcNow != null) clockProvider.overrideWithValue(() => utcNow),
      ],
      child: const ActraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

const signedIn = <String, Object>{'lang': 'en', 'city': 'tashkent', 'user_name': 'Test'};

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
  testWidgets('onboarding: language, city, name, then the main tabs in Russian', (tester) async {
    await pumpApp(tester);

    expect(find.text('Oʻzbekcha'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
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

    for (final label in ['Главная', 'Площадки', 'Игры', 'Профиль']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('Привет, Тест'), findsOneWidget);
  });

  testWidgets('the same home screen renders in Uzbek', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'uz'}, utcNow: sundayMorning);
    expect(find.text('Salom, Test'), findsOneWidget);
    expect(find.text('Mavjud oʻyinlar'), findsOneWidget);
    expect(find.text('Maydonlar'), findsWidgets);
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
    expect(find.text('Continue'), findsNothing);
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
    await tap(tester, find.text('2 spots left'));
    expect(find.text('Players · 2/4'), findsOneWidget);

    await tap(tester, find.widgetWithText(FilledButton, 'Join'));
    expect(find.text('Players · 3/4'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Leave game'));
    expect(find.text('Players · 2/4'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('switching city switches venues and currency', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'city': 'almaty'}, utcNow: sundayMorning);

    await tap(tester, find.text('Venues'));
    expect(find.text('Alatau Padel & Tennis'), findsOneWidget);
    expect(find.text('Lochin Padel Club'), findsNothing);
    expect(find.textContaining('₸'), findsWidgets);
    expect(find.textContaining('UZS'), findsNothing);
  });
}
