import 'package:actra/domain/competitive.dart';
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
}
