import '../../core/markets.dart';
import '../../domain/booking_engine.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../repositories.dart';
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
  final Map<String, Venue> _venues = {for (final v in kSampleVenues) v.id: v};
  final Map<String, Game> _games = {};

  Venue _venue(String id) => _venues[id] ?? (throw StateError('Unknown venue $id'));

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
  Future<List<Sport>> sports() async => kSampleSports;

  @override
  Future<List<Venue>> venues(String cityId) async => _venues.values.where((v) => v.cityId == cityId).toList();

  @override
  Future<Venue> venue(String id) async => _venue(id);

  @override
  Future<List<BannerItem>> banners(String cityId) async => kSampleBanners;

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
}
