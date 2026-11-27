import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';

/// A rated sport's players in the current city, best rating first: the top
/// 100, and the signed-in player's own row pinned below when they are lower
/// (design 2026-11-27-actra-m7-competitive §5.7). Reached from the Social tab
/// and from the rating on the profile.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, required this.sportId});

  final String sportId;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  late String _sportId = widget.sportId;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final city = ref.watch(currentCityProvider);
    final cityName = city.name.resolve(context.lang);
    final rated = [
      for (final s in ref.watch(sportsProvider).valueOrNull ?? const <Sport>[])
        if (s.competitiveRating) s,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text(l.leaderboardTitle(cityName)),
      ),
      body: Column(
        children: [
          if (rated.length > 1)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                children: [
                  for (final s in rated)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChipButton(
                        key: ValueKey('leaderboard-sport-${s.id}'),
                        label: s.name.resolve(context.lang),
                        selected: s.id == _sportId,
                        onTap: () => setState(() => _sportId = s.id),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: AsyncBody(
              value: ref.watch(leaderboardProvider((sportId: _sportId, cityId: city.id))),
              builder: (board) {
                final me = board.me;
                if (board.rows.isEmpty && me == null) {
                  return EmptyState(icon: Icons.emoji_events_outlined, text: l.leaderboardEmpty(cityName));
                }
                // My row is pinned whenever the list does not hold it: I rank
                // below the top 100, or I hid myself from search.
                final pinned = me != null && !board.rows.any((r) => r.id == me.id) ? me : null;
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: [
                          if (board.rows.isNotEmpty)
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (var i = 0; i < board.rows.length; i++) ...[
                                    if (i > 0) const Divider(height: 1),
                                    _LeaderboardTile(row: board.rows[i]),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (pinned != null)
                      Material(
                        key: const ValueKey('leaderboard-me'),
                        color: AppColors.primarySoft,
                        child: SafeArea(top: false, child: _LeaderboardTile(row: pinned)),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({required this.row});

  final LeaderboardRow row;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return InkWell(
      key: ValueKey('leaderboard-row-${row.id}'),
      onTap: () => context.push('/players/${row.id}'),
      child: Container(
        color: row.isMe ? AppColors.primarySoft : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 34, child: Text('${row.position}', style: manrope(15, 800))),
            InitialAvatar(name: row.name, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name, style: manrope(15.5, 700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  // The provisional tag sits by the games count, so the name
                  // keeps its room on a small phone.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(l.leaderboardGames(row.rating.ratedGames), style: AppText.caption),
                      if (row.rating.provisional) Pill(text: l.ratingProvisional, color: AppColors.amberSoft),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Pill(
              text: formatRating(row.rating.rating),
              icon: Icons.bar_chart_rounded,
              color: AppColors.primarySoft,
              onColor: AppColors.primaryDark,
            ),
          ],
        ),
      ),
    );
  }
}
