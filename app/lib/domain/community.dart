// Players, reliability, the inbox and Game Requests (product spec §8.3, §9.2,
// §9.4, §13). Pure types: the backend and the sample data fill them in.

import 'competitive.dart';

// ---- Reliability ----

enum ReliabilityBadge {
  /// Fewer than three reliability events so far and a good score.
  isNew,
  reliable,

  /// At most one upcoming booking at a time.
  limited,

  /// Cannot book, join, create or ask until old events pass 90 days.
  blocked,
}

class Reliability {
  const Reliability({required this.score, required this.badge});

  /// What a player who has done nothing yet has.
  static const fresh = Reliability(score: 80, badge: ReliabilityBadge.isNew);

  /// 0–100.
  final int score;
  final ReliabilityBadge badge;

  bool get isBlocked => badge == ReliabilityBadge.blocked;
  bool get isLimited => badge == ReliabilityBadge.limited;
}

enum ReliabilityKind {
  noShow(-20),
  lateCancel(-5),
  bookingPaid(2),
  gameCompleted(2);

  const ReliabilityKind(this.delta);

  final int delta;
}

class ReliabilityEvent {
  const ReliabilityEvent({required this.kind, required this.ref, required this.at});

  final ReliabilityKind kind;

  /// The booking or game the event is about. One event per kind and ref.
  final String ref;
  final DateTime at;
}

/// The score and badge for [events] as of [now] (plan: Reliability): only the
/// last 90 days count, positive credit is capped at +20 so it cannot be
/// banked against no-shows, and the badge is `new` until three events.
Reliability reliabilityFrom(Iterable<ReliabilityEvent> events, {required DateTime now}) {
  const window = Duration(days: 90);
  const maxCredit = 20;
  var positive = 0;
  var negative = 0;
  var ever = 0;
  for (final e in events) {
    ever++;
    if (!e.at.isAfter(now.subtract(window))) continue;
    if (e.kind.delta > 0) {
      positive += e.kind.delta;
    } else {
      negative += e.kind.delta;
    }
  }
  final score = (80 + (positive < maxCredit ? positive : maxCredit) + negative).clamp(0, 100).toInt();
  return Reliability(
    score: score,
    badge: score >= 70
        ? (ever < 3 ? ReliabilityBadge.isNew : ReliabilityBadge.reliable)
        : score >= 50
        ? ReliabilityBadge.limited
        : ReliabilityBadge.blocked,
  );
}

// ---- People ----

/// Someone in a game, a join request or a Game Request, as the others see
/// them. The signed-in player has id `kMeId`.
class GameMember {
  const GameMember({
    required this.id,
    required this.name,
    this.level = 1,
    this.rating,
    this.provisional = false,
    this.reliability = Reliability.fresh,
    this.deleted = false,
  });

  final String id;
  final String name;

  /// The account was deleted: the screens show "Deleted player" (the name is
  /// empty by then).
  final bool deleted;

  /// Level 1–5 in the game's sport; 1 when they have not set one.
  final int level;

  /// Rating in the game's sport when it is a rated one and they have a
  /// rating; null otherwise.
  final double? rating;

  /// The [rating] has fewer than ten rated games behind it.
  final bool provisional;
  final Reliability reliability;
}

/// A player's public profile (no phone, no contact details).
class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    this.cityId,
    this.levels = const {},
    this.ratings = const {},
    this.reliability = Reliability.fresh,
    this.gamesPlayed = 0,
    this.sportsmanship = Sportsmanship.none,
    this.deleted = false,
  });

  final String id;
  final String name;
  final String? cityId;

  /// The account was deleted.
  final bool deleted;

  /// Self-selected level 1–5 per sport id (derived from the rating in a rated
  /// sport).
  final Map<String, int> levels;

  /// Rating per rated sport the player has ticked.
  final Map<String, SportRating> ratings;
  final Reliability reliability;

  /// Completed games the player took part in.
  final int gamesPlayed;

  /// Thumbs up and down from other players (design §6.1).
  final Sportsmanship sportsmanship;

  int levelFor(String sportId) => levels[sportId] ?? 1;
}

// ---- Game Requests ("looking for players") ----

enum GameRequestStatus { open, converted, expired, cancelled }

enum MyRequestStatus { host, interested }

class GameRequest {
  const GameRequest({
    required this.id,
    required this.sportId,
    required this.cityId,
    required this.hostId,
    required this.hostName,
    required this.start,
    required this.end,
    required this.playersNeeded,
    required this.createdAt,
    this.venueId,
    this.area,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.minRating,
    this.maxRating,
    this.note,
    this.status = GameRequestStatus.open,
    this.gameId,
    this.interested = const [],
    int? interestedCount,
    this.myStatus,
    this.hostDeleted = false,
  }) : interestedCount = interestedCount ?? interested.length;

  final String id;
  final String sportId;
  final String cityId;
  final String hostId;
  final String hostName;

  /// The poster's account was deleted (the name is empty by then).
  final bool hostDeleted;
  final String? venueId;

  /// Free text: the part of town the poster can play in.
  final String? area;

  /// The window the poster can play in, in the city's wall-clock time.
  final DateTime start;
  final DateTime end;

