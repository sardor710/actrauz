import 'package:actra/features/common/rating_pill.dart';
import 'package:actra/l10n/gen/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a rating range shows one decimal, truncated', () {
    expect(formatRatingRange(2.0, 4.99), '2.0–4.9');
    expect(formatRatingRange(3.0, 4.5), '3.0–4.5');
    expect(formatRatingRange(1.0, 7.0), '1.0–7.0');
    expect(formatRatingRange(5.0, 7.0), '5.0–7.0');
  });

  test('a rating shows two decimals', () {
    expect(formatRating(2.7), '2.70');
    expect(formatRating(3.47), '3.47');
  });

  test("a player's level: the level, the rating, or no rating yet in a rated sport", () {
    final l = AppLocalizationsEn();
    expect(memberLevel(l, rated: false, level: 3), 'Level 3');
    expect(memberLevel(l, rated: true, level: 3, rating: 3.47), '3.47');
    expect(memberLevel(l, rated: true, level: 2, rating: 2.5, provisional: true), l.ratingWithProvisional('2.50'));
    // A player with no rating in padel is not "Level 1".
    expect(memberLevel(l, rated: true, level: 1), 'No rating yet');
  });
}
