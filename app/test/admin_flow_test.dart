import 'package:actra/app.dart';
import 'package:actra/data/admin_repository.dart';
import 'package:actra/features/admin/admin_home_screen.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/state/admin_providers.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_flow_test.dart';

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

    for (final path in ['/admin', '/admin/venues', '/admin/venues/v1', '/admin/sports', '/admin/banners', '/admin/audit']) {
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

    for (final path in ['/admin', '/admin/venues', '/admin/venues/new', '/admin/sports', '/admin/banners', '/admin/audit']) {
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

  testWidgets('the venue editor uses two columns on a wide screen', (tester) async {
    await openLochin(tester);
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();

    final details = tester.getTopLeft(key('venue-name-en'));
    final courts = tester.getTopLeft(key('add-court'));
    expect(courts.dx, greaterThan(details.dx + 300));
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
