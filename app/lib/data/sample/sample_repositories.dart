import '../../core/localized_text.dart';
import '../../core/markets.dart';
import '../../domain/admin.dart';
import '../../domain/booking_engine.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../domain/pricing.dart';
import '../admin_repository.dart';
import '../owner_repository.dart';
import '../repositories.dart';
import '../supabase/mappers.dart' show bannerDraftJson, courtDraftJson, sportDraftJson, venueDraftJson;
import 'sample_data.dart';

/// In-memory stand-in for the backend. State lives for one app run.
class SampleBackend implements CatalogRepository, BookingRepository, GameRepository {
  SampleBackend({required this.utcNow, this.meName = ''}) {
    _engine = BookingEngine(venueById: _venue);
    _seedGames();
  }

  /// Current UTC time; injected so tests can fix the clock.
  final DateTime Function() utcNow;
  final String meName;

  late final BookingEngine _engine;

  /// Every venue with every court, in creation order. The engine and the
  /// owner screens read these; players see only the active ones.
  final Map<String, Venue> _venues = {for (final v in kSampleVenues) v.id: v};
  final Set<String> _inactiveVenues = {};
  final Set<String> _inactiveCourts = {};

  /// Venue id → user ids who manage it.
  final Map<String, Set<String>> _owners = {
    for (final id in kSampleOwnedVenueIds) id: {kMeId},
  };
  final Map<String, AdminSport> _sports = {
    for (final (i, s) in kSampleSports.indexed) s.id: AdminSport(sport: s, sortOrder: i, active: true),
  };
  final Map<String, AdminBanner> _banners = {
    for (final (i, b) in kSampleBanners.indexed)
      b.id: AdminBanner(id: b.id, title: b.title, subtitle: b.subtitle, url: b.url, sortOrder: i, active: true),
  };
  final Map<String, int> _bannerColors = {for (final b in kSampleBanners) b.id: b.colorSeed};

  /// This run's admin and owner changes, oldest first.
  final List<AuditEntry> _audit = [];
  final Map<String, Game> _games = {};

  Venue _venue(String id) => _venues[id] ?? (throw StateError('Unknown venue $id'));

  /// Whether the demo player manages [venueId].
  bool _manages(String venueId) => _venues.containsKey(venueId) && (_owners[venueId]?.contains(kMeId) ?? false);

  /// What players see of a venue: only its active courts.
  Venue _public(Venue v) =>
      v.courts.any((c) => _inactiveCourts.contains(c.id))
          ? v.copyWith(courts: [for (final c in v.courts) if (!_inactiveCourts.contains(c.id)) c])
          : v;

  void _log(String action, String entity, String? entityId, {Map<String, dynamic>? before, Map<String, dynamic>? after}) {
    _audit.add(
      AuditEntry(
        id: '${_audit.length + 1}',
        action: action,
        entity: entity,
        entityId: entityId,
        actorName: meName,
        at: utcNow(),
        before: before,
        after: after,
      ),
    );
  }

  DateTime _nowAt(Venue venue) => venueNow(cityById(venue.cityId), utcNow: utcNow());

  Player get _me => Player(id: kMeId, name: meName, levels: {for (final s in kSampleSports) s.id: 3});

  /// Every sample game sits on a real booking, so its slot shows as taken.
  void _seedGames() {
    for (final seed in kGameSeeds) {
      final venue = _venue(seed.venueId);
      final court = venue.court(seed.courtId);
      final now = _nowAt(venue);
      final start = dateOnly(now).add(Duration(days: seed.daysAhead, hours: seed.hour, minutes: seed.minute));
      final slot = SlotTime(start, start.add(Duration(minutes: court.slotMinutes)));
      final hostId = seed.participantIds.first;
      try {
        final held = _engine.hold(userId: hostId, venueId: venue.id, courtId: court.id, slots: [slot], now: now);
        final booking = _engine.confirm(held.id, now: now, players: seed.spots);
        _games[seed.id] = Game(
          id: seed.id,
          sportId: court.sportId,
          cityId: venue.cityId,
          venueId: venue.id,
          hostId: hostId,
          start: slot.start,
          end: slot.end,
          spots: seed.spots,
          participantIds: seed.participantIds,
          minLevel: seed.minLevel,
          maxLevel: seed.maxLevel,
          pricePerPlayer: (booking.totalPrice / seed.spots).round(),
          bookingId: booking.id,
        );
      } on BookingException {
        // The venue is closed that day: skip this sample game.
      }
    }
  }

