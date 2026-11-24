import 'dart:io';

import 'package:actra/data/sample/sample_data.dart';
import 'package:actra/data/sample/sample_media.dart';
import 'package:actra/data/social.dart';
import 'package:actra/features/common/widgets.dart';
import 'package:actra/state/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bundled media', () {
    void expectFile(String asset) => expect(File(asset).existsSync(), isTrue, reason: '$asset is missing');

    test('every sample venue, banner, tournament and sport has its image', () {
      for (final venue in kSampleVenues) {
        expectFile(venuePhoto(venue.id));
      }
      for (final banner in kSampleBanners) {
        expectFile(bannerPhoto(banner.id));
        expect(kBannerCta[banner.id], isNotNull, reason: 'no button text for ${banner.id}');
        expect(kBannerRoute[banner.id], isNotNull, reason: 'no destination for ${banner.id}');
      }
      for (final tournament in kTournamentSeeds) {
        expectFile(tournamentPhoto(tournament.id));
      }
      // Running and gym have no artwork yet: SportBadge falls back to a line icon.
      for (final sport in kSampleSports.where((s) => s.bookable)) {
        expectFile(sportIconAsset(sport.id));
      }
      for (final asset in [kWaveIcon, kTrophyIcon, kGamesPromoPhoto, 'assets/fonts/Manrope.ttf']) {
        expectFile(asset);
      }
    });

    test('every bundled file is credited', () {
      final credits = File('assets/CREDITS.md').readAsStringSync();
      final files = Directory('assets')
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll('\\', '/').replaceFirst('assets/', ''))
          .where((p) => p != 'CREDITS.md');
      for (final file in files) {
        expect(credits.contains(file), isTrue, reason: '$file is not listed in CREDITS.md');
      }
    });

    test('banner button texts exist in all three languages', () {
      for (final text in kBannerCta.values) {
        expect(text.uz, isNotEmpty);
        expect(text.ru, isNotEmpty);
        expect(text.en, isNotEmpty);
      }
    });

    testWidgets('a missing photo shows the placeholder instead of a hole', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PhotoBox(asset: 'assets/photos/does_not_exist.jpg', width: 100, height: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-fallback')), findsOneWidget);
    });
  });

  group('teams', () {
    const repo = SampleSocialRepository();

    test('every city has a team and each team is in its city', () async {
      for (final cityId in ['tashkent', 'almaty', 'astana']) {
        final teams = await repo.teams(cityId);
        expect(teams, isNotEmpty, reason: cityId);
        expect(teams.every((t) => t.cityId == cityId), isTrue);
      }
    });

    test('every team plays a known sport', () {
      final sportIds = kSampleSports.map((s) => s.id).toSet();
      for (final team in kSampleTeams) {
        expect(sportIds, contains(team.sportId));
        expect(team.memberCount, greaterThan(0));
      }
    });
  });

  group('favourites', () {
    test('toggling adds, then removes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final favourites = container.read(favouritesProvider.notifier);

      expect(container.read(favouritesProvider), isEmpty);
      favourites.toggle('v1');
      favourites.toggle('v2');
      expect(container.read(favouritesProvider), {'v1', 'v2'});
      favourites.toggle('v1');
      expect(container.read(favouritesProvider), {'v2'});
      favourites.toggle('v2');
      expect(container.read(favouritesProvider), isEmpty);
    });
  });
}
