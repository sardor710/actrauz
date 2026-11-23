import 'package:actra/features/common/widgets.dart';
import 'package:actra/features/owner/owner_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';

/// Sunday 22 Nov 2026, 10:00 in Tashkent: the last day of the week 16–22 Nov.
Finder cell(String localTime) => find.byKey(ValueKey('owner-cell-$localTime'));

Future<void> openCalendar(WidgetTester tester) async {
  await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
  await tap(tester, find.byType(InitialAvatar).first);
  await tap(tester, find.text('My venues'));
  await tap(tester, find.text('Lochin Padel Club'));
}

void main() {
  testWidgets('the calendar opens on this week for the first court', (tester) async {
    await openCalendar(tester);

    expect(find.byType(OwnerCalendarScreen), findsOneWidget);
    expect(find.text('16 Nov – 22 Nov'), findsOneWidget);
    // Today's remaining slots are free, the ones that have ended are not tappable.
    expect(find.descendant(of: cell('2026-11-22T11:30'), matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
    expect(find.descendant(of: cell('2026-11-22T07:00'), matching: find.byIcon(Icons.add_rounded)), findsNothing);
    // Monday is over.
    expect(find.descendant(of: cell('2026-11-16T19:00'), matching: find.byIcon(Icons.add_rounded)), findsNothing);
  });

  testWidgets('add a walk-in, see the name, then cancel it', (tester) async {
    await openCalendar(tester);

    await tap(tester, cell('2026-11-22T11:30'));
    expect(find.text('New booking'), findsWidgets);

    // The name is required.
    await tap(tester, find.widgetWithText(FilledButton, 'Save booking'));
    expect(find.text('Enter the customer name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Customer name'), 'Jasur');
    await tap(tester, find.text('Card'));
    await tap(tester, find.widgetWithText(FilledButton, 'Save booking'));

    expect(find.descendant(of: cell('2026-11-22T11:30'), matching: find.text('Jasur')), findsOneWidget);

    // 10:00 now, 11:30 start: it cannot be marked yet.
    await tap(tester, cell('2026-11-22T11:30'));
    expect(find.text('Walk-in or phone'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('300 000 UZS'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Mark paid')).onPressed, isNull);

    await tap(tester, find.widgetWithText(TextButton, 'Cancel booking'));
    expect(find.text('Cancel this booking?'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Cancel booking'));

    expect(find.descendant(of: cell('2026-11-22T11:30'), matching: find.text('Jasur')), findsNothing);
    expect(find.descendant(of: cell('2026-11-22T11:30'), matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
  });

  testWidgets('a walk-in over two slots fills both and takes them from players', (tester) async {
    await openCalendar(tester);

    await tap(tester, cell('2026-11-22T13:00'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Customer name'), 'Malika');
    // The second stepper is "Number of slots".
    await tap(tester, find.byIcon(Icons.add_rounded).last);
    expect(find.textContaining('13:00–16:00'), findsOneWidget);
    expect(find.text('600 000 UZS'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Save booking'));

    expect(find.descendant(of: cell('2026-11-22T13:00'), matching: find.text('Malika')), findsOneWidget);
    expect(find.descendant(of: cell('2026-11-22T14:30'), matching: find.text('Malika')), findsOneWidget);
  });

  testWidgets('block a time, then open it again', (tester) async {
    await openCalendar(tester);

    await tap(tester, cell('2026-11-22T17:30'));
    await tap(tester, find.text('Block time'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Reason (optional)'), 'Maintenance');
    await tap(tester, find.widgetWithText(FilledButton, 'Block this time'));

    expect(
      find.descendant(of: cell('2026-11-22T17:30'), matching: find.byIcon(Icons.lock_outline_rounded)),
      findsOneWidget,
    );

    await tap(tester, cell('2026-11-22T17:30'));
    expect(find.text('Maintenance'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Open this time again'));

    expect(find.descendant(of: cell('2026-11-22T17:30'), matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
  });

  testWidgets('next week, then Today', (tester) async {
    await openCalendar(tester);

    await tap(tester, find.byTooltip('Next week'));
    expect(find.text('23 Nov – 29 Nov'), findsOneWidget);
    // A sample game sits on a real booking tomorrow evening.
    expect(find.descendant(of: cell('2026-11-23T19:00'), matching: find.text('Aziz')), findsOneWidget);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Today'));
    expect(find.text('16 Nov – 22 Nov'), findsOneWidget);
  });

  testWidgets('switching court shows that court\'s week', (tester) async {
    await openCalendar(tester);

    await tap(tester, find.byTooltip('Next week'));
    await tap(tester, find.text('Court 2'));
    // The full sample game on Court 2 is on Tuesday evening.
    expect(find.descendant(of: cell('2026-11-24T19:00'), matching: find.byType(Text)), findsOneWidget);
    expect(find.descendant(of: cell('2026-11-23T19:00'), matching: find.byIcon(Icons.add_rounded)), findsOneWidget);
  });

  for (final (lang, title, free) in [('ru', 'Мои площадки', 'Свободно'), ('uz', 'Mening maydonlarim', 'Boʻsh')]) {
    testWidgets('the calendar reads in $lang', (tester) async {
      await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
      await tap(tester, find.byType(InitialAvatar).first);
      await tap(tester, find.text(title));
      await tap(tester, find.text('Lochin Padel Club'));
      expect(find.text(free), findsOneWidget);
    });
  }
}
