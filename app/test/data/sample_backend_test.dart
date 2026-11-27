import 'package:actra/core/markets.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/competitive.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/slot_generator.dart';
import 'package:actra/domain/teams.dart';
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

  test('every sample tournament has valid categories, in three languages, and none is over its cap', () {
    for (final t in kTournamentSeeds) {
      expect(t.categories, isNotEmpty, reason: t.id);
      expect(t.categories.map((c) => c.id).toSet(), hasLength(t.categories.length), reason: t.id);
      for (final c in t.categories) {
        expect(c.taken, lessThanOrEqualTo(c.cap), reason: c.id);
        expect(c.minLevel, inInclusiveRange(1, 5), reason: c.id);
        expect(c.maxLevel, inInclusiveRange(c.minLevel, 5), reason: c.id);
        expect(c.cap, inInclusiveRange(1, 512), reason: c.id);
        expect([c.name.uz, c.name.ru, c.name.en], everyElement(isNotEmpty), reason: c.id);
      }
    }
    // The ids are unique across tournaments too (the seed turns each into a uuid).
    final ids = [for (final t in kTournamentSeeds) ...t.categories.map((c) => c.id)];
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('the sample tournaments are dated from today, each closing registration before it starts', () async {
    for (final city in kCities) {
      for (final t in await backend.tournament.list(city.id)) {
        final seed = kTournamentSeeds.firstWhere((s) => s.id == t.id);
        final today = DateTime.utc(2026, 11, 22);
        expect(t.start, today.add(Duration(days: seed.daysAhead)));
        expect(t.end, today.add(Duration(days: seed.daysAhead + seed.days - 1)));
        expect(t.registrationDeadline, t.start.add(Duration(days: -seed.deadlineDaysBefore, hours: 18)));
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
      expect((forPlayer.payload['venue_name'] as Map).keys, containsAll(['uz', 'ru', 'kk', 'en']));
      expect(forPlayer.payload['sport_id'], 'padel');
      expect(forPlayer.route, '/bookings');
      final forOwner = inbox.firstWhere((n) => n.kind == 'venue_new_booking' && n.payload['booking_id'] == booking.id);
      expect(forOwner.payload.containsKey('venue_name'), isFalse);
      expect(forOwner.payload['venue_id'], 'v1');
      expect((forOwner.payload['court_name'] as Map).keys, containsAll(['uz', 'ru', 'kk', 'en']));
      expect(forOwner.route, '/owner/v1');
    });
  });

  group('ratings', () {
    Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));

    test('every sample player in padel or tennis has a rating that agrees with their level', () {
      for (final p in kSamplePlayers) {
        for (final sportId in ['padel', 'tennis']) {
          final level = p.levels[sportId];
          final rating = p.ratings[sportId];
          expect(rating == null, level == null, reason: '${p.id} $sportId');
          if (rating == null) continue;
          expect(rating.rating, level! + 0.5, reason: '${p.id} $sportId');
          expect(levelOfRating(rating.rating), level, reason: '${p.id} $sportId');
          expect(rating.ratedGames, p.id == 'p2' ? 4 : 12, reason: '${p.id} $sportId');
        }
        expect(p.ratings.keys.toSet().difference({'padel', 'tennis'}), isEmpty, reason: p.id);
      }
    });

    test('a new player has no sports', () async {
      expect(await backend.mySports(), isEmpty);
      expect((await backend.player(kMeId)).levels, isEmpty);
    });

    test('the questionnaire places me in padel; I can retake it until my first rated game', () async {
      final sports = await backend.setSport('padel', answers: [1, 2, 1, 0, 2]);
      final padel = sports.single;
      expect(padel.sportId, 'padel');
      expect(padel.rating!.rating, 2.7);
      expect(padel.rating!.ratedGames, 0);
      expect(padel.rating!.provisional, isTrue);
      expect(padel.level, 2);
      expect(padel.canRetake, isTrue);
      expect((await backend.player(kMeId)).levelFor('padel'), 2);
      expect((await backend.player(kMeId)).ratingFor('padel'), 2.7);
      expect((await backend.profile(kMeId)).ratings['padel']!.rating, 2.7);

      final again = await backend.setSport('padel', answers: [3, 3, 3, 3, 3]);
      expect(again.single.rating!.rating, 5.0);
      expect(again.single.level, 5);
    });

    test('a rating with rated games is kept when the questionnaire is answered again', () async {
      final rated = SampleBackend(
        utcNow: () => utcNow,
        meRatings: const {'tennis': SportRating(rating: 3.8, ratedGames: 3)},
      );
      final tennis = (await rated.mySports()).single;
      expect(tennis.level, 3);
      expect(tennis.canRetake, isFalse);
      final after = (await rated.setSport('tennis', answers: [0, 0, 0, 0, 0])).single;
      expect(after.rating!.rating, 3.8);
      expect(after.rating!.ratedGames, 3);
      expect(after.level, 3);
    });

    test('a simple sport takes a level; the wrong kind of answer is refused', () async {
      final sports = await backend.setSport('football', level: 4);
      expect(sports.single.sportId, 'football');
      expect(sports.single.level, 4);
      expect(sports.single.rating, isNull);
      expect(sports.single.canRetake, isFalse);
      expect((await backend.setSport('football', level: 2)).single.level, 2);

      await expectLater(backend.setSport('football', level: 6), joinError(JoinError.invalidArgument));
      await expectLater(backend.setSport('football', answers: [1, 1, 1, 1, 1]), joinError(JoinError.invalidArgument));
      await expectLater(backend.setSport('padel', level: 3), joinError(JoinError.invalidArgument));
      await expectLater(backend.setSport('padel', answers: [1, 1, 1, 1]), joinError(JoinError.invalidArgument));
      await expectLater(backend.setSport('padel'), joinError(JoinError.invalidArgument));
      await expectLater(backend.setSport('cricket', level: 3), joinError(JoinError.invalidArgument));
    });

    test('my sports come in catalogue order; removing one keeps its rating for later', () async {
      await backend.setSport('padel', answers: [1, 2, 1, 0, 2]);
      await backend.setSport('football', level: 4);
      expect((await backend.mySports()).map((s) => s.sportId), ['football', 'padel']);

      final left = await backend.removeSport('padel');
      expect(left.map((s) => s.sportId), ['football']);
      expect((await backend.profile(kMeId)).ratings, isEmpty);
      expect((await backend.player(kMeId)).levels, {'football': 4});

      // Ticking padel again brings the rating back while it has no rated games: the answers replace it.
      final back = await backend.setSport('padel', answers: [0, 0, 0, 0, 0]);
      expect(back.map((s) => s.sportId), ['football', 'padel']);
      expect(back.last.rating!.rating, 1.0);
    });

    test('players can be found by rating in a rated sport', () async {
      final found = await backend.players('tashkent', sportId: 'padel', minRating: 3, maxRating: 4);
      expect(found.map((p) => p.id), unorderedEquals(['p1', 'p5', 'p8']));
      for (final p in found) {
        expect(p.ratings['padel']!.rating, inInclusiveRange(3, 4));
      }
      // No rating counts as 1.0.
      final low = await backend.players('tashkent', sportId: 'tennis', minRating: 1, maxRating: 1.5);
      expect(low.map((p) => p.id), unorderedEquals(['p1', 'p3', 'p5', 'p6', 'p7']));
    });

    test('a padel game with a rating range derives its levels; a range sent as levels becomes ratings', () async {
      final bookingSlot = SlotTime(DateTime.utc(2026, 11, 22, 11, 30), DateTime.utc(2026, 11, 22, 13, 0));
      final held = await backend.hold('v1', 'v1c1', [bookingSlot]);
      final booking = await backend.confirm(held.id, players: 4);
      final game = await backend.create(
        GameDraft(sportId: 'padel', spots: 4, bookingId: booking.id, minRating: 3, maxRating: 4.5),
      );
      expect(game.minLevel, 3);
      expect(game.maxLevel, 4);
      expect(game.minRating, 3.0);
      expect(game.maxRating, 4.5);
      expect((await backend.game(game.id)).minRating, 3.0);
      expect((await backend.game(game.id)).maxRating, 4.5);

      // p7 (4.5) fits; p2 (2.5) does not and would have to ask.
      expect((await backend.joinAs('p7', game.id)).participantIds, [kMeId, 'p7']);
      await expectLater(backend.joinAs('p2', game.id), joinError(JoinError.levelOutOfRange));

      // The seeded padel game 2-4 reads as 2.00-4.99; a running game has no rating range.
      final g1 = await backend.game('g1');
      expect((g1.minRating, g1.maxRating), (2.0, 4.99));
      final g4 = await backend.game('g4');
      expect((g4.minRating, g4.maxRating), (3.0, 7.0));
      expect((await backend.game('g2')).minRating, isNull);

      // One end only, or an upside-down range, is refused.
      final held2 = await backend.hold('v1', 'v1c2', [bookingSlot]);
      final booking2 = await backend.confirm(held2.id, players: 4);
      await expectLater(
        backend.create(GameDraft(sportId: 'padel', spots: 4, bookingId: booking2.id, minRating: 3)),
        joinError(JoinError.invalidArgument),
      );
      await expectLater(
        backend.create(GameDraft(sportId: 'padel', spots: 4, bookingId: booking2.id, minRating: 4, maxRating: 3)),
        joinError(JoinError.invalidArgument),
      );
    });

    test('participants show their rating in a rated sport, and nothing in a simple one', () async {
      final g1 = await backend.game('g1');
      final p2 = g1.participants.firstWhere((m) => m.id == 'p2');
      expect(p2.rating, 2.5);
      expect(p2.provisional, isTrue);
      final p1 = g1.participants.firstWhere((m) => m.id == 'p1');
      expect(p1.rating, 3.5);
      expect(p1.provisional, isFalse);
      final football = await backend.game('g2');
      expect(football.participants.every((m) => m.rating == null && !m.provisional), isTrue);
    });

    test('a padel Game Request carries its rating range into the game it becomes', () async {
      final request = await backend.createRequest(
        GameRequestDraft(
          sportId: 'padel',
          playersNeeded: 1,
          start: DateTime.utc(2026, 11, 23, 18),
          end: DateTime.utc(2026, 11, 23, 21),
          minRating: 2.5,
          maxRating: 4,
        ),
      );
      expect((request.minLevel, request.maxLevel), (2, 4));
      expect((request.minRating, request.maxRating), (2.5, 4.0));
      expect((await backend.request('rq1')).minRating, 2.0);
      expect((await backend.request('rq2')).minRating, isNull);

      final slot = SlotTime(DateTime.utc(2026, 11, 23, 19), DateTime.utc(2026, 11, 23, 20, 30));
      final held = await backend.hold('v1', 'v1c2', [slot]);
      final booking = await backend.confirm(held.id, players: 2);
      final game = await backend.convertRequest(request.id, PlacePick(bookingId: booking.id));
      expect((game.minRating, game.maxRating), (2.5, 4.0));
      expect((game.minLevel, game.maxLevel), (2, 4));
    });
  });

  group('scores and past games', () {
    Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));

    // Sunday 10:00 in Tashkent; gf1, gf2 and gf3 were played yesterday.
    final tashkentNow = DateTime.utc(2026, 11, 22, 10);
    const sixFourTwice = [(6, 4), (6, 4)];
    const aziz = SportRating(rating: 3.5, ratedGames: 12);
    const dilnoza = SportRating(rating: 2.5, ratedGames: 4);

    Future<MatchResult> enterGf1() async =>
        (await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: sixFourTwice)).result!;

    test('finished games are past games, newest first, and never in the games list', () async {
      final past = await backend.pastGames();
      expect(past.map((g) => g.id), ['gf2', 'gf1', 'gf3']);
      expect((await backend.games('tashkent')).map((g) => g.id), isNot(contains('gf1')));

      final gf1 = await backend.game('gf1');
      expect(gf1.sportId, 'padel');
      expect(gf1.hostId, kMeId);
      expect(gf1.participantIds, [kMeId, 'p1', 'p2', 'p3']);
      expect(gf1.endedAt(tashkentNow), isTrue);
      expect(gf1.endedAt(gf1.start), isFalse);
      expect(gf1.result, isNull);

      final gf2 = await backend.game('gf2');
      expect(gf2.hostId, 'p1');
      expect(gf2.result!.status, ResultStatus.pending);
      expect(gf2.result!.enteredBy, 'p1');
      expect(gf2.result!.sideB, contains(kMeId), reason: 'I am on the other side, so I can confirm');
    });

    test('the host enters a score; an opponent confirms and ratings move', () async {
      final pending = await enterGf1();
      expect(pending.status, ResultStatus.pending);
      expect(pending.enteredBy, kMeId);
      expect(pending.sideA, [kMeId, 'p1']);
      expect(pending.sideB, ['p2', 'p3']);
      expect(pending.sets, sixFourTwice);
      expect(pending.winner, MatchWinner.a);
      expect(pending.changes, isEmpty);

      final confirmed = (await backend.confirmScoreAs('p2', pending.id)).result!;
      expect(confirmed.status, ResultStatus.confirmed);
      expect(confirmed.confirmedBy, ['p2']);

      // I had no padel rating: I start at the average of those who have one.
      final expected = ratingChanges(sideA: [null, aziz], sideB: [dilnoza, null], sets: sixFourTwice);
      expect(confirmed.changes[kMeId]!.oldRating, 3.0);
      expect(confirmed.changes[kMeId]!.newRating, expected.a.first.newRating);
      expect(confirmed.changes['p2']!.newRating, expected.b.first.newRating);
      expect(confirmed.changes.keys, unorderedEquals([kMeId, 'p1', 'p2', 'p3']));

      final padel = (await backend.mySports()).singleWhere((s) => s.sportId == 'padel');
      expect(padel.rating!.rating, expected.a.first.newRating);
      expect(padel.rating!.ratedGames, 1);
      expect(padel.level, levelOfRating(expected.a.first.newRating));
      expect(padel.canRetake, isFalse);
      final p2 = (await backend.game('gf1')).participants.singleWhere((m) => m.id == 'p2');
      expect(p2.rating, expected.b.first.newRating);

      final notice = (await backend.inbox()).firstWhere((n) => n.kind == 'rating_updated');
      expect(notice.category, 'ratings');
      expect(notice.payload['old'], 3.0);
      expect(notice.payload['new'], expected.a.first.newRating);
      expect(notice.route, '/games/gf1');

      // Confirming twice changes nothing.
      expect(() => backend.confirmScoreAs('p3', pending.id), joinError(JoinError.notFound));
    });

    test('I confirm the score p1 entered for gf2', () async {
      final gf2 = await backend.game('gf2');
      final confirmed = (await backend.confirmScore(gf2.result!.id)).result!;
      expect(confirmed.status, ResultStatus.confirmed);
      expect(confirmed.changes, contains(kMeId));
    });

    test('a partner confirming is not enough', () async {
      final pending = await enterGf1();
      final after = (await backend.confirmScoreAs('p1', pending.id)).result!;
      expect(after.status, ResultStatus.pending);
      expect(after.confirmedBy, ['p1']);
      expect(after.changes, isEmpty);
      // The one who entered it cannot confirm it.
      expect(() => backend.confirmScore(pending.id), joinError(JoinError.notFound));
    });

    test('whoever entered a pending score can correct it; that clears the confirmations', () async {
      final pending = await enterGf1();
      await backend.confirmScoreAs('p1', pending.id);
      final corrected =
          (await backend.enterScore('gf1', sideA: [kMeId, 'p2'], sideB: ['p1', 'p3'], sets: [(6, 3)])).result!;
      expect(corrected.id, pending.id);
      expect(corrected.confirmedBy, isEmpty);
      expect(corrected.sideA, [kMeId, 'p2']);
      expect(corrected.sets, [(6, 3)]);
    });

    test('a dispute freezes the result', () async {
      final pending = await enterGf1();
      final disputed = (await backend.disputeScoreAs('p2', pending.id, reason: '  We won the second set  ')).result!;
      expect(disputed.status, ResultStatus.disputed);
      expect(disputed.disputeReason, 'We won the second set');
      expect((await backend.inbox()).where((n) => n.kind == 'score_disputed'), hasLength(1));
      expect(backend.autoConfirmScores(), 0);
      expect(await backend.mySports(), isEmpty, reason: 'no rating moved');
      expect(() => backend.confirmScoreAs('p2', pending.id), joinError(JoinError.notFound));
      expect(
        () => backend.enterScore('gf1', sideA: [kMeId], sideB: ['p2'], sets: sixFourTwice),
        joinError(JoinError.scoreClosed),
      );
    });

    test('a pending score confirms itself 24 hours after it was entered', () async {
      var now = utcNow;
      final timed = SampleBackend(utcNow: () => now);
      final pending =
          (await timed.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: sixFourTwice)).result!;
      now = utcNow.add(const Duration(hours: 23));
      // Only gf2's, which p1 entered an hour before the start.
      expect(timed.autoConfirmScores(), 1);
      expect((await timed.game('gf2')).result!.status, ResultStatus.confirmed);
      expect((await timed.game('gf1')).result!.status, ResultStatus.pending);
      now = utcNow.add(const Duration(hours: 24));
      expect(timed.autoConfirmScores(), 1);
      expect((await timed.game('gf1')).result!.status, ResultStatus.confirmed);
      expect(pending.status, ResultStatus.pending);
      expect((await timed.mySports()).single.rating!.ratedGames, 2, reason: 'gf2 and gf1');
    });

    test('who may enter a score, and when', () async {
      var now = utcNow;
      final timed = SampleBackend(utcNow: () => now);
      // Not the host, within 24 hours of the end.
      expect(
        () => timed.enterScoreAs('p1', 'gf1', sideA: ['p1'], sideB: ['p2'], sets: sixFourTwice),
        joinError(JoinError.forbidden),
      );
      // Not the host of gf2 either, within 24 hours of its end.
      expect(
        () => timed.enterScore('gf2', sideA: [kMeId], sideB: ['p1'], sets: sixFourTwice),
        joinError(JoinError.forbidden),
      );
      // Not in the game.
      expect(
        () => timed.enterScoreAs('p5', 'gf1', sideA: ['p5'], sideB: ['p2'], sets: sixFourTwice),
        joinError(JoinError.notFound),
      );
      // A simple sport.
      await timed.join('g2');
      expect(
        () => timed.enterScore('g2', sideA: [kMeId], sideB: ['p3'], sets: sixFourTwice),
        joinError(JoinError.notFound),
      );
      // A padel game that has not ended.
      final slot = SlotTime(DateTime.utc(2026, 11, 23, 19), DateTime.utc(2026, 11, 23, 20, 30));
      final booking = await timed.confirm((await timed.hold('v1', 'v1c2', [slot])).id, players: 2);
      final upcoming = await timed.create(GameDraft(sportId: 'padel', spots: 2, bookingId: booking.id));
      await timed.joinAs('p1', upcoming.id);
      expect(
        () => timed.enterScore(upcoming.id, sideA: [kMeId], sideB: ['p1'], sets: sixFourTwice),
        joinError(JoinError.scoreClosed),
      );

      // 25 hours after the end anyone in the game may.
      now = utcNow.add(const Duration(hours: 25));
      final entered = await timed.enterScoreAs('p1', 'gf1', sideA: ['p1'], sideB: ['p2'], sets: sixFourTwice);
      expect(entered.result!.enteredBy, 'p1');
      // A pending score someone else entered: even the host cannot replace it.
      expect(
        () => timed.enterScore('gf1', sideA: [kMeId], sideB: ['p1'], sets: sixFourTwice),
        joinError(JoinError.forbidden),
      );
      // 8 days after the end nobody may.
      now = utcNow.add(const Duration(days: 8));
      expect(
        () => timed.enterScoreAs('p1', 'gf1', sideA: ['p1'], sideB: ['p2'], sets: sixFourTwice),
        joinError(JoinError.scoreClosed),
      );
    });

    test('bad scores are refused', () async {
      for (final (sideA, sideB, sets) in <(List<String>, List<String>, List<(int, int)>)>[
        ([kMeId, 'p1'], ['p2'], sixFourTwice),
        ([kMeId, 'p1'], ['p1', 'p2'], sixFourTwice),
        ([kMeId], ['p5'], sixFourTwice),
        (['p1'], ['p2'], sixFourTwice),
        ([kMeId], ['p2'], [(6, 0), (6, 0), (6, 0), (6, 0), (6, 0), (6, 0)]),
        ([kMeId], ['p2'], [(0, 0)]),
        ([kMeId], ['p2'], [(31, 0)]),
        ([kMeId], ['p2'], [(-1, 6)]),
        ([kMeId], ['p2'], []),
      ]) {
        expect(
          () => backend.enterScore('gf1', sideA: sideA, sideB: sideB, sets: sets),
          joinError(JoinError.invalidArgument),
          reason: '$sideA v $sideB $sets',
        );
      }
    });

    test('a deleted player cannot be named; one deleted before confirmation voids the result', () async {
      final pending = await enterGf1();
      backend.markDeleted('p3');
      expect(
        () => backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: sixFourTwice),
        joinError(JoinError.invalidArgument),
      );
      final voided = (await backend.confirmScoreAs('p2', pending.id)).result!;
      expect(voided.status, ResultStatus.voided);
      expect(voided.changes, isEmpty);
      expect(await backend.mySports(), isEmpty);
      final notice = (await backend.inbox()).firstWhere((n) => n.kind == 'score_resolved');
      expect(notice.payload['action'], 'void');
    });

    test('nobody leaves a game once it has started', () async {
      expect(() => backend.leaveAs('p1', 'gf1'), joinError(JoinError.notFound));
    });

    test('the players of a game that ends hear about it; the host may enter the score', () async {
      var now = utcNow;
      final timed = SampleBackend(utcNow: () => now);
      final slot = SlotTime(DateTime.utc(2026, 11, 23, 19), DateTime.utc(2026, 11, 23, 20, 30));
      final booking = await timed.confirm((await timed.hold('v1', 'v1c2', [slot])).id, players: 2);
      final game = await timed.create(GameDraft(sportId: 'padel', spots: 2, bookingId: booking.id));
      await timed.joinAs('p1', game.id);
      expect((await timed.inbox()).where((n) => n.kind == 'game_finished'), isEmpty);

      now = DateTime.utc(2026, 11, 23, 15, 31); // 20:31 in Tashkent
      final finished = (await timed.inbox()).where((n) => n.kind == 'game_finished').toList();
      expect(finished, hasLength(1));
      expect(finished.single.category, 'games');
      expect(finished.single.payload['can_score'], isTrue);
      expect(finished.single.route, '/games/${game.id}');
      expect((await timed.pastGames()).first.id, game.id);
      expect((await timed.inbox()).where((n) => n.kind == 'game_finished'), hasLength(1), reason: 'once');
    });

    test('score notices can be muted under ratings', () async {
      await backend.saveSettings(const CommunitySettings(mutedCategories: {'ratings', 'teams'}));
      final pending = await enterGf1();
      await backend.confirmScoreAs('p2', pending.id);
      expect((await backend.inbox()).where((n) => n.category == 'ratings'), isEmpty);
    });
  });

  group('leaderboard', () {
    test('lists rated players by rating, then rated games, then id; the demo player only with a rated game', () async {
      final before = await backend.leaderboard('padel', 'tashkent');
      expect(before.rows.map((r) => r.id), ['p7', 'p1', 'p5', 'p8', 'p2']);
      expect(before.rows.map((r) => r.position), [1, 2, 3, 4, 5]);
      expect(before.rows.first.name, 'Bekzod');
      expect(before.rows.first.rating.rating, 4.5);
      expect(before.rows.last.rating.ratedGames, 4);
      expect(before.rows.any((r) => r.isMe), isFalse);
      expect(before.me, isNull, reason: 'no confirmed result yet');
      // Players without a padel rating, and sports without ratings, are not listed.
      expect(before.rows.map((r) => r.id), isNot(contains('p3')));
      expect((await backend.leaderboard('football', 'tashkent')).rows, isEmpty);
      // Sample players are in every city.
      expect((await backend.leaderboard('padel', 'almaty')).rows.map((r) => r.id), before.rows.map((r) => r.id));
    });

    test('a deleted player is never listed', () async {
      backend.markDeleted('p7');
      expect((await backend.leaderboard('padel', 'tashkent')).rows.map((r) => r.id), ['p1', 'p5', 'p8', 'p2']);
    });

    test('a confirmed result puts me on the board, in rows and as me', () async {
      final result =
          (await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: [(6, 4), (6, 4)])).result!;
      await backend.confirmScoreAs('p2', result.id);

      final after = await backend.leaderboard('padel', 'tashkent');
      final mine = (await backend.mySports()).singleWhere((s) => s.sportId == 'padel').rating!;
      expect(after.me, isNotNull);
      expect(after.me!.isMe, isTrue);
      expect(after.me!.id, kMeId);
      expect(after.me!.rating.rating, mine.rating);
      expect(after.me!.rating.ratedGames, 1);
      expect(after.rows.where((r) => r.isMe), hasLength(1));
      expect(after.rows[after.me!.position - 1].id, kMeId);
      final ratings = after.rows.map((r) => r.rating.rating).toList();
      expect(ratings, [...ratings]..sort((a, b) => b.compareTo(a)));
    });
  });

  group('after the game', () {
    Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));

    // gf1 (padel, hosted by me, with p1-p3) and gf3 (football, hosted by p1,
    // with me, p2, p3) ended yesterday evening in Tashkent.
    test('votes are stored, changeable and removable, and only mine are shown to me', () async {
      var game = await backend.vote('gf1', 'p1', true);
      expect(game.afterGame!.myVotes, {'p1': true});
      game = await backend.vote('gf1', 'p1', false);
      expect(game.afterGame!.myVotes, {'p1': false});
      await backend.voteAs('p2', 'gf1', 'p1', true);
      game = await backend.vote('gf1', 'p2', true);
      expect(game.afterGame!.myVotes, {'p1': false, 'p2': true}, reason: 'p2 voting for p1 is not mine');
      game = await backend.vote('gf1', 'p1', null);
      expect(game.afterGame!.myVotes, {'p2': true});
      expect((await backend.game('gf1')).afterGame!.myVotes, {'p2': true});
    });

    test('votes need another participant of a finished game, within 7 days', () async {
      expect(backend.vote('gf1', kMeId, true), joinError(JoinError.notFound));
      expect(backend.vote('gf1', 'p4', true), joinError(JoinError.notFound));
      expect(backend.vote('nope', 'p1', true), joinError(JoinError.notFound));
      // Two players of a game that has not started.
      final upcoming = (await backend.games('tashkent')).firstWhere((g) => g.participantIds.length > 1);
      final [first, second, ...] = upcoming.participantIds;
      expect(backend.voteAs(first, upcoming.id, second, true), joinError(JoinError.notFound));
      expect(backend.reportNoShowAs(first, upcoming.id, second, reported: true), joinError(JoinError.notFound));
      expect(upcoming.afterGame, isNull, reason: 'no after-game part before the end');
      backend.markDeleted('p3');
      expect(backend.vote('gf1', 'p3', true), joinError(JoinError.notFound));
      expect(backend.reportNoShow('gf1', 'p3', reported: true), joinError(JoinError.notFound));

      var now = utcNow;
      final timed = SampleBackend(utcNow: () => now);
      now = utcNow.add(const Duration(days: 6));
      expect((await timed.vote('gf1', 'p1', true)).afterGame!.myVotes, {'p1': true});
      now = utcNow.add(const Duration(days: 7));
      expect(timed.vote('gf1', 'p1', false), joinError(JoinError.scoreClosed));
    });

    test('no-show reports close 48 hours after the end', () async {
      // gf1 ended Saturday 19:30, 14.5 hours before now.
      var now = utcNow;
      final timed = SampleBackend(utcNow: () => now);
      now = utcNow.add(const Duration(hours: 33));
      expect((await timed.reportNoShow('gf1', 'p1', reported: true)).afterGame!.myNoShows, {'p1'});
      now = utcNow.add(const Duration(hours: 34));
      expect(timed.reportNoShow('gf1', 'p1', reported: false), joinError(JoinError.scoreClosed));
    });

    test('my own no-show reports show on the game, and can be undone', () async {
      var game = await backend.reportNoShow('gf3', 'p2', reported: true);
      expect(game.afterGame!.myNoShows, {'p2'});
      game = await backend.reportNoShow('gf3', 'p2', reported: false);
      expect(game.afterGame!.myNoShows, isEmpty);
    });

    test('a no-show majority lowers reliability once and notifies; withdrawing undoes it', () async {
      Future<int> score() async => (await backend.settings()).reliability.score;
      Future<int> notices() async => (await backend.inbox()).where((n) => n.kind == 'no_show_recorded').length;
      final before = await score();

      // gf3: three others, so a majority is two of them.
      await backend.reportNoShowAs('p1', 'gf3', kMeId, reported: true);
      expect(await score(), before, reason: 'one report of three is no majority');
      expect(await notices(), 0);

      await backend.reportNoShowAs('p2', 'gf3', kMeId, reported: true);
      expect(await score(), before + ReliabilityKind.noShow.delta);
      expect(await notices(), 1);
      final notice = (await backend.inbox()).firstWhere((n) => n.kind == 'no_show_recorded');
      expect(notice.category, 'games');
      expect(notice.payload['game_id'], 'gf3');
      expect(notice.payload['sport_id'], 'football');
      expect(notice.route, '/games/gf3');

      await backend.reportNoShowAs('p3', 'gf3', kMeId, reported: true);
      expect(await score(), before + ReliabilityKind.noShow.delta, reason: 'once per game');
      expect(await notices(), 1);

      await backend.reportNoShowAs('p3', 'gf3', kMeId, reported: false);
      expect(await score(), before + ReliabilityKind.noShow.delta, reason: 'two of three is still a majority');
      await backend.reportNoShowAs('p2', 'gf3', kMeId, reported: false);
      expect(await score(), before, reason: 'below the majority again');
    });

    test('a no-show majority freezes a pending score and blocks a new one', () async {
      // gf2's pending score has me in it.
      await backend.reportNoShowAs('p1', 'gf2', kMeId, reported: true);
      await backend.reportNoShowAs('p3', 'gf2', kMeId, reported: true);
      final result = (await backend.game('gf2')).result!;
      expect(result.status, ResultStatus.disputed);
      expect(result.disputeReason, 'no_show');
      expect((await backend.inbox()).where((n) => n.kind == 'score_disputed'), hasLength(1));

      // gf1 has no score yet: p3, recorded as not there, cannot be in one.
      await backend.reportNoShowAs('p1', 'gf1', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf1', 'p3', reported: true);
      expect(
        backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: const [(6, 4)]),
        joinError(JoinError.invalidArgument),
      );
      expect((await backend.enterScore('gf1', sideA: [kMeId], sideB: ['p2'], sets: const [(6, 4)])).result, isNotNull);
    });

    test('a no-show majority flags a confirmed score', () async {
      await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: const [(6, 4)]);
      await backend.confirmScoreAs('p2', 'r-gf1');
      await backend.reportNoShowAs('p1', 'gf1', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf1', 'p3', reported: true);
      final result = (await backend.game('gf1')).result!;
      expect(result.status, ResultStatus.confirmed);
      expect(result.flaggedNoShow, isTrue);
    });

    test('reporting a player: once per player and game while open', () async {
      await backend.reportPlayer('p1', gameId: 'gf1', reason: ReportReason.falseScore, details: 'Not 6-0');
      expect(
        backend.reportPlayer('p1', gameId: 'gf1', reason: ReportReason.other),
        joinError(JoinError.alreadyReported),
      );
      // Another game, or none, is another report.
      await backend.reportPlayer('p1', gameId: 'gf3', reason: ReportReason.language);
      await backend.reportPlayer('p1', reason: ReportReason.aggression);
      expect(backend.reportPlayer('p1', reason: ReportReason.other), joinError(JoinError.alreadyReported));

      expect(backend.reportPlayer(kMeId, reason: ReportReason.other), joinError(JoinError.invalidArgument));
      expect(
        backend.reportPlayer('p2', reason: ReportReason.other, details: 'x' * 501),
        joinError(JoinError.invalidArgument),
      );
      await backend.reportPlayer('p2', reason: ReportReason.other, details: '  ${'x' * 500}  ');
      expect(backend.reportPlayer('p4', gameId: 'gf1', reason: ReportReason.other), joinError(JoinError.notFound));
      expect(backend.reportPlayer('nobody', reason: ReportReason.other), joinError(JoinError.notFound));
      backend.markDeleted('p5');
      expect(backend.reportPlayer('p5', reason: ReportReason.other), joinError(JoinError.notFound));
    });

    test('a recorded no-show takes the game-completed credit, and gives it back with the penalty', () async {
      backend.recordReliability(kMeId, ReliabilityKind.gameCompleted, 'gf3');
      final before = await backend.profile(kMeId);

      await backend.reportNoShowAs('p1', 'gf3', kMeId, reported: true);
      await backend.reportNoShowAs('p2', 'gf3', kMeId, reported: true);
      final recorded = await backend.profile(kMeId);
      expect(
        recorded.reliability.score,
        before.reliability.score - ReliabilityKind.gameCompleted.delta + ReliabilityKind.noShow.delta,
      );
      expect(recorded.gamesPlayed, before.gamesPlayed - 1);

      await backend.reportNoShowAs('p2', 'gf3', kMeId, reported: false);
      final undone = await backend.profile(kMeId);
      expect(undone.reliability.score, before.reliability.score);
      expect(undone.gamesPlayed, before.gamesPlayed);
    });

    test('a host the venue already marked no-show is not penalised again for the game', () async {
      var now = utcNow;
      final timed = SampleBackend(utcNow: () => now);
      // g4: hosted by p7, with p5, p8 and p1, on a booking.
      final g4 = await timed.game('g4');
      expect(g4.hostId, 'p7');
      timed.recordReliability('p7', ReliabilityKind.noShow, g4.bookingId!);
      final hostBefore = (await timed.profile('p7')).reliability.score;
      final p1Before = (await timed.profile('p1')).reliability.score;
      // Just after the end.
      now = utcNow.add(g4.end.difference(venueNow(cityById(g4.cityId), utcNow: utcNow))).add(const Duration(minutes: 1));

      await timed.reportNoShowAs('p5', 'g4', 'p7', reported: true);
      await timed.reportNoShowAs('p8', 'g4', 'p7', reported: true);
      expect((await timed.profile('p7')).reliability.score, hostBefore);

      // The same majority does count against a player the venue did not mark.
      await timed.reportNoShowAs('p5', 'g4', 'p1', reported: true);
      await timed.reportNoShowAs('p8', 'g4', 'p1', reported: true);
      expect((await timed.profile('p1')).reliability.score, p1Before + ReliabilityKind.noShow.delta);
    });

    test('sportsmanship shows from five votes', () async {
      expect((await backend.profile('p1')).sportsmanship.votes, 0);
      await backend.vote('gf1', 'p1', true);
      await backend.voteAs('p2', 'gf1', 'p1', true);
      await backend.voteAs('p3', 'gf1', 'p1', false);
      await backend.voteAs('p2', 'gf3', 'p1', true);
      var votes = (await backend.profile('p1')).sportsmanship;
      expect(votes.votes, 4);
      expect(votes.percent, isNull);

      await backend.voteAs('p3', 'gf3', 'p1', true);
      votes = (await backend.profile('p1')).sportsmanship;
      expect(votes.votes, 5);
      expect(votes.percent, 80);
    });
  });

  group('teams', () {
    Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));
    TeamDraft draft(String name, {TeamJoinPolicy joinPolicy = TeamJoinPolicy.open}) =>
        TeamDraft(name: name, sportId: 'padel', cityId: 'tashkent', joinPolicy: joinPolicy);

    test('every seeded team has a known sport and city, a sample captain and 2 to 4 members, never me', () async {
      final sportIds = (await backend.sports()).map((s) => s.id).toSet();
      final playerIds = kSamplePlayers.map((p) => p.id).toSet();
      expect(kTeamSeeds, hasLength(8));
      for (final seed in kTeamSeeds) {
        expect(sportIds, contains(seed.sportId), reason: seed.id);
        expect(kCities.map((c) => c.id), contains(seed.cityId), reason: seed.id);
        expect(playerIds, containsAll([seed.captainId, ...seed.memberIds]), reason: seed.id);
        expect(seed.memberIds.length, inInclusiveRange(2, 4), reason: seed.id);
        expect(seed.memberIds, isNot(contains(seed.captainId)), reason: seed.id);
        final team = await backend.team(seed.id);
        expect(team.memberCount, seed.memberIds.length + 1);
        expect(team.members.map((m) => m.id), [seed.captainId, ...seed.memberIds]);
        expect(team.myStatus, isNull);
      }
    });

    test('a city lists its teams by size, then name', () async {
      expect((await backend.teams('tashkent')).map((t) => t.name), [
        'Chilonzor FC',
        'Yunusobod Padel',
        'Hoops TAS',
        'Tennis Crew',
      ]);
    });

    test('an invite and a join request reach the inbox and open the team', () async {
      final theirs = await backend.createTeamAs('p1', draft('Aziz Squad'));
      await backend.inviteToTeamAs('p1', theirs.id, kMeId);
      final invite = (await backend.inbox()).firstWhere((n) => n.kind == 'team_invite');
      expect(invite.category, 'teams');
      expect(invite.payload, {'team_id': theirs.id, 'team_name': 'Aziz Squad', 'actor_name': 'Aziz'});
      expect(invite.route, '/teams/${theirs.id}');
      // Inviting again while the invite is open sends nothing new.
      await backend.inviteToTeamAs('p1', theirs.id, kMeId);
      expect((await backend.inbox()).where((n) => n.kind == 'team_invite'), hasLength(1));

      final mine = await backend.createTeam(draft('Night Owls', joinPolicy: TeamJoinPolicy.approval));
      await backend.joinTeamAs('p2', mine.id);
      final ask = (await backend.inbox()).firstWhere((n) => n.kind == 'team_join_request');
      expect(ask.payload, {'team_id': mine.id, 'team_name': 'Night Owls', 'actor_name': 'Dilnoza'});
      expect(ask.route, '/teams/${mine.id}');

      // Muted: nothing arrives.
      await backend.saveSettings(const CommunitySettings(mutedCategories: {'teams'}));
      await backend.joinTeamAs('p4', mine.id);
      expect((await backend.inbox()).where((n) => n.kind == 'team_join_request'), hasLength(1));
    });

    test('a deleted captain hands the team to the member who joined first', () async {
      backend.markDeleted('p1');
      final team = await backend.team('tm1');
      expect(team.captainId, 'p5');
      expect(team.members.map((m) => m.id), ['p5', 'p7', 'p8']);
      expect(team.members.first.captain, isTrue);
      // Their memberships go too.
      expect((await backend.team('tm2')).members.map((m) => m.id), isNot(contains('p1')));

      // I joined first: I am the captain now, and hear about it.
      final theirs = await backend.createTeamAs('p2', draft('Dilnoza Squad'));
      await backend.joinTeam(theirs.id);
      await backend.joinTeamAs('p4', theirs.id);
      backend.markDeleted('p2');
      final mine = await backend.team(theirs.id);
      expect(mine.captainId, kMeId);
      expect(mine.myStatus, MyTeamStatus.captain);
      expect(mine.members.map((m) => m.id), [kMeId, 'p4']);
      final notice = (await backend.inbox()).firstWhere((n) => n.kind == 'team_captain');
      expect(notice.payload, {'team_id': theirs.id, 'team_name': 'Dilnoza Squad', 'actor_name': 'Dilnoza'});
      expect(notice.route, '/teams/${theirs.id}');

      // Nobody left: the team goes.
      final solo = await backend.createTeamAs('p4', draft('Madina Solo'));
      backend.markDeleted('p4');
      expect(backend.team(solo.id), joinError(JoinError.notFound));
    });

    test('the admin removes a team, with an audit entry', () async {
      final theirs = await backend.createTeamAs('p1', draft('Aziz Squad'));
      final listed = (await backend.admin.review()).teams;
      expect(listed.first.id, theirs.id, reason: 'newest first');
      expect(listed.map((t) => t.id), containsAll([for (final s in kTeamSeeds) s.id]));

      await backend.admin.deleteTeam(theirs.id);
      expect(backend.team(theirs.id), joinError(JoinError.notFound));
      final entry = (await backend.admin.auditLog()).first;
      expect(entry.action, 'team_deleted');
      expect(entry.entity, 'team');
      expect(entry.entityId, theirs.id);
      expect(entry.before!['name'], 'Aziz Squad');
      expect(entry.after, isNull);
      expect(
        backend.admin.deleteTeam(theirs.id),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.notFound)),
      );
    });
  });

  group('team games', () {
    Matcher joinError(JoinError error) => throwsA(isA<JoinException>().having((e) => e.error, 'error', error));
    // Monday 23 Nov 2026, 07:00 in Tashkent: 21 hours after the clock.
    final start = DateTime.utc(2026, 11, 23, 7);
    TeamDraft runners(String name, {String cityId = 'tashkent'}) =>
        TeamDraft(name: name, sportId: 'running', cityId: cityId);
    GameDraft teamRun(String? teamId, {int? openHoursBefore, String sportId = 'running', int spots = 4}) => GameDraft(
      sportId: sportId,
      spots: spots,
      meetingPoint: 'Bunyodkor park, main gate',
      start: start,
      end: start.add(const Duration(hours: 1)),
      teamId: teamId,
      openHoursBefore: openHoursBefore,
    );
    Future<List<String>> listed(SampleBackend b, String userId) async =>
        [for (final g in await b.gamesAs(userId, 'tashkent')) g.id];

    test('a team game is listed for its members only, and the members hear about it', () async {
      final team = await backend.createTeamAs('p1', runners('Aziz Runners'));
      await backend.joinTeam(team.id);
      await backend.joinTeamAs('p2', team.id);
      final game = await backend.createAs('p1', teamRun(team.id));

      // Read as invite-only, as old builds do; the team is what marks it.
      expect(game.visibility, GameVisibility.inviteOnly);
      expect(game.team?.id, team.id);
      expect(game.team?.name, 'Aziz Runners');
      expect(game.publicFrom, isNull);

      expect((await backend.games('tashkent')).map((g) => g.id), contains(game.id));
      expect(await listed(backend, 'p2'), contains(game.id));
      expect(await listed(backend, 'p3'), isNot(contains(game.id)));
      await expectLater(backend.joinAs('p3', game.id), joinError(JoinError.notFound));
      await expectLater(backend.requestToJoinAs('p3', game.id), joinError(JoinError.notFound));
      expect((await backend.joinAs('p2', game.id)).participantIds, ['p1', 'p2']);
      expect((await backend.join(game.id)).participantIds, ['p1', 'p2', kMeId]);

      final posted = (await backend.inbox()).firstWhere((n) => n.kind == 'team_game_posted');
      expect(posted.category, 'teams');
      expect(posted.payload, {
        'game_id': game.id,
        'sport_id': 'running',
        'starts_local': '2026-11-23T07:00:00',
        'team_id': team.id,
        'team_name': 'Aziz Runners',
      });
      expect(posted.route, '/games/${game.id}');
    });

    test('a team game opens to everyone at its lead time, while spots remain', () async {
      var clock = utcNow;
      final timed = SampleBackend(utcNow: () => clock);
      final team = await timed.createTeam(runners('Night Runners'));
      final game = await timed.create(teamRun(team.id, openHoursBefore: 12, spots: 3));
      // 12 hours before 07:00 on Monday, in Tashkent wall-clock time.
      expect(game.publicFrom, DateTime.utc(2026, 11, 22, 19));
      expect(await listed(timed, 'p3'), isNot(contains(game.id)));
      await expectLater(timed.joinAs('p3', game.id), joinError(JoinError.notFound));

      // 20:00 in Tashkent.
      clock = DateTime.utc(2026, 11, 22, 15);
      expect(await listed(timed, 'p3'), contains(game.id));
      expect((await timed.joinAs('p3', game.id)).participantIds, [kMeId, 'p3']);
      // The rating and level rules still apply, and the JSON still says invite-only.
      final last = await timed.joinAs('p4', game.id);
      expect(last.visibility, GameVisibility.inviteOnly);
      // Full: it leaves the open list.
      expect(await listed(timed, 'p5'), isNot(contains(game.id)));
      await expectLater(timed.joinAs('p5', game.id), joinError(JoinError.full));

      // A lead time longer than the time left opens the game at once.
      final soon = await timed.create(
        GameDraft(
          sportId: 'running',
          spots: 4,
          meetingPoint: 'Riverside',
          start: DateTime.utc(2026, 11, 23, 9),
          end: DateTime.utc(2026, 11, 23, 10),
          teamId: team.id,
          openHoursBefore: 48,
        ),
      );
      expect(await listed(timed, 'p5'), contains(soon.id));
    });

    test('only the captain posts a team game, in the team sport and city', () async {
      final team = await backend.createTeamAs('p1', runners('Aziz Runners'));
      await backend.joinTeam(team.id);
      await expectLater(backend.create(teamRun(team.id)), joinError(JoinError.forbidden));
      await expectLater(backend.createAs('p1', teamRun('nope')), joinError(JoinError.notFound));
      await expectLater(backend.createAs('p1', teamRun(team.id, sportId: 'gym')), joinError(JoinError.invalidArgument));
      await expectLater(
        backend.createAs('p1', teamRun(null, openHoursBefore: 12)),
        joinError(JoinError.invalidArgument),
      );
      await expectLater(
        backend.createAs('p1', teamRun(team.id, openHoursBefore: 6)),
        joinError(JoinError.invalidArgument),
      );
      // A meeting point is in Tashkent; the team is in Almaty.
      final almaty = await backend.createTeamAs('p1', runners('Alatau Runners', cityId: 'almaty'));
      await expectLater(backend.createAs('p1', teamRun(almaty.id)), joinError(JoinError.invalidArgument));
    });

    test('the team page lists the games the viewer may see and counts them all', () async {
      final theirs = await backend.createTeamAs('p1', runners('Aziz Runners'));
      final game = await backend.createAs('p1', teamRun(theirs.id));
      // Not a member: the count, but not the game.
      var team = await backend.team(theirs.id);
      expect(team.upcomingGames, 1);
      expect(team.games, isEmpty);
      expect((await backend.teams('tashkent')).firstWhere((t) => t.id == theirs.id).upcomingGames, 1);

      await backend.joinTeam(theirs.id);
      team = await backend.team(theirs.id);
      expect(team.games.map((g) => g.id), [game.id]);
      expect(team.games.single.team?.name, 'Aziz Runners');
    });

    test('a deleted team leaves an invite-only game that never opens', () async {
      var clock = utcNow;
      final timed = SampleBackend(utcNow: () => clock);
      final team = await timed.createTeamAs('p1', runners('Aziz Runners'));
      await timed.joinTeamAs('p2', team.id);
      final game = await timed.createAs('p1', teamRun(team.id, openHoursBefore: 12));
      await timed.joinAs('p2', game.id);
      await timed.admin.deleteTeam(team.id);

      clock = DateTime.utc(2026, 11, 22, 15);
      final seen = (await timed.gamesAs('p2', 'tashkent')).firstWhere((g) => g.id == game.id);
      expect(seen.team, isNull);
      expect(seen.publicFrom, isNull);
      expect(seen.visibility, GameVisibility.inviteOnly);
      expect(await listed(timed, 'p3'), isNot(contains(game.id)));
      await expectLater(timed.joinAs('p3', game.id), joinError(JoinError.notFound));
    });

    test('a member the host removed does not get back in through the team', () async {
      final team = await backend.createTeam(runners('Night Runners'));
      await backend.joinTeamAs('p2', team.id);
      final game = await backend.create(teamRun(team.id));
      await backend.joinAs('p2', game.id);
      await backend.removeParticipant(game.id, 'p2');
      await expectLater(backend.joinAs('p2', game.id), joinError(JoinError.notFound));
    });
  });
}

String _courtOf(String bookingId, SampleBackend backend) {
  // Sample games are seeded from kGameSeeds, in order, as bookings b1, b2, …
  final index = int.parse(bookingId.substring(1)) - 1;
  return kGameSeeds[index].courtId;
}
