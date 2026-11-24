import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/supabase/errors.dart';
import 'package:actra/data/supabase/mappers.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/pricing.dart';
import 'package:actra/domain/slot_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers.dart';

const me = '11111111-1111-1111-1111-111111111111';
const other = '22222222-2222-2222-2222-222222222222';

/// A venue as PostgREST returns it, with its hours, courts, rules embedded.
Map<String, dynamic> venueRow() => {
  'id': 'venue-1',
  'city_id': 'tashkent',
  'name_uz': 'Lochin',
  'name_ru': 'Лочин',
  'name_en': 'Lochin',
  'description_uz': null,
  'description_ru': 'Два корта',
  'description_en': null,
  'address_uz': 'A',
  'address_ru': 'Б',
  'address_en': 'C',
  'district_uz': 'Yunusobod',
  'district_ru': 'Юнусабад',
  'district_en': 'Yunusabad',
  'phone': '+998 71 200 00 01',
  'amenities': ['parking', 'showers'],
  'color_seed': 2,
  // Open Monday to Saturday; there is no Sunday row.
  'working_hours': [
    for (var d = 1; d <= 6; d++) {'weekday': d, 'closed': false, 'open_minute': 420, 'close_minute': 1380},
  ],
  'courts': [
    {
      'id': 'court-b',
      'sport_id': 'basketball',
      'name_en': 'Second',
      'slot_minutes': 60,
      'base_price': 200000,
      'indoor': false,
      'sort_order': 1,
      'price_rules': <Map<String, dynamic>>[],
      'working_hours': [
        {'weekday': 1, 'closed': true, 'open_minute': 0, 'close_minute': 0},
        {'weekday': 2, 'closed': false, 'open_minute': 600, 'close_minute': 720},
      ],
    },
    {
      'id': 'court-a',
      'sport_id': 'padel',
      'name_uz': 'Kort 1',
      'name_ru': 'Корт 1',
      'name_en': 'Court 1',
      'slot_minutes': 90,
      'base_price': 180000,
      'indoor': true,
      'sort_order': 0,
      // Deliberately out of order: sort_order decides which rule wins.
      'price_rules': [
        {
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
          'from_minute': 0,
          'to_minute': 1440,
          'price': 111,
          'sort_order': 1,
        },
        {
          'weekdays': [1, 2, 3, 4, 5],
          'from_minute': 1080,
          'to_minute': 1380,
          'price': 250000,
          'sort_order': 0,
        },
      ],
      'working_hours': <Map<String, dynamic>>[],
    },
  ],
};

Map<String, dynamic> bookingJson({String status = 'confirmed', String userId = me}) => {
  'id': 'booking-1',
  'user_id': userId,
  'venue_id': 'venue-1',
  'court_id': 'court-a',
  'starts_local': '2026-11-23T17:30:00',
  'ends_local': '2026-11-23T20:30:00',
  'slot_count': 2,
  'total_price': 430000,
  'currency': 'UZS',
  'status': status,
  'payment_method': 'pay_at_venue',
  'payment_status': 'unpaid',
  'hold_expires_local': status == 'held' ? '2026-11-22T20:05:00' : null,
  'late_cancellation': false,
  'players': 4,
  'note': null,
};

