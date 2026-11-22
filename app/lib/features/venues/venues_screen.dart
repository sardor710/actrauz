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
import '../home/home_screen.dart';

/// Venues in the selected city: search, sort, sport and favourites filters.
class VenuesScreen extends ConsumerStatefulWidget {
  const VenuesScreen({super.key});

  @override
  ConsumerState<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends ConsumerState<VenuesScreen> {
  String _query = '';
  String? _sportId;
  bool _cheapestFirst = false;
  bool _favouritesOnly = false;

  bool _matches(Venue venue, String lang, Set<String> favourites) {
    if (_sportId != null && !venue.sportIds.contains(_sportId)) return false;
    if (_favouritesOnly && !favourites.contains(venue.id)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return venue.name.resolve(lang).toLowerCase().contains(q) || venue.district.resolve(lang).toLowerCase().contains(q);
  }

  Future<void> _pickSport(List<Sport> sports) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.filterSport,
      options: {'': l.allSports, for (final s in sports) s.id: s.name.resolve(context.lang)},
      current: _sportId ?? '',
    );
    if (picked != null && mounted) setState(() => _sportId = picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final favourites = ref.watch(favouritesProvider);
    final today = dateOnly(ref.watch(cityNowProvider)());

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncBody(
          value: ref.watch(venuesProvider),
          builder: (venues) {
            // Only sports that some venue in this city offers.
            final offered = {for (final v in venues) ...v.sportIds};
            final filters = sports.where((s) => offered.contains(s.id)).toList();
            final shown = venues.where((v) => _matches(v, context.lang, favourites)).toList();
            if (_cheapestFirst) {
              shown.sort((a, b) => (venueFromPrice(a, today) ?? 0).compareTo(venueFromPrice(b, today) ?? 0));
            }
            final sportName = filters.where((s) => s.id == _sportId).firstOrNull?.name.resolve(context.lang);

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: AppHeader()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: l.searchVenues,
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AsyncBody(
                      value: ref.watch(bannersProvider),
                      builder: (banners) => BannerCarousel(banners: banners),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        FilterChipButton(
                          icon: Icons.swap_vert_rounded,
                          label: _cheapestFirst ? l.sortPrice : null,
                          selected: _cheapestFirst,
                          onTap: () => setState(() => _cheapestFirst = !_cheapestFirst),
                        ),
                        FilterChipButton(
                          label: sportName ?? l.filterSport,
                          selected: _sportId != null,
                          dropdown: true,
                          onTap: () => _pickSport(filters),
                        ),
                        FilterChipButton(
                          label: l.favourites,
                          icon: _favouritesOnly ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          selected: _favouritesOnly,
                          onTap: () => setState(() => _favouritesOnly = !_favouritesOnly),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
                    child: Text('${l.tabVenues} (${shown.length})'.toUpperCase(), style: AppText.sectionTitle),
                  ),
                ),
                if (shown.isEmpty)
                  SliverToBoxAdapter(child: EmptyState(icon: Icons.search_off_rounded, text: l.noVenues))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, i) => _VenueCard(
                        venue: shown[i],
                        sports: sports,
                        fromPrice: venueFromPrice(shown[i], today),
                        favourite: favourites.contains(shown[i].id),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VenueCard extends ConsumerWidget {
  const _VenueCard({required this.venue, required this.sports, required this.fromPrice, required this.favourite});

  final Venue venue;
  final List<Sport> sports;
  final int? fromPrice;
  final bool favourite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final currency = cityById(venue.cityId).currency;
    final venueSports = sports.where((s) => venue.sportIds.contains(s.id)).toList();

    return Card(
      child: InkWell(
        onTap: () => context.go('/venues/${venue.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoBox(
                asset: venuePhoto(venue.id),
                height: 188,
                radius: 14,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.62),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(l.bookable, style: manrope(12.5, 700, color: Colors.white)),
                          ),
                          const Spacer(),
                          OverlayIconButton(
                            icon: favourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: favourite ? AppColors.error : AppColors.ink,
                            label: l.favourites,
                            onTap: () => ref.read(favouritesProvider.notifier).toggle(venue.id),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          for (final sport in venueSports.take(3))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(
                                sportIcon(sport.iconKey),
                                size: 20,
                                color: Colors.white,
                                shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.name.resolve(context.lang), style: AppText.cardTitle),
                    const SizedBox(height: 3),
                    Text(
                      '${venue.district.resolve(context.lang)} · '
                      '${venueSports.map((s) => s.name.resolve(context.lang)).join(', ')}',
                      style: AppText.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (fromPrice != null) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(child: Text(l.priceStartingFrom, style: AppText.muted)),
                          Text(money(l, fromPrice!, currency), style: manrope(14.5, 800)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
