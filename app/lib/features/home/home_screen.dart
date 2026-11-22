import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/app_header.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../games/game_card.dart';

/// City-scoped feed: search, banners, sports, venues, free courts, games.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final venues = ref.watch(venuesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const AppHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _SearchButton(text: l.searchHint, onTap: () => context.go('/venues')),
            ),
            AsyncBody(value: ref.watch(bannersProvider), builder: (banners) => BannerCarousel(banners: banners)),
            const SizedBox(height: 16),

            // Sports that have a venue in this city.
            AsyncBody(
              value: venues,
              builder: (list) {
                final offered = {for (final v in list) ...v.sportIds};
                final shown = sports.where((s) => offered.contains(s.id)).toList();
                return SectionCard(
                  title: l.gamesBySports,
                  contentPadding: const EdgeInsets.only(bottom: 14),
                  child: SizedBox(
                    height: 108,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 4),
                      itemBuilder: (context, i) => _SportTile(
                        sport: shown[i],
                        onTap: () {
                          ref.read(gamesSportFilterProvider.notifier).state = shown[i].id;
                          context.go('/games');
                        },
                      ),
                    ),
                  ),
                );
              },
            ),

            AsyncBody(
              value: venues,
              builder: (list) => SectionCard(
                title: l.venuesNearYou,
                onSeeAll: () => context.go('/venues'),
                contentPadding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  height: 176,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => _VenueTile(venue: list[i]),
                  ),
                ),
              ),
            ),

            AsyncBody(
              value: ref.watch(freeTodayProvider),
              builder: (items) => SectionCard(
                title: l.homeCourts,
                child: items.isEmpty
                    ? EmptyState(icon: Icons.event_busy_outlined, text: l.noCourtsToday)
                    : Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) const Divider(height: 20),
                            _FreeTodayRow(item: items[i]),
                          ],
                        ],
                      ),
              ),
            ),

            AsyncBody(
              value: ref.watch(gamesProvider),
              builder: (games) => games.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 8, 6),
                          child: Row(
                            children: [
                              Expanded(child: Text(l.homeGames.toUpperCase(), style: AppText.sectionTitle)),
                              TextButton(onPressed: () => context.go('/games'), child: Text(l.seeAll)),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 214,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: games.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 12),
                            itemBuilder: (context, i) => SizedBox(width: 312, child: GameCard(game: games[i])),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: manrope(15, 500, color: AppColors.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Swipeable photo banners with a headline and a call-to-action pill.
class BannerCarousel extends StatelessWidget {
  const BannerCarousel({super.key, required this.banners});

  final List<BannerItem> banners;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 168,
    child: PageView.builder(
      controller: PageController(viewportFraction: 0.9),
      padEnds: true,
      itemCount: banners.length,
      itemBuilder: (context, i) {
        final banner = banners[i];
        final cta = kBannerCta[banner.id]?.resolve(context.lang);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: PromoCard(
            photo: bannerPhoto(banner.id),
            title: banner.title.resolve(context.lang),
            subtitle: banner.subtitle.resolve(context.lang),
            cta: cta,
            onTap: () => context.go(kBannerRoute[banner.id] ?? '/venues'),
          ),
        );
      },
    ),
  );
}

/// Photo card with white headline text and a lime button.
class PromoCard extends StatelessWidget {
  const PromoCard({super.key, required this.photo, required this.title, this.subtitle, this.cta, required this.onTap});

  final String photo;
  final String title;
  final String? subtitle;
  final String? cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: PhotoBox(
      asset: photo,
      radius: 22,
      darken: 0.72,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: manrope(19, 800, color: Colors.white, height: 1.2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: manrope(13.5, 600, color: AppColors.lime, height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (cta != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(8)),
                child: Text(cta!, style: manrope(13, 800), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SportTile extends StatelessWidget {
  const _SportTile({required this.sport, required this.onTap});

  final Sport sport;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: SizedBox(
      width: 92,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SportBadge(sportId: sport.id, size: 58),
          const SizedBox(height: 10),
          Text(
            sport.name.resolve(context.lang),
            style: manrope(13.5, 700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

class _VenueTile extends StatelessWidget {
  const _VenueTile({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => context.go('/venues/${venue.id}'),
    child: SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoBox(asset: venuePhoto(venue.id), width: 132, height: 116, radius: 18),
          const SizedBox(height: 8),
          Text(
            venue.name.resolve(context.lang),
            style: manrope(14, 700, height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}

class _FreeTodayRow extends ConsumerWidget {
  const _FreeTodayRow({required this.item});

  final FreeToday item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final venue = item.venue;
    // The venue's lowest price this week, the same figure the Venues tab shows.
    final price =
        venueFromPrice(venue, dateOnly(ref.watch(cityNowProvider)())) ??
        item.next.map((s) => s.price).reduce((a, b) => a < b ? a : b);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.go('/venues/${venue.id}'),
      child: Row(
        children: [
          PhotoBox(asset: venuePhoto(venue.id), width: 64, height: 64, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue.name.resolve(context.lang),
                  style: manrope(15, 700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l.fromPrice(money(l, price, cityById(venue.cityId).currency)),
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final slot in item.next)
                      Pill(text: hm(slot.time.start), color: AppColors.primarySoft, onColor: AppColors.primaryDark),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
        ],
      ),
    );
  }
}
