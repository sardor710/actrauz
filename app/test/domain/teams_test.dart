import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/teams.dart';
import 'package:actra/features/inbox/inbox_screen.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The team rules of the sample backend, which mirror
/// supabase/migrations/20261127130000_teams.sql.
void main() {
  // Sunday 22 Nov 2026, 10:00 in all three cities.
  final utcNow = DateTime.utc(2026, 11, 22, 5, 0);
  late SampleBackend backend;

  setUp(() => backend = SampleBackend(utcNow: () => utcNow, meName: 'Demo Player'));

  Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));

  TeamDraft draft(
    String name, {
    String sportId = 'padel',
    String cityId = 'tashkent',
    TeamJoinPolicy joinPolicy = TeamJoinPolicy.open,
    String? description,
  }) => TeamDraft(name: name, sportId: sportId, cityId: cityId, description: description, joinPolicy: joinPolicy);

  test('creating a team makes me its captain and its first member', () async {
    final team = await backend.createTeam(draft('  Night Owls  ', description: '  Evenings only  '));
    expect(team.name, 'Night Owls');
    expect(team.description, 'Evenings only');
    expect(team.captainId, kMeId);
    expect(team.myStatus, MyTeamStatus.captain);
    expect(team.isCaptain, isTrue);
    expect(team.memberCount, 1);
    expect(team.members.single.id, kMeId);
    expect(team.members.single.captain, isTrue);
    expect(team.members.single.name, 'Demo Player');
    expect(team.requests, isEmpty);
    expect(team.games, isEmpty);
    expect(team.upcomingGames, 0);
    expect(team.colorSeed, inInclusiveRange(0, 7));

    // My team is listed first, in any city.
    expect((await backend.teams('tashkent')).first.id, team.id);
    expect((await backend.teams('almaty')).first.id, team.id);
    expect((await backend.teams('almaty')).skip(1).every((t) => t.cityId == 'almaty'), isTrue);
  });

  test('a name is taken in its city and sport, whatever the case', () async {
    await backend.createTeam(draft('Night Owls'));
    expect(backend.createTeam(draft('night owls ')), joinError(JoinError.nameTaken));
    expect(backend.createTeam(draft('Yunusobod Padel')), joinError(JoinError.nameTaken));
    await backend.createTeam(draft('Night Owls', sportId: 'tennis'));
    await backend.createTeam(draft('Night Owls', cityId: 'almaty'));
    expect(backend.createTeam(draft('ab')), joinError(JoinError.invalidArgument));
    expect(backend.createTeam(draft('x' * 41)), joinError(JoinError.invalidArgument));
    expect(backend.createTeam(draft('Good name', description: 'x' * 501)), joinError(JoinError.invalidArgument));
    expect(backend.createTeam(draft('Good name', sportId: 'chess')), joinError(JoinError.invalidArgument));
    expect(backend.createTeam(draft('Good name', cityId: 'paris')), joinError(JoinError.invalidArgument));
  });

  test('a sixth team as captain is too many', () async {
    for (var i = 1; i <= 5; i++) {
      await backend.createTeam(draft('Team number $i'));
    }
    expect(backend.createTeam(draft('Team number 6')), joinError(JoinError.teamLimit));
  });

  test('an open team takes me at once; I can leave it', () async {
    final before = await backend.team('tm1');
    expect(before.joinPolicy, TeamJoinPolicy.open);
    expect(before.myStatus, isNull);

    final joined = await backend.joinTeam('tm1');
    expect(joined.myStatus, MyTeamStatus.member);
    expect(joined.isMember, isTrue);
    expect(joined.memberCount, before.memberCount + 1);
    expect(joined.members.last.id, kMeId);
    expect(joined.requests, isEmpty, reason: 'only the captain sees requests');
    expect(backend.joinTeam('tm1'), joinError(JoinError.alreadyJoined));
    expect((await backend.teams('almaty')).first.id, 'tm1', reason: 'my teams come first in any city');

    await backend.leaveTeam('tm1');
    expect((await backend.team('tm1')).myStatus, isNull);
    expect(backend.leaveTeam('tm1'), joinError(JoinError.notFound));
    expect(backend.joinTeam('nope'), joinError(JoinError.notFound));
    expect(backend.team('nope'), joinError(JoinError.notFound));
  });

  test('an approval team takes a request the captain decides', () async {
    final asked = await backend.joinTeam('tm2');
    expect(asked.myStatus, MyTeamStatus.requested);
    expect(asked.myRequestId, isNotNull);
    expect(backend.joinTeam('tm2'), joinError(JoinError.alreadyRequested));
    await backend.withdrawTeamRequest(asked.myRequestId!);
    expect((await backend.team('tm2')).myStatus, isNull);
    expect(backend.withdrawTeamRequest(asked.myRequestId!), joinError(JoinError.notFound));

    final mine = await backend.createTeam(draft('Night Owls', joinPolicy: TeamJoinPolicy.approval));
    await backend.joinTeamAs('p2', mine.id);
    await backend.joinTeamAs('p4', mine.id);
    final waiting = await backend.team(mine.id);
    expect(waiting.requests.map((r) => r.userId), ['p2', 'p4']);
    expect(waiting.requests.first.name, 'Dilnoza');
    expect(waiting.requests.first.level, 2);
    expect(waiting.requests.first.rating, 2.5);
    expect(waiting.memberCount, 1);

    final approved = await backend.decideTeamRequest(waiting.requests.first.id, approve: true);
    expect(approved.members.map((m) => m.id), [kMeId, 'p2']);
    expect(approved.requests.map((r) => r.userId), ['p4']);
    final declined = await backend.decideTeamRequest(waiting.requests.last.id, approve: false);
    expect(declined.members.map((m) => m.id), [kMeId, 'p2']);
    expect(declined.requests, isEmpty);
    expect(backend.decideTeamRequest(waiting.requests.last.id, approve: true), joinError(JoinError.notFound));
    expect(backend.decideTeamRequest('nope', approve: true), joinError(JoinError.notFound));

    // Someone else's team: not mine to decide.
    final other = await backend.joinTeamAs('p8', 'tm2');
    expect(other.myRequestId, isNotNull);
    expect(backend.decideTeamRequest(other.myRequestId!, approve: true), joinError(JoinError.forbidden));
  });

  test('pending requests stay when a team opens up; only name, description and policy change', () async {
    final mine = await backend.createTeam(draft('Night Owls', joinPolicy: TeamJoinPolicy.approval));
    await backend.joinTeamAs('p2', mine.id);
    await backend.createTeam(draft('Early Birds'));

    final updated = await backend.updateTeam(
      mine.id,
      draft('Late Owls', sportId: 'tennis', cityId: 'almaty', description: 'Fridays'),
    );
    expect(updated.name, 'Late Owls');
    expect(updated.description, 'Fridays');
    expect(updated.joinPolicy, TeamJoinPolicy.open);
    expect(updated.sportId, 'padel');
    expect(updated.cityId, 'tashkent');
    expect(updated.requests.map((r) => r.userId), ['p2']);

    // The same name again is fine; another team's name is not.
    await backend.updateTeam(mine.id, draft('Late Owls'));
    expect((await backend.team(mine.id)).description, isNull, reason: 'no description clears it');
    expect(backend.updateTeam(mine.id, draft('early birds')), joinError(JoinError.nameTaken));
    expect(backend.updateTeam(mine.id, draft('ab')), joinError(JoinError.invalidArgument));
    expect(backend.updateTeam('tm1', draft('Mine now')), joinError(JoinError.forbidden));
    expect(backend.updateTeam('nope', draft('Mine now')), joinError(JoinError.notFound));
  });

  test('an invite lets me in, even to an approval team', () async {
    final theirs = await backend.createTeamAs('p1', draft('Aziz Squad', joinPolicy: TeamJoinPolicy.approval));
    expect(theirs.myStatus, MyTeamStatus.captain, reason: 'as the creator sees it');
    await backend.inviteToTeamAs('p1', theirs.id, kMeId);
    final invited = await backend.team(theirs.id);
    expect(invited.myStatus, MyTeamStatus.invited);

    final accepted = await backend.respondTeamInvite(theirs.id, accept: true);
    expect(accepted.myStatus, MyTeamStatus.member);
    expect(accepted.members.map((m) => m.id), ['p1', kMeId]);
    expect(backend.respondTeamInvite(theirs.id, accept: true), joinError(JoinError.notFound));

    // Declining, then being invited again; joining with an open invite joins at once.
    final other = await backend.createTeamAs('p5', draft('Arman Squad', joinPolicy: TeamJoinPolicy.approval));
    await backend.inviteToTeamAs('p5', other.id, kMeId);
    expect((await backend.respondTeamInvite(other.id, accept: false)).myStatus, isNull);
    await backend.inviteToTeamAs('p5', other.id, kMeId);
    expect((await backend.joinTeam(other.id)).myStatus, MyTeamStatus.member);
  });

  test('only the captain invites, and never themselves, a member or a deleted player', () async {
    final mine = await backend.createTeam(draft('Night Owls'));
    await backend.joinTeamAs('p2', mine.id);
    expect(backend.inviteToTeam(mine.id, kMeId), joinError(JoinError.invalidArgument));
    expect(backend.inviteToTeam(mine.id, 'p2'), joinError(JoinError.alreadyJoined));
    expect(backend.inviteToTeam(mine.id, 'nobody'), joinError(JoinError.notFound));
    backend.markDeleted('p4');
    expect(backend.inviteToTeam(mine.id, 'p4'), joinError(JoinError.notFound));
    expect(backend.inviteToTeam('tm1', 'p2'), joinError(JoinError.forbidden));
    await backend.inviteToTeam(mine.id, 'p3');
    expect((await backend.team(mine.id)).memberCount, 2, reason: 'an invite is not a membership');
  });

  test('the captain cannot leave until they hand the team over', () async {
    final mine = await backend.createTeam(draft('Night Owls'));
    await backend.joinTeamAs('p2', mine.id);
    expect(backend.leaveTeam(mine.id), joinError(JoinError.captainCannotLeave));
    expect(backend.transferCaptain(mine.id, kMeId), joinError(JoinError.invalidArgument));
    expect(backend.transferCaptain(mine.id, 'p3'), joinError(JoinError.notFound));
    expect(backend.transferCaptain('tm1', 'p5'), joinError(JoinError.forbidden));

    final handed = await backend.transferCaptain(mine.id, 'p2');
    expect(handed.captainId, 'p2');
    expect(handed.myStatus, MyTeamStatus.member);
    expect(handed.members.first.id, 'p2', reason: 'the captain comes first');
    expect(handed.members.first.captain, isTrue);
    await backend.leaveTeam(mine.id);
    final after = await backend.team(mine.id);
    expect(after.members.map((m) => m.id), ['p2']);
    expect(after.myStatus, isNull);
  });

  test('the captain removes a member, never themselves', () async {
    final mine = await backend.createTeam(draft('Night Owls'));
    await backend.joinTeamAs('p2', mine.id);
    final removed = await backend.removeTeamMember(mine.id, 'p2');
    expect(removed.members.map((m) => m.id), [kMeId]);
    expect(backend.removeTeamMember(mine.id, 'p2'), joinError(JoinError.notFound));
    expect(backend.removeTeamMember(mine.id, kMeId), joinError(JoinError.invalidArgument));
    expect(backend.removeTeamMember('tm1', 'p5'), joinError(JoinError.forbidden));
  });

  test('the captain deletes the team', () async {
    final mine = await backend.createTeam(draft('Night Owls'));
    expect(backend.deleteTeam('tm1'), joinError(JoinError.forbidden));
    await backend.deleteTeam(mine.id);
    expect(backend.team(mine.id), joinError(JoinError.notFound));
    expect((await backend.teams('tashkent')).map((t) => t.id), isNot(contains(mine.id)));
    expect(backend.deleteTeam(mine.id), joinError(JoinError.notFound));
  });

  test('every team notice has its sentence, and all but team_deleted open the team', () {
    AppNotification notice(String kind, [Map<String, Object?>? payload]) => AppNotification(
      id: 'n',
      kind: kind,
      category: 'teams',
      payload: payload ?? const {'team_id': 't1', 'team_name': 'Night Owls', 'actor_name': 'Aziz'},
      createdAt: utcNow,
      read: false,
    );
    for (final kind in [
      'team_invite',
      'team_join_request',
      'team_join_approved',
      'team_join_declined',
      'team_removed',
      'team_captain',
    ]) {
      expect(notice(kind).route, '/teams/t1', reason: kind);
      expect(notice(kind, const {}).route, isNull, reason: '$kind without a team');
    }
    expect(notice('team_deleted').route, isNull);

    for (final code in ['en', 'ru', 'uz', 'kk']) {
      final l = lookupAppLocalizations(Locale(code));
      final texts = [
        for (final kind in [
          'team_invite',
          'team_join_request',
          'team_join_approved',
          'team_join_declined',
          'team_removed',
          'team_captain',
          'team_deleted',
        ])
          notificationText(l, code, notice(kind)),
      ];
      expect(texts, everyElement(contains('Night Owls')), reason: code);
      expect(texts.toSet(), hasLength(texts.length), reason: code);
      expect(texts.take(2), everyElement(contains('Aziz')), reason: code);
      expect(notificationText(l, code, notice('team_invite', const {'team_id': 't1'})), l.notifUnknown);
    }
  });

  test('my profile lists my teams by name', () async {
    await backend.createTeam(draft('Night Owls'));
    await backend.joinTeam('tm4');
    final teams = (await backend.profile(kMeId)).teams;
    expect(teams.map((t) => t.name), ['Hoops TAS', 'Night Owls']);
    expect(teams.first.sportId, 'basketball');
    expect((await backend.profile('p1')).teams.map((t) => t.id), containsAll(['tm1', 'tm2']));
  });
}
