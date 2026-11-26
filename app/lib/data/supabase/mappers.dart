import '../../core/localized_text.dart';
import '../../core/markets.dart';
import '../../domain/admin.dart';
import '../../domain/booking_engine.dart';
import '../../domain/community.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../domain/tournaments.dart';
import '../sample/sample_data.dart' show kMeId;

/// Rows and JSON from the backend → domain objects. Pure functions, no
/// network, so they are tested on their own.
///
/// Two conventions hold everywhere:
///  * times arrive as venue wall-clock strings (`2026-11-23T17:30:00`) and
///    become UTC-flagged `DateTime`s, like every `DateTime` in the domain;
///  * the signed-in player's id is replaced by [kMeId], so screens recognise
///    "me" the same way with the sample backend and the real one.

typedef Row = Map<String, dynamic>;

/// The `<field>_uz`, `<field>_ru`, `<field>_en` columns of one text.
LocalizedText textOf(Row row, String field) => LocalizedText(
  uz: row['${field}_uz'] as String?,
  ru: row['${field}_ru'] as String?,
  en: row['${field}_en'] as String?,
);

/// `2026-11-23T17:30:00` (or a bare date) as venue wall-clock time.
DateTime wallClock(String value) {
  final local = DateTime.parse(value.length == 10 ? '${value}T00:00:00' : value);
  return DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second);
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `2026-11-23`
String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// `2026-11-23T17:30:00`, with no zone: the backend reads it as venue time.
String isoLocal(DateTime d) => '${isoDate(d)}T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

String _userId(Object? id, String? myUserId) => id == myUserId && id != null ? kMeId : (id as String? ?? '');

/// The id to send to the backend for [id]: [kMeId] is the signed-in user.
String userIdOut(String id, String? myUserId) => id == kMeId && myUserId != null ? myUserId : id;

List<Row> _rows(Object? value) => [for (final r in (value as List? ?? const [])) Map<String, dynamic>.from(r as Map)];

int _order(Row a, Row b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0);

Sport sportFromRow(Row row) => Sport(
  id: row['id'] as String,
  name: textOf(row, 'name'),
  iconKey: row['icon_key'] as String,
  bookable: row['bookable'] as bool? ?? true,
  competitiveRating: row['competitive_rating'] as bool? ?? false,
  defaultPlayers: row['default_players'] as int? ?? 2,
);

DayHours? _dayHours(Row row) =>
    row['closed'] == true ? null : DayHours(row['open_minute'] as int, row['close_minute'] as int);

/// A venue row with `working_hours`, `courts`, and each court's
/// `price_rules` and `working_hours` embedded.
Venue venueFromRow(Row row) {
  final venueId = row['id'] as String;
  // No row for a weekday means the venue is closed that day.
  final hours = <int, DayHours?>{for (var d = 1; d <= 7; d++) d: null};
  for (final h in _rows(row['working_hours'])) {
    hours[h['weekday'] as int] = _dayHours(h);
  }
  return Venue(
    id: venueId,
    cityId: row['city_id'] as String,
    name: textOf(row, 'name'),
    description: textOf(row, 'description'),
    address: textOf(row, 'address'),
    district: textOf(row, 'district'),
    phone: row['phone'] as String? ?? '',
    hours: hours,
    amenities: [for (final a in (row['amenities'] as List? ?? const [])) a as String],
    colorSeed: row['color_seed'] as int? ?? 0,
    courts: [for (final c in _rows(row['courts'])..sort(_order)) courtFromRow(c, venueId: venueId)],
  );
}

Court courtFromRow(Row row, {required String venueId}) => Court(
  id: row['id'] as String,
  venueId: venueId,
  sportId: row['sport_id'] as String,
  name: textOf(row, 'name'),
  slotMinutes: row['slot_minutes'] as int,
  basePrice: row['base_price'] as int,
  indoor: row['indoor'] as bool? ?? false,
  priceRules: [
    for (final r in _rows(row['price_rules'])..sort(_order))
      PriceRule(
        weekdays: {for (final d in r['weekdays'] as List) d as int},
        fromMinute: r['from_minute'] as int,
        toMinute: r['to_minute'] as int,
        price: r['price'] as int,
      ),
  ],
  // Only the weekdays that differ from the venue; closed maps to null.
  hoursOverride: {for (final h in _rows(row['working_hours'])) h['weekday'] as int: _dayHours(h)},
);

BannerItem bannerFromRow(Row row) => BannerItem(
  id: row['id'] as String,
  title: textOf(row, 'title'),
  subtitle: textOf(row, 'subtitle'),
  url: row['url'] as String,
  colorSeed: row['color_seed'] as int? ?? 0,
);

