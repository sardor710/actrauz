import '../../core/localized_text.dart';
import '../../core/markets.dart';
import '../../domain/tournaments.dart';
import 'sample_data.dart';

/// The tournament rules of the database, in memory: caps that are never
/// exceeded, partner invites that expire after 48 hours, a waitlist whose
/// offers hold the spot for 24 hours, fees locked at registration, and the
/// admin's changes (product spec §14, plan M5 Global Constraints).
///
/// Everything is kept in the tournament's city time, as the app sees it.
/// Expired invites and offers are settled at the start of every call, so they
/// never hold a spot or block anyone ("lazy expiry").
///
/// Not modelled: the deadline reminder job, and registrations of players the
/// sample data does not name (a category's `taken` count stands for them: they
/// hold spots but show in no list).
class SampleTournaments {
  SampleTournaments({
    required this.utcNow,
    required this.cityNow,
    required this.venueCity,
    required this.venueName,
    required this.knownSport,
    required this.nameOf,
    required this.levelOf,
    required this.userExists,
    required this.isBlocked,
    required this.notify,
    this.isDeleted = _alive,
  }) {
    for (final seed in kTournamentSeeds) {
      final cityId = venueCity(seed.venueId)!;
      final first = dateOnly(cityNow(cityId)).add(Duration(days: seed.daysAhead));
      _tournaments[seed.id] = _Tournament(
        id: seed.id,
        cityId: cityId,
        sportId: seed.sportId,
        venueId: seed.venueId,
        title: seed.title,
        start: first,
        end: first.add(Duration(days: seed.days - 1)),
        deadline: first.add(Duration(days: -seed.deadlineDaysBefore, hours: 18)),
        colorSeed: _colorSeed(seed.id),
      );
      for (final (i, c) in seed.categories.indexed) {
        _categories[c.id] = _Category(
          id: c.id,
          tournamentId: seed.id,
          name: c.name,
          kind: c.kind,
          gender: c.gender,
          minLevel: c.minLevel,
          maxLevel: c.maxLevel,
          fee: c.fee,
          cap: c.cap,
          waitlistEnabled: c.waitlistEnabled,
          sortOrder: i,
          taken: c.taken,
        );
      }
    }
  }

  final DateTime Function() utcNow;

  /// Wall-clock time in a city.
  final DateTime Function(String cityId) cityNow;

  /// The city of a venue, or null when there is no such venue.
  final String? Function(String venueId) venueCity;
  final LocalizedText Function(String venueId) venueName;
  final bool Function(String sportId) knownSport;
  final String Function(String userId) nameOf;
  final int Function(String userId, String sportId) levelOf;
  final bool Function(String userId) userExists;
  final bool Function(String userId) isBlocked;

  /// Whether a player deleted their account: their entries stay as history,
  /// and their phone no longer finds them.
  final bool Function(String userId) isDeleted;
  static bool _alive(String userId) => false;

  /// Writes to a player's inbox (only the demo player has one).
  final void Function(String userId, String kind, String category, Map<String, Object?> payload) notify;

  final Map<String, _Tournament> _tournaments = {};
  final Map<String, _Category> _categories = {};
  final List<_Entry> _entries = [];
  final Map<String, List<DateTime>> _phoneLookups = {};
  int _nextId = 1;
  int _waitSeq = 1;

  static const _inviteHours = 48;
  static const _offerHours = 24;
  static const _lookupLimit = 20;

