import 'dart:async';

import 'package:actra/core/localized_text.dart';
import 'package:actra/core/theme.dart';
import 'package:actra/data/repositories.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/brackets.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:actra/features/inbox/inbox_screen.dart';
import 'package:actra/features/tournaments/bracket_view.dart';
import 'package:actra/features/tournaments/group_table.dart';
import 'package:actra/features/tournaments/next_match_card.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:actra/router.dart';
import 'package:actra/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../app_flow_test.dart';
import '../games_host_flow_test.dart' show containerOf;

// ---- Hand-built draws ----

DrawEntry _entry(int seed, {String? groupId, List<PlayerRef>? players}) => DrawEntry(
  registrationId: 'e$seed',
  seed: seed,
  strength: 0,
  groupId: groupId,
  players: players ?? [PlayerRef(id: 'u$seed', name: 'Player$seed')],
);

TournamentMatch _ko(
  String id,
  int round,
  int position, {
  String? a,
  String? b,
  bool aEmpty = false,
  bool bEmpty = false,
  MatchStatus status = MatchStatus.waiting,
  MatchOutcome? outcome,
  Side? winner,
  List<List<int>>? sets,
  String? courtName,
  DateTime? startsAt,
  String? placeNote,
}) => TournamentMatch(
  id: id,
  stage: MatchStage.knockout,
  round: round,
  position: position,
  status: status,
  sideA: a,
  sideB: b,
  aEmpty: aEmpty,
  bEmpty: bEmpty,
  outcome: outcome,
  winner: winner,
  sets: sets,
  courtId: courtName == null ? null : 'c-$courtName',
  courtName: courtName == null ? null : LocalizedText.all(courtName),
  startsAt: startsAt,
  placeNote: placeNote,
);

TournamentMatch _played(String id, int round, int position, String a, String b, Side winner, List<List<int>> sets) =>
    _ko(
      id,
      round,
      position,
      a: a,
      b: b,
      status: MatchStatus.done,
      outcome: MatchOutcome.played,
      winner: winner,
      sets: sets,
    );

/// An 8-entry knockout: quarter-finals played, semi-finals ready, final waiting.
CategoryDraw eightDraw({bool finished = false}) => CategoryDraw(
  categoryId: 'k8',
  format: DrawFormat.knockout,
  published: true,
  entries: [for (var s = 1; s <= 8; s++) _entry(s)],
  matches: [
    _played('q1', 1, 1, 'e1', 'e8', Side.a, const [
      [6, 2],
      [6, 3],
    ]),
    _played('q2', 1, 2, 'e4', 'e5', Side.b, const [
      [4, 6],
      [6, 3],
      [5, 7],
    ]),
    _played('q3', 1, 3, 'e2', 'e7', Side.a, const [
      [6, 1],
      [6, 0],
    ]),
    _ko('q4', 1, 4, a: 'e3', b: 'e6', status: MatchStatus.done, outcome: MatchOutcome.walkover, winner: Side.a),
    _ko(
      's1',
      2,
      1,
      a: 'e1',
      b: 'e5',
      status: MatchStatus.ready,
      courtName: 'Court 7',
      startsAt: DateTime.utc(2026, 12, 4, 10),
    ),
    _ko('s2', 2, 2, a: 'e2', b: 'e3', status: MatchStatus.ready),
    if (finished)
      _played('f', 3, 1, 'e1', 'e2', Side.b, const [
        [3, 6],
        [2, 6],
      ])
    else
      _ko('f', 3, 1),
  ],
  winner: finished ? 'e2' : null,
  runnerUp: finished ? 'e1' : null,
  finished: finished,
);

/// A 3-entry knockout: seed 1 has a bye into the final.
final threeDraw = CategoryDraw(
  categoryId: 'k3',
  format: DrawFormat.knockout,
  published: true,
  entries: [for (var s = 1; s <= 3; s++) _entry(s)],
  matches: [
    _ko('b1', 1, 1, a: 'e1', bEmpty: true, status: MatchStatus.done, outcome: MatchOutcome.bye, winner: Side.a),
    _ko('m2', 1, 2, a: 'e3', b: 'e2', status: MatchStatus.ready),
    _ko('f3', 2, 1, a: 'e1', status: MatchStatus.waiting),
  ],
);