/// A tournament row with its venue's name columns embedded as `venues`.
TournamentItem tournamentFromRow(Row row) => TournamentItem(
  id: row['id'] as String,
  cityId: row['city_id'] as String,
  sportId: row['sport_id'] as String,
  title: textOf(row, 'title'),
  venueName: row['venues'] == null
      ? const LocalizedText()
      : textOf(Map<String, dynamic>.from(row['venues'] as Map), 'name'),
  start: wallClock(row['starts_on'] as String),
  end: wallClock(row['ends_on'] as String),
  minFee: row['min_fee'] as int? ?? 0,
  maxFee: row['max_fee'] as int? ?? 0,
  slotsTotal: row['slots_total'] as int? ?? 0,
  slotsFilled: row['slots_filled'] as int? ?? 0,
);

BookingStatus bookingStatusOf(String value) => switch (value) {
  'held' => BookingStatus.held,
  'confirmed' => BookingStatus.confirmed,
  'cancelled_by_player' => BookingStatus.cancelledByPlayer,
  'cancelled_by_venue' => BookingStatus.cancelledByVenue,
  'completed' => BookingStatus.completed,
  // Not marked by the owner within 48 hours: shown as completed.
  'unverified' => BookingStatus.completed,
  'paid' => BookingStatus.paid,
  'no_show' => BookingStatus.noShow,
  'released' => BookingStatus.released,
  _ => throw FormatException('Unknown booking status "$value"'),
};

/// The JSON returned by `hold_slots`, `confirm_booking`, `cancel_booking`
/// and `my_bookings`.
Booking bookingFromJson(Row json, {required String? myUserId}) {
  final holdExpires = json['hold_expires_local'] as String?;
  return Booking(
    id: json['id'] as String,
    userId: _userId(json['user_id'], myUserId),
    venueId: json['venue_id'] as String,
    courtId: json['court_id'] as String,
    start: wallClock(json['starts_local'] as String),
    end: wallClock(json['ends_local'] as String),
    slotCount: json['slot_count'] as int,
    totalPrice: json['total_price'] as int,
    status: bookingStatusOf(json['status'] as String),
    paymentStatus: json['payment_status'] == 'paid' ? PaymentStatus.paid : PaymentStatus.unpaid,
    holdExpiresAt: holdExpires == null ? null : wallClock(holdExpires),
    lateCancellation: json['late_cancellation'] as bool? ?? false,
    players: json['players'] as int?,
    note: json['note'] as String?,
  );
}

BookingSource bookingSourceOf(String? value) => switch (value) {
  null || 'app' => BookingSource.app,
  'walk_in' => BookingSource.walkIn,
  'block' => BookingSource.block,
  _ => throw FormatException('Unknown booking source "$value"'),
};

WalkInPayment? walkInPaymentOf(String? value) => switch (value) {
  null => null,
  'cash' => WalkInPayment.cash,
  'card' => WalkInPayment.card,
  'transfer' => WalkInPayment.transfer,
  _ => throw FormatException('Unknown walk-in payment "$value"'),
};

/// `p_payment_method` of `owner_create_walk_in`.
String walkInPaymentCode(WalkInPayment payment) => switch (payment) {
  WalkInPayment.cash => 'cash',
  WalkInPayment.card => 'card',
  WalkInPayment.transfer => 'transfer',
};

/// `p_outcome` of `owner_mark_booking`.
String bookingOutcomeCode(BookingOutcome outcome) => switch (outcome) {
  BookingOutcome.paid => 'paid',
  BookingOutcome.noShow => 'no_show',
};

/// The JSON returned by the `owner_*` functions and embedded in
/// `owner_calendar`: a player booking's keys plus `source`,
/// `walk_in_payment`, `customer_name`, `customer_phone` and `reason`.
OwnerBooking ownerBookingFromJson(Row json) => OwnerBooking(
  id: json['id'] as String,
  venueId: json['venue_id'] as String,
  courtId: json['court_id'] as String,
  start: wallClock(json['starts_local'] as String),
  end: wallClock(json['ends_local'] as String),
  slotCount: json['slot_count'] as int,
  totalPrice: json['total_price'] as int,
  status: bookingStatusOf(json['status'] as String),
  source: bookingSourceOf(json['source'] as String?),
  paymentStatus: json['payment_status'] == 'paid' ? PaymentStatus.paid : PaymentStatus.unpaid,
  walkInPayment: walkInPaymentOf(json['walk_in_payment'] as String?),
  customerName: json['customer_name'] as String?,
  customerPhone: json['customer_phone'] as String?,
  note: json['note'] as String?,
  reason: json['reason'] as String?,
  players: json['players'] as int?,
);