  static int _colorSeed(String id) => id.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) % 1000);

  static Never _fail(TournamentError error) => throw TournamentException(error);

  // ---- Lookups ----

  _Tournament _tournament(String id) => _tournaments[id] ?? _fail(TournamentError.notFound);

  _Category _categoryRow(String id) => _categories[id] ?? _fail(TournamentError.notFound);

  _Entry _entryRow(String id) => _entries.where((e) => e.id == id).firstOrNull ?? _fail(TournamentError.notFound);

  /// A category of an active tournament.
  _Category _openCategory(String id) {
    final c = _categoryRow(id);
    if (!_tournaments[c.tournamentId]!.active) _fail(TournamentError.notFound);
    return c;
  }

  Iterable<_Category> _categoriesOf(String tournamentId) {
    final rows = _categories.values.where((c) => c.tournamentId == tournamentId).toList();
    // Stable: equal sort orders keep their creation order.
    return [for (final (_, c) in (rows.indexed.toList()..sort(_bySortOrder))) c];
  }

  static int _bySortOrder((int, _Category) a, (int, _Category) b) {
    final byOrder = a.$2.sortOrder.compareTo(b.$2.sortOrder);
    return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
  }

  DateTime _now(_Tournament t) => cityNow(t.cityId);

  int _counted(_Category c) => c.taken + _entries.where((e) => e.categoryId == c.id && e.status.counted).length;

  Iterable<_Entry> _liveIn(String categoryId) => _entries.where((e) => e.categoryId == categoryId && e.status.live);

  /// The player is in the category: registrant of a live entry, or its
  /// confirmed partner. [except] leaves one entry out.
  bool _isIn(String categoryId, String userId, {String? except}) => _liveIn(
    categoryId,
  ).any((e) => e.id != except && (e.userId == userId || (e.partnerId == userId && e.partnerConfirmed)));

  bool _isMember(_Entry e, String userId) => e.userId == userId || (e.partnerId == userId && e.partnerConfirmed);

  static Map<String, Object?> _loc(LocalizedText t) => {'uz': t.uz, 'ru': t.ru, 'kk': t.kk, 'en': t.en};

  // ---- Expiry ----

  void _sweepAll() {
    for (final c in _categories.values.toList()) {
      _sweep(c);
    }
  }

  /// Invites past their expiry become `expired` (the registrant is told);
  /// offers past theirs become `lapsed` and the spot goes to the next entry.
  void _sweep(_Category c) {
    final t = _tournaments[c.tournamentId]!;
    final now = _now(t);
    for (final e in _entries.where((e) => e.categoryId == c.id).toList()) {
      if ((e.status == RegistrationStatus.pendingPartner || e.status == RegistrationStatus.waitlisted) &&
          !e.partnerConfirmed &&
          e.partnerExpiresAt != null &&
          !e.partnerExpiresAt!.isAfter(now)) {
        e.status = RegistrationStatus.expired;
        notify(e.userId, 'tournament_partner_expired', 'tournaments', _note(e));
      }
    }
    var lapsed = false;
    for (final e in _entries.where((e) => e.categoryId == c.id && e.status == RegistrationStatus.offered)) {
      if (e.offerExpiresAt != null && !e.offerExpiresAt!.isAfter(now)) {
        e.status = RegistrationStatus.lapsed;
        lapsed = true;
      }
    }
    if (lapsed) _offerSpots(c, admin: false);
  }

  // ---- Offers ----

  /// While the category has room, the first confirmed waitlisted entry is
  /// offered the spot; the offer holds it. Nothing once the deadline has
  /// passed, unless [admin] asks. Returns how many were offered.
  int _offerSpots(_Category c, {required bool admin}) {
    final t = _tournaments[c.tournamentId]!;
    final now = _now(t);
    if (!t.active || (!admin && !now.isBefore(t.deadline))) return 0;
    var offered = 0;
    while (_counted(c) < c.cap) {
      final next =
          (_entries
                  .where((e) => e.categoryId == c.id && e.status == RegistrationStatus.waitlisted && e.partnerConfirmed)
                  .toList()
                ..sort((a, b) => a.waitlistPosition!.compareTo(b.waitlistPosition!)))
              .firstOrNull;
      if (next == null) break;
      final hold = now.add(const Duration(hours: _offerHours));
      next
        ..status = RegistrationStatus.offered
        ..offerExpiresAt = now.isBefore(t.deadline) && t.deadline.isBefore(hold) ? t.deadline : hold;
      final note = {..._note(next), 'offer_expires_local': _local(next.offerExpiresAt!)};
      notify(next.userId, 'tournament_spot_offered', 'tournaments', note);
      if (next.partnerId != null) notify(next.partnerId!, 'tournament_spot_offered', 'tournaments', note);
      offered++;
    }
    return offered;
  }

  static String _local(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// What every tournament notification carries besides its own keys.
  Map<String, Object?> _note(_Entry e) {
    final c = _categories[e.categoryId]!;
    final t = _tournaments[c.tournamentId]!;
    return {
      'registration_id': e.id,
      'tournament_id': t.id,
      'category_id': c.id,
      'title': _loc(t.title),
      'category_name': _loc(c.name),
    };
  }

  void _notifyBoth(_Entry e, String kind, [Map<String, Object?> extra = const {}]) {
    final note = {..._note(e), ...extra};
    notify(e.userId, kind, 'tournaments', note);
    if (e.partnerId != null) notify(e.partnerId!, kind, 'tournaments', note);
  }

  // ---- Views ----

  Registration _view(_Entry e, String viewer, {bool withTournament = false}) {
    final c = _categories[e.categoryId]!;
    final t = _tournaments[c.tournamentId]!;
    int? place;
    if (e.status == RegistrationStatus.waitlisted && e.partnerConfirmed) {
      place = _entries
          .where(
            (w) =>
                w.categoryId == e.categoryId &&
                w.status == RegistrationStatus.waitlisted &&
                w.partnerConfirmed &&
                w.waitlistPosition! <= e.waitlistPosition!,
          )
          .length;
    }
    return Registration(
      id: e.id,
      tournamentId: t.id,
      categoryId: c.id,
      categoryName: c.name,
      kind: c.kind,
      status: e.status,
      registrant: PlayerRef(id: e.userId, name: nameOf(e.userId), deleted: isDeleted(e.userId)),
      partner: e.partnerId == null
          ? null
          : PlayerRef(id: e.partnerId!, name: nameOf(e.partnerId!), deleted: isDeleted(e.partnerId!)),
      partnerConfirmed: e.partnerConfirmed,
      fee: e.fee,
      currency: cityById(t.cityId).currency,
      paid: e.paidAt != null,
      partnerExpiresAt: e.partnerExpiresAt,
      offerExpiresAt: e.offerExpiresAt,
      waitlistPlace: place,
      createdAt: e.createdAt,
      role: viewer == e.userId
          ? RegistrationRole.registrant
          : viewer == e.partnerId
          ? RegistrationRole.partner
          : null,
      tournament: withTournament
          ? TournamentSummary(
              id: t.id,
              cityId: t.cityId,
              sportId: t.sportId,
              title: t.title,
              start: t.start,
              end: t.end,
              venueId: t.venueId,
              colorSeed: t.colorSeed,
              coverUrl: t.coverUrl,
              registrationOpen: t.active && _now(t).isBefore(t.deadline),
            )
          : null,
    );
  }

  TournamentCategory _categoryView(_Category c, String viewer) {
    final mine =
        (_liveIn(c.id).where((e) => e.userId == viewer || e.partnerId == viewer).toList()..sort((a, b) {
              final aIn = a.userId == viewer || a.partnerConfirmed;
              final bIn = b.userId == viewer || b.partnerConfirmed;
              if (aIn != bIn) return aIn ? -1 : 1;
              return b.seq.compareTo(a.seq);
            }))
            .firstOrNull;
    return TournamentCategory(
      id: c.id,
      tournamentId: c.tournamentId,
      name: c.name,
      kind: c.kind,
      gender: c.gender,
      minLevel: c.minLevel,
      maxLevel: c.maxLevel,
      fee: c.fee,
      cap: c.cap,
      filled: _counted(c),
      waitlistCount: _entries.where((e) => e.categoryId == c.id && e.status == RegistrationStatus.waitlisted).length,
      waitlistEnabled: c.waitlistEnabled,
      sortOrder: c.sortOrder,
      myStatus: mine?.status,
    );
  }

  Tournament _tournamentView(_Tournament t, String viewer) {
    final cats = _categoriesOf(t.id).toList();
    final fees = [for (final c in cats) c.fee];
    final mine = _entries
        .where(
          (e) =>
              e.status.live &&
              _categories[e.categoryId]!.tournamentId == t.id &&
              (e.userId == viewer || e.partnerId == viewer),
        )
        .toList()
        .reversed;
    return Tournament(
      id: t.id,
      cityId: t.cityId,
      sportId: t.sportId,
      title: t.title,
      venueName: t.venueId == null ? const LocalizedText() : venueName(t.venueId!),
      start: t.start,
      end: t.end,
      minFee: fees.isEmpty ? 0 : fees.reduce((a, b) => a < b ? a : b),
      maxFee: fees.isEmpty ? 0 : fees.reduce((a, b) => a > b ? a : b),
      slotsTotal: cats.fold(0, (sum, c) => sum + c.cap),
      slotsFilled: cats.fold(0, (sum, c) => sum + _counted(c)),
      currency: cityById(t.cityId).currency,
      registrationDeadline: t.deadline,
      registrationOpen: t.active && _now(t).isBefore(t.deadline),
      venueId: t.venueId,
      description: t.description,
      coverUrl: t.coverUrl,
      colorSeed: t.colorSeed,
      active: t.active,
      categories: [for (final c in cats) _categoryView(c, viewer)],
      myRegistrations: [for (final e in mine) _view(e, viewer)],
    );
  }

  // ---- Players ----

  List<Tournament> list(
    String viewer,
    String cityId, {
    String? sportId,
    DateTime? from,
    TournamentSort sort = TournamentSort.date,
  }) {
    _sweepAll();
    final today = dateOnly(cityNow(cityId));
    final rows = _tournaments.values
        .where(
          (t) =>
              t.active &&
              t.cityId == cityId &&
              (sportId == null || t.sportId == sportId) &&
              !t.end.isBefore(today) &&
              (from == null || !t.end.isBefore(dateOnly(from))),
        )
        .toList();
    rows.sort((a, b) {
      if (sort == TournamentSort.az) {
        final byTitle = a.title.resolve('ru').toLowerCase().compareTo(b.title.resolve('ru').toLowerCase());
        if (byTitle != 0) return byTitle;
      }
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });
    return [for (final t in rows) _tournamentView(t, viewer)];
  }

  Tournament get(String viewer, String id) {
    _sweepAll();
    final t = _tournament(id);
    if (!t.active) _fail(TournamentError.notFound);
    return _tournamentView(t, viewer);
  }

  /// The checks register and joinWaitlist share, in the database's order:
  /// reliability, deadline, arguments, levels, already in, partner already in.
  void _checkEntry(String userId, _Category c, _Tournament t, String? partnerId) {
    if (isBlocked(userId)) _fail(TournamentError.reliabilityTooLow);
    if (!_now(t).isBefore(t.deadline)) _fail(TournamentError.deadlinePassed);
    if (c.kind == CategoryKind.singles && partnerId != null) _fail(TournamentError.invalidArgument);
    if (c.kind == CategoryKind.pairs) {
      if (partnerId == null || partnerId == userId) _fail(TournamentError.invalidArgument);
      if (!userExists(partnerId)) _fail(TournamentError.notFound);
    }
    bool fits(String id) {
      final level = levelOf(id, t.sportId);
      return level >= c.minLevel && level <= c.maxLevel;
    }

    if (!fits(userId) || (partnerId != null && !fits(partnerId))) _fail(TournamentError.levelOutOfRange);
    if (_isIn(c.id, userId)) _fail(TournamentError.alreadyRegistered);
    if (partnerId != null && _isIn(c.id, partnerId)) _fail(TournamentError.partnerUnavailable);
  }

  _Entry _addEntry(
    _Category c,
    _Tournament t,
    String userId,
    String? partnerId, {
    required RegistrationStatus status,
    required bool confirmed,
    bool admin = false,
  }) {
    final now = _now(t);
    final pair = c.kind == CategoryKind.pairs && !admin;
    final n = _nextId++;
    final entry = _Entry(
      id: 'r$n',
      seq: n,
      categoryId: c.id,
      userId: userId,
      partnerId: partnerId,
      partnerConfirmed: confirmed,
      status: status,
      fee: c.fee,
      createdAt: utcNow(),
      partnerExpiresAt: pair ? _earlier(now.add(const Duration(hours: _inviteHours)), t.deadline) : null,
      adminOverride: admin,
    );
    _entries.add(entry);
    return entry;
  }

  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  /// Singles: registered at once while there is room. Pairs: pending until the
  /// partner accepts (48 hours, or until the deadline if sooner); not counted.
  Registration register(String userId, String categoryId, String? partnerId) {
    _sweepAll();
    final c = _openCategory(categoryId);
    final t = _tournaments[c.tournamentId]!;
    _checkEntry(userId, c, t, partnerId);
    final singles = c.kind == CategoryKind.singles;
    if (singles && _counted(c) >= c.cap) _fail(TournamentError.full);

    final entry = _addEntry(
      c,
      t,
      userId,
      partnerId,
      status: singles ? RegistrationStatus.registered : RegistrationStatus.pendingPartner,
      confirmed: singles,
    );
    if (singles) {
      notify(userId, 'tournament_registered', 'tournaments', _note(entry));
    } else {
      notify(partnerId!, 'tournament_partner_invite', 'invites', {..._note(entry), 'actor_name': nameOf(userId)});
    }
    return _view(entry, userId);
  }

  /// The named partner answers a pending pair, or an unconfirmed waitlisted
  /// pair. Accepting a pending pair registers it while there is room;
  /// accepting a waitlisted pair confirms it (it keeps its place, and is
  /// offered a spot at once if one is free).
  Registration respondPartner(String userId, String registrationId, {required bool accept}) {
    _sweepAll();
    final e = _entries.where((e) => e.id == registrationId).firstOrNull;
    if (e == null || e.partnerId != userId) _fail(TournamentError.notFound);
    final c = _categories[e.categoryId]!;
    final t = _tournaments[c.tournamentId]!;
    final now = _now(t);
    if (!now.isBefore(t.deadline)) _fail(TournamentError.deadlinePassed);
    final answerable =
        (e.status == RegistrationStatus.pendingPartner || e.status == RegistrationStatus.waitlisted) &&
        !e.partnerConfirmed &&
        (e.partnerExpiresAt == null || e.partnerExpiresAt!.isAfter(now));
    if (!answerable) _fail(TournamentError.notFound);

    final actor = {'actor_name': nameOf(userId)};
    if (!accept) {
      e.status = RegistrationStatus.declined;
      notify(e.userId, 'tournament_partner_declined', 'tournaments', {..._note(e), ...actor});
      return _view(e, userId);
    }

    if (isBlocked(userId)) _fail(TournamentError.reliabilityTooLow);
    bool fits(String id) {
      final level = levelOf(id, t.sportId);
      return level >= c.minLevel && level <= c.maxLevel;
    }

    if (!fits(e.userId) || !fits(userId)) _fail(TournamentError.levelOutOfRange);
    if (_isIn(c.id, e.userId, except: e.id) || _isIn(c.id, userId, except: e.id)) {
      _fail(TournamentError.partnerUnavailable);
    }

    if (e.status == RegistrationStatus.pendingPartner) {
      if (_counted(c) >= c.cap) _fail(TournamentError.full);
      e
        ..status = RegistrationStatus.registered
        ..partnerConfirmed = true;
      notify(e.userId, 'tournament_partner_accepted', 'tournaments', {..._note(e), ...actor});
      notify(e.userId, 'tournament_registered', 'tournaments', _note(e));
      notify(userId, 'tournament_registered', 'tournaments', _note(e));
    } else {
      e.partnerConfirmed = true;
      notify(e.userId, 'tournament_partner_accepted', 'tournaments', {..._note(e), ...actor});
      _offerSpots(c, admin: false);
    }
    return _view(e, userId);
  }

  /// The registrant or the confirmed partner, until the deadline. A spot that
  /// held a place goes to the waitlist.
  Registration cancel(String userId, String registrationId) {
    _sweepAll();
    final e = _entries.where((e) => e.id == registrationId).firstOrNull;
    if (e == null || !_isMember(e, userId)) _fail(TournamentError.notFound);
    final c = _categories[e.categoryId]!;
    final t = _tournaments[c.tournamentId]!;
    if (!t.active) _fail(TournamentError.notFound);
    if (!_now(t).isBefore(t.deadline)) _fail(TournamentError.deadlinePassed);
    if (!e.status.live) _fail(TournamentError.notFound);

    final held = e.status.counted;
    e.status = RegistrationStatus.cancelled;
    // On a pair the other player is told: the partner (confirmed or only
    // invited) when the registrant cancels, the registrant when the partner does.
    final other = e.userId == userId ? e.partnerId : e.userId;
    if (other != null) {
      notify(other, 'tournament_partner_cancelled', 'tournaments', {..._note(e), 'actor_name': nameOf(userId)});
    }
    if (held) _offerSpots(c, admin: false);
    return _view(e, userId);
  }

  /// Only into a full category with the waitlist on. A pairs entry waits for
  /// its partner's confirmation before it can be offered a spot.
  Registration joinWaitlist(String userId, String categoryId, String? partnerId) {
    _sweepAll();
    final c = _openCategory(categoryId);
    final t = _tournaments[c.tournamentId]!;
    _checkEntry(userId, c, t, partnerId);
    if (!c.waitlistEnabled) _fail(TournamentError.waitlistClosed);
    if (_counted(c) < c.cap) _fail(TournamentError.notFull);

    final singles = c.kind == CategoryKind.singles;
    final entry = _addEntry(c, t, userId, partnerId, status: RegistrationStatus.waitlisted, confirmed: singles)
      ..waitlistPosition = _waitSeq++;
    if (!singles) {
      notify(partnerId!, 'tournament_partner_invite', 'invites', {..._note(entry), 'actor_name': nameOf(userId)});
    }
    return _view(entry, userId);
  }

  /// The registrant or the confirmed partner takes an offered spot while the
  /// offer runs.
  Registration claimOffer(String userId, String registrationId) {
    _sweepAll();
    final e = _entries.where((e) => e.id == registrationId).firstOrNull;
    if (e == null || !_isMember(e, userId) || e.status != RegistrationStatus.offered) _fail(TournamentError.notFound);
    final t = _tournaments[_categories[e.categoryId]!.tournamentId]!;
    if (!t.active) _fail(TournamentError.notFound);
    if (isBlocked(userId)) _fail(TournamentError.reliabilityTooLow);
    e.status = RegistrationStatus.registered;
    _notifyBoth(e, 'tournament_registered');
    return _view(e, userId);
  }

  List<Registration> myRegistrations(String userId) {
    _sweepAll();
    final rows = <_Entry>[];
    for (final e in _entries.reversed) {
      if (e.userId != userId && e.partnerId != userId) continue;
      final t = _tournaments[_categories[e.categoryId]!.tournamentId]!;
      if (!t.active) continue;
      if (t.end.isBefore(dateOnly(_now(t)))) continue;
      rows.add(e);
    }
    rows.sort((a, b) => b.seq.compareTo(a.seq));
    return [for (final e in rows) _view(e, userId, withTournament: true)];
  }

  /// Whether a sample player has this phone number: their id and name, never
  /// the phone. At most 20 calls an hour per caller, hits and misses alike.
  PlayerRef? findPlayerByPhone(String userId, String phone) {
    final now = utcNow();
    final calls = _phoneLookups.putIfAbsent(userId, () => [])
      ..removeWhere((at) => !at.isAfter(now.subtract(const Duration(hours: 1))));
    if (calls.length >= _lookupLimit) _fail(TournamentError.rateLimited);
    calls.add(now);

    String normalize(String p) => p.replaceAll(RegExp(r'[\s()-]'), '');
    final wanted = normalize(phone);
    if (!RegExp(r'^\+[0-9]{7,15}$').hasMatch(wanted)) return null;
    for (final entry in kSamplePlayerPhones.entries) {
      if (normalize(entry.value) == wanted && !isDeleted(entry.key)) {
        return PlayerRef(id: entry.key, name: nameOf(entry.key));
      }
    }
    return null;
  }

  // ---- Admin ----

  static const _maxText = 200;
  static const _maxDescription = 2000;

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  static bool _named(LocalizedText t) => !_blank(t.uz) || !_blank(t.ru) || !_blank(t.kk) || !_blank(t.en);

  static bool _fits(LocalizedText t, int max) => [t.uz, t.ru, t.kk, t.en].every((s) => s == null || s.trim().length <= max);

  /// Blank languages become null, as the database stores them.
  static LocalizedText _clean(LocalizedText t) {
    String? c(String? s) => _blank(s) ? null : s!.trim();
    return LocalizedText(uz: c(t.uz), ru: c(t.ru), kk: c(t.kk), en: c(t.en));
  }

  List<AdminTournament> adminTournaments() {
    _sweepAll();
    final rows = _tournaments.values.toList()
      ..sort((a, b) {
        final byStart = b.start.compareTo(a.start);
        return byStart != 0 ? byStart : a.id.compareTo(b.id);
      });
    return [
      for (final t in rows)
        AdminTournament(
          tournament: _tournamentView(t, ''),
          categoryCount: _categories.values.where((c) => c.tournamentId == t.id).length,
          registrationCount: _entries
              .where((e) => e.status.live && _categories[e.categoryId]!.tournamentId == t.id)
              .length,
        ),
    ];
  }

  void _validateCategory(CategoryDraft d) {
    if (!_named(d.name) ||
        !_fits(d.name, _maxText) ||
        d.minLevel < 1 ||
        d.maxLevel > 5 ||
        d.minLevel > d.maxLevel ||
        d.fee < 0 ||
        d.fee > 50000000 ||
        d.cap < 1 ||
        d.cap > 512) {
      _fail(TournamentError.invalidArgument);
    }
  }

  /// The tournament's id. No `id` on the draft = create; categories on the
  /// draft are made with it, or one open singles category (fee 0, 16 places).
  String saveTournament(TournamentDraft d) {
    _sweepAll();
    final start = dateOnly(d.start);
    final end = dateOnly(d.end);
    final creating = d.id == null;
    final existing = creating ? null : _tournament(d.id!);
    final deadline = d.registrationDeadline ?? start;
    final venueOk = d.venueId == null || venueCity(d.venueId!) == d.cityId;
    if (!kCities.any((c) => c.id == d.cityId) ||
        !knownSport(d.sportId) ||
        !venueOk ||
        !_named(d.title) ||
        !_fits(d.title, _maxText) ||
        !_fits(d.description, _maxDescription) ||
        end.isBefore(start) ||
        (!_blank(d.coverUrl) && !RegExp(r'^https://\S+$').hasMatch(d.coverUrl!.trim())) ||
        deadline.isAfter(end.add(const Duration(days: 1)))) {
      _fail(TournamentError.invalidArgument);
    }
    if (creating) {
      for (final c in d.categories) {
        _validateCategory(c);
      }
    } else if (existing!.cityId != d.cityId &&
        _entries.any((e) => e.status.live && _categories[e.categoryId]!.tournamentId == existing.id)) {
      // Fees already taken are in the old city's currency.
      _fail(TournamentError.hasRegistrations);
    }

    final id = existing?.id ?? 'tx${_nextId++}';
    final t =
        existing ??
        _Tournament(
          id: id,
          cityId: d.cityId,
          sportId: d.sportId,
          start: start,
          end: end,
          deadline: deadline,
          title: d.title,
        );
    t
      ..cityId = d.cityId
      ..sportId = d.sportId
      ..venueId = d.venueId
      ..title = _clean(d.title)
      ..description = _clean(d.description)
      ..start = start
      ..end = end
      ..deadline = deadline
      ..coverUrl = _blank(d.coverUrl) ? null : d.coverUrl!.trim()
      ..colorSeed = d.colorSeed ?? existing?.colorSeed ?? _colorSeed(id)
      ..active = d.active;
    _tournaments[id] = t;

    if (creating) {
      final drafts = d.categories.isEmpty
          ? [
              CategoryDraft(
                name: const LocalizedText(uz: 'Ochiq', ru: 'Открытая', en: 'Open'),
              ),
            ]
          : d.categories;
      for (final (i, c) in drafts.indexed) {
        _categories['${id}c${i + 1}'] = _Category(
          id: '${id}c${i + 1}',
          tournamentId: id,
          name: _clean(c.name),
          kind: c.kind,
          gender: c.gender,
          minLevel: c.minLevel,
          maxLevel: c.maxLevel,
          fee: c.fee,
          cap: c.cap,
          waitlistEnabled: c.waitlistEnabled,
          sortOrder: c.sortOrder ?? i,
        );
      }
    }
    return id;
  }

  String saveCategory(CategoryDraft d) {
    _sweepAll();
    if (d.id != null) _categoryRow(d.id!);
    _validateCategory(d);
    if (d.id == null) {
      if (d.tournamentId == null || !_tournaments.containsKey(d.tournamentId)) _fail(TournamentError.invalidArgument);
      final siblings = _categoriesOf(d.tournamentId!).toList();
      final id = '${d.tournamentId}n${_nextId++}';
      _categories[id] = _Category(
        id: id,
        tournamentId: d.tournamentId!,
        name: _clean(d.name),
        kind: d.kind,
        gender: d.gender,
        minLevel: d.minLevel,
        maxLevel: d.maxLevel,
        fee: d.fee,
        cap: d.cap,
        waitlistEnabled: d.waitlistEnabled,
        sortOrder:
            d.sortOrder ??
            (siblings.isEmpty ? 0 : siblings.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1),
      );
      return id;
    }

    final c = _categoryRow(d.id!);
    if (d.tournamentId != null && d.tournamentId != c.tournamentId) _fail(TournamentError.invalidArgument);
    if (d.cap < _counted(c)) _fail(TournamentError.invalidArgument);
    if (d.kind != c.kind && (c.taken > 0 || _liveIn(c.id).isNotEmpty)) _fail(TournamentError.hasRegistrations);
    final before = c.cap;
    c
      ..name = _clean(d.name)
      ..kind = d.kind
      ..gender = d.gender
      ..minLevel = d.minLevel
      ..maxLevel = d.maxLevel
      ..fee = d.fee
      ..cap = d.cap
      ..waitlistEnabled = d.waitlistEnabled
      ..sortOrder = d.sortOrder ?? c.sortOrder;
    if (c.cap > before) _offerSpots(c, admin: false);
    return c.id;
  }

  void deleteCategory(String categoryId) {
    final c = _categoryRow(categoryId);
    // History is never deleted: a category any registration was ever in stays.
    if (c.taken > 0 || _entries.any((e) => e.categoryId == c.id)) _fail(TournamentError.hasRegistrations);
    if (!_categories.values.any((o) => o.tournamentId == c.tournamentId && o.id != c.id)) {
      _fail(TournamentError.invalidArgument);
    }
    _categories.remove(c.id);
  }

  String? _phone(String userId) => kSamplePlayerPhones[userId];

  AdminRegistration _adminView(_Entry e) => AdminRegistration(
    registration: _view(e, ''),
    registrantPhone: _phone(e.userId),
    partnerPhone: e.partnerId == null ? null : _phone(e.partnerId!),
    paidAt: e.paidAt,
    adminOverride: e.adminOverride,
    waitlistPosition: e.waitlistPosition,
  );

  List<AdminRegistration> registrations(String tournamentId) {
    _sweepAll();
    _tournament(tournamentId);
    int rank(RegistrationStatus s) => switch (s) {
      RegistrationStatus.registered => 0,
      RegistrationStatus.offered => 1,
      RegistrationStatus.pendingPartner => 2,
      RegistrationStatus.waitlisted => 3,
      _ => 4,
    };
    final out = <_Entry>[];
    for (final c in _categoriesOf(tournamentId)) {
      final rows = _entries.where((e) => e.categoryId == c.id).toList()
        ..sort((a, b) {
          final byRank = rank(a.status).compareTo(rank(b.status));
          if (byRank != 0) return byRank;
          final byWait = (a.waitlistPosition ?? -1).compareTo(b.waitlistPosition ?? -1);
          return byWait != 0 ? byWait : a.seq.compareTo(b.seq);
        });
      out.addAll(rows);
    }
    return [for (final e in out) _adminView(e)];
  }

  AdminRegistration setPaid(String registrationId, bool paid) {
    final e = _entryRow(registrationId);
    if (e.status != RegistrationStatus.registered) _fail(TournamentError.notMarkable);
    e.paidAt = paid ? (e.paidAt ?? utcNow()) : null;
    return _adminView(e);
  }

  AdminRegistration removeRegistration(String registrationId) {
    _sweepAll();
    final e = _entryRow(registrationId);
    if (!e.status.live) _fail(TournamentError.notFound);
    final held = e.status.counted;
    e.status = RegistrationStatus.removed;
    _notifyBoth(e, 'tournament_removed');
    if (held) _offerSpots(_categories[e.categoryId]!, admin: false);
    return _adminView(e);
  }

  AdminRegistration moveRegistration(String registrationId, String categoryId) {
    _sweepAll();
    final e = _entryRow(registrationId);
    final target = _categoryRow(categoryId);
    final source = _categories[e.categoryId]!;
    if (target.id == source.id ||
        target.tournamentId != source.tournamentId ||
        target.kind != source.kind ||
        e.status != RegistrationStatus.registered) {
      _fail(TournamentError.invalidArgument);
    }
    final partner = e.partnerConfirmed ? e.partnerId : null;
    if (_isIn(target.id, e.userId, except: e.id)) _fail(TournamentError.alreadyRegistered);
    if (partner != null && _isIn(target.id, partner, except: e.id)) _fail(TournamentError.partnerUnavailable);
    if (_counted(target) >= target.cap) _fail(TournamentError.full);

    e.categoryId = target.id;
    _notifyBoth(e, 'tournament_moved', {'from_category_name': _loc(source.name)});
    _offerSpots(source, admin: false);
    return _adminView(e);
  }

  AdminRegistration addRegistration(String categoryId, String userId, String? partnerId) {
    _sweepAll();
    final c = _openCategory(categoryId);
    final t = _tournaments[c.tournamentId]!;
    if ((c.kind == CategoryKind.singles && partnerId != null) ||
        (c.kind == CategoryKind.pairs && (partnerId == null || partnerId == userId))) {
      _fail(TournamentError.invalidArgument);
    }
    if (!userExists(userId) || (partnerId != null && !userExists(partnerId))) _fail(TournamentError.notFound);
    if (_isIn(c.id, userId)) _fail(TournamentError.alreadyRegistered);
    if (partnerId != null && _isIn(c.id, partnerId)) _fail(TournamentError.partnerUnavailable);
    if (_counted(c) >= c.cap) _fail(TournamentError.full);

    final e = _addEntry(c, t, userId, partnerId, status: RegistrationStatus.registered, confirmed: true, admin: true);
    _notifyBoth(e, 'tournament_registered');
    return _adminView(e);
  }

  /// Offers the free spots to the waitlist now, also after the deadline.
  int offerNext(String categoryId) {
    _sweepAll();
    final c = _categoryRow(categoryId);
    if (_counted(c) >= c.cap) _fail(TournamentError.full);
    return _offerSpots(c, admin: true);
  }

  /// Fees of registered entries marked paid in the period (city-local days,
  /// inclusive), per currency; [cityId] null = every city.
  Map<Currency, int> paidRevenue(String? cityId, DateTime from, DateTime to) {
    final sums = <Currency, int>{};
    for (final e in _entries) {
      final paidAt = e.paidAt;
      if (e.status != RegistrationStatus.registered || paidAt == null) continue;
      final t = _tournaments[_categories[e.categoryId]!.tournamentId]!;
      if (cityId != null && t.cityId != cityId) continue;
      final city = cityById(t.cityId);
      final day = dateOnly(paidAt.add(Duration(minutes: city.utcOffsetMinutes)));
      if (day.isBefore(dateOnly(from)) || day.isAfter(dateOnly(to))) continue;
      sums[city.currency] = (sums[city.currency] ?? 0) + e.fee;
    }
    return sums;
  }

  /// Entries created in the period (city-local days, inclusive), any state.
  int registrationsCreated(String? cityId, DateTime from, DateTime to) {
    var n = 0;
    for (final e in _entries) {
      final t = _tournaments[_categories[e.categoryId]!.tournamentId]!;
      if (cityId != null && t.cityId != cityId) continue;
      final day = dateOnly(e.createdAt.add(Duration(minutes: cityById(t.cityId).utcOffsetMinutes)));
      if (!day.isBefore(dateOnly(from)) && !day.isAfter(dateOnly(to))) n++;
    }
    return n;
  }
}

