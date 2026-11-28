// M8a final review (app side): another account's data never comes back on a
// page opened again after its loads failed (A1), sheets close on an account
// change, a locked category offers no Register or Cancel even as a redone
// draft (A2), a withdrawn entry cannot be picked as a winner (A3), a venue or
// entries load error offers Try again (A4), and a refused organiser call says
// so (A5).

import 'package:actra/core/localized_text.dart';
import 'package:actra/data/organizer_repository.dart';
import 'package:actra/data/repositories.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/brackets.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/teams.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../admin_flow_test.dart' show key;
import '../app_flow_test.dart';
import '../games_host_flow_test.dart' show containerOf;

/// The sample backend, with switches for what fails.
class _Backend extends SampleBackend {
  _Backend({required super.utcNow, this.offline = false, this.venueFails = false}) : super(meName: 'Test');

  /// The tournament page, brackets, my entries and matches, the organiser's
  /// lists and a team page fail to load.
  final bool offline;

  /// The venue (its courts and hours) fails to load.
  bool venueFails;

  /// The organiser's entry list is refused with this.
  TournamentError? entriesError;

  /// Brackets as this (plain) player sees them, instead of the demo admin.
  String? bracketsAs;

  void _check() {
    if (offline) throw const TournamentException(TournamentError.unavailable);
  }

  @override
  Future<Venue> venue(String id) async {
    if (venueFails) throw StateError('venue offline');
    return super.venue(id);
  }

  @override
  Future<Team> team(String id) async {
    if (offline) throw const JoinException(JoinError.unavailable);
    return super.team(id);
  }

  @override
  TournamentRepository get tournament => _tournaments ??= _Tournaments(super.tournament, this);
  TournamentRepository? _tournaments;

  @override
  OrganizerRepository get organizer => _organizer ??= _Organizer(super.organizer, this);
  OrganizerRepository? _organizer;
}

class _Tournaments implements TournamentRepository {
  _Tournaments(this._inner, this._owner);

  final TournamentRepository _inner;
  final _Backend _owner;

  @override
  Future<Tournament> get(String id) async {
    _owner._check();
    return _inner.get(id);
  }

  @override
  Future<TournamentBracket> bracket(String tournamentId) async {
    _owner._check();
    final as = _owner.bracketsAs;
    return as == null ? _inner.bracket(tournamentId) : _owner.bracketAs(as, tournamentId);
  }

  @override
  Future<List<Registration>> myRegistrations() async {
    _owner._check();
    return _inner.myRegistrations();
  }

  @override
  Future<List<MyMatch>> myMatches() async {
    _owner._check();
    return _inner.myMatches();
  }

  @override
  Future<List<Tournament>> list(
    String cityId, {
    String? sportId,
    DateTime? from,
    TournamentSort sort = TournamentSort.date,
  }) => _inner.list(cityId, sportId: sportId, from: from, sort: sort);
  @override
  Future<Registration> register(String categoryId, {String? partnerId}) =>
      _inner.register(categoryId, partnerId: partnerId);
  @override
  Future<Registration> respondPartner(String registrationId, {required bool accept}) =>
      _inner.respondPartner(registrationId, accept: accept);
  @override
  Future<Registration> cancel(String registrationId) => _inner.cancel(registrationId);
  @override
  Future<Registration> joinWaitlist(String categoryId, {String? partnerId}) =>
      _inner.joinWaitlist(categoryId, partnerId: partnerId);
  @override
  Future<Registration> claimOffer(String registrationId) => _inner.claimOffer(registrationId);
  @override
  Future<PlayerRef?> findPlayerByPhone(String phone) => _inner.findPlayerByPhone(phone);
}

class _Organizer implements OrganizerRepository {
  _Organizer(this._inner, this._owner);

  final OrganizerRepository _inner;
  final _Backend _owner;

  @override
  Future<List<TournamentSummary>> organizedTournaments() async {
    _owner._check();
    return _inner.organizedTournaments();
  }