  // ---- CatalogRepository ----

  @override
  Future<List<Sport>> sports() async => [
    for (final s in _sports.values.where((s) => s.active).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
      s.sport,
  ];

  @override
  Future<List<Venue>> venues(String cityId) async => [
    for (final v in _venues.values)
      if (v.cityId == cityId && !_inactiveVenues.contains(v.id)) _public(v),
  ];

  @override
  Future<Venue> venue(String id) async {
    if (_inactiveVenues.contains(id)) throw StateError('Unknown venue $id');
    return _public(_venue(id));
  }

  @override
  Future<List<BannerItem>> banners(String cityId) async => [
    for (final b in _banners.values.where((b) => b.active && (b.cityId == null || b.cityId == cityId)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
      BannerItem(id: b.id, title: b.title, subtitle: b.subtitle, url: b.url, colorSeed: _bannerColors[b.id] ?? 0),
  ];

  @override
  Future<List<TournamentItem>> tournaments(String cityId) async {
    final items = <TournamentItem>[];
    for (final seed in kTournamentSeeds) {
      final venue = _venue(seed.venueId);
      if (venue.cityId != cityId) continue;
      final start = dateOnly(_nowAt(venue)).add(Duration(days: seed.daysAhead));
      items.add(
        TournamentItem(
          id: seed.id,
          cityId: venue.cityId,
          sportId: seed.sportId,
          title: seed.title,
          venueName: venue.name,
          start: start,
          end: start.add(Duration(days: seed.days - 1)),
          minFee: seed.minFee,
          maxFee: seed.maxFee,
          slotsTotal: seed.slotsTotal,
          slotsFilled: seed.slotsFilled,
        ),
      );
    }
    return items;
  }

  // ---- BookingRepository ----

  @override
  Future<List<SlotView>> availability(String venueId, String courtId, DateTime date) async =>
      _engine.availability(venueId, courtId, date, now: _nowAt(_venue(venueId)), userId: kMeId);

  @override
  Future<Booking> hold(String venueId, String courtId, List<SlotTime> slots) async =>
      _engine.hold(userId: kMeId, venueId: venueId, courtId: courtId, slots: slots, now: _nowAt(_venue(venueId)));

  @override
  Future<Booking> confirm(String bookingId, {int? players, String? note}) async {
    final booking = _engine.byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    return _engine.confirm(bookingId, now: _nowAt(_venue(booking.venueId)), players: players, note: note);
  }

  @override
  Future<void> release(String bookingId) async => _engine.release(bookingId);

  @override
  Future<Booking> cancel(String bookingId) async {
    final booking = _engine.byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    return _engine.cancel(bookingId, now: _nowAt(_venue(booking.venueId)));
  }

  @override
  Future<List<Booking>> myBookings() async => _engine.bookingsOf(kMeId);

  // ---- GameRepository ----

  @override
  Future<List<Game>> games(String cityId) async {
    final open = _games.values.where((g) {
      final upcoming = g.start.isAfter(_nowAt(_venue(g.venueId)));
      return g.cityId == cityId && upcoming && (!g.isFull || g.participantIds.contains(kMeId));
    }).toList()..sort((a, b) => a.start.compareTo(b.start));
    return open;
  }

  @override
  Future<Game> game(String id) async => _games[id] ?? (throw StateError('Unknown game $id'));

  @override
  Future<Game> join(String id) async => _games[id] = joinGame(await game(id), _me);

  @override
  Future<Game> leave(String id) async => _games[id] = leaveGame(await game(id), kMeId);

  @override
  Future<Player> player(String id) async =>
      id == kMeId ? _me : kSamplePlayers.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id));

  // ---- Owner ----

  /// The demo player's owner operations, on the same engine as their player
  /// bookings, so a booking made in the demo shows in the owner calendar.
  ///
  /// A separate object rather than `SampleBackend implements OwnerRepository`:
  /// [OwnerRepository.cancel] and [BookingRepository.cancel] share a name
  /// but not a meaning or a return type.
  late final OwnerRepository owner = _SampleOwnerRepository(this);

  // ---- Admin ----

  /// The demo player is an admin. A separate object for the same reason as
  /// [owner]: `venues()` and `sports()` clash with [CatalogRepository].
  late final AdminRepository admin = _SampleAdminRepository(this);
}

class _SampleOwnerRepository implements OwnerRepository {
  _SampleOwnerRepository(this._backend);

