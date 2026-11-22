import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_media.dart';
import 'package:actra/data/sample/seed_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seedUuid matches what Postgres gives for md5(...)::uuid', () {
    // Values read from the deployed database.
    expect(seedUuid('v1'), 'b0883839-4cab-196b-8117-0b0d05e36952');
    expect(seedUuid('v1c1'), '506ca9a8-0cc5-2926-8958-c8a4efdc1ce6');
    expect(seedUuid('g2'), '82e19b43-c141-1d86-7ea3-5fa7e7cd3547');
  });

  test('seeded rows get the same bundled photos as their sample ids', () {
    for (final venue in kSampleVenues) {
      expect(venuePhoto(seedUuid(venue.id)), venuePhoto(venue.id));
      expect(venuePhoto(venue.id), 'assets/photos/venue_${venue.id}.jpg');
    }
    for (final banner in kSampleBanners) {
      expect(bannerPhoto(seedUuid(banner.id)), 'assets/photos/banner_${banner.id}.jpg');
      expect(kBannerRoute[sampleKey(seedUuid(banner.id))], isNotNull);
    }
    for (final t in kTournamentSeeds) {
      expect(tournamentPhoto(seedUuid(t.id)), 'assets/photos/tournament_${t.id}.jpg');
    }
  });

  test('an id that did not come from the seed is left alone', () {
    const real = '11111111-2222-3333-4444-555555555555';
    expect(sampleKey(real), real);
    expect(venuePhoto(real), 'assets/photos/venue_$real.jpg');
  });
}
