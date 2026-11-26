import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the spec's anti-goal: no untranslated or mixed-language screens.
void main() {
  Map<String, dynamic> load(String code) =>
      jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map<String, dynamic>;

  Map<String, String> messages(Map<String, dynamic> arb) => {
    for (final e in arb.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };

  final enArb = load('en');
  final en = messages(enArb);

  // Placeholder names declared for a key in the English template.
  Set<String> declared(String key) {
    final meta = enArb['@$key'] as Map<String, dynamic>?;
    final map = meta?['placeholders'] as Map<String, dynamic>?;
    return map?.keys.toSet() ?? {};
  }

  bool uses(String message, String name) => RegExp('\\{$name[,}]').hasMatch(message);

  for (final code in ['ru', 'uz', 'kk']) {
    final other = messages(load(code));

    test('$code has exactly the same keys as en', () {
      expect(other.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'extra keys in $code');
      expect(en.keys.toSet().difference(other.keys.toSet()), isEmpty, reason: 'keys missing in $code');
    });

    test('$code has no empty values and keeps every placeholder', () {
      for (final key in en.keys) {
        final value = other[key] ?? '';
        expect(value.trim(), isNotEmpty, reason: '$key is empty in $code');
        for (final name in declared(key)) {
          expect(uses(value, name), isTrue, reason: '$key in $code does not use {$name}');
        }
      }
    });
  }

  test('en uses every placeholder it declares', () {
    for (final key in en.keys) {
      for (final name in declared(key)) {
        expect(uses(en[key]!, name), isTrue, reason: '$key does not use {$name}');
      }
    }
  });

  test('Uzbek uses the modifier letter ʻ, not an ASCII apostrophe', () {
    for (final e in messages(load('uz')).entries) {
      expect(e.value.contains("'"), isFalse, reason: '${e.key} contains an ASCII apostrophe');
    }
  });
}