OwnerSlot ownerSlotFromJson(Row json) => OwnerSlot(
  time: SlotTime(wallClock(json['starts_local'] as String), wallClock(json['ends_local'] as String)),
  price: json['price'] as int,
  state: switch (json['state']) {
    'free' => OwnerSlotState.free,
    'booked' => OwnerSlotState.booked,
    'blocked' => OwnerSlotState.blocked,
    'past' => OwnerSlotState.past,
    final other => throw FormatException('Unknown slot state "$other"'),
  },
  bookingId: json['booking_id'] as String?,
);

/// The JSON returned by `owner_calendar`: `{ "slots": [...], "bookings": [...] }`.
OwnerCalendar ownerCalendarFromJson(Row json) => OwnerCalendar(
  slots: [for (final s in _rows(json['slots'])) ownerSlotFromJson(s)],
  bookings: {for (final b in _rows(json['bookings'])) b['id'] as String: ownerBookingFromJson(b)},
);

Map<String, Object?> _dayHoursJson(int weekday, DayHours? h) => {
  'weekday': weekday,
  'open_minute': h?.openMinute,
  'close_minute': h?.closeMinute,
};

/// `p_hours` of `owner_set_venue_hours`: exactly seven objects, Monday
/// first; a closed (or missing) weekday has null minutes.
List<Map<String, Object?>> venueHoursJson(WeekHours hours) => [for (var d = 1; d <= 7; d++) _dayHoursJson(d, hours[d])];

/// `p_hours` of `owner_set_court_hours`: only the overridden weekdays.
List<Map<String, Object?>> courtHoursJson(WeekHours override) => [
  for (final d in override.keys.toList()..sort()) _dayHoursJson(d, override[d]),
];

/// `p_rules` of `owner_set_court_pricing`, in the given order.
List<Map<String, Object?>> priceRulesJson(List<PriceRule> rules) => [
  for (final r in rules)
    {'weekdays': r.weekdays.toList()..sort(), 'from_minute': r.fromMinute, 'to_minute': r.toMinute, 'price': r.price},
];

/// `UZS` / `KZT`.
Currency currencyOf(String code) => Currency.values.firstWhere(
  (c) => c.name == code.toLowerCase(),
  orElse: () => throw FormatException('Unknown currency "$code"'),
);

/// The JSON returned by `owner_dashboard`.
OwnerDashboard ownerDashboardFromJson(Row json) => OwnerDashboard(
  currency: currencyOf(json['currency'] as String),
  days: json['days'] as int,
  bookingsApp: json['bookings_app'] as int? ?? 0,
  bookingsWalkIn: json['bookings_walk_in'] as int? ?? 0,
  revenuePaid: json['revenue_paid'] as int? ?? 0,
  revenueUnconfirmed: json['revenue_unconfirmed'] as int? ?? 0,
  noShows: json['no_shows'] as int? ?? 0,
  slotsAvailable: json['slots_available'] as int? ?? 0,
  slotsBooked: json['slots_booked'] as int? ?? 0,
  heatmap: {
    for (final cell in _rows(json['heatmap']))
      (weekday: cell['weekday'] as int, hour: cell['hour'] as int): cell['count'] as int,
  },
);

// ---- Admin ----

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// `<field>_uz`, `<field>_ru`, `<field>_en`, blank languages as null.
Map<String, Object?> textJson(String field, LocalizedText text) => {
  '${field}_uz': _blankToNull(text.uz),
  '${field}_ru': _blankToNull(text.ru),
  '${field}_en': _blankToNull(text.en),
};

/// `{ "user_id", "full_name", "phone" }` from `admin_search_users` and a
/// venue's `owners`.
OwnerRef ownerRefFromJson(Row json) => OwnerRef(
  userId: json['user_id'] as String,
  name: json['full_name'] as String? ?? '',
  phone: json['phone'] as String?,
);

/// One row of `admin_list_venues`: stored columns, `hours` (seven days),
/// `courts` (each with `hours` and `price_rules`, inactive ones included)
/// and `owners`.
AdminVenue adminVenueFromJson(Row json) {
  final courts = _rows(json['courts']);
  final row = {
    ...json,
    'working_hours': json['hours'],
    'courts': [
      for (final c in courts) {...c, 'working_hours': c['hours']},
    ],
  };
  return AdminVenue(
    venue: venueFromRow(row),
    active: json['active'] as bool? ?? true,
    inactiveCourtIds: {
      for (final c in courts)
        if (c['active'] == false) c['id'] as String,
    },
    owners: [for (final o in _rows(json['owners'])) ownerRefFromJson(o)],
  );
}

/// `p_venue` of `admin_save_venue`; no `id` key for a new venue.
Map<String, Object?> venueDraftJson(VenueDraft draft) => {
  if (draft.id != null) 'id': draft.id,
  'city_id': draft.cityId,
  ...textJson('name', draft.name),
  ...textJson('description', draft.description),
  ...textJson('address', draft.address),
  ...textJson('district', draft.district),
  'phone': draft.phone.trim(),
  'amenities': [...draft.amenities],
  'active': draft.active,
};

