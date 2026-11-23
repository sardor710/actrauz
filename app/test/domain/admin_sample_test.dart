import 'package:actra/core/localized_text.dart';
import 'package:actra/data/admin_repository.dart';
import 'package:actra/data/owner_repository.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/admin.dart';
import 'package:actra/domain/booking_engine.dart';
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
}