  final SampleBackend _backend;

  BookingEngine get _engine => _backend._engine;

  /// The venue, when the demo player manages it.
  Venue _owned(String venueId) {
    if (!_backend._manages(venueId)) throw const BookingException(BookingError.notAllowed);
    return _backend._venue(venueId);
  }

  static Map<String, dynamic> _bookingJson(Booking b) => {
    'status': b.status.name,
    'source': b.source.name,
    'starts_local': b.start.toIso8601String(),
    'slot_count': b.slotCount,
    'total_price': b.totalPrice,
  };

  /// Logs an owner write on a booking and returns the owner's view of it.
  OwnerBooking _logged(String action, Booking? before, Booking after) {
    _backend._log(
      action,
      'booking',
      after.id,
      before: before == null ? null : _bookingJson(before),
      after: _bookingJson(after),
    );
    return _view(after);
  }

  /// A booking at a venue the demo player manages.
  Booking _ownedBooking(String bookingId) {
    final booking = _engine.byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    _owned(booking.venueId);
    return booking;
  }

  DateTime _now(String venueId) => _backend._nowAt(_backend._venue(venueId));

  /// The session name for the demo player, the sample name for anyone else.
  String _nameOf(String userId) => userId == kMeId
      ? _backend.meName
      : kSamplePlayers.firstWhere((p) => p.id == userId, orElse: () => Player(id: userId, name: userId)).name;

  OwnerBooking _view(Booking booking) => OwnerBooking.fromBooking(booking, nameOf: _nameOf);

  @override
  Future<List<Venue>> myVenues() async => [
    for (final v in _backend._venues.values)
      if (_backend._manages(v.id) && !_backend._inactiveVenues.contains(v.id)) _backend._public(v),
  ];

  @override
  Future<OwnerCalendar> calendar(String venueId, String courtId, DateTime from, int days) async {
    _owned(venueId);
    return _engine.ownerCalendar(venueId, courtId, from, days, now: _now(venueId), nameOf: _nameOf);
  }

  @override
  Future<OwnerBooking> createWalkIn(
    String venueId,
    String courtId,
    List<SlotTime> slots, {
    required String name,
    String? phone,
    int? players,
    required WalkInPayment payment,
  }) async {
    _owned(venueId);
    return _logged(
      'owner_create_walk_in',
      null,
      _engine.createWalkIn(
        venueId: venueId,
        courtId: courtId,
        slots: slots,
        name: name,
        phone: phone,
        players: players,
        payment: payment,
        now: _now(venueId),
      ),
    );
  }

  @override
  Future<OwnerBooking> blockSlots(String venueId, String courtId, List<SlotTime> slots, {String? reason}) async {
    _owned(venueId);
    return _logged(
      'owner_block_slots',
      null,
      _engine.blockSlots(venueId: venueId, courtId: courtId, slots: slots, reason: reason, now: _now(venueId)),
    );
  }

  @override
  Future<OwnerBooking> cancel(String bookingId) async {
    final booking = _ownedBooking(bookingId);
    return _logged('owner_cancel_booking', booking, _engine.cancelByVenue(bookingId, now: _now(booking.venueId)));
  }

  @override
  Future<OwnerBooking> mark(String bookingId, BookingOutcome outcome) async {
    final booking = _ownedBooking(bookingId);
    return _logged('owner_mark_booking', booking, _engine.mark(bookingId, outcome, now: _now(booking.venueId)));
  }

  // ---- Settings: the same validation as the database functions ----

  static void _checkHours(WeekHours hours, {required bool allDays}) {
    final valid =
        hours.keys.every((d) => d >= 1 && d <= 7) &&
        (!allDays || hours.length == 7) &&
        hours.values.every((h) => h == null || (h.openMinute >= 0 && h.openMinute < h.closeMinute && h.closeMinute <= 1440));
    if (!valid) throw const BookingException(BookingError.invalidHours);
  }

