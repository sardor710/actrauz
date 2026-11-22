import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/money.dart';
import '../../domain/models.dart';
import '../../domain/pricing.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Venue profile: description, address, hours, amenities and its courts.
class VenueScreen extends ConsumerWidget {
  const VenueScreen({super.key, required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];

    return Scaffold(
      appBar: AppBar(),
      body: AsyncBody(
        value: ref.watch(venueProvider(venueId)),
        builder: (venue) {
          final currency = cityById(venue.cityId).currency;
          final today = dateOnly(ref.watch(cityNowProvider)());
          Sport? sportOf(String id) => sports.where((s) => s.id == id).firstOrNull;
          final firstSport = sportOf(venue.sportIds.first);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SeedArt(seed: venue.colorSeed, icon: sportIcon(firstSport?.iconKey ?? ''), height: 160),
              ),
              const SizedBox(height: 16),
              Text(
                venue.name.resolve(context.lang),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                venue.district.resolve(context.lang),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _Title(l.about),
              Text(venue.description.resolve(context.lang), style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(l.address),
                subtitle: Text(venue.address.resolve(context.lang)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_outlined),
                title: Text(l.phone),
                subtitle: Text(venue.phone),
              ),
              _Title(l.workingHours),
              _HoursRow(label: l.weekdays, value: hoursText(l, venue.hours[1])),
              _HoursRow(label: l.saturday, value: hoursText(l, venue.hours[6])),
              _HoursRow(label: l.sunday, value: hoursText(l, venue.hours[7])),
              if (venue.amenities.isNotEmpty) ...[
                _Title(l.amenities),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final key in venue.amenities) Pill(text: amenityText(l, key))],
                ),
              ],
              _Title(l.courts),
              for (final court in venue.courts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CourtTile(
                    venue: venue,
                    court: court,
                    sport: sportOf(court.sportId),
                    priceText: _priceText(l, venue, court, today, currency),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// "180 000 – 300 000 soʻm" from this court's own slots this week.
  String? _priceText(AppLocalizations l, Venue venue, Court court, DateTime today, Currency currency) {
    final range = feeRange(venue.copyWith(courts: [court]), court.sportId, today);
    if (range == null) return null;
    if (range.min == range.max) return money(l, range.min, currency);
    return '${groupThousands(range.min)} – ${money(l, range.max, currency)}';
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _CourtTile extends StatelessWidget {
  const _CourtTile({required this.venue, required this.court, required this.sport, required this.priceText});

  final Venue venue;
  final Court court;
  final Sport? sport;
  final String? priceText;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final details = [
      if (sport != null) sport!.name.resolve(context.lang),
      court.indoor ? l.indoor : l.outdoor,
      l.slotLength(court.slotMinutes),
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        // Two rows, so long court names and prices never squeeze the button.
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(child: Icon(sportIcon(sport?.iconKey ?? ''))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        court.name.resolve(context.lang),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        details,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    priceText ?? '',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => context.go('/venues/${venue.id}/book/${court.id}'),
                  child: Text(l.book),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
