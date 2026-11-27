import '../../domain/games.dart';
import '../../domain/teams.dart';
import 'sample_data.dart';

/// Teams in memory, with the database's rules (`app.create_team` …
/// `app.transfer_captain`, `app.team_json`, `app.list_teams` and the team
/// step of `app.delete_account` in
/// supabase/migrations/20261127130000_teams.sql). Every call names the
/// player acting, so tests can act as anyone; only the demo player has an
/// inbox ([notify] drops the rest).
class SampleTeams {
  SampleTeams({
    required this.utcNow,
    required this.memberOf,
    required this.nameOf,
    required this.userExists,
    required this.isDeleted,
    required this.activeSport,
    required this.knownCity,
    required this.notify,
    required this.upcomingGames,
    required this.gamesFor,
  }) {
    for (final (i, seed) in kTeamSeeds.indexed) {
      final created = utcNow().subtract(Duration(days: seed.daysAgo));
      _teams[seed.id] = _Team(
        id: seed.id,
        name: seed.name,
        sportId: seed.sportId,
        cityId: seed.cityId,
        description: seed.description,
        joinPolicy: seed.joinPolicy,
        colorSeed: i % 8,
        captainId: seed.captainId,
        createdAt: created,
      )..members.addAll({
          seed.captainId: created,
          for (final (j, id) in seed.memberIds.indexed) id: created.add(Duration(days: j + 1)),
        });
    }
  }

  final DateTime Function() utcNow;

  /// The player as a game shows them in the team's sport: name, level,
  /// rating, reliability.
  final GameMember Function(String userId, String sportId) memberOf;
  final String Function(String userId) nameOf;
  final bool Function(String userId) userExists;
  final bool Function(String userId) isDeleted;
  final bool Function(String sportId) activeSport;
  final bool Function(String cityId) knownCity;
  final void Function(String userId, String kind, String category, Map<String, Object?> payload) notify;

  /// How many of the team's games have not started and are not cancelled,
  /// whoever asks (`team_summary_json.upcoming_games`).
  final int Function(String teamId) upcomingGames;

  /// Those games as [viewer] sees them, only the ones they may see, soonest
  /// first (`team_json.games`).
  final List<Game> Function(String teamId, String viewer) gamesFor;

  final Map<String, _Team> _teams = {};
  final List<_Ask> _asks = [];
  int _nextId = 1;

  // ---- Reading ----

  /// The caller's teams (any city) first, then the other teams of [cityId];
  /// each group by member count, largest first, then name, then id.
  List<Team> list(String viewer, String cityId) {
    final listed = [
      for (final t in _teams.values)
        if (t.cityId == cityId || t.members.containsKey(viewer)) t,
    ]..sort((a, b) {
        final byMine = (b.members.containsKey(viewer) ? 1 : 0) - (a.members.containsKey(viewer) ? 1 : 0);
        if (byMine != 0) return byMine;
        final bySize = b.members.length.compareTo(a.members.length);
        if (bySize != 0) return bySize;
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return [for (final t in listed) _summary(t, viewer)];
  }

  Team team(String viewer, String id) => _view(_find(id), viewer);

  /// Every team, newest first, at most 200, as the admin's removal list.
  List<Team> all(String viewer) => [
    for (final t in (_teams.values.toList()
          ..sort((a, b) {
            final byDate = b.createdAt.compareTo(a.createdAt);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          }))
        .take(200))
      _summary(t, viewer),
  ];

  /// [userId]'s teams by name, as `player_json.teams`.
  List<TeamRef> refsOf(String userId) => [
    for (final t in (_teams.values.where((t) => t.members.containsKey(userId)).toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      })))
      TeamRef(id: t.id, name: t.name, sportId: t.sportId),
  ];

  /// The team a game points to, while it exists: its current name, as
  /// `game_json.team` reads it.
  TeamRef? refOf(String id) {
    final t = _teams[id];
    return t == null ? null : TeamRef(id: t.id, name: t.name, sportId: t.sportId);
  }

  /// Whether [userId] is the captain or a member of the team (false once it
  /// is gone).
  bool isMember(String id, String userId) => _teams[id]?.members.containsKey(userId) ?? false;

  // ---- Team games ----

