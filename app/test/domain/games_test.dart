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

  Player player(String id, {int? level}) => Player(id: id, name: id, levels: level == null ? const {} : {'padel': level});

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
}
