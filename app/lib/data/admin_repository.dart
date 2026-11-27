import '../domain/admin.dart';
import '../domain/tournaments.dart';

/// What the admin screens need from the backend. Every call is refused with
/// `BookingException(BookingError.notAllowed)` for someone who is not an
/// admin; validation failures surface as `invalidArgument`, `notFound`,
/// `hasBookings` or `alreadyExists`. The tournament calls at the end are the
/// exception: they fail with a `TournamentException` instead (see there).
abstract class AdminRepository {
  /// Never refused: `false` for anyone who is not an admin.
  Future<bool> isAdmin();

  /// Every venue, active or not, newest first.
  Future<List<AdminVenue>> venues();

  /// The venue's id; a new venue opens 08:00–22:00 every day.
  Future<String> saveVenue(VenueDraft draft);

  /// Refused with `hasBookings` when any booking references it; set
  /// `active = false` instead.
  Future<void> deleteVenue(String venueId);

  Future<String> saveCourt(CourtDraft draft);

  /// Copies sport, slot length, prices, rules and hour overrides; names get
  /// " 2" appended. Returns the copy's id.
  Future<String> duplicateCourt(String courtId);

  /// Refused with `hasBookings` when any booking references it.
  Future<void> deleteCourt(String courtId);

  /// At most 20 users whose name or phone matches; nothing for a query
  /// under 2 characters.
  Future<List<OwnerRef>> searchUsers(String query);

  Future<void> setOwner(String venueId, String userId, {required bool assigned});

  /// Every sport, by sort order.
  Future<List<AdminSport>> sports();

  /// Refused with `alreadyExists` when creating an id that exists.
  Future<String> saveSport(SportDraft draft, {required bool create});

  /// Every banner, by sort order.
  Future<List<AdminBanner>> banners();

  Future<String> saveBanner(BannerDraft draft);

  Future<void> deleteBanner(String bannerId);

  /// Newest first; [limit] 1–100; [before] pages back from an entry's time.
  Future<List<AuditEntry>> auditLog({int limit = 50, DateTime? before});

  // ---- Tournaments ----
  //
  // These fail with a `TournamentException`: `notAllowed` for someone who is
  // not an admin, then `notFound`, `invalidArgument`, `hasRegistrations`,
  // `full`, `notMarkable`, `alreadyRegistered` or `partnerUnavailable`.

  /// Every tournament, active or not, latest start first.
  Future<List<AdminTournament>> tournaments();

  /// The tournament's id. A new tournament brings its first categories (or
  /// gets one open singles category).
  Future<String> saveTournament(TournamentDraft draft);

  /// The category's id; a new one goes last in its tournament. The cap never
  /// goes below the entries holding a spot, and the kind is fixed once the
  /// category has live entries (`hasRegistrations`).
  Future<String> saveCategory(CategoryDraft draft);

  /// Only a category no registration has ever been in (`hasRegistrations`),
  /// and never a tournament's last one (`invalidArgument`).
  Future<void> deleteCategory(String categoryId);

  /// Every entry of the tournament, any state: by category, then counted
  /// entries, pending pairs, the waitlist in order, finished ones.
  Future<List<AdminRegistration>> registrations(String tournamentId);

  /// `registered` entries only (`notMarkable` otherwise).
  Future<AdminRegistration> setPaid(String registrationId, bool paid);

  /// Any live entry, at any time; a freed spot goes to the waitlist.
  Future<AdminRegistration> removeRegistration(String registrationId);

  /// A registered entry to another category of the same tournament and kind,
  /// bypassing its level range, never its cap.
  Future<AdminRegistration> moveRegistration(String registrationId, String categoryId);

  /// Adds a player (and, for pairs, the partner, confirmed at once),
  /// bypassing the level range, the deadline and the reliability block, never
  /// the cap (`full`).
  Future<AdminRegistration> addRegistration(String categoryId, String userId, {String? partnerId});

  /// Offers the category's free spots to the waitlist now, also after the
  /// deadline. Returns how many were offered; `full` when there is no free spot.
  Future<int> offerNext(String categoryId);

  /// [cityId] `null` = every city. [from] to [to] inclusive, at most 366 days.
  Future<AdminDashboard> dashboard({String? cityId, required DateTime from, required DateTime to});

  // ---- Review (design §6.4) ----

  /// The disputed and flagged scores and the open abuse reports, oldest
  /// first.
  Future<AdminReview> review();

  /// [action]: `confirm` or `correct` (with [sets]) on a disputed score,
  /// `void` on a pending, disputed or confirmed one (a confirmed score's
  /// rating changes are reversed), `keep` on a confirmed score flagged
  /// because of a no-show (the flag goes, nothing else changes). Anything
  /// else is `notFound`. The players are told, except for `keep`.
  Future<void> resolveScore(String resultId, String action, {List<(int, int)>? sets});

  /// Closes an open report with an optional note of at most 500 characters.
  Future<void> closeReport(String reportId, {String? note});

  /// Removes a team (design §7): its members are told, the audit log keeps
  /// it as `team_deleted`. `notFound` when it is gone.
  Future<void> deleteTeam(String id);
}