/// `p_court` of `admin_save_court`; no `id` key for a new court.
Map<String, Object?> courtDraftJson(CourtDraft draft) => {
  if (draft.id != null) 'id': draft.id,
  'venue_id': draft.venueId,
  'sport_id': draft.sportId,
  ...textJson('name', draft.name),
  'slot_minutes': draft.slotMinutes,
  'base_price': draft.basePrice,
  'indoor': draft.indoor,
  'active': draft.active,
};

/// One row of `admin_list_sports`.
AdminSport adminSportFromJson(Row json) => AdminSport(
  sport: sportFromRow(json),
  sortOrder: json['sort_order'] as int? ?? 0,
  active: json['active'] as bool? ?? true,
);

/// `p_sport` of `admin_save_sport`; the id is always sent.
Map<String, Object?> sportDraftJson(SportDraft draft) => {
  'id': draft.id.trim(),
  ...textJson('name', draft.name),
  'icon_key': draft.iconKey.trim(),
  'bookable': draft.bookable,
  'competitive_rating': draft.competitiveRating,
  'default_players': draft.defaultPlayers,
  'sort_order': draft.sortOrder,
  'active': draft.active,
};

/// One row of `admin_list_banners`.
AdminBanner adminBannerFromJson(Row json) => AdminBanner(
  id: json['id'] as String,
  cityId: json['city_id'] as String?,
  title: textOf(json, 'title'),
  subtitle: textOf(json, 'subtitle'),
  url: json['url'] as String,
  sortOrder: json['sort_order'] as int? ?? 0,
  active: json['active'] as bool? ?? true,
);

/// `p_banner` of `admin_save_banner`; no `id` key for a new banner, and
/// `city_id` always present (null = every city).
Map<String, Object?> bannerDraftJson(BannerDraft draft) => {
  if (draft.id != null) 'id': draft.id,
  'city_id': draft.cityId,
  ...textJson('title', draft.title),
  ...textJson('subtitle', draft.subtitle),
  'url': draft.url.trim(),
  'sort_order': draft.sortOrder,
  'active': draft.active,
};

Map<String, dynamic>? _jsonMap(Object? value) => value == null ? null : Map<String, dynamic>.from(value as Map);

/// One row of `admin_audit_log`.
AuditEntry auditEntryFromJson(Row json) => AuditEntry(
  id: json['id'].toString(),
  action: json['action'] as String,
  entity: json['entity'] as String,
  entityId: json['entity_id']?.toString(),
  actorName: json['actor_name'] as String?,
  at: DateTime.parse(json['created_at'] as String).toUtc(),
  before: _jsonMap(json['before']),
  after: _jsonMap(json['after']),
);

/// One row of `court_availability`.
SlotView slotFromRow(Row row) => SlotView(
  time: SlotTime(wallClock(row['starts_local'] as String), wallClock(row['ends_local'] as String)),
  price: row['price'] as int,
  state: switch (row['state']) {
    'free' => SlotState.free,
    'mine' => SlotState.mine,
    'past' => SlotState.past,
    _ => SlotState.taken,
  },
);

double? _double(Object? value) => (value as num?)?.toDouble();

/// An instant, as the backend writes `timestamptz`.
DateTime _instant(Object? value) => DateTime.parse(value as String).toUtc();

Reliability reliabilityFromJson(Row json) => Reliability(
  score: json['score'] as int,
  badge: switch (json['badge']) {
    'new' => ReliabilityBadge.isNew,
    'reliable' => ReliabilityBadge.reliable,
    'limited' => ReliabilityBadge.limited,
    'blocked' => ReliabilityBadge.blocked,
    final other => throw FormatException('Unknown reliability badge "$other"'),
  },
);

Reliability _reliabilityOf(Object? value) =>
    value == null ? Reliability.fresh : reliabilityFromJson(Map<String, dynamic>.from(value as Map));

/// `{ id, name, level, reliability }` of a game's participants and of a
/// request's interested players. [idKey] is `user_id` in a join request.
GameMember gameMemberFromJson(Row json, {required String? myUserId, String idKey = 'id'}) => GameMember(
  id: _userId(json[idKey], myUserId),
  name: json['name'] as String? ?? '',
  level: json['level'] as int? ?? 1,
  reliability: _reliabilityOf(json['reliability']),
);

MyGameStatus? _myGameStatus(Object? value) => switch (value) {
  null => null,
  'host' => MyGameStatus.host,
  'participant' => MyGameStatus.participant,
  'invited' => MyGameStatus.invited,
  'requested' => MyGameStatus.requested,
  _ => throw FormatException('Unknown game status "$value"'),
};

