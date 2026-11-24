import 'package:actra/core/markets.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
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
      for (final text in [
        venue.name,
        venue.description,
        venue.address,
        venue.district,
        ...venue.courts.map((c) => c.name),
      ]) {
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
        final slots = await backend.availability(game.venueId!, _courtOf(game.bookingId!, backend), game.start);
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

  group('community', () {
    // Monday 23 Nov 2026, early morning, in Tashkent wall-clock time.
    final tomorrowEarly = DateTime.utc(2026, 11, 23, 7);
    final tomorrowEnd = DateTime.utc(2026, 11, 23, 8);
    final bookingSlot = SlotTime(DateTime.utc(2026, 11, 22, 11, 30), DateTime.utc(2026, 11, 22, 13, 0));

    GameDraft runningDraft({int spots = 4, GameVisibility visibility = GameVisibility.public}) => GameDraft(
      sportId: 'running',
      spots: spots,
      visibility: visibility,
      meetingPoint: 'Bunyodkor park, main gate',
      meetingLat: 41.3,
      meetingLng: 69.2,
      start: tomorrowEarly,
      end: tomorrowEnd,
    );
    Future<Game> runningGame({int spots = 4, GameVisibility visibility = GameVisibility.public}) =>
        backend.create(runningDraft(spots: spots, visibility: visibility));

    Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));

    test('running and gym are place-only sports', () async {
      final sports = {for (final s in await backend.sports()) s.id: s};
      expect(sports['running']!.bookable, isFalse);
      expect(sports['gym']!.bookable, isFalse);
      expect(sports['padel']!.bookable, isTrue);
      for (final s in [sports['running']!, sports['gym']!]) {
        expect(s.name.uz, isNotEmpty);
        expect(s.name.ru, isNotEmpty);
        expect(s.name.en, isNotEmpty);
      }
    });

    test('a game from my own booking takes its price per player from the booking', () async {
      final held = await backend.hold('v1', 'v1c1', [bookingSlot]);
      final booking = await backend.confirm(held.id, players: 4);

      final game = await backend.create(GameDraft(sportId: 'padel', spots: 3, bookingId: booking.id));
      expect(game.kind, GameKind.booked);
      expect(game.venueId, 'v1');
      expect(game.hostId, kMeId);
      expect(game.myStatus, MyGameStatus.host);
      expect(game.participantIds, [kMeId]);
      expect(game.participants.single.id, kMeId);
      // 300000 for the court / 3 spots.
      expect(game.pricePerPlayer, 100000);
      expect(game.start, bookingSlot.start);

      // One game per booking, and only on the player's own booking.
      await expectLater(
        backend.create(GameDraft(sportId: 'padel', spots: 4, bookingId: booking.id)),
        joinError(JoinError.gameExists),
      );
      await expectLater(
        backend.create(const GameDraft(sportId: 'padel', spots: 4, bookingId: 'b1')),
        joinError(JoinError.bookingNotUsable),
      );

      // The price follows the spots when the host changes them.
      final changed = await backend.updateGame(game.id, spots: 4);
      expect(changed.pricePerPlayer, 75000);
    });

    test('a game on a map point is listed in the host city with no venue', () async {
      final game = await runningGame();
      expect(game.kind, GameKind.mapPoint);
      expect(game.venueId, isNull);
      expect(game.cityId, 'tashkent');
      expect(game.pricePerPlayer, isNull);
      expect((await backend.games('tashkent')).map((g) => g.id), contains(game.id));
      // Other players' games stay in their city; a game I host is listed wherever I look.
      final theirs = await backend.createAs('p3', runningDraft());
      expect((await backend.games('almaty')).map((g) => g.id), isNot(contains(theirs.id)));
      expect((await backend.games('almaty')).map((g) => g.id), contains(game.id));
    });

    test('a request waits for the host; approving puts the player in, declining does not', () async {
      final game = await runningGame(spots: 3);

      final asRequester = await backend.requestToJoinAs('p1', game.id);
      expect(asRequester.myStatus, MyGameStatus.requested);
      expect(asRequester.myRequestId, isNotNull);
      var seen = await backend.game(game.id);
      expect(seen.joinRequests.single.member.id, 'p1');
      expect(seen.joinRequests.single.member.name, 'Aziz');
      await expectLater(backend.requestToJoinAs('p1', game.id), joinError(JoinError.alreadyRequested));

      seen = await backend.decideRequest(seen.joinRequests.single.id, approve: true);
      expect(seen.participantIds, [kMeId, 'p1']);
      expect(seen.joinRequests, isEmpty);

      await backend.requestToJoinAs('p2', game.id);
      seen = await backend.decideRequest((await backend.game(game.id)).joinRequests.single.id, approve: false);
      expect(seen.participantIds, [kMeId, 'p1']);
      expect(seen.joinRequests, isEmpty);
    });

    test('approving a request on a game that filled up is refused', () async {
      final game = await runningGame(spots: 2);
      await backend.requestToJoinAs('p1', game.id);
      await backend.joinAs('p3', game.id);
      final requests = (await backend.game(game.id)).joinRequests;
      await expectLater(backend.decideRequest(requests.single.id, approve: true), joinError(JoinError.full));
      expect((await backend.game(game.id)).participantIds, [kMeId, 'p3']);
    });

    test('an invite-only game does not exist for others until they are invited; the invite skips the level', () async {
      final game = await runningGame(visibility: GameVisibility.inviteOnly);
      await expectLater(backend.joinAs('p1', game.id), joinError(JoinError.notFound));
      await backend.invite(game.id, 'p1');
      final joined = await backend.joinAs('p1', game.id);
      expect(joined.participantIds, [kMeId, 'p1']);
    });

    test('I see an invitation in the inbox, decline it, and can no longer join', () async {
      final theirs = await backend.createAs('p3', runningDraft(visibility: GameVisibility.inviteOnly));
      expect((await backend.games('tashkent')).map((g) => g.id), isNot(contains(theirs.id)));
      await backend.inviteAs('p3', theirs.id, kMeId);
      expect((await backend.game(theirs.id)).myStatus, MyGameStatus.invited);
      expect((await backend.games('tashkent')).map((g) => g.id), contains(theirs.id));
      final invite = (await backend.inbox()).first;
      expect(invite.kind, 'game_invite');
      expect(invite.category, 'invites');
      expect(invite.payload['actor_name'], 'Timur');

      await backend.declineInvite(theirs.id);
      await expectLater(backend.join(theirs.id), joinError(JoinError.notFound));
      // The city list shows public games only; the game still opens.
      expect((await backend.games('tashkent')).map((g) => g.id), isNot(contains(theirs.id)));
      expect((await backend.game(theirs.id)).id, theirs.id);
    });

    test('a removed player cannot join or ask again until the host invites them', () async {
      final game = await runningGame();
      await backend.joinAs('p1', game.id);
      await backend.removeParticipant(game.id, 'p1');
      await expectLater(backend.joinAs('p1', game.id), joinError(JoinError.notFound));
      await expectLater(backend.requestToJoinAs('p1', game.id), joinError(JoinError.notFound));
      expect((await backend.game(game.id)).joinRequests, isEmpty);

      await backend.invite(game.id, 'p1');
      expect((await backend.joinAs('p1', game.id)).participantIds, [kMeId, 'p1']);
      // Leaving of their own accord later does not bar them again.
      await backend.leaveAs('p1', game.id);
      expect((await backend.joinAs('p1', game.id)).participantIds, [kMeId, 'p1']);
    });

    test('host tools: remove a player, edit, cancel', () async {
      final game = await runningGame();
      await backend.joinAs('p1', game.id);
      await backend.joinAs('p2', game.id);
      var g = await backend.removeParticipant(game.id, 'p1');
      expect(g.participantIds, [kMeId, 'p2']);
      g = await backend.updateGame(game.id, note: 'Bring water', spots: 6);
      expect(g.note, 'Bring water');
      expect(g.spots, 6);
      await expectLater(backend.updateGame(game.id, spots: 1), joinError(JoinError.invalidArgument));
      final cancelled = await backend.cancelGame(game.id, cancelBooking: false);
      expect(cancelled.cancelled, isTrue);
      expect((await backend.games('tashkent')).map((g) => g.id), isNot(contains(game.id)));
    });

    test('cancelling a game can cancel its booking too, and a started game cannot be cancelled', () async {
      final held = await backend.hold('v1', 'v1c1', [bookingSlot]);
      final booking = await backend.confirm(held.id, players: 4);
      final game = await backend.create(GameDraft(sportId: 'padel', spots: 4, bookingId: booking.id));
      await backend.cancelGame(game.id, cancelBooking: true);
      expect((await backend.myBookings()).single.status, BookingStatus.cancelledByPlayer);

      await expectLater(
        backend.create(
          GameDraft(
            sportId: 'running',
            spots: 2,
            meetingPoint: 'x',
            start: DateTime.utc(2026, 11, 22, 9),
            end: DateTime.utc(2026, 11, 22, 9, 30),
          ),
        ),
        joinError(JoinError.inPast),
      );
    });

    test('once a game has started it can no longer be cancelled', () async {
      var clock = utcNow;
      final timed = SampleBackend(utcNow: () => clock);
      final game = await timed.create(runningDraft());
      // The game starts at 07:00 in Tashkent, which is 02:00 UTC.
      clock = DateTime.utc(2026, 11, 23, 3);
      await expectLater(timed.cancelGame(game.id, cancelBooking: false), joinError(JoinError.notCancellable));
      expect((await timed.game(game.id)).cancelled, isFalse);
    });

    test('someone else cannot run my game', () async {
      final theirs = await backend.createAs('p3', runningDraft());
      for (final call in [
        () => backend.removeParticipant(theirs.id, 'p3'),
        () => backend.updateGame(theirs.id, spots: 5),
        () => backend.cancelGame(theirs.id, cancelBooking: false),
        () => backend.invite(theirs.id, 'p1'),
      ]) {
        await expectLater(call(), joinError(JoinError.notFound));
      }
    });

    test('a Game Request: interest, then converting adds the interested up to the spots', () async {
      final request = await backend.createRequest(
        GameRequestDraft(
          sportId: 'running',
          playersNeeded: 4,
          start: tomorrowEarly,
          end: tomorrowEnd,
          area: 'Yunusobod',
        ),
      );
      expect(request.myStatus, MyRequestStatus.host);
      expect((await backend.requests('tashkent')).map((r) => r.id), contains(request.id));

      for (final id in ['p1', 'p2', 'p3']) {
        await backend.interestAs(id, request.id);
      }
      await expectLater(backend.interestAs('p1', request.id), joinError(JoinError.alreadyJoined));
      expect((await backend.request(request.id)).interested.map((m) => m.id), ['p1', 'p2', 'p3']);
      expect((await backend.inbox()).where((n) => n.kind == 'request_interest'), hasLength(3));

      // The poster removes the first one, so p2 is next in line.
      await backend.removeInterested(request.id, 'p1');

      final game = await backend.convertRequest(
        request.id,
        const PlacePick(meetingPoint: 'Bunyodkor park', meetingLat: 41.3, meetingLng: 69.2, spots: 2),
      );
      expect(game.kind, GameKind.mapPoint);
      expect(game.spots, 2);
      // Two spots: the poster and the first interested player; p3 is not added.
      expect(game.participantIds, [kMeId, 'p2']);
      final converted = await backend.request(request.id);
      expect(converted.status, GameRequestStatus.converted);
      expect(converted.gameId, game.id);
      expect((await backend.requests('tashkent')).map((r) => r.id), isNot(contains(request.id)));
    });

    test('converting without spots takes everyone who is interested', () async {
      final request = await backend.createRequest(
        GameRequestDraft(sportId: 'running', playersNeeded: 2, start: tomorrowEarly, end: tomorrowEnd),
      );
      await backend.interestAs('p1', request.id);
      await backend.interestAs('p2', request.id);
      final game = await backend.convertRequest(
        request.id,
        const PlacePick(meetingPoint: 'x', meetingLat: 1, meetingLng: 1),
      );
      expect(game.spots, 3);
      expect(game.participantIds, [kMeId, 'p1', 'p2']);
    });

    test('converting skips an interested player who has been blocked since', () async {
      final request = await backend.createRequest(
        GameRequestDraft(sportId: 'running', playersNeeded: 1, start: tomorrowEarly, end: tomorrowEnd),
      );
      await backend.interestAs('p1', request.id);
      await backend.interestAs('p2', request.id);
      backend.recordReliability('p1', ReliabilityKind.noShow, 'x-1');
      backend.recordReliability('p1', ReliabilityKind.noShow, 'x-2');
      final game = await backend.convertRequest(
        request.id,
        const PlacePick(meetingPoint: 'x', meetingLat: 1, meetingLng: 1, spots: 2),
      );
      expect(game.participantIds, [kMeId, 'p2']);
    });

    test('other people\'s requests: I am in, then out; only the poster converts or cancels', () async {
      final seeded = (await backend.requests('tashkent')).firstWhere((r) => r.hostId != kMeId);
      final joined = await backend.imIn(seeded.id);
      expect(joined.myStatus, MyRequestStatus.interested);
      expect(joined.interested.map((m) => m.id), contains(kMeId));
      expect((await backend.withdrawInterest(seeded.id)).myStatus, isNull);

      await expectLater(
        backend.convertRequest(seeded.id, const PlacePick(meetingPoint: 'x', meetingLat: 1, meetingLng: 1)),
        joinError(JoinError.notFound),
      );
      await expectLater(backend.cancelRequest(seeded.id), joinError(JoinError.notFound));
      await expectLater(backend.removeInterested(seeded.id, 'p1'), joinError(JoinError.notFound));
    });

    test('the inbox gets game_joined when a sample player joins my game', () async {
      final game = await runningGame();
      expect(await backend.unreadCount(), 1, reason: 'the sample inbox starts with one unread');
      await backend.joinAs('p1', game.id);
      final inbox = await backend.inbox();
      expect(inbox.first.kind, 'game_joined');
      expect(inbox.first.category, 'games');
      expect(inbox.first.payload['game_id'], game.id);
      expect(inbox.first.payload['actor_name'], 'Aziz');
      expect(inbox.first.route, '/games/${game.id}');
      expect(inbox.first.read, isFalse);
      expect(await backend.unreadCount(), 2);

      await backend.markRead([inbox.first.id]);
      expect(await backend.unreadCount(), 1);
      await backend.markRead();
      expect(await backend.unreadCount(), 0);
    });

    test('a muted category writes nothing to the inbox', () async {
      await backend.saveSettings(const CommunitySettings(mutedCategories: {'games'}));
      expect((await backend.settings()).mutedCategories, {'games'});
      final game = await runningGame();
      await backend.joinAs('p1', game.id);
      await backend.requestToJoinAs('p2', game.id);
      expect((await backend.inbox()).where((n) => n.category == 'games'), isEmpty);

      await backend.saveSettings(const CommunitySettings());
      await backend.joinAs('p3', game.id);
      expect((await backend.inbox()).where((n) => n.kind == 'game_joined'), hasLength(1));
    });

    test('the inbox pages by date with before', () async {
      final game = await runningGame(spots: 9);
      for (final id in ['p1', 'p2', 'p3']) {
        await backend.joinAs(id, game.id);
      }
      final all = await backend.inbox();
      expect(all.length, greaterThanOrEqualTo(4));
      final older = await backend.inbox(before: all[1].createdAt);
      expect(older.every((n) => n.createdAt.isBefore(all[1].createdAt)), isTrue);
      expect(older.map((n) => n.id), isNot(contains(all[0].id)));
      expect(older.map((n) => n.id), isNot(contains(all[1].id)));

      // With the id as well, the next page starts right after the last entry.
      final next = await backend.inbox(before: all[1].createdAt, beforeId: all[1].id);
      expect(next.map((n) => n.id), all.skip(2).map((n) => n.id));
    });

    test('players can be found by sport level and name; I am not in the list', () async {
      final everyone = await backend.players('tashkent');
      expect(everyone.map((p) => p.id), isNot(contains(kMeId)));
      expect(everyone.length, kSamplePlayers.length);
      final padel4 = await backend.players('tashkent', sportId: 'padel', minLevel: 4, maxLevel: 5);
      expect(padel4.map((p) => p.id), ['p7']);
      expect((await backend.players('tashkent', query: 'dil')).single.name, 'Dilnoza');
      final profile = await backend.profile('p1');
      expect(profile.name, 'Aziz');
      expect(profile.levels['padel'], 3);
      expect(profile.reliability.badge, ReliabilityBadge.isNew);
      expect((await backend.profile(kMeId)).reliability.badge, ReliabilityBadge.reliable);
    });

    test('hiding from search leaves me out of the list; the profile still opens', () async {
      await backend.saveSettings(const CommunitySettings(hiddenFromSearch: true));
      expect((await backend.settings()).hiddenFromSearch, isTrue);
      expect((await backend.profile(kMeId)).id, kMeId);
    });

    test('the demo player is reliable; a no-show makes them limited, a second blocked', () async {
      expect((await backend.settings()).reliability.badge, ReliabilityBadge.reliable);

      backend.recordReliability(kMeId, ReliabilityKind.noShow, 'b-1');
      expect((await backend.settings()).reliability.score, 66);
      expect((await backend.settings()).reliability.badge, ReliabilityBadge.limited);
      // Limited: one upcoming booking at a time.
      final held = await backend.hold('v1', 'v1c1', [bookingSlot]);
      await backend.confirm(held.id, players: 4);
      final next = SlotTime(DateTime.utc(2026, 11, 22, 13, 0), DateTime.utc(2026, 11, 22, 14, 30));
      await expectLater(
        backend.hold('v1', 'v1c1', [next]),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.tooManyBookings)),
      );

      backend.recordReliability(kMeId, ReliabilityKind.noShow, 'b-2');
      expect((await backend.settings()).reliability.badge, ReliabilityBadge.blocked);
      await expectLater(
        backend.hold('v1', 'v1c1', [next]),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.reliabilityTooLow)),
      );
      await expectLater(runningGame(), joinError(JoinError.reliabilityTooLow));
      await expectLater(backend.join('g3'), joinError(JoinError.reliabilityTooLow));
    });

    test('a late cancellation counts against the player; an early one does not', () async {
      // Inside 6 hours of the start (it is 10:00; the slot starts at 11:30).
      final held = await backend.hold('v1', 'v1c1', [bookingSlot]);
      final booking = await backend.confirm(held.id, players: 4);
      await backend.cancel(booking.id);
      expect((await backend.settings()).reliability.score, 81);
    });

    test('a cancellation more than six hours before the start is free', () async {
      // It is 10:00; this slot starts at 17:30.
      final slot = SlotTime(DateTime.utc(2026, 11, 22, 17, 30), DateTime.utc(2026, 11, 22, 19));
      final held = await backend.hold('v1', 'v1c1', [slot]);
      final booking = await backend.confirm(held.id, players: 4);
      expect((await backend.cancel(booking.id)).lateCancellation, isFalse);
      expect((await backend.settings()).reliability.score, 86);
    });

    test('owners are told about bookings with the court named in three languages', () async {
      final held = await backend.hold('v1', 'v1c1', [bookingSlot]);
      final booking = await backend.confirm(held.id, players: 4);
      final inbox = await backend.inbox();
      final forPlayer = inbox.firstWhere((n) => n.kind == 'booking_confirmed');
      expect(forPlayer.payload['booking_id'], booking.id);
      expect((forPlayer.payload['venue_name'] as Map)['en'], 'Lochin Padel Club');
      expect(forPlayer.payload['sport_id'], 'padel');
      expect(forPlayer.route, '/bookings');
      final forOwner = inbox.firstWhere((n) => n.kind == 'venue_new_booking' && n.payload['booking_id'] == booking.id);
      expect(forOwner.payload.containsKey('venue_name'), isFalse);
      expect(forOwner.payload['venue_id'], 'v1');
      expect((forOwner.payload['court_name'] as Map).keys, containsAll(['uz', 'ru', 'en']));
      expect(forOwner.route, '/owner/v1');
    });
  });
}

String _courtOf(String bookingId, SampleBackend backend) {
  // Sample games are seeded from kGameSeeds, in order, as bookings b1, b2, …
  final index = int.parse(bookingId.substring(1)) - 1;
  return kGameSeeds[index].courtId;
}