  /// The team [userId] posts a game for, as `app.create_game` checks it:
  /// [JoinError.notFound] for an unknown team, [JoinError.captainOnly] unless
  /// they are its captain. Gives the members to tell, the poster excluded.
  ({TeamRef team, String cityId, List<String> others}) postingFor(String userId, String id) {
    final t = _captained(userId, id);
    return (
      team: TeamRef(id: t.id, name: t.name, sportId: t.sportId),
      cityId: t.cityId,
      others: [for (final m in _ordered(t)) if (m != userId) m],
    );
  }

  // ---- Creating, editing, deleting ----

  Team create(String userId, TeamDraft draft) {
    final fields = _fields(draft);
    if (!activeSport(draft.sportId) || !knownCity(draft.cityId)) throw const JoinException(JoinError.invalidArgument);
    if (_teams.values.where((t) => t.captainId == userId).length >= Team.maxCaptained) {
      throw const JoinException(JoinError.teamLimit);
    }
    _checkName(fields.name, draft.cityId, draft.sportId);
    final id = 'team${_nextId++}';
    final now = utcNow();
    final team = _teams[id] = _Team(
      id: id,
      name: fields.name,
      sportId: draft.sportId,
      cityId: draft.cityId,
      description: fields.description,
      joinPolicy: draft.joinPolicy,
      colorSeed: id.codeUnits.fold(0, (sum, c) => sum + c) % 8,
      captainId: userId,
      createdAt: now,
    )..members[userId] = now;
    return _view(team, userId);
  }

  /// Name, description and join policy only. Pending requests stay when a
  /// team opens up: the captain still decides them.
  Team update(String userId, String id, TeamDraft draft) {
    final team = _captained(userId, id);
    final fields = _fields(draft);
    _checkName(fields.name, team.cityId, team.sportId, except: team.id);
    team
      ..name = fields.name
      ..description = fields.description
      ..joinPolicy = draft.joinPolicy;
    return _view(team, userId);
  }

  void delete(String userId, String id) => _drop(_captained(userId, id), userId);

  /// What an admin's removal does: [delete] without the captain check.
  /// [JoinError.notFound] for an unknown team.
  void dropById(String id, String actor) => _drop(_find(id), actor);

  /// Tells every member but [actor] that the team is going, then removes it
  /// with its requests and invites.
  void _drop(_Team team, String actor) {
    for (final id in team.members.keys) {
      if (id != actor) notify(id, 'team_deleted', 'teams', _note(team, actor));
    }
    _teams.remove(team.id);
    _asks.removeWhere((a) => a.teamId == team.id);
  }

  /// The team as the database's audit log keeps it before a deletion.
  Map<String, dynamic> rowOf(String id) {
    final t = _find(id);
    return {
      'id': t.id,
      'name': t.name,
      'sport_id': t.sportId,
      'city_id': t.cityId,
      'description': t.description,
      'join_policy': t.joinPolicy.name,
      'color_seed': t.colorSeed,
      'captain_id': t.captainId,
    };
  }

  // ---- Joining and leaving ----

  /// An open team, or one that invited the player: a member at once. An
  /// approval team: a pending request, and the captain hears.
  Team join(String userId, String id) {
    final team = _find(id);
    if (team.members.containsKey(userId)) throw const JoinException(JoinError.alreadyInTeam);
    if (team.joinPolicy == TeamJoinPolicy.open || team.invites[userId] == _InviteStatus.pending) {
      _addMember(team, userId);
      return _view(team, userId);
    }
    if (_pendingAsk(team.id, userId) != null) throw const JoinException(JoinError.alreadyAskedTeam);
    _asks.add(_Ask(id: 'tr${_nextId++}', teamId: team.id, userId: userId, createdAt: utcNow()));
    notify(team.captainId, 'team_join_request', 'teams', _note(team, userId));
    return _view(team, userId);
  }

  void leave(String userId, String id) {
    final team = _find(id);
    if (team.captainId == userId) throw const JoinException(JoinError.captainCannotLeave);
    if (team.members.remove(userId) == null) throw const JoinException(JoinError.notFound);
  }

  void withdraw(String userId, String requestId) {
    final ask = _asks.where((a) => a.id == requestId && a.userId == userId && a.pending).firstOrNull;
    if (ask == null) throw const JoinException(JoinError.notFound);
    ask.status = _AskStatus.withdrawn;
  }