/// The JSON returned by `list_games`, `get_game`, `join_game`, `leave_game`,
/// `create_game` and the other game functions. `join_requests` is only there
/// for the host.
Game gameFromJson(Row json, {required String? myUserId}) => Game(
  id: json['id'] as String,
  sportId: json['sport_id'] as String,
  cityId: json['city_id'] as String,
  venueId: json['venue_id'] as String?,
  hostId: _userId(json['host_id'], myUserId),
  kind: switch (json['kind']) {
    null || 'booked' => GameKind.booked,
    'place' => GameKind.place,
    'map_point' => GameKind.mapPoint,
    final other => throw FormatException('Unknown game kind "$other"'),
  },
  visibility: json['visibility'] == 'invite_only' ? GameVisibility.inviteOnly : GameVisibility.public,
  start: wallClock(json['starts_local'] as String),
  end: wallClock(json['ends_local'] as String),
  spots: json['spots'] as int,
  participantIds: [for (final id in (json['participant_ids'] as List? ?? const [])) _userId(id, myUserId)],
  minLevel: json['min_level'] as int? ?? 1,
  maxLevel: json['max_level'] as int? ?? 5,
  pricePerPlayer: json['price_per_player'] as int?,
  bookingId: json['booking_id'] as String?,
  note: json['note'] as String?,
  meetingPoint: json['meeting_point'] as String?,
  meetingLat: _double(json['meeting_lat']),
  meetingLng: _double(json['meeting_lng']),
  distanceKm: _double(json['distance_km']),
  pace: json['pace'] as String?,
  myStatus: _myGameStatus(json['my_status']),
  myRequestId: json['my_request_id'] as String?,
  participants: [for (final m in _rows(json['participants'])) gameMemberFromJson(m, myUserId: myUserId)],
  joinRequests: [
    for (final r in _rows(json['join_requests']))
      JoinRequest(
        id: r['id'] as String,
        member: gameMemberFromJson(r, myUserId: myUserId, idKey: 'user_id'),
        createdAt: _instant(r['created_at']),
      ),
  ],
  cancelled: json['status'] == 'cancelled',
);

/// The JSON returned by `get_game_request`, `list_game_requests` and the other
/// request functions.
GameRequest gameRequestFromJson(Row json, {required String? myUserId}) {
  final interested = [for (final m in _rows(json['interested'])) gameMemberFromJson(m, myUserId: myUserId)];
  return GameRequest(
    id: json['id'] as String,
    sportId: json['sport_id'] as String,
    cityId: json['city_id'] as String,
    hostId: _userId(json['host_id'], myUserId),
    hostName: json['host_name'] as String? ?? '',
    venueId: json['venue_id'] as String?,
    area: json['area'] as String?,
    start: wallClock(json['starts_local'] as String),
    end: wallClock(json['ends_local'] as String),
    playersNeeded: json['players_needed'] as int,
    minLevel: json['min_level'] as int? ?? 1,
    maxLevel: json['max_level'] as int? ?? 5,
    note: json['note'] as String?,
    status: switch (json['status']) {
      null || 'open' => GameRequestStatus.open,
      'converted' => GameRequestStatus.converted,
      'expired' => GameRequestStatus.expired,
      'cancelled' => GameRequestStatus.cancelled,
      final other => throw FormatException('Unknown request status "$other"'),
    },
    gameId: json['game_id'] as String?,
    createdAt: _instant(json['created_at']),
    interested: interested,
    interestedCount: json['interested_count'] as int? ?? interested.length,
    myStatus: switch (json['my_status']) {
      null => null,
      'host' => MyRequestStatus.host,
      'interested' => MyRequestStatus.interested,
      final other => throw FormatException('Unknown request player status "$other"'),
    },
  );
}

/// One row of `list_players`, or the result of `player_profile`.
PlayerProfile playerProfileFromJson(Row json, {required String? myUserId}) => PlayerProfile(
  id: _userId(json['id'], myUserId),
  name: json['name'] as String? ?? '',
  cityId: json['city_id'] as String?,
  levels: {for (final e in (json['levels'] as Map? ?? const {}).entries) e.key as String: e.value as int},
  reliability: _reliabilityOf(json['reliability']),
  gamesPlayed: json['games_played'] as int? ?? 0,
);

/// One row of `my_notifications`.
AppNotification notificationFromJson(Row json) => AppNotification(
  id: json['id'] as String,
  kind: json['kind'] as String,
  category: json['category'] as String,
  payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
  createdAt: _instant(json['created_at']),
  read: json['read'] as bool? ?? false,
);

/// The JSON returned by `my_settings`.
CommunitySettings communitySettingsFromJson(Row json) => CommunitySettings(
  mutedCategories: {for (final c in (json['muted_categories'] as List? ?? const [])) c as String},
  hiddenFromSearch: json['hidden_from_search'] as bool? ?? false,
  reliability: _reliabilityOf(json['reliability']),
);