  /// Other players wanted; the poster is not counted.
  final int playersNeeded;
  final int minLevel;
  final int maxLevel;

  /// The rating range in a rated sport (null in a simple sport); the level
  /// range is derived from it.
  final double? minRating;
  final double? maxRating;
  final String? note;
  final GameRequestStatus status;

  /// The game it became, once converted.
  final String? gameId;

  /// In the order they tapped "I'm in".
  final List<GameMember> interested;
  final int interestedCount;
  final MyRequestStatus? myStatus;
  final DateTime createdAt;

  bool get isOpen => status == GameRequestStatus.open;
  bool get isMine => myStatus == MyRequestStatus.host;
  bool get imIn => myStatus == MyRequestStatus.interested;

  GameRequest copyWith({
    GameRequestStatus? status,
    String? gameId,
    List<GameMember>? interested,
    MyRequestStatus? myStatus,
    bool clearMyStatus = false,
  }) => GameRequest(
    id: id,
    sportId: sportId,
    cityId: cityId,
    hostId: hostId,
    hostName: hostName,
    hostDeleted: hostDeleted,
    start: start,
    end: end,
    playersNeeded: playersNeeded,
    createdAt: createdAt,
    venueId: venueId,
    area: area,
    minLevel: minLevel,
    maxLevel: maxLevel,
    minRating: minRating,
    maxRating: maxRating,
    note: note,
    status: status ?? this.status,
    gameId: gameId ?? this.gameId,
    interested: interested ?? this.interested,
    myStatus: clearMyStatus ? null : (myStatus ?? this.myStatus),
  );
}

/// What a player fills in to post a Game Request.
class GameRequestDraft {
  const GameRequestDraft({
    required this.sportId,
    required this.playersNeeded,
    required this.start,
    required this.end,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.minRating,
    this.maxRating,
    this.venueId,
    this.area,
    this.note,
  });

  final String sportId;
  final int playersNeeded;
  final int minLevel;
  final int maxLevel;

  /// A rated sport: both ends, or neither (the level range is then converted).
  final double? minRating;
  final double? maxRating;
  final DateTime start;
  final DateTime end;
  final String? venueId;
  final String? area;
  final String? note;
}

// ---- Inbox and settings ----

/// The categories a player can mute (spec §13; `ratings` and `teams` from M7).
const kNotificationCategories = [
  'bookings',
  'venue',
  'games',
  'requests',
  'invites',
  'tournaments',
  'ratings',
  'teams',
];

/// One inbox entry. The database stores no sentence: the app renders the text
/// from [kind] and [payload].
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.category,
    required this.payload,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String kind;
  final String category;

  /// Always has `sport_id` and `starts_local` when there is one; the rest
  /// depends on the kind (`game_id`, `request_id`, `actor_name`, …).
  final Map<String, Object?> payload;
  final DateTime createdAt;
  final bool read;

  /// The screen this entry opens, or null when there is nothing to open.
  String? get route {
    String? text(String key) {
      final value = payload[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    switch (kind) {
      case 'booking_confirmed' || 'booking_cancelled_by_venue' || 'booking_reminder':
        return '/bookings';
      case 'venue_new_booking' || 'venue_booking_cancelled':
        final venueId = text('venue_id');
        return venueId == null ? null : '/owner/$venueId';
      case 'game_joined' ||
          'game_left' ||
          'join_request' ||
          'join_approved' ||
          'join_declined' ||
          'game_full' ||
          'game_changed' ||
          'game_cancelled' ||
          'game_removed' ||
          'game_reminder' ||
          'game_invite' ||
          'request_converted' ||
          'game_finished' ||
          'score_entered' ||
          'score_disputed' ||
          'score_resolved' ||
          'rating_updated' ||
          'no_show_recorded':
        final gameId = text('game_id');
        return gameId == null ? null : '/games/$gameId';
      case 'tournament_registered' ||
          'tournament_partner_invite' ||
          'tournament_partner_accepted' ||
          'tournament_partner_declined' ||
          'tournament_partner_cancelled' ||
          'tournament_partner_expired' ||
          'tournament_spot_offered' ||
          'tournament_deadline_reminder' ||
          'tournament_removed' ||
          'tournament_moved':
        final tournamentId = text('tournament_id');
        return tournamentId == null ? null : '/tournaments/$tournamentId';
      case 'request_interest' || 'request_expired':
        final requestId = text('request_id');
        return requestId == null ? null : '/games/requests/$requestId';
      default:
        return null;
    }
  }

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    kind: kind,
    category: category,
    payload: payload,
    createdAt: createdAt,
    read: read ?? this.read,
  );
}

/// A player's community settings. [reliability] is read-only: saving ignores it.
class CommunitySettings {
  const CommunitySettings({
    this.mutedCategories = const {},
    this.hiddenFromSearch = false,
    this.reliability = Reliability.fresh,
  });

  final Set<String> mutedCategories;
  final bool hiddenFromSearch;
  final Reliability reliability;

  CommunitySettings copyWith({Set<String>? mutedCategories, bool? hiddenFromSearch}) => CommunitySettings(
    mutedCategories: mutedCategories ?? this.mutedCategories,
    hiddenFromSearch: hiddenFromSearch ?? this.hiddenFromSearch,
    reliability: reliability,
  );
}