  /// Saves [venue] for the rest of the run: player screens, the engine and
  /// the owner calendar all read the backend's venue map.
  void _save(Venue venue) => _backend._venues[venue.id] = venue;

  static Venue _withHours(Venue v, WeekHours hours) => Venue(
    id: v.id,
    cityId: v.cityId,
    name: v.name,
    description: v.description,
    address: v.address,
    district: v.district,
    phone: v.phone,
    hours: hours,
    courts: v.courts,
    amenities: v.amenities,
    colorSeed: v.colorSeed,
  );

  static Court _withCourt(
    Court c, {
    WeekHours? hoursOverride,
    int? slotMinutes,
    int? basePrice,
    List<PriceRule>? priceRules,
  }) => Court(
    id: c.id,
    venueId: c.venueId,
    sportId: c.sportId,
    name: c.name,
    slotMinutes: slotMinutes ?? c.slotMinutes,
    basePrice: basePrice ?? c.basePrice,
    priceRules: priceRules ?? c.priceRules,
    hoursOverride: hoursOverride ?? c.hoursOverride,
    indoor: c.indoor,
  );

  void _replaceCourt(String venueId, String courtId, Court Function(Court) change) {
    final venue = _owned(venueId);
    final court = venue.court(courtId);
    _save(venue.copyWith(courts: [for (final c in venue.courts) c.id == court.id ? change(c) : c]));
  }

  @override
  Future<void> setVenueHours(String venueId, WeekHours hours) async {
    final venue = _owned(venueId);
    _checkHours(hours, allDays: true);
    _save(_withHours(venue, Map.unmodifiable(hours)));
    _backend._log('owner_set_venue_hours', 'venue', venueId, after: {'hours': _hoursJson(hours)});
  }

  static List<Map<String, dynamic>> _hoursJson(WeekHours hours) => [
    for (final d in hours.keys.toList()..sort())
      {'weekday': d, 'open_minute': hours[d]?.openMinute, 'close_minute': hours[d]?.closeMinute},
  ];

  @override
  Future<void> setCourtHours(String venueId, String courtId, WeekHours override) async {
    _owned(venueId);
    _checkHours(override, allDays: false);
    _replaceCourt(venueId, courtId, (c) => _withCourt(c, hoursOverride: Map.unmodifiable(override)));
    _backend._log('owner_set_court_hours', 'court', courtId, after: {'hours': _hoursJson(override)});
  }

  @override
  Future<void> setCourtPricing(
    String venueId,
    String courtId, {
    required int slotMinutes,
    required int basePrice,
    required List<PriceRule> rules,
  }) async {
    _owned(venueId);
    final valid =
        const {60, 90, 120}.contains(slotMinutes) &&
        basePrice >= 0 &&
        basePrice <= BookingEngine.maxPrice &&
        rules.every(
          (r) =>
              r.weekdays.isNotEmpty &&
              r.weekdays.every((d) => d >= 1 && d <= 7) &&
              r.fromMinute >= 0 &&
              r.fromMinute < r.toMinute &&
              r.toMinute <= 1440 &&
              r.price >= 0 &&
              r.price <= BookingEngine.maxPrice,
        );
    if (!valid) throw const BookingException(BookingError.invalidArgument);
    if (overlappingRules(rules).isNotEmpty) throw const BookingException(BookingError.rulesOverlap);
    _replaceCourt(
      venueId,
      courtId,
      (c) => _withCourt(c, slotMinutes: slotMinutes, basePrice: basePrice, priceRules: List.unmodifiable(rules)),
    );
    _backend._log(
      'owner_set_court_pricing',
      'court',
      courtId,
      after: {
        'slot_minutes': slotMinutes,
        'base_price': basePrice,
        'rules': [
          for (final r in rules)
            {'weekdays': r.weekdays.toList()..sort(), 'from_minute': r.fromMinute, 'to_minute': r.toMinute, 'price': r.price},
        ],
      },
    );
  }

  @override
  Future<OwnerDashboard> dashboard(String venueId, {String? courtId, required DateTime from, required DateTime to}) async {
    _owned(venueId);
    return _engine.ownerDashboard(venueId, courtId: courtId, from: from, to: to);
  }
}

/// The admin functions over the sample backend's data, with the database's
/// validation. Changes last for the rest of the run.
class _SampleAdminRepository implements AdminRepository {
  _SampleAdminRepository(this._b);

