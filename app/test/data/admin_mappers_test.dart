import 'package:actra/core/localized_text.dart';
import 'package:actra/data/supabase/errors.dart';
import 'package:actra/data/supabase/mappers.dart';
import 'package:actra/domain/admin.dart';
import 'package:actra/data/sample/sample_data.dart' show kMeId;
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/competitive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of `admin_list_venues`: stored column names, `hours` instead of
/// `working_hours`, inactive courts included, and owners.
Map<String, dynamic> adminVenueJson() => {
  'id': 'venue-1',
  'city_id': 'tashkent',
  'name_uz': 'Lochin',
  'name_ru': 'Лочин',
  'name_en': null,
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
  'amenities': ['parking', 'cafe'],
  'color_seed': 2,
  'active': false,
  'created_at': '2026-11-23T10:00:00+00:00',
  'hours': [
    for (var d = 1; d <= 7; d++)
      {'weekday': d, 'closed': d == 7, 'open_minute': 480, 'close_minute': 1320},
  ],
  'courts': [
    {
      'id': 'court-b',
      'venue_id': 'venue-1',
      'sport_id': 'tennis',
      'name_uz': null,
      'name_ru': null,
      'name_en': 'Second',
      'slot_minutes': 60,
      'base_price': 200000,
      'indoor': false,
      'sort_order': 1,
      'active': false,
      'hours': [
        {'weekday': 2, 'closed': true, 'open_minute': 0, 'close_minute': 0},
      ],
      'price_rules': <Object>[],
    },
    {
      'id': 'court-a',
      'venue_id': 'venue-1',
      'sport_id': 'padel',
      'name_uz': 'Kort 1',
      'name_ru': 'Корт 1',
      'name_en': 'Court 1',
      'slot_minutes': 90,
      'base_price': 180000,
      'indoor': true,
      'sort_order': 0,
      'active': true,
      'hours': <Object>[],
      'price_rules': [
        {'weekdays': [1, 2, 3, 4, 5], 'from_minute': 1080, 'to_minute': 1440, 'price': 250000},
      ],
    },
  ],
  'owners': [
    {'user_id': 'user-1', 'full_name': 'Aziz', 'phone': '+998901234567'},
    {'user_id': 'user-2', 'full_name': null, 'phone': null},
  ],
};

