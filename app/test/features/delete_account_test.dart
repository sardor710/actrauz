import 'dart:async';

import 'package:actra/data/auth/auth_repository.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/owner.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/features/owner/booking_details_sheet.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_flow_test.dart' show goTo;
import '../app_flow_test.dart' as sample;
import '../games_host_flow_test.dart' show containerOf;
import '../onboarding_telegram_test.dart' show FakeAuth, pumpApp, ru, tap;

final en = lookupAppLocalizations(const Locale('en'));

const _signedIn = <String, Object>{'lang': 'ru', 'city': 'tashkent', 'user_name': 'Тест'};

/// Signed in with a backend session, on the profile, with the delete dialog open.
Future<FakeAuth> openDeleteDialog(WidgetTester tester, {Object? error}) async {
  final auth = FakeAuth(session: true, storedName: 'Тест')..deleteError = error;
  await pumpApp(tester, auth, prefs: _signedIn);
  await tap(tester, find.byType(InitialAvatar).first);
  await tester.ensureVisible(find.text(ru.deleteAccount));
  await tap(tester, find.text(ru.deleteAccount));
  return auth;
}

SampleBackend backendOf(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

/// A public running game on Monday morning at a meeting point.
GameDraft runningDraft() => GameDraft(
  sportId: 'running',
  spots: 4,
  meetingPoint: 'Bunyodkor park, main gate',
  meetingLat: 41.3,
  meetingLng: 69.2,
  start: DateTime.utc(2026, 11, 23, 7),
  end: DateTime.utc(2026, 11, 23, 8),
);

void main() {
  testWidgets('delete account asks before deleting', (tester) async {
    final auth = await openDeleteDialog(tester);
    expect(find.text(ru.deleteAccountTitle), findsOneWidget);
    expect(find.text(ru.deleteAccountBody), findsOneWidget);

    // Cancel changes nothing.
    await tap(tester, find.widgetWithText(TextButton, ru.cancel));
    expect(find.text(ru.deleteAccountTitle), findsNothing);
    expect(auth.deletes, 0);
    expect(find.text(ru.deleteAccount), findsOneWidget, reason: 'still on the profile');

    await tap(tester, find.text(ru.deleteAccount));
    await tap(tester, find.widgetWithText(FilledButton, ru.deleteAccountConfirm));
    expect(auth.deletes, 1);

    // Signed out like sign-out, language and city kept: straight to the
    // sign-in step, not the language list.
    expect(find.text(ru.signInTitle), findsOneWidget);
    expect(find.text('Oʻzbekcha'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_name'), isNull);
    expect(prefs.getString('lang'), 'ru');
    expect(prefs.getString('city'), 'tashkent');

    // Back goes to the city step as usual.
    await tap(tester, find.byType(BackButton));
    expect(find.text(ru.chooseCity), findsOneWidget);
  });

  test('the dialog says what deletion does', () {
    for (final part in ['upcoming bookings', 'games', 'name and phone', 'cannot be undone']) {
      expect(en.deleteAccountBody, contains(part));
    }
  });

  testWidgets('admin sees why not', (tester) async {
    final auth = await openDeleteDialog(tester, error: const AdminAccountException());
    await tap(tester, find.widgetWithText(FilledButton, ru.deleteAccountConfirm));

    expect(auth.deletes, 1);
    expect(find.text(ru.deleteAccountAdmin), findsOneWidget);
    expect(find.text(ru.deleteAccount), findsOneWidget, reason: 'still signed in, on the profile');
    expect(auth.signOuts, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_name'), 'Тест');
  });

  testWidgets('no connection: the account stays and the player is told', (tester) async {
    final auth = await openDeleteDialog(tester, error: Exception('offline'));
    await tap(tester, find.widgetWithText(FilledButton, ru.deleteAccountConfirm));

    expect(find.text(ru.errUnavailable), findsOneWidget);
    expect(find.text(ru.deleteAccount), findsOneWidget);
    expect(auth.signOuts, 0);
  });

  testWidgets('a 401 after a lost answer signs out as a deletion does', (tester) async {
    // The first call deleted the account but its answer never arrived; the
    // retry's token is refused, and the app must not stay signed in.
    final auth = await openDeleteDialog(tester, error: const SessionInvalidException());
    await tap(tester, find.widgetWithText(FilledButton, ru.deleteAccountConfirm));

    expect(auth.deletes, 1);
    expect(auth.signOuts, 1);
    expect(find.text(ru.signInTitle), findsOneWidget);
    expect(find.text('Oʻzbekcha'), findsNothing);
    expect(find.text(ru.errUnavailable), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_name'), isNull);
    expect(prefs.getString('lang'), 'ru');
    expect(prefs.getString('city'), 'tashkent');
  });

  testWidgets('a second confirm while deleting starts nothing', (tester) async {
    final auth = await openDeleteDialog(tester);
    final gate = auth.deleteGate = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, ru.deleteAccountConfirm));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Progress shows over the profile until the call settles; the menu
    // underneath cannot be reached.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text(ru.deleteAccount), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(ru.deleteAccountTitle), findsNothing);
    // Nor does a second call reach the backend while one is running.
    final second = containerOf(tester).read(sessionProvider.notifier).deleteAccount();
    expect(auth.deletes, 1);

    gate.complete();
    await second;
    await tester.pumpAndSettle();
    expect(auth.deletes, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(ru.signInTitle), findsOneWidget);
  });

  testWidgets('a failure is still shown after leaving the profile', (tester) async {
    final auth = await openDeleteDialog(tester, error: Exception('offline'));
    final gate = auth.deleteGate = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, ru.deleteAccountConfirm));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    containerOf(tester).read(routerProvider).go('/games');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text(ru.errUnavailable), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(auth.signOuts, 0);
  });

  testWidgets('a later sign-out still starts at the language list', (tester) async {
    // A failed deletion leaves nothing behind for the next sign-out.
    final auth = await openDeleteDialog(tester, error: Exception('offline'));
    await tap(tester, find.widgetWithText(FilledButton, ru.deleteAccountConfirm));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(ru.signOut));
    await tap(tester, find.text(ru.signOut));
    expect(auth.signOuts, 1);
    expect(find.text('Oʻzbekcha'), findsOneWidget);
  });

  group('deleted player shows a placeholder name', () {
    testWidgets('in a game\'s participant list', (tester) async {
      await sample.pumpApp(tester, prefs: sample.signedIn, utcNow: sample.sundayMorning);
      final backend = backendOf(tester);
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
      await backend.joinAs('p2', game.id);
      backend.markDeleted('p1');

      await goTo(tester, '/games/${game.id}');
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.text(en.deletedPlayer), findsOneWidget);
      expect(find.text('Aziz'), findsNothing);
      expect(find.text('Dilnoza'), findsOneWidget);
    });

    testWidgets('in the title of a game whose host deleted their account', (tester) async {
      await sample.pumpApp(tester, prefs: sample.signedIn, utcNow: sample.sundayMorning);
      final backend = backendOf(tester);
      // Aziz hosts; deleting cancels the game, and its notification still
      // opens it.
      final game = await backend.createAs('p1', runningDraft());
      backend.markDeleted('p1');
      containerOf(tester).invalidate(playerProvider);

      await goTo(tester, '/games/${game.id}');
      expect(find.text(en.gameTitle(en.deletedPlayer, 'Running')), findsOneWidget);
      expect(find.text(en.gameTitle('', 'Running')), findsNothing);
      expect(find.textContaining('Aziz'), findsNothing);
    });

    testWidgets('on a game card, with a neutral avatar', (tester) async {
      await sample.pumpApp(tester, prefs: sample.signedIn, utcNow: sample.sundayMorning);
      final backend = backendOf(tester);
      final game = await backend.createAs('p1', runningDraft());
      await backend.joinAs('p2', game.id);
      backend.markDeleted('p1');
      containerOf(tester)
        ..invalidate(playerProvider)
        ..invalidate(gamesProvider);

      await goTo(tester, '/games');
      final card = find.ancestor(of: find.text(en.gameTitle(en.deletedPlayer, 'Running')), matching: find.byType(Card));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const ValueKey('deleted-avatar'))), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('?')), findsNothing);
      expect(
        find.descendant(of: card, matching: find.text('D')),
        findsOneWidget,
        reason: 'Dilnoza keeps her initial',
      );
    });

    testWidgets('in the owner\'s booking sheet', (tester) async {
      await sample.pumpApp(tester, prefs: sample.signedIn, utcNow: sample.sundayMorning);
      final venue = kSampleVenues.first;
      final court = venue.courts.first;
      OwnerBooking played({required bool deleted}) => OwnerBooking(
        id: 'b-old',
        venueId: venue.id,
        courtId: court.id,
        start: DateTime.utc(2026, 11, 20, 18),
        end: DateTime.utc(2026, 11, 20, 19, 30),
        slotCount: 1,
        totalPrice: 180000,
        status: BookingStatus.paid,
        source: BookingSource.app,
        customerDeleted: deleted,
      );

      showBookingDetailsSheet(
        tester.element(find.byType(Scaffold).first),
        venue: venue,
        court: court,
        booking: played(deleted: true),
        now: DateTime.utc(2026, 11, 22, 10),
      );
      await tester.pumpAndSettle();
      expect(find.text(en.deletedPlayer), findsOneWidget);
    });

    testWidgets('on their profile, which offers no invite', (tester) async {
      await sample.pumpApp(tester, prefs: sample.signedIn, utcNow: sample.sundayMorning);
      final router = containerOf(tester).read(routerProvider);
      router.go('/players/p5');
      await tester.pumpAndSettle();
      expect(find.text(en.inviteToGame), findsOneWidget, reason: 'a live player can be invited');

      backendOf(tester).markDeleted('p5');
      router.go('/games');
      await tester.pumpAndSettle();
      containerOf(tester).invalidate(playerProfileProvider('p5'));
      router.go('/players/p5');
      await tester.pumpAndSettle();
      expect(find.text(en.deletedPlayer), findsWidgets);
      expect(find.text(en.inviteToGame), findsNothing);
    });

    testWidgets('in a tournament\'s participant list', (tester) async {
      await sample.pumpApp(tester, prefs: sample.signedIn, utcNow: sample.sundayMorning);
      final backend = backendOf(tester);
      await backend.admin.addRegistration('t1c1', 'p1', partnerId: 'p5');
      backend.markDeleted('p5');

      await goTo(tester, '/admin/tournaments/t1/participants');
      expect(find.text('Aziz'), findsOneWidget);
      expect(find.textContaining(en.deletedPlayer), findsOneWidget);
      expect(find.textContaining('Arman'), findsNothing);
    });
  });
}
