import '../core/localized_text.dart';
import '../core/markets.dart';
import 'models.dart';

/// Tournaments, categories and registrations (product spec §10.1, §14), and
/// what the admin screens add on top.
///
/// Times are wall-clock in the tournament's city, as everywhere in the
/// domain: UTC-flagged `DateTime`s that mean "venue time".

/// Singles: one player per entry. Pairs: the registrant and a partner who must
/// accept.
enum CategoryKind { singles, pairs }

/// Shown, not enforced: profiles have no gender. The level range is enforced.
enum CategoryGender { men, women, mixed, open }

/// Where an entry stands (spec §14). `registered` and `offered` hold a spot;
/// paid is a flag on `registered`, not a state.
enum RegistrationStatus {
  pendingPartner,
  registered,
  waitlisted,
  offered,
  declined,
  expired,
  cancelled,
  removed,
  lapsed;

  /// Holds a spot: counts toward the category's cap.
  bool get counted => this == registered || this == offered;

  /// Still in play: not declined, expired, cancelled, removed or lapsed.
  bool get live => this == pendingPartner || this == registered || this == waitlisted || this == offered;
}

/// How the signed-in player takes part in an entry.
enum RegistrationRole { registrant, partner }

enum TournamentSort { date, az }

/// A player named on an entry. Never carries a phone number.
class PlayerRef {
  const PlayerRef({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is PlayerRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class TournamentCategory {
  const TournamentCategory({
    required this.id,
    required this.tournamentId,
    required this.name,
    required this.kind,
    required this.gender,
    required this.minLevel,
    required this.maxLevel,
    required this.fee,
    required this.cap,
    required this.filled,
    this.waitlistCount = 0,
    this.waitlistEnabled = true,
    this.sortOrder = 0,
    this.myStatus,
  });

  final String id;
  final String tournamentId;
  final LocalizedText name;
  final CategoryKind kind;
  final CategoryGender gender;
  final int minLevel;
  final int maxLevel;

  /// Whole currency units of the tournament's city.
  final int fee;

  /// Entries (players for singles, pairs for pairs).
  final int cap;

  /// Entries holding a spot: registered or offered.
  final int filled;
  final int waitlistCount;
  final bool waitlistEnabled;
  final int sortOrder;

  /// The signed-in player's live entry in it, as registrant or partner.
  final RegistrationStatus? myStatus;

  bool get full => filled >= cap;

  /// A full category with the waitlist on takes waitlist entries instead.
  bool get canJoinWaitlist => full && waitlistEnabled;
}

/// What the player's registrations list shows of a tournament.
class TournamentSummary {
  const TournamentSummary({
    required this.id,
    required this.cityId,
    required this.sportId,
    required this.title,
    required this.start,
    required this.end,
    this.venueId,
    this.colorSeed = 0,
    this.coverUrl,
  });

  final String id;
  final String cityId;
  final String sportId;
  final LocalizedText title;
  final DateTime start;
  final DateTime end;
  final String? venueId;
  final int colorSeed;
  final String? coverUrl;
}

/// One entry: a player (singles) or a pair, registrant first.
class Registration {
  const Registration({
    required this.id,
    required this.tournamentId,
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.status,
    required this.registrant,
    required this.fee,
    required this.currency,
    required this.createdAt,
    this.partner,
    this.partnerConfirmed = false,
    this.paid = false,
    this.partnerExpiresAt,
    this.offerExpiresAt,
    this.waitlistPlace,
    this.role,
    this.tournament,
  });

  final String id;
  final String tournamentId;
  final String categoryId;
  final LocalizedText categoryName;
  final CategoryKind kind;
  final RegistrationStatus status;
  final PlayerRef registrant;
  final PlayerRef? partner;

  /// The partner accepted; always true for singles.
  final bool partnerConfirmed;

  /// Locked at registration (spec §14 rule 4).
  final int fee;
  final Currency currency;
  final bool paid;

  /// A pending invite runs out at this time (wall-clock).
  final DateTime? partnerExpiresAt;

  /// An offered spot is held until this time (wall-clock).
  final DateTime? offerExpiresAt;

  /// 1 = next in line, among waitlisted entries that can be offered a spot;
  /// null for a pair still waiting on its partner, and for any other status.
  final int? waitlistPlace;
  final DateTime createdAt;

  /// The signed-in player's part in it; null when they are in neither role
  /// (an admin looking at someone else's entry).
  final RegistrationRole? role;

  /// Only in [TournamentRepository.myRegistrations].
  final TournamentSummary? tournament;

  bool get isMine => role != null;
}

/// A tournament as the registration screens show it. A [TournamentItem], so
/// the cards and the home strip keep working: its fee range and slots are
/// the sums over the categories.
class Tournament extends TournamentItem {
  const Tournament({
    required super.id,
    required super.cityId,
    required super.sportId,
    required super.title,
    required super.venueName,
    required super.start,
    required super.end,
    required super.minFee,
    required super.maxFee,
    required super.slotsTotal,
    required super.slotsFilled,
    required this.currency,
    required this.registrationDeadline,
    required this.registrationOpen,
    this.venueId,
    this.description = const LocalizedText(),
    this.coverUrl,
    this.colorSeed = 0,
    this.active = true,
    this.categories = const [],
    this.myRegistrations = const [],
  });

  final Currency currency;
  final String? venueId;
  final LocalizedText description;

  /// Registration closes at this time (wall-clock).
  final DateTime registrationDeadline;
  final bool registrationOpen;
  final String? coverUrl;
  final int colorSeed;
  final bool active;
  final List<TournamentCategory> categories;

  /// The player's live entries, as registrant or as partner.
  final List<Registration> myRegistrations;

  TournamentCategory category(String id) => categories.firstWhere((c) => c.id == id);

  /// Every category is full.
  bool get full => categories.isNotEmpty && categories.every((c) => c.full);
}

// ---- Errors ----

/// What the database refuses with (`full`, `deadline_passed`, …).
enum TournamentError {
  full,
  deadlinePassed,
  levelOutOfRange,
  alreadyRegistered,
  partnerUnavailable,
  notFull,
  waitlistClosed,
  notFound,
  invalidArgument,
  hasRegistrations,
  reliabilityTooLow,
  rateLimited,

  /// Admin functions only: the caller is not an admin.
  notAllowed,

  /// Admin only: paid can be set on `registered` entries only.
  notMarkable,

  /// No connection, an expired session, a server fault.
  unavailable,
}

class TournamentException implements Exception {
  const TournamentException(this.error);

  final TournamentError error;

  @override
  String toString() => 'TournamentException(${error.name})';
}

// ---- Admin ----

/// A row of the admin's tournament list: the tournament as players see it
/// (`active` or not) plus how much is in it.
class AdminTournament {
  const AdminTournament({required this.tournament, required this.categoryCount, required this.registrationCount});

  final Tournament tournament;
  final int categoryCount;

  /// Live entries: pending, registered, waitlisted or offered.
  final int registrationCount;
}

/// The editable fields of a category. No [id] = a new category, which needs
/// [tournamentId].
class CategoryDraft {
  CategoryDraft({
    this.id,
    this.tournamentId,
    this.name = const LocalizedText(),
    this.kind = CategoryKind.singles,
    this.gender = CategoryGender.open,
    this.minLevel = 1,
    this.maxLevel = 5,
    this.fee = 0,
    this.cap = 16,
    this.waitlistEnabled = true,
    this.sortOrder,
  });

  CategoryDraft.from(TournamentCategory category)
    : id = category.id,
      tournamentId = category.tournamentId,
      name = category.name,
      kind = category.kind,
      gender = category.gender,
      minLevel = category.minLevel,
      maxLevel = category.maxLevel,
      fee = category.fee,
      cap = category.cap,
      waitlistEnabled = category.waitlistEnabled,
      sortOrder = category.sortOrder;

  String? id;
  String? tournamentId;
  LocalizedText name;
  CategoryKind kind;
  CategoryGender gender;
  int minLevel;
  int maxLevel;
  int fee;
  int cap;
  bool waitlistEnabled;

  /// `null` places a new category last and leaves an existing one where it is.
  int? sortOrder;
}

/// The editable fields of a tournament. No [id] = a new tournament, which
/// may bring its first [categories] (without them it gets one open singles
/// category with fee 0 and 16 places).
class TournamentDraft {
  TournamentDraft({
    this.id,
    required this.cityId,
    required this.sportId,
    required this.start,
    required this.end,
    this.venueId,
    this.title = const LocalizedText(),
    this.description = const LocalizedText(),
    this.registrationDeadline,
    this.coverUrl,
    this.colorSeed,
    this.active = true,
    List<CategoryDraft>? categories,
  }) : categories = categories ?? [];

  TournamentDraft.from(Tournament tournament)
    : id = tournament.id,
      cityId = tournament.cityId,
      sportId = tournament.sportId,
      start = tournament.start,
      end = tournament.end,
      venueId = tournament.venueId,
      title = tournament.title,
      description = tournament.description,
      registrationDeadline = tournament.registrationDeadline,
      coverUrl = tournament.coverUrl,
      colorSeed = tournament.colorSeed,
      active = tournament.active,
      categories = [];

  String? id;
  String cityId;
  String sportId;
  String? venueId;
  LocalizedText title;
  LocalizedText description;

  /// First and last day (the time of day is ignored).
  DateTime start;
  DateTime end;

  /// Wall-clock; `null` closes registration at 00:00 on [start]. Must not
  /// be after the end of [end].
  DateTime? registrationDeadline;

  /// `https://…` or `null`.
  String? coverUrl;
  int? colorSeed;
  bool active;

  /// Only used when creating.
  List<CategoryDraft> categories;
}

/// An entry as the admin screens see it: with phones, the paid time and the
/// override flag.
class AdminRegistration {
  const AdminRegistration({
    required this.registration,
    this.registrantPhone,
    this.partnerPhone,
    this.paidAt,
    this.adminOverride = false,
    this.waitlistPosition,
  });

  final Registration registration;
  final String? registrantPhone;
  final String? partnerPhone;

  /// When it was marked paid, in UTC.
  final DateTime? paidAt;

  /// An admin added it, bypassing the level range and the deadline.
  final bool adminOverride;

  /// Order of joining the waitlist; only on waitlisted entries.
  final int? waitlistPosition;
}

/// Players, never summed with anything else.
class UserStats {
  const UserStats({this.total = 0, this.active30d = 0, this.newToday = 0, this.new7d = 0, this.newMonth = 0});

  final int total;

  /// Opened the app in the last 30 days.
  final int active30d;
  final int newToday;
  final int new7d;
  final int newMonth;
}

/// One currency's revenue in the period. Currencies are never added together.
class CurrencyRevenue {
  const CurrencyRevenue({required this.currency, required this.venues, required this.tournaments});

  final Currency currency;

  /// Paid bookings (app and walk-in).
  final int venues;

  /// Entry fees of registered entries marked paid.
  final int tournaments;

  int get total => venues + tournaments;
}

/// What was created in the period, whatever became of it.
class ActivityCounts {
  const ActivityCounts({this.bookings = 0, this.games = 0, this.registrations = 0});

  final int bookings;
  final int games;
  final int registrations;
}

class AdminDashboard {
  const AdminDashboard({this.users = const UserStats(), this.revenue = const [], this.counts = const ActivityCounts()});

  final UserStats users;

  /// One row per currency with money in the period, by currency code.
  final List<CurrencyRevenue> revenue;
  final ActivityCounts counts;
}
