import '../../core/localized_text.dart';
import '../../core/markets.dart';
import '../../domain/admin.dart';
import '../../domain/booking_engine.dart';
import '../../domain/community.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/owner.dart';
import '../../domain/tournaments.dart';
import '../../domain/pricing.dart';
import '../admin_repository.dart';
import '../owner_repository.dart';
import '../repositories.dart';
import '../social.dart';
import '../supabase/mappers.dart'
    show bannerDraftJson, categoryDraftJson, courtDraftJson, isoLocal, sportDraftJson, tournamentDraftJson, venueDraftJson;
import 'sample_competitive.dart';
import 'sample_data.dart';
import 'sample_tournaments.dart';

/// In-memory stand-in for the backend. State lives for one app run.
class SampleBackend
    implements CatalogRepository, BookingRepository, GameRepository, SocialRepository, NotificationRepository {
  /// [meLevels] and [meRatings] are the demo player's sports to start with; a
  /// new player has none.
  SampleBackend({
    required this.utcNow,
    this.meName = '',
    Map<String, int> meLevels = const {},
    Map<String, SportRating> meRatings = const {},
  }) {
    _mySports = SampleSports(levels: meLevels, ratings: meRatings, sportOf: (id) => _sports[id]);
    _engine = BookingEngine(venueById: _venue);
    _seedGames();
    _seedCommunity();
    // Dated from the clock at start-up, like the games.
    _rules;
  }

  /// Current UTC time; injected so tests can fix the clock.
  final DateTime Function() utcNow;
  final String meName;

  late final BookingEngine _engine;

  /// The demo player's ticked sports and ratings.
  late final SampleSports _mySports;

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
  final Map<String, GameRequest> _requests = {};

  /// Reliability events per player; only the demo player starts with any.
  final Map<String, List<ReliabilityEvent>> _reliabilityEvents = {};
  final List<AppNotification> _inbox = [];
  CommunitySettings _settings = const CommunitySettings();
  int _nextId = 1;

  Venue _venue(String id) => _venues[id] ?? (throw StateError('Unknown venue $id'));

  /// Whether the demo player manages [venueId].
  bool _manages(String venueId) => _venues.containsKey(venueId) && (_owners[venueId]?.contains(kMeId) ?? false);

  /// What players see of a venue: only its active courts.
  Venue _public(Venue v) => v.courts.any((c) => _inactiveCourts.contains(c.id))
      ? v.copyWith(
          courts: [
            for (final c in v.courts)
              if (!_inactiveCourts.contains(c.id)) c,
          ],
        )
      : v;

  void _log(
    String action,
    String entity,
    String? entityId, {
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) {
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

  /// Every rating counts for joining, a ticked sport or not (as
  /// `app.effective_rating`); [player] and [profile] show the ticked ones.
  Player get _me => Player(id: kMeId, name: meName, levels: {..._mySports.levels}, ratings: {..._mySports.ratings});

  /// Every sample game sits on a real booking, so its slot shows as taken.
  void _seedGames() {
    for (final seed in kGameSeeds) {
      final venue = _venue(seed.venueId);
      final court = venue.court(seed.courtId);
      final now = _nowAt(venue);
      final start = dateOnly(now).add(Duration(days: seed.daysAhead, hours: seed.hour, minutes: seed.minute));
      final slot = SlotTime(start, start.add(Duration(minutes: court.slotMinutes)));
      final hostId = seed.participantIds.first;
      // A rated sport: the rating range the level range stands for.
      final range = ratingRangeFor(
        _sports[court.sportId]!,
        minRating: null,
        maxRating: null,
        minLevel: seed.minLevel,
        maxLevel: seed.maxLevel,
      );
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
          minRating: range?.min,
          maxRating: range?.max,
          pricePerPlayer: (booking.totalPrice / seed.spots).round(),
          bookingId: booking.id,
        );
      } on BookingException {
        // The venue is closed that day: skip this sample game.
      }
    }
  }

  /// Sample Game Requests, the demo player's reliability history and the
  /// notifications they start with.
  void _seedCommunity() {
    for (final seed in kRequestSeeds) {
      final cityNow = _cityNow(seed.cityId);
      final day = dateOnly(cityNow).add(Duration(days: seed.daysAhead));
      final range = ratingRangeFor(
        _sports[seed.sportId]!,
        minRating: null,
        maxRating: null,
        minLevel: seed.minLevel,
        maxLevel: seed.maxLevel,
      );
      final request = GameRequest(
        id: seed.id,
        sportId: seed.sportId,
        cityId: seed.cityId,
        hostId: seed.hostId,
        hostName: _nameOf(seed.hostId),
        area: seed.area,
        start: day.add(Duration(hours: seed.fromHour)),
        end: day.add(Duration(hours: seed.toHour)),
        playersNeeded: seed.playersNeeded,
        minLevel: seed.minLevel,
        maxLevel: seed.maxLevel,
        minRating: range?.min,
        maxRating: range?.max,
        note: seed.note,
        createdAt: utcNow().subtract(const Duration(hours: 5)),
        interested: [for (final id in seed.interestedIds) _member(id, seed.sportId)],
      );
      _requests[request.id] = request;
    }

    // Three completed games in the last 40 days: a reliable player.
    for (final (i, daysAgo) in [10, 25, 40].indexed) {
      _reliabilityEvents[kMeId] = [
        ...?_reliabilityEvents[kMeId],
        ReliabilityEvent(
          kind: ReliabilityKind.gameCompleted,
          ref: 'seed-${i + 1}',
          at: utcNow().subtract(Duration(days: daysAgo)),
        ),
      ];
    }

    for (final seed in kNotificationSeeds) {
      _inbox.add(
        AppNotification(
          id: seed.id,
          kind: seed.kind,
          category: seed.category,
          payload: seed.payload,
          createdAt: utcNow().subtract(Duration(hours: seed.hoursAgo)),
          read: seed.read,
        ),
      );
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
    for (final b
        in _banners.values.where((b) => b.active && (b.cityId == null || b.cityId == cityId)).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
      BannerItem(id: b.id, title: b.title, subtitle: b.subtitle, url: b.url, colorSeed: _bannerColors[b.id] ?? 0),
  ];

  @override
  Future<List<TournamentItem>> tournaments(String cityId) async => _rules.list(kMeId, cityId);

  // ---- BookingRepository ----

  @override
  Future<List<SlotView>> availability(String venueId, String courtId, DateTime date) async =>
      _engine.availability(venueId, courtId, date, now: _nowAt(_venue(venueId)), userId: kMeId);

  @override
  Future<Booking> hold(String venueId, String courtId, List<SlotTime> slots) async => _engine.hold(
    userId: kMeId,
    venueId: venueId,
    courtId: courtId,
    slots: slots,
    now: _nowAt(_venue(venueId)),
    reliability: _reliability(kMeId),
  );

  @override
  Future<Booking> confirm(String bookingId, {int? players, String? note}) async {
    final booking = _engine.byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    final confirmed = _engine.confirm(bookingId, now: _nowAt(_venue(booking.venueId)), players: players, note: note);
    _notify(kMeId, 'booking_confirmed', 'bookings', _bookingNote(confirmed));
    if (_manages(confirmed.venueId)) _notify(kMeId, 'venue_new_booking', 'venue', _ownerNote(confirmed));
    return confirmed;
  }

  @override
  Future<void> release(String bookingId) async => _engine.release(bookingId);

  @override
  Future<Booking> cancel(String bookingId) async {
    final booking = _engine.byId(bookingId);
    if (booking == null) throw const BookingException(BookingError.notFound);
    final cancelled = _engine.cancel(bookingId, now: _nowAt(_venue(booking.venueId)));
    if (cancelled.lateCancellation) recordReliability(kMeId, ReliabilityKind.lateCancel, bookingId);
    if (_manages(cancelled.venueId)) {
      _notify(kMeId, 'venue_booking_cancelled', 'venue', _ownerNote(cancelled));
    }
    _cancelGamesOn(bookingId, kMeId);
    return cancelled;
  }

  @override
  Future<List<Booking>> myBookings() async => _engine.bookingsOf(kMeId);

  // ---- Reliability (the same rules as the database, plan: Reliability) ----

  Reliability _reliability(String userId) => reliabilityFrom(_reliabilityEvents[userId] ?? const [], now: utcNow());

  void _requireReliable(String userId) {
    if (_reliability(userId).isBlocked) throw const JoinException(JoinError.reliabilityTooLow);
  }

  /// Records a reliability event for [userId]. One event per kind and ref;
  /// paid and no-show replace each other for the same booking.
  void recordReliability(String userId, ReliabilityKind kind, String ref) {
    final events = _reliabilityEvents.putIfAbsent(userId, () => []);
    final opposite = switch (kind) {
      ReliabilityKind.bookingPaid => ReliabilityKind.noShow,
      ReliabilityKind.noShow => ReliabilityKind.bookingPaid,
      _ => null,
    };
    events.removeWhere((e) => e.ref == ref && (e.kind == kind || e.kind == opposite));
    events.add(ReliabilityEvent(kind: kind, ref: ref, at: utcNow()));
  }

  // ---- Inbox ----

  DateTime _lastStamp = DateTime.utc(2000);

  /// Writes to the demo player's inbox, unless they muted the category. Only
  /// the demo player has an inbox in sample mode.
  void _notify(String userId, String kind, String category, Map<String, Object?> payload) {
    if (userId != kMeId || _settings.mutedCategories.contains(category)) return;
    // Strictly increasing, so paging by date never skips or repeats an entry.
    var at = utcNow();
    if (!at.isAfter(_lastStamp)) at = _lastStamp.add(const Duration(milliseconds: 1));
    _lastStamp = at;
    _inbox.add(
      AppNotification(
        id: 'n${_nextId++}',
        kind: kind,
        category: category,
        payload: payload,
        createdAt: at,
        read: false,
      ),
    );
  }

  Map<String, Object?> _gameNote(Game g) => {'game_id': g.id, 'sport_id': g.sportId, 'starts_local': isoLocal(g.start)};

  Map<String, Object?> _requestNote(GameRequest r) => {
    'request_id': r.id,
    'sport_id': r.sportId,
    'starts_local': isoLocal(r.start),
  };

  Map<String, Object?> _bookingNote(Booking b) {
    final venue = _venue(b.venueId);
    return {
      'booking_id': b.id,
      'sport_id': venue.court(b.courtId).sportId,
      'starts_local': isoLocal(b.start),
      'venue_name': {'uz': venue.name.uz, 'ru': venue.name.ru, 'kk': venue.name.kk, 'en': venue.name.en},
    };
  }

  /// What the owners of the venue are told about a booking: the booking's
  /// keys without the venue name, plus the venue, the court (in three
  /// languages) and the player who booked.
  Map<String, Object?> _ownerNote(Booking b) {
    final court = _venue(b.venueId).court(b.courtId).name;
    return {
      ..._bookingNote(b)..remove('venue_name'),
      'venue_id': b.venueId,
      'court_name': {'uz': court.uz, 'ru': court.ru, 'kk': court.kk, 'en': court.en},
      'actor_name': _nameOf(b.userId),
    };
  }

  /// Every participant but [except] hears about the game.
  void _notifyGame(Game g, String kind, {String? except}) {
    for (final id in g.participantIds) {
      if (id != except) _notify(id, kind, 'games', _gameNote(g));
    }
  }

  void _notifyIfFull(Game g, String filler) {
    if (g.isFull) _notifyGame(g, 'game_full', except: filler);
  }

  // ---- Who is who ----

  Player _playerOf(String id) => id == kMeId
      ? _me
      : kSamplePlayers.firstWhere(
          (p) => p.id == id,
          orElse: () => Player(id: id, name: id),
        );

  /// The session name for the demo player, the sample name for anyone else;
  /// empty once deleted, as the backend scrubs it.
  String _nameOf(String id) => _deleted.contains(id) ? '' : (id == kMeId ? meName : _playerOf(id).name);

  /// Sample players whose account was deleted ([markDeleted]).
  final Set<String> _deleted = {};

  /// Marks a sample player's account as deleted, so tests can see how their
  /// history reads to everyone else. (The demo player's own deletion is a
  /// sign-out: this backend goes with the name.)
  void markDeleted(String userId) => _deleted.add(userId);

  bool _exists(String userId) => userId == kMeId || kSamplePlayers.any((p) => p.id == userId);

  GameMember _member(String userId, String sportId) {
    final player = _playerOf(userId);
    // Only rated sports have ratings at all.
    final rating = player.ratings[sportId];
    return GameMember(
      id: userId,
      name: _nameOf(userId),
      level: player.levelFor(sportId),
      rating: rating?.rating,
      provisional: rating?.provisional ?? false,
      reliability: _reliability(userId),
      deleted: _deleted.contains(userId),
    );
  }

  /// Sample players live in Tashkent, like the demo player until they choose a city.
  static const _homeCityId = 'tashkent';

  DateTime _cityNow(String cityId) => venueNow(cityById(cityId), utcNow: utcNow());

  // ---- Games: rules ----

  /// Invite state per game and invited player.
  final Map<String, Map<String, _Invite>> _invites = {};

  final Map<String, List<_JoinAsk>> _joinAsks = {};

  _Invite? _inviteOf(String gameId, String userId) => _invites[gameId]?[userId];

  bool _isInvited(String gameId, String userId) => _inviteOf(gameId, userId) == _Invite.pending;

  _JoinAsk? _pendingAsk(String gameId, String userId) =>
      (_joinAsks[gameId] ?? const []).where((a) => a.userId == userId && a.status == _AskStatus.pending).firstOrNull;

  /// The host removed [userId] from the game and has not invited them since.
  bool _removed(String gameId, String userId) =>
      (_joinAsks[gameId] ?? const []).any((a) => a.userId == userId && a.status == _AskStatus.removed);

  bool _canSee(String viewer, Game g) =>
      g.visibility == GameVisibility.public ||
      g.hostId == viewer ||
      g.participantIds.contains(viewer) ||
      _inviteOf(g.id, viewer) != null ||
      (_joinAsks[g.id] ?? const []).any((a) => a.userId == viewer);

  bool _started(Game g) => !g.start.isAfter(_cityNow(g.cityId));

  /// An open game that has not started and that [viewer] may see; anything
  /// else does not exist for them.
  Game _live(String id, {String? viewer}) {
    final g = _games[id];
    if (g == null || g.cancelled || _started(g) || (viewer != null && !_canSee(viewer, g))) {
      throw const JoinException(JoinError.notFound);
    }
    return g;
  }

  /// A game of [userId]'s own that has not started.
  Game _hosted(String id, String userId) {
    final g = _games[id];
    if (g == null || g.hostId != userId || g.cancelled || _started(g)) throw const JoinException(JoinError.notFound);
    return g;
  }

  /// The game as [viewer] sees it: who is in, their status, and, for the
  /// host, the requests waiting.
  Game _view(Game g, String viewer) {
    final status = g.hostId == viewer
        ? MyGameStatus.host
        : g.participantIds.contains(viewer)
        ? MyGameStatus.participant
        : _isInvited(g.id, viewer)
        ? MyGameStatus.invited
        : _pendingAsk(g.id, viewer) != null
        ? MyGameStatus.requested
        : null;
    return g.copyWith(
      participants: [for (final id in g.participantIds) _member(id, g.sportId)],
      joinRequests: g.hostId == viewer
          ? [
              for (final a in _joinAsks[g.id] ?? const <_JoinAsk>[])
                if (a.status == _AskStatus.pending)
                  JoinRequest(id: a.id, member: _member(a.userId, g.sportId), createdAt: a.createdAt),
            ]
          : const [],
      myStatus: status,
      clearMyStatus: status == null,
      myRequestId: _pendingAsk(g.id, viewer)?.id,
      clearMyRequestId: _pendingAsk(g.id, viewer) == null,
    );
  }

  /// The player became a participant: their invite is accepted and any open
  /// request is closed.
  void _closePending(String gameId, String userId) {
    if (_invites[gameId]?[userId] == _Invite.pending) _invites[gameId]![userId] = _Invite.accepted;
    _pendingAsk(gameId, userId)?.status = _AskStatus.approved;
  }

  /// The people in the game took a new player: [joined] is the game after.
  Game _save(Game g) => _games[g.id] = g;

  /// Acts as [userId]: sample players use these to join, ask and be invited.
  Future<Game> joinAs(String userId, String id) async {
    _requireReliable(userId);
    final g = _live(id);
    final invited = _isInvited(id, userId);
    if (_removed(id, userId)) throw const JoinException(JoinError.notFound);
    final joined = _save(joinGame(g, _playerOf(userId), invited: invited));
    _closePending(id, userId);
    _notify(g.hostId, 'game_joined', 'games', {..._gameNote(g), 'actor_name': _nameOf(userId)});
    _notifyIfFull(joined, userId);
    return _view(joined, userId);
  }

  Future<Game> leaveAs(String userId, String id) async {
    final g = _games[id];
    if (g == null) throw const JoinException(JoinError.notFound);
    final left = _save(leaveGame(g, userId));
    if (!g.cancelled && g.end.isAfter(_cityNow(g.cityId))) {
      if (g.start.difference(_cityNow(g.cityId)) < BookingEngine.freeCancelWindow) {
        recordReliability(userId, ReliabilityKind.lateCancel, id);
      }
      _notify(g.hostId, 'game_left', 'games', {..._gameNote(g), 'actor_name': _nameOf(userId)});
    }
    return _view(left, userId);
  }

  Future<Game> requestToJoinAs(String userId, String id) async {
    _requireReliable(userId);
    final g = _live(id, viewer: userId);
    if (_removed(id, userId)) throw const JoinException(JoinError.notFound);
    if (g.participantIds.contains(userId)) throw const JoinException(JoinError.alreadyJoined);
    if (_pendingAsk(id, userId) != null) throw const JoinException(JoinError.alreadyRequested);
    if (g.isFull) throw const JoinException(JoinError.full);
    final ask = _JoinAsk(id: 'jr${_nextId++}', gameId: id, userId: userId, createdAt: utcNow());
    (_joinAsks[id] ??= []).add(ask);
    _notify(g.hostId, 'join_request', 'games', {..._gameNote(g), 'request_id': ask.id, 'actor_name': _nameOf(userId)});
    return _view(g, userId);
  }

  Future<Game> inviteAs(String userId, String id, String inviteeId) async {
    final g = _hosted(id, userId);
    if (!_exists(inviteeId)) throw const JoinException(JoinError.notFound);
    if (g.participantIds.contains(inviteeId)) throw const JoinException(JoinError.alreadyJoined);
    // Inviting a player the host removed earlier lets them back in.
    _joinAsks[id]?.removeWhere((a) => a.userId == inviteeId && a.status == _AskStatus.removed);
    final previous = _inviteOf(id, inviteeId);
    (_invites[id] ??= {})[inviteeId] = _Invite.pending;
    if (previous != _Invite.pending) {
      _notify(inviteeId, 'game_invite', 'invites', {..._gameNote(g), 'actor_name': _nameOf(userId)});
    }
    return _view(g, userId);
  }

  /// A new game hosted by [userId]: from their own booking for a bookable
  /// sport, at a venue or meeting point for a place-only one.
  Future<Game> createAs(String userId, GameDraft draft) async {
    _requireReliable(userId);
    if (draft.spots < 2 ||
        draft.spots > 30 ||
        draft.minLevel < 1 ||
        draft.maxLevel > 5 ||
        draft.minLevel > draft.maxLevel ||
        (draft.distanceKm != null && draft.distanceKm! <= 0)) {
      throw const JoinException(JoinError.invalidArgument);
    }
    final sport = _sports[draft.sportId];
    if (sport == null || !sport.active) throw const JoinException(JoinError.notFound);
    // A rated sport keeps a rating range and derives the levels from it.
    final range = ratingRangeFor(
      sport,
      minRating: draft.minRating,
      maxRating: draft.maxRating,
      minLevel: draft.minLevel,
      maxLevel: draft.maxLevel,
    );

    final String cityId;
    final GameKind kind;
    final DateTime start;
    final DateTime end;
    String? venueId;
    String? bookingId;
    String? meeting;
    int? price;
    if (sport.sport.bookable) {
      final booking = draft.bookingId == null ? null : _engine.byId(draft.bookingId!);
      if (booking == null ||
          booking.userId != userId ||
          booking.source != BookingSource.app ||
          booking.status != BookingStatus.confirmed ||
          !booking.start.isAfter(_nowAt(_venue(booking.venueId))) ||
          _venue(booking.venueId).court(booking.courtId).sportId != sport.sport.id) {
        throw const JoinException(JoinError.bookingNotUsable);
      }
      if (_games.values.any((g) => g.bookingId == booking.id && !g.cancelled)) {
        throw const JoinException(JoinError.gameExists);
      }
      kind = GameKind.booked;
      cityId = _venue(booking.venueId).cityId;
      venueId = booking.venueId;
      bookingId = booking.id;
      start = booking.start;
      end = booking.end;
      price = _perPlayer(booking.totalPrice, draft.spots);
    } else {
      if (draft.venueId != null) {
        if (!_venues.containsKey(draft.venueId) || _inactiveVenues.contains(draft.venueId)) {
          throw const JoinException(JoinError.notFound);
        }
        kind = GameKind.place;
        venueId = draft.venueId;
        cityId = _venue(draft.venueId!).cityId;
      } else {
        meeting = _blank(draft.meetingPoint);
        final lat = draft.meetingLat;
        final lng = draft.meetingLng;
        if (meeting == null ||
            (lat == null) != (lng == null) ||
            (lat != null && (lat < -90 || lat > 90)) ||
            (lng != null && (lng < -180 || lng > 180))) {
          throw const JoinException(JoinError.invalidArgument);
        }
        kind = GameKind.mapPoint;
        cityId = _homeCityId;
      }
      _checkWindow(cityId, draft.start, draft.end);
      start = draft.start!;
      end = draft.end!;
    }

    final game = Game(
      id: 'gm${_nextId++}',
      sportId: sport.sport.id,
      cityId: cityId,
      venueId: venueId,
      hostId: userId,
      kind: kind,
      visibility: draft.visibility,
      start: start,
      end: end,
      spots: draft.spots,
      participantIds: [userId],
      minLevel: range == null ? draft.minLevel : levelOfRating(range.min),
      maxLevel: range == null ? draft.maxLevel : levelOfRating(range.max),
      minRating: range?.min,
      maxRating: range?.max,
      pricePerPlayer: price,
      bookingId: bookingId,
      note: _blank(draft.note),
      meetingPoint: meeting,
      meetingLat: meeting == null ? null : draft.meetingLat,
      meetingLng: meeting == null ? null : draft.meetingLng,
      distanceKm: draft.distanceKm,
      pace: _blank(draft.pace),
    );
    return _view(_save(game), userId);
  }

  static String? _blank(String? text) {
    final t = text?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// The share each player pays: the court price over the spots, rounded up.
  static int _perPlayer(int total, int spots) => (total + spots - 1) ~/ spots;

  /// The window of a place-only game or a Game Request: in the future, within
  /// 14 days, at most 12 hours long.
  void _checkWindow(String cityId, DateTime? start, DateTime? end) {
    if (start == null || end == null) throw const JoinException(JoinError.invalidArgument);
    final now = _cityNow(cityId);
    if (!start.isAfter(now)) throw const JoinException(JoinError.inPast);
    if (dateOnly(start).difference(dateOnly(now)).inDays > BookingEngine.maxDaysAhead) {
      throw const JoinException(JoinError.tooFarAhead);
    }
    if (!end.isAfter(start) || end.difference(start) > const Duration(hours: 12)) {
      throw const JoinException(JoinError.invalidArgument);
    }
  }

  /// The games on a booking that is no longer happening are cancelled and
  /// their players told (except [actor]). Nobody's reliability changes.
  void _cancelGamesOn(String bookingId, String actor) {
    for (final g in _games.values.toList()) {
      if (g.bookingId != bookingId || g.cancelled) continue;
      final cancelled = _save(g.copyWith(cancelled: true));
      _notifyGame(cancelled, 'game_cancelled', except: actor);
    }
  }

  // ---- GameRepository ----

  @override
  Future<List<Game>> games(String cityId) async {
    bool listed(Game g) {
      if (g.cancelled || _started(g)) return false;
      final mine = g.hostId == kMeId || g.participantIds.contains(kMeId) || _isInvited(g.id, kMeId);
      // Invite-only games come in only as `mine`, never through the city.
      final inCity =
          g.cityId == cityId &&
          g.visibility == GameVisibility.public &&
          (!g.isFull || g.participantIds.contains(kMeId));
      return inCity || mine;
    }

    return [
      for (final g in _games.values.where(listed).toList()..sort((a, b) => a.start.compareTo(b.start))) _view(g, kMeId),
    ];
  }

  @override
  Future<Game> game(String id) async {
    final g = _games[id];
    if (g == null || !_canSee(kMeId, g)) throw StateError('Unknown game $id');
    return _view(g, kMeId);
  }

  @override
  Future<Game> join(String id) => joinAs(kMeId, id);

  @override
  Future<Game> leave(String id) => leaveAs(kMeId, id);

  @override
  Future<Player> player(String id) async {
    final p = _playerOf(id);
    // As the backend returns it: a deleted account has no name or levels left,
    // and a rating shows only for a sport that is ticked.
    if (_deleted.contains(id)) return Player(id: p.id, name: '', deleted: true);
    return Player(id: p.id, name: p.name, levels: p.levels, ratings: profileOf(p).ratings);
  }

  @override
  Future<Game> create(GameDraft draft) => createAs(kMeId, draft);

  @override
  Future<Game> requestToJoin(String gameId) => requestToJoinAs(kMeId, gameId);

  @override
  Future<Game> withdrawRequest(String requestId) async {
    final ask = [
      for (final asks in _joinAsks.values) ...asks,
    ].where((a) => a.id == requestId && a.userId == kMeId && a.status == _AskStatus.pending).firstOrNull;
    if (ask == null) throw const JoinException(JoinError.notFound);
    ask.status = _AskStatus.withdrawn;
    return _view(_games[ask.gameId]!, kMeId);
  }

  @override
  Future<Game> decideRequest(String requestId, {required bool approve}) async {
    final ask = [for (final asks in _joinAsks.values) ...asks].where((a) => a.id == requestId).firstOrNull;
    final g = ask == null ? null : _games[ask.gameId];
    if (ask == null || g == null || g.hostId != kMeId || ask.status != _AskStatus.pending) {
      throw const JoinException(JoinError.notFound);
    }
    if (!approve) {
      ask.status = _AskStatus.declined;
      _notify(ask.userId, 'join_declined', 'games', _gameNote(g));
      return _view(g, kMeId);
    }
    if (g.cancelled || _started(g)) throw const JoinException(JoinError.notFound);
    if (g.participantIds.contains(ask.userId)) throw const JoinException(JoinError.alreadyJoined);
    if (g.isFull) throw const JoinException(JoinError.full);
    // The requester may have been blocked since asking.
    _requireReliable(ask.userId);
    final joined = _save(g.copyWith(participantIds: [...g.participantIds, ask.userId]));
    _closePending(g.id, ask.userId);
    _notify(ask.userId, 'join_approved', 'games', _gameNote(g));
    _notifyIfFull(joined, ask.userId);
    return _view(joined, kMeId);
  }

  @override
  Future<Game> invite(String gameId, String userId) => inviteAs(kMeId, gameId, userId);

  @override
  Future<Game> declineInvite(String gameId) async {
    if (!_isInvited(gameId, kMeId)) throw const JoinException(JoinError.notFound);
    _invites[gameId]![kMeId] = _Invite.declined;
    return _view(_games[gameId]!, kMeId);
  }

  @override
  Future<Game> removeParticipant(String gameId, String userId) async {
    final g = _hosted(gameId, kMeId);
    if (userId == kMeId) throw const JoinException(JoinError.hostCannotLeave);
    if (!g.participantIds.contains(userId)) throw const JoinException(JoinError.notParticipant);
    final removed = _save(leaveGame(g, userId));
    if (!_removed(gameId, userId)) {
      (_joinAsks[gameId] ??= []).add(
        _JoinAsk(id: 'jr${_nextId++}', gameId: gameId, userId: userId, createdAt: utcNow())..status = _AskStatus.removed,
      );
    }
    _notify(userId, 'game_removed', 'games', _gameNote(g));
    return _view(removed, kMeId);
  }

  @override
  Future<Game> updateGame(String gameId, {String? note, required int spots}) async {
    final g = _hosted(gameId, kMeId);
    if (spots < 2 || spots > 30 || spots < g.participantIds.length) {
      throw const JoinException(JoinError.invalidArgument);
    }
    final newNote = note == null ? g.note : _blank(note);
    if (newNote == g.note && spots == g.spots) return _view(g, kMeId);
    final booking = g.bookingId == null ? null : _engine.byId(g.bookingId!);
    final updated = _save(
      g.copyWith(
        spots: spots,
        note: newNote,
        clearNote: newNote == null,
        pricePerPlayer: booking == null ? null : _perPlayer(booking.totalPrice, spots),
      ),
    );
    _notifyGame(updated, 'game_changed', except: kMeId);
    return _view(updated, kMeId);
  }

  @override
  Future<Game> cancelGame(String gameId, {required bool cancelBooking}) async {
    final g = _games[gameId];
    if (g == null || g.hostId != kMeId || g.cancelled) throw const JoinException(JoinError.notFound);
    if (_started(g)) throw const JoinException(JoinError.notCancellable);
    final cancelled = _save(g.copyWith(cancelled: true));
    _notifyGame(cancelled, 'game_cancelled', except: kMeId);
    final booking = g.bookingId == null ? null : _engine.byId(g.bookingId!);
    if (cancelBooking &&
        booking != null &&
        booking.userId == kMeId &&
        booking.source == BookingSource.app &&
        booking.status == BookingStatus.confirmed &&
        booking.start.isAfter(_nowAt(_venue(booking.venueId)))) {
      await cancel(booking.id);
    }
    return _view(cancelled, kMeId);
  }

  // ---- Game Requests ----

  GameRequest _requestView(GameRequest r, String viewer) {
    final status = r.hostId == viewer
        ? MyRequestStatus.host
        : r.interested.any((m) => m.id == viewer)
        ? MyRequestStatus.interested
        : null;
    return r.copyWith(
      interested: [for (final m in r.interested) _member(m.id, r.sportId)],
      myStatus: status,
      clearMyStatus: status == null,
    );
  }

  /// An open request whose window has not ended, which [mustHost] limits to
  /// the poster's own.
  GameRequest _openRequest(String id, {String? host}) {
    final r = _requests[id];
    if (r == null || !r.isOpen || !r.end.isAfter(_cityNow(r.cityId)) || (host != null && r.hostId != host)) {
      throw const JoinException(JoinError.notFound);
    }
    return r;
  }

  GameRequest _saveRequest(GameRequest r) => _requests[r.id] = r;

  Future<GameRequest> createRequestAs(String userId, GameRequestDraft draft) async {
    _requireReliable(userId);
    if (draft.playersNeeded < 1 ||
        draft.playersNeeded > 29 ||
        draft.minLevel < 1 ||
        draft.maxLevel > 5 ||
        draft.minLevel > draft.maxLevel) {
      throw const JoinException(JoinError.invalidArgument);
    }
    final sport = _sports[draft.sportId];
    if (sport == null || !sport.active) throw const JoinException(JoinError.notFound);
    final range = ratingRangeFor(
      sport,
      minRating: draft.minRating,
      maxRating: draft.maxRating,
      minLevel: draft.minLevel,
      maxLevel: draft.maxLevel,
    );
    if (draft.venueId != null && (!_venues.containsKey(draft.venueId) || _inactiveVenues.contains(draft.venueId))) {
      throw const JoinException(JoinError.notFound);
    }
    final cityId = draft.venueId == null ? _homeCityId : _venue(draft.venueId!).cityId;
    _checkWindow(cityId, draft.start, draft.end);
    return _requestView(
      _saveRequest(
        GameRequest(
          id: 'rqn${_nextId++}',
          sportId: draft.sportId,
          cityId: cityId,
          hostId: userId,
          hostName: _nameOf(userId),
          venueId: draft.venueId,
          area: _blank(draft.area),
          start: draft.start,
          end: draft.end,
          playersNeeded: draft.playersNeeded,
          minLevel: range == null ? draft.minLevel : levelOfRating(range.min),
          maxLevel: range == null ? draft.maxLevel : levelOfRating(range.max),
          minRating: range?.min,
          maxRating: range?.max,
          note: _blank(draft.note),
          createdAt: utcNow(),
        ),
      ),
      userId,
    );
  }

  /// "I'm in", as [userId].
  Future<GameRequest> interestAs(String userId, String id) async {
    _requireReliable(userId);
    final r = _openRequest(id);
    if (r.hostId == userId) throw const JoinException(JoinError.invalidArgument);
    if (r.interested.any((m) => m.id == userId)) throw const JoinException(JoinError.alreadyJoined);
    final updated = _saveRequest(r.copyWith(interested: [...r.interested, _member(userId, r.sportId)]));
    _notify(r.hostId, 'request_interest', 'requests', {..._requestNote(r), 'actor_name': _nameOf(userId)});
    return _requestView(updated, userId);
  }

  @override
  Future<List<GameRequest>> requests(String cityId) async => [
    for (final r
        in _requests.values
            .where((r) => r.isOpen && r.end.isAfter(_cityNow(r.cityId)) && (r.cityId == cityId || r.hostId == kMeId))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start)))
      _requestView(r, kMeId),
  ];

  @override
  Future<GameRequest> request(String id) async {
    final r = _requests[id];
    if (r == null) throw StateError('Unknown request $id');
    return _requestView(r, kMeId);
  }

  @override
  Future<GameRequest> createRequest(GameRequestDraft draft) => createRequestAs(kMeId, draft);

  @override
  Future<GameRequest> imIn(String id) => interestAs(kMeId, id);

  @override
  Future<GameRequest> withdrawInterest(String id) async {
    final r = _requests[id];
    if (r == null || !r.isOpen || !r.interested.any((m) => m.id == kMeId)) {
      throw const JoinException(JoinError.notFound);
    }
    return _requestView(
      _saveRequest(
        r.copyWith(
          interested: [
            for (final m in r.interested)
              if (m.id != kMeId) m,
          ],
        ),
      ),
      kMeId,
    );
  }

  @override
  Future<GameRequest> removeInterested(String id, String userId) async {
    final r = _openRequest(id, host: kMeId);
    if (!r.interested.any((m) => m.id == userId)) throw const JoinException(JoinError.notFound);
    return _requestView(
      _saveRequest(
        r.copyWith(
          interested: [
            for (final m in r.interested)
              if (m.id != userId) m,
          ],
        ),
      ),
      kMeId,
    );
  }

  @override
  Future<GameRequest> cancelRequest(String id) async {
    final r = _openRequest(id, host: kMeId);
    return _requestView(_saveRequest(r.copyWith(status: GameRequestStatus.cancelled)), kMeId);
  }

  @override
  Future<Game> convertRequest(String id, PlacePick place) async {
    final r = _openRequest(id, host: kMeId);
    final hasPlace = place.bookingId != null || place.venueId != null || _blank(place.meetingPoint) != null;
    final game = await createAs(
      kMeId,
      GameDraft(
        sportId: r.sportId,
        spots: place.spots ?? 1 + r.playersNeeded,
        minLevel: r.minLevel,
        maxLevel: r.maxLevel,
        minRating: r.minRating,
        maxRating: r.maxRating,
        visibility: place.visibility ?? GameVisibility.public,
        note: r.note,
        pace: place.pace,
        distanceKm: place.distanceKm,
        bookingId: place.bookingId,
        venueId: place.venueId ?? (hasPlace ? null : r.venueId),
        meetingPoint: place.meetingPoint,
        meetingLat: place.meetingLat,
        meetingLng: place.meetingLng,
        start: place.start ?? r.start,
        end: place.end ?? r.end,
      ),
    );
    var current = _games[game.id]!;
    for (final member in r.interested) {
      var added = false;
      // A player blocked since tapping is told, but not added.
      if (!current.isFull && !_reliability(member.id).isBlocked && !current.participantIds.contains(member.id)) {
        current = _save(current.copyWith(participantIds: [...current.participantIds, member.id]));
        added = true;
      }
      _notify(member.id, 'request_converted', 'requests', {..._requestNote(r), 'game_id': game.id, 'added': added});
    }
    _saveRequest(r.copyWith(status: GameRequestStatus.converted, gameId: game.id));
    return _view(current, kMeId);
  }

  // ---- SocialRepository ----

  @override
  Future<List<Team>> teams(String cityId) async => kSampleTeams.where((t) => t.cityId == cityId).toList();

  @override
  Future<List<PlayerProfile>> players(
    String cityId, {
    String? sportId,
    int minLevel = 1,
    int maxLevel = 5,
    double? minRating,
    double? maxRating,
    String? query,
  }) async {
    // As `list_players_rated`: a rating bound only in a rated sport.
    final byRating = sportId != null && (minRating != null || maxRating != null);
    if (byRating && !(_sports[sportId]?.sport.competitiveRating ?? false)) {
      throw const JoinException(JoinError.invalidArgument);
    }
    return searchPlayers(
      kSamplePlayers,
      sportId: sportId,
      minLevel: minLevel,
      maxLevel: maxLevel,
      minRating: minRating,
      maxRating: maxRating,
      query: query,
      reliabilityOf: _reliability,
    );
  }

  @override
  Future<PlayerProfile> profile(String userId) async => profileOf(
    // As the backend returns it: a deleted account has no name or levels.
    await player(userId),
    reliability: _reliability(userId),
    gamesPlayed: (_reliabilityEvents[userId] ?? const []).where((e) => e.kind == ReliabilityKind.gameCompleted).length,
  );

  @override
  Future<List<MySport>> mySports() async => _mySports.mySports();

  @override
  Future<List<MySport>> setSport(String sportId, {int? level, List<int>? answers}) async {
    _mySports.set(sportId, level: level, answers: answers);
    return _mySports.mySports();
  }

  @override
  Future<List<MySport>> removeSport(String sportId) async {
    _mySports.remove(sportId);
    return _mySports.mySports();
  }

  // ---- NotificationRepository ----

  @override
  Future<List<AppNotification>> inbox({DateTime? before, String? beforeId}) async {
    // Newest first, ties by id, as the database pages: (createdAt, id) < (before, beforeId).
    int newestFirst(AppNotification a, AppNotification b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    }

    bool older(AppNotification n) =>
        before == null ||
        n.createdAt.isBefore(before) ||
        (beforeId != null && n.createdAt.isAtSameMomentAs(before) && n.id.compareTo(beforeId) < 0);

    final entries = [
      for (final n in _inbox)
        if (older(n)) n,
    ]..sort(newestFirst);
    return entries.take(50).toList();
  }

  @override
  Future<int> unreadCount() async => _inbox.where((n) => !n.read).length;

  @override
  Future<void> markRead([List<String>? ids]) async {
    for (var i = 0; i < _inbox.length; i++) {
      if (ids == null || ids.contains(_inbox[i].id)) _inbox[i] = _inbox[i].copyWith(read: true);
    }
  }

  @override
  Future<CommunitySettings> settings() async => CommunitySettings(
    mutedCategories: {..._settings.mutedCategories},
    hiddenFromSearch: _settings.hiddenFromSearch,
    reliability: _reliability(kMeId),
  );

  @override
  Future<void> saveSettings(CommunitySettings settings) async {
    if (!settings.mutedCategories.every(kNotificationCategories.contains)) {
      throw const JoinException(JoinError.invalidArgument);
    }
    _settings = CommunitySettings(
      mutedCategories: {...settings.mutedCategories},
      hiddenFromSearch: settings.hiddenFromSearch,
    );
  }

  // ---- Tournaments ----

  late final SampleTournaments _rules = SampleTournaments(
    utcNow: utcNow,
    cityNow: _cityNow,
    venueCity: (id) => _venues[id]?.cityId,
    venueName: (id) => _venue(id).name,
    knownSport: _sports.containsKey,
    nameOf: _nameOf,
    levelOf: (userId, sportId) => _playerOf(userId).levelFor(sportId),
    userExists: _exists,
    isBlocked: (userId) => _reliability(userId).isBlocked,
    notify: _notify,
    isDeleted: _deleted.contains,
  );

  /// The tournament calls for any player, so tests can fill a category, have a
  /// partner accept or a waitlisted player claim an offer. The demo player's
  /// own go through [tournament].
  Future<Registration> registerAs(String userId, String categoryId, {String? partnerId}) async =>
      _rules.register(userId, categoryId, partnerId);

  Future<Registration> respondPartnerAs(String userId, String registrationId, {required bool accept}) async =>
      _rules.respondPartner(userId, registrationId, accept: accept);

  Future<Registration> cancelRegistrationAs(String userId, String registrationId) async =>
      _rules.cancel(userId, registrationId);

  Future<Registration> joinWaitlistAs(String userId, String categoryId, {String? partnerId}) async =>
      _rules.joinWaitlist(userId, categoryId, partnerId);

  Future<Registration> claimOfferAs(String userId, String registrationId) async =>
      _rules.claimOffer(userId, registrationId);

  /// The demo player's tournament operations. A separate object, because
  /// [TournamentRepository.cancel] clashes with [BookingRepository.cancel].
  late final TournamentRepository tournament = _SampleTournamentRepository(this);

  // ---- Booking hooks the owner repository calls ----

  /// A venue cancelled [booking]: the player hears, the games on it are off.
  void _venueCancelled(Booking booking) {
    if (booking.source == BookingSource.app) {
      _notify(booking.userId, 'booking_cancelled_by_venue', 'bookings', _bookingNote(booking));
    }
    _cancelGamesOn(booking.id, kMeId);
  }

  /// An owner marked an app booking paid or no-show; walk-ins count for nothing.
  void _marked(Booking booking, BookingOutcome outcome) {
    if (booking.source != BookingSource.app) return;
    recordReliability(
      booking.userId,
      outcome == BookingOutcome.paid ? ReliabilityKind.bookingPaid : ReliabilityKind.noShow,
      booking.id,
    );
  }

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

  OwnerBooking _view(Booking booking) =>
      OwnerBooking.fromBooking(booking, nameOf: _backend._nameOf, isDeleted: _backend._deleted.contains);

  @override
  Future<List<Venue>> myVenues() async => [
    for (final v in _backend._venues.values)
      if (_backend._manages(v.id) && !_backend._inactiveVenues.contains(v.id)) _backend._public(v),
  ];

  @override
  Future<OwnerCalendar> calendar(String venueId, String courtId, DateTime from, int days) async {
    _owned(venueId);
    return _engine.ownerCalendar(
      venueId,
      courtId,
      from,
      days,
      now: _now(venueId),
      nameOf: _backend._nameOf,
      isDeleted: _backend._deleted.contains,
    );
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
    final cancelled = _engine.cancelByVenue(bookingId, now: _now(booking.venueId));
    _backend._venueCancelled(cancelled);
    return _logged('owner_cancel_booking', booking, cancelled);
  }

  @override
  Future<OwnerBooking> mark(String bookingId, BookingOutcome outcome) async {
    final booking = _ownedBooking(bookingId);
    final marked = _engine.mark(bookingId, outcome, now: _now(booking.venueId));
    _backend._marked(marked, outcome);
    return _logged('owner_mark_booking', booking, marked);
  }

  // ---- Settings: the same validation as the database functions ----

  static void _checkHours(WeekHours hours, {required bool allDays}) {
    final valid =
        hours.keys.every((d) => d >= 1 && d <= 7) &&
        (!allDays || hours.length == 7) &&
        hours.values.every(
          (h) => h == null || (h.openMinute >= 0 && h.openMinute < h.closeMinute && h.closeMinute <= 1440),
        );
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
            {
              'weekdays': r.weekdays.toList()..sort(),
              'from_minute': r.fromMinute,
              'to_minute': r.toMinute,
              'price': r.price,
            },
        ],
      },
    );
  }

  @override
  Future<OwnerDashboard> dashboard(
    String venueId, {
    String? courtId,
    required DateTime from,
    required DateTime to,
  }) async {
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
  static bool _named(LocalizedText t) => !_blank(t.uz) || !_blank(t.ru) || !_blank(t.kk) || !_blank(t.en);
  static bool _fits(LocalizedText t, int max) => [t.uz, t.ru, t.kk, t.en].every((s) => s == null || s.trim().length <= max);
  static bool _knownCity(String id) => kCities.any((c) => c.id == id);

  /// Blank languages become null, as the database stores them.
  static LocalizedText _clean(LocalizedText t) {
    String? c(String? s) => _blank(s) ? null : s!.trim();
    return LocalizedText(uz: c(t.uz), ru: c(t.ru), kk: c(t.kk), en: c(t.en));
  }

  String _ownerName(String userId) => userId == kMeId
      ? _b.meName
      : kSamplePlayers
            .firstWhere(
              (p) => p.id == userId,
              orElse: () => Player(id: userId, name: userId),
            )
            .name;

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
    inactiveCourtIds: {
      for (final c in v.courts)
        if (_b._inactiveCourts.contains(c.id)) c.id,
    },
    owners: [for (final id in _b._owners[v.id] ?? const <String>{}) OwnerRef(userId: id, name: _ownerName(id))],
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
      hours:
          existing?.hours ??
          weekHours(weekdays: const DayHours.hm(8, 0, 22, 0), weekend: const DayHours.hm(8, 0, 22, 0)),
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
    // Games and Game Requests hold on to their venue too.
    if (_b._engine.hasBookings(venueId: venueId) ||
        _b._games.values.any((g) => g.venueId == venueId) ||
        _b._requests.values.any((r) => r.venueId == venueId)) {
      throw const BookingException(BookingError.hasBookings);
    }
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
      name: LocalizedText(
        uz: two(original.name.uz),
        ru: two(original.name.ru),
        kk: two(original.name.kk),
        en: two(original.name.en),
      ),
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
    _b._venues[venue.id] = venue.copyWith(
      courts: [
        for (final c in venue.courts)
          if (c.id != courtId) c,
      ],
    );
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

  // ---- Tournaments ----

  SampleTournaments get _t => _b._rules;

  static Map<String, dynamic> _registrationLog(AdminRegistration r) => {
    'registration_id': r.registration.id,
    'category_id': r.registration.categoryId,
    'status': r.registration.status.name,
    'paid': r.registration.paid,
  };

  @override
  Future<List<AdminTournament>> tournaments() async => _t.adminTournaments();

  @override
  Future<String> saveTournament(TournamentDraft draft) async {
    final existing = draft.id == null ? null : _t.adminTournaments().where((t) => t.tournament.id == draft.id).firstOrNull;
    final id = _t.saveTournament(draft);
    _b._log(
      draft.id == null ? 'create_tournament' : 'update_tournament',
      'tournament',
      id,
      before: existing == null ? null : tournamentDraftJson(TournamentDraft.from(existing.tournament)),
      after: tournamentDraftJson(draft),
    );
    return id;
  }

  @override
  Future<String> saveCategory(CategoryDraft draft) async {
    final id = _t.saveCategory(draft);
    _b._log(
      draft.id == null ? 'create_category' : 'update_category',
      'tournament_category',
      id,
      after: categoryDraftJson(draft),
    );
    return id;
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    _t.deleteCategory(categoryId);
    _b._log('delete_category', 'tournament_category', categoryId);
  }

  @override
  Future<List<AdminRegistration>> registrations(String tournamentId) async => _t.registrations(tournamentId);

  @override
  Future<AdminRegistration> setPaid(String registrationId, bool paid) async {
    final r = _t.setPaid(registrationId, paid);
    _b._log('set_registration_paid', 'tournament_registration', registrationId, after: _registrationLog(r));
    return r;
  }

  @override
  Future<AdminRegistration> removeRegistration(String registrationId) async {
    final r = _t.removeRegistration(registrationId);
    _b._log('remove_registration', 'tournament_registration', registrationId, after: _registrationLog(r));
    return r;
  }

  @override
  Future<AdminRegistration> moveRegistration(String registrationId, String categoryId) async {
    final r = _t.moveRegistration(registrationId, categoryId);
    _b._log('move_registration', 'tournament_registration', registrationId, after: _registrationLog(r));
    return r;
  }

  @override
  Future<AdminRegistration> addRegistration(String categoryId, String userId, {String? partnerId}) async {
    final r = _t.addRegistration(categoryId, userId, partnerId);
    _b._log('add_registration', 'tournament_registration', r.registration.id, after: _registrationLog(r));
    return r;
  }

  @override
  Future<int> offerNext(String categoryId) async {
    final offered = _t.offerNext(categoryId);
    _b._log('offer_next', 'tournament_category', categoryId, after: {'offered': offered});
    return offered;
  }

  @override
  Future<AdminDashboard> dashboard({String? cityId, required DateTime from, required DateTime to}) async {
    if (cityId != null && !_knownCity(cityId)) throw const TournamentException(TournamentError.notFound);
    final first = dateOnly(from);
    final last = dateOnly(to);
    final days = last.difference(first).inDays + 1;
    if (days < 1 || days > 366) throw const TournamentException(TournamentError.invalidArgument);

    // Venue revenue and bookings come from the owner dashboard, whose limit is
    // shorter than this one's: ask in windows.
    const window = BookingEngine.maxDashboardDays;
    final venues = <Currency, int>{};
    var bookings = 0;
    for (final venue in _b._venues.values) {
      if (cityId != null && venue.cityId != cityId) continue;
      final currency = cityById(venue.cityId).currency;
      for (var day = first; !day.isAfter(last); day = day.add(const Duration(days: window))) {
        final end = day.add(const Duration(days: window - 1));
        final stats = _b._engine.ownerDashboard(venue.id, from: day, to: end.isAfter(last) ? last : end);
        venues[currency] = (venues[currency] ?? 0) + stats.revenuePaid;
        bookings += stats.bookingsApp + stats.bookingsWalkIn;
      }
    }
    final tournaments = _t.paidRevenue(cityId, first, last);
    final currencies = {
      ...tournaments.keys,
      for (final e in venues.entries)
        if (e.value > 0) e.key,
    }.toList()..sort((a, b) => a.name.compareTo(b.name));

    // The sample players live in Tashkent, and the demo player joined today.
    final everyone = kSamplePlayers.length + 1;
    final users = cityId == null || cityId == SampleBackend._homeCityId
        ? UserStats(total: everyone, active30d: everyone, newToday: 1, new7d: 1, newMonth: 1)
        : const UserStats();
    return AdminDashboard(
      users: users,
      revenue: [
        for (final c in currencies) CurrencyRevenue(currency: c, venues: venues[c] ?? 0, tournaments: tournaments[c] ?? 0),
      ],
      counts: ActivityCounts(
        bookings: bookings,
        // Sample games have no creation time: those played in the period.
        games: _b._games.values
            .where(
              (g) =>
                  (cityId == null || g.cityId == cityId) &&
                  !dateOnly(g.start).isBefore(first) &&
                  !dateOnly(g.start).isAfter(last),
            )
            .length,
        registrations: _t.registrationsCreated(cityId, first, last),
      ),
    );
  }
}