  final SampleBackend _b;
  int _nextVenue = 1;
  int _nextBanner = 1;

  static const _maxText = 200;
  static const _maxDescription = 2000;

  static Never _invalid() => throw const BookingException(BookingError.invalidArgument);
  static Never _notFound() => throw const BookingException(BookingError.notFound);

  static bool _blank(String? s) => s == null || s.trim().isEmpty;
  static bool _named(LocalizedText t) => !_blank(t.uz) || !_blank(t.ru) || !_blank(t.en);
  static bool _fits(LocalizedText t, int max) => [t.uz, t.ru, t.en].every((s) => s == null || s.trim().length <= max);
  static bool _knownCity(String id) => kCities.any((c) => c.id == id);

  /// Blank languages become null, as the database stores them.
  static LocalizedText _clean(LocalizedText t) {
    String? c(String? s) => _blank(s) ? null : s!.trim();
    return LocalizedText(uz: c(t.uz), ru: c(t.ru), en: c(t.en));
  }

  String _ownerName(String userId) => userId == kMeId
      ? _b.meName
      : kSamplePlayers.firstWhere((p) => p.id == userId, orElse: () => Player(id: userId, name: userId)).name;

  /// The venue and court for [courtId].
  (Venue, Court) _findCourt(String courtId) {
    for (final v in _b._venues.values) {
      for (final c in v.courts) {
        if (c.id == courtId) return (v, c);
      }
    }
    _notFound();
  }

  AdminVenue _adminVenue(Venue v) => AdminVenue(
    venue: v,
    active: !_b._inactiveVenues.contains(v.id),
    inactiveCourtIds: {for (final c in v.courts) if (_b._inactiveCourts.contains(c.id)) c.id},
    owners: [
      for (final id in _b._owners[v.id] ?? const <String>{}) OwnerRef(userId: id, name: _ownerName(id)),
    ],
  );

  @override
  Future<bool> isAdmin() async => true;

  // ---- Venues and courts ----

  @override
  Future<List<AdminVenue>> venues() async => [for (final v in _b._venues.values.toList().reversed) _adminVenue(v)];

  @override
  Future<String> saveVenue(VenueDraft draft) async {
    final valid =
        _knownCity(draft.cityId) &&
        _named(draft.name) &&
        _fits(draft.name, _maxText) &&
        _fits(draft.address, _maxText) &&
        _fits(draft.district, _maxText) &&
        _fits(draft.description, _maxDescription) &&
        draft.phone.trim().length <= _maxText &&
        draft.amenities.every(kAmenityKeys.contains);
    if (!valid) _invalid();

    final existing = draft.id == null ? null : (_b._venues[draft.id] ?? _notFound());
    final before = existing == null ? null : venueDraftJson(VenueDraft.from(_adminVenue(existing)));
    var id = existing?.id ?? '';
    while (existing == null && (id.isEmpty || _b._venues.containsKey(id))) {
      id = 'v${kSampleVenues.length + _nextVenue++}';
    }
    _b._venues[id] = Venue(
      id: id,
      cityId: draft.cityId,
      name: _clean(draft.name),
      description: _clean(draft.description),
      address: _clean(draft.address),
      district: _clean(draft.district),
      phone: draft.phone.trim(),
      hours: existing?.hours ?? weekHours(weekdays: const DayHours.hm(8, 0, 22, 0), weekend: const DayHours.hm(8, 0, 22, 0)),
      courts: existing?.courts ?? const [],
      amenities: List.unmodifiable(draft.amenities),
      colorSeed: existing?.colorSeed ?? _b._venues.length,
    );
    if (draft.active) {
      _b._inactiveVenues.remove(id);
    } else {
      _b._inactiveVenues.add(id);
    }
    // Whoever creates a venue manages it.
    if (existing == null) _b._owners[id] = {kMeId};
    _b._log(
      'admin_save_venue',
      'venue',
      id,
      before: before,
      after: venueDraftJson(VenueDraft.from(_adminVenue(_b._venue(id)))),
    );
    return id;
  }

