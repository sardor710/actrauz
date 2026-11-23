import '../domain/admin.dart';

/// What the admin screens need from the backend. Every call is refused with
/// `BookingException(BookingError.notAllowed)` for someone who is not an
/// admin; validation failures surface as `invalidArgument`, `notFound`,
/// `hasBookings` or `alreadyExists`.
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
}
