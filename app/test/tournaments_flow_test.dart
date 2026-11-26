import 'package:actra/core/localized_text.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/features/inbox/inbox_screen.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf;

/// What changed behind the screens' backs shows after these providers reload.
Future<void> reload(WidgetTester tester) async {
  final c = containerOf(tester);
  c.invalidate(tournamentsProvider);
  c.invalidate(tournamentProvider);
  c.invalidate(myRegistrationsProvider);
  c.invalidate(inboxProvider);
  c.invalidate(unreadCountProvider);
  await tester.pumpAndSettle();
}

SampleBackend backendOf(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

Finder category(String id) => find.byKey(ValueKey('category-$id'));

Finder inCategory(String id, Finder finder) => find.descendant(of: category(id), matching: finder);

Future<void> openTournament(WidgetTester tester, String title) async {
  await tap(tester, find.text('Tournaments'));
  await tap(tester, find.text(title));
}

Future<void> openMine(WidgetTester tester) async {
  await tap(tester, find.text('Tournaments'));
  await tap(tester, find.byKey(const ValueKey('my-tournaments')));
}

void main() {
  testWidgets('the list filters by sport and sorts A-Z', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = backendOf(tester);
    // Starts last, but its title sorts first.
    await backend.admin.saveTournament(
      TournamentDraft(
        cityId: 'tashkent',
        sportId: 'tennis',
        start: DateTime.utc(2026, 12, 20),
        end: DateTime.utc(2026, 12, 20),
        title: const LocalizedText.all('Aaa Open'),
      ),
    );
    await reload(tester);
    await tap(tester, find.text('Tournaments'));

    double top(String title) => tester.getTopLeft(find.text(title)).dy;
    expect(top('Tashkent Padel Cup'), lessThan(top('Amateur 5-a-side League')));
    expect(top('Amateur 5-a-side League'), lessThan(top('Aaa Open')));

    await tap(tester, find.byKey(const ValueKey('tournaments-sort-az')));
    expect(top('Aaa Open'), lessThan(top('Tashkent Padel Cup')));

    await tap(tester, find.byKey(const ValueKey('tournaments-sport')));
    await tap(tester, find.text('Padel').last);
    expect(find.text('Tashkent Padel Cup'), findsOneWidget);
    expect(find.text('Amateur 5-a-side League'), findsNothing);
    expect(find.text('Aaa Open'), findsNothing);
  });

  testWidgets('the detail shows X of Y filled; a full category offers the waitlist instead of Register', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openTournament(tester, 'Amateur 5-a-side League');

    expect(inCategory('t2c1', find.text('12 of 12 filled')), findsOneWidget);
    expect(inCategory('t2c1', find.text('Join waitlist')), findsOneWidget);
    expect(inCategory('t2c1', find.widgetWithText(FilledButton, 'Register')), findsNothing);
  });

  testWidgets('the detail lists every category with kind, gender, level, fee and spots', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openTournament(tester, 'Tashkent Padel Cup');

    expect(inCategory('t1c1', find.text('9 of 12 filled')), findsOneWidget);
    expect(inCategory('t1c1', find.widgetWithText(FilledButton, 'Register')), findsOneWidget);
    expect(inCategory('t1c2', find.text("Men's pairs")), findsOneWidget);
    expect(inCategory('t1c2', find.text('Men')), findsOneWidget);
    expect(inCategory('t1c2', find.text('Pairs')), findsOneWidget);
    expect(inCategory('t1c2', find.text('Level 3–5')), findsOneWidget);
    expect(inCategory('t1c2', find.text('Join waitlist')), findsOneWidget);
    expect(inCategory('t1c3', find.text('Level 2–4')), findsOneWidget);
    expect(inCategory('t1c3', find.textContaining('400 000 UZS')), findsOneWidget);
  });

  testWidgets('registering for singles takes a spot; cancelling before the deadline gives it back', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'city': 'almaty'}, utcNow: sundayMorning);
    await openTournament(tester, 'Almaty Open Tennis');

    expect(inCategory('t3c1', find.text('5 of 16 filled')), findsOneWidget);
    await tap(tester, inCategory('t3c1', find.widgetWithText(FilledButton, 'Register')));
    expect(find.textContaining('15 000 ₸'), findsWidgets);
    await tap(tester, find.widgetWithText(FilledButton, 'Confirm registration'));

    expect(inCategory('t3c1', find.text('6 of 16 filled')), findsOneWidget);
    expect(inCategory('t3c1', find.text('Registered')), findsOneWidget);
    expect(inCategory('t3c1', find.widgetWithText(FilledButton, 'Register')), findsNothing);

    await tap(tester, inCategory('t3c1', find.widgetWithText(OutlinedButton, 'Cancel registration')));
    await tap(tester, find.widgetWithText(FilledButton, 'Cancel registration'));
    expect(inCategory('t3c1', find.text('5 of 16 filled')), findsOneWidget);
    expect(inCategory('t3c1', find.widgetWithText(FilledButton, 'Register')), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('pairs: a partner found by phone gets an invite and the entry waits for them', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openTournament(tester, 'Tashkent Padel Cup');

    await tap(tester, inCategory('t1c1', find.widgetWithText(FilledButton, 'Register')));
    expect(find.widgetWithText(FilledButton, 'Send invite'), findsOneWidget);
    await tap(tester, find.text('Phone number'));
    await tester.enterText(find.byKey(const ValueKey('partner-phone')), '+998 90 100 00 01');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Find'));
    expect(find.text('Aziz'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Send invite'));

    expect(inCategory('t1c1', find.text('Waiting for partner')), findsOneWidget);
    expect(inCategory('t1c1', find.textContaining('Aziz')), findsOneWidget);
    // A pending pair holds no spot.
    expect(inCategory('t1c1', find.text('9 of 12 filled')), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('pairs: an unknown phone number is said so, and nothing is sent', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openTournament(tester, 'Tashkent Padel Cup');

    await tap(tester, inCategory('t1c1', find.widgetWithText(FilledButton, 'Register')));
    await tap(tester, find.text('Phone number'));
    await tester.enterText(find.byKey(const ValueKey('partner-phone')), '+998 90 999 99 99');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Find'));

    expect(find.text('No player has this number'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send invite'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Send invite'));
    expect(find.text('Choose a partner first'), findsOneWidget);
  });

  testWidgets('pairs: a partner picked from the players list is invited', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openTournament(tester, 'Tashkent Padel Cup');

    await tap(tester, inCategory('t1c1', find.widgetWithText(FilledButton, 'Register')));
    await tap(tester, find.byKey(const ValueKey('partner-player-p5')));
    await tap(tester, find.widgetWithText(FilledButton, 'Send invite'));

    expect(inCategory('t1c1', find.text('Waiting for partner')), findsOneWidget);
    expect(inCategory('t1c1', find.textContaining('Arman')), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('as the partner, accepting from My tournaments registers the pair', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await backendOf(tester).registerAs('p1', 't1c1', partnerId: kMeId);
    await reload(tester);
    await openMine(tester);

    expect(find.text('My tournaments'), findsWidgets);
    expect(find.text('Tashkent Padel Cup'), findsOneWidget);
    expect(find.textContaining('Aziz invited you'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
    // An unconfirmed partner cannot cancel, only answer.
    expect(find.text('Cancel registration'), findsNothing);

    await tap(tester, find.widgetWithText(FilledButton, 'Accept'));
    expect(find.text('Registered'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel registration'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('declining a partner invite leaves the entry declined with no actions', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await backendOf(tester).registerAs('p1', 't1c1', partnerId: kMeId);
    await reload(tester);
    await openMine(tester);

    await tap(tester, find.widgetWithText(OutlinedButton, 'Decline'));
    expect(find.text('Declined'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsNothing);
    await settleSnackbars(tester);
  });

  testWidgets('a waitlisted player is offered a freed spot, sees Claim with a countdown, and claims it', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await openTournament(tester, 'Amateur 5-a-side League');

    await tap(tester, inCategory('t2c1', find.widgetWithText(OutlinedButton, 'Join waitlist')));
    await tap(tester, find.widgetWithText(FilledButton, 'Join waitlist'));
    expect(inCategory('t2c1', find.text('On the waitlist')), findsOneWidget);
    expect(inCategory('t2c1', find.text('Place 1 in line')), findsOneWidget);

    // The admin raises the cap by one; the first in line is offered the spot.
    final backend = backendOf(tester);
    final tournament = await backend.tournament.get('t2');
    await backend.admin.saveCategory(CategoryDraft.from(tournament.category('t2c1'))..cap = 13);
    await reload(tester);

    expect(inCategory('t2c1', find.text('Spot offered')), findsOneWidget);
    expect(inCategory('t2c1', find.textContaining('left')), findsOneWidget);
    // An offer holds the spot, so the category still reads full.
    expect(inCategory('t2c1', find.text('13 of 13 filled')), findsOneWidget);
    await tap(tester, inCategory('t2c1', find.widgetWithText(FilledButton, 'Claim')));
    expect(inCategory('t2c1', find.text('Registered')), findsOneWidget);
    expect(inCategory('t2c1', find.widgetWithText(FilledButton, 'Claim')), findsNothing);

    await openMine(tester);
    expect(find.text('Registered'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('the offer also shows in My tournaments with Claim', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = backendOf(tester);
    await backend.tournament.joinWaitlist('t2c1');
    final tournament = await backend.tournament.get('t2');
    await backend.admin.saveCategory(CategoryDraft.from(tournament.category('t2c1'))..cap = 13);
    await reload(tester);
    await openMine(tester);

    expect(find.text('Spot offered'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Claim'));
    expect(find.text('Registered'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('after the deadline register, waitlist and cancel are gone', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = backendOf(tester);
    final entry = await backend.tournament.register('t1c1', partnerId: 'p1');
    await backend.respondPartnerAs('p1', entry.id, accept: true);
    final tournament = await backend.tournament.get('t1');
    await backend.admin.saveTournament(TournamentDraft.from(tournament)..registrationDeadline = DateTime.utc(2026, 11, 20));
    await reload(tester);

    await openTournament(tester, 'Tashkent Padel Cup');
    expect(find.text('Registration is closed'), findsOneWidget);
    expect(inCategory('t1c1', find.text('Registered')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Register'), findsNothing);
    expect(find.text('Join waitlist'), findsNothing);
    expect(find.text('Cancel registration'), findsNothing);

    await openMine(tester);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('Cancel registration'), findsNothing);
  });

  testWidgets('a tournament notification in the inbox opens the tournament', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await backendOf(tester).registerAs('p1', 't1c1', partnerId: kMeId);
    await reload(tester);

    await tap(tester, find.byKey(const ValueKey('inbox-bell')));
    expect(find.textContaining('Aziz invited you to be their partner in Tashkent Padel Cup'), findsOneWidget);
    await tap(tester, find.textContaining('Aziz invited you to be their partner'));

    expect(find.byKey(const ValueKey('tournament-detail')), findsOneWidget);
    // The invite can be answered right here.
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Accept'));
    expect(inCategory('t1c1', find.text('Registered')), findsOneWidget);
    await settleSnackbars(tester);
  });

  group('notification texts', () {
    const kinds = [
      'tournament_registered',
      'tournament_partner_invite',
      'tournament_partner_accepted',
      'tournament_partner_declined',
      'tournament_partner_cancelled',
      'tournament_partner_expired',
      'tournament_spot_offered',
      'tournament_deadline_reminder',
      'tournament_removed',
      'tournament_moved',
    ];

    AppNotification note(String kind) => AppNotification(
      id: 'n-$kind',
      kind: kind,
      category: kind == 'tournament_partner_invite' ? 'invites' : 'tournaments',
      payload: const {
        'tournament_id': 't1',
        'category_id': 't1c1',
        'registration_id': 'r1',
        'actor_name': 'Aziz',
        'title': {'uz': 'Toshkent kubogi', 'ru': 'Кубок Ташкента', 'en': 'Tashkent Cup'},
        'category_name': {'uz': 'Ochiq', 'ru': 'Открытая', 'en': 'Open'},
      },
      createdAt: DateTime.utc(2026, 11, 22),
      read: false,
    );

    for (final code in ['en', 'ru', 'uz']) {
      test('every tournament kind has a sentence in $code that names the tournament', () {
        final l = lookupAppLocalizations(Locale(code));
        final title = {'en': 'Tashkent Cup', 'ru': 'Кубок Ташкента', 'uz': 'Toshkent kubogi'}[code]!;
        final seen = <String>{};
        for (final kind in kinds) {
          final text = notificationText(l, code, note(kind));
          expect(text, isNot(l.notifUnknown), reason: '$kind in $code');
          expect(text, contains(title), reason: '$kind in $code');
          expect(seen.add(text), isTrue, reason: '$kind repeats another sentence in $code');
        }
      });
    }

    test('a missing title falls back to a plain word instead of an empty gap', () {
      final l = lookupAppLocalizations(const Locale('en'));
      final bare = AppNotification(
        id: 'n',
        kind: 'tournament_registered',
        category: 'tournaments',
        payload: const {'tournament_id': 't1'},
        createdAt: DateTime.utc(2026, 11, 22),
        read: false,
      );
      expect(notificationText(l, 'en', bare), 'You are registered for the tournament');
    });
  });
}
