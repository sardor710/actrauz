import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/teams.dart';
import 'package:actra/features/games/create_game_screen.dart';
import 'package:actra/features/games/game_card.dart';
import 'package:actra/features/games/game_screen.dart';
import 'package:actra/features/social/team_editor_screen.dart';
import 'package:actra/features/social/team_screen.dart';
import 'package:actra/router.dart';
import 'package:actra/state/admin_providers.dart';
import 'package:actra/state/providers.dart';
import 'package:actra/state/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_flow_test.dart';
import 'games_host_flow_test.dart' show bookPadel, containerOf;

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _go(WidgetTester tester, String location) async {
  containerOf(tester).read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, String location) async {
  containerOf(tester).read(routerProvider).push(location);
  await tester.pumpAndSettle();
}

/// Reloads every team view after a change made behind the app's back.
Future<void> _refresh(WidgetTester tester) async {
  final c = containerOf(tester);
  c.invalidate(teamsProvider);
  c.invalidate(teamProvider);
  c.invalidate(playerProfileProvider);
  c.invalidate(adminReviewProvider);
  await tester.pumpAndSettle();
}

const _owls = TeamDraft(name: 'Night Owls', sportId: 'padel', cityId: 'tashkent');

Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(_key('team-name'), name);
  await tester.pumpAndSettle();
}

Future<void> _pickPadel(WidgetTester tester) async {
  await tap(tester, _key('team-sport'));
  await tap(tester, find.text('Padel').last);
}