  @override
  Future<void> deleteVenue(String venueId) async {
    final venue = _b._venues[venueId] ?? _notFound();
    if (_b._engine.hasBookings(venueId: venueId)) throw const BookingException(BookingError.hasBookings);
    final before = venueDraftJson(VenueDraft.from(_adminVenue(venue)));
    _b._venues.remove(venueId);
    _b._inactiveVenues.remove(venueId);
    _b._owners.remove(venueId);
    for (final c in venue.courts) {
      _b._inactiveCourts.remove(c.id);
    }
    _b._log('admin_delete_venue', 'venue', venueId, before: before);
  }

  @override
  Future<String> saveCourt(CourtDraft draft) async {
    final valid =
        _b._venues.containsKey(draft.venueId) &&
        _b._sports.containsKey(draft.sportId) &&
        _named(draft.name) &&
        _fits(draft.name, _maxText) &&
        const {60, 90, 120}.contains(draft.slotMinutes) &&
        draft.basePrice >= 0 &&
        draft.basePrice <= BookingEngine.maxPrice;
    if (!valid) _invalid();

    Court? existing;
    if (draft.id != null) {
      final (venue, court) = _findCourt(draft.id!);
      // A court stays in its venue.
      if (venue.id != draft.venueId) _invalid();
      existing = court;
    }
    final venue = _b._venue(draft.venueId);
    final before = existing == null
        ? null
        : courtDraftJson(CourtDraft.from(existing, active: !_b._inactiveCourts.contains(existing.id)));
    final id = existing?.id ?? _newCourtId(venue);
    final court = Court(
      id: id,
      venueId: venue.id,
      sportId: draft.sportId,
      name: _clean(draft.name),
      slotMinutes: draft.slotMinutes,
      basePrice: draft.basePrice,
      priceRules: existing?.priceRules ?? const [],
      hoursOverride: existing?.hoursOverride ?? const {},
      indoor: draft.indoor,
    );
    _b._venues[venue.id] = venue.copyWith(
      courts: existing == null ? [...venue.courts, court] : [for (final c in venue.courts) c.id == id ? court : c],
    );
    if (draft.active) {
      _b._inactiveCourts.remove(id);
    } else {
      _b._inactiveCourts.add(id);
    }
    _b._log(
      'admin_save_court',
      'court',
      id,
      before: before,
      after: courtDraftJson(CourtDraft.from(court, active: draft.active)),
    );
    return id;
  }

  String _newCourtId(Venue venue) {
    final taken = {for (final v in _b._venues.values) ...v.courts.map((c) => c.id)};
    var n = venue.courts.length + 1;
    while (taken.contains('${venue.id}c$n')) {
      n++;
    }
    return '${venue.id}c$n';
  }

  @override
  Future<String> duplicateCourt(String courtId) async {
    final (venue, original) = _findCourt(courtId);
    String? two(String? s) => _blank(s) ? s : '$s 2';
    final id = _newCourtId(venue);
    final copy = Court(
      id: id,
      venueId: venue.id,
      sportId: original.sportId,
      name: LocalizedText(uz: two(original.name.uz), ru: two(original.name.ru), en: two(original.name.en)),
      slotMinutes: original.slotMinutes,
      basePrice: original.basePrice,
      priceRules: original.priceRules,
      hoursOverride: original.hoursOverride,
      indoor: original.indoor,
    );
    final courts = [...venue.courts];
    courts.insert(courts.indexWhere((c) => c.id == courtId) + 1, copy);
    _b._venues[venue.id] = venue.copyWith(courts: courts);
    _b._log(
      'admin_duplicate_court',
      'court',
      id,
      before: {'source_court_id': courtId},
      after: courtDraftJson(CourtDraft.from(copy, active: true)),
    );
    return id;
  }

  @override
  Future<void> deleteCourt(String courtId) async {
    final (venue, court) = _findCourt(courtId);
    if (_b._engine.hasBookings(courtId: courtId)) throw const BookingException(BookingError.hasBookings);
    final before = courtDraftJson(CourtDraft.from(court, active: !_b._inactiveCourts.contains(courtId)));
    _b._venues[venue.id] = venue.copyWith(courts: [for (final c in venue.courts) if (c.id != courtId) c]);
    _b._inactiveCourts.remove(courtId);
    _b._log('admin_delete_court', 'court', courtId, before: before);
  }

  // ---- Owners ----