void main() {
  group('admin venue', () {
    test('the venue, its courts in order, hours, rules and owners', () {
      final a = adminVenueFromJson(adminVenueJson());
      expect(a.active, isFalse);
      expect(a.venue.id, 'venue-1');
      expect(a.venue.cityId, 'tashkent');
      expect(a.venue.name.ru, 'Лочин');
      expect(a.venue.name.en, isNull);
      expect(a.venue.description.ru, 'Два корта');
      expect(a.venue.phone, '+998 71 200 00 01');
      expect(a.venue.amenities, ['parking', 'cafe']);
      expect(a.venue.hours[1]!.openMinute, 480);
      expect(a.venue.hours[7], isNull);
      expect(a.venue.courts.map((c) => c.id), ['court-a', 'court-b']);
      final courtA = a.venue.court('court-a');
      expect(courtA.venueId, 'venue-1');
      expect(courtA.indoor, isTrue);
      expect(courtA.priceRules.single.price, 250000);
      expect(a.venue.court('court-b').hoursOverride, {2: null});
      expect(a.inactiveCourtIds, {'court-b'});
      expect(a.owners.map((o) => o.userId), ['user-1', 'user-2']);
      expect(a.owners.first.name, 'Aziz');
      expect(a.owners.first.phone, '+998901234567');
      expect(a.owners.last.name, '');
      expect(a.owners.last.phone, isNull);
    });

    test('missing active flags and owners mean active and none', () {
      final json = adminVenueJson()
        ..remove('active')
        ..remove('owners');
      for (final c in json['courts'] as List) {
        (c as Map).remove('active');
      }
      final a = adminVenueFromJson(json);
      expect(a.active, isTrue);
      expect(a.inactiveCourtIds, isEmpty);
      expect(a.owners, isEmpty);
    });

    test('a draft from an admin venue round-trips to the save payload', () {
      final draft = VenueDraft.from(adminVenueFromJson(adminVenueJson()));
      expect(venueDraftJson(draft), {
        'id': 'venue-1',
        'city_id': 'tashkent',
        'name_uz': 'Lochin',
        'name_ru': 'Лочин',
        'name_kk': null,
        'name_en': null,
        'description_uz': null,
        'description_ru': 'Два корта',
        'description_kk': null,
        'description_en': null,
        'address_uz': 'A',
        'address_ru': 'Б',
        'address_kk': null,
        'address_en': 'C',
        'district_uz': 'Yunusobod',
        'district_ru': 'Юнусабад',
        'district_kk': null,
        'district_en': 'Yunusabad',
        'phone': '+998 71 200 00 01',
        'amenities': ['parking', 'cafe'],
        'active': false,
      });
    });

    test('a new venue has no id key, and blank texts are sent as null, trimmed otherwise', () {
      final json = venueDraftJson(VenueDraft(name: const LocalizedText(uz: ' Yangi ', ru: '', en: '  ')));
      expect(json.containsKey('id'), isFalse);
      expect(json['name_uz'], 'Yangi');
      expect(json['name_ru'], isNull);
      expect(json['name_kk'], isNull);
      expect(json['name_en'], isNull);
      expect(json['city_id'], 'tashkent');
      expect(json['amenities'], isEmpty);
      expect(json['active'], isTrue);
      expect(json.keys.toSet(), {
        'city_id',
        for (final f in ['name', 'description', 'address', 'district'])
          for (final l in ['uz', 'ru', 'kk', 'en']) '${f}_$l',
        'phone',
        'amenities',
        'active',
      });
    });
  });

  group('court draft', () {
    test('payload keys, with and without an id', () {
      final court = adminVenueFromJson(adminVenueJson()).venue.court('court-b');
      expect(courtDraftJson(CourtDraft.from(court, active: false)), {
        'id': 'court-b',
        'venue_id': 'venue-1',
        'sport_id': 'tennis',
        'name_uz': null,
        'name_ru': null,
        'name_kk': null,
        'name_en': 'Second',
        'slot_minutes': 60,
        'base_price': 200000,
        'indoor': false,
        'active': false,
      });
      final created = courtDraftJson(CourtDraft(venueId: 'venue-1', sportId: 'padel', name: const LocalizedText.all('Court 3')));
      expect(created.containsKey('id'), isFalse);
      expect(created['slot_minutes'], 90);
      expect(created['base_price'], 0);
      expect(created['active'], isTrue);
    });
  });

  group('sport', () {
    final row = {
      'id': 'squash',
      'name_uz': 'Skvosh',
      'name_ru': 'Сквош',
      'name_kk': 'Сквош',
      'name_en': 'Squash',
      'icon_key': 'squash',
      'bookable': true,
      'competitive_rating': true,
      'default_players': 2,
      'sort_order': 7,
      'active': false,
    };

    test('row and payload', () {
      final s = adminSportFromJson(row);
      expect(s.sport.id, 'squash');
      expect(s.sport.name.ru, 'Сквош');
      expect(s.sport.competitiveRating, isTrue);
      expect(s.sortOrder, 7);
      expect(s.active, isFalse);
      expect(sportDraftJson(SportDraft.from(s)), row);
    });
  });

  group('banner', () {
    final row = {
      'id': 'banner-1',
      'city_id': null,
      'title_uz': 'Sarlavha',
      'title_ru': 'Заголовок',
      'title_kk': 'Тақырып',
      'title_en': 'Title',
      'subtitle_uz': null,
      'subtitle_ru': 'Подзаголовок',
      'subtitle_kk': null,
      'subtitle_en': null,
      'url': 'https://example.com',
      'sort_order': 2,
      'active': true,
    };

    test('row and payload', () {
      final b = adminBannerFromJson({...row, 'color_seed': 3});
      expect(b.id, 'banner-1');
      expect(b.cityId, isNull);
      expect(b.title.en, 'Title');
      expect(b.subtitle.ru, 'Подзаголовок');
      expect(b.url, 'https://example.com');
      expect(b.sortOrder, 2);
      expect(b.active, isTrue);
      expect(bannerDraftJson(BannerDraft.from(b)), row);
    });

    test('a new banner has no id but always a city key', () {
      final json = bannerDraftJson(BannerDraft(title: const LocalizedText.all('Hi'), url: 'https://x.uz'));
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('city_id'), isTrue);
      expect(json['city_id'], isNull);
    });
  });

  group('users and audit', () {
    test('search results', () {
      final u = ownerRefFromJson({'user_id': 'u1', 'full_name': 'Dilnoza', 'phone': '+998901112233'});
      expect(u.userId, 'u1');
      expect(u.name, 'Dilnoza');
      expect(u.phone, '+998901112233');
    });

    test('an audit entry', () {
      final e = auditEntryFromJson({
        'id': '42',
        'created_at': '2026-11-23T10:15:30.123+05:00',
        'actor_name': 'Admin',
        'action': 'admin_save_venue',
        'entity': 'venue',
        'entity_id': 'venue-1',
        'before': null,
        'after': {'name_ru': 'Лочин', 'active': true},
      });
      expect(e.id, '42');
      expect(e.at, DateTime.utc(2026, 11, 23, 5, 15, 30, 123));
      expect(e.at.isUtc, isTrue);
      expect(e.actorName, 'Admin');
      expect(e.action, 'admin_save_venue');
      expect(e.entity, 'venue');
      expect(e.entityId, 'venue-1');
      expect(e.before, isNull);
      expect(e.after, {'name_ru': 'Лочин', 'active': true});
    });

    test('a numeric id and a missing actor', () {
      final e = auditEntryFromJson({
        'id': 7,
        'created_at': '2026-11-23T10:15:30Z',
        'actor_name': null,
        'action': 'owner_cancel_booking',
        'entity': 'booking',
        'entity_id': null,
        'before': {'status': 'confirmed'},
        'after': {'status': 'cancelled_by_venue'},
      });
      expect(e.id, '7');
      expect(e.actorName, isNull);
      expect(e.entityId, isNull);
      expect(e.before, {'status': 'confirmed'});
    });
  });

  group('admin review', () {
    Map<String, dynamic> resultJson(String id, String status, {String? reason, bool flagged = false}) => {
      'id': id,
      'status': status,
      'sets': [
        [6, 4],
        [3, 6],
        [7, 5],
      ],
      'winner': 'a',
      'entered_by': 'u-host',
      'side_a': ['u-host', 'u-me'],
      'side_b': ['u-x', 'u-y'],
      'confirmed_by': <String>[],
      'dispute_reason': reason,
      'flagged_no_show': flagged,
      'changes': <String, Object>{},
    };

    Map<String, dynamic> reviewJson() => {
      'disputes': [
        {
          'result': resultJson('r1', 'disputed', reason: 'Wrong score'),
          'game': {'game_id': 'g1', 'sport_id': 'padel', 'starts_local': '2026-11-21T18:00:00'},
          'players': [
            {'id': 'u-host', 'name': 'Aziz', 'side': 'a'},
            {'id': 'u-me', 'name': 'Demo Admin', 'side': 'a'},
            {'id': 'u-x', 'name': 'Bobur', 'side': 'b'},
            {'id': 'u-y', 'name': 'Dilnoza', 'side': 'b'},
          ],
          'disputed_by_name': 'Bobur',
        },
        {
          'result': resultJson('r2', 'disputed', reason: 'no_show'),
          'game': {'game_id': 'g2', 'sport_id': 'tennis', 'starts_local': '2026-11-20T09:30:00'},
          'players': <Object>[],
          'disputed_by_name': null,
        },
        {
          'result': resultJson('r3', 'confirmed', flagged: true),
          'game': {'game_id': 'g3', 'sport_id': 'padel', 'starts_local': '2026-11-19T20:00:00'},
          'players': <Object>[],
          'disputed_by_name': null,
        },
      ],
      'reports': [
        {
          'id': 'rep1',
          'reporter_id': 'u-me',
          'reporter_name': 'Demo Admin',
          'target_id': 'u-x',
          'target_name': 'Bobur',
          'game_id': 'g1',
          'game': {'game_id': 'g1', 'sport_id': 'padel', 'starts_local': '2026-11-21T18:00:00'},
          'result': resultJson('r1', 'void'),
          'reason': 'false_score',
          'details': 'It was 6-0',
          'created_at': '2026-11-22T08:00:00+00:00',
        },
        {
          'id': 'rep2',
          'reporter_id': 'u-x',
          'reporter_name': 'Bobur',
          'target_id': 'u-y',
          'target_name': 'Dilnoza',
          'game_id': null,
          'game': null,
          'result': null,
          'reason': 'language',
          'details': null,
          'created_at': '2026-11-22T09:00:00+00:00',
        },
      ],
      'counts': {'disputes': 3, 'reports': 2},
    };

    test('disputes: result, game, names, who disputed; the signed-in user becomes me', () {
      final review = adminReviewFromJson(reviewJson(), myUserId: 'u-me');
      expect(review.disputes, hasLength(3));
      final d = review.disputes.first;
      expect(d.result.id, 'r1');
      expect(d.result.status, ResultStatus.disputed);
      expect(d.result.disputeReason, 'Wrong score');
      expect(d.result.sets, const [(6, 4), (3, 6), (7, 5)]);
      expect(d.result.sideA, ['u-host', kMeId]);
      expect(d.game.gameId, 'g1');
      expect(d.game.sportId, 'padel');
      expect(d.game.startsLocal, DateTime.utc(2026, 11, 21, 18));
      expect(d.names, {'u-host': 'Aziz', kMeId: 'Demo Admin', 'u-x': 'Bobur', 'u-y': 'Dilnoza'});
      expect(d.nameOf('u-x'), 'Bobur');
      expect(d.disputedByName, 'Bobur');
      expect(d.flagged, isFalse);
    });

    test('a no-show dispute has no disputer; a confirmed flagged result is flagged', () {
      final review = adminReviewFromJson(reviewJson(), myUserId: null);
      expect(review.disputes[1].result.disputeReason, 'no_show');
      expect(review.disputes[1].disputedByName, isNull);
      expect(review.disputes[2].flagged, isTrue);
      expect(review.disputes[2].result.flaggedNoShow, isTrue);
      expect(review.disputes[0].names.containsKey('u-me'), isTrue, reason: 'no signed-in id: ids stay as sent');
    });

    test('reports: reason, text, date, game and score, or neither', () {
      final review = adminReviewFromJson(reviewJson(), myUserId: 'u-me');
      expect(review.reports, hasLength(2));
      final r = review.reports.first;
      expect(r.id, 'rep1');
      expect(r.reporterId, kMeId);
      expect(r.reporterName, 'Demo Admin');
      expect(r.targetId, 'u-x');
      expect(r.targetName, 'Bobur');
      expect(r.reason, ReportReason.falseScore);
      expect(r.details, 'It was 6-0');
      expect(r.createdAt, DateTime.utc(2026, 11, 22, 8));
      expect(r.game!.gameId, 'g1');
      expect(r.result!.status, ResultStatus.voided);
      expect(r.hasLiveScore, isFalse);
      final bare = review.reports.last;
      expect(bare.reason, ReportReason.language);
      expect(bare.details, isNull);
      expect(bare.game, isNull);
      expect(bare.result, isNull);
      expect(review.openCount, 5);
    });

    test('an empty review, unknown keys and a missing teams key are fine', () {
      expect(adminReviewFromJson({'disputes': [], 'reports': [], 'counts': {}}, myUserId: null).openCount, 0);
      expect(adminReviewFromJson(<String, dynamic>{}, myUserId: null).openCount, 0);
      final json = reviewJson()..['teams'] = [{'id': 't1'}]..['something_new'] = 1;
      expect(adminReviewFromJson(json, myUserId: null).openCount, 5);
    });
  });

  test('admin errors', () {
    PostgrestException raised(String message) => PostgrestException(message: message, code: 'P0001');
    expect(bookingExceptionFor(raised('has_bookings')).error, BookingError.hasBookings);
    expect(bookingExceptionFor(raised('already_exists')).error, BookingError.alreadyExists);
    expect(bookingExceptionFor(raised('not_allowed')).error, BookingError.notAllowed);
  });
}
