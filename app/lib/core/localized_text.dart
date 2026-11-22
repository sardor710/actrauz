/// Content entered by admins and owners, one value per language.
///
/// A missing translation falls back to Russian, then English (product spec §3).
class LocalizedText {
  const LocalizedText({this.uz, this.ru, this.en});

  /// Same text in every language, for names that are not translated.
  const LocalizedText.all(String value) : uz = value, ru = value, en = value;

  final String? uz;
  final String? ru;
  final String? en;

  String? _byCode(String languageCode) => switch (languageCode) {
    'uz' => uz,
    'ru' => ru,
    'en' => en,
    _ => null,
  };

  String resolve(String languageCode) {
    for (final code in [languageCode, 'ru', 'en', 'uz']) {
      final value = _byCode(code);
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}