String _visibilityCode(GameVisibility v) => v == GameVisibility.inviteOnly ? 'invite_only' : 'public';

/// `p_game` of `create_game`. A key with no value is left out: the database
/// reads a missing key and a null differently.
Map<String, Object?> gameDraftJson(GameDraft draft) => {
  'sport_id': draft.sportId,
  'spots': draft.spots,
  'min_level': draft.minLevel,
  'max_level': draft.maxLevel,
  'visibility': _visibilityCode(draft.visibility),
  if (_blankToNull(draft.note) != null) 'note': _blankToNull(draft.note),
  if (_blankToNull(draft.pace) != null) 'pace': _blankToNull(draft.pace),
  if (draft.distanceKm != null) 'distance_km': draft.distanceKm,
  if (draft.bookingId != null) 'booking_id': draft.bookingId,
  if (draft.venueId != null) 'venue_id': draft.venueId,
  if (_blankToNull(draft.meetingPoint) != null) 'meeting_point': _blankToNull(draft.meetingPoint),
  if (draft.meetingLat != null) 'meeting_lat': draft.meetingLat,
  if (draft.meetingLng != null) 'meeting_lng': draft.meetingLng,
  if (draft.start != null) 'starts_local': isoLocal(draft.start!),
  if (draft.end != null) 'ends_local': isoLocal(draft.end!),
};

/// `p_place` of `convert_game_request`. Only what the player chose is sent:
/// the database falls back to the request's own spots, times and venue for
/// every key that is missing, which a null would defeat.
Map<String, Object?> placePickJson(PlacePick place) => {
  if (place.bookingId != null) 'booking_id': place.bookingId,
  if (place.venueId != null) 'venue_id': place.venueId,
  if (_blankToNull(place.meetingPoint) != null) 'meeting_point': _blankToNull(place.meetingPoint),
  if (place.meetingLat != null) 'meeting_lat': place.meetingLat,
  if (place.meetingLng != null) 'meeting_lng': place.meetingLng,
  if (place.spots != null) 'spots': place.spots,
  if (place.start != null) 'starts_local': isoLocal(place.start!),
  if (place.end != null) 'ends_local': isoLocal(place.end!),
  if (place.visibility != null) 'visibility': _visibilityCode(place.visibility!),
  if (_blankToNull(place.pace) != null) 'pace': _blankToNull(place.pace),
  if (place.distanceKm != null) 'distance_km': place.distanceKm,
};

/// `p_request` of `create_game_request`.
Map<String, Object?> gameRequestDraftJson(GameRequestDraft draft) => {
  'sport_id': draft.sportId,
  'players_needed': draft.playersNeeded,
  'min_level': draft.minLevel,
  'max_level': draft.maxLevel,
  'starts_local': isoLocal(draft.start),
  'ends_local': isoLocal(draft.end),
  if (draft.venueId != null) 'venue_id': draft.venueId,
  if (_blankToNull(draft.area) != null) 'area': _blankToNull(draft.area),
  if (_blankToNull(draft.note) != null) 'note': _blankToNull(draft.note),
};

/// A profile row with `player_levels` embedded.
Player playerFromRow(Row row, {required String? myUserId}) => Player(
  id: _userId(row['id'], myUserId),
  name: row['full_name'] as String? ?? '',
  levels: {for (final l in _rows(row['player_levels'])) l['sport_id'] as String: l['level'] as int},
);

// ---- Tournaments ----

/// `{ "uz": …, "ru": …, "en": … }`, as the functions write names that are not
/// columns (a tournament's venue, a registration's category).
LocalizedText localizedTextFromJson(Object? value) {
  if (value is! Map) return const LocalizedText();
  return LocalizedText(uz: value['uz'] as String?, ru: value['ru'] as String?, en: value['en'] as String?);
}

CategoryKind categoryKindOf(String value) => switch (value) {
  'singles' => CategoryKind.singles,
  'pairs' => CategoryKind.pairs,
  _ => throw FormatException('Unknown category kind "$value"'),
};

CategoryGender categoryGenderOf(String value) => switch (value) {
  'men' => CategoryGender.men,
  'women' => CategoryGender.women,
  'mixed' => CategoryGender.mixed,
  'open' => CategoryGender.open,
  _ => throw FormatException('Unknown category gender "$value"'),
};

RegistrationStatus registrationStatusOf(String value) => switch (value) {
  'pending_partner' => RegistrationStatus.pendingPartner,
  'registered' => RegistrationStatus.registered,
  'waitlisted' => RegistrationStatus.waitlisted,
  'offered' => RegistrationStatus.offered,
  'declined' => RegistrationStatus.declined,
  'expired' => RegistrationStatus.expired,
  'cancelled' => RegistrationStatus.cancelled,
  'removed' => RegistrationStatus.removed,
  'lapsed' => RegistrationStatus.lapsed,
  _ => throw FormatException('Unknown registration status "$value"'),
};