void main() {
  testWidgets('create a team and see it under My teams', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await tap(tester, find.text('Social'));

    await tester.ensureVisible(_key('teams-create'));
    await tap(tester, _key('teams-create'));
    expect(find.byType(TeamEditorScreen), findsOneWidget);
    await _typeName(tester, 'Night Owls');
    await _pickPadel(tester);
    await tester.enterText(_key('team-description'), 'Late padel after work');
    await tap(tester, _key('team-policy-approval'));
    await tap(tester, _key('team-save'));

    // The new team's page, with me as its captain.
    expect(find.byType(TeamScreen), findsOneWidget);
    expect(find.text('Night Owls'), findsWidgets);
    expect(find.text('Late padel after work'), findsOneWidget);
    expect(find.text('By approval'), findsOneWidget);
    expect(_key('team-edit'), findsOneWidget);
    expect(_key('team-join'), findsNothing);

    await tap(tester, find.byType(BackButton));
    expect(find.descendant(of: _key('my-teams'), matching: find.text('Night Owls')), findsOneWidget);
  });

  testWidgets('join an open team', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await tap(tester, find.text('Social'));
    expect(find.descendant(of: _key('my-teams'), matching: find.text('Yunusobod Padel')), findsNothing);

    await tap(tester, find.text('Yunusobod Padel'));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
    await tap(tester, _key('team-join'));

    expect(find.text('5 members'), findsOneWidget);
    expect(_key('team-leave'), findsOneWidget);
    expect(_key('team-join'), findsNothing);

    await tap(tester, find.byType(BackButton));
    expect(find.descendant(of: _key('my-teams'), matching: find.text('Yunusobod Padel')), findsOneWidget);

    // A member leaves after saying yes.
    await tap(tester, find.text('Yunusobod Padel'));
    await tap(tester, _key('team-leave'));
    await tap(tester, _key('team-dialog-ok'));
    expect(_key('team-join'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
  });

  testWidgets('teams in the city follow my sports unless I show all', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning, withSports: false);
    await tap(tester, find.text('Social'));
    // No sports yet: every team of the city, and no toggle.
    for (final name in ['Yunusobod Padel', 'Chilonzor FC', 'Tennis Crew', 'Hoops TAS']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(_key('teams-show-all'), findsNothing);

    await containerOf(tester).read(sampleBackendProvider).setSport('football', level: 3);
    containerOf(tester).invalidate(mySportsProvider);
    await tester.pumpAndSettle();
    expect(find.text('Chilonzor FC'), findsOneWidget);
    expect(find.text('Yunusobod Padel'), findsNothing);
    expect(find.text('Hoops TAS'), findsNothing);

    await tap(tester, _key('teams-show-all'));
    expect(find.text('Yunusobod Padel'), findsOneWidget);
    expect(find.text('Hoops TAS'), findsOneWidget);
    expect(find.text('My sports only'), findsOneWidget);
  });

  testWidgets('request to join and get approved', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    // Chilonzor FC asks the captain, Timur, to approve.
    await _push(tester, '/teams/tm2');
    expect(find.text('By approval'), findsOneWidget);
    await tap(tester, _key('team-join'));
    expect(_key('team-cancel-request'), findsOneWidget);
    expect(_key('team-leave'), findsNothing);

    final backend = containerOf(tester).read(sampleBackendProvider);
    final requestId = (await backend.team('tm2')).myRequestId!;
    await backend.decideTeamRequestAs('p3', requestId, approve: true);
    await _refresh(tester);

    expect(_key('team-cancel-request'), findsNothing);
    expect(_key('team-leave'), findsOneWidget);
    expect(find.text('5 members'), findsOneWidget);
  });

  testWidgets('invite a player to my team from their profile', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(
      const TeamDraft(name: 'Night Owls', sportId: 'padel', cityId: 'tashkent', joinPolicy: TeamJoinPolicy.approval),
    );
    await _refresh(tester);

    await _push(tester, '/players/p2');
    await tap(tester, _key('profile-invite-team'));
    await tap(tester, _key('invite-team-${team.id}'));
    expect(find.text('Dilnoza was invited'), findsOneWidget);
    await settleSnackbars(tester);

    // With the invite open, Dilnoza joins the approval team at once.
    final joined = await backend.joinTeamAs('p2', team.id);
    expect(joined.memberCount, 2);
    await _refresh(tester);

    // Her profile now lists the team, and it is no longer offered.
    expect(find.text('Night Owls'), findsOneWidget);
    await tap(tester, _key('profile-invite-team'));
    expect(_key('invite-team-${team.id}'), findsNothing);
    expect(find.text('No team of yours to invite them to'), findsOneWidget);
  });

  testWidgets('captain hands over and leaves', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(_owls);
    await backend.joinTeamAs('p1', team.id);
    await _refresh(tester);

    await _push(tester, '/teams/${team.id}');
    expect(find.text('2 members'), findsOneWidget);
    // The captain's Leave asks for a new captain first.
    await tap(tester, _key('team-leave'));
    expect(find.text('Hand the captain role to a member, then you leave the team.'), findsOneWidget);
    await tap(tester, _key('handover-p1'));

    expect(_key('team-join'), findsOneWidget);
    expect(_key('team-edit'), findsNothing);
    expect(find.text('1 member'), findsOneWidget);
    final after = await backend.team(team.id);
    expect(after.captainId, 'p1');
    expect(after.myStatus, isNull);
  });

  testWidgets('a captain alone can only delete the team', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(_owls);
    await _refresh(tester);
    await tap(tester, find.text('Social'));
    await _push(tester, '/teams/${team.id}');

    await tap(tester, _key('team-leave'));
    expect(find.text('Nobody else is in the team. You can delete it instead.'), findsOneWidget);
    await tap(tester, _key('handover-delete'));
    await tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));

    expect(find.byType(TeamScreen), findsNothing);
    expect(find.text('Night Owls'), findsNothing);
    expect((await backend.teams('tashkent')).any((t) => t.id == team.id), isFalse);
  });

  testWidgets('the captain approves a request and removes a member', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(
      const TeamDraft(name: 'Night Owls', sportId: 'padel', cityId: 'tashkent', joinPolicy: TeamJoinPolicy.approval),
    );
    await backend.joinTeamAs('p1', team.id);
    await _refresh(tester);
    await _push(tester, '/teams/${team.id}');

    final requestId = (await backend.team(team.id)).requests.single.id;
    await tap(tester, _key('team-approve-$requestId'));
    expect(find.text('2 members'), findsOneWidget);
    expect(_key('team-approve-$requestId'), findsNothing);

    await tap(tester, _key('team-member-menu-p1'));
    await tap(tester, find.text('Remove from team'));
    await tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Remove')));
    expect(find.text('1 member'), findsOneWidget);
    expect(_key('team-member-menu-p1'), findsNothing);
  });

  testWidgets('an invited player accepts on the team page', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    // Chilonzor FC needs approval, but an invite lets me in.
    await backend.inviteToTeamAs('p3', 'tm2', kMeId);
    await _refresh(tester);
    await tap(tester, find.text('Social'));
    expect(_key('team-invite-dot-tm2'), findsOneWidget);

    await tap(tester, find.text('Chilonzor FC'));
    expect(_key('team-decline'), findsOneWidget);
    await tap(tester, _key('team-accept'));
    expect(_key('team-leave'), findsOneWidget);
    expect(find.text('5 members'), findsOneWidget);
  });

  testWidgets('a taken name shows an error', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _push(tester, '/teams/new');

    // Too short: Save stays off.
    await _typeName(tester, 'Yu');
    await _pickPadel(tester);
    expect(tester.widget<FilledButton>(_key('team-save')).onPressed, isNull);

    await _typeName(tester, 'yunusobod padel');
    await tap(tester, _key('team-save'));
    expect(find.text('A team with this name already exists in this city and sport'), findsOneWidget);
    expect(find.byType(TeamEditorScreen), findsOneWidget);
  });

  testWidgets('the captain edits the name and policy; sport and city stay', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(_owls);
    await _refresh(tester);
    await _push(tester, '/teams/${team.id}');

    await tap(tester, _key('team-edit'));
    expect(find.byType(TeamEditorScreen), findsOneWidget);
    expect(_key('team-sport'), findsNothing);
    expect(find.text('Sport and city cannot be changed after the team is created.'), findsOneWidget);
    await _typeName(tester, 'Early Birds');
    await tap(tester, _key('team-policy-approval'));
    await tap(tester, _key('team-save'));

    expect(find.byType(TeamScreen), findsOneWidget);
    expect(find.text('Early Birds'), findsWidgets);
    expect(find.text('By approval'), findsOneWidget);
  });

  testWidgets('admin deletes a team', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _go(tester, '/admin/review');
    await tap(tester, _key('review-tab-teams'));
    expect(_key('review-team-tm1'), findsOneWidget);

    await tester.ensureVisible(_key('review-delete-team-tm1'));
    await tap(tester, _key('review-delete-team-tm1'));
    await tap(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));

    expect(_key('review-team-tm1'), findsNothing);
    expect(_key('review-team-tm2'), findsOneWidget);
    final backend = containerOf(tester).read(sampleBackendProvider);
    expect((await backend.teams('tashkent')).any((t) => t.id == 'tm1'), isFalse);
    await settleSnackbars(tester);
  });

  testWidgets('a player profile and my own profile list teams as pills', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    await _push(tester, '/players/p1');
    // Aziz captains Yunusobod Padel and plays for Chilonzor FC and two more.
    await tap(tester, _key('profile-team-tm1'));
    expect(find.byType(TeamScreen), findsOneWidget);

    final backend = containerOf(tester).read(sampleBackendProvider);
    await backend.createTeam(_owls);
    await _refresh(tester);
    await _go(tester, '/profile');
    expect(find.text('MY TEAMS'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
  });

  testWidgets('captain posts a team game', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(_owls);
    await backend.joinTeamAs('p1', team.id);
    final booking = await bookPadel(tester);
    await _refresh(tester);

    await _push(tester, '/teams/${team.id}');
    expect(find.text('UPCOMING GAMES'), findsOneWidget);
    expect(find.text('No upcoming team games'), findsOneWidget);
    await tester.ensureVisible(_key('team-post-game'));
    await tap(tester, _key('team-post-game'));

    // The create form, with the team's sport and the team already chosen.
    expect(find.byType(CreateGameScreen), findsOneWidget);
    await tap(tester, _key('booking-${booking.id}'));
    await tester.ensureVisible(_key('who-team-${team.id}'));
    expect(tester.widget<RadioListTile<String>>(_key('who-team-${team.id}')).checked, isTrue);
    expect(find.text('Open to everyone if spots remain'.toUpperCase()), findsOneWidget);
    await tester.ensureVisible(_key('open-hours-24'));
    await tap(tester, _key('open-hours-24'));
    await tap(tester, find.byKey(const ValueKey('create-game-submit')));

    // The game shows the team, not "Invite only", and when it opens to everyone (24 h before Monday 11:30).
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    expect(find.text('Invite only'), findsNothing);
    expect(find.text('Opens to everyone · Today 11:30'), findsOneWidget);

    // Listed on the team page and in the Games tab.
    await _go(tester, '/teams/${team.id}');
    expect(find.text('No upcoming team games'), findsNothing);
    expect(find.descendant(of: find.byType(GameCard), matching: find.text('Night Owls')), findsOneWidget);
    expect(find.text('1 game soon'), findsOneWidget);
    await _go(tester, '/games');
    expect(find.descendant(of: find.byType(GameCard), matching: find.text('Night Owls')), findsOneWidget);
  });

  testWidgets('joining a team brings its games into the Games tab', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeamAs(
      'p1',
      const TeamDraft(name: 'Aziz Runners', sportId: 'running', cityId: 'tashkent'),
    );
    await backend.createAs(
      'p1',
      GameDraft(
        sportId: 'running',
        spots: 4,
        meetingPoint: 'Riverside',
        start: DateTime.utc(2026, 11, 23, 7),
        end: DateTime.utc(2026, 11, 23, 8),
        teamId: team.id,
      ),
    );
    await _refresh(tester);
    await _go(tester, '/games');
    expect(find.text('Riverside'), findsNothing);

    await _push(tester, '/teams/${team.id}');
    // Not a member: the count, but no game card.
    expect(find.text('1 game soon'), findsOneWidget);
    expect(find.byType(GameCard), findsNothing);
    await tap(tester, _key('team-join'));
    expect(find.byType(GameCard), findsOneWidget);

    await _go(tester, '/games');
    expect(find.text('Riverside'), findsOneWidget);
    expect(find.descendant(of: find.byType(GameCard), matching: find.text('Aziz Runners')), findsOneWidget);
  });

  testWidgets('post a game from the team page while a create form is open in Games', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    final team = await backend.createTeam(
      const TeamDraft(name: 'Night Runners', sportId: 'running', cityId: 'tashkent'),
    );
    await _refresh(tester);
    await _go(tester, '/games/new');
    expect(find.byType(CreateGameScreen), findsOneWidget);

    await _push(tester, '/teams/${team.id}');
    await tester.ensureVisible(_key('team-post-game'));
    await tap(tester, _key('team-post-game'));
    await tester.ensureVisible(_key('who-team-${team.id}'));
    expect(tester.widget<RadioListTile<String>>(_key('who-team-${team.id}')).checked, isTrue);
  });

  testWidgets('team choice is hidden without a team', (tester) async {
    await pumpApp(tester, prefs: signedIn, utcNow: sundayMorning);
    final backend = containerOf(tester).read(sampleBackendProvider);
    // A team in another sport, and another captain's padel team I am in.
    final runners = await backend.createTeam(
      const TeamDraft(name: 'Night Runners', sportId: 'running', cityId: 'tashkent'),
    );
    await backend.joinTeam('tm1');
    await _refresh(tester);

    await _go(tester, '/games/new');
    await tap(tester, find.text('Padel'));
    expect(find.text('Who can join'.toUpperCase()), findsNothing);
    expect(find.byType(SegmentedButton<GameVisibility>), findsOneWidget);
    expect(_key('who-team-tm1'), findsNothing);

    await tap(tester, find.text('Running'));
    await tester.ensureVisible(_key('who-team-${runners.id}'));
    expect(find.byType(SegmentedButton<GameVisibility>), findsNothing);
    expect(_key('who-public'), findsOneWidget);
    expect(_key('who-invite'), findsOneWidget);
    // Lead times appear only once the team is chosen.
    expect(_key('open-hours-24'), findsNothing);
    await tap(tester, _key('who-team-${runners.id}'));
    expect(_key('open-hours-never'), findsOneWidget);
  });

  for (final lang in ['ru', 'kk']) {
    testWidgets('team games fit a phone in $lang', (tester) async {
      await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();
      final backend = containerOf(tester).read(sampleBackendProvider);
      final team = await backend.createTeam(
        const TeamDraft(name: 'Yunusobod Evening Padel Club Long', sportId: 'padel', cityId: 'tashkent'),
      );
      final booking = await bookPadel(tester);
      await _refresh(tester);

      await _push(tester, '/teams/${team.id}');
      await tester.ensureVisible(_key('team-post-game'));
      await tap(tester, _key('team-post-game'));
      await tap(tester, _key('booking-${booking.id}'));
      await tester.ensureVisible(_key('who-team-${team.id}'));
      await tester.ensureVisible(_key('open-hours-24'));
      // Clear of the bottom bar.
      await tester.drag(
        find.descendant(of: find.byType(CreateGameScreen), matching: find.byType(ListView)),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      await tap(tester, _key('open-hours-24'));
      await tap(tester, find.byKey(const ValueKey('create-game-submit')));
      expect(find.byType(GameScreen), findsOneWidget);
      // The team pill and when it opens to everyone.
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);

      await _go(tester, '/teams/${team.id}');
      expect(find.byType(GameCard), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);
      await _go(tester, '/games');
      expect(find.byType(GameCard), findsWidgets);
    });

    testWidgets('the team screens fit a phone in $lang', (tester) async {
      await pumpApp(tester, prefs: {...signedIn, 'lang': lang}, utcNow: sundayMorning);
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();
      final backend = containerOf(tester).read(sampleBackendProvider);

      // The captain's page: a long name, a pending request, several members.
      final team = await backend.createTeam(
        const TeamDraft(
          name: 'Yunusobod Evening Padel Club Long',
          sportId: 'padel',
          cityId: 'tashkent',
          description: 'Weekday evening doubles in Yunusobod. All levels welcome, bring a friend.',
          joinPolicy: TeamJoinPolicy.approval,
        ),
      );
      await backend.inviteToTeamAs(kMeId, team.id, 'p1');
      await backend.joinTeamAs('p1', team.id);
      await backend.inviteToTeamAs(kMeId, team.id, 'p7');
      await backend.joinTeamAs('p7', team.id);
      await backend.joinTeamAs('p8', team.id);
      await backend.inviteToTeamAs('p3', 'tm2', kMeId);
      await _refresh(tester);

      await _go(tester, '/social');
      expect(_key('my-teams'), findsOneWidget);

      await _push(tester, '/teams/${team.id}');
      expect(find.byType(TeamScreen), findsOneWidget);
      await tap(tester, _key('team-leave'));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Invited, then a plain visitor of an approval team.
      await _go(tester, '/social');
      await _push(tester, '/teams/tm2');
      expect(_key('team-accept'), findsOneWidget);
      await _go(tester, '/social');
      await _push(tester, '/teams/tm3');
      expect(_key('team-join'), findsOneWidget);

      // The editor, creating and editing.
      await _go(tester, '/social');
      await _push(tester, '/teams/new');
      expect(find.byType(TeamEditorScreen), findsOneWidget);
      await _go(tester, '/social');
      await _push(tester, '/teams/${team.id}/edit');
      expect(find.byType(TeamEditorScreen), findsOneWidget);

      // A profile with both invite buttons and team pills.
      await _go(tester, '/social');
      await _push(tester, '/players/p7');
      expect(_key('profile-invite-team'), findsOneWidget);

      // The admin's third tab.
      await _go(tester, '/admin/review');
      await tap(tester, _key('review-tab-teams'));
      expect(_key('review-team-${team.id}'), findsOneWidget);
    });
  }
}
