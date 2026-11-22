import '../../core/localized_text.dart';

/// Bundled sample imagery. Once the backend is connected, venue and banner
/// photos come from storage and only the sport icons stay bundled.

String venuePhoto(String venueId) => 'assets/photos/venue_$venueId.jpg';

String bannerPhoto(String bannerId) => 'assets/photos/banner_$bannerId.jpg';

String tournamentPhoto(String tournamentId) => 'assets/photos/tournament_$tournamentId.jpg';

String sportIconAsset(String sportId) => 'assets/icons/$sportId.png';

const kWaveIcon = 'assets/icons/wave.png';
const kTrophyIcon = 'assets/icons/trophy.png';

/// Photo behind the promo card on the Games tab and the onboarding screen.
const kGamesPromoPhoto = 'assets/photos/banner_bn3.jpg';

/// Button text for each sample banner.
const kBannerCta = <String, LocalizedText>{
  'bn1': LocalizedText(uz: 'Maydon tanlash', ru: 'Выбрать площадку', en: 'Find a venue'),
  'bn2': LocalizedText(uz: 'Oʻyinlarni koʻrish', ru: 'Смотреть игры', en: 'Browse games'),
};

/// Tab each sample banner opens.
const kBannerRoute = <String, String>{'bn1': '/venues', 'bn2': '/games'};