PlayerRef playerRefFromJson(Row json, {required String? myUserId}) =>
    PlayerRef(id: _userId(json['id'], myUserId), name: json['name'] as String? ?? '');

DateTime? _wallClockOrNull(Object? value) => value == null ? null : wallClock(value as String);

/// One of a tournament's `categories`.
TournamentCategory tournamentCategoryFromJson(Row json) => TournamentCategory(
  id: json['id'] as String,
  tournamentId: json['tournament_id'] as String,
  name: textOf(json, 'name'),
  kind: categoryKindOf(json['kind'] as String),
  gender: categoryGenderOf(json['gender'] as String? ?? 'open'),
  minLevel: json['min_level'] as int? ?? 1,
  maxLevel: json['max_level'] as int? ?? 5,
  fee: json['fee'] as int? ?? 0,
  cap: json['cap'] as int,
  filled: json['filled'] as int? ?? 0,
  waitlistCount: json['waitlist_count'] as int? ?? 0,
  waitlistEnabled: json['waitlist_enabled'] as bool? ?? true,
  sortOrder: json['sort_order'] as int? ?? 0,
  myStatus: json['my_status'] == null ? null : registrationStatusOf(json['my_status'] as String),
);

/// The `tournament` embedded in a row of `my_registrations`.
TournamentSummary tournamentSummaryFromJson(Row json) => TournamentSummary(
  id: json['id'] as String,
  cityId: json['city_id'] as String,
  sportId: json['sport_id'] as String,
  title: textOf(json, 'title'),
  start: wallClock(json['starts_on'] as String),
  end: wallClock(json['ends_on'] as String),
  venueId: json['venue_id'] as String?,
  colorSeed: json['color_seed'] as int? ?? 0,
  coverUrl: json['cover_url'] as String?,
  registrationOpen: json['registration_open'] as bool? ?? false,
);

/// The JSON returned by `register_tournament`, `respond_partner`,
/// `cancel_registration`, `join_waitlist`, `claim_offer`, a row of
/// `my_registrations` and an entry inside a tournament's `my_registrations`.
/// The role is not on the wire: it is whichever of the two players is the
/// signed-in one.
Registration registrationFromJson(Row json, {required String? myUserId}) {
  final registrant = playerRefFromJson(Map<String, dynamic>.from(json['registrant'] as Map), myUserId: myUserId);
  final partnerJson = json['partner'];
  final partner = partnerJson == null
      ? null
      : playerRefFromJson(Map<String, dynamic>.from(partnerJson as Map), myUserId: myUserId);
  final tournament = json['tournament'];
  return Registration(
    id: json['id'] as String,
    tournamentId: json['tournament_id'] as String,
    categoryId: json['category_id'] as String,
    categoryName: localizedTextFromJson(json['category_name']),
    kind: categoryKindOf(json['kind'] as String),
    status: registrationStatusOf(json['status'] as String),
    registrant: registrant,
    partner: partner,
    partnerConfirmed: json['partner_confirmed'] as bool? ?? false,
    fee: json['fee'] as int? ?? 0,
    currency: currencyOf(json['currency'] as String),
    paid: json['paid'] as bool? ?? false,
    partnerExpiresAt: _wallClockOrNull(json['partner_expires_local']),
    offerExpiresAt: _wallClockOrNull(json['offer_expires_local']),
    waitlistPlace: json['waitlist_place'] as int?,
    createdAt: _instant(json['created_at']),
    role: registrant.id == kMeId
        ? RegistrationRole.registrant
        : partner?.id == kMeId
        ? RegistrationRole.partner
        : null,
    tournament: tournament == null ? null : tournamentSummaryFromJson(Map<String, dynamic>.from(tournament as Map)),
  );
}

/// The JSON returned by `get_tournament` and each row of `list_tournaments`.
/// `fee_min` / `fee_max` (table columns `min_fee` / `max_fee`) are the
/// categories' fee range.
Tournament tournamentFromJson(Row json, {required String? myUserId}) => Tournament(
  id: json['id'] as String,
  cityId: json['city_id'] as String,
  sportId: json['sport_id'] as String,
  title: textOf(json, 'title'),
  venueName: localizedTextFromJson(json['venue_name']),
  start: wallClock(json['starts_on'] as String),
  end: wallClock(json['ends_on'] as String),
  minFee: json['fee_min'] as int? ?? 0,
  maxFee: json['fee_max'] as int? ?? 0,
  slotsTotal: json['slots_total'] as int? ?? 0,
  slotsFilled: json['slots_filled'] as int? ?? 0,
  currency: currencyOf(json['currency'] as String),
  registrationDeadline: wallClock(json['registration_deadline_local'] as String),
  registrationOpen: json['registration_open'] as bool? ?? false,
  venueId: json['venue_id'] as String?,
  description: textOf(json, 'description'),
  coverUrl: json['cover_url'] as String?,
  colorSeed: json['color_seed'] as int? ?? 0,
  active: json['active'] as bool? ?? true,
  categories: [for (final c in _rows(json['categories'])) tournamentCategoryFromJson(c)],
  myRegistrations: [for (final r in _rows(json['my_registrations'])) registrationFromJson(r, myUserId: myUserId)],
);

