/// Content entered by admins and owners, one value per language.
///
/// A missing translation falls back to Russian, then English, then Uzbek, then
/// Kazakh (product spec §3), so text entered in one language only still shows.
class LocalizedText {
  const LocalizedText({this.uz, this.ru, this.kk, this.en});

  /// Same text in Uzbek, Russian and English, for names that are not
  /// translated (brand names). Kazakh stays empty and falls back to Russian.
  const LocalizedText.all(String value) : uz = value, ru = value, kk = null, en = value;

  final String? uz;
  final String? ru;
  final String? kk;
  final String? en;

  String? _byCode(String languageCode) => switch (languageCode) {
    'uz' => uz,
    'ru' => ru,
    'kk' => kk,
    'en' => en,
    _ => null,
  };

  String resolve(String languageCode) {
    for (final code in [languageCode, 'ru', 'en', 'uz', 'kk']) {
      final value = _byCode(code);
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}