void main() {
  group('venue', () {
    late Venue venue;
    setUp(() => venue = venueFromRow(venueRow()));

    test('texts keep one value per language and fall back as usual', () {
      expect(venue.name.resolve('ru'), 'Лочин');
      expect(venue.description.uz, isNull);
      expect(venue.description.resolve('uz'), 'Два корта');
      expect(venue.amenities, ['parking', 'showers']);
      expect(venue.colorSeed, 2);
      expect(venue.cityId, 'tashkent');
    });

    test('a weekday without a row is closed', () {
      expect(venue.hours.keys.toSet(), {1, 2, 3, 4, 5, 6, 7});
      expect(venue.hours[1]!.openMinute, 420);
      expect(venue.hours[6]!.closeMinute, 1380);
      expect(venue.hours[7], isNull);
      expect(generateSlots(venue, venue.court('court-a'), DateTime.utc(2026, 11, 29)), isEmpty);
    });

    test('courts come in sort order with their venue id', () {
      expect(venue.courts.map((c) => c.id), ['court-a', 'court-b']);
      expect(venue.courts.every((c) => c.venueId == 'venue-1'), isTrue);
      expect(venue.sportIds, ['padel', 'basketball']);
      expect(venue.court('court-a').indoor, isTrue);
    });

    test('slots and prices computed from the mapped venue match the engine', () {
      final court = venue.court('court-a');
      final slots = generateSlots(venue, court, monday);
      expect(slots.first.start, DateTime.utc(2026, 11, 23, 7));
      expect(slots.last.start, DateTime.utc(2026, 11, 23, 20, 30));
      expect(slots.length, 10);
      // The evening rule (sort_order 0) beats the catch-all (sort_order 1).
      expect(priceForSlot(court, slotAt(monday, 19, 0)), 250000);
      expect(priceForSlot(court, slotAt(monday, 10, 0)), 111);
    });

    test('a court override replaces the venue hours, and closed means closed', () {
      final court = venue.court('court-b');
      expect(court.hoursOverride.containsKey(1), isTrue);
      expect(court.hoursOverride[1], isNull);
      expect(generateSlots(venue, court, monday), isEmpty);
      // Tuesday 10:00-12:00 in 60-minute slots.
      expect(generateSlots(venue, court, DateTime.utc(2026, 11, 24)).length, 2);
      // Wednesday has no override: the venue's 07:00-23:00.
      expect(generateSlots(venue, court, DateTime.utc(2026, 11, 25)).length, 16);
    });
  });

  group('booking', () {
    test('wall-clock strings become UTC-flagged times', () {
      final booking = bookingFromJson(bookingJson(), myUserId: me);
      expect(booking.start, DateTime.utc(2026, 11, 23, 17, 30));
      expect(booking.end, DateTime.utc(2026, 11, 23, 20, 30));
      expect(booking.start.isUtc, isTrue);
      expect(booking.slotCount, 2);
      expect(booking.totalPrice, 430000);
      expect(booking.players, 4);
      expect(booking.holdExpiresAt, isNull);
      expect(booking.paymentMethod, PaymentMethod.payAtVenue);
      expect(booking.paymentStatus, PaymentStatus.unpaid);
    });

    test('a hold carries its expiry in venue time', () {
      final held = bookingFromJson(bookingJson(status: 'held'), myUserId: me);
      expect(held.status, BookingStatus.held);
      expect(held.holdExpiresAt, DateTime.utc(2026, 11, 22, 20, 5));
    });

    test('every backend status has a meaning in the app', () {
      const expected = {
        'held': BookingStatus.held,
        'confirmed': BookingStatus.confirmed,
        'cancelled_by_player': BookingStatus.cancelledByPlayer,
        'cancelled_by_venue': BookingStatus.cancelledByVenue,
        'completed': BookingStatus.completed,
        'unverified': BookingStatus.completed,
        'paid': BookingStatus.paid,
        'no_show': BookingStatus.noShow,
        'released': BookingStatus.released,
      };
      for (final entry in expected.entries) {
        expect(
          bookingFromJson(bookingJson(status: entry.key), myUserId: me).status,
          entry.value,
          reason: entry.key,
        );
      }
      expect(() => bookingStatusOf('teleported'), throwsFormatException);
    });

    test('my own id becomes "me"; other ids are kept', () {
      expect(bookingFromJson(bookingJson(), myUserId: me).userId, kMeId);
      expect(bookingFromJson(bookingJson(userId: other), myUserId: me).userId, other);
      expect(bookingFromJson(bookingJson(), myUserId: null).userId, me);
    });

    test('availability rows', () {
      final slot = slotFromRow({
        'starts_local': '2026-11-23T07:00:00',
        'ends_local': '2026-11-23T08:30:00',
        'price': 180000,
        'state': 'mine',
      });
      expect(slot.time, slotAt(monday, 7, 0));
      expect(slot.price, 180000);
      expect(slot.state, SlotState.mine);
      for (final entry in {'free': SlotState.free, 'taken': SlotState.taken, 'past': SlotState.past}.entries) {
        expect(
          slotFromRow({
            'starts_local': '2026-11-23T07:00:00',
            'ends_local': '2026-11-23T08:30:00',
            'price': 1,
            'state': entry.key,
          }).state,
          entry.value,
        );
      }
    });

    test('times are sent without a zone', () {
      expect(isoLocal(DateTime.utc(2026, 11, 23, 7, 5)), '2026-11-23T07:05:00');
      expect(isoDate(DateTime.utc(2026, 1, 3, 23, 59)), '2026-01-03');
      expect(wallClock('2026-11-23'), DateTime.utc(2026, 11, 23));
    });
  });

  group('games and players', () {
    final json = {
      'id': 'game-1',
      'sport_id': 'padel',
      'city_id': 'tashkent',
      'venue_id': 'venue-1',
      'host_id': other,
      'starts_local': '2026-11-23T19:00:00',
      'ends_local': '2026-11-23T20:30:00',
      'spots': 4,
      'min_level': 2,
      'max_level': 4,
      'price_per_player': 62500,
      'booking_id': 'booking-9',
      'note': null,
      'participant_ids': [other, me],
    };

    test('a game keeps the participant order and marks me', () {
      final game = gameFromJson(json, myUserId: me);
      expect(game.hostId, other);
      expect(game.participantIds, [other, kMeId]);
      expect(game.spotsLeft, 2);
      expect(game.start, DateTime.utc(2026, 11, 23, 19));
      expect(game.minLevel, 2);
      expect(game.pricePerPlayer, 62500);
    });

    test('a game I host has me as host', () {
      final game = gameFromJson({
        ...json,
        'host_id': me,
        'participant_ids': [me],
      }, myUserId: me);
      expect(game.hostId, kMeId);
      expect(game.participantIds, [kMeId]);
    });

    test('a player with levels', () {
      final player = playerFromRow({
        'id': other,
        'full_name': 'Aziz',
        'player_levels': [
          {'sport_id': 'padel', 'level': 3},
          {'sport_id': 'football', 'level': 4},
        ],
      }, myUserId: me);
      expect(player.name, 'Aziz');
      expect(player.levelFor('padel'), 3);
      expect(player.levelFor('tennis'), 1);
      expect(playerFromRow({'id': me, 'full_name': null, 'player_levels': null}, myUserId: me).id, kMeId);
    });
  });

  group('catalog', () {
    test('sport, banner and tournament rows', () {
      final sport = sportFromRow({
        'id': 'padel',
        'name_uz': 'Padel',
        'name_ru': 'Падел',
        'name_en': 'Padel',
        'icon_key': 'padel',
        'bookable': true,
        'competitive_rating': true,
        'default_players': 4,
      });
      expect(sport.competitiveRating, isTrue);
      expect(sport.defaultPlayers, 4);

      final banner = bannerFromRow({
        'id': 'b',
        'title_en': 'Book',
        'subtitle_ru': 'Сразу',
        'url': 'https://example.com',
        'color_seed': 3,
      });
      expect(banner.title.en, 'Book');
      expect(banner.subtitle.resolve('en'), 'Сразу');

      final tournament = tournamentFromRow({
        'id': 't',
        'city_id': 'almaty',
        'sport_id': 'tennis',
        'title_en': 'Almaty Open',
        'starts_on': '2026-12-07',
        'ends_on': '2026-12-09',
        'min_fee': 15000,
        'max_fee': 25000,
        'slots_total': 24,
        'slots_filled': 9,
        'venues': {'name_uz': 'Alatau', 'name_ru': 'Алатау', 'name_en': 'Alatau'},
      });
      expect(tournament.start, DateTime.utc(2026, 12, 7));
      expect(tournament.end, DateTime.utc(2026, 12, 9));
      expect(tournament.venueName.ru, 'Алатау');
      expect(tournament.slotsFilled, 9);
    });
  });

  group('errors', () {
    PostgrestException raised(String message) => PostgrestException(message: message, code: 'P0001');

    test('rule violations become the exceptions the screens handle', () {
      const booking = {
        'slot_taken': BookingError.slotTaken,
        'not_contiguous': BookingError.notContiguous,
        'empty_selection': BookingError.emptySelection,
        'in_past': BookingError.inPast,
        'too_far_ahead': BookingError.tooFarAhead,
        'too_many_bookings': BookingError.tooManyBookings,
        'hold_expired': BookingError.holdExpired,
        'not_found': BookingError.notFound,
        'not_cancellable': BookingError.notCancellable,
      };
      for (final entry in booking.entries) {
        expect(bookingExceptionFor(raised(entry.key)).error, entry.value, reason: entry.key);
      }
      const join = {
        'full': JoinError.full,
        'already_joined': JoinError.alreadyJoined,
        'level_out_of_range': JoinError.levelOutOfRange,
        'not_participant': JoinError.notParticipant,
        'host_cannot_leave': JoinError.hostCannotLeave,
      };
      for (final entry in join.entries) {
        expect(joinExceptionFor(raised(entry.key)).error, entry.value, reason: entry.key);
      }
    });

    test('anything else is "unavailable", never a crash', () async {
      expect(bookingExceptionFor(raised('JWT expired')).error, BookingError.unavailable);
      expect(bookingExceptionFor(Exception('no connection')).error, BookingError.unavailable);
      expect(joinExceptionFor(StateError('boom')).error, JoinError.unavailable);
      // An engine error passes through untouched.
      expect(bookingExceptionFor(const BookingException(BookingError.slotTaken)).error, BookingError.slotTaken);

      await expectLater(
        guardBooking<void>(() async => throw raised('slot_taken')),
        throwsA(isA<BookingException>().having((e) => e.error, 'error', BookingError.slotTaken)),
      );
      await expectLater(
        guardJoin<void>(() async => throw Exception('offline')),
        throwsA(isA<JoinException>().having((e) => e.error, 'error', JoinError.unavailable)),
      );
      expect(await guardBooking(() async => 7), 7);
    });
  });

  group('community', () {
    const reliabilityJson = {'score': 86, 'badge': 'reliable'};

    Map<String, dynamic> member(String id, String name, {int? level = 3}) => {
      'id': id,
      'name': name,
      'level': level,
      'reliability': reliabilityJson,
    };

    test('a game on a map point has no venue, with participants and join requests', () {
      final game = gameFromJson({
        'id': 'game-2',
        'sport_id': 'running',
        'city_id': 'tashkent',
        'venue_id': null,
        'host_id': me,
        'kind': 'map_point',
        'visibility': 'invite_only',
        'status': 'open',
        'starts_local': '2026-11-23T07:00:00',
        'ends_local': '2026-11-23T08:00:00',
        'spots': 6,
        'min_level': 1,
        'max_level': 5,
        'price_per_player': null,
        'booking_id': null,
        'note': 'Easy pace',
        'meeting_point': 'Bunyodkor park, main gate',
        'meeting_lat': 41,
        'meeting_lng': 69.25,
        'distance_km': 5,
        'pace': '6:00/km',
        'my_status': 'host',
        'participant_ids': [me, other],
        'participants': [member(me, 'Sardor'), member(other, 'Aziz', level: null)],
        'join_requests': [
          {
            'id': 'req-1',
            'user_id': '33333333-3333-3333-3333-333333333333',
            'name': 'Madina',
            'level': 4,
            'reliability': {'score': 60, 'badge': 'limited'},
            'created_at': '2026-11-22T05:30:00+00:00',
          },
        ],
      }, myUserId: me);

      expect(game.kind, GameKind.mapPoint);
      expect(game.visibility, GameVisibility.inviteOnly);
      expect(game.venueId, isNull);
      expect(game.cancelled, isFalse);
      expect(game.meetingPoint, 'Bunyodkor park, main gate');
      expect(game.meetingLat, 41.0);
      expect(game.meetingLng, 69.25);
      expect(game.distanceKm, 5.0);
      expect(game.pace, '6:00/km');
      expect(game.myStatus, MyGameStatus.host);
      expect(game.hostId, kMeId);
      expect(game.participantIds, [kMeId, other]);
      expect(game.participants.map((m) => m.id), [kMeId, other]);
      expect(game.participants.first.reliability.badge, ReliabilityBadge.reliable);
      expect(game.participants.first.reliability.score, 86);
      expect(game.participants.last.level, 1, reason: 'no level counts as 1');
      final request = game.joinRequests.single;
      expect(request.id, 'req-1');
      expect(request.member.id, '33333333-3333-3333-3333-333333333333');
      expect(request.member.name, 'Madina');
      expect(request.member.level, 4);
      expect(request.member.reliability.badge, ReliabilityBadge.limited);
      expect(request.createdAt, DateTime.utc(2026, 11, 22, 5, 30));
    });

    test('a game for a player who is not the host has no join requests and a status', () {
      final base = {
        'id': 'g',
        'sport_id': 'padel',
        'city_id': 'tashkent',
        'venue_id': 'venue-1',
        'host_id': other,
        'starts_local': '2026-11-23T19:00:00',
        'ends_local': '2026-11-23T20:30:00',
        'spots': 4,
        'participant_ids': [other],
      };
      expect(gameFromJson({...base, 'my_status': 'invited'}, myUserId: me).myStatus, MyGameStatus.invited);
      final asked = gameFromJson({...base, 'my_status': 'requested', 'my_request_id': 'req-9'}, myUserId: me);
      expect(asked.myStatus, MyGameStatus.requested);
      expect(asked.myRequestId, 'req-9');
      expect(gameFromJson(base, myUserId: me).myRequestId, isNull);
      expect(gameFromJson({...base, 'my_status': 'participant'}, myUserId: me).myStatus, MyGameStatus.participant);
      final plain = gameFromJson(base, myUserId: me);
      expect(plain.myStatus, isNull);
      expect(plain.kind, GameKind.booked);
      expect(plain.visibility, GameVisibility.public);
      expect(plain.joinRequests, isEmpty);
      expect(plain.participants, isEmpty);
      expect(gameFromJson({...base, 'status': 'cancelled'}, myUserId: me).cancelled, isTrue);
    });

    test('a game request keeps the interested players in order and marks me', () {
      final request = gameRequestFromJson({
        'id': 'r1',
        'sport_id': 'padel',
        'city_id': 'tashkent',
        'host_id': other,
        'host_name': 'Aziz',
        'venue_id': null,
        'area': 'Yunusobod',
        'starts_local': '2026-11-24T18:00:00',
        'ends_local': '2026-11-24T21:00:00',
        'players_needed': 3,
        'min_level': 2,
        'max_level': 4,
        'note': null,
        'status': 'open',
        'game_id': null,
        'created_at': '2026-11-22T05:00:00+00:00',
        'interested': [member(other, 'Aziz'), member(me, 'Sardor')],
        'interested_count': 2,
        'my_status': 'interested',
      }, myUserId: me);
      expect(request.hostId, other);
      expect(request.hostName, 'Aziz');
      expect(request.area, 'Yunusobod');
      expect(request.venueId, isNull);
      expect(request.start, DateTime.utc(2026, 11, 24, 18));
      expect(request.end, DateTime.utc(2026, 11, 24, 21));
      expect(request.playersNeeded, 3);
      expect(request.minLevel, 2);
      expect(request.status, GameRequestStatus.open);
      expect(request.interested.map((m) => m.id), [other, kMeId]);
      expect(request.interestedCount, 2);
      expect(request.myStatus, MyRequestStatus.interested);
      expect(request.createdAt, DateTime.utc(2026, 11, 22, 5));
      expect(request.gameId, isNull);

      final mine = gameRequestFromJson({
        'id': 'r2',
        'sport_id': 'running',
        'city_id': 'tashkent',
        'host_id': me,
        'host_name': 'Sardor',
        'starts_local': '2026-11-24T07:00:00',
        'ends_local': '2026-11-24T08:00:00',
        'players_needed': 2,
        'status': 'converted',
        'game_id': 'game-5',
        'created_at': '2026-11-22T05:00:00+00:00',
        'interested': <Object>[],
        'interested_count': 0,
        'my_status': 'host',
      }, myUserId: me);
      expect(mine.hostId, kMeId);
      expect(mine.myStatus, MyRequestStatus.host);
      expect(mine.status, GameRequestStatus.converted);
      expect(mine.gameId, 'game-5');
      expect(mine.minLevel, 1);
      expect(mine.maxLevel, 5);
    });

    test('a player profile has levels, reliability and games played, and I am kMeId', () {
      final profile = playerProfileFromJson({
        'id': me,
        'name': 'Sardor',
        'city_id': 'tashkent',
        'levels': {'padel': 3, 'football': 2},
        'reliability': {'score': 40, 'badge': 'blocked'},
        'games_played': 7,
      }, myUserId: me);
      expect(profile.id, kMeId);
      expect(profile.name, 'Sardor');
      expect(profile.cityId, 'tashkent');
      expect(profile.levels, {'padel': 3, 'football': 2});
      expect(profile.levelFor('padel'), 3);
      expect(profile.levelFor('tennis'), 1);
      expect(profile.reliability.badge, ReliabilityBadge.blocked);
      expect(profile.gamesPlayed, 7);
    });

    test('every reliability badge maps', () {
      expect(reliabilityFromJson({'score': 80, 'badge': 'new'}).badge, ReliabilityBadge.isNew);
      expect(reliabilityFromJson({'score': 90, 'badge': 'reliable'}).badge, ReliabilityBadge.reliable);
      expect(reliabilityFromJson({'score': 60, 'badge': 'limited'}).badge, ReliabilityBadge.limited);
      expect(reliabilityFromJson({'score': 10, 'badge': 'blocked'}).badge, ReliabilityBadge.blocked);
      expect(() => reliabilityFromJson({'score': 1, 'badge': 'mystery'}), throwsFormatException);
    });

    test('settings', () {
      final settings = communitySettingsFromJson({
        'muted_categories': ['games', 'venue'],
        'hidden_from_search': true,
        'reliability': {'score': 55, 'badge': 'limited'},
      });
      expect(settings.mutedCategories, {'games', 'venue'});
      expect(settings.hiddenFromSearch, isTrue);
      expect(settings.reliability.badge, ReliabilityBadge.limited);
    });

    test('a notification keeps its payload and read state', () {
      final n = notificationFromJson({
        'id': 'n1',
        'kind': 'game_joined',
        'category': 'games',
        'payload': {'game_id': 'g1', 'actor_name': 'Aziz', 'sport_id': 'padel', 'starts_local': '2026-11-23T19:00:00'},
        'created_at': '2026-11-22T05:00:00.123456+00:00',
        'read': false,
      });
      expect(n.kind, 'game_joined');
      expect(n.category, 'games');
      expect(n.payload['actor_name'], 'Aziz');
      expect(n.read, isFalse);
      expect(n.createdAt, DateTime.utc(2026, 11, 22, 5, 0, 0, 123, 456));
      expect(n.createdAt.isUtc, isTrue);
    });

    test('each notification kind opens its screen', () {
      AppNotification n(String kind, [Map<String, Object?> payload = const {}]) => AppNotification(
        id: 'n',
        kind: kind,
        category: 'x',
        payload: payload,
        createdAt: DateTime.utc(2026),
        read: false,
      );
      for (final kind in ['booking_confirmed', 'booking_cancelled_by_venue', 'booking_reminder']) {
        expect(n(kind, {'booking_id': 'b1'}).route, '/bookings', reason: kind);
      }
      for (final kind in ['venue_new_booking', 'venue_booking_cancelled']) {
        expect(n(kind, {'venue_id': 'v1'}).route, '/owner/v1', reason: kind);
      }
      for (final kind in [
        'game_joined',
        'game_left',
        'join_request',
        'join_approved',
        'join_declined',
        'game_full',
        'game_changed',
        'game_cancelled',
        'game_removed',
        'game_reminder',
        'game_invite',
        'request_converted',
      ]) {
        expect(n(kind, {'game_id': 'g9'}).route, '/games/g9', reason: kind);
      }
      for (final kind in ['request_interest', 'request_expired']) {
        expect(n(kind, {'request_id': 'r4'}).route, '/games/requests/r4', reason: kind);
      }
      // Nothing to open: an unknown kind, or a payload without its id.
      expect(n('something_new').route, isNull);
      expect(n('game_joined').route, isNull);
      expect(n('venue_new_booking').route, isNull);
    });

    test('a game draft sends only what it has', () {
      expect(
        gameDraftJson(
          GameDraft(
            sportId: 'running',
            spots: 6,
            minLevel: 2,
            maxLevel: 4,
            visibility: GameVisibility.inviteOnly,
            note: ' Easy ',
            meetingPoint: 'Park',
            meetingLat: 41.3,
            meetingLng: 69.2,
            distanceKm: 5,
            pace: '6:00',
            start: DateTime.utc(2026, 11, 23, 7),
            end: DateTime.utc(2026, 11, 23, 8),
          ),
        ),
        {
          'sport_id': 'running',
          'spots': 6,
          'min_level': 2,
          'max_level': 4,
          'visibility': 'invite_only',
          'note': 'Easy',
          'meeting_point': 'Park',
          'meeting_lat': 41.3,
          'meeting_lng': 69.2,
          'distance_km': 5.0,
          'pace': '6:00',
          'starts_local': '2026-11-23T07:00:00',
          'ends_local': '2026-11-23T08:00:00',
        },
      );
      // A booked game: the booking carries the time, so there are no null keys at all.
      expect(gameDraftJson(const GameDraft(sportId: 'padel', spots: 4, bookingId: 'b-1')), {
        'sport_id': 'padel',
        'spots': 4,
        'min_level': 1,
        'max_level': 5,
        'visibility': 'public',
        'booking_id': 'b-1',
      });
    });

    test('a place pick omits what it does not set, so the backend defaults apply', () {
      expect(placePickJson(const PlacePick(bookingId: 'b-1')), {'booking_id': 'b-1'});
      expect(
        placePickJson(
          PlacePick(venueId: 'v-1', spots: 5, start: DateTime.utc(2026, 11, 24, 7), end: DateTime.utc(2026, 11, 24, 8)),
        ),
        {'venue_id': 'v-1', 'spots': 5, 'starts_local': '2026-11-24T07:00:00', 'ends_local': '2026-11-24T08:00:00'},
      );
      expect(placePickJson(const PlacePick(meetingPoint: 'Park', meetingLat: 1.5, meetingLng: 2.5)), {
        'meeting_point': 'Park',
        'meeting_lat': 1.5,
        'meeting_lng': 2.5,
      });
    });

    test('a game request draft', () {
      expect(
        gameRequestDraftJson(
          GameRequestDraft(
            sportId: 'padel',
            playersNeeded: 3,
            minLevel: 2,
            start: DateTime.utc(2026, 11, 24, 18),
            end: DateTime.utc(2026, 11, 24, 21),
            area: ' Yunusobod ',
          ),
        ),
        {
          'sport_id': 'padel',
          'players_needed': 3,
          'min_level': 2,
          'max_level': 5,
          'starts_local': '2026-11-24T18:00:00',
          'ends_local': '2026-11-24T21:00:00',
          'area': 'Yunusobod',
        },
      );
    });

    test('the new rule codes map to their errors', () {
      const join = {
        'already_requested': JoinError.alreadyRequested,
        'not_found': JoinError.notFound,
        'reliability_too_low': JoinError.reliabilityTooLow,
        'booking_not_usable': JoinError.bookingNotUsable,
        'game_exists': JoinError.gameExists,
        'invalid_argument': JoinError.invalidArgument,
        'in_past': JoinError.inPast,
        'too_far_ahead': JoinError.tooFarAhead,
        'forbidden': JoinError.forbidden,
        'not_cancellable': JoinError.notCancellable,
      };
      for (final entry in join.entries) {
        expect(
          joinExceptionFor(PostgrestException(message: entry.key, code: 'P0001')).error,
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        bookingExceptionFor(const PostgrestException(message: 'reliability_too_low', code: 'P0001')).error,
        BookingError.reliabilityTooLow,
      );
    });
  });
}
