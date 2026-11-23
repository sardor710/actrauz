import '../../core/localized_text.dart';
import '../../core/markets.dart';
import '../../domain/admin.dart';
import '../../domain/booking_engine.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
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
  venueName: row['venues'] == null ? const LocalizedText() : textOf(Map<String, dynamic>.from(row['venues'] as Map), 'name'),
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
  bookings: {
    for (final b in _rows(json['bookings']))
      b['id'] as String: ownerBookingFromJson(b),
  },
);

Map<String, Object?> _dayHoursJson(int weekday, DayHours? h) => {
  'weekday': weekday,
  'open_minute': h?.openMinute,
  'close_minute': h?.closeMinute,
};

/// `p_hours` of `owner_set_venue_hours`: exactly seven objects, Monday
/// first; a closed (or missing) weekday has null minutes.
List<Map<String, Object?>> venueHoursJson(WeekHours hours) => [
  for (var d = 1; d <= 7; d++) _dayHoursJson(d, hours[d]),
];

/// `p_hours` of `owner_set_court_hours`: only the overridden weekdays.
List<Map<String, Object?>> courtHoursJson(WeekHours override) => [
  for (final d in override.keys.toList()..sort()) _dayHoursJson(d, override[d]),
];

/// `p_rules` of `owner_set_court_pricing`, in the given order.
List<Map<String, Object?>> priceRulesJson(List<PriceRule> rules) => [
  for (final r in rules)
    {
      'weekdays': r.weekdays.toList()..sort(),
      'from_minute': r.fromMinute,
      'to_minute': r.toMinute,
      'price': r.price,
    },
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

/// The JSON returned by `list_games`, `get_game`, `join_game`, `leave_game`.
Game gameFromJson(Row json, {required String? myUserId}) => Game(
  id: json['id'] as String,
  sportId: json['sport_id'] as String,
  cityId: json['city_id'] as String,
  venueId: json['venue_id'] as String,
  hostId: _userId(json['host_id'], myUserId),
  start: wallClock(json['starts_local'] as String),
  end: wallClock(json['ends_local'] as String),
  spots: json['spots'] as int,
  participantIds: [for (final id in (json['participant_ids'] as List? ?? const [])) _userId(id, myUserId)],
  minLevel: json['min_level'] as int? ?? 1,
  maxLevel: json['max_level'] as int? ?? 5,
  pricePerPlayer: json['price_per_player'] as int?,
  bookingId: json['booking_id'] as String?,
  note: json['note'] as String?,
);

/// A profile row with `player_levels` embedded.
Player playerFromRow(Row row, {required String? myUserId}) => Player(
  id: _userId(row['id'], myUserId),
  name: row['full_name'] as String? ?? '',
  levels: {for (final l in _rows(row['player_levels'])) l['sport_id'] as String: l['level'] as int},
);