/// The demo player's view of [SampleTournaments].
class _SampleTournamentRepository implements TournamentRepository {
  _SampleTournamentRepository(this._b);

  final SampleBackend _b;

  SampleTournaments get _rules => _b._rules;

  @override
  Future<List<Tournament>> list(
    String cityId, {
    String? sportId,
    DateTime? from,
    TournamentSort sort = TournamentSort.date,
  }) async => _rules.list(kMeId, cityId, sportId: sportId, from: from, sort: sort);

  @override
  Future<Tournament> get(String id) async => _rules.get(kMeId, id);

  @override
  Future<Registration> register(String categoryId, {String? partnerId}) =>
      _b.registerAs(kMeId, categoryId, partnerId: partnerId);

  @override
  Future<Registration> respondPartner(String registrationId, {required bool accept}) =>
      _b.respondPartnerAs(kMeId, registrationId, accept: accept);

  @override
  Future<Registration> cancel(String registrationId) => _b.cancelRegistrationAs(kMeId, registrationId);

  @override
  Future<Registration> joinWaitlist(String categoryId, {String? partnerId}) =>
      _b.joinWaitlistAs(kMeId, categoryId, partnerId: partnerId);

  @override
  Future<Registration> claimOffer(String registrationId) => _b.claimOfferAs(kMeId, registrationId);

  @override
  Future<List<Registration>> myRegistrations() async => _rules.myRegistrations(kMeId);

  @override
  Future<PlayerRef?> findPlayerByPhone(String phone) async => _rules.findPlayerByPhone(kMeId, phone);
}

enum _Invite { pending, accepted, declined }

/// `removed`: the host took the player out; it bars them from joining or
/// asking again until the host invites them (as the database does).
enum _AskStatus { pending, approved, declined, withdrawn, removed }

/// A request to join a game, waiting for the host, or a host's removal.
class _JoinAsk {
  _JoinAsk({required this.id, required this.gameId, required this.userId, required this.createdAt});

  final String id;
  final String gameId;
  final String userId;
  final DateTime createdAt;
  _AskStatus status = _AskStatus.pending;
}
