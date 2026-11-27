import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../data/sample/sample_media.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/ui_providers.dart';
import '../common/app_header.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../home/home_screen.dart';
import 'game_card.dart';
import 'request_card.dart';

/// Open games in the city, filtered by day, sport and the player's level.
class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key});

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> {
  static const _days = 14;
  bool _myLevel = false;

  Future<void> _pickSport(List<Sport> sports) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.filterSport,
      options: {'': l.allSports, for (final s in sports) s.id: s.name.resolve(context.lang)},
      current: ref.read(gamesSportFilterProvider) ?? '',
    );
    if (picked != null) ref.read(gamesSportFilterProvider.notifier).state = picked.isEmpty ? null : picked;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sportId = ref.watch(gamesSportFilterProvider);
    final day = ref.watch(gamesDayProvider);
    final today = dateOnly(ref.watch(cityNowProvider)());
    final me = ref.watch(playerProvider(kMeId)).valueOrNull;
    final sportName = sports.where((s) => s.id == sportId).firstOrNull?.name.resolve(context.lang);
    final tab = ref.watch(gamesTabProvider);

    bool matches(Game g) {
      if (sportId != null && g.sportId != sportId) return false;
      if (day != null && dateOnly(g.start) != today.add(Duration(days: day))) return false;
      // The rating range in padel and tennis, the level range elsewhere.
      if (_myLevel && me != null && !fitsRange(g, me)) return false;
      return true;
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(tab == 0 ? '/games/new' : '/games/requests/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: Text(
          (tab == 0 ? l.createGame : l.postRequest).toUpperCase(),
          style: manrope(14, 800, color: Colors.white, letterSpacing: 0.4),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: tab == 1
            ? const _RequestsList()
            : AsyncBody(
                value: ref.watch(gamesProvider),
                builder: (games) {
                  final shown = games.where(matches).toList();
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      const AppHeader(),
                      const GamesTabSwitch(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                        child: SizedBox(
                          height: 168,
                          child: PromoCard(
                            photo: kGamesPromoPhoto,
                            title: l.gamesPromoTitle,
                            subtitle: l.gamesPromoText,
                            cta: l.gamesPromoCta,
                            onTap: () => context.go('/venues'),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 82,
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            _MonthTag(text: DateFormat('MMM', context.lang).format(today).toUpperCase()),
                            Expanded(
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: _days + 1,
                                itemBuilder: (context, i) {
                                  if (i == 0) {
                                    return _DayItem(
                                      top: l.allDays,
                                      bottom: null,
                                      selected: day == null,
                                      onTap: () => ref.read(gamesDayProvider.notifier).state = null,
                                    );
                                  }
                                  final offset = i - 1;
                                  final date = today.add(Duration(days: offset));
                                  return _DayItem(
                                    top: offset == 0 ? l.today : weekdayShort(context.lang, date),
                                    bottom: '${date.day}',
                                    selected: day == offset,
                                    onTap: () => ref.read(gamesDayProvider.notifier).state = offset,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            FilterChipButton(
                              label: sportName ?? l.filterSport,
                              selected: sportId != null,
                              dropdown: true,
                              onTap: () => _pickSport(sports),
                            ),
                            FilterChipButton(
                              label: l.myLevel,
                              icon: Icons.bar_chart_rounded,
                              selected: _myLevel,
                              onTap: () => setState(() => _myLevel = !_myLevel),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
                        child: Text(l.homeGames.toUpperCase(), style: AppText.sectionTitle),
                      ),
                      if (shown.isEmpty)
                        EmptyState(icon: Icons.groups_outlined, text: l.noGames)
                      else
                        for (final game in shown)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: GameCard(game: game),
                          ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _MonthTag extends StatelessWidget {
  const _MonthTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
    alignment: Alignment.center,
    child: RotatedBox(
      quarterTurns: 3,
      child: Text(
        text.replaceAll('.', ''),
        style: manrope(12.5, 800, color: AppColors.primaryDark, letterSpacing: 1),
        maxLines: 1,
      ),
    ),
  );
}

class _DayItem extends StatelessWidget {
  const _DayItem({required this.top, required this.bottom, required this.selected, required this.onTap});

  final String top;

  /// Day of month; `null` for the "all days" item.
  final String? bottom;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: SizedBox(
      width: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(top, style: manrope(13, 600, color: selected ? AppColors.ink : AppColors.muted), maxLines: 1),
          const SizedBox(height: 6),
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: bottom == null
                ? Icon(Icons.apps_rounded, size: 20, color: selected ? Colors.white : AppColors.ink)
                : Text(bottom!, style: manrope(17, 700, color: selected ? Colors.white : AppColors.ink)),
          ),
        ],
      ),
    ),
  );
}

/// Games or Game Requests, on the Games tab.
class GamesTabSwitch extends ConsumerWidget {
  const GamesTabSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final tab = ref.watch(gamesTabProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 0, label: Text(l.tabGames, key: const ValueKey('games-tab-games'))),
            ButtonSegment(value: 1, label: Text(l.gamesTabRequests, key: const ValueKey('games-tab-requests'))),
          ],
          selected: {tab},
          onSelectionChanged: (v) => ref.read(gamesTabProvider.notifier).state = v.first,
        ),
      ),
    );
  }
}

/// Open Game Requests in the city, for the sport picked in the filter.
class _RequestsList extends ConsumerWidget {
  const _RequestsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sportId = ref.watch(gamesSportFilterProvider);
    final sportName = sports.where((s) => s.id == sportId).firstOrNull?.name.resolve(context.lang);

    return AsyncBody(
      value: ref.watch(gameRequestsProvider),
      builder: (requests) {
        final shown = [
          for (final r in requests)
            if (sportId == null || r.sportId == sportId) r,
        ];
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const AppHeader(),
            const GamesTabSwitch(),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  FilterChipButton(
                    label: sportName ?? l.filterSport,
                    selected: sportId != null,
                    dropdown: true,
                    onTap: () async {
                      final picked = await showOptionSheet(
                        context,
                        title: l.filterSport,
                        options: {'': l.allSports, for (final s in sports) s.id: s.name.resolve(context.lang)},
                        current: sportId ?? '',
                      );
                      if (picked != null) {
                        ref.read(gamesSportFilterProvider.notifier).state = picked.isEmpty ? null : picked;
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
              child: Text(l.homeRequests.toUpperCase(), style: AppText.sectionTitle),
            ),
            if (shown.isEmpty)
              EmptyState(icon: Icons.groups_outlined, text: l.noRequests)
            else
              for (final request in shown)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: GameRequestCard(request: request),
                ),
          ],
        );
      },
    );
  }
}
