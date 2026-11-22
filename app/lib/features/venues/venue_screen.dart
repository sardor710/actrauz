import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/models.dart';
import '../../domain/pricing.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Venue profile: photo, description, address, hours, amenities and courts.
class VenueScreen extends ConsumerWidget {
  const VenueScreen({super.key, required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final favourite = ref.watch(favouritesProvider).contains(venueId);

    return Scaffold(
      body: AsyncBody(
        value: ref.watch(venueProvider(venueId)),
        builder: (venue) {
          final currency = cityById(venue.cityId).currency;
          final today = dateOnly(ref.watch(cityNowProvider)());
          Sport? sportOf(String id) => sports.where((s) => s.id == id).firstOrNull;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              PhotoBox(
                asset: venuePhoto(venue.id),
                height: 250,
                radius: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Row(
                        children: [
                          OverlayIconButton(icon: Icons.arrow_back_rounded, onTap: () => context.pop()),
                          const Spacer(),
                          OverlayIconButton(
                            icon: favourite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: favourite ? AppColors.error : AppColors.ink,
                            label: l.favourites,
                            onTap: () => ref.read(favouritesProvider.notifier).toggle(venue.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.name.resolve(context.lang), style: AppText.title),
                    const SizedBox(height: 4),
                    Text(venue.district.resolve(context.lang), style: AppText.muted.copyWith(fontSize: 15)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in venue.sportIds)
                          if (sportOf(id) != null)
                            Pill(
                              text: sportOf(id)!.name.resolve(context.lang),
                              icon: sportIcon(sportOf(id)!.iconKey),
                              color: AppColors.primarySoft,
                              onColor: AppColors.primaryDark,
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              // Booking is why people open this page, so courts come first.
              SectionCard(
                title: l.courts,
                child: Column(
                  children: [
                    for (var i = 0; i < venue.courts.length; i++) ...[
                      if (i > 0) const Divider(height: 28),
                      _CourtRow(
                        venue: venue,
                        court: venue.courts[i],
                        sport: sportOf(venue.courts[i].sportId),
                        priceText: _priceText(l, venue, venue.courts[i], today, currency),
                      ),
                    ],
                  ],
                ),
              ),
              SectionCard(
                title: l.about,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(venue.description.resolve(context.lang), style: AppText.body.copyWith(fontSize: 15)),
                    const SizedBox(height: 14),
                    _InfoRow(icon: Icons.place_outlined, label: l.address, value: venue.address.resolve(context.lang)),
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.phone_outlined, label: l.phone, value: venue.phone),
                  ],
                ),
              ),
              SectionCard(
                title: l.workingHours,
                child: Column(
                  children: _sameHoursEveryDay(venue)
                      ? [_HoursRow(label: l.everyDay, value: hoursText(l, venue.hours[1]))]
                      : [
                          _HoursRow(label: l.weekdays, value: hoursText(l, venue.hours[1])),
                          _HoursRow(label: l.saturday, value: hoursText(l, venue.hours[6])),
                          _HoursRow(label: l.sunday, value: hoursText(l, venue.hours[7])),
                        ],
                ),
              ),
              if (venue.amenities.isNotEmpty)
                SectionCard(
                  title: l.amenities,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final key in venue.amenities) Pill(text: amenityText(l, key), icon: Icons.check_rounded),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _sameHoursEveryDay(Venue venue) {
    final first = venue.hours[1];
    if (first == null) return false;
    return [
      for (var d = 2; d <= 7; d++) venue.hours[d],
    ].every((h) => h != null && h.openMinute == first.openMinute && h.closeMinute == first.closeMinute);
  }

  /// "180 000 – 300 000 soʻm" from this court's own slots this week.
  String? _priceText(AppLocalizations l, Venue venue, Court court, DateTime today, Currency currency) {
    final range = feeRange(venue.copyWith(courts: [court]), court.sportId, today);
    if (range == null) return null;
    if (range.min == range.max) return money(l, range.min, currency);
    return '${groupThousands(range.min)} – ${money(l, range.max, currency)}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: AppColors.ink),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption),
            Text(value, style: manrope(15, 700)),
          ],
        ),
      ),
    ],
  );
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppText.muted.copyWith(fontSize: 15))),
        Text(value, style: manrope(15, 700)),
      ],
    ),
  );
}

class _CourtRow extends StatelessWidget {
  const _CourtRow({required this.venue, required this.court, required this.sport, required this.priceText});

  final Venue venue;
  final Court court;
  final Sport? sport;
  final String? priceText;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final details = [
      if (sport != null) sport!.name.resolve(context.lang),
      court.indoor ? l.indoor : l.outdoor,
      l.slotLength(court.slotMinutes),
    ].join(' · ');

    // Two rows, so long court names and prices never squeeze the button.
    return Column(
      children: [
        Row(
          children: [
            SportBadge(sportId: court.sportId, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(court.name.resolve(context.lang), style: manrope(16, 800)),
                  Text(details, style: AppText.muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(priceText ?? '', style: manrope(14.5, 700))),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: () => context.go('/venues/${venue.id}/book/${court.id}'),
              child: Text(l.book),
            ),
          ],
        ),
      ],
    );
  }
}
