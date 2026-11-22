import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/app_header.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Upcoming tournaments in the selected city. Registration arrives in a later
/// milestone, so the cards open a "coming soon" message for now.
class TournamentsScreen extends ConsumerWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncBody(
          value: ref.watch(tournamentsProvider),
          builder: (items) => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const AppHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.tournamentsPromoTitle, style: manrope(19, 800, color: Colors.white, height: 1.2)),
                            const SizedBox(height: 4),
                            Text(l.tournamentsPromoText, style: manrope(13.5, 600, color: AppColors.lime, height: 1.3)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Image.asset(kTrophyIcon, width: 76, height: 76, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
                child: Text('${l.homeTournaments} (${items.length})'.toUpperCase(), style: AppText.sectionTitle),
              ),
              if (items.isEmpty)
                EmptyState(icon: Icons.emoji_events_outlined, text: l.noTournaments)
              else
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TournamentCard(item: item),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class TournamentCard extends ConsumerWidget {
  const TournamentCard({super.key, required this.item});

  final TournamentItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final city = ref.watch(currentCityProvider);
    final now = ref.watch(cityNowProvider)();
    final full = item.slotsFilled >= item.slotsTotal;
    final fee = item.minFee == item.maxFee
        ? money(l, item.minFee, city.currency)
        : '${groupThousands(item.minFee)} – ${money(l, item.maxFee, city.currency)}';
    final dates = item.start == item.end
        ? dayLabel(l, context.lang, item.start, now)
        : '${dayLabel(l, context.lang, item.start, now)} – ${dayLabel(l, context.lang, item.end, now)}';

    return Card(
      child: InkWell(
        onTap: () => showMessage(context, l.comingSoon),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PhotoBox(asset: tournamentPhoto(item.id), width: 104, height: 104, radius: 14),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SportBadge(sportId: item.sportId, size: 22),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Pill(
                                text: full ? l.tournamentFull : l.registrationOpen,
                                color: full ? AppColors.errorSoft : AppColors.primarySoft,
                                onColor: full ? AppColors.error : AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title.resolve(context.lang),
                          style: AppText.cardTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.venueName.resolve(context.lang),
                          style: AppText.muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(dates, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Text(l.entryFee, style: AppText.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fee,
                      style: manrope(14.5, 800),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: item.slotsFilled / item.slotsTotal,
                borderRadius: BorderRadius.circular(8),
                minHeight: 7,
                color: full ? AppColors.error : AppColors.primary,
              ),
              const SizedBox(height: 6),
              Text(l.filledOf(item.slotsFilled, item.slotsTotal), style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}