class _Tournament {
  _Tournament({
    required this.id,
    required this.cityId,
    required this.sportId,
    required this.title,
    required this.start,
    required this.end,
    required this.deadline,
    this.venueId,
    this.colorSeed = 0,
  });

  final String id;
  String cityId;
  String sportId;
  String? venueId;
  LocalizedText title;
  LocalizedText description = const LocalizedText();
  DateTime start;
  DateTime end;
  DateTime deadline;
  String? coverUrl;
  int colorSeed;
  bool active = true;
}

class _Category {
  _Category({
    required this.id,
    required this.tournamentId,
    required this.name,
    required this.kind,
    required this.gender,
    required this.minLevel,
    required this.maxLevel,
    required this.fee,
    required this.cap,
    required this.waitlistEnabled,
    required this.sortOrder,
    this.taken = 0,
  });

  final String id;
  final String tournamentId;
  LocalizedText name;
  CategoryKind kind;
  CategoryGender gender;
  int minLevel;
  int maxLevel;
  int fee;
  int cap;
  bool waitlistEnabled;
  int sortOrder;

  /// Spots held by players the sample data does not name.
  final int taken;
}

class _Entry {
  _Entry({
    required this.id,
    required this.categoryId,
    required this.userId,
    required this.partnerId,
    required this.partnerConfirmed,
    required this.status,
    required this.fee,
    required this.createdAt,
    required this.seq,
    this.partnerExpiresAt,
    this.adminOverride = false,
  });

  final String id;

  /// Creation order, to break ties between entries made in the same instant.
  final int seq;
  String categoryId;
  final String userId;
  final String? partnerId;
  bool partnerConfirmed;
  RegistrationStatus status;

  /// Locked at registration.
  final int fee;
  final DateTime createdAt;
  DateTime? paidAt;
  DateTime? partnerExpiresAt;
  DateTime? offerExpiresAt;
  int? waitlistPosition;
  final bool adminOverride;
}
