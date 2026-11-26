import 'package:actra/core/money.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_flow_test.dart' show closeSheet, goTo, key, openAdmin;
import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf;

SampleBackend backendOf(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

/// Captures what the app puts on the clipboard.
String? Function() captureClipboard(WidgetTester tester) {
  String? text;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') text = (call.arguments as Map)['text'] as String?;
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return () => text;
}

void main() {
  testWidgets('the admin home links to Tournaments and Dashboard', (tester) async {
    await openAdmin(tester);
    expect(find.text('Tournaments'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    await tap(tester, key('admin-tournaments'));
    expect(find.text('Tashkent Padel Cup'), findsOneWidget);
    expect(find.text('Amateur 5-a-side League'), findsOneWidget);
  });

  testWidgets('creating a tournament with a singles and a pairs category shows it in the player list', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-tournaments'));
    await tap(tester, key('add-tournament'));

    await tester.enterText(key('tournament-title-en'), 'Spring Smash');

    // Nothing to register for yet.
    await tap(tester, key('save-tournament'));
    expect(find.text('Add at least one category'), findsOneWidget);
    await settleSnackbars(tester);

    await tap(tester, key('add-category'));
    await tester.enterText(key('category-name-en'), 'Singles A');
    await tester.enterText(key('category-fee'), '100000');
    await tester.enterText(key('category-cap'), '8');
    await tap(tester, key('save-category'));

    await tap(tester, key('add-category'));
    await tester.enterText(key('category-name-en'), 'Pairs B');
    await tap(tester, key('category-kind-pairs'));
    await tester.enterText(key('category-fee'), '200000');
    await tester.enterText(key('category-cap'), '6');
    await tap(tester, key('save-category'));

    expect(find.text('Singles A'), findsOneWidget);
    expect(find.text('Pairs B'), findsOneWidget);
    await tap(tester, key('save-tournament'));
    await settleSnackbars(tester);

    await goTo(tester, '/tournaments');
    expect(find.text('Spring Smash'), findsOneWidget);
    await tap(tester, find.text('Spring Smash'));
    expect(find.text('Singles A'), findsOneWidget);
    expect(find.text('Pairs B'), findsOneWidget);
    expect(find.text('0 of 8 filled'), findsOneWidget);
    expect(find.text('0 of 6 filled'), findsOneWidget);
  });

  testWidgets('saving an existing tournament keeps its registration deadline', (tester) async {
    await openAdmin(tester);
    final before = (await backendOf(tester).admin.tournaments()).firstWhere((t) => t.tournament.id == 't1');
    await goTo(tester, '/admin/tournaments/t1');
    await tester.enterText(key('tournament-title-en'), 'Tashkent Padel Cup 2');
    await tap(tester, key('save-tournament'));
    await settleSnackbars(tester);
    final after = (await backendOf(tester).admin.tournaments()).firstWhere((t) => t.tournament.id == 't1');
    expect(after.tournament.title.en, 'Tashkent Padel Cup 2');
    expect(after.tournament.registrationDeadline, before.tournament.registrationDeadline);
    expect(after.categoryCount, before.categoryCount);
  });

  testWidgets('the date pickers open on a tournament dated more than a year ago', (tester) async {
    await openAdmin(tester);
    final backend = backendOf(tester);
    final t1 = (await backend.admin.tournaments()).firstWhere((t) => t.tournament.id == 't1').tournament;
    await backend.admin.saveTournament(
      TournamentDraft.from(t1)
        ..start = DateTime.utc(2024, 3, 1)
        ..end = DateTime.utc(2024, 3, 2)
        ..registrationDeadline = DateTime.utc(2024, 2, 28, 18),
    );
    await goTo(tester, '/admin/tournaments/t1');
    for (final field in ['tournament-start', 'tournament-end', 'tournament-deadline']) {
      await tap(tester, key(field));
      expect(tester.takeException(), isNull, reason: field);
      expect(find.byType(DatePickerDialog), findsOneWidget, reason: field);
      await tap(tester, find.text('Cancel'));
    }
  });

  testWidgets('lowering a cap below the entries holding a spot shows the error', (tester) async {
    await openAdmin(tester);
    await goTo(tester, '/admin/tournaments/t1');
    // Men's pairs: 8 of 8.
    await tap(tester, key('category-row-t1c2'));
    await tester.enterText(key('category-cap'), '5');
    await tap(tester, key('save-category'));
    expect(find.textContaining('lower than the 8'), findsOneWidget);
    expect(find.byKey(ValueKey('save-category')), findsOneWidget);

    // Equal to the count is fine.
    await tester.enterText(key('category-cap'), '8');
    await tap(tester, key('save-category'));
    expect(find.byKey(ValueKey('save-category')), findsNothing);
    await settleSnackbars(tester);
  });

  testWidgets('a category with registrations cannot be deleted; the last category has no delete', (tester) async {
    await openAdmin(tester);
    final backend = backendOf(tester);
    await backend.admin.addRegistration('t1c3', 'p1', partnerId: 'p5');
    await goTo(tester, '/admin/tournaments/t1');

    await tap(tester, key('category-row-t1c3'));
    await tap(tester, key('delete-category'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('This category has registrations and cannot be deleted or changed to another type'), findsOneWidget);
    await closeSheet(tester);

    // A tournament with one category: it stays.
    await goTo(tester, '/admin/tournaments/t2');
    await tap(tester, key('category-row-t2c1'));
    expect(find.byKey(ValueKey('delete-category')), findsNothing);
  });

  testWidgets('moving a registration to a full category shows full; to a free one works', (tester) async {
    await openAdmin(tester);
    final entry = await backendOf(tester).admin.addRegistration('t1c1', 'p1', partnerId: 'p5');
    final id = entry.registration.id;
    await goTo(tester, '/admin/tournaments/t1/participants');

    await tap(tester, key('reg-menu-$id'));
    await tap(tester, key('move-$id'));
    // Men's pairs is full (8 of 8).
    await tap(tester, find.textContaining("Men's pairs").last);
    expect(find.text('This category just filled up'), findsOneWidget);
    await settleSnackbars(tester);
    expect(find.descendant(of: key('participants-t1c1'), matching: key('registration-$id')), findsOneWidget);

    await tap(tester, key('reg-menu-$id'));
    await tap(tester, key('move-$id'));
    await tap(tester, find.textContaining('Mixed pairs').last);
    await settleSnackbars(tester);
    expect(find.descendant(of: key('participants-t1c3'), matching: key('registration-$id')), findsOneWidget);
  });

  testWidgets('only registered entries can be moved or marked paid', (tester) async {
    await openAdmin(tester);
    final backend = backendOf(tester);
    final registered = await backend.admin.addRegistration('t1c1', 'p1', partnerId: 'p5');
    // The demo player waits for a spot in the full football league.
    final waiting = await backend.tournament.joinWaitlist('t2c1');

    await goTo(tester, '/admin/tournaments/t1/participants');
    expect(find.byKey(ValueKey('paid-${registered.registration.id}')), findsOneWidget);
    await tap(tester, key('reg-menu-${registered.registration.id}'));
    expect(find.byKey(ValueKey('move-${registered.registration.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('remove-${registered.registration.id}')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(ValueKey('remove-${registered.registration.id}')))).pop();
    await tester.pumpAndSettle();

    await goTo(tester, '/admin/tournaments/t2/participants');
    expect(find.byKey(ValueKey('paid-${waiting.id}')), findsNothing);
    await tap(tester, key('reg-menu-${waiting.id}'));
    expect(find.byKey(ValueKey('move-${waiting.id}')), findsNothing);
    expect(find.byKey(ValueKey('remove-${waiting.id}')), findsOneWidget);
    expect(find.text('Place 1 in line'), findsOneWidget);
  });

  testWidgets('Offer next on a full category shows the reason', (tester) async {
    await openAdmin(tester);
    await backendOf(tester).tournament.joinWaitlist('t2c1');
    await goTo(tester, '/admin/tournaments/t2/participants');
    await tap(tester, key('offer-next-t2c1'));
    expect(find.text('This category just filled up'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('marking an entry paid shows in the dashboard tournament revenue, per currency', (tester) async {
    await openAdmin(tester);
    final backend = backendOf(tester);
    final uz = await backend.admin.addRegistration('t1c1', 'p1', partnerId: 'p5');
    final kz = await backend.admin.addRegistration('t3c1', 'p4');

    await goTo(tester, '/admin/dashboard');
    expect(find.text(groupThousands(300000)), findsNothing);

    await goTo(tester, '/admin/tournaments/t1/participants');
    await tap(tester, key('paid-${uz.registration.id}'));
    await goTo(tester, '/admin/tournaments/t3/participants');
    await tap(tester, key('paid-${kz.registration.id}'));

    await goTo(tester, '/admin/dashboard');
    expect(find.descendant(of: key('revenue-UZS'), matching: find.text('UZS')), findsOneWidget);
    expect(find.descendant(of: key('revenue-KZT'), matching: find.text('KZT')), findsOneWidget);
    expect(find.descendant(of: key('revenue-UZS'), matching: find.text(groupThousands(300000))), findsOneWidget);
    expect(find.descendant(of: key('revenue-KZT'), matching: find.text(groupThousands(15000))), findsOneWidget);
    // Never one number across currencies.
    expect(find.text(groupThousands(315000)), findsNothing);
    expect(find.textContaining('Total'), findsNWidgets(1)); // only "Total users"
    expect(find.text('Venues'), findsOneWidget);
    expect(find.text('Tournaments'), findsOneWidget);
    expect(find.text('Bookings created'), findsOneWidget);

    // Unmarking takes it out again.
    await goTo(tester, '/admin/tournaments/t1/participants');
    await tap(tester, key('paid-${uz.registration.id}'));
    await goTo(tester, '/admin/dashboard');
    expect(find.text(groupThousands(300000)), findsNothing);
  });

  testWidgets('the dashboard has period presets and a city filter', (tester) async {
    await openAdmin(tester);
    await goTo(tester, '/admin/dashboard');
    expect(find.byKey(ValueKey('stat-users-total')), findsOneWidget);
    for (final period in ['today', 'week', 'month', 'custom']) {
      expect(find.byKey(ValueKey('dash-period-$period')), findsOneWidget);
    }
    await tap(tester, key('dash-period-week'));
    await tap(tester, key('dash-period-month'));
    await tap(tester, key('dash-city'));
    await tap(tester, find.text('Almaty').last);
    expect(find.byKey(ValueKey('stat-users-total')), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('Copy CSV puts the header and one line per entry on the clipboard', (tester) async {
    await openAdmin(tester);
    final clipboard = captureClipboard(tester);
    final backend = backendOf(tester);
    final a = await backend.admin.addRegistration('t1c3', 'p1', partnerId: 'p5');
    await backend.admin.addRegistration('t1c3', 'p2', partnerId: 'p8');
    await backend.admin.setPaid(a.registration.id, true);

    await goTo(tester, '/admin/tournaments/t1/participants');
    await tap(tester, key('copy-csv-t1c3'));

    final lines = clipboard()!.trim().split('\n');
    expect(
      lines.first,
      'category,status,registrant_name,registrant_phone,partner_name,partner_phone,fee,currency,paid,created',
    );
    expect(lines, hasLength(3));
    expect(lines[1], contains('Mixed pairs,registered,Aziz,+998901000001,Arman,+998901000005,400000,UZS,yes,'));
    expect(lines[2], contains('Mixed pairs,registered,Dilnoza,+998901000002,Kamila,+77011000008,400000,UZS,no,'));
    await settleSnackbars(tester);
  });

  testWidgets('removing an entry asks first and takes it off the list', (tester) async {
    await openAdmin(tester);
    final entry = await backendOf(tester).admin.addRegistration('t1c3', 'p1', partnerId: 'p5');
    final id = entry.registration.id;
    await goTo(tester, '/admin/tournaments/t1/participants');
    await tap(tester, key('reg-menu-$id'));
    await tap(tester, key('remove-$id'));
    await tap(tester, find.widgetWithText(FilledButton, 'Remove'));
    await settleSnackbars(tester);
    expect(find.byKey(ValueKey('registration-$id')), findsNothing);
  });

  testWidgets('adding a player to a pairs category takes two picks', (tester) async {
    await openAdmin(tester);
    await goTo(tester, '/admin/tournaments/t1/participants');
    await tap(tester, key('add-player-t1c3'));
    await tester.enterText(key('owner-search'), 'Aziz');
    await tester.pumpAndSettle();
    await tap(tester, key('user-p1'));
    await tester.enterText(key('owner-search'), 'Arman');
    await tester.pumpAndSettle();
    await tap(tester, key('user-p5'));
    await settleSnackbars(tester);
    expect(find.descendant(of: key('participants-t1c3'), matching: find.text('Aziz')), findsOneWidget);
    expect(find.descendant(of: key('participants-t1c3'), matching: find.text('With Arman')), findsOneWidget);
  });
}
