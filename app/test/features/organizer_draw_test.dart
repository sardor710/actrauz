import 'dart:async';

import 'package:actra/data/organizer_repository.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/brackets.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_flow_test.dart' show key, openAdmin;
import '../app_flow_test.dart';
import '../games_host_flow_test.dart' show containerOf;

SampleBackend _backend(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

Future<void> _go(WidgetTester tester, String location) async {
  containerOf(tester).read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

/// Eight singles entries in Almaty Open Tennis's open singles (t3c1), which
/// has no draw yet.
Future<void> _eightEntries(WidgetTester tester) async {
  final admin = _backend(tester).admin;
  for (var i = 1; i <= 8; i++) {
    await admin.addRegistration('t3c1', 'p$i');
  }
}

/// The manager of t3 on the open singles.
Future<void> _openManager(WidgetTester tester) async {
  await _go(tester, '/tournaments/t3/manage');
  expect(key('tournament-manage-screen'), findsOneWidget);
  await tap(tester, key('manage-category-t3c1'));
}

Future<void> _makeDraw(WidgetTester tester, {bool groups = false}) async {
  if (groups) {
    await tap(tester, key('format-groups'));
    await tap(tester, key('group-size-4'));
    await tap(tester, key('advance-2'));
  }
  await tester.ensureVisible(key('make-draw'));
  await tap(tester, key('make-draw'));
}

Future<CategoryDraw> _draw(WidgetTester tester, String categoryId) async =>
    (await _backend(tester).tournament.bracket(categoryId.substring(0, 2))).draw(categoryId)!;

/// Reloads everything the manager shows, as coming back to the app does.
Future<void> _reload(WidgetTester tester) async {
  final c = containerOf(tester);
  c.invalidate(bracketProvider);
  c.invalidate(organizerEntriesProvider);
  await tester.pumpAndSettle();
}

// ---- An organiser repository whose loads can fail, for account switches ----

class _FlakyOrganizer implements OrganizerRepository {
  _FlakyOrganizer(this._inner, this._owner);

  final OrganizerRepository _inner;
  final _Flaky _owner;

  @override
  Future<List<TournamentSummary>> organizedTournaments() async {
    await _owner.gate?.future;
    if (_owner.offline) throw const TournamentException(TournamentError.unavailable);
    return _inner.organizedTournaments();
  }

  @override
  Future<List<AdminRegistration>> entries(String tournamentId) => _inner.entries(tournamentId);
  @override
  Future<CategoryDraw> makeDraw(String categoryId, DrawFormat format, {int? groupSize, int? advance}) =>
      _inner.makeDraw(categoryId, format, groupSize: groupSize, advance: advance);
  @override
  Future<CategoryDraw> swapEntries(String categoryId, String registrationA, String registrationB) =>
      _inner.swapEntries(categoryId, registrationA, registrationB);
  @override
  Future<CategoryDraw> publish(String categoryId) => _inner.publish(categoryId);
  @override
  Future<CategoryDraw> redo(String categoryId) => _inner.redo(categoryId);
  @override
  Future<TournamentMatch> scheduleMatch(String matchId, {String? courtId, DateTime? startsAt, String? placeNote}) =>
      _inner.scheduleMatch(matchId, courtId: courtId, startsAt: startsAt, placeNote: placeNote);
  @override
  Future<FillResult> fillDay(
    String tournamentId,
    DateTime day,
    List<String> courtIds,
    TimeOfDay from, {
    List<String>? categoryIds,
  }) => _inner.fillDay(tournamentId, day, courtIds, from, categoryIds: categoryIds);
  @override
  Future<CategoryDraw> enterScore(String matchId, MatchOutcome outcome, {Side? winner, List<List<int>>? sets}) =>
      _inner.enterScore(matchId, outcome, winner: winner, sets: sets);
  @override
  Future<CategoryDraw> withdraw(String registrationId) => _inner.withdraw(registrationId);
}

class _Flaky extends SampleBackend {
  _Flaky({required super.utcNow}) : super(meName: 'Test');

  bool offline = false;

  /// "Tournaments I run" waits for it (and then fails while [offline]).
  Completer<void>? gate;

  @override
  OrganizerRepository get organizer => _flaky ??= _FlakyOrganizer(super.organizer, this);
  OrganizerRepository? _flaky;
}

void main() {
  group('organisers on the tournament editor', () {
    testWidgets('an admin adds an organiser by phone and removes them', (tester) async {
      await openAdmin(tester);
      await _go(tester, '/admin/tournaments/t3');
      await tester.ensureVisible(key('add-organizer'));
      expect(find.text('No organisers yet'), findsOneWidget);

      await tap(tester, key('add-organizer'));
      await tap(tester, find.text('Phone number'));
      await tester.enterText(key('partner-phone'), '+998 90 100 00 01');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Find'));
      expect(find.text('Aziz'), findsOneWidget);
      await tap(tester, key('pick-player-ok'));
      await settleSnackbars(tester);

      expect(key('organizer-p1'), findsOneWidget);
      expect((await _backend(tester).admin.organizers('t3')).map((p) => p.id), ['p1']);
      // Aziz hears about it.
      expect(await _backend(tester).organizerAs('p1').organizedTournaments(), isNotEmpty);

      await tester.ensureVisible(key('remove-organizer-p1'));
      await tap(tester, key('remove-organizer-p1'));
      await settleSnackbars(tester);
      expect(key('organizer-p1'), findsNothing);
      expect(await _backend(tester).admin.organizers('t3'), isEmpty);
    });

    testWidgets('adding needs a player picked first', (tester) async {
      await openAdmin(tester);
      await _go(tester, '/admin/tournaments/t3');
      await tester.ensureVisible(key('add-organizer'));
      await tap(tester, key('add-organizer'));
      await tap(tester, key('pick-player-ok'));
      expect(find.text('Choose a player first'), findsOneWidget);
      expect(await _backend(tester).admin.organizers('t3'), isEmpty);
    });
  });

  group('Tournaments I run', () {
    testWidgets('shows for an organiser and opens the manager', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _go(tester, '/profile');
      await tap(tester, key('profile-organizing'));
      expect(find.text('Tournaments I run'), findsOneWidget);
      await tap(tester, key('organized-t1'));
      expect(key('tournament-manage-screen'), findsOneWidget);
      // Men's pairs: the published bracket.
      await tap(tester, key('manage-category-t1c2'));
      expect(key('draw-status-published'), findsOneWidget);
    });

    testWidgets('is not shown to someone who runs none', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _backend(tester).admin.setOrganizer('t1', kMeId, add: false);
      await _go(tester, '/profile');
      expect(key('profile-organizing'), findsNothing);
    });

    testWidgets("another account never sees the previous one's row, even when its load fails", (tester) async {
      final gate = Completer<void>();
      final backends = <_Flaky>[];
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) {
          final b = _Flaky(utcNow: clock)..gate = backends.isEmpty ? null : gate;
          backends.add(b);
          return b;
        },
      );
      await _go(tester, '/profile');
      expect(key('profile-organizing'), findsOneWidget);

      await containerOf(tester).read(sessionProvider.notifier).signIn('Other');
      await tester.pump();
      expect(key('profile-organizing'), findsNothing);
      backends.last.offline = true;
      gate.complete();
      await tester.pumpAndSettle();
      expect(key('profile-organizing'), findsNothing);
    });
  });

  group('the draw manager', () {
    testWidgets('lists the entries with names, phones and paid', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      expect(find.text('8 entries'), findsOneWidget);
      await tap(tester, key('entries-toggle'));
      expect(find.text('Aziz'), findsOneWidget);
      expect(find.text('+998901000001'), findsOneWidget);
      expect(find.text('Not paid'), findsNWidgets(8));
    });

    testWidgets('a groups draw of size 4 with 2 advancing shows groups A and B', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      expect(key('draw-status-none'), findsOneWidget);
      await _makeDraw(tester, groups: true);

      expect(key('draw-status-draft'), findsOneWidget);
      expect(find.text('Group A'), findsOneWidget);
      expect(find.text('Group B'), findsOneWidget);
      final draw = await _draw(tester, 't3c1');
      expect(draw.format, DrawFormat.groups);
      expect(draw.groupSize, 4);
      expect(draw.advance, 2);
      expect(draw.published, isFalse);
    });

    testWidgets('too few entries says so', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _backend(tester).admin.addRegistration('t3c1', 'p1');
      await _openManager(tester);
      await _makeDraw(tester);
      expect(find.text('Not enough registered entries for this format'), findsOneWidget);
      expect(key('draw-status-none'), findsOneWidget);
      await settleSnackbars(tester);
    });

    testWidgets('tapping two entries of a draft swaps them', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      await _makeDraw(tester, groups: true);

      final before = await _draw(tester, 't3c1');
      final a = before.groups[0].standings.first.registrationId;
      final b = before.groups[1].standings.first.registrationId;
      final groupA = before.entry(a).groupId;
      final groupB = before.entry(b).groupId;

      await tester.ensureVisible(key('draft-entry-$a'));
      await tap(tester, key('draft-entry-$a'));
      expect(key('draft-selected-$a'), findsOneWidget);
      await tester.ensureVisible(key('draft-entry-$b'));
      await tap(tester, key('draft-entry-$b'));

      final after = await _draw(tester, 't3c1');
      expect(after.entry(a).groupId, groupB);
      expect(after.entry(b).groupId, groupA);
      expect(key('draft-selected-$a'), findsNothing);
      // The preview follows: a is now listed in the second group.
      expect(
        find.descendant(of: key('draft-group-$groupB'), matching: key('draft-entry-$a')),
        findsOneWidget,
      );
    });

    testWidgets('an out-of-date draft shows the banner and cannot be published', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      await _makeDraw(tester);
      expect(key('draw-outdated'), findsNothing);

      // Another entry arrives after the draft.
      await _backend(tester).admin.addRegistration('t3c1', kMeId);
      await _reload(tester);

      expect(key('draw-outdated'), findsOneWidget);
      expect(find.text('Out of date — make the draw again'), findsOneWidget);
      await tester.ensureVisible(key('publish-draw'));
      expect(tester.widget<FilledButton>(key('publish-draw')).onPressed, isNull);

      // Making it again clears it.
      await _makeDraw(tester);
      expect(key('draw-outdated'), findsNothing);
      expect(find.text('9 entries'), findsOneWidget);
    });

    testWidgets('publish asks first, then locks the entries', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      await _makeDraw(tester);

      await tester.ensureVisible(key('publish-draw'));
      await tap(tester, key('publish-draw'));
      expect(find.text('Publish the draw?'), findsOneWidget);
      expect(find.textContaining('Entries lock and the waitlist closes'), findsOneWidget);
      // Cancel leaves it a draft.
      await tap(tester, find.text('Cancel'));
      expect((await _draw(tester, 't3c1')).published, isFalse);

      await tap(tester, key('publish-draw'));
      await tap(tester, key('confirm-dialog-ok'));

      expect((await _draw(tester, 't3c1')).published, isTrue);
      expect(key('draw-status-published'), findsOneWidget);
      expect(find.text('Published: entries are locked'), findsOneWidget);
      expect(key('publish-draw'), findsNothing);
      expect(key('make-draw'), findsNothing);
      // Locked: nobody more gets in.
      await expectLater(
        _backend(tester).admin.addRegistration('t3c1', kMeId),
        throwsA(isA<TournamentException>().having((e) => e.error, 'error', TournamentError.drawPublished)),
      );
    });

    testWidgets('redo before a score makes a new draft', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      await _makeDraw(tester);
      await tester.ensureVisible(key('publish-draw'));
      await tap(tester, key('publish-draw'));
      await tap(tester, key('confirm-dialog-ok'));

      await tester.ensureVisible(key('redo-draw'));
      await tap(tester, key('redo-draw'));
      expect(find.text('Redo the draw?'), findsOneWidget);
      await tap(tester, key('confirm-dialog-ok'));
      expect((await _draw(tester, 't3c1')).published, isFalse);
      expect(key('draw-status-draft'), findsOneWidget);
    });

    testWidgets('redo after a score says the draw is final', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _eightEntries(tester);
      await _openManager(tester);
      await _makeDraw(tester);
      await tester.ensureVisible(key('publish-draw'));
      await tap(tester, key('publish-draw'));
      await tap(tester, key('confirm-dialog-ok'));

      // A score is entered elsewhere meanwhile.
      final ready = (await _draw(tester, 't3c1')).matches.firstWhere((m) => m.status == MatchStatus.ready);
      await _backend(tester).organizer.enterScore(
        ready.id,
        MatchOutcome.played,
        sets: const [
          [6, 3],
          [6, 4],
        ],
      );

      await tester.ensureVisible(key('redo-draw'));
      await tap(tester, key('redo-draw'));
      await tap(tester, key('confirm-dialog-ok'));
      expect(find.text('A score has been entered: the draw can no longer be redone'), findsOneWidget);
      expect((await _draw(tester, 't3c1')).published, isTrue);
      // The reload knows: no Redo any more.
      expect(key('redo-draw'), findsNothing);
      await settleSnackbars(tester);
    });

    testWidgets('Schedule and Scores are tabs of their own', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _go(tester, '/tournaments/t1/manage');
      expect(find.text('Draw'), findsWidgets);
      await tap(tester, key('manage-tab-schedule'));
      expect(key('manage-schedule'), findsOneWidget);
      await tap(tester, key('manage-tab-scores'));
      expect(key('manage-scores'), findsOneWidget);
    });
  });

  group('fits a phone', () {
    for (final lang in ['uz', 'ru', 'kk']) {
      testWidgets('the manager with a groups draft, the entries and the organisers in $lang', (tester) async {
        await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
        tester.view.physicalSize = const Size(360, 2400);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpAndSettle();
        await _eightEntries(tester);
        await _backend(tester).admin.setOrganizer('t3', 'p1', add: true);

        await _openManager(tester);
        await tap(tester, key('format-groups'));
        expect(tester.takeException(), isNull);
        await _makeDraw(tester, groups: true);
        await tester.ensureVisible(key('entries-toggle'));
        await tap(tester, key('entries-toggle'));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(key('publish-draw'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await _go(tester, '/organizing');
        expect(tester.takeException(), isNull);

        await _go(tester, '/admin/tournaments/t3');
        await tester.ensureVisible(key('add-organizer'));
        await tester.pumpAndSettle();
        expect(key('organizer-p1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
