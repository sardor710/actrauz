import 'package:actra/features/common/widgets.dart';
import 'package:actra/features/owner/owner_dashboard_screen.dart';
import 'package:actra/features/owner/owner_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'owner_flow_test.dart';

Future<void> openSettings(WidgetTester tester) async {
  await openCalendar(tester);
  await tap(tester, find.byTooltip('Hours and prices'));
  expect(find.byType(OwnerSettingsScreen), findsOneWidget);
}

/// Leaves a snackbar's timer to finish and returns to the calendar.
Future<void> backToCalendar(WidgetTester tester) async {
  await settleSnackbars(tester);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('closing a weekday for the venue empties that calendar column', (tester) async {
    await openSettings(tester);
    expect(find.text('Sunday'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('edit-venue-hours')));
    // Sunday is weekday 7.
    await tap(tester, find.byKey(const ValueKey('hours-open-7')));
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);

    await backToCalendar(tester);
    expect(cell('2026-11-22T11:30'), findsNothing);
    expect(cell('2026-11-21T11:30'), findsOneWidget);
  });

  testWidgets('a new base price is what the next walk-in costs', (tester) async {
    await openSettings(tester);

    await tap(tester, find.byKey(const ValueKey('edit-prices-v1c1')));
    await tester.enterText(find.byKey(const ValueKey('base-price')), '200000');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('200 000 UZS'), findsOneWidget);

    await backToCalendar(tester);
    await tap(tester, find.byTooltip('Next week'));
    // Monday morning has no price rule, so it costs the base price.
    await tap(tester, cell('2026-11-23T10:00'));
    expect(find.text('200 000 UZS'), findsOneWidget);
  });

  testWidgets('a rule that overlaps another is refused', (tester) async {
    await openSettings(tester);

    await tap(tester, find.byKey(const ValueKey('edit-prices-v1c1')));
    // The sample court already has a Mon–Fri evening rule; "Add rule" starts with the same days and hours.
    await tap(tester, find.text('Add rule'));
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Two rules cover the same day and time'), findsOneWidget);

    // Removing the extra rule makes it valid again.
    await tap(tester, find.byTooltip('Remove rule').last);
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Saved'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('a court can close on a day the venue is open', (tester) async {
    await openSettings(tester);

    await tap(tester, find.byKey(const ValueKey('edit-hours-v1c1')));
    await tap(tester, find.byKey(const ValueKey('hours-mode-7')));
    await tap(tester, find.text('Closed').last);
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));

    await backToCalendar(tester);
    // Court 1 is closed on Sunday; Court 2 still follows the venue.
    expect(cell('2026-11-22T11:30'), findsNothing);
    await tap(tester, find.text('Court 2'));
    expect(cell('2026-11-22T11:30'), findsOneWidget);
  });

  testWidgets('the dashboard counts today\'s walk-in and shows its hour', (tester) async {
    await openCalendar(tester);

    await tap(tester, cell('2026-11-22T11:30'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Customer name'), 'Jasur');
    await tap(tester, find.widgetWithText(FilledButton, 'Save booking'));

    await tap(tester, find.byTooltip('Dashboard'));
    expect(find.byType(OwnerDashboardScreen), findsOneWidget);
    expect(find.text('App 0 · walk-in 1'), findsOneWidget);
    expect(find.text('PEAK HOURS'), findsOneWidget);
    // One booking starting in the 11 o'clock hour.
    expect(find.text('11'), findsOneWidget);

    // Nothing is paid yet.
    expect(
      find.descendant(of: find.byKey(const ValueKey('metric-revenue')), matching: find.text('0 UZS')),
      findsOneWidget,
    );

    await tap(tester, find.text('Court 2'));
    expect(find.text('App 0 · walk-in 0'), findsOneWidget);
    expect(find.text('No bookings in this period'), findsOneWidget);
  });

  testWidgets('the settings read in Russian', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'ru'}, utcNow: sundayMorning);
    await tap(tester, find.byType(InitialAvatar).first);
    await tap(tester, find.text('Мои площадки'));
    await tap(tester, find.text('Lochin Padel Club'));
    await tap(tester, find.byTooltip('Часы и цены'));
    expect(find.text('ЧАСЫ РАБОТЫ ПЛОЩАДКИ'), findsOneWidget);
    expect(find.text('Воскресенье'), findsOneWidget);
  });
}

