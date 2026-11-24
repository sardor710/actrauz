import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// One joinable game: time, who is going, title, venue and level.
class GameCard extends ConsumerWidget {
  const GameCard({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final venueId = game.venueId;
    final venue = venueId == null ? null : ref.watch(venueProvider(venueId)).valueOrNull;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sport = sports.where((s) => s.id == game.sportId).firstOrNull;
    final now = ref.watch(cityNowProvider)();

    String nameOf(String id) =>
        id == kMeId ? l.you : (ref.watch(playerProvider(id)).valueOrNull?.name ?? '');
    final names = [for (final id in game.participantIds) nameOf(id)];
    final host = nameOf(game.hostId);
    final scarce = !game.isFull && game.spotsLeft <= 2;

    return Card(
      child: InkWell(
        onTap: () => context.go('/games/${game.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Pill(
                        text: '${dayLabel(l, context.lang, game.start, now)} · ${timeRange(game.start, game.end)}',
                        color: AppColors.blue,
                        onColor: Colors.white,
                        large: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SportBadge(sportId: game.sportId, size: 30),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  AvatarStack(names: names),
                  const SizedBox(width: 10),
                  // Side by side when there is room, stacked on a narrow card.
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l.going(game.participantIds.length, game.spots),
                          style: manrope(15, 600, color: AppColors.muted),
                        ),
                        if (scarce || game.isFull)
                          Pill(
                            text: l.spotsLeft(game.spotsLeft),
                            color: game.isFull ? AppColors.errorSoft : AppColors.amber,
                            onColor: game.isFull ? AppColors.error : AppColors.ink,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.gameTitle(host, sport?.name.resolve(context.lang) ?? ''),
                style: AppText.cardTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      venue?.name.resolve(context.lang) ?? '',
                      style: AppText.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(
                    text: l.levelRange(game.minLevel, game.maxLevel),
                    icon: Icons.bar_chart_rounded,
                    color: AppColors.primarySoft,
                    onColor: AppColors.primaryDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
