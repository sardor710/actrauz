import 'package:actra/features/common/rating_pill.dart';
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
}
