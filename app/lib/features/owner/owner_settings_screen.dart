import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/owner_providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'hours_editor.dart';
import 'pricing_editor.dart';

/// Working hours for the venue and, per court, its own hours, slot length
/// and prices (product spec §11.2–11.4). Owners edit; they cannot add or
/// remove courts.
class OwnerSettingsScreen extends ConsumerWidget {
  const OwnerSettingsScreen({super.key, required this.venueId});

  final String venueId;

  /// Runs a save, then refreshes everything that shows hours or prices.
  Future<void> _save(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    final l = context.l;
    try {
      await action();
      refreshOwner(ref);
      if (context.mounted) showMessage(context, l.savedMsg);
    } catch (e) {
      if (context.mounted) showMessage(context, bookingErrorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final repo = ref.read(ownerRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/owner/$venueId')),
        title: Text(l.ownerSettings),
      ),
      body: AsyncBody(
        value: ref.watch(myVenuesProvider),
        builder: (venues) {
          final venue = venues.where((v) => v.id == venueId).firstOrNull;
          if (venue == null) {
            return Center(child: EmptyState(icon: Icons.lock_outline_rounded, text: l.errNotAllowed));
          }
          final currency = cityById(venue.cityId).currency;

          return ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              SectionCard(
                title: l.venueHours,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HoursSummary(hours: venue.hours),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('edit-venue-hours'),
                      onPressed: () async {
                        final hours = await showHoursEditor(context, title: l.venueHours, initial: venue.hours);
                        if (hours != null && context.mounted) {
                          await _save(context, ref, () => repo.setVenueHours(venue.id, hours));
                        }
                      },
                      child: Text(l.editLabel),
                    ),
                  ],
                ),
              ),
              for (final court in venue.courts)
                SectionCard(
                  title: court.name.resolve(context.lang),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Fact(label: l.slotLengthLabel, value: l.slotLength(court.slotMinutes)),
                      _Fact(label: l.basePrice, value: money(l, court.basePrice, currency)),
                      _Fact(label: l.priceRules, value: l.rulesCount(court.priceRules.length)),
                      _Fact(
                        label: l.courtHours,
                        value: court.hoursOverride.isEmpty ? l.sameAsVenue : _overrideDays(context, court),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              key: ValueKey('edit-hours-${court.id}'),
                              onPressed: () async {
                                final hours = await showHoursEditor(
                                  context,
                                  title: '${l.courtHours} · ${court.name.resolve(context.lang)}',
                                  initial: court.hoursOverride,
                                  inherited: venue.hours,
                                );
                                if (hours != null && context.mounted) {
                                  await _save(context, ref, () => repo.setCourtHours(venue.id, court.id, hours));
                                }
                              },
                              child: Text(l.hoursTitle),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              key: ValueKey('edit-prices-${court.id}'),
                              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                              onPressed: () async {
                                final draft = await showPricingEditor(context, court: court, currency: currency);
                                if (draft != null && context.mounted) {
                                  await _save(
                                    context,
                                    ref,
                                    () => repo.setCourtPricing(
                                      venue.id,
                                      court.id,
                                      slotMinutes: draft.slotMinutes,
                                      basePrice: draft.basePrice,
                                      rules: draft.rules,
                                    ),
                                  );
                                }
                              },
                              child: Text(l.pricesTitle),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// "Mon, Sat": the weekdays on which the court differs from the venue.
  String _overrideDays(BuildContext context, Court court) {
    final days = court.hoursOverride.keys.toList()..sort();
    return days.map((d) => weekdayShortName(context.lang, d)).join(', ');
  }
}

/// Seven rows of "Monday 07:00–23:00".
class _HoursSummary extends StatelessWidget {
  const _HoursSummary({required this.hours});

  final WeekHours hours;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var d = 1; d <= 7; d++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(weekdayName(context.lang, d), style: AppText.muted.copyWith(fontSize: 15))),
              Text(
                hoursText(context.l, hours[d]),
                style: manrope(15, 700, color: hours[d] == null ? AppColors.error : AppColors.ink),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppText.muted.copyWith(fontSize: 15))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value, style: manrope(15, 700), textAlign: TextAlign.end, maxLines: 2),
        ),
      ],
    ),
  );
}
