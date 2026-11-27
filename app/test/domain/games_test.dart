import 'package:actra/domain/games.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Game game({int spots = 4, List<String> participants = const ['host'], int min = 1, int max = 5}) => Game(
    id: 'g1',
    sportId: 'padel',
    cityId: 'tashkent',
    venueId: 'v1',
    hostId: 'host',
    start: DateTime.utc(2026, 11, 23, 19),
    end: DateTime.utc(2026, 11, 23, 20, 30),
    spots: spots,
    participantIds: participants,
    minLevel: min,
    maxLevel: max,
  );

  Player player(String id, {int? level}) =>
      Player(id: id, name: id, levels: level == null ? const {} : {'padel': level});

  JoinError errorOf(void Function() action) {
    try {
      action();
    } on JoinException catch (e) {
      return e.error;
    }
    fail('expected a JoinException');
  }

  test('joining adds the player and lowers the spots left', () {
    final joined = joinGame(game(), player('ali', level: 3));
    expect(joined.participantIds, ['host', 'ali']);
    expect(joined.spotsLeft, 2);
    expect(joined.isFull, isFalse);
  });

  test('a full game refuses further players', () {
    var g = game(spots: 2);
    g = joinGame(g, player('ali'));
    expect(g.isFull, isTrue);
    expect(errorOf(() => joinGame(g, player('vali'))), JoinError.full);
    expect(g.participantIds.length, lessThanOrEqualTo(g.spots));
  });

  test('joining twice is refused', () {
    final g = joinGame(game(), player('ali'));
    expect(errorOf(() => joinGame(g, player('ali'))), JoinError.alreadyJoined);
  });

  test('a player outside the level range is refused', () {
    expect(errorOf(() => joinGame(game(min: 3, max: 5), player('ali', level: 2))), JoinError.levelOutOfRange);
    expect(joinGame(game(min: 3, max: 5), player('ali', level: 3)).participantIds, contains('ali'));
  });

  test('a player with no level for the sport counts as level 1', () {
    expect(errorOf(() => joinGame(game(min: 2), player('ali'))), JoinError.levelOutOfRange);
    expect(joinGame(game(min: 1), player('ali')).participantIds, contains('ali'));
  });

  test('leaving removes the player and reopens the spot', () {
    final g = leaveGame(joinGame(game(spots: 2), player('ali')), 'ali');
    expect(g.participantIds, ['host']);
    expect(g.isFull, isFalse);
  });

  test('the host cannot leave and a stranger cannot leave', () {
    expect(errorOf(() => leaveGame(game(), 'host')), JoinError.hostCannotLeave);
    expect(errorOf(() => leaveGame(game(), 'ali')), JoinError.notParticipant);
  });

  group('invite-only games', () {
    Game inviteOnly() => Game(
      id: 'g2',
      sportId: 'padel',
      cityId: 'tashkent',
      venueId: 'v1',
      hostId: 'host',
      start: DateTime.utc(2026, 11, 23, 19),
      end: DateTime.utc(2026, 11, 23, 20, 30),
      spots: 4,
      participantIds: const ['host'],
      minLevel: 3,
      maxLevel: 5,
      visibility: GameVisibility.inviteOnly,
    );

    test('without an invite the game does not exist for the player', () {
      expect(errorOf(() => joinGame(inviteOnly(), player('ali', level: 4))), JoinError.notFound);
    });

    test('an invite opens the game and skips the level check', () {
      final joined = joinGame(inviteOnly(), player('ali', level: 1), invited: true);
      expect(joined.participantIds, ['host', 'ali']);
    });

    test('an invited player still cannot take a full game or join twice', () {
      final full = inviteOnly().copyWith(participantIds: ['host', 'a', 'b', 'c']);
      expect(errorOf(() => joinGame(full, player('ali'), invited: true)), JoinError.full);
      final once = joinGame(inviteOnly(), player('ali'), invited: true);
      expect(errorOf(() => joinGame(once, player('ali'), invited: true)), JoinError.alreadyJoined);
    });
  });

  test('a game on a map point has no venue', () {
    final g = Game(
      id: 'g3',
      sportId: 'running',
      cityId: 'tashkent',
      hostId: 'host',
      start: DateTime.utc(2026, 11, 23, 7),
      end: DateTime.utc(2026, 11, 23, 8),
      spots: 5,
      participantIds: const ['host'],
      kind: GameKind.mapPoint,
      meetingPoint: 'Bunyodkor park, main gate',
      meetingLat: 41.3,
      meetingLng: 69.2,
    );
    expect(g.venueId, isNull);
    expect(g.copyWith(participantIds: ['host', 'ali']).meetingPoint, 'Bunyodkor park, main gate');
    expect(g.copyWith(participantIds: ['host', 'ali']).kind, GameKind.mapPoint);
  });

  group('rating ranges', () {
    // 3.0-4.5, with the whole-number range the database derives from it.
    Game rated() => Game(
      id: 'g4',
      sportId: 'padel',
      cityId: 'tashkent',
      venueId: 'v1',
      hostId: 'host',
      start: DateTime.utc(2026, 11, 23, 19),
      end: DateTime.utc(2026, 11, 23, 20, 30),
      spots: 4,
      participantIds: const ['host'],
      minLevel: 3,
      maxLevel: 4,
      minRating: 3.0,
      maxRating: 4.5,
    );

    Player rating(String id, double value) =>
        Player(id: id, name: id, levels: {'padel': value.floor()}, ratings: {'padel': SportRating(rating: value, ratedGames: 12)});

    test('the rating decides, not the level: 4.7 is outside 3.0-4.5 although its level 4 is inside 3-4', () {
      expect(errorOf(() => joinGame(rated(), rating('ali', 4.7))), JoinError.levelOutOfRange);
      expect(joinGame(rated(), rating('ali', 4.5)).participantIds, ['host', 'ali']);
      expect(joinGame(rated(), rating('ali', 3.0)).participantIds, ['host', 'ali']);
    });

    test('an invited player skips the rating check', () {
      expect(joinGame(rated(), rating('ali', 4.7), invited: true).participantIds, ['host', 'ali']);
    });

    test('a player with no rating counts as 1.0', () {
      expect(player('ali', level: 3).ratingFor('padel'), 1.0);
      expect(errorOf(() => joinGame(rated(), player('ali', level: 3))), JoinError.levelOutOfRange);
    });

    test('copyWith keeps the rating range', () {
      final g = rated().copyWith(participantIds: ['host', 'ali']);
      expect(g.minRating, 3.0);
      expect(g.maxRating, 4.5);
    });
  });
}
