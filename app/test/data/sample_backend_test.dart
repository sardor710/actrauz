import 'package:actra/core/markets.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/slot_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sunday 22 Nov 2026, 10:00 in all three cities.
  final utcNow = DateTime.utc(2026, 11, 22, 5, 0);
  late SampleBackend backend;

  setUp(() => backend = SampleBackend(utcNow: () => utcNow));

  test('every city has venues, and each venue belongs to its city', () async {
    for (final city in kCities) {
      final venues = await backend.venues(city.id);
      expect(venues, isNotEmpty, reason: city.id);
      expect(venues.every((v) => v.cityId == city.id), isTrue);
    }
  });

  test('every court plays a known sport and has slots this week', () async {
    final sportIds = (await backend.sports()).map((s) => s.id).toSet();
    final today = DateTime.utc(2026, 11, 22);
    for (final venue in kSampleVenues) {
      for (final court in venue.courts) {
        expect(sportIds, contains(court.sportId));
        final slots = [for (var d = 0; d < 7; d++) ...generateSlots(venue, court, today.add(Duration(days: d)))];
        expect(slots, isNotEmpty, reason: court.id);
      }
    }
  });

  test('every text shown for a venue exists in all three languages', () {
    for (final venue in kSampleVenues) {
      for (final text in [venue.name, venue.description, venue.address, venue.district, ...venue.courts.map((c) => c.name)]) {
        expect(text.uz, isNotEmpty);
        expect(text.ru, isNotEmpty);
        expect(text.en, isNotEmpty);
      }
    }
  });

  test('sample games sit on real bookings and are not over capacity', () async {
    var total = 0;
    for (final city in kCities) {
      for (final game in await backend.games(city.id)) {
        total++;
        expect(game.participantIds.length, lessThanOrEqualTo(game.spots));
        expect(game.bookingId, isNotNull);
        final slots = await backend.availability(game.venueId, _courtOf(game.bookingId!, backend), game.start);
        expect(slots.firstWhere((s) => s.time.start == game.start).state, SlotState.taken);
      }
    }
    expect(total, greaterThanOrEqualTo(4));
  });

  test('full games are hidden from discovery', () async {
    final games = await backend.games('tashkent');
    expect(games.any((g) => g.isFull), isFalse);
    expect(games.map((g) => g.id), isNot(contains('g4')));
  });

  test('a hold shows as mine, then as taken once confirmed', () async {
    final slot = SlotTime(DateTime.utc(2026, 11, 22, 11, 30), DateTime.utc(2026, 11, 22, 13, 0));
    Future<SlotState> state() async =>
        (await backend.availability('v1', 'v1c1', slot.start)).firstWhere((s) => s.time == slot).state;

    expect(await state(), SlotState.free);
    final held = await backend.hold('v1', 'v1c1', [slot]);
    expect(await state(), SlotState.mine);
    await backend.confirm(held.id, players: 4);
    expect(await state(), SlotState.taken);
    expect((await backend.myBookings()).single.totalPrice, 300000);
  });
}

String _courtOf(String bookingId, SampleBackend backend) {
  // Sample games are seeded from kGameSeeds, in order, as bookings b1, b2, …
  final index = int.parse(bookingId.substring(1)) - 1;
  return kGameSeeds[index].courtId;
}
