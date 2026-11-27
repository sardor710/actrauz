import 'package:actra/app.dart';
import 'package:actra/data/admin_repository.dart';
import 'package:actra/data/sample/sample_data.dart' show kMeId;
import 'package:actra/domain/admin.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/admin/admin_review_screen.dart';
import 'package:actra/features/social/player_profile_screen.dart';
import 'package:actra/data/sample/sample_repositories.dart' show SampleBackend;
import 'package:actra/core/theme.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/features/admin/admin_audit_screen.dart';
import 'package:actra/features/admin/admin_common.dart' show adminWrite;
import 'package:actra/features/common/formatters.dart' show joinErrorText;
import 'package:actra/l10n/gen/app_localizations_en.dart';
import 'package:actra/features/admin/admin_home_screen.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/state/admin_providers.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show containerOf;

/// In sample mode the signed-in demo player is an admin.
Future<void> openAdmin(WidgetTester tester) async {
  await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
  await tap(tester, find.byType(InitialAvatar).first);
  await tap(tester, find.text('Admin'));
  expect(find.byType(AdminHomeScreen), findsOneWidget);
}

/// Opens the venue editor for Lochin Padel Club (v1, two padel courts).
Future<void> openLochin(WidgetTester tester) async {
  await openAdmin(tester);
  await tap(tester, find.byKey(const ValueKey('admin-venues')));
  await tap(tester, find.text('Lochin Padel Club'));
}

Future<void> goTo(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await tester.pumpAndSettle();
}

Finder key(String value) => find.byKey(ValueKey(value));

/// Dismisses the open bottom sheet, which may cover the whole phone screen.
Future<void> closeSheet(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(BottomSheet))).pop();
  await tester.pumpAndSettle();
}

