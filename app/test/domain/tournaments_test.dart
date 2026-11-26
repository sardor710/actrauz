import 'package:actra/core/localized_text.dart';
import 'package:actra/core/markets.dart';
import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_repositories.dart';
import 'package:actra/domain/community.dart';
import 'package:actra/domain/models.dart';
import 'package:actra/domain/tournaments.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tournament rules, through the sample backend (the database's rules in
/// memory). Padel levels: the demo player 3, p1 3, p2 2, p5 3, p7 4, p8 3;
/// everybody else counts as level 1.
void main() {
  // Sunday 22 Nov 2026, 10:00 in Tashkent and Almaty. Tournament t1 (padel,
  // Tashkent) runs 4–5 Dec and closes registration on 2 Dec at 18:00.
  var utcNow = DateTime.utc(2026, 11, 22, 5);
  late SampleBackend backend;

  setUp(() {
    utcNow = DateTime.utc(2026, 11, 22, 5);
    backend = SampleBackend(utcNow: () => utcNow, meName: 'Sam');
  });

  Matcher refuses(TournamentError error) => throwsA(isA<TournamentException>().having((e) => e.error, 'error', error));

  /// A fresh category of a tournament, made as an admin would.
  Future<String> makeCategory({
    String tournament = 't1',
    int cap = 1,
    CategoryKind kind = CategoryKind.singles,
    int minLevel = 1,
    int maxLevel = 5,
    int fee = 100000,
    bool waitlist = true,
  }) => backend.admin.saveCategory(
    CategoryDraft(
      tournamentId: tournament,
      name: const LocalizedText.all('Test'),
      kind: kind,
      minLevel: minLevel,
      maxLevel: maxLevel,
      fee: fee,
      cap: cap,
      waitlistEnabled: waitlist,
    ),
  );

  Future<TournamentCategory> categoryOf(String id, {String tournament = 't1'}) async =>
      (await backend.tournament.get(tournament)).category(id);

  Future<List<AppNotification>> inboxOf(String kind) async => [
    for (final n in await backend.inbox())
      if (n.kind == kind) n,
  ];

  group('the sample tournaments', () {
    test('every tournament has categories whose places add up, and a deadline before it starts', () async {
      for (final city in kCities) {
        for (final t in await backend.tournament.list(city.id)) {
          expect(t.categories, isNotEmpty, reason: t.id);
          expect(t.slotsTotal, t.categories.fold<int>(0, (sum, c) => sum + c.cap));
          expect(t.slotsFilled, t.categories.fold<int>(0, (sum, c) => sum + c.filled));
          expect(t.registrationDeadline.isBefore(t.start), isTrue, reason: t.id);
          expect(t.registrationOpen, isTrue, reason: t.id);
          expect(t.currency, city.currency);
        }
      }
    });

    test('the old list still shows them as TournamentItems, full where nothing is left', () async {
      final items = await backend.tournaments('tashkent');
      expect(items.map((t) => t.id), ['t1', 't2']);
      final full = {for (final t in items) t.id: t.slotsFilled >= t.slotsTotal};
      expect(full, {'t1': false, 't2': true});
      expect(items.first.minFee, 300000);
      expect(items.first.maxFee, 500000);
    });

    test('a tournament can be looked up, filtered by sport and sorted by title', () async {
      expect((await backend.tournament.get('t3')).categories, hasLength(2));
      await expectLater(backend.tournament.get('nope'), refuses(TournamentError.notFound));
      expect((await backend.tournament.list('tashkent', sportId: 'football')).map((t) => t.id), ['t2']);
      expect(await backend.tournament.list('almaty', sportId: 'football'), isEmpty);
      // A tournament that sorts first by title but starts last.
      final first = await backend.admin.saveTournament(
        TournamentDraft(
          cityId: 'tashkent',
          sportId: 'padel',
          start: DateTime.utc(2026, 12, 30),
          end: DateTime.utc(2026, 12, 30),
          title: const LocalizedText(ru: 'Аа'),
        ),
      );
      expect((await backend.tournament.list('tashkent')).map((t) => t.id), ['t1', 't2', first]);
      expect((await backend.tournament.list('tashkent', sort: TournamentSort.az)).map((t) => t.id), [
        first,
        't1',
        't2',
      ]);
      // The padel cup (4–5 Dec) ended before 6 Dec.
      expect((await backend.tournament.list('tashkent', from: DateTime.utc(2026, 12, 6))).map((t) => t.id), [
        't2',
        first,
      ]);
    });
  });

  group('singles', () {
    test('register until the cap, then full: the cap is never exceeded', () async {
      final cat = await makeCategory(cap: 2);
      await backend.registerAs('p1', cat);
      final mine = await backend.tournament.register(cat);
      expect(mine.status, RegistrationStatus.registered);
      expect(mine.role, RegistrationRole.registrant);
      expect(mine.registrant.id, kMeId);
      await expectLater(backend.registerAs('p5', cat), refuses(TournamentError.full));

      final c = await categoryOf(cat);
      expect((c.filled, c.full, c.myStatus), (2, true, RegistrationStatus.registered));
      final t = await backend.tournament.get('t1');
      expect(t.myRegistrations.single.id, mine.id);
      expect(t.slotsFilled, 9 + 8 + 2 + 2);
    });

    test('registering twice, or outside the level range, is refused', () async {
      final open = await makeCategory(cap: 3);
      await backend.tournament.register(open);
      await expectLater(backend.tournament.register(open), refuses(TournamentError.alreadyRegistered));

      final advanced = await makeCategory(cap: 3, minLevel: 4);
      await expectLater(backend.tournament.register(advanced), refuses(TournamentError.levelOutOfRange));
      await expectLater(backend.registerAs('p7', advanced), completes);
    });

    test('a partner cannot be named for singles, and the category must be of an active tournament', () async {
      final cat = await makeCategory(cap: 3);
      await expectLater(backend.tournament.register(cat, partnerId: 'p1'), refuses(TournamentError.invalidArgument));
      await expectLater(backend.tournament.register('missing'), refuses(TournamentError.notFound));
    });

    test('the fee is locked when registering', () async {
      final cat = await makeCategory(cap: 3, fee: 100000);
      final mine = await backend.tournament.register(cat);
      await backend.admin.saveCategory(CategoryDraft.from(await categoryOf(cat))..fee = 250000);
      expect((await categoryOf(cat)).fee, 250000);
      final entry = (await backend.tournament.myRegistrations()).single;
      expect((entry.fee, entry.currency), (100000, Currency.uzs));
      expect(entry.id, mine.id);
    });

    test('registering tells the player, in the inbox, with the tournament to open', () async {
      final cat = await makeCategory(cap: 3);
      final mine = await backend.tournament.register(cat);
      final note = (await inboxOf('tournament_registered')).single;
      expect(note.category, 'tournaments');
      expect(note.payload['registration_id'], mine.id);
      expect(note.payload['tournament_id'], 't1');
      expect(note.payload['category_id'], cat);
      expect((note.payload['title'] as Map)['en'], 'Tashkent Padel Cup');
      expect((note.payload['category_name'] as Map).keys, containsAll(['uz', 'ru', 'kk', 'en']));
      expect(note.route, '/tournaments/t1');
    });
  });

  group('the deadline', () {
    test('registration and cancelling work until 18:00 on 2 Dec, then nothing does', () async {
      final cat = await makeCategory(cap: 3);
      final other = await makeCategory(cap: 3);
      final mine = await backend.tournament.register(cat);

      // 17:59 local on 2 Dec.
      utcNow = DateTime.utc(2026, 12, 2, 12, 59);
      expect((await backend.tournament.get('t1')).registrationOpen, isTrue);
      await backend.tournament.register(other);

      utcNow = DateTime.utc(2026, 12, 2, 13);
      expect((await backend.tournament.get('t1')).registrationOpen, isFalse);
      await expectLater(backend.registerAs('p1', cat), refuses(TournamentError.deadlinePassed));
      await expectLater(backend.tournament.cancel(mine.id), refuses(TournamentError.deadlinePassed));
      expect(
        (await backend.tournament.myRegistrations()).map((r) => r.status),
        everyElement(RegistrationStatus.registered),
      );
    });

    test('a spot freed after the deadline goes to nobody; an admin can still offer it', () async {
      final cat = await makeCategory(cap: 1);
      final first = await backend.registerAs('p1', cat);
      final waiting = await backend.tournament.joinWaitlist(cat);
      utcNow = DateTime.utc(2026, 12, 2, 13);
      await backend.admin.removeRegistration(first.id);
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.waitlisted);

      expect(await backend.admin.offerNext(cat), 1);
      final offered = (await backend.tournament.myRegistrations()).single;
      expect(offered.id, waiting.id);
      expect(offered.status, RegistrationStatus.offered);
      // A full 24 hours, not cut at the deadline.
      expect(offered.offerExpiresAt, DateTime.utc(2026, 12, 3, 18));
      expect((await backend.tournament.claimOffer(waiting.id)).status, RegistrationStatus.registered);
    });
  });

  group('the waitlist', () {
    test('joining needs a full category with the waitlist on', () async {
      final room = await makeCategory(cap: 2);
      await expectLater(backend.tournament.joinWaitlist(room), refuses(TournamentError.notFull));
      final closed = await makeCategory(cap: 1, waitlist: false);
      await backend.registerAs('p1', closed);
      await expectLater(backend.tournament.joinWaitlist(closed), refuses(TournamentError.waitlistClosed));
    });

    test('cancelling offers the spot to the first in line, who holds it for 24 hours', () async {
      final cat = await makeCategory(cap: 1);
      final first = await backend.registerAs('p1', cat);
      final mine = await backend.tournament.joinWaitlist(cat);
      final third = await backend.joinWaitlistAs('p5', cat);
      expect((mine.status, mine.waitlistPlace), (RegistrationStatus.waitlisted, 1));
      expect(third.waitlistPlace, 2);
      expect((await categoryOf(cat)).waitlistCount, 2);

      await backend.cancelRegistrationAs('p1', first.id);
      final offered = (await backend.tournament.myRegistrations()).single;
      expect(offered.status, RegistrationStatus.offered);
      expect(offered.offerExpiresAt, DateTime.utc(2026, 11, 23, 10));
      final note = (await inboxOf('tournament_spot_offered')).single;
      expect(note.payload['offer_expires_local'], '2026-11-23T10:00:00');
      expect(note.route, '/tournaments/t1');

      // The offer holds the spot: nobody else can take it, counted or not.
      expect((await categoryOf(cat)).filled, 1);
      await expectLater(backend.registerAs('p7', cat), refuses(TournamentError.full));

      final claimed = await backend.tournament.claimOffer(mine.id);
      expect(claimed.status, RegistrationStatus.registered);
      expect((await categoryOf(cat)).filled, 1);
      // The one behind keeps waiting.
      await expectLater(backend.claimOfferAs('p5', third.id), refuses(TournamentError.notFound));
    });

    test('an offer not claimed in 24 hours lapses and goes to the next in line', () async {
      final cat = await makeCategory(cap: 1);
      final first = await backend.registerAs('p1', cat);
      final mine = await backend.tournament.joinWaitlist(cat);
      final next = await backend.joinWaitlistAs('p5', cat);
      await backend.cancelRegistrationAs('p1', first.id);

      utcNow = utcNow.add(const Duration(hours: 24));
      await expectLater(backend.tournament.claimOffer(mine.id), refuses(TournamentError.notFound));
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.lapsed);
      expect((await backend.claimOfferAs('p5', next.id)).status, RegistrationStatus.registered);
      expect((await categoryOf(cat)).filled, 1);
    });

    test('an offer never runs past the deadline', () async {
      final cat = await makeCategory(cap: 1);
      final first = await backend.registerAs('p1', cat);
      final mine = await backend.tournament.joinWaitlist(cat);
      // 17:00 on 2 Dec: one hour to the deadline.
      utcNow = DateTime.utc(2026, 12, 2, 12);
      await backend.cancelRegistrationAs('p1', first.id);
      final offered = (await backend.tournament.myRegistrations()).single;
      expect(offered.id, mine.id);
      expect(offered.offerExpiresAt, DateTime.utc(2026, 12, 2, 18));
    });

    test('a spot freed by an admin, or a raised cap, goes to the waitlist too', () async {
      final cat = await makeCategory(cap: 1);
      await backend.registerAs('p1', cat);
      final mine = await backend.tournament.joinWaitlist(cat);
      expect(mine.status, RegistrationStatus.waitlisted);
      await backend.admin.saveCategory(CategoryDraft.from(await categoryOf(cat))..cap = 2);
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.offered);
    });
  });

  group('pairs', () {
    test('pending until the partner accepts: not counted, 48 hours to answer', () async {
      final cat = await makeCategory(cap: 1, kind: CategoryKind.pairs);
      final mine = await backend.tournament.register(cat, partnerId: 'p1');
      expect(mine.status, RegistrationStatus.pendingPartner);
      expect(mine.partner, const PlayerRef(id: 'p1', name: 'Aziz'));
      expect(mine.partnerExpiresAt, DateTime.utc(2026, 11, 24, 10));
      expect((await categoryOf(cat)).filled, 0);

      // Pending pairs hold nothing: a second pair can be pending too.
      final rival = await backend.registerAs('p5', cat, partnerId: 'p7');
      expect(rival.status, RegistrationStatus.pendingPartner);

      final accepted = await backend.respondPartnerAs('p1', mine.id, accept: true);
      expect(accepted.status, RegistrationStatus.registered);
      expect(accepted.role, RegistrationRole.partner);
      expect(accepted.partnerConfirmed, isTrue);
      expect((await categoryOf(cat)).filled, 1);
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.registered);

      // The category filled meanwhile: the second partner is told so.
      await expectLater(backend.respondPartnerAs('p7', rival.id, accept: true), refuses(TournamentError.full));
      expect((await categoryOf(cat)).filled, 1);
    });

    test('the invite shows up for the partner, and accepting tells the registrant', () async {
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final invite = await backend.registerAs('p1', cat, partnerId: kMeId);
      final tournament = await backend.tournament.get('t1');
      expect(tournament.category(cat).myStatus, RegistrationStatus.pendingPartner);
      expect(tournament.myRegistrations.single.role, RegistrationRole.partner);
      final note = (await inboxOf('tournament_partner_invite')).single;
      expect(note.category, 'invites');
      expect(note.payload['actor_name'], 'Aziz');
      expect(note.route, '/tournaments/t1');

      final accepted = await backend.tournament.respondPartner(invite.id, accept: true);
      expect((accepted.status, accepted.role), (RegistrationStatus.registered, RegistrationRole.partner));
      expect((await inboxOf('tournament_registered')), hasLength(1));
    });

    test('declining tells the registrant and frees the partner', () async {
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final mine = await backend.tournament.register(cat, partnerId: 'p1');
      final declined = await backend.respondPartnerAs('p1', mine.id, accept: false);
      expect(declined.status, RegistrationStatus.declined);
      final note = (await inboxOf('tournament_partner_declined')).single;
      expect(note.payload['actor_name'], 'Aziz');
      expect((await categoryOf(cat)).myStatus, isNull);
      await expectLater(backend.respondPartnerAs('p1', mine.id, accept: true), refuses(TournamentError.notFound));
      await expectLater(backend.tournament.register(cat, partnerId: 'p1'), completes);
    });

    test('an invite that is not answered in 48 hours expires', () async {
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final mine = await backend.tournament.register(cat, partnerId: 'p1');
      utcNow = utcNow.add(const Duration(hours: 47));
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.pendingPartner);
      utcNow = utcNow.add(const Duration(hours: 1));
      await expectLater(backend.respondPartnerAs('p1', mine.id, accept: true), refuses(TournamentError.notFound));
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.expired);
      expect(await inboxOf('tournament_partner_expired'), hasLength(1));
      // Expired entries block nobody.
      await expectLater(backend.tournament.register(cat, partnerId: 'p1'), completes);
    });

    test('an invite runs out at the deadline if that comes first', () async {
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      utcNow = DateTime.utc(2026, 12, 2, 6);
      final mine = await backend.tournament.register(cat, partnerId: 'p1');
      expect(mine.partnerExpiresAt, DateTime.utc(2026, 12, 2, 18));
    });

    test('a pair needs a partner who exists, who is not the registrant, and whose level fits', () async {
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs, minLevel: 3);
      await expectLater(backend.tournament.register(cat), refuses(TournamentError.invalidArgument));
      await expectLater(backend.tournament.register(cat, partnerId: kMeId), refuses(TournamentError.invalidArgument));
      await expectLater(backend.tournament.register(cat, partnerId: 'nobody'), refuses(TournamentError.notFound));
      await expectLater(backend.tournament.register(cat, partnerId: 'p2'), refuses(TournamentError.levelOutOfRange));
      await expectLater(backend.tournament.register(cat, partnerId: 'p1'), completes);
    });

    test('a partner already confirmed in the category is unavailable', () async {
      final cat = await makeCategory(cap: 3, kind: CategoryKind.pairs);
      final pair = await backend.registerAs('p1', cat, partnerId: 'p5');
      await backend.respondPartnerAs('p5', pair.id, accept: true);
      await expectLater(backend.tournament.register(cat, partnerId: 'p5'), refuses(TournamentError.partnerUnavailable));
      await expectLater(backend.tournament.register(cat, partnerId: 'p1'), refuses(TournamentError.partnerUnavailable));
    });

    test('a pair on the waitlist is offered a spot only once the partner confirmed', () async {
      final cat = await makeCategory(cap: 1, kind: CategoryKind.pairs);
      final held = await backend.registerAs('p5', cat, partnerId: 'p7');
      await backend.respondPartnerAs('p7', held.id, accept: true);
      final waiting = await backend.tournament.joinWaitlist(cat, partnerId: 'p1');
      expect(
        (waiting.status, waiting.partnerConfirmed, waiting.waitlistPlace),
        (RegistrationStatus.waitlisted, false, null),
      );

      await backend.cancelRegistrationAs('p7', held.id);
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.waitlisted);

      // The partner confirms: the free spot is offered at once.
      await backend.respondPartnerAs('p1', waiting.id, accept: true);
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.offered);
      expect((await backend.claimOfferAs('p1', waiting.id)).status, RegistrationStatus.registered);
    });
  });

  group('cancelling and other people\'s entries', () {
    test('the registrant, or the confirmed partner, cancels; a spot goes to the waitlist', () async {
      final cat = await makeCategory(cap: 1, kind: CategoryKind.pairs);
      final pair = await backend.registerAs('p5', cat, partnerId: kMeId);
      // Not confirmed yet: the invited player cannot cancel the entry.
      await expectLater(backend.tournament.cancel(pair.id), refuses(TournamentError.notFound));
      await backend.tournament.respondPartner(pair.id, accept: true);
      final cancelled = await backend.tournament.cancel(pair.id);
      expect(cancelled.status, RegistrationStatus.cancelled);
      expect(cancelled.role, RegistrationRole.partner);
      expect((await categoryOf(cat)).filled, 0);
      expect((await backend.tournament.myRegistrations()).single.status, RegistrationStatus.cancelled);
    });

    test('cancelling a pair tells the other player, confirmed or only invited', () async {
      // The confirmed partner cancels a registered pair: I, the registrant, am told.
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final mine = await backend.tournament.register(cat, partnerId: 'p1');
      await backend.respondPartnerAs('p1', mine.id, accept: true);
      await backend.cancelRegistrationAs('p1', mine.id);
      final note = (await inboxOf('tournament_partner_cancelled')).single;
      expect(note.category, 'tournaments');
      expect(note.payload['actor_name'], 'Aziz');
      expect(note.payload['registration_id'], mine.id);
      expect(note.payload['tournament_id'], 't1');
      expect(note.payload['category_id'], cat);
      expect(note.route, '/tournaments/t1');

      // A registrant cancels a pending pair: I, the invited partner, am told.
      final other = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final invite = await backend.registerAs('p5', other, partnerId: kMeId);
      await backend.cancelRegistrationAs('p5', invite.id);
      final notes = await inboxOf('tournament_partner_cancelled');
      expect(notes, hasLength(2));
      expect(notes.map((n) => n.payload['registration_id']), contains(invite.id));

      // My own cancel of a singles entry tells nobody (and not me).
      final single = await makeCategory(cap: 2);
      final s = await backend.tournament.register(single);
      await backend.tournament.cancel(s.id);
      expect(await inboxOf('tournament_partner_cancelled'), hasLength(2));
    });

    test('nobody acts on someone else\'s entry', () async {
      final cat = await makeCategory(cap: 2);
      final theirs = await backend.registerAs('p1', cat);
      await expectLater(backend.tournament.cancel(theirs.id), refuses(TournamentError.notFound));
      await expectLater(backend.tournament.claimOffer(theirs.id), refuses(TournamentError.notFound));
      await expectLater(backend.tournament.respondPartner(theirs.id, accept: true), refuses(TournamentError.notFound));
      await expectLater(backend.tournament.cancel('missing'), refuses(TournamentError.notFound));
      expect((await categoryOf(cat)).filled, 1);
      // A cancelled entry cannot be cancelled again.
      await backend.cancelRegistrationAs('p1', theirs.id);
      await expectLater(backend.cancelRegistrationAs('p1', theirs.id), refuses(TournamentError.notFound));
    });

    test('my registrations lists both roles, newest first, with the tournament', () async {
      final single = await makeCategory(cap: 2);
      final pairs = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final first = await backend.tournament.register(single);
      utcNow = utcNow.add(const Duration(minutes: 1));
      final invite = await backend.registerAs('p1', pairs, partnerId: kMeId);
      final entries = await backend.tournament.myRegistrations();
      expect(entries.map((r) => r.id), [invite.id, first.id]);
      expect(entries.map((r) => r.role), [RegistrationRole.partner, RegistrationRole.registrant]);
      expect(entries.first.tournament?.id, 't1');
      expect(entries.first.tournament?.title.en, 'Tashkent Padel Cup');
    });

    test('my registrations say whether registration is open, and leave out inactive tournaments', () async {
      final cat = await makeCategory(cap: 2);
      await backend.tournament.register(cat);
      expect((await backend.tournament.myRegistrations()).single.tournament?.registrationOpen, isTrue);

      final draft = TournamentDraft.from(await backend.tournament.get('t1'))..registrationDeadline = DateTime.utc(2026, 11, 20);
      await backend.admin.saveTournament(draft);
      expect((await backend.tournament.myRegistrations()).single.tournament?.registrationOpen, isFalse);

      await backend.admin.saveTournament(draft..active = false);
      expect(await backend.tournament.myRegistrations(), isEmpty);
    });
  });

  group('a blocked player', () {
    test('cannot register, accept, join the waitlist or claim; may still decline; an admin can add them', () async {
      final room = await makeCategory(cap: 3);
      final full = await makeCategory(cap: 1);
      final pairs = await makeCategory(cap: 3, kind: CategoryKind.pairs);
      final offeredFor = await makeCategory(cap: 1);
      final invite = await backend.registerAs('p1', pairs, partnerId: kMeId);
      final declinable = await backend.registerAs('p5', pairs, partnerId: kMeId);
      final holder = await backend.registerAs('p1', offeredFor);
      await backend.tournament.joinWaitlist(offeredFor);
      await backend.registerAs('p1', full);
      await backend.cancelRegistrationAs('p1', holder.id);
      expect((await backend.tournament.myRegistrations()).any((r) => r.status == RegistrationStatus.offered), isTrue);

      // No-shows take the score below 50: blocked.
      for (final ref in ['b1', 'b2', 'b3']) {
        backend.recordReliability(kMeId, ReliabilityKind.noShow, ref);
      }
      expect((await backend.settings()).reliability.isBlocked, isTrue);

      await expectLater(backend.tournament.register(room), refuses(TournamentError.reliabilityTooLow));
      await expectLater(backend.tournament.joinWaitlist(full), refuses(TournamentError.reliabilityTooLow));
      await expectLater(
        backend.tournament.respondPartner(invite.id, accept: true),
        refuses(TournamentError.reliabilityTooLow),
      );
      final offered = (await backend.tournament.myRegistrations()).firstWhere(
        (r) => r.status == RegistrationStatus.offered,
      );
      await expectLater(backend.tournament.claimOffer(offered.id), refuses(TournamentError.reliabilityTooLow));

      expect(
        (await backend.tournament.respondPartner(declinable.id, accept: false)).status,
        RegistrationStatus.declined,
      );
      expect((await backend.admin.addRegistration(room, kMeId)).registration.status, RegistrationStatus.registered);
    });
  });

  group('finding a partner by phone', () {
    test('an exact number finds the player, whatever its spacing; nothing else does', () async {
      expect(await backend.tournament.findPlayerByPhone('+998 90 100-00-01'), const PlayerRef(id: 'p1', name: 'Aziz'));
      expect(await backend.tournament.findPlayerByPhone('+998901000009'), isNull);
      expect(await backend.tournament.findPlayerByPhone('1000001'), isNull);
      expect(await backend.tournament.findPlayerByPhone('not a number'), isNull);
    });

    test('at most 20 lookups an hour', () async {
      for (var i = 0; i < 20; i++) {
        await backend.tournament.findPlayerByPhone('+998901000001');
      }
      await expectLater(backend.tournament.findPlayerByPhone('+998901000001'), refuses(TournamentError.rateLimited));
      utcNow = utcNow.add(const Duration(hours: 1, minutes: 1));
      expect(await backend.tournament.findPlayerByPhone('+998901000001'), isNotNull);
    });
  });

  group('admin', () {
    test('adding a player bypasses the level range and the deadline, never the cap', () async {
      final cat = await makeCategory(cap: 1, minLevel: 4);
      utcNow = DateTime.utc(2026, 12, 2, 13);
      final added = await backend.admin.addRegistration(cat, 'p1');
      expect(added.registration.status, RegistrationStatus.registered);
      expect(added.adminOverride, isTrue);
      expect(added.registrantPhone, '+998901000001');
      await expectLater(backend.admin.addRegistration(cat, 'p2'), refuses(TournamentError.full));
      await expectLater(backend.admin.addRegistration(cat, 'p1'), refuses(TournamentError.alreadyRegistered));
      await expectLater(backend.admin.addRegistration(cat, 'nobody'), refuses(TournamentError.notFound));
    });

    test('adding a pair confirms the partner at once', () async {
      final cat = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      await expectLater(backend.admin.addRegistration(cat, 'p1'), refuses(TournamentError.invalidArgument));
      final added = await backend.admin.addRegistration(cat, 'p1', partnerId: kMeId);
      expect((added.registration.status, added.registration.partnerConfirmed), (RegistrationStatus.registered, true));
      expect(await inboxOf('tournament_registered'), hasLength(1));
      await expectLater(
        backend.admin.addRegistration(cat, 'p5', partnerId: 'p1'),
        refuses(TournamentError.partnerUnavailable),
      );
    });

    test('removing frees the spot for the waitlist and tells the player', () async {
      final cat = await makeCategory(cap: 1);
      final mine = await backend.tournament.register(cat);
      final waiting = await backend.joinWaitlistAs('p1', cat);
      final removed = await backend.admin.removeRegistration(mine.id);
      expect(removed.registration.status, RegistrationStatus.removed);
      final note = (await inboxOf('tournament_removed')).single;
      expect(note.route, '/tournaments/t1');
      expect((await backend.claimOfferAs('p1', waiting.id)).status, RegistrationStatus.registered);
      await expectLater(backend.admin.removeRegistration(mine.id), refuses(TournamentError.notFound));
    });

    test('moving keeps the fee, needs room, and tells the player where from', () async {
      final from = await makeCategory(cap: 2, fee: 100000);
      final to = await makeCategory(cap: 1, fee: 300000);
      final other = await makeCategory(cap: 2, kind: CategoryKind.pairs);
      final mine = await backend.tournament.register(from);
      await expectLater(backend.admin.moveRegistration(mine.id, other), refuses(TournamentError.invalidArgument));
      await expectLater(backend.admin.moveRegistration(mine.id, from), refuses(TournamentError.invalidArgument));

      final moved = await backend.admin.moveRegistration(mine.id, to);
      expect(moved.registration.categoryId, to);
      expect(moved.registration.fee, 100000);
      final note = (await inboxOf('tournament_moved')).single;
      expect((note.payload['from_category_name'] as Map).keys, containsAll(['uz', 'ru', 'kk', 'en']));
      expect(note.route, '/tournaments/t1');

      final second = await backend.registerAs('p1', from);
      await expectLater(backend.admin.moveRegistration(second.id, to), refuses(TournamentError.full));
    });

    test('paid is a flag on registered entries only, and its first time is kept', () async {
      final cat = await makeCategory(cap: 2);
      final mine = await backend.tournament.register(cat);
      final paid = await backend.admin.setPaid(mine.id, true);
      expect((paid.registration.paid, paid.registration.status), (true, RegistrationStatus.registered));
      expect(paid.paidAt, utcNow);
      utcNow = utcNow.add(const Duration(hours: 1));
      expect((await backend.admin.setPaid(mine.id, true)).paidAt, DateTime.utc(2026, 11, 22, 5));
      expect((await backend.admin.setPaid(mine.id, false)).registration.paid, isFalse);

      await backend.tournament.cancel(mine.id);
      await expectLater(backend.admin.setPaid(mine.id, true), refuses(TournamentError.notMarkable));
      await expectLater(backend.admin.setPaid('missing', true), refuses(TournamentError.notFound));
    });

    test('the entries of a tournament come by category, counted first, waitlist in order', () async {
      final cat = await makeCategory(cap: 1);
      await backend.registerAs('p5', cat);
      final waitlisted = await backend.joinWaitlistAs('p1', cat);
      await backend.joinWaitlistAs('p2', cat);
      final rows = (await backend.admin.registrations('t1')).where((r) => r.registration.categoryId == cat).toList();
      expect(rows.map((r) => r.registration.status), [
        RegistrationStatus.registered,
        RegistrationStatus.waitlisted,
        RegistrationStatus.waitlisted,
      ]);
      expect(rows[1].registration.id, waitlisted.id);
      expect(rows[1].waitlistPosition, lessThan(rows[2].waitlistPosition!));
      await expectLater(backend.admin.registrations('nope'), refuses(TournamentError.notFound));
    });

    test('a category cannot shrink below its entries, change kind with entries or be deleted with history', () async {
      final cat = await makeCategory(cap: 3);
      final mine = await backend.tournament.register(cat);
      final theirs = await backend.registerAs('p1', cat);
      final draft = CategoryDraft.from(await categoryOf(cat));
      await expectLater(backend.admin.saveCategory(draft..cap = 1), refuses(TournamentError.invalidArgument));
      draft.cap = 3;
      await expectLater(
        backend.admin.saveCategory(draft..kind = CategoryKind.pairs),
        refuses(TournamentError.hasRegistrations),
      );
      await expectLater(
        backend.admin.saveCategory(
          draft
            ..minLevel = 5
            ..maxLevel = 1,
        ),
        refuses(TournamentError.invalidArgument),
      );

      await backend.tournament.cancel(mine.id);
      await backend.cancelRegistrationAs('p1', theirs.id);
      // Cancelled entries are history: the category stays.
      await expectLater(backend.admin.deleteCategory(cat), refuses(TournamentError.hasRegistrations));
      final empty = await makeCategory();
      await backend.admin.deleteCategory(empty);
      await expectLater(backend.admin.deleteCategory(empty), refuses(TournamentError.notFound));
    });

    test('a tournament keeps at least one category', () async {
      final fresh = await backend.admin.saveTournament(
        TournamentDraft(
          cityId: 'tashkent',
          sportId: 'padel',
          start: DateTime.utc(2026, 12, 20),
          end: DateTime.utc(2026, 12, 21),
          title: const LocalizedText(en: 'New Cup'),
        ),
      );
      final tournament = (await backend.admin.tournaments()).firstWhere((t) => t.tournament.id == fresh);
      expect(tournament.categoryCount, 1);
      final only = tournament.tournament.categories.single;
      expect((only.kind, only.cap, only.fee), (CategoryKind.singles, 16, 0));
      await expectLater(backend.admin.deleteCategory(only.id), refuses(TournamentError.invalidArgument));
    });

    test('saving a tournament checks what the database checks', () async {
      TournamentDraft draft({
        String city = 'tashkent',
        String sport = 'padel',
        String? venue,
        LocalizedText title = const LocalizedText(en: 'Cup'),
        DateTime? start,
        DateTime? end,
        DateTime? deadline,
        String? cover,
      }) => TournamentDraft(
        cityId: city,
        sportId: sport,
        venueId: venue,
        title: title,
        start: start ?? DateTime.utc(2026, 12, 20),
        end: end ?? DateTime.utc(2026, 12, 21),
        registrationDeadline: deadline,
        coverUrl: cover,
      );
      final admin = backend.admin;
      await expectLater(admin.saveTournament(draft(city: 'paris')), refuses(TournamentError.invalidArgument));
      await expectLater(admin.saveTournament(draft(sport: 'curling')), refuses(TournamentError.invalidArgument));
      await expectLater(admin.saveTournament(draft(venue: 'v4')), refuses(TournamentError.invalidArgument));
      await expectLater(
        admin.saveTournament(draft(title: const LocalizedText())),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        admin.saveTournament(draft(start: DateTime.utc(2026, 12, 22))),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        admin.saveTournament(draft(cover: 'http://x.example/a.jpg')),
        refuses(TournamentError.invalidArgument),
      );
      // After the end of the last day.
      await expectLater(
        admin.saveTournament(draft(deadline: DateTime.utc(2026, 12, 22, 0, 1))),
        refuses(TournamentError.invalidArgument),
      );
      final id = await admin.saveTournament(
        draft(venue: 'v1', cover: 'https://x.example/a.jpg', deadline: DateTime.utc(2026, 12, 19, 12)),
      );
      final saved = (await backend.tournament.get(id));
      expect(saved.registrationDeadline, DateTime.utc(2026, 12, 19, 12));
      expect(saved.venueName.en, 'Lochin Padel Club');
      expect(saved.coverUrl, 'https://x.example/a.jpg');
      // No deadline: 00:00 on the first day.
      final plain = await backend.tournament.get(await admin.saveTournament(draft()));
      expect(plain.registrationDeadline, DateTime.utc(2026, 12, 20));
    });

    test('a tournament with entries cannot move to another city; an inactive one is hidden from players', () async {
      final cat = await makeCategory(cap: 2);
      await backend.tournament.register(cat);
      final draft = TournamentDraft.from(await backend.tournament.get('t1'))
        ..venueId = null
        ..cityId = 'almaty';
      await expectLater(backend.admin.saveTournament(draft), refuses(TournamentError.hasRegistrations));

      draft
        ..cityId = 'tashkent'
        ..active = false;
      await backend.admin.saveTournament(draft);
      await expectLater(backend.tournament.get('t1'), refuses(TournamentError.notFound));
      expect((await backend.tournament.list('tashkent')).map((t) => t.id), ['t2']);
      expect((await backend.admin.tournaments()).map((t) => t.tournament.id), containsAll(['t1', 't2', 't3']));
      await expectLater(backend.registerAs('p1', cat), refuses(TournamentError.notFound));
    });

    test('every change is in the audit log', () async {
      final cat = await makeCategory(cap: 2);
      final mine = await backend.tournament.register(cat);
      await backend.admin.setPaid(mine.id, true);
      await backend.admin.removeRegistration(mine.id);
      final actions = (await backend.admin.auditLog()).map((e) => e.action);
      expect(actions, containsAll(['create_category', 'set_registration_paid', 'remove_registration']));
    });

    test('the dashboard keeps currencies apart and counts only paid, registered entries', () async {
      final uzs = await makeCategory(cap: 3, fee: 200000);
      final kzt = await makeCategory(tournament: 't3', cap: 3, fee: 20000);
      final a = await backend.tournament.register(uzs);
      final b = await backend.tournament.register(kzt);
      final gone = await backend.registerAs('p1', uzs);
      for (final id in [a.id, b.id, gone.id]) {
        await backend.admin.setPaid(id, true);
      }
      await backend.admin.removeRegistration(gone.id);
      await backend.registerAs('p5', uzs);

      final today = DateTime.utc(2026, 11, 22);
      final all = await backend.admin.dashboard(from: today, to: today);
      expect(
        [for (final r in all.revenue) (r.currency, r.tournaments)],
        [(Currency.kzt, 20000), (Currency.uzs, 200000)],
      );
      expect(all.counts.registrations, 4);
      expect(all.users.total, 9);

      final almaty = await backend.admin.dashboard(cityId: 'almaty', from: today, to: today);
      expect([for (final r in almaty.revenue) r.currency], [Currency.kzt]);
      expect(almaty.counts.registrations, 1);

      final yesterday = DateTime.utc(2026, 11, 21);
      expect((await backend.admin.dashboard(from: yesterday, to: yesterday)).revenue, isEmpty);
    });

    test('the dashboard checks its period and city', () async {
      final day = DateTime.utc(2026, 11, 22);
      await expectLater(
        backend.admin.dashboard(from: day, to: day.subtract(const Duration(days: 1))),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        backend.admin.dashboard(from: day, to: day.add(const Duration(days: 366))),
        refuses(TournamentError.invalidArgument),
      );
      await expectLater(
        backend.admin.dashboard(cityId: 'paris', from: day, to: day),
        refuses(TournamentError.notFound),
      );
      await expectLater(backend.admin.dashboard(from: day, to: day.add(const Duration(days: 365))), completes);
    });
  });

  group('notifications', () {
    AppNotification note(String kind, [Map<String, Object?> payload = const {}]) => AppNotification(
      id: 'n',
      kind: kind,
      category: 'tournaments',
      payload: payload,
      createdAt: DateTime.utc(2026, 11, 22),
      read: false,
    );

    test('every tournament kind opens the tournament', () {
      for (final kind in [
        'tournament_registered',
        'tournament_partner_invite',
        'tournament_partner_accepted',
        'tournament_partner_declined',
        'tournament_partner_cancelled',
        'tournament_partner_expired',
        'tournament_spot_offered',
        'tournament_deadline_reminder',
        'tournament_removed',
        'tournament_moved',
      ]) {
        expect(note(kind, {'tournament_id': 't9'}).route, '/tournaments/t9', reason: kind);
        expect(note(kind).route, isNull, reason: '$kind without a tournament');
        expect(note(kind, {'tournament_id': ''}).route, isNull, reason: '$kind with an empty id');
      }
    });

    test('tournaments are a category a player can mute', () async {
      expect(kNotificationCategories, contains('tournaments'));
      await backend.saveSettings(const CommunitySettings(mutedCategories: {'tournaments'}));
      final cat = await makeCategory(cap: 2);
      await backend.tournament.register(cat);
      expect(await inboxOf('tournament_registered'), isEmpty);
    });
  });

  group('the types', () {
    test('which statuses hold a spot, and which are still in play', () {
      expect(
        [
          for (final s in RegistrationStatus.values)
            if (s.counted) s,
        ],
        [RegistrationStatus.registered, RegistrationStatus.offered],
      );
      expect(
        [
          for (final s in RegistrationStatus.values)
            if (s.live) s,
        ],
        [
          RegistrationStatus.pendingPartner,
          RegistrationStatus.registered,
          RegistrationStatus.waitlisted,
          RegistrationStatus.offered,
        ],
      );
    });

    test('a Tournament is a TournamentItem, so the cards and the home strip keep working', () async {
      final TournamentItem item = await backend.tournament.get('t1');
      expect(item.slotsTotal, 32);
      expect(item.slotsFilled, 19);
      expect(item.venueName.en, 'Lochin Padel Club');
    });
  });
}
