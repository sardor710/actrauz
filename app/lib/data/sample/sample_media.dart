import '../../core/localized_text.dart';
import 'seed_ids.dart';

/// Bundled sample imagery. Photos are named after the sample ids; rows loaded
/// into the database by the seed are matched back to them with [sampleKey],
/// so the same pictures show with the sample backend and the real one. A row
/// with no bundled photo falls back to a plain colour. Photo storage arrives
/// with the owner panel.

String venuePhoto(String venueId) => 'assets/photos/venue_${sampleKey(venueId)}.jpg';

String bannerPhoto(String bannerId) => 'assets/photos/banner_${sampleKey(bannerId)}.jpg';

String tournamentPhoto(String tournamentId) => 'assets/photos/tournament_${sampleKey(tournamentId)}.jpg';

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