/// Someone who is not an admin: every other call would be refused.
class _NotAdmin implements AdminRepository {
  @override
  Future<bool> isAdmin() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('a Review write refused as not allowed says admins only, not "your venue"', (tester) async {
    SharedPreferences.setMockInitialValues(signedIn);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: buildTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => adminWrite(
                  context,
                  ref,
                  () async => throw const BookingException(BookingError.notAllowed),
                  adminOnly: true,
                ),
                child: const Text('write'),
              ),
            ),
          ),
        ),
      ),
    );
    await tap(tester, find.text('write'));
    expect(find.text('Only Actra administrators can open this page'), findsOneWidget);
    expect(find.text('You do not manage this venue'), findsNothing);
    await settleSnackbars(tester);
  });

  test('team and after-game refusals have their own words', () {
    final l = AppLocalizationsEn();
    String text(JoinError e) => joinErrorText(l, JoinException(e));
    expect(text(JoinError.alreadyInTeam), 'You are already in this team');
    expect(text(JoinError.alreadyAskedTeam), 'You have already asked to join this team');
    expect(text(JoinError.captainOnly), 'Only the captain can do this');
    expect(text(JoinError.windowClosed), 'The time for this has passed');
  });

  testWidgets('the profile shows Admin, which opens the four sections', (tester) async {
    await openAdmin(tester);
    for (final label in ['Venues', 'Sports', 'Banners', 'Audit log']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('6 venues'), findsOneWidget);
  });

  testWidgets('a non-admin sees no Admin row and a locked admin page', (tester) async {
    SharedPreferences.setMockInitialValues(signedIn);
    final prefs = await SharedPreferences.getInstance();
    await initializeDateFormatting();
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => sundayMorning),
          adminRepositoryProvider.overrideWithValue(_NotAdmin()),
        ],
        child: const ActraApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tap(tester, find.byType(InitialAvatar).first);
    expect(find.text('My venues'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);

    for (final path in ['/admin', '/admin/venues', '/admin/venues/v1', '/admin/sports', '/admin/banners', '/admin/audit', '/admin/review', '/admin/tournaments', '/admin/tournaments/new', '/admin/tournaments/t1', '/admin/tournaments/t1/participants', '/admin/dashboard']) {
      await goTo(tester, path);
      expect(find.text('Only Actra administrators can open this page'), findsOneWidget, reason: path);
    }
  });

  testWidgets('create a venue with a court and see it in the player\'s venue list', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-venues'));
    await tap(tester, key('add-venue'));
    expect(find.text('New venue'), findsOneWidget);
    // Courts and owners come after the first save.
    expect(find.text('Save the venue to add courts and owners'), findsOneWidget);
    expect(key('add-court'), findsNothing);

    // A name is required in at least one language.
    await tap(tester, key('save-venue'));
    expect(find.text('Fill in at least one language'), findsOneWidget);

    await tester.enterText(key('venue-name-en'), 'Test Arena');
    await tester.enterText(key('venue-district-en'), 'Mirzo Ulugbek');
    await tap(tester, find.text('Parking'));
    await tap(tester, key('save-venue'));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Save the venue to add courts and owners'), findsNothing);

    await tap(tester, key('add-court'));
    expect(find.text('New court'), findsOneWidget);
    await tester.enterText(key('court-name-en'), 'Centre Court');
    await tester.enterText(key('court-price'), '150000');
    await tap(tester, find.text('60 min'));
    await tap(tester, key('save-court'));
    expect(find.text('Centre Court'), findsOneWidget);
    // Thousands are grouped with a non-breaking space.
    expect(find.textContaining(RegExp(r'60 min · 150\s000\sUZS')), findsOneWidget);
    await settleSnackbars(tester);

    await goTo(tester, '/venues');
    expect(find.text('Test Arena'), findsOneWidget);
    await tap(tester, find.text('Test Arena'));
    expect(find.text('Centre Court'), findsOneWidget);
  });

  testWidgets('duplicate a court', (tester) async {
    await openLochin(tester);
    expect(find.text('Court 1'), findsOneWidget);

    await tap(tester, key('court-menu-v1c1'));
    await tap(tester, find.text('Duplicate'));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Court 1 2'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('deactivate a court and see it leave the player\'s venue page', (tester) async {
    await openLochin(tester);
    expect(find.text('Inactive'), findsNothing);

    await tap(tester, key('court-menu-v1c2'));
    await tap(tester, find.text('Edit').last);
    expect(find.text('Edit court'), findsOneWidget);
    await tap(tester, key('court-active'));
    await tap(tester, key('save-court'));
    expect(find.text('Inactive'), findsOneWidget);
    await settleSnackbars(tester);

    await goTo(tester, '/venues/v1');
    expect(find.text('Court 1'), findsOneWidget);
    expect(find.text('Court 2'), findsNothing);
  });

  testWidgets('deleting a court with bookings offers to deactivate it instead', (tester) async {
    await openLochin(tester);

    // A sample game is booked on Court 1 tomorrow.
    await tap(tester, key('court-menu-v1c1'));
    await tap(tester, find.text('Delete'));
    expect(find.text('Delete “Court 1”?'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));

    expect(find.textContaining('It has bookings'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Deactivate instead'));
    expect(find.text('Court 1'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    await settleSnackbars(tester);
  });

  testWidgets('a court without bookings is deleted after confirmation', (tester) async {
    await openLochin(tester);
    await tap(tester, key('court-menu-v1c1'));
    await tap(tester, find.text('Duplicate'));
    expect(find.text('Court 1 2'), findsOneWidget);

    await tap(tester, key('court-menu-v1c3'));
    await tap(tester, find.text('Delete'));
    // Cancelling keeps it.
    await tap(tester, find.widgetWithText(TextButton, 'Cancel'));
    expect(find.text('Court 1 2'), findsOneWidget);

    await tap(tester, key('court-menu-v1c3'));
    await tap(tester, find.text('Delete'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Court 1 2'), findsNothing);
    await settleSnackbars(tester);
  });

  testWidgets('assign an owner found by search, then remove them', (tester) async {
    await openLochin(tester);
    expect(find.text('Aziz'), findsNothing);

    await tap(tester, key('assign-owner'));
    expect(find.text('Type at least 2 characters'), findsOneWidget);
    await tester.enterText(key('owner-search'), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('Nobody found'), findsOneWidget);

    await tester.enterText(key('owner-search'), 'azi');
    await tester.pumpAndSettle();
    await tap(tester, key('user-p1'));

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Aziz'), findsOneWidget);
    await settleSnackbars(tester);

    await tap(tester, key('remove-owner-p1'));
    expect(find.text('Aziz'), findsNothing);
    await settleSnackbars(tester);
  });

  testWidgets('add a sport and see it in the list, an existing id is refused', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-sports'));
    expect(find.text('Padel'), findsOneWidget);

    await tap(tester, key('add-sport'));
    expect(find.text('New sport'), findsOneWidget);
    await tester.enterText(key('sport-id'), 'padel');
    await tester.enterText(key('sport-name-en'), 'Squash');
    await tap(tester, key('save-sport'));
    expect(find.text('This ID is already taken'), findsOneWidget);

    await tester.enterText(key('sport-id'), 'Squash!');
    await tap(tester, key('save-sport'));
    expect(find.textContaining('2–30 characters'), findsOneWidget);

    await tester.enterText(key('sport-id'), 'squash');
    await tap(tester, find.text('Place only'));
    await tap(tester, key('save-sport'));
    expect(find.text('Squash'), findsOneWidget);
    // Running and gym are place-only too, so Squash is the third.
    expect(find.textContaining('Place only'), findsNWidgets(3));
    await settleSnackbars(tester);

    // Editing keeps the id and does not offer to change it.
    await tap(tester, find.text('Squash'));
    expect(find.text('Edit sport'), findsOneWidget);
    expect(key('sport-id'), findsNothing);
  });

  testWidgets('add a banner and see it on Home, then delete it', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-banners'));

    await tap(tester, key('add-banner'));
    await tester.enterText(key('banner-title-en'), 'Spring Cup');
    await tester.enterText(key('banner-url'), 'http://actra.uz');
    await tap(tester, key('save-banner'));
    expect(find.text('The link must start with https://'), findsOneWidget);

    await tester.enterText(key('banner-url'), 'https://actra.uz/cup');
    await tap(tester, key('save-banner'));
    expect(find.text('Spring Cup'), findsOneWidget);
    expect(find.textContaining('All cities'), findsWidgets);
    await settleSnackbars(tester);

    await goTo(tester, '/home');
    expect(find.text('Spring Cup'), findsOneWidget);

    await goTo(tester, '/admin/banners');
    await tap(tester, find.text('Spring Cup'));
    await tap(tester, key('delete-banner'));
    await tap(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(find.text('Spring Cup'), findsNothing);
    await settleSnackbars(tester);
  });

  test('account deletion and hidden samples read as text in the audit log', () {
    AuditEntry entry(String action, String entity) =>
        AuditEntry(id: action, action: action, entity: entity, at: DateTime.utc(2026, 11, 26));
    for (final code in ['en', 'ru', 'uz', 'kk']) {
      final l = lookupAppLocalizations(Locale(code));
      expect(auditActionText(l, entry('owner_account_deleted', 'venue')), l.auditOwnerAccountDeleted, reason: code);
      expect(auditActionText(l, entry('hide_sample', 'venue')), l.auditHideSample, reason: code);
      expect(auditActionText(l, entry('hide_sample', 'tournament')), l.auditHideSample, reason: code);
    }
  });

  test('the Review actions read as text in the audit log', () {
    AuditEntry entry(String action, String entity) =>
        AuditEntry(id: action, action: action, entity: entity, at: DateTime.utc(2026, 11, 27));
    for (final code in ['en', 'ru', 'uz', 'kk']) {
      final l = lookupAppLocalizations(Locale(code));
      for (final (action, entity, text) in [
        ('score_confirm', 'result', l.auditScoreConfirm),
        ('score_correct', 'result', l.auditScoreCorrect),
        ('score_void', 'result', l.auditScoreVoid),
        ('score_keep', 'result', l.auditScoreKeep),
        ('report_closed', 'report', l.auditReportClosed),
        ('team_deleted', 'team', l.auditTeamDeleted),
      ]) {
        expect(auditActionText(l, entry(action, entity)), text, reason: '$code $action');
        expect(text, isNot(action), reason: '$code $action');
      }
    }
  });

  testWidgets('the audit log lists the changes, newest first, with their values', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-audit'));
    expect(find.text('No changes recorded yet'), findsOneWidget);

    await goTo(tester, '/admin/sports');
    await tap(tester, key('add-sport'));
    await tester.enterText(key('sport-id'), 'squash');
    await tester.enterText(key('sport-name-en'), 'Squash');
    await tap(tester, key('save-sport'));
    await settleSnackbars(tester);

    await goTo(tester, '/admin/venues/v1');
    await tap(tester, key('court-menu-v1c1'));
    await tap(tester, find.text('Duplicate'));
    await settleSnackbars(tester);

    await goTo(tester, '/admin/audit');
    expect(find.text('Sport created'), findsOneWidget);
    expect(find.text('Court duplicated'), findsOneWidget);
    // Newest first.
    expect(
      tester.getTopLeft(find.text('Court duplicated')).dy,
      lessThan(tester.getTopLeft(find.text('Sport created')).dy),
    );

    await tap(tester, find.text('Sport created'));
    expect(find.text('AFTER'), findsOneWidget);
    expect(find.textContaining('"id": "squash"'), findsOneWidget);
  });

  testWidgets('every admin screen fits a phone', (tester) async {
    await openLochin(tester);
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();

    await tester.ensureVisible(key('court-menu-v1c1'));
    await tester.pumpAndSettle();
    await tap(tester, key('court-menu-v1c1'));
    await tap(tester, find.text('Edit').last);
    expect(find.text('Edit court'), findsOneWidget);
    await closeSheet(tester);

    await tester.ensureVisible(key('assign-owner'));
    await tester.pumpAndSettle();
    await tap(tester, key('assign-owner'));
    await tester.enterText(key('owner-search'), 'a');
    await tester.enterText(key('owner-search'), 'di');
    await tester.pumpAndSettle();
    expect(key('user-p2'), findsOneWidget);
    await closeSheet(tester);

    // A change, so the audit log has an entry to expand.
    await tester.ensureVisible(key('court-menu-v1c1'));
    await tester.pumpAndSettle();
    await tap(tester, key('court-menu-v1c1'));
    await tap(tester, find.text('Duplicate'));
    await settleSnackbars(tester);

    for (final path in ['/admin', '/admin/venues', '/admin/venues/new', '/admin/sports', '/admin/banners', '/admin/tournaments', '/admin/tournaments/new', '/admin/tournaments/t1', '/admin/tournaments/t1/participants', '/admin/dashboard', '/admin/audit']) {
      await goTo(tester, path);
    }
    await tap(tester, find.text('Court duplicated'));
    expect(find.text('AFTER'), findsOneWidget);

    await goTo(tester, '/admin/sports');
    await tap(tester, key('add-sport'));
    await closeSheet(tester);
    await goTo(tester, '/admin/banners');
    await tap(tester, key('add-banner'));
    expect(find.text('New banner'), findsOneWidget);
  });

  testWidgets('a venue named only in Kazakh saves and shows that name in English', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-venues'));
    await tap(tester, key('add-venue'));
    expect(key('venue-name-kk'), findsOneWidget);

    await tester.enterText(key('venue-name-kk'), 'Алатау Арена');
    await tap(tester, key('save-venue'));
    expect(find.text('Saved'), findsOneWidget);
    await settleSnackbars(tester);

    await goTo(tester, '/venues');
    expect(find.text('Алатау Арена'), findsOneWidget);
  });

  testWidgets('localized inputs: 2x2 grid when wide, stacked on a phone, multiline always stacked', (tester) async {
    await openAdmin(tester);
    await tap(tester, key('admin-venues'));
    await tap(tester, key('add-venue'));

    Offset at(String k) => tester.getTopLeft(key(k));
    // 900 wide: a 2x2 grid, uz | ru over kk | en.
    expect(at('venue-name-uz').dy, at('venue-name-ru').dy);
    expect(at('venue-name-kk').dy, at('venue-name-en').dy);
    expect(at('venue-name-kk').dy, greaterThan(at('venue-name-uz').dy));
    expect(at('venue-name-kk').dx, at('venue-name-uz').dx);
    expect(at('venue-name-en').dx, at('venue-name-ru').dx);
    // The description is multiline: four stacked inputs.
    final tops = [for (final c in ['uz', 'ru', 'kk', 'en']) at('venue-description-$c')];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i].dy, greaterThan(tops[i - 1].dy));
      expect(tops[i].dx, tops[0].dx);
    }

    tester.view.physicalSize = const Size(420, 3400);
    await tester.pumpAndSettle();
    final names = [for (final c in ['uz', 'ru', 'kk', 'en']) at('venue-name-$c')];
    for (var i = 1; i < names.length; i++) {
      expect(names[i].dy, greaterThan(names[i - 1].dy));
    }
  });

  testWidgets('the venue editor uses two columns on a wide screen', (tester) async {
    await openLochin(tester);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();

    final details = tester.getTopLeft(key('venue-name-en'));
    final courts = tester.getTopLeft(key('add-court'));
    expect(courts.dx, greaterThan(details.dx + 300));
  });

  testWidgets('Review names a deleted player instead of leaving a blank', (tester) async {
    SharedPreferences.setMockInitialValues(signedIn);
    final prefs = await SharedPreferences.getInstance();
    await initializeDateFormatting();
    tester.view.physicalSize = const Size(900, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final game = AdminGameNote(gameId: 'g1', sportId: 'padel', startsLocal: DateTime.utc(2026, 11, 21, 18));
    final review = AdminReview(
      disputes: [
        AdminDispute(
          result: const MatchResult(
            id: 'r1',
            status: ResultStatus.disputed,
            sets: [(6, 4)],
            winner: MatchWinner.a,
            enteredBy: 'u1',
            sideA: ['u1'],
            sideB: ['u2'],
          ),
          game: game,
          // u1's name came back empty, u2 is missing altogether.
          names: const {'u1': ''},
          disputedByName: 'Aziz',
        ),
      ],
      reports: [
        AdminReport(
          id: 'rep1',
          reporterId: 'u3',
          reporterName: '',
          targetId: 'u4',
          targetName: 'Bobur',
          reason: ReportReason.language,
          createdAt: DateTime.utc(2026, 11, 22, 8),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          adminReviewProvider.overrideWith((ref) async => review),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: buildTheme(),
          home: const AdminReviewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final board = find.byKey(const ValueKey('score-board'));
    expect(find.descendant(of: board, matching: find.text('Deleted player')), findsNWidgets(2));

    await tap(tester, find.text('Reports · 1'));
    expect(find.text('Deleted player reported Bobur'), findsOneWidget);
  });

  group('review', () {
    /// The sample backend of the running app.
    SampleBackend backendOf(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

    Future<void> openReview(WidgetTester tester) async {
      await goTo(tester, '/admin');
      await tap(tester, key('admin-review'));
      expect(find.byType(AdminReviewScreen), findsOneWidget);
    }

    testWidgets('the admin home counts what waits for review', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await goTo(tester, '/admin');
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Nothing waiting'), findsOneWidget);

      final backend = backendOf(tester);
      await backend.disputeScoreAs('p2', 'r-gf2');
      await backend.reportPlayerAs('p1', 'p3', reason: ReportReason.language);
      containerOf(tester).invalidate(adminReviewProvider);
      await tester.pumpAndSettle();
      expect(find.text('2 open'), findsOneWidget);
    });

    testWidgets('admin confirms a disputed score', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.disputeScoreAs('p2', 'r-gf2', reason: 'We won the second set');
      await openReview(tester);

      expect(find.byKey(const ValueKey('score-board')), findsOneWidget);
      expect(find.textContaining('We won the second set'), findsOneWidget);
      expect(key('review-keep-r-gf2'), findsNothing, reason: 'keep is for a flagged score');
      expect(key('review-correct-r-gf2'), findsOneWidget);

      await tap(tester, key('review-confirm-r-gf2'));
      expect(find.text('Confirm this score?'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect((await backend.game('gf2')).result!.status, ResultStatus.disputed, reason: 'cancelled');

      await tap(tester, key('review-confirm-r-gf2'));
      await tap(tester, key('review-dialog-ok'));
      expect((await backend.game('gf2')).result!.status, ResultStatus.confirmed);
      expect(key('review-score-r-gf2'), findsNothing);
      expect(find.text('No scores to review'), findsOneWidget);
      expect((await backend.admin.auditLog()).first.action, 'score_confirm');
    });

    testWidgets('admin corrects a disputed score with the set editor', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.disputeScoreAs('p2', 'r-gf2');
      await openReview(tester);

      await tap(tester, key('review-correct-r-gf2'));
      expect(find.text('Correct the score'), findsOneWidget);
      // The entered score, 6–3 6–4, is the start; the first set was 6–4.
      expect(tester.widget<Text>(key('set-0-mine')).data, '6');
      expect(tester.widget<Text>(key('set-0-theirs')).data, '3');
      await tap(tester, key('set-0-theirs-plus'));
      await tap(tester, key('review-correct-save'));

      final result = (await backend.game('gf2')).result!;
      expect(result.status, ResultStatus.confirmed);
      expect(result.sets, const [(6, 4), (6, 4)]);
      expect(find.text('No scores to review'), findsOneWidget);
    });

    testWidgets('admin voids a disputed score', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.disputeScoreAs('p2', 'r-gf2');
      await openReview(tester);
      await tap(tester, key('review-void-r-gf2'));
      expect(find.text('Void this score?'), findsOneWidget);
      await tap(tester, key('review-dialog-ok'));
      expect((await backend.game('gf2')).result!.status, ResultStatus.voided);
      expect(find.text('No scores to review'), findsOneWidget);
    });

    testWidgets('a flagged confirmed score offers Keep and Void, not Confirm', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.confirmScoreAs(kMeId, 'r-gf2');
      await backend.reportNoShowAs('p1', 'gf2', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf2', 'p3', reported: true);
      expect((await backend.game('gf2')).result!.flaggedNoShow, isTrue);
      await openReview(tester);

      expect(find.text('Flagged: no-show'), findsOneWidget);
      expect(key('review-confirm-r-gf2'), findsNothing);
      expect(key('review-correct-r-gf2'), findsNothing);
      await tap(tester, key('review-keep-r-gf2'));
      expect(find.text('Keep this score?'), findsOneWidget);
      await tap(tester, key('review-dialog-ok'));
      final result = (await backend.game('gf2')).result!;
      expect(result.status, ResultStatus.confirmed);
      expect(result.flaggedNoShow, isFalse);
      expect(find.text('No scores to review'), findsOneWidget);
    });

    testWidgets('a no-show freeze reads as one', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.reportNoShowAs('p1', 'gf2', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf2', 'p3', reported: true);
      await openReview(tester);
      expect(find.text('Frozen: no-show'), findsOneWidget);
      expect(key('review-confirm-r-gf2'), findsOneWidget);
    });

    testWidgets('admin closes a report with a note', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.reportPlayerAs('p1', 'p3', reason: ReportReason.language, details: 'Shouted at everyone');
      final id = (await backend.admin.review()).reports.single.id;
      await openReview(tester);
      expect(find.text('No scores to review'), findsOneWidget);

      await tap(tester, key('review-tab-reports'));
      expect(key('review-report-$id'), findsOneWidget);
      expect(find.text('Abusive language'), findsOneWidget);
      expect(find.text('Shouted at everyone'), findsOneWidget);
      expect(key('review-void-score-$id'), findsNothing, reason: 'not about a game');

      await tap(tester, key('review-close-$id'));
      await tester.enterText(key('review-note'), 'Warned them');
      expect(find.descendant(of: key('review-close-save'), matching: find.text('Close report')), findsOneWidget);
      await tap(tester, key('review-close-save'));
      expect(key('review-report-$id'), findsNothing);
      expect(find.text('No open reports'), findsOneWidget);
      final entry = (await backend.admin.auditLog()).first;
      expect((entry.action, entry.after!['admin_note']), ('report_closed', 'Warned them'));
    });

    testWidgets('a report about a game shows its score, which the admin can void', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.reportPlayerAs('p2', 'p1', gameId: 'gf2', reason: ReportReason.falseScore);
      final id = (await backend.admin.review()).reports.single.id;
      await openReview(tester);
      await tap(tester, key('review-tab-reports'));

      expect(find.text('Score: 6–3, 6–4'), findsOneWidget);
      await tap(tester, key('review-void-score-$id'));
      expect(find.text('Void this score?'), findsOneWidget);
      await tap(tester, key('review-dialog-ok'));
      expect((await backend.game('gf2')).result!.status, ResultStatus.voided);
      // The report stays open; it just no longer offers the score.
      expect(key('review-report-$id'), findsOneWidget);
      expect(find.textContaining('Score:'), findsNothing);
      expect(key('review-void-score-$id'), findsNothing);
    });

    testWidgets('the review fits a phone, with its sheets', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.disputeScoreAs('p2', 'r-gf2', reason: 'We won the second set and the third, the score is wrong');
      await backend.reportPlayerAs('p2', 'p1', gameId: 'gf2', reason: ReportReason.aggression, details: 'x' * 300);
      await openReview(tester);
      tester.view.physicalSize = const Size(375, 812);
      await tester.pumpAndSettle();

      await tap(tester, key('review-correct-r-gf2'));
      await tap(tester, key('set-0-mine-plus'));
      await closeSheet(tester);
      await tap(tester, key('review-tab-reports'));
      await tap(tester, key('review-close-ar1'));
      await closeSheet(tester);
    });

    testWidgets('the reported player opens their profile', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = backendOf(tester);
      await backend.reportPlayerAs('p1', 'p3', reason: ReportReason.other);
      final id = (await backend.admin.review()).reports.single.id;
      await openReview(tester);
      await tap(tester, key('review-tab-reports'));
      await tap(tester, key('review-target-$id'));
      expect(find.byType(PlayerProfileScreen), findsOneWidget);
    });
  });

  testWidgets('the admin screens read in Russian and Uzbek', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'ru'}, utcNow: sundayMorning);
    await goTo(tester, '/admin');
    expect(find.text('Журнал изменений'), findsOneWidget);
    expect(find.text('6 площадок'), findsOneWidget);

    await tap(tester, key('admin-venues'));
    expect(find.text('Добавить площадку'), findsOneWidget);
  });

  testWidgets('the admin home reads in Uzbek', (tester) async {
    await pumpApp(tester, prefs: {...signedIn, 'lang': 'uz'}, utcNow: sundayMorning);
    await goTo(tester, '/admin');
    expect(find.text('Oʻzgarishlar jurnali'), findsOneWidget);
    expect(find.text('6 ta maydon'), findsOneWidget);
  });
}
