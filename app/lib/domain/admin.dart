import '../core/localized_text.dart';
import '../core/markets.dart';
import 'models.dart';

/// Admin view of the catalog (product spec §12): every venue, court, sport
/// and banner, active or not, and the audit log.

/// A user who manages, or could manage, a venue.
class OwnerRef {
  const OwnerRef({required this.userId, required this.name, this.phone});

  final String userId;
  final String name;
  final String? phone;
}

class AdminVenue {
  const AdminVenue({
    required this.venue,
    required this.active,
    this.inactiveCourtIds = const {},
    this.owners = const [],
  });

  /// With every court, active or not, in display order.
  final Venue venue;
  final bool active;
  final Set<String> inactiveCourtIds;
  final List<OwnerRef> owners;
}

/// The editable fields of a venue. No [id] = a new venue.
class VenueDraft {
  VenueDraft({
    this.id,
    String? cityId,
    this.name = const LocalizedText(),
    this.description = const LocalizedText(),
    this.address = const LocalizedText(),
    this.district = const LocalizedText(),
    this.phone = '',
    List<String>? amenities,
    this.active = true,
  }) : cityId = cityId ?? kCities.first.id,
       amenities = amenities ?? [];

  VenueDraft.from(AdminVenue admin)
    : id = admin.venue.id,
      cityId = admin.venue.cityId,
      name = admin.venue.name,
      description = admin.venue.description,
      address = admin.venue.address,
      district = admin.venue.district,
      phone = admin.venue.phone,
      amenities = [...admin.venue.amenities],
      active = admin.active;

  String? id;
  String cityId;
  LocalizedText name;
  LocalizedText description;
  LocalizedText address;
  LocalizedText district;
  String phone;

  /// Keys from `kAmenityKeys`.
  List<String> amenities;
  bool active;
}

/// The editable fields of a court. No [id] = a new court. Hours and price
/// rules are the owner's settings and are not part of the draft.
class CourtDraft {
  CourtDraft({
    this.id,
    required this.venueId,
    required this.sportId,
    this.name = const LocalizedText(),
    this.slotMinutes = 90,
    this.basePrice = 0,
    this.indoor = false,
    this.active = true,
  });

  CourtDraft.from(Court court, {required this.active})
    : id = court.id,
      venueId = court.venueId,
      sportId = court.sportId,
      name = court.name,
      slotMinutes = court.slotMinutes,
      basePrice = court.basePrice,
      indoor = court.indoor;

  String? id;
  String venueId;
  String sportId;
  LocalizedText name;

  /// 60, 90 or 120.
  int slotMinutes;
  int basePrice;
  bool indoor;
  bool active;
}

class AdminSport {
  const AdminSport({required this.sport, required this.sortOrder, required this.active});

  final Sport sport;
  final int sortOrder;
  final bool active;
}

class SportDraft {
  SportDraft({
    this.id = '',
    this.name = const LocalizedText(),
    this.iconKey = '',
    this.bookable = true,
    this.competitiveRating = false,
    this.defaultPlayers = 2,
    this.sortOrder = 0,
    this.active = true,
  });

  SportDraft.from(AdminSport admin)
    : id = admin.sport.id,
      name = admin.sport.name,
      iconKey = admin.sport.iconKey,
      bookable = admin.sport.bookable,
      competitiveRating = admin.sport.competitiveRating,
      defaultPlayers = admin.sport.defaultPlayers,
      sortOrder = admin.sortOrder,
      active = admin.active;

  /// `^[a-z][a-z0-9_]{1,29}$`; chosen when the sport is created.
  String id;
  LocalizedText name;
  String iconKey;
  bool bookable;
  bool competitiveRating;
  int defaultPlayers;
  int sortOrder;
  bool active;
}

/// Matches a valid [SportDraft.id].
final kSportIdPattern = RegExp(r'^[a-z][a-z0-9_]{1,29}$');

class AdminBanner {
  const AdminBanner({
    required this.id,
    this.cityId,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.sortOrder,
    required this.active,
  });

  final String id;

  /// `null` = shown in every city.
  final String? cityId;
  final LocalizedText title;
  final LocalizedText subtitle;
  final String url;
  final int sortOrder;
  final bool active;
}

/// The editable fields of a banner. No [id] = a new banner.
class BannerDraft {
  BannerDraft({
    this.id,
    this.cityId,
    this.title = const LocalizedText(),
    this.subtitle = const LocalizedText(),
    this.url = 'https://',
    this.sortOrder = 0,
    this.active = true,
  });

  BannerDraft.from(AdminBanner banner)
    : id = banner.id,
      cityId = banner.cityId,
      title = banner.title,
      subtitle = banner.subtitle,
      url = banner.url,
      sortOrder = banner.sortOrder,
      active = banner.active;

  String? id;
  String? cityId;
  LocalizedText title;
  LocalizedText subtitle;

  /// Must start with `https://`.
  String url;
  int sortOrder;
  bool active;
}

/// One admin or owner change (spec §12.7): who, what, when, before, after.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.entity,
    this.entityId,
    this.actorName,
    required this.at,
    this.before,
    this.after,
  });

  final String id;
  final String action;
  final String entity;
  final String? entityId;
  final String? actorName;

  /// When it happened, in UTC.
  final DateTime at;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
}
