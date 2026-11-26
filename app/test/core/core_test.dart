import 'package:actra/core/localized_text.dart';
import 'package:actra/core/markets.dart';
import 'package:actra/core/languages.dart';
import 'package:actra/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups thousands with non-breaking spaces', () {
    expect(groupThousands(250000), '250 000');
    expect(groupThousands(999), '999');
    expect(groupThousands(1500000), '1 500 000');
    expect(groupThousands(0), '0');
  });

  test('falls back to Russian, then English', () {
    const t = LocalizedText(ru: 'Корт', en: 'Court');
    expect(t.resolve('uz'), 'Корт');
    expect(const LocalizedText(en: 'Court').resolve('uz'), 'Court');
    expect(const LocalizedText(uz: 'Kort', ru: 'Корт').resolve('uz'), 'Kort');
    expect(const LocalizedText().resolve('uz'), '');
  });

  test('kazakh-only text falls back', () {
    for (final code in ['uz', 'ru', 'kk', 'en']) {
      expect(const LocalizedText(kk: 'Алатау').resolve(code), 'Алатау');
    }
    expect(const LocalizedText(ru: 'А', kk: 'Ә').resolve('kk'), 'Ә');
    expect(const LocalizedText(ru: 'А', en: 'B').resolve('kk'), 'А');
    expect(const LocalizedText.all('X').resolve('kk'), 'X');
  });

  test('every language has a code and a native name', () {
    expect(kLanguageCodes, ['uz', 'ru', 'kk', 'en']);
    expect(kLanguageNames.keys, kLanguageCodes);
    expect(kLanguageNames['kk'], 'Қазақша');
  });

  test('an empty translation counts as missing', () {
    expect(const LocalizedText(uz: '', ru: 'Корт').resolve('uz'), 'Корт');
  });

  test('venueNow applies the city offset', () {
    final now = venueNow(cityById('tashkent'), utcNow: DateTime.utc(2026, 11, 22, 20, 30));
    expect(now, DateTime.utc(2026, 11, 23, 1, 30));
  });

  test('every city has a currency matching its country', () {
    for (final city in kCities) {
      expect(city.currency, city.countryCode == 'UZ' ? Currency.uzs : Currency.kzt);
      expect(city.name.kk, isNotEmpty);
      for (final code in ['uz', 'ru', 'kk', 'en']) {
        expect(city.name.resolve(code), isNotEmpty);
      }
    }
  });
}