  @override
  Future<List<AdminRegistration>> entries(String tournamentId) async {
    _owner._check();
    if (_owner.entriesError case final error?) throw TournamentException(error);
    return _inner.entries(tournamentId);
  }

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

const _error = 'Something went wrong. Try again.';
const _t1 = 'Tashkent Padel Cup';

_Backend _backend(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider) as _Backend;

Future<void> _go(WidgetTester tester, String location) async {
  containerOf(tester).read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

/// The app as 'Test'; every account signed in after it is offline.
Future<void> _pumpThenOffline(WidgetTester tester) async {
  var built = 0;
  await pumpApp(
    tester,
    prefs: signedIn,
    utcNow: sundayMorning,
    backend: (clock) => _Backend(utcNow: clock, offline: built++ > 0),
  );
}

Future<void> _switchAccount(WidgetTester tester) async {
  await containerOf(tester).read(sessionProvider.notifier).signIn('Other');
  await tester.pumpAndSettle();
}

TournamentMatch _ko(CategoryDraw d, int round, int position) =>
    d.matches.firstWhere((m) => m.stage == MatchStage.knockout && m.round == round && m.position == position);

void main() {
  group('A1: leave and reopen while offline after an account switch', () {
    testWidgets("the tournament page never shows the previous account's tournament or Manage", (tester) async {
      await _pumpThenOffline(tester);
      await _go(tester, '/tournaments/t1');
      expect(find.text(_t1), findsOneWidget);
      expect(key('tournament-manage'), findsOneWidget);

      await _switchAccount(tester);
      expect(find.text(_t1), findsNothing);

      await _go(tester, '/tournaments');
      await _go(tester, '/tournaments/t1');
      expect(find.text(_t1), findsNothing);
      expect(key('tournament-manage'), findsNothing);
      expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
    });

    testWidgets("the manager never shows the previous account's tournament, entries or draws", (tester) async {
      await _pumpThenOffline(tester);
      await _go(tester, '/tournaments/t1/manage');
      expect(key('entries-count'), findsOneWidget);
      expect(find.text(_t1), findsOneWidget);
      await tap(tester, key('manage-category-t1c2'));
      expect(key('draw-status-published'), findsOneWidget);

      await _switchAccount(tester);
      // Left within the Tournaments tab, so the manager is built afresh.
      await _go(tester, '/tournaments');
      await _go(tester, '/tournaments/t1/manage');
      expect(key('tournament-manage-screen'), findsOneWidget);
      expect(find.text(_t1), findsNothing);
      expect(key('entries-count'), findsNothing);
      expect(key('draw-status-published'), findsNothing);
      await tap(tester, key('manage-tab-scores'));
      expect(find.byKey(const ValueKey('manage-scores')), findsOneWidget);
      expect(find.textContaining('Bekzod'), findsNothing);
    });

    testWidgets("My tournaments, then the tournament: never the previous account's Manage", (tester) async {
      await _pumpThenOffline(tester);
      await _go(tester, '/my-tournaments');
      await _go(tester, '/tournaments/t1');
      expect(key('tournament-manage'), findsOneWidget);

      await _switchAccount(tester);
      await _go(tester, '/my-tournaments');
      await _go(tester, '/tournaments/t1');
      expect(key('tournament-manage'), findsNothing);
      expect(find.text(_t1), findsNothing);
    });

    testWidgets("a team page (M7) never shows the previous account's team", (tester) async {
      await _pumpThenOffline(tester);
      await _go(tester, '/teams/tm1');
      expect(find.text('Yunusobod Padel'), findsWidgets);

      await _switchAccount(tester);
      await _go(tester, '/home');
      await _go(tester, '/teams/tm1');
      expect(find.text('Yunusobod Padel'), findsNothing);
      expect(find.text(_error), findsOneWidget);
    });

    testWidgets('an open score sheet closes when the account changes', (tester) async {
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Backend(utcNow: clock),
      );
      final d = (await _backend(tester).tournament.bracket('t1')).draw('t1c2')!;
      final sf1 = _ko(d, 2, 1);
      await _go(tester, '/tournaments/t1/manage');
      await tap(tester, key('manage-tab-scores'));
      await tap(tester, key('score-match-${sf1.id}'));
      expect(key('match-score-save'), findsOneWidget);

      await _switchAccount(tester);
      expect(key('match-score-save'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('A2: a locked category from the bracket', () {
    testWidgets('a redone draft, as a plain player: no Register and no Cancel', (tester) async {
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Backend(utcNow: clock),
      );
      final backend = _backend(tester);
      final t = await backend.admin.saveTournament(
        TournamentDraft(
          cityId: 'tashkent',
          sportId: 'padel',
          venueId: 'v1',
          start: DateTime.utc(2026, 12, 10),
          end: DateTime.utc(2026, 12, 10),
          title: const LocalizedText.all('Lock Cup'),
          categories: [
            CategoryDraft(name: const LocalizedText.all('Mine'), cap: 16),
            CategoryDraft(name: const LocalizedText.all('Theirs'), cap: 16),
            CategoryDraft(name: const LocalizedText.all('Open'), cap: 16),
          ],
        ),
      );
      final (mine, theirs, open) = ('${t}c1', '${t}c2', '${t}c3');
      for (final p in [kMeId, 'p1', 'p2', 'p3']) {
        await backend.admin.addRegistration(mine, p);
      }
      for (final p in ['p4', 'p5']) {
        await backend.admin.addRegistration(theirs, p);
      }
      for (final c in [mine, theirs]) {
        await backend.organizer.makeDraw(c, DrawFormat.knockout);
        await backend.organizer.publish(c);
        await backend.organizer.redo(c);
      }
      backend.bracketsAs = 'p6';

      await _go(tester, '/tournaments/$t');
      expect(find.text('Lock Cup'), findsWidgets);
      Finder inCategory(String id, Finder f) => find.descendant(of: key('category-$id'), matching: f);
      expect(inCategory(mine, find.text('Cancel registration')), findsNothing);
      expect(inCategory(mine, find.text('Register')), findsNothing);
      expect(inCategory(theirs, find.text('Register')), findsNothing);
      expect(inCategory(theirs, find.text('Join waitlist')), findsNothing);
      // An open category still offers Register.
      expect(inCategory(open, find.text('Register')), findsOneWidget);
      // Nothing of the drafts shows to a player.
      expect(key('tournament-manage'), findsNothing);
    });
  });

  group('A3–A5: the manager', () {
    testWidgets("a withdrawn entry's chip cannot be picked as the winner", (tester) async {
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Backend(utcNow: clock),
      );
      final backend = _backend(tester);
      var d = (await backend.tournament.bracket('t1')).draw('t1c2')!;
      final sf1 = _ko(d, 2, 1);
      d = await backend.organizer.withdraw(sf1.sideA!);
      expect(_ko(d, 2, 1).outcome, MatchOutcome.walkover);

      await _go(tester, '/tournaments/t1/manage');
      await tap(tester, key('manage-tab-scores'));
      await tap(tester, key('score-match-${sf1.id}'));
      final a = tester.widget<ChoiceChip>(key('winner-a'));
      final b = tester.widget<ChoiceChip>(key('winner-b'));
      expect(a.onSelected, isNull, reason: 'withdrawn');
      expect(b.onSelected, isNotNull);
      expect(b.selected, isTrue);
    });

    testWidgets('a venue that fails to load offers Try again in the match-time and fill-day sheets', (tester) async {
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Backend(utcNow: clock, venueFails: true),
      );
      final backend = _backend(tester);
      final d = (await backend.tournament.bracket('t1')).draw('t1c2')!;
      final finalMatch = _ko(d, 3, 1);
      await _go(tester, '/tournaments/t1/manage');
      await tap(tester, key('manage-tab-schedule'));

      Finder keyed(String prefix) =>
          find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith(prefix));

      // Fill the day, with the venue never loaded: no endless progress bar.
      await tap(tester, key('fill-day'));
      expect(key('venue-retry'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      backend.venueFails = false;
      await tap(tester, key('venue-retry'));
      expect(key('venue-retry'), findsNothing);
      expect(keyed('fill-from-'), findsWidgets);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // The match-time sheet, with the venue failing to load again.
      backend.venueFails = true;
      containerOf(tester).invalidate(venueProvider);
      await tester.pumpAndSettle();
      await tap(tester, key('schedule-match-${finalMatch.id}'));
      expect(key('venue-retry'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      backend.venueFails = false;
      await tap(tester, key('venue-retry'));
      expect(key('venue-retry'), findsNothing);
      expect(keyed('sheet-slot-'), findsWidgets);
    });

    testWidgets("the Draw tab's entries error says why and offers Try again", (tester) async {
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Backend(utcNow: clock),
      );
      final backend = _backend(tester)..entriesError = TournamentError.unavailable;
      await _go(tester, '/tournaments/t1/manage');
      expect(key('entries-count'), findsNothing);
      expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
      backend.entriesError = null;
      await tap(tester, key('entries-retry'));
      expect(key('entries-count'), findsOneWidget);
    });

    testWidgets("a refused organiser call says only the tournament's organisers may", (tester) async {
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Backend(utcNow: clock),
      );
      _backend(tester).entriesError = TournamentError.notAllowed;
      await _go(tester, '/tournaments/t1/manage');
      expect(find.text("Only this tournament's organisers can open this page"), findsOneWidget);
      expect(find.text('Only Actra administrators can open this page'), findsNothing);
    });
  });
}