GroupStanding _row(String id, int place, {required int points, bool advancing = false}) => GroupStanding(
  registrationId: id,
  played: 3,
  won: points ~/ 2,
  drawn: 0,
  lost: 3 - points ~/ 2,
  points: points,
  setsFor: 0,
  setsAgainst: 0,
  gamesFor: 0,
  gamesAgainst: 0,
  place: place,
  advancing: advancing,
  withdrawn: false,
);

/// A group of four, two advancing; standings in place order.
final groupDraw = CategoryDraw(
  categoryId: 'g4',
  format: DrawFormat.groups,
  published: true,
  groupSize: 4,
  advance: 2,
  entries: [for (var s = 1; s <= 4; s++) _entry(s, groupId: 'ga')],
  groups: [
    DrawGroup(
      id: 'ga',
      label: 'A',
      standings: [
        _row('e3', 1, points: 6, advancing: true),
        _row('e1', 2, points: 4, advancing: true),
        _row('e4', 3, points: 2),
        _row('e2', 4, points: 0),
      ],
    ),
  ],
);

final _now = DateTime.utc(2026, 11, 22, 10);

Future<void> _pump(WidgetTester tester, Widget child, {String lang = 'en', double width = 400}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

// ---- The sample backend, with tournament loads that can fail, seen by a plain player ----

class _FlakyTournaments implements TournamentRepository {
  _FlakyTournaments(this._inner, this._owner);

  final TournamentRepository _inner;
  final _Flaky _owner;

  Future<T> _guard<T>(Future<T> Function() f) {
    if (_owner.offline) throw const TournamentException(TournamentError.unavailable);
    return f();
  }

  @override
  Future<List<Tournament>> list(
    String cityId, {
    String? sportId,
    DateTime? from,
    TournamentSort sort = TournamentSort.date,
  }) => _inner.list(cityId, sportId: sportId, from: from, sort: sort);
  @override
  Future<Tournament> get(String id) => _guard(() => _inner.get(id));
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
  Future<List<Registration>> myRegistrations() => _guard(_inner.myRegistrations);
  @override
  Future<PlayerRef?> findPlayerByPhone(String phone) => _inner.findPlayerByPhone(phone);
  @override
  Future<TournamentBracket> bracket(String tournamentId) => _guard(() async {
    await _owner.gate?.future;
    final b = await _inner.bracket(tournamentId);
    if (!_owner.plainPlayer) return b;
    // As a player who does not organise it sees it.
    return TournamentBracket(
      organizer: false,
      draws: b.draws.where((d) => d.published).toList(),
      myNextMatch: b.myNextMatch,
      finished: b.finished,
    );
  });
  @override
  Future<List<MyMatch>> myMatches() => _guard(_inner.myMatches);
}

class _Flaky extends SampleBackend {
  _Flaky({required super.utcNow}) : super(meName: 'Test');

  bool offline = false;

  /// The demo player is an admin, so organises every tournament; with this
  /// on, brackets come as a plain player's.
  bool plainPlayer = false;

  /// Brackets wait for it.
  Completer<void>? gate;

  @override
  TournamentRepository get tournament => _flaky ??= _FlakyTournaments(super.tournament, this);
  TournamentRepository? _flaky;
}

SampleBackend _backend(WidgetTester tester) => containerOf(tester).read(sampleBackendProvider);

Future<void> _openT1(WidgetTester tester) async {
  await tap(tester, find.text('Tournaments'));
  await tap(tester, find.text('Tashkent Padel Cup'));
}

Future<void> _openMine(WidgetTester tester) async {
  await tap(tester, find.text('Tournaments'));
  await tap(tester, find.byKey(const ValueKey('my-tournaments')));
}

/// The sample bracket's semi-finals, by position.
Future<List<TournamentMatch>> _semis(WidgetTester tester) async {
  final bracket = await _backend(tester).tournament.bracket('t1');
  return bracket.draw('t1c2')!.matches.where((m) => m.stage == MatchStage.knockout && m.round == 2).toList()
    ..sort((a, b) => a.position.compareTo(b.position));
}

Future<void> _pull(WidgetTester tester, Finder on) async {
  await tester.fling(on, const Offset(0, 1500), 1000);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

const _newKinds = [
  'organizer_added',
  'organizer_removed',
  'draw_published',
  'draw_redone',
  'waitlist_closed',
  'match_scheduled',
  'match_result',
  'entry_withdrawn',
  'category_won',
];

AppNotification _note(String kind, [Map<String, Object?> extra = const {}]) => AppNotification(
  id: 'n-$kind',
  kind: kind,
  category: kind == 'rating_updated' || kind == 'score_resolved' ? 'ratings' : 'tournaments',
  payload: {
    'tournament_id': 't1',
    'category_id': 't1c2',
    'title': const {'uz': 'Toshkent kubogi', 'ru': 'Кубок Ташкента', 'kk': 'Ташкент кубогы', 'en': 'Tashkent Cup'},
    'category_name': const {'uz': 'Erkaklar', 'ru': 'Мужчины', 'kk': 'Ерлер', 'en': 'Men'},
    ...extra,
  },
  createdAt: DateTime.utc(2026, 11, 22),
  read: false,
);

void main() {
  setUpAll(initializeDateFormatting);

  group('bracket', () {
    testWidgets('an 8-draw shows three rounds side by side with the scores', (tester) async {
      await _pump(tester, BracketView(draw: eightDraw(), now: _now));

      expect(find.text('Quarter-finals'), findsOneWidget);
      expect(find.text('Semi-finals'), findsOneWidget);
      expect(find.text('Final'), findsOneWidget);
      expect(find.text('6–2 6–3'), findsOneWidget);
      expect(find.text('4–6 6–3 5–7'), findsOneWidget);
      expect(find.text('Walkover'), findsOneWidget);
      // Rounds left to right.
      double x(String text) => tester.getTopLeft(find.text(text)).dx;
      expect(x('Quarter-finals'), lessThan(x('Semi-finals')));
      expect(x('Semi-finals'), lessThan(x('Final')));
      // A scheduled match says where and when.
      expect(
        find.descendant(of: find.byKey(const ValueKey('match-s1')), matching: find.textContaining('Court 7')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('match-s1')), matching: find.textContaining('10:00')),
        findsOneWidget,
      );
      // Sides not known yet.
      expect(
        find.descendant(of: find.byKey(const ValueKey('match-f')), matching: find.text('To be decided')),
        findsNWidgets(2),
      );
    });

    testWidgets('a bye is not drawn as a match', (tester) async {
      await _pump(tester, BracketView(draw: threeDraw, now: _now));

      expect(find.byKey(const ValueKey('match-b1')), findsNothing);
      expect(find.byKey(const ValueKey('match-m2')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-f3')), findsOneWidget);
      expect(find.text('Bye'), findsNothing);
      // Player1 shows once: in the final, not against an empty slot.
      expect(find.text('Player1'), findsOneWidget);
    });

    testWidgets('a finished category names the winner and the runner-up', (tester) async {
      await _pump(tester, CategoryDrawSection(draw: eightDraw(finished: true), now: _now));

      expect(find.byKey(const ValueKey('draw-winner')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('draw-winner')), matching: find.text('Player2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('draw-runner-up')), matching: find.text('Player1')),
        findsOneWidget,
      );
    });

    testWidgets('a pair shows both names', (tester) async {
      final draw = CategoryDraw(
        categoryId: 'p',
        format: DrawFormat.knockout,
        published: true,
        entries: [
          _entry(
            1,
            players: const [
              PlayerRef(id: 'a', name: 'Aziz'),
              PlayerRef(id: 'b', name: 'Bekzod'),
            ],
          ),
          _entry(
            2,
            players: const [
              PlayerRef(id: 'c', name: 'Gone', deleted: true),
              PlayerRef(id: 'd', name: 'Dilshod'),
            ],
          ),
        ],
        matches: [_ko('f', 1, 1, a: 'e1', b: 'e2', status: MatchStatus.ready)],
      );
      await _pump(tester, BracketView(draw: draw, now: _now));
      expect(find.text('Aziz / Bekzod'), findsOneWidget);
      expect(find.text('Deleted player / Dilshod'), findsOneWidget);
    });
  });

  group('group table', () {
    testWidgets('orders by place and marks the two advancing', (tester) async {
      await _pump(tester, GroupTable(group: groupDraw.groups.single, draw: groupDraw));

      expect(find.text('Group A'), findsOneWidget);
      for (final header in ['P', 'W', 'L', 'Pts']) {
        expect(find.text(header), findsOneWidget);
      }
      double y(String id) => tester.getTopLeft(find.byKey(ValueKey('group-row-$id'))).dy;
      expect(y('e3'), lessThan(y('e1')));
      expect(y('e1'), lessThan(y('e4')));
      expect(y('e4'), lessThan(y('e2')));
      expect(find.byKey(const ValueKey('advancing-e3')), findsOneWidget);
      expect(find.byKey(const ValueKey('advancing-e1')), findsOneWidget);
      expect(find.byKey(const ValueKey('advancing-e4')), findsNothing);
      expect(find.byKey(const ValueKey('advancing-e2')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('group-row-e3')), matching: find.text('6')), findsOneWidget);
    });
  });

  group('next match', () {
    testWidgets('shows the opponent, the court and the time', (tester) async {
      final draw = CategoryDraw(
        categoryId: 'n',
        format: DrawFormat.knockout,
        published: true,
        entries: [
          _entry(
            1,
            players: const [
              PlayerRef(id: kMeId, name: 'Test'),
              PlayerRef(id: 'p7', name: 'Bekzod'),
            ],
          ),
          _entry(
            2,
            players: const [
              PlayerRef(id: 'x', name: 'Rustam'),
              PlayerRef(id: 'y', name: 'Jasur'),
            ],
          ),
        ],
      );
      final match = _ko(
        'n1',
        2,
        1,
        a: 'e2',
        b: 'e1',
        status: MatchStatus.ready,
        courtName: 'Court 1',
        startsAt: DateTime.utc(2026, 12, 4, 10),
      );
      await _pump(tester, NextMatchCard(match: match, draw: draw, now: _now));

      expect(find.text('Your next match'), findsOneWidget);
      expect(find.textContaining('Rustam / Jasur'), findsOneWidget);
      expect(find.textContaining('Bekzod'), findsNothing);
      expect(find.textContaining('Court 1'), findsOneWidget);
      expect(find.textContaining('10:00'), findsOneWidget);
    });

    testWidgets('without a venue it shows the place note', (tester) async {
      final draw = CategoryDraw(
        categoryId: 'n',
        format: DrawFormat.knockout,
        published: true,
        entries: [
          _entry(
            1,
            players: const [PlayerRef(id: kMeId, name: 'Test')],
          ),
          _entry(2),
        ],
      );
      final match = _ko('n1', 1, 1, a: 'e1', b: 'e2', status: MatchStatus.ready, placeNote: 'Park, pitch 3');
      await _pump(tester, NextMatchCard(match: match, draw: draw, now: _now));
      expect(find.textContaining('Player2'), findsOneWidget);
      expect(find.textContaining('Park, pitch 3'), findsOneWidget);
    });
  });

  group('the tournament page', () {
    testWidgets('a published draw shows its bracket and the next match on top', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openT1(tester);

      expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-t1c1')), findsNothing);
      expect(find.text('Semi-finals'), findsOneWidget);
      expect(find.text('6–2 6–2'), findsOneWidget);
      final next = find.byKey(const ValueKey('next-match'));
      expect(next, findsOneWidget);
      expect(find.descendant(of: next, matching: find.textContaining('Farrukh')), findsOneWidget);
      expect(find.descendant(of: next, matching: find.textContaining('Court 1')), findsOneWidget);
      // On top: above the categories.
      expect(tester.getTopLeft(next).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('category-t1c1'))).dy));
    });

    testWidgets('a draft is not shown on the page, even to its organiser', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final backend = _backend(tester);
      await backend.admin.addRegistration('t1c1', 'p1', partnerId: 'p2');
      await backend.admin.addRegistration('t1c1', 'p3', partnerId: 'p4');
      final draft = await backend.organizer.makeDraw('t1c1', DrawFormat.knockout);
      expect(draft.published, isFalse);
      // The organiser's bracket has it.
      expect((await backend.tournament.bracket('t1')).draw('t1c1'), isNotNull);
      containerOf(tester).invalidate(bracketProvider);
      await _openT1(tester);
      expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-t1c1')), findsNothing);
    });

    testWidgets('a locked category offers no Cancel registration', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openT1(tester);
      final t1c2 = find.byKey(const ValueKey('category-t1c2'));
      expect(find.descendant(of: t1c2, matching: find.text('Registered')), findsOneWidget);
      expect(find.descendant(of: t1c2, matching: find.text('Cancel registration')), findsNothing);

      await _openMine(tester);
      final entry = find.ancestor(of: find.text("Men's pairs"), matching: find.byType(Card)).first;
      expect(find.descendant(of: entry, matching: find.text('Registered')), findsOneWidget);
      expect(find.descendant(of: entry, matching: find.text('Cancel registration')), findsNothing);
    });

    testWidgets('Manage shows only to an organiser and opens the manager', (tester) async {
      late _Flaky backend;
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => backend = _Flaky(utcNow: clock),
      );
      await _openT1(tester);
      expect(find.byKey(const ValueKey('tournament-manage')), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('tournament-manage')));
      expect(find.byKey(const ValueKey('tournament-manage-screen')), findsOneWidget);

      // A player who does not organise it.
      backend.plainPlayer = true;
      final c = containerOf(tester);
      c.invalidate(bracketProvider);
      c.read(routerProvider).go('/tournaments/t1');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tournament-detail')), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tournament-manage')), findsNothing);
    });

    testWidgets('every category done: winner, runner-up and Finished', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final organizer = _backend(tester).organizer;
      final semis = await _semis(tester);
      await organizer.enterScore(
        semis[0].id,
        MatchOutcome.played,
        sets: const [
          [6, 3],
          [6, 4],
        ],
      );
      await organizer.enterScore(
        semis[1].id,
        MatchOutcome.played,
        sets: const [
          [6, 1],
          [6, 2],
        ],
      );
      final bracket = await _backend(tester).tournament.bracket('t1');
      final finalMatch = bracket
          .draw('t1c2')!
          .matches
          .firstWhere((m) => m.stage == MatchStage.knockout && m.round == 3);
      await organizer.enterScore(
        finalMatch.id,
        MatchOutcome.played,
        sets: const [
          [7, 5],
          [6, 4],
        ],
      );
      containerOf(tester).invalidate(bracketProvider);
      await _openT1(tester);

      expect(find.byKey(const ValueKey('tournament-finished')), findsOneWidget);
      final winner = find.byKey(const ValueKey('draw-winner'));
      expect(find.descendant(of: winner, matching: find.textContaining('Test')), findsOneWidget);
      expect(find.byKey(const ValueKey('draw-runner-up')), findsOneWidget);
      expect(find.byKey(const ValueKey('next-match')), findsNothing);
    });

    testWidgets('a reload that fails keeps the bracket, and a failed pull says so', (tester) async {
      late _Flaky backend;
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => backend = _Flaky(utcNow: clock),
      );
      await _openT1(tester);
      expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);

      backend.offline = true;
      // As on coming back to the app.
      final c = containerOf(tester);
      c.invalidate(bracketProvider);
      c.invalidate(tournamentProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-t1c1')), findsOneWidget);

      await _pull(tester, find.byKey(const ValueKey('tournament-detail')));
      expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget, reason: 'the failed pull is not silent');
      await settleSnackbars(tester);
    });

    testWidgets('pulling the page down shows a score the organiser entered meanwhile', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openT1(tester);
      expect(find.text('6–3 6–4'), findsOneWidget);
      final semis = await _semis(tester);
      await _backend(tester)
          .organizerAs(kMeId)
          .enterScore(
            semis[1].id,
            MatchOutcome.played,
            sets: const [
              [6, 0],
              [6, 0],
            ],
          );
      expect(find.text('6–0 6–0'), findsNothing);

      await _pull(tester, find.byKey(const ValueKey('tournament-detail')));
      expect(find.text('6–0 6–0'), findsOneWidget);
    });
  });

  group('reloads', () {
    Future<void> scoreSecondSemi(WidgetTester tester) async {
      final semis = await _semis(tester);
      await _backend(tester).organizer.enterScore(
        semis[1].id,
        MatchOutcome.played,
        sets: const [
          [6, 0],
          [6, 0],
        ],
      );
    }

    testWidgets('opening the page again shows a score entered meanwhile', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openT1(tester);
      expect(find.text('6–0 6–0'), findsNothing);
      final c = containerOf(tester);
      c.read(routerProvider).go('/tournaments');
      await tester.pumpAndSettle();
      await scoreSecondSemi(tester);

      c.read(routerProvider).go('/tournaments/t1');
      await tester.pumpAndSettle();
      expect(find.text('6–0 6–0'), findsOneWidget);
    });

    testWidgets('coming back to the app shows a score entered meanwhile', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openT1(tester);
      await scoreSecondSemi(tester);
      expect(find.text('6–0 6–0'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('6–0 6–0'), findsOneWidget);
    });

    testWidgets('a notice opened from the inbox shows the fresh bracket', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openT1(tester);
      // The demo player's semi-final.
      final semis = await _semis(tester);
      await _backend(tester).organizer.enterScore(
        semis[0].id,
        MatchOutcome.played,
        sets: const [
          [6, 1],
          [6, 1],
        ],
      );
      final c = containerOf(tester);
      c.invalidate(inboxProvider);
      c.invalidate(unreadCountProvider);
      // The tournaments tab keeps the page underneath.
      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();

      await tap(tester, find.byKey(const ValueKey('inbox-bell')));
      await tap(tester, find.textContaining('Your match result in Tashkent Padel Cup').first);
      expect(find.byKey(const ValueKey('tournament-detail')), findsOneWidget);
      expect(find.text('6–1 6–1'), findsOneWidget);
    });

    testWidgets("another account never sees the previous one's next match or Manage", (tester) async {
      final gate = Completer<void>();
      var built = 0;
      await pumpApp(
        tester,
        prefs: signedIn,
        utcNow: sundayMorning,
        backend: (clock) => _Flaky(utcNow: clock)..gate = built++ == 0 ? null : gate,
      );
      await _openT1(tester);
      expect(find.byKey(const ValueKey('next-match')), findsOneWidget);
      expect(find.byKey(const ValueKey('tournament-manage')), findsOneWidget);

      await containerOf(tester).read(sessionProvider.notifier).signIn('Other');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('next-match')), findsNothing);
      expect(find.byKey(const ValueKey('tournament-manage')), findsNothing);
      expect(find.byKey(const ValueKey('draw-t1c2')), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('My tournaments', () {
    testWidgets('the next match on top and My matches', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      await _openMine(tester);

      final next = find.byKey(const ValueKey('next-match'));
      expect(next, findsOneWidget);
      expect(find.descendant(of: next, matching: find.textContaining('Farrukh')), findsOneWidget);
      final mine = find.byKey(const ValueKey('my-matches'));
      expect(mine, findsOneWidget);
      expect(find.descendant(of: mine, matching: find.text('My matches'.toUpperCase())), findsOneWidget);
      // The semi-final to play and the quarter-final played (6–3 6–4).
      expect(find.descendant(of: mine, matching: find.text('6–3 6–4')), findsOneWidget);
      expect(find.descendant(of: mine, matching: find.textContaining('Farrukh')), findsOneWidget);
    });
  });

  group('notifications', () {
    for (final code in ['en', 'kk', 'ru', 'uz']) {
      test('every new tournament kind has its own sentence in $code', () {
        final l = lookupAppLocalizations(Locale(code));
        final title = {
          'en': 'Tashkent Cup',
          'ru': 'Кубок Ташкента',
          'kk': 'Ташкент кубогы',
          'uz': 'Toshkent kubogi',
        }[code]!;
        final seen = <String>{};
        for (final kind in _newKinds) {
          final text = notificationText(l, code, _note(kind));
          expect(text, isNot(l.notifUnknown), reason: '$kind in $code');
          expect(text, contains(title), reason: '$kind in $code');
          expect(seen.add(text), isTrue, reason: '$kind repeats another sentence in $code');
        }
        // A correction reads differently from a first result.
        expect(
          notificationText(l, code, _note('match_result', {'correction': true})),
          isNot(notificationText(l, code, _note('match_result'))),
        );
      });
    }

    test('every new kind opens the tournament', () {
      for (final kind in _newKinds) {
        expect(_note(kind).route, '/tournaments/t1', reason: kind);
      }
    });

    test('a tournament score or rating notice opens the tournament; a game one still the game', () {
      for (final kind in ['rating_updated', 'score_resolved']) {
        expect(_note(kind, {'old': 3.5, 'new': 3.6, 'action': 'void'}).route, '/tournaments/t1', reason: kind);
        expect(_note(kind, {'game_id': 'g9'}).route, '/games/g9', reason: kind);
      }
    });

    testWidgets('tapping a match result or a tournament rating notice opens the tournament', (tester) async {
      await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
      final semis = await _semis(tester);
      await _backend(tester).organizer.enterScore(
        semis[0].id,
        MatchOutcome.played,
        sets: const [
          [6, 3],
          [6, 4],
        ],
      );
      final c = containerOf(tester);
      c.invalidate(inboxProvider);
      c.invalidate(unreadCountProvider);
      await tester.pumpAndSettle();

      for (final text in ['Your rating changed', 'Your match result in Tashkent Padel Cup']) {
        await tap(tester, find.byKey(const ValueKey('inbox-bell')));
        await tap(tester, find.textContaining(text).first);
        expect(find.byKey(const ValueKey('tournament-detail')), findsOneWidget, reason: text);
        // The fresh bracket: the semi-final is played.
        expect(find.text('6–3 6–4'), findsNWidgets(2), reason: text);
        c.read(routerProvider).go('/home');
        await tester.pumpAndSettle();
      }
    });
  });

  group('fits a phone', () {
    for (final lang in ['uz', 'ru', 'kk']) {
      testWidgets('the tournament page and My tournaments in $lang', (tester) async {
        await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
        tester.view.physicalSize = const Size(360, 2400);
        await tester.pumpAndSettle();
        final c = containerOf(tester);
        c.read(routerProvider).go('/tournaments/t1');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('draw-t1c2')), findsOneWidget);
        expect(find.byKey(const ValueKey('next-match')), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('draw-t1c2')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        c.read(routerProvider).go('/my-tournaments');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('my-matches')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the group table and a finished bracket in $lang', (tester) async {
        await _pump(
          tester,
          CategoryDrawSection(draw: groupDraw, now: _now),
          lang: lang,
          width: 360,
        );
        await _pump(
          tester,
          CategoryDrawSection(draw: eightDraw(finished: true), now: _now),
          lang: lang,
          width: 360,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
