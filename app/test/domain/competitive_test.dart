import 'package:actra/domain/community.dart';
import 'package:actra/domain/competitive.dart';
import 'package:actra/domain/games.dart';
import 'package:actra/features/inbox/inbox_screen.dart';
import 'package:actra/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('questionnaire', () {
    test('the same values as the database: lowest, capped highest, and a mixed set', () {
      expect(questionnaireRating([0, 0, 0, 0, 0]), 1.00);
      expect(questionnaireRating([3, 3, 3, 3, 3]), 5.00);
      expect(questionnaireRating([1, 2, 1, 0, 2]), 2.70);
    });

    test('anything but five answers of 0-3 is refused', () {
      expect(() => questionnaireRating([1, 2, 1, 0]), throwsArgumentError);
      expect(() => questionnaireRating([1, 2, 1, 0, 2, 1]), throwsArgumentError);
      expect(() => questionnaireRating([1, 2, 1, 0, 4]), throwsArgumentError);
      expect(() => questionnaireRating([-1, 2, 1, 0, 2]), throwsArgumentError);
    });
  });

  group('rating and level', () {
    test('a rating is provisional for its first ten rated games', () {
      expect(const SportRating(rating: 3.5, ratedGames: 9).provisional, isTrue);
      expect(const SportRating(rating: 3.5, ratedGames: 10).provisional, isFalse);
    });

    test('the level is the whole part of the rating, capped at 5', () {
      expect(levelOfRating(1.0), 1);
      expect(levelOfRating(2.99), 2);
      expect(levelOfRating(5.0), 5);
      expect(levelOfRating(6.4), 5);
    });

    test('a level range becomes a rating range as the database converts it', () {
      expect(ratingRangeOfLevels(2, 4), (min: 2.0, max: 4.99));
      expect(ratingRangeOfLevels(3, 5), (min: 3.0, max: 7.0));
    });
  });

  group('match results', () {
    test('more sets win; equal sets go to more games; equal games are a draw', () {
      expect(matchWinner([(6, 4), (6, 4)]), MatchWinner.a);
      expect(matchWinner([(4, 6), (6, 4), (3, 6)]), MatchWinner.b);
      expect(matchWinner([(6, 0), (5, 7)]), MatchWinner.a);
      expect(matchWinner([(6, 4), (4, 6)]), MatchWinner.draw);
    });
  });

  group('rating changes (the same values as the database)', () {
    const provisional = SportRating(rating: 3.5);
    const established = SportRating(rating: 3.5, ratedGames: 10);

    List<double> news(List<RatingChange> changes) => [for (final c in changes) c.newRating];
    List<double> deltas(List<RatingChange> changes) => [for (final c in changes) c.delta];

    test('four provisional players at 3.50, 6-4 6-4: +0.13 and -0.13 (0.1275 rounds up)', () {
      final c = ratingChanges(
        sideA: [provisional, provisional],
        sideB: [provisional, provisional],
        sets: [(6, 4), (6, 4)],
      );
      expect(news(c.a), [3.63, 3.63]);
      expect(news(c.b), [3.37, 3.37]);
      expect(deltas(c.a), [0.13, 0.13]);
      expect(deltas(c.b), [-0.13, -0.13]);
      expect(c.a.first.oldRating, 3.5);
    });

    test('established players move less: +0.05 and -0.05', () {
      final c = ratingChanges(
        sideA: [established, established],
        sideB: [established, established],
        sets: [(6, 4), (6, 4)],
      );
      expect(news(c.a), [3.55, 3.55]);
      expect(news(c.b), [3.45, 3.45]);
    });

    test('a favourite wins small, an underdog wins big: 4.50 v 3.50, 6-0 6-0', () {
      const strong = SportRating(rating: 4.5);
      final favourite = ratingChanges(sideA: [strong], sideB: [provisional], sets: [(6, 0), (6, 0)]);
      expect(deltas(favourite.a), [0.03]);
      expect(deltas(favourite.b), [-0.03]);
      expect((favourite.a.single.newRating, favourite.b.single.newRating), (4.53, 3.47));

      final underdog = ratingChanges(sideA: [strong], sideB: [provisional], sets: [(0, 6), (0, 6)]);
      expect(deltas(underdog.a), [-0.34]);
      expect(deltas(underdog.b), [0.34]);
      expect((underdog.a.single.newRating, underdog.b.single.newRating), (4.16, 3.84));
    });

    test('a draw at equal ratings changes nothing', () {
      final c = ratingChanges(sideA: [provisional], sideB: [provisional], sets: [(6, 4), (4, 6)]);
      expect(deltas(c.a), [0.0]);
      expect(deltas(c.b), [0.0]);
      expect(news(c.a), [3.5]);
    });

    test('a player with no rating starts at the average of the others, capped at 5.00', () {
      final c = ratingChanges(
        sideA: [const SportRating(rating: 3.0), const SportRating(rating: 4.0)],
        sideB: [const SportRating(rating: 5.0), null],
        sets: [(6, 4), (6, 4)],
      );
      expect(c.b.last.oldRating, 4.0);

      const six = SportRating(rating: 6.0, ratedGames: 20);
      final capped = ratingChanges(sideA: [six, six], sideB: [six, null], sets: [(6, 4), (6, 4)]);
      expect(capped.b.last.oldRating, 5.0);
    });

    test('when nobody has a rating everyone starts at 2.50', () {
      final c = ratingChanges(sideA: [null, null], sideB: [null, null], sets: [(6, 4), (6, 4)]);
      expect([for (final x in [...c.a, ...c.b]) x.oldRating], [2.5, 2.5, 2.5, 2.5]);
      expect(news(c.a), [2.63, 2.63]);
    });

    test('a rating stays within 1.00-7.00', () {
      final c = ratingChanges(
        sideA: [const SportRating(rating: 1.0)],
        sideB: [const SportRating(rating: 1.0)],
        sets: [(0, 6), (0, 6)],
      );
      expect(c.a.single.newRating, 1.0);
      expect(c.a.single.delta, 0.0);
    });
  });

  group('score notifications', () {
    const kinds = ['game_finished', 'score_entered', 'score_disputed', 'score_resolved', 'rating_updated'];

    AppNotification note(String kind, [Map<String, Object?> extra = const {}]) => AppNotification(
      id: 'n-$kind',
      kind: kind,
      category: kind == 'game_finished' ? 'games' : 'ratings',
      payload: {'game_id': 'g9', 'sport_id': 'padel', 'starts_local': '2026-11-21T18:00:00', 'result_id': 'r9', ...extra},
      createdAt: DateTime.utc(2026, 11, 22),
      read: false,
    );

    test('every score kind opens the game', () {
      for (final kind in kinds) {
        expect(note(kind).route, '/games/g9', reason: kind);
      }
    });

    test('a rating notice without numbers reads as a plain notification', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(notificationText(l, 'en', note('rating_updated', {'old': 'x', 'new': null})), l.notifUnknown);
    });

    for (final code in ['en', 'ru', 'uz', 'kk']) {
      test('every score kind has its own sentence in $code', () {
        final l = lookupAppLocalizations(Locale(code));
        final texts = [
          notificationText(l, code, note('game_finished', {'can_score': true})),
          notificationText(l, code, note('game_finished', {'can_score': false})),
          notificationText(l, code, note('score_entered')),
          notificationText(l, code, note('score_disputed')),
          notificationText(l, code, note('score_resolved', {'action': 'confirm'})),
          notificationText(l, code, note('score_resolved', {'action': 'void'})),
          notificationText(l, code, note('rating_updated', {'old': 3.5, 'new': 3.63})),
        ];
        expect(texts, everyElement(isNot(l.notifUnknown)));
        expect(texts.toSet(), hasLength(texts.length));
        expect(texts.last, allOf(contains('3.50'), contains('3.63')));
      });
    }
  });

  group('after the game', () {
    // Played Saturday 18:00-19:30, venue time.
    final end = DateTime(2026, 11, 21, 19, 30);
    Game game({bool cancelled = false}) => Game(
      id: 'g9',
      sportId: 'football',
      cityId: 'tashkent',
      hostId: 'p1',
      start: end.subtract(const Duration(minutes: 90)),
      end: end,
      spots: 4,
      participantIds: const ['p1', 'me'],
      cancelled: cancelled,
    );

    test('votes are open from the end for 7 days', () {
      expect(canVote(game(), end.subtract(const Duration(minutes: 1))), isFalse);
      expect(canVote(game(), end), isTrue);
      expect(canVote(game(), end.add(const Duration(days: 7, minutes: -1))), isTrue);
      expect(canVote(game(), end.add(const Duration(days: 7))), isFalse);
      expect(canVote(game(cancelled: true), end.add(const Duration(hours: 1))), isFalse);
    });

    test('no-show reports are open from the end for 48 hours', () {
      expect(canReportNoShow(game(), end.subtract(const Duration(minutes: 1))), isFalse);
      expect(canReportNoShow(game(), end), isTrue);
      expect(canReportNoShow(game(), end.add(const Duration(hours: 48, minutes: -1))), isTrue);
      expect(canReportNoShow(game(), end.add(const Duration(hours: 48))), isFalse);
      expect(canReportNoShow(game(cancelled: true), end.add(const Duration(hours: 1))), isFalse);
    });

    test('a recorded no-show opens the game and has its own sentence', () {
      final note = AppNotification(
        id: 'n1',
        kind: 'no_show_recorded',
        category: 'games',
        payload: const {'game_id': 'g9', 'sport_id': 'football', 'starts_local': '2026-11-21T18:00:00'},
        createdAt: DateTime.utc(2026, 11, 22),
        read: false,
      );
      expect(note.route, '/games/g9');
      for (final code in ['en', 'ru', 'uz', 'kk']) {
        final l = lookupAppLocalizations(Locale(code));
        expect(notificationText(l, code, note), l.notifNoShowRecorded);
        expect(l.notifNoShowRecorded, isNot(l.notifUnknown));
      }
    });
  });
}
