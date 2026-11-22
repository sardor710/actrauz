import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Venue list for the selected city with name search and a sport filter.
class VenuesScreen extends ConsumerStatefulWidget {
  const VenuesScreen({super.key});

  @override
  ConsumerState<VenuesScreen> createState() => _VenuesScreenState();
}

class _VenuesScreenState extends ConsumerState<VenuesScreen> {
  String _query = '';
  String? _sportId;

  bool _matches(Venue venue, String lang) {
    if (_sportId != null && !venue.sportIds.contains(_sportId)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return venue.name.resolve(lang).toLowerCase().contains(q) || venue.district.resolve(lang).toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];

    return Scaffold(
      appBar: AppBar(title: Text(l.tabVenues)),
      body: AsyncBody(
        value: ref.watch(venuesProvider),
        builder: (venues) {
          // Only sports that some venue in this city offers.
          final offered = {for (final v in venues) ...v.sportIds};
          final filters = sports.where((s) => offered.contains(s.id)).toList();
          final shown = venues.where((v) => _matches(v, context.lang)).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: InputDecoration(hintText: l.searchVenues, prefixIcon: const Icon(Icons.search)),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(l.allSports),
                        selected: _sportId == null,
                        onSelected: (_) => setState(() => _sportId = null),
                      ),
                    ),
                    for (final sport in filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(sportIcon(sport.iconKey), size: 18),
                          label: Text(sport.name.resolve(context.lang)),
                          selected: _sportId == sport.id,
                          onSelected: (_) => setState(() => _sportId = sport.id),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: EmptyState(icon: Icons.search_off, text: l.noVenues))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, i) => _VenueCard(venue: shown[i], sports: sports),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VenueCard extends ConsumerWidget {
  const _VenueCard({required this.venue, required this.sports});

  final Venue venue;
  final List<Sport> sports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final currency = cityById(venue.cityId).currency;
    final today = dateOnly(ref.watch(cityNowProvider)());
    final from = venueFromPrice(venue, today);
    final venueSports = sports.where((s) => venue.sportIds.contains(s.id)).toList();

    return Card(
      child: InkWell(
        onTap: () => context.go('/venues/${venue.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeedArt(
              seed: venue.colorSeed,
              icon: venueSports.isEmpty ? Icons.sports : sportIcon(venueSports.first.iconKey),
              height: 110,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    venue.name.resolve(context.lang),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    venue.district.resolve(context.lang),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final sport in venueSports)
                              Pill(text: sport.name.resolve(context.lang), icon: sportIcon(sport.iconKey)),
                          ],
                        ),
                      ),
                      if (from != null)
                        Text(
                          l.fromPrice(money(l, from, currency)),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                    ],
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
