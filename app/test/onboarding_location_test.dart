import 'dart:async';

import 'package:actra/app.dart';
import 'package:actra/data/location/city_locator.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final en = lookupAppLocalizations(const Locale('en'));

class _ThrowingLocator implements CityLocator {
  @override
  Future<String?> detectCityId() async => throw Exception('denied');
}

class _HangingLocator implements CityLocator {
  final _never = Completer<String?>();
  @override
  Future<String?> detectCityId() => _never.future;
}

Future<void> pumpToCityStep(WidgetTester tester, CityLocator locator) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await initializeDateFormatting();
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        cityLocatorProvider.overrideWithValue(locator),
      ],
      child: const ActraApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('English'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder tileIcon(String city, IconData icon) =>
    find.descendant(of: find.widgetWithText(InkWell, city), matching: find.byIcon(icon));

void main() {
  testWidgets('detected city is preselected', (tester) async {
    await pumpToCityStep(tester, const FixedCityLocator('almaty'));
    await tester.pumpAndSettle();

    expect(find.text(en.chooseCity), findsOneWidget);
    expect(find.text(en.cityDetected('Almaty')), findsOneWidget);
    expect(tileIcon('Almaty', Icons.check_circle), findsOneWidget);
    expect(tileIcon('Tashkent', Icons.check_circle), findsNothing);
    // Not advanced until tapped.
    expect(find.text(en.signInTitle), findsNothing);

    await tester.tap(find.text('Tashkent'));
    await tester.pumpAndSettle();
    expect(find.text(en.signInTitle), findsOneWidget);
  });

  for (final (name, locator) in <(String, CityLocator)>[
    ('throws', _ThrowingLocator()),
    ('hangs', _HangingLocator()),
  ]) {
    testWidgets('detection failure leaves manual choice ($name)', (tester) async {
      await pumpToCityStep(tester, locator);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(en.detectingCity), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      for (final city in ['Tashkent', 'Almaty', 'Astana']) {
        expect(find.text(city), findsOneWidget);
      }
      await tester.tap(find.text('Astana'));
      await tester.pumpAndSettle();
      expect(find.text(en.signInTitle), findsOneWidget);
    });
  }
}
