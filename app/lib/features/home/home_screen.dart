import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../games/game_card.dart';

/// City-scoped feed: banners, open games, courts free today, tournaments.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final city = ref.watch(currentCityProvider);
    final name = ref.watch(sessionProvider.select((s) => s.userName)) ?? '';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.greeting(name),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.place_outlined, size: 18),
                    label: Text(city.name.resolve(context.lang)),
                    onPressed: () => context.go('/profile'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AsyncBody(value: ref.watch(bannersProvider), builder: (banners) => _Banners(banners: banners)),

            SectionHeader(title: l.homeGames, onSeeAll: () => context.go('/games')),
            AsyncBody(
              value: ref.watch(gamesProvider),
              builder: (games) => games.isEmpty
                  ? EmptyState(icon: Icons.groups_outlined, text: l.noGames)
                  : SizedBox(
                      height: 180,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: games.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => SizedBox(width: 280, child: GameCard(game: games[i])),
                      ),
                    ),
            ),

            SectionHeader(title: l.homeCourts, onSeeAll: () => context.go('/venues')),
            AsyncBody(
              value: ref.watch(freeTodayProvider),
              builder: (items) => items.isEmpty
                  ? EmptyState(icon: Icons.event_busy_outlined, text: l.noCourtsToday)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FreeTodayTile(item: item),
                            ),
                        ],
                      ),
                    ),
            ),

            SectionHeader(title: l.homeTournaments),
            AsyncBody(
              value: ref.watch(tournamentsProvider),
              builder: (items) => SizedBox(
                height: 190,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => SizedBox(width: 280, child: _TournamentCard(item: items[i])),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banners extends StatelessWidget {
  const _Banners({required this.banners});

  final List<BannerItem> banners;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 132,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: banners.length,
        itemBuilder: (context, i) {
          final banner = banners[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SeedArt(
                seed: banner.colorSeed,
                icon: Icons.sports,
                height: 132,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        banner.title.resolve(context.lang),
                        style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        banner.subtitle.resolve(context.lang),
                        style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FreeTodayTile extends ConsumerWidget {
  const _FreeTodayTile({required this.item});

  final FreeToday item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final venue = item.venue;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final icon = sports.where((s) => s.id == venue.sportIds.first).map((s) => sportIcon(s.iconKey)).firstOrNull;

    return Card(
      child: InkWell(
        onTap: () => context.go('/venues/${venue.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  child: SeedArt(seed: venue.colorSeed, icon: icon ?? Icons.sports, height: 56),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name.resolve(context.lang),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [for (final slot in item.next) Pill(text: hm(slot.time.start), icon: Icons.schedule)],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentCard extends ConsumerWidget {
  const _TournamentCard({required this.item});

  final TournamentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final city = ref.watch(currentCityProvider);
    final now = ref.watch(cityNowProvider)();
    final full = item.slotsFilled >= item.slotsTotal;
    final fee = item.minFee == item.maxFee
        ? money(l, item.minFee, city.currency)
        : '${money(l, item.minFee, city.currency)} – ${money(l, item.maxFee, city.currency)}';

    return Card(
      child: InkWell(
        onTap: () => showMessage(context, l.comingSoon),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title.resolve(context.lang),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${dayLabel(l, context.lang, item.start, now)} · ${item.venueName.resolve(context.lang)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${l.entryFee}: $fee',
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: item.slotsFilled / item.slotsTotal,
                borderRadius: BorderRadius.circular(8),
                minHeight: 6,
              ),
              const SizedBox(height: 6),
              Text(
                l.filledOf(item.slotsFilled, item.slotsTotal),
                style: theme.textTheme.labelMedium?.copyWith(color: full ? scheme.error : scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
