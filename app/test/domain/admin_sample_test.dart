import 'package:actra/core/localized_text.dart';
import 'package:actra/data/admin_repository.dart';
import 'package:actra/data/owner_repository.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/admin.dart';
import 'package:actra/domain/booking_engine.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/owner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Sunday 22 Nov 2026, 10:00 in all three cities.
  final utcNow = DateTime.utc(2026, 11, 22, 5, 0);
  final monday = DateTime.utc(2026, 11, 23);
  late SampleBackend backend;
  late AdminRepository admin;
  late OwnerRepository owner;

  setUp(() {
    backend = SampleBackend(utcNow: () => utcNow, meName: 'Demo Admin');
    admin = backend.admin;
    owner = backend.owner;
  });

  Future<BookingError> errorOf(Future<void> Function() action) async {
    try {
      await action();
    } on BookingException catch (e) {
      return e.error;
    }
    fail('expected a BookingException');
  }

  VenueDraft newVenue({String city = 'tashkent'}) => VenueDraft(
    cityId: city,
    name: const LocalizedText(uz: 'Yangi maydon', ru: 'Новая площадка', en: 'New Ground'),
    address: const LocalizedText.all('1 Test Street'),
    phone: '+998 71 000 00 00',
    amenities: ['parking'],
  );

  Future<AdminVenue> adminVenue(String id) async => (await admin.venues()).firstWhere((v) => v.venue.id == id);

  test('the demo player is an admin', () async {
    expect(await admin.isAdmin(), isTrue);
  });

  group('venues', () {
    test('every sample venue is listed, newest first, with owners', () async {
      final venues = await admin.venues();
      expect(venues.map((v) => v.venue.id).toSet(), {for (final v in kSampleVenues) v.id});
      expect(venues.first.venue.id, kSampleVenues.last.id);
      final v1 = venues.firstWhere((v) => v.venue.id == 'v1');
      expect(v1.active, isTrue);
      expect(v1.inactiveCourtIds, isEmpty);
      expect(v1.owners.single.userId, kMeId);
      expect(v1.owners.single.name, 'Demo Admin');
      expect(venues.firstWhere((v) => v.venue.id == 'v2').owners, isEmpty);
    });

    test('a new venue opens 08:00–22:00, shows to players once it has a court, and the creator manages it', () async {
      final id = await admin.saveVenue(newVenue());
      final created = await adminVenue(id);
      expect((await admin.venues()).first.venue.id, id);
      expect(created.venue.name.en, 'New Ground');
      expect(created.venue.amenities, ['parking']);
      for (var d = 1; d <= 7; d++) {
        expect(created.venue.hours[d]!.openMinute, 480);
        expect(created.venue.hours[d]!.closeMinute, 1320);
      }
      expect((await backend.venues('tashkent')).map((v) => v.id), contains(id));
      expect((await owner.myVenues()).map((v) => v.id), contains(id));

      final courtId = await admin.saveCourt(
        CourtDraft(venueId: id, sportId: 'padel', name: const LocalizedText.all('Court 1'), basePrice: 100000),
      );
      final slots = await backend.availability(id, courtId, monday);
      expect(slots, hasLength(9)); // 08:00 to 20:00 starts, 90-minute slots
      expect(slots.first.price, 100000);
      final held = await backend.hold(id, courtId, [slots.first.time]);
      expect((await backend.confirm(held.id)).totalPrice, 100000);
      final cal = await owner.calendar(id, courtId, monday, 1);
      expect(cal.slots.first.state, OwnerSlotState.booked);
    });

    test('updating a venue keeps its courts and hours', () async {
      final draft = VenueDraft.from(await adminVenue('v1'))
        ..name = const LocalizedText.all('Lochin Renamed')
        ..amenities = ['cafe'];
      expect(await admin.saveVenue(draft), 'v1');
      final v1 = await backend.venue('v1');
      expect(v1.name.en, 'Lochin Renamed');
      expect(v1.amenities, ['cafe']);
      expect(v1.courts, hasLength(2));
      expect(v1.hours[1]!.openMinute, 420);
    });

    test('a deactivated venue leaves the player screens but stays in the admin list', () async {
      await admin.saveVenue(VenueDraft.from(await adminVenue('v2'))..active = false);
      expect((await backend.venues('tashkent')).map((v) => v.id), isNot(contains('v2')));
      await expectLater(backend.venue('v2'), throwsStateError);
      expect((await adminVenue('v2')).active, isFalse);

      await admin.saveVenue(VenueDraft.from(await adminVenue('v2'))..active = true);
      expect((await backend.venues('tashkent')).map((v) => v.id), contains('v2'));
    });

    test('a deactivated managed venue leaves my venues', () async {
      await admin.saveVenue(VenueDraft.from(await adminVenue('v1'))..active = false);
      expect((await owner.myVenues()).map((v) => v.id), isNot(contains('v1')));
    });

    test('validation', () async {
      expect(await errorOf(() => admin.saveVenue(newVenue(city: 'paris'))), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveVenue(newVenue()..name = const LocalizedText(uz: ' ', ru: ''))),
          BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveVenue(newVenue()..amenities = ['spa'])), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveVenue(newVenue()..address = LocalizedText.all('a' * 201))),
          BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveVenue(newVenue()..phone = '1' * 201)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveVenue(newVenue()..description = LocalizedText(ru: 'd' * 2001))),
          BookingError.invalidArgument);
      expect(await admin.saveVenue(newVenue()..description = LocalizedText(ru: 'd' * 2000)), isNotEmpty);
      expect(await errorOf(() => admin.saveVenue(newVenue()..id = 'nope')), BookingError.notFound);
    });

    test('a venue with bookings cannot be deleted; one without can', () async {
      expect(await errorOf(() => admin.deleteVenue('v1')), BookingError.hasBookings);
      final id = await admin.saveVenue(newVenue());
      await admin.saveCourt(CourtDraft(venueId: id, sportId: 'padel', name: const LocalizedText.all('C')));
      await admin.deleteVenue(id);
      expect((await admin.venues()).map((v) => v.venue.id), isNot(contains(id)));
      expect((await owner.myVenues()).map((v) => v.id), isNot(contains(id)));
      expect(await errorOf(() => admin.deleteVenue(id)), BookingError.notFound);
    });

    test('a venue that a game or a Game Request uses cannot be deleted', () async {
      final start = DateTime.utc(2026, 11, 23, 7);
      final end = DateTime.utc(2026, 11, 23, 8);
      final withGame = await admin.saveVenue(newVenue());
      await backend.create(GameDraft(sportId: 'gym', spots: 2, venueId: withGame, start: start, end: end));
      expect(await errorOf(() => admin.deleteVenue(withGame)), BookingError.hasBookings);

      final withRequest = await admin.saveVenue(newVenue());
      await backend.createRequest(
        GameRequestDraft(sportId: 'gym', playersNeeded: 1, venueId: withRequest, start: start, end: end),
      );
      expect(await errorOf(() => admin.deleteVenue(withRequest)), BookingError.hasBookings);
      expect((await admin.venues()).map((v) => v.venue.id), containsAll([withGame, withRequest]));
    });
  });

  group('courts', () {
    test('create, update and validation', () async {
      final id = await admin.saveCourt(
        CourtDraft(venueId: 'v2', sportId: 'tennis', name: const LocalizedText.all('Court X'), slotMinutes: 60, indoor: true),
      );
      final court = (await backend.venue('v2')).court(id);
      expect(court.sportId, 'tennis');
      expect(court.slotMinutes, 60);
      expect(court.indoor, isTrue);
      expect((await backend.venue('v2')).courts.last.id, id);

      await admin.saveCourt(CourtDraft.from(court, active: true)..basePrice = 99000);
      expect((await backend.venue('v2')).court(id).basePrice, 99000);

      CourtDraft good() => CourtDraft(venueId: 'v2', sportId: 'tennis', name: const LocalizedText.all('Y'));
      expect(await errorOf(() => admin.saveCourt(good()..slotMinutes = 45)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveCourt(good()..basePrice = -1)), BookingError.invalidArgument);
      expect(
        await errorOf(() => admin.saveCourt(good()..basePrice = BookingEngine.maxPrice + 1)),
        BookingError.invalidArgument,
      );
      expect(await admin.saveCourt(good()..basePrice = BookingEngine.maxPrice), isNotEmpty);
      expect(await errorOf(() => admin.saveCourt(good()..sportId = 'quidditch')), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveCourt(good()..name = const LocalizedText())), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveCourt(good()..venueId = 'nowhere')), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveCourt(good()..id = 'nope')), BookingError.notFound);
    });

    test('a deactivated court leaves the player venue page but not the owner calendar', () async {
      final v1 = await adminVenue('v1');
      await admin.saveCourt(CourtDraft.from(v1.venue.court('v1c2'), active: false));
      expect((await backend.venue('v1')).courts.map((c) => c.id), ['v1c1']);
      expect((await backend.venues('tashkent')).firstWhere((v) => v.id == 'v1').courts, hasLength(1));
      expect((await adminVenue('v1')).inactiveCourtIds, {'v1c2'});
      expect((await adminVenue('v1')).venue.courts, hasLength(2));
      // Existing bookings on it can still be seen and run by the owner.
      expect((await owner.calendar('v1', 'v1c2', monday, 7)).bookings, isNotEmpty);
    });

    test('duplicate copies prices, rules and hours, appends " 2", and sits after the original', () async {
      await owner.setCourtHours('v1', 'v1c1', {1: const DayHours(600, 900)});
      final copyId = await admin.duplicateCourt('v1c1');
      final v1 = await backend.venue('v1');
      expect(v1.courts.map((c) => c.id), ['v1c1', copyId, 'v1c2']);
      final original = v1.court('v1c1');
      final copy = v1.court(copyId);
      expect(copy.name.en, 'Court 1 2');
      expect(copy.name.ru, 'Корт 1 2');
      expect(copy.sportId, original.sportId);
      expect(copy.slotMinutes, original.slotMinutes);
      expect(copy.basePrice, original.basePrice);
      expect(copy.priceRules.map((r) => r.price), original.priceRules.map((r) => r.price));
      expect(copy.hoursOverride[1]!.openMinute, 600);
      // The copy has none of the original's bookings.
      expect((await owner.calendar('v1', copyId, monday, 7)).bookings, isEmpty);
      expect(await errorOf(() => admin.duplicateCourt('nope')), BookingError.notFound);
    });

    test('a court with bookings cannot be deleted; a fresh copy can', () async {
      expect(await errorOf(() => admin.deleteCourt('v1c1')), BookingError.hasBookings);
      final copyId = await admin.duplicateCourt('v1c1');
      await admin.deleteCourt(copyId);
      expect((await backend.venue('v1')).courts.map((c) => c.id), ['v1c1', 'v1c2']);
      expect(await errorOf(() => admin.deleteCourt(copyId)), BookingError.notFound);
    });
  });

  group('owners', () {
    test('search by name, case-insensitive; short queries find nothing', () async {
      expect((await admin.searchUsers('dil')).map((u) => u.name), ['Dilnoza']);
      expect((await admin.searchUsers('A')), isEmpty);
      expect((await admin.searchUsers(' ')), isEmpty);
      expect((await admin.searchUsers('demo')).single.userId, kMeId);
      expect((await admin.searchUsers('a')), isEmpty);
      expect((await admin.searchUsers('ar')).length, lessThanOrEqualTo(20));
    });

    test('assigning and removing an owner, idempotently', () async {
      await admin.setOwner('v2', 'p2', assigned: true);
      await admin.setOwner('v2', 'p2', assigned: true);
      expect((await adminVenue('v2')).owners.map((o) => o.name), ['Dilnoza']);
      await admin.setOwner('v2', 'p2', assigned: false);
      await admin.setOwner('v2', 'p2', assigned: false);
      expect((await adminVenue('v2')).owners, isEmpty);
      expect(await errorOf(() => admin.setOwner('nope', 'p2', assigned: true)), BookingError.notFound);
    });

    test('the demo player gains and loses owner access with the assignment', () async {
      await admin.setOwner('v2', kMeId, assigned: true);
      expect((await owner.myVenues()).map((v) => v.id), contains('v2'));
      expect((await owner.calendar('v2', 'v2c1', monday, 7)).slots, isNotEmpty);
      await admin.setOwner('v1', kMeId, assigned: false);
      expect((await owner.myVenues()).map((v) => v.id), isNot(contains('v1')));
      expect(await errorOf(() => owner.calendar('v1', 'v1c1', monday, 7)), BookingError.notAllowed);
    });
  });

  group('sports', () {
    test('listed by sort order; create shows to players; duplicate ids refused', () async {
      expect((await admin.sports()).map((s) => s.sport.id), [for (final s in kSampleSports) s.id]);
      final id = await admin.saveSport(
        SportDraft(id: 'squash', name: const LocalizedText.all('Squash'), iconKey: 'squash', sortOrder: 99),
        create: true,
      );
      expect(id, 'squash');
      expect((await admin.sports()).last.sport.id, 'squash');
      expect((await backend.sports()).map((s) => s.id), contains('squash'));
      expect(
        await errorOf(() => admin.saveSport(SportDraft(id: 'padel', name: const LocalizedText.all('P'), iconKey: 'p'), create: true)),
        BookingError.alreadyExists,
      );
    });

    test('deactivating hides it from players; validation', () async {
      final tennis = (await admin.sports()).firstWhere((s) => s.sport.id == 'tennis');
      await admin.saveSport(SportDraft.from(tennis)..active = false, create: false);
      expect((await backend.sports()).map((s) => s.id), isNot(contains('tennis')));
      expect((await admin.sports()).firstWhere((s) => s.sport.id == 'tennis').active, isFalse);

      SportDraft good() => SportDraft(id: 'squash', name: const LocalizedText.all('S'), iconKey: 'squash');
      expect(await errorOf(() => admin.saveSport(good()..id = 'Squash', create: true)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveSport(good()..id = 's', create: true)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveSport(good()..name = const LocalizedText(), create: true)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveSport(good()..defaultPlayers = 0, create: true)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveSport(good()..iconKey = '', create: true)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveSport(good(), create: false)), BookingError.notFound);
    });
  });

  group('banners', () {
    test('create, city filter, deactivate, delete', () async {
      final id = await admin.saveBanner(BannerDraft(
        cityId: 'almaty',
        title: const LocalizedText.all('Almaty only'),
        url: 'https://example.com/almaty',
        sortOrder: -1,
      ));
      expect((await admin.banners()).first.id, id);
      expect((await backend.banners('almaty')).first.title.en, 'Almaty only');
      expect((await backend.banners('tashkent')).map((b) => b.id), isNot(contains(id)));

      final b = (await admin.banners()).firstWhere((b) => b.id == id);
      await admin.saveBanner(BannerDraft.from(b)..active = false);
      expect((await backend.banners('almaty')).map((b) => b.id), isNot(contains(id)));

      await admin.deleteBanner(id);
      expect((await admin.banners()).map((b) => b.id), isNot(contains(id)));
      expect(await errorOf(() => admin.deleteBanner(id)), BookingError.notFound);
    });

    test('validation', () async {
      BannerDraft good() => BannerDraft(title: const LocalizedText.all('T'), url: 'https://ok.uz');
      expect(await errorOf(() => admin.saveBanner(good()..url = 'http://insecure.uz')), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveBanner(good()..cityId = 'paris')), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveBanner(good()..title = const LocalizedText())), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveBanner(good()..subtitle = LocalizedText.all('s' * 201))), BookingError.invalidArgument);
      expect(await errorOf(() => admin.saveBanner(good()..id = 'nope')), BookingError.notFound);
    });
  });

  group('audit log', () {
    test('lists admin and owner changes of this run, newest first', () async {
      expect(await admin.auditLog(), isEmpty);
      final venueId = await admin.saveVenue(newVenue());
      await admin.setOwner('v2', 'p2', assigned: true);
      final free = (await backend.availability('v1', 'v1c1', monday)).firstWhere((s) => s.state == SlotState.free);
      await owner.createWalkIn('v1', 'v1c1', [free.time], name: 'Rustam', payment: WalkInPayment.cash);

      final log = await admin.auditLog();
      expect(log.map((e) => e.action), ['owner_create_walk_in', 'admin_set_owner', 'admin_save_venue']);
      final created = log.last;
      expect(created.entity, 'venue');
      expect(created.entityId, venueId);
      expect(created.actorName, 'Demo Admin');
      expect(created.before, isNull);
      expect(created.after!['name_en'], 'New Ground');
      expect(created.at, utcNow);
      expect(log.first.entity, 'booking');

      await admin.saveVenue(VenueDraft.from(await adminVenue(venueId))..phone = '+998 71 111 11 11');
      final update = (await admin.auditLog()).first;
      expect(update.before!['phone'], '+998 71 000 00 00');
      expect(update.after!['phone'], '+998 71 111 11 11');
    });

    test('limit, and refused changes are not logged', () async {
      for (var i = 0; i < 3; i++) {
        await admin.saveBanner(BannerDraft(title: LocalizedText.all('B$i'), url: 'https://b.uz'));
      }
      await errorOf(() => admin.saveBanner(BannerDraft(title: const LocalizedText.all('x'), url: 'ftp://no')));
      expect(await admin.auditLog(), hasLength(3));
      expect(await admin.auditLog(limit: 2), hasLength(2));
      expect(await admin.auditLog(before: utcNow), isEmpty);
      expect(await errorOf(() => admin.auditLog(limit: 0)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.auditLog(limit: 101)), BookingError.invalidArgument);
    });

    test('paging with before', () async {
      var clock = utcNow;
      final paged = SampleBackend(utcNow: () => clock, meName: 'Demo');
      for (var i = 0; i < 5; i++) {
        clock = utcNow.add(Duration(minutes: i));
        await paged.admin.saveBanner(BannerDraft(title: LocalizedText.all('B$i'), url: 'https://b.uz'));
      }
      final first = await paged.admin.auditLog(limit: 2);
      expect(first.map((e) => e.at.minute), [4, 3]);
      final next = await paged.admin.auditLog(limit: 2, before: first.last.at);
      expect(next.map((e) => e.at.minute), [2, 1]);
    });
  });

  group('review of scores and reports', () {
    Future<double?> padel(String id) async => (await backend.profile(id)).ratings['padel']?.rating;
    Future<int?> rated(String id) async => (await backend.profile(id)).ratings['padel']?.ratedGames;
    Future<String> nameOf(String id) async => (await backend.profile(id)).name;

    test('a disputed score is listed with who disputed it, an empty review otherwise', () async {
      expect((await admin.review()).openCount, 0);
      await backend.disputeScoreAs('p2', 'r-gf2', reason: 'We won the second set');
      final review = await admin.review();
      expect(review.disputes, hasLength(1));
      final dispute = review.disputes.single;
      expect(dispute.result.id, 'r-gf2');
      expect(dispute.result.status, ResultStatus.disputed);
      expect(dispute.result.disputeReason, 'We won the second set');
      expect(dispute.disputedByName, await nameOf('p2'));
      expect(dispute.game.gameId, 'gf2');
      expect(dispute.game.sportId, 'padel');
      expect(dispute.nameOf('p1'), await nameOf('p1'));
      expect(dispute.flagged, isFalse);
      expect(review.openCount, 1);
    });

    test('a no-show freeze has no disputer, a flagged confirmed score is listed too', () async {
      await backend.reportNoShowAs('p1', 'gf2', kMeId, reported: true);
      await backend.reportNoShowAs('p3', 'gf2', kMeId, reported: true);
      var dispute = (await admin.review()).disputes.single;
      expect(dispute.result.disputeReason, 'no_show');
      expect(dispute.disputedByName, isNull);

      await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: const [(6, 4)]);
      await backend.confirmScoreAs('p2', 'r-gf1');
      await backend.reportNoShowAs('p1', 'gf1', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf1', 'p3', reported: true);
      final review = await admin.review();
      expect(review.disputes, hasLength(2));
      dispute = review.disputes.firstWhere((d) => d.result.id == 'r-gf1');
      expect(dispute.flagged, isTrue);
      expect(dispute.result.flaggedNoShow, isTrue);
    });

    test('confirm applies the ratings, tells the players, is audited and leaves the list', () async {
      await backend.disputeScoreAs('p2', 'r-gf2');
      final before = {for (final id in ['p1', 'p2', 'p3']) id: await padel(id)};
      await admin.resolveScore('r-gf2', 'confirm');

      expect((await admin.review()).disputes, isEmpty);
      final result = (await backend.game('gf2')).result!;
      expect(result.status, ResultStatus.confirmed);
      expect(result.changes.keys, containsAll(['p1', 'p2', 'p3', kMeId]));
      for (final id in ['p1', 'p2', 'p3']) {
        expect(await padel(id), result.changes[id]!.newRating);
        expect(await padel(id), isNot(before[id]));
      }
      final notice = (await backend.inbox()).firstWhere((n) => n.kind == 'score_resolved');
      expect(notice.payload['action'], 'confirm');
      final entry = (await admin.auditLog()).first;
      expect((entry.action, entry.entity, entry.entityId), ('score_confirm', 'match_result', 'r-gf2'));
      expect(entry.before!['status'], 'disputed');
      expect(entry.after!['status'], 'confirmed');
    });

    test('correct replaces the sets, then applies them', () async {
      await backend.disputeScoreAs('p2', 'r-gf2');
      await admin.resolveScore('r-gf2', 'correct', sets: const [(3, 6), (6, 4), (4, 6)]);
      final result = (await backend.game('gf2')).result!;
      expect(result.status, ResultStatus.confirmed);
      expect(result.sets, const [(3, 6), (6, 4), (4, 6)]);
      expect(result.winner, MatchWinner.b);
      final entry = (await admin.auditLog()).first;
      expect(entry.action, 'score_correct');
      expect(entry.after!['sets'], [
        [3, 6],
        [6, 4],
        [4, 6],
      ]);
    });

    test('correct needs valid sets; confirm and correct only work on a disputed score', () async {
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'confirm')), BookingError.notFound, reason: 'pending');
      await backend.disputeScoreAs('p2', 'r-gf2');
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'correct')), BookingError.invalidArgument);
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'correct', sets: const [])), BookingError.invalidArgument);
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'correct', sets: const [(0, 0)])), BookingError.invalidArgument);
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'correct', sets: const [(31, 2)])), BookingError.invalidArgument);
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'bogus')), BookingError.invalidArgument);
      expect(await errorOf(() => admin.resolveScore('r-nope', 'confirm')), BookingError.notFound);
      expect((await admin.review()).disputes, hasLength(1), reason: 'refused calls change nothing');
      expect(await admin.auditLog(), isEmpty);

      await admin.resolveScore('r-gf2', 'confirm');
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'confirm')), BookingError.notFound, reason: 'confirmed');
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'correct', sets: const [(6, 0)])), BookingError.notFound);
    });

    test('void on a confirmed score takes its rating changes back, once', () async {
      final ratings = {for (final id in ['p1', 'p2', 'p3']) id: await padel(id)};
      final games = {for (final id in ['p1', 'p2', 'p3']) id: await rated(id)};
      await backend.confirmScoreAs('p2', 'r-gf2');
      expect((await backend.game('gf2')).result!.status, ResultStatus.confirmed);
      expect(await padel('p1'), isNot(ratings['p1']));

      await admin.resolveScore('r-gf2', 'void');
      expect((await backend.game('gf2')).result!.status, ResultStatus.voided);
      for (final id in ['p1', 'p2']) {
        expect(await padel(id), ratings[id], reason: id);
        expect(await rated(id), games[id], reason: id);
      }
      // Nobody had rated p3: the rating they started with stays, and no rated game.
      expect(ratings['p3'], isNull);
      expect(await rated('p3'), 0);
      final entry = (await admin.auditLog()).first;
      expect((entry.action, entry.after!['status']), ('score_void', 'void'));
      expect((await backend.inbox()).where((n) => n.kind == 'score_resolved' && n.payload['action'] == 'void'), hasLength(1));
      expect(await errorOf(() => admin.resolveScore('r-gf2', 'void')), BookingError.notFound, reason: 'already void');
      expect(await padel('p1'), ratings['p1'], reason: 'not taken back twice');
    });

    test('void works on a pending score, which moves no ratings', () async {
      final before = await padel('p1');
      await admin.resolveScore('r-gf2', 'void');
      expect((await backend.game('gf2')).result!.status, ResultStatus.voided);
      expect(await padel('p1'), before);
    });

    test('keep clears the flag of a confirmed score and nothing else', () async {
      await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: const [(6, 4)]);
      await backend.confirmScoreAs('p2', 'r-gf1');
      expect(await errorOf(() => admin.resolveScore('r-gf1', 'keep')), BookingError.notFound, reason: 'not flagged');
      await backend.reportNoShowAs('p1', 'gf1', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf1', 'p3', reported: true);
      final ratings = await padel('p1');
      final notices = (await backend.inbox()).length;

      await admin.resolveScore('r-gf1', 'keep');
      final result = (await backend.game('gf1')).result!;
      expect(result.status, ResultStatus.confirmed);
      expect(result.flaggedNoShow, isFalse);
      expect(await padel('p1'), ratings);
      expect((await admin.review()).disputes, isEmpty);
      expect(await backend.inbox(), hasLength(notices), reason: 'keep tells nobody');
      expect((await admin.auditLog()).first.action, 'score_keep');
      expect(await errorOf(() => admin.resolveScore('r-gf1', 'keep')), BookingError.notFound);
    });

    test('a flagged score can be voided: its rating changes are reversed', () async {
      final before = await padel('p1');
      await backend.enterScore('gf1', sideA: [kMeId, 'p1'], sideB: ['p2', 'p3'], sets: const [(6, 4)]);
      await backend.confirmScoreAs('p2', 'r-gf1');
      await backend.reportNoShowAs('p1', 'gf1', 'p3', reported: true);
      await backend.reportNoShowAs('p2', 'gf1', 'p3', reported: true);
      await admin.resolveScore('r-gf1', 'void');
      expect(await padel('p1'), before);
      expect((await admin.review()).disputes, isEmpty);
    });

    test('a report lists the game and its score; closing it removes it and is audited', () async {
      await backend.reportPlayerAs('p2', kMeId, gameId: 'gf2', reason: ReportReason.falseScore, details: 'Not 6-3');
      await backend.reportPlayerAs('p1', 'p3', reason: ReportReason.language);
      final review = await admin.review();
      expect(review.reports, hasLength(2));
      final first = review.reports.first;
      expect(first.reason, ReportReason.falseScore);
      expect(first.details, 'Not 6-3');
      expect(first.reporterId, 'p2');
      expect(first.targetId, kMeId);
      expect(first.game!.gameId, 'gf2');
      expect(first.result!.id, 'r-gf2');
      expect(first.hasLiveScore, isTrue);
      expect(review.reports.last.game, isNull);
      expect(review.reports.last.hasLiveScore, isFalse);
      expect(review.openCount, 2);

      await admin.closeReport(first.id, note: '  Checked, fine  ');
      expect((await admin.review()).reports.map((r) => r.id), [review.reports.last.id]);
      final entry = (await admin.auditLog()).first;
      expect((entry.action, entry.entity, entry.entityId), ('report_closed', 'abuse_report', first.id));
      expect(entry.after!['admin_note'], 'Checked, fine');

      // Closed, a report can be made again.
      await backend.reportPlayerAs('p2', kMeId, gameId: 'gf2', reason: ReportReason.other);
      expect((await admin.review()).reports, hasLength(2));
    });

    test('closing a report: unknown or closed is not found, an overlong note is refused', () async {
      await backend.reportPlayerAs('p1', 'p3', reason: ReportReason.other);
      final id = (await admin.review()).reports.single.id;
      expect(await errorOf(() => admin.closeReport(id, note: 'x' * 501)), BookingError.invalidArgument);
      expect(await errorOf(() => admin.closeReport('nope')), BookingError.notFound);
      await admin.closeReport(id);
      expect(await errorOf(() => admin.closeReport(id)), BookingError.notFound);
      expect((await admin.auditLog()).single.after!['admin_note'], isNull);
    });

    test('a voided score is not offered on a report', () async {
      await backend.reportPlayerAs('p1', 'p3', gameId: 'gf2', reason: ReportReason.falseScore);
      await admin.resolveScore('r-gf2', 'void');
      final report = (await admin.review()).reports.single;
      expect(report.result!.status, ResultStatus.voided);
      expect(report.hasLiveScore, isFalse);
    });
  });
}