/// One row of `admin_list_tournaments`: a tournament plus `category_count`
/// and `registration_count`.
AdminTournament adminTournamentFromJson(Row json, {required String? myUserId}) => AdminTournament(
  tournament: tournamentFromJson(json, myUserId: myUserId),
  categoryCount: json['category_count'] as int? ?? 0,
  registrationCount: json['registration_count'] as int? ?? 0,
);

/// The JSON returned by the `admin_*` registration functions: an entry with
/// phones in `registrant` and `partner`, `paid_at`, `admin_override` and
/// `waitlist_position`.
AdminRegistration adminRegistrationFromJson(Row json, {required String? myUserId}) {
  final partner = json['partner'];
  return AdminRegistration(
    registration: registrationFromJson(json, myUserId: myUserId),
    registrantPhone: (json['registrant'] as Map)['phone'] as String?,
    partnerPhone: partner == null ? null : (partner as Map)['phone'] as String?,
    paidAt: json['paid_at'] == null ? null : _instant(json['paid_at']),
    adminOverride: json['admin_override'] as bool? ?? false,
    waitlistPosition: json['waitlist_position'] as int?,
  );
}

/// The JSON returned by `admin_dashboard`.
AdminDashboard adminDashboardFromJson(Row json) {
  final users = Map<String, dynamic>.from(json['users'] as Map? ?? const {});
  final counts = Map<String, dynamic>.from(json['counts'] as Map? ?? const {});
  return AdminDashboard(
    users: UserStats(
      total: users['total'] as int? ?? 0,
      active30d: users['active_30d'] as int? ?? 0,
      newToday: users['new_today'] as int? ?? 0,
      new7d: users['new_7d'] as int? ?? 0,
      newMonth: users['new_month'] as int? ?? 0,
    ),
    revenue: [
      for (final r in _rows(json['revenue']))
        CurrencyRevenue(
          currency: currencyOf(r['currency'] as String),
          venues: r['venues'] as int? ?? 0,
          tournaments: r['tournaments'] as int? ?? 0,
        ),
    ],
    counts: ActivityCounts(
      bookings: counts['bookings'] as int? ?? 0,
      games: counts['games'] as int? ?? 0,
      registrations: counts['registrations'] as int? ?? 0,
    ),
  );
}

/// `p_category` of `admin_save_category`, or one of a new tournament's
/// `categories` when [nested]. `sort_order` is left out when the draft has
/// none (the database refuses a null); `id` and `tournament_id` are left out
/// inside a tournament.
Map<String, Object?> categoryDraftJson(CategoryDraft draft, {bool nested = false}) => {
  if (!nested && draft.id != null) 'id': draft.id,
  if (!nested && draft.tournamentId != null) 'tournament_id': draft.tournamentId,
  ...textJson('name', draft.name),
  'kind': draft.kind.name,
  'gender': draft.gender.name,
  'min_level': draft.minLevel,
  'max_level': draft.maxLevel,
  'fee': draft.fee,
  'cap': draft.cap,
  'waitlist_enabled': draft.waitlistEnabled,
  if (draft.sortOrder != null) 'sort_order': draft.sortOrder,
};

/// `p_tournament` of `admin_save_tournament`. `categories` only when creating
/// (the database refuses it on an update); the summary columns are never sent.
Map<String, Object?> tournamentDraftJson(TournamentDraft draft) => {
  if (draft.id != null) 'id': draft.id,
  'city_id': draft.cityId,
  'sport_id': draft.sportId,
  'venue_id': draft.venueId,
  ...textJson('title', draft.title),
  ...textJson('description', draft.description),
  'starts_on': isoDate(draft.start),
  'ends_on': isoDate(draft.end),
  'registration_deadline_local': draft.registrationDeadline == null ? null : isoLocal(draft.registrationDeadline!),
  'cover_url': _blankToNull(draft.coverUrl),
  if (draft.colorSeed != null) 'color_seed': draft.colorSeed,
  'active': draft.active,
  if (draft.id == null && draft.categories.isNotEmpty)
    'categories': [for (final c in draft.categories) categoryDraftJson(c, nested: true)],
};