  @override
  Future<List<OwnerRef>> searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final people = [
      if (!_blank(_b.meName)) OwnerRef(userId: kMeId, name: _b.meName),
      for (final p in kSamplePlayers) OwnerRef(userId: p.id, name: p.name),
    ];
    bool matches(OwnerRef u) =>
        u.name.toLowerCase().contains(q) ||
        (digits.isNotEmpty && (u.phone?.replaceAll(RegExp(r'\D'), '').contains(digits) ?? false));
    return people.where(matches).take(20).toList();
  }

  @override
  Future<void> setOwner(String venueId, String userId, {required bool assigned}) async {
    if (!_b._venues.containsKey(venueId)) _notFound();
    final owners = _b._owners.putIfAbsent(venueId, () => {});
    if (assigned) {
      owners.add(userId);
    } else {
      owners.remove(userId);
    }
    _b._log('admin_set_owner', 'venue_owner', venueId, after: {'user_id': userId, 'assigned': assigned});
  }

  // ---- Sports ----

  @override
  Future<List<AdminSport>> sports() async =>
      _b._sports.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<String> saveSport(SportDraft draft, {required bool create}) async {
    final id = draft.id.trim();
    final valid =
        kSportIdPattern.hasMatch(id) &&
        _named(draft.name) &&
        _fits(draft.name, _maxText) &&
        !_blank(draft.iconKey) &&
        draft.iconKey.trim().length <= _maxText &&
        draft.defaultPlayers > 0;
    if (!valid) _invalid();
    final existing = _b._sports[id];
    if (create && existing != null) throw const BookingException(BookingError.alreadyExists);
    if (!create && existing == null) _notFound();

    final saved = AdminSport(
      sport: Sport(
        id: id,
        name: _clean(draft.name),
        iconKey: draft.iconKey.trim(),
        bookable: draft.bookable,
        competitiveRating: draft.competitiveRating,
        defaultPlayers: draft.defaultPlayers,
      ),
      sortOrder: draft.sortOrder,
      active: draft.active,
    );
    _b._sports[id] = saved;
    _b._log(
      'admin_save_sport',
      'sport',
      id,
      before: existing == null ? null : sportDraftJson(SportDraft.from(existing)),
      after: sportDraftJson(SportDraft.from(saved)),
    );
    return id;
  }

  // ---- Banners ----

  @override
  Future<List<AdminBanner>> banners() async =>
      _b._banners.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<String> saveBanner(BannerDraft draft) async {
    final valid =
        (draft.cityId == null || _knownCity(draft.cityId!)) &&
        _named(draft.title) &&
        _fits(draft.title, _maxText) &&
        _fits(draft.subtitle, _maxText) &&
        draft.url.trim().startsWith('https://') &&
        draft.url.trim().length > 'https://'.length;
    if (!valid) _invalid();
    final existing = draft.id == null ? null : (_b._banners[draft.id] ?? _notFound());

    var id = existing?.id ?? '';
    while (existing == null && (id.isEmpty || _b._banners.containsKey(id))) {
      id = 'bn${kSampleBanners.length + _nextBanner++}';
    }
    final saved = AdminBanner(
      id: id,
      cityId: draft.cityId,
      title: _clean(draft.title),
      subtitle: _clean(draft.subtitle),
      url: draft.url.trim(),
      sortOrder: draft.sortOrder,
      active: draft.active,
    );
    _b._banners[id] = saved;
    _b._bannerColors.putIfAbsent(id, () => _b._banners.length);
    _b._log(
      'admin_save_banner',
      'banner',
      id,
      before: existing == null ? null : bannerDraftJson(BannerDraft.from(existing)),
      after: bannerDraftJson(BannerDraft.from(saved)),
    );
    return id;
  }

  @override
  Future<void> deleteBanner(String bannerId) async {
    final existing = _b._banners.remove(bannerId) ?? _notFound();
    _b._log('admin_delete_banner', 'banner', bannerId, before: bannerDraftJson(BannerDraft.from(existing)));
  }

  // ---- Audit log ----

  @override
  Future<List<AuditEntry>> auditLog({int limit = 50, DateTime? before}) async {
    if (limit < 1 || limit > 100) _invalid();
    return _b._audit.reversed.where((e) => before == null || e.at.isBefore(before)).take(limit).toList();
  }
}
