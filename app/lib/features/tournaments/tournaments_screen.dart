import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/models.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/app_header.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import 'tournament_tools.dart';

/// Upcoming tournaments in the selected city: filter by date and sport, sort
/// by date or A–Z, and open one to register.
class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  String? _sportId;

  /// Hides tournaments that end before this day. Part of the query, so it is
  /// a date and never "now".
  DateTime? _from;
  bool _az = false;

  Future<void> _pickSport(List<Sport> sports) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.filterSport,
      options: {'': l.allSports, for (final s in sports) s.id: s.name.resolve(context.lang)},
      current: _sportId ?? '',
    );
    if (picked != null) setState(() => _sportId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickDate() async {
    final today = dateOnly(ref.read(cityNowProvider)());
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _from = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final city = ref.watch(currentCityProvider);
    final now = ref.watch(cityNowProvider)();
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sportName = sports.where((s) => s.id == _sportId).firstOrNull?.name.resolve(context.lang);
    final query = (sportId: _sportId, from: _from, sort: _az ? TournamentSort.az : TournamentSort.date);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    FilterChipButton(
                      key: const ValueKey('tournaments-sport'),
                      label: sportName ?? l.filterSport,
                      selected: _sportId != null,
                      dropdown: true,
                      onTap: () => _pickSport(sports),
                    ),
                    FilterChipButton(
                      key: const ValueKey('tournaments-date'),
                      icon: Icons.event_outlined,
                      label: _from == null
                          ? l.tournamentFilterDate
                          : l.tournamentFilterFrom(dayLabel(l, context.lang, _from!, now)),
                      selected: _from != null,
                      onTap: _pickDate,
                    ),
                    if (_from != null)
                      FilterChipButton(
                        key: const ValueKey('tournaments-date-clear'),
                        icon: Icons.close_rounded,
                        onTap: () => setState(() => _from = null),
                      ),
                    FilterChipButton(
                      key: const ValueKey('tournaments-city'),
                      icon: Icons.place_outlined,
                      label: city.name.resolve(context.lang),
                      dropdown: true,
                      onTap: () => showCityPicker(context, ref),
                    ),
                    FilterChipButton(
                      key: const ValueKey('tournaments-sort-az'),
                      icon: Icons.sort_by_alpha_rounded,
                      label: l.tournamentSortAz,
                      selected: _az,
                      onTap: () => setState(() => _az = !_az),
                    ),
                  ],
                ),
              ),
            ),
            AsyncBody(
              value: ref.watch(tournamentsProvider(query)),
              builder: (items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${l.homeTournaments} (${items.length})'.toUpperCase(), style: AppText.sectionTitle),
                        ),
                        TextButton.icon(
                          key: const ValueKey('my-tournaments'),
                          onPressed: () => context.push('/my-tournaments'),
                          icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                          label: Text(l.tournamentsMine),
                        ),
                      ],
                    ),
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
          ],
        ),
      ),
    );
  }
}

class TournamentCard extends ConsumerWidget {
  const TournamentCard({super.key, required this.item});

  final Tournament item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final now = tournamentNow(ref, item.cityId);
    final sport = ref.watch(sportsProvider).valueOrNull?.where((s) => s.id == item.sportId).firstOrNull;
    final full = item.full;
    final (pill, pillColor, pillOn) = !item.registrationOpen
        ? (l.registrationClosed, AppColors.field, AppColors.muted)
        : full
        ? (l.tournamentFull, AppColors.errorSoft, AppColors.error)
        : (l.registrationOpen, AppColors.primarySoft, AppColors.primaryDark);
    final place = [
      ?sport?.name.resolve(context.lang),
      cityById(item.cityId).name.resolve(context.lang),
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: () => context.go('/tournaments/${item.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TournamentCover(
                    id: item.id,
                    sportId: item.sportId,
                    coverUrl: item.coverUrl,
                    colorSeed: item.colorSeed,
                    width: 104,
                    height: 104,
                  ),
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
                              child: Pill(text: pill, color: pillColor, onColor: pillOn),
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
                        Text(place, style: AppText.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          tournamentDates(l, context.lang, item, now),
                          style: AppText.muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                      feeRangeText(l, item.minFee, item.maxFee, item.currency),
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
                value: item.slotsTotal == 0 ? 0 : item.slotsFilled / item.slotsTotal,
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