  /// The captain approves (a member) or declines a pending request; the
  /// player hears either way. A deleted account is never approved.
  Team decide(String userId, String requestId, {required bool approve}) {
    final ask = _asks.where((a) => a.id == requestId).firstOrNull;
    if (ask == null) throw const JoinException(JoinError.notFound);
    final team = _captained(userId, ask.teamId);
    if (!ask.pending) throw const JoinException(JoinError.notFound);
    if (approve) {
      if (isDeleted(ask.userId)) throw const JoinException(JoinError.notFound);
      if (team.members.containsKey(ask.userId)) throw const JoinException(JoinError.alreadyJoined);
      _addMember(team, ask.userId);
      notify(ask.userId, 'team_join_approved', 'teams', _note(team, userId));
    } else {
      ask.status = _AskStatus.declined;
      notify(ask.userId, 'team_join_declined', 'teams', _note(team, userId));
    }
    return _view(team, userId);
  }

  // ---- Captain tools and invites ----

  Team remove(String userId, String id, String memberId) {
    final team = _captained(userId, id);
    if (memberId == team.captainId) throw const JoinException(JoinError.invalidArgument);
    if (team.members.remove(memberId) == null) throw const JoinException(JoinError.notFound);
    notify(memberId, 'team_removed', 'teams', _note(team, userId));
    return _view(team, userId);
  }

  /// Inviting again reopens a declined or used invite; while one is open,
  /// nothing new is sent.
  void invite(String userId, String id, String inviteeId) {
    final team = _captained(userId, id);
    if (inviteeId == userId) throw const JoinException(JoinError.invalidArgument);
    if (!userExists(inviteeId) || isDeleted(inviteeId)) throw const JoinException(JoinError.notFound);
    if (team.members.containsKey(inviteeId)) throw const JoinException(JoinError.alreadyJoined);
    final previous = team.invites[inviteeId];
    team.invites[inviteeId] = _InviteStatus.pending;
    if (previous != _InviteStatus.pending) notify(inviteeId, 'team_invite', 'teams', _note(team, userId));
  }

  /// Accepting makes the player a member, whatever the join policy.
  Team respond(String userId, String id, {required bool accept}) {
    final team = _find(id);
    if (team.invites[userId] != _InviteStatus.pending) throw const JoinException(JoinError.notFound);
    if (accept) {
      _addMember(team, userId);
    } else {
      team.invites[userId] = _InviteStatus.declined;
    }
    return _view(team, userId);
  }

  /// The 5-team limit applies to creating only.
  Team transfer(String userId, String id, String memberId) {
    final team = _captained(userId, id);
    if (memberId == userId) throw const JoinException(JoinError.invalidArgument);
    if (!team.members.containsKey(memberId) || isDeleted(memberId)) throw const JoinException(JoinError.notFound);
    team.captainId = memberId;
    notify(memberId, 'team_captain', 'teams', _note(team, userId));
    return _view(team, userId);
  }

  // ---- A deleted account ----

  /// Each team [userId] captains goes to the other live member who joined
  /// first (who hears), or is removed when no one is left; then their
  /// memberships, requests and invites go. Call before the account counts as
  /// deleted, so the notice still carries their name.
  void accountDeleted(String userId) {
    for (final team in _teams.values.where((t) => t.captainId == userId).toList()) {
      final heir = _ordered(team).where((id) => id != userId && !isDeleted(id)).firstOrNull;
      if (heir == null) {
        _teams.remove(team.id);
        _asks.removeWhere((a) => a.teamId == team.id);
      } else {
        team.captainId = heir;
        notify(heir, 'team_captain', 'teams', _note(team, userId));
      }
    }
    for (final team in _teams.values) {
      team.members.remove(userId);
      team.invites.remove(userId);
    }
    _asks.removeWhere((a) => a.userId == userId);
  }

  // ---- Rules ----

  _Team _find(String id) => _teams[id] ?? (throw const JoinException(JoinError.notFound));

  _Team _captained(String userId, String id) {
    final team = _find(id);
    if (team.captainId != userId) throw const JoinException(JoinError.captainOnly);
    return team;
  }

  /// The trimmed name and description (blank → none), checked as
  /// `app.team_fields` does.
  static ({String name, String? description}) _fields(TeamDraft draft) {
    final name = draft.name.trim();
    final description = draft.description?.trim() ?? '';
    // Characters, as the database counts them.
    if (name.runes.length < Team.minName ||
        name.runes.length > Team.maxName ||
        description.runes.length > Team.maxDescription) {
      throw const JoinException(JoinError.invalidArgument);
    }
    return (name: name, description: description.isEmpty ? null : description);
  }

