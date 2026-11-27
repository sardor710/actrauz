// Teams (M7 design §7). Pure types: the backend and the sample data fill
// them in, with the rules of supabase/migrations/20261127130000_teams.sql.

import 'games.dart';

/// Who may join: anyone at once, or only those the captain approves (or
/// invites).
enum TeamJoinPolicy { open, approval }

/// The signed-in player's place in a team. Precedence as the backend gives
/// it: captain, member, invited, requested.
enum MyTeamStatus { captain, member, requested, invited }

/// A standing group of players in one sport and one city, shown with its
/// initials on the colour [colorSeed] picks. The list calls fill only the
/// summary; [members], [requests] and [games] come with the team page.
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.sportId,
    required this.cityId,
    required this.captainId,
    this.description,
    this.joinPolicy = TeamJoinPolicy.open,
    this.colorSeed = 0,
    this.memberCount = 0,
    this.upcomingGames = 0,
    this.myStatus,
    this.myRequestId,
    this.members = const [],
    this.requests = const [],
    this.games = const [],
  });

  /// The most teams a player can create as captain (a transfer or a
  /// captain's account deletion can leave someone with more).
  static const maxCaptained = 5;

  /// Name length after trimming, and description length, as the backend
  /// checks them.
  static const minName = 3;
  static const maxName = 40;
  static const maxDescription = 500;

  final String id;
  final String name;
  final String sportId;
  final String cityId;
  final String? description;
  final TeamJoinPolicy joinPolicy;

  /// 0–7.
  final int colorSeed;

  /// `kMeId` when the signed-in player is the captain.
  final String captainId;
  final int memberCount;

  /// Team games that have not started and are not cancelled.
  final int upcomingGames;
  final MyTeamStatus? myStatus;

  /// The signed-in player's pending join request, to withdraw it.
  final String? myRequestId;

  /// The captain first, then in the order they joined.
  final List<TeamMember> members;

  /// Pending join requests, oldest first; only the captain sees them.
  final List<TeamRequest> requests;

  /// Upcoming team games the signed-in player may see, soonest first.
  final List<Game> games;

  bool get isCaptain => myStatus == MyTeamStatus.captain;

  /// The captain or a member.
  bool get isMember => myStatus == MyTeamStatus.captain || myStatus == MyTeamStatus.member;
}

/// Someone in a team, as everyone sees them.
class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    this.level = 1,
    this.rating,
    this.provisional = false,
    this.reliability = Reliability.fresh,
    this.captain = false,
    this.deleted = false,
  });

  final String id;

  /// Empty for a deleted account.
  final String name;

  /// Level 1–5 in the team's sport; 1 when they have not set one.
  final int level;

  /// Rating in the team's sport when it is a rated one and they have one.
  final double? rating;
  final bool provisional;
  final Reliability reliability;
  final bool captain;
  final bool deleted;
}

/// A pending request to join an approval team, as the captain sees it.
class TeamRequest {
  const TeamRequest({
    required this.id,
    required this.userId,
    required this.name,
    this.level = 1,
    this.rating,
    this.reliability = Reliability.fresh,
  });

  final String id;
  final String userId;
  final String name;
  final int level;
  final double? rating;
  final Reliability reliability;
}

/// What the captain fills in. Editing changes only [name], [description] and
/// [joinPolicy]; a team keeps its sport and city.
class TeamDraft {
  const TeamDraft({
    required this.name,
    required this.sportId,
    required this.cityId,
    this.description,
    this.joinPolicy = TeamJoinPolicy.open,
  });

  final String name;
  final String sportId;
  final String cityId;

  /// Null or blank clears it.
  final String? description;
  final TeamJoinPolicy joinPolicy;
}

/// A team on a player's profile.
class TeamRef {
  const TeamRef({required this.id, required this.name, required this.sportId});

  final String id;
  final String name;
  final String sportId;
}