  void _checkName(String name, String cityId, String sportId, {String? except}) {
    final taken = _teams.values.any(
      (t) => t.id != except && t.cityId == cityId && t.sportId == sportId && t.name.toLowerCase() == name.toLowerCase(),
    );
    if (taken) throw const JoinException(JoinError.nameTaken);
  }

  /// A member: their pending request is approved and their pending invite
  /// accepted.
  void _addMember(_Team team, String userId) {
    team.members[userId] = utcNow();
    _pendingAsk(team.id, userId)?.status = _AskStatus.approved;
    if (team.invites[userId] == _InviteStatus.pending) team.invites[userId] = _InviteStatus.accepted;
  }

  _Ask? _pendingAsk(String teamId, String userId) =>
      _asks.where((a) => a.teamId == teamId && a.userId == userId && a.pending).firstOrNull;

  Map<String, Object?> _note(_Team t, String actor) => {'team_id': t.id, 'team_name': t.name, 'actor_name': nameOf(actor)};

  /// Member ids, captain first, then by joining, then by id.
  List<String> _ordered(_Team t) => t.members.keys.toList()
    ..sort((a, b) {
      if (a == t.captainId) return -1;
      if (b == t.captainId) return 1;
      final byJoin = t.members[a]!.compareTo(t.members[b]!);
      return byJoin != 0 ? byJoin : a.compareTo(b);
    });

  MyTeamStatus? _status(_Team t, String viewer) => t.captainId == viewer
      ? MyTeamStatus.captain
      : t.members.containsKey(viewer)
      ? MyTeamStatus.member
      : t.invites[viewer] == _InviteStatus.pending
      ? MyTeamStatus.invited
      : _pendingAsk(t.id, viewer) != null
      ? MyTeamStatus.requested
      : null;

  Team _summary(
    _Team t,
    String viewer, {
    List<TeamMember> members = const [],
    List<TeamRequest> requests = const [],
    List<Game> games = const [],
  }) =>
      Team(
        id: t.id,
        name: t.name,
        sportId: t.sportId,
        cityId: t.cityId,
        description: t.description,
        joinPolicy: t.joinPolicy,
        colorSeed: t.colorSeed,
        captainId: t.captainId,
        memberCount: t.members.length,
        upcomingGames: upcomingGames(t.id),
        myStatus: _status(t, viewer),
        myRequestId: _pendingAsk(t.id, viewer)?.id,
        members: members,
        requests: requests,
        games: games,
      );

  Team _view(_Team t, String viewer) => _summary(
    t,
    viewer,
    members: [for (final id in _ordered(t)) _teamMember(memberOf(id, t.sportId), captain: id == t.captainId)],
    requests: t.captainId == viewer
        ? [
            for (final a in _asks.where((a) => a.teamId == t.id && a.pending).toList()
              ..sort((a, b) {
                final byDate = a.createdAt.compareTo(b.createdAt);
                return byDate != 0 ? byDate : a.id.compareTo(b.id);
              }))
              _request(a, memberOf(a.userId, t.sportId)),
          ]
        : const [],
    games: gamesFor(t.id, viewer),
  );
}

TeamMember _teamMember(GameMember m, {required bool captain}) => TeamMember(
  id: m.id,
  name: m.name,
  level: m.level,
  rating: m.rating,
  provisional: m.provisional,
  reliability: m.reliability,
  captain: captain,
  deleted: m.deleted,
);

TeamRequest _request(_Ask a, GameMember m) =>
    TeamRequest(id: a.id, userId: a.userId, name: m.name, level: m.level, rating: m.rating, reliability: m.reliability);

class _Team {
  _Team({
    required this.id,
    required this.name,
    required this.sportId,
    required this.cityId,
    required this.description,
    required this.joinPolicy,
    required this.colorSeed,
    required this.captainId,
    required this.createdAt,
  });

  final String id;
  String name;
  final String sportId;
  final String cityId;
  String? description;
  TeamJoinPolicy joinPolicy;
  final int colorSeed;
  String captainId;
  final DateTime createdAt;

  /// Member id → when they joined; the captain is a member too.
  final Map<String, DateTime> members = {};
  final Map<String, _InviteStatus> invites = {};
}

enum _InviteStatus { pending, accepted, declined }

enum _AskStatus { pending, approved, declined, withdrawn }

class _Ask {
  _Ask({required this.id, required this.teamId, required this.userId, required this.createdAt});

  final String id;
  final String teamId;
  final String userId;
  final DateTime createdAt;
  _AskStatus status = _AskStatus.pending;

  bool get pending => status == _AskStatus.pending;
}
