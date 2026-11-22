import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// One joinable game: sport, venue, time, spots left, level range, price.
class GameCard extends ConsumerWidget {
  const GameCard({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final venue = ref.watch(venueProvider(game.venueId)).valueOrNull;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final sport = sports.where((s) => s.id == game.sportId).firstOrNull;
    final currency = cityById(game.cityId).currency;
    final now = ref.watch(cityNowProvider)();

    return Card(
      child: InkWell(
        onTap: () => context.go('/games/${game.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(sportIcon(sport?.iconKey ?? ''), size: 20, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sport?.name.resolve(context.lang) ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          venue?.name.resolve(context.lang) ?? '',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${dayLabel(l, context.lang, game.start, now)}, ${timeRange(game.start, game.end)}',
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // One line each, so the card keeps the same height in every language.
              Row(
                children: [
                  Flexible(
                    child: Pill(
                      text: l.spotsLeft(game.spotsLeft),
                      color: game.isFull ? scheme.errorContainer : scheme.tertiaryContainer,
                      onColor: game.isFull ? scheme.onErrorContainer : scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Pill(text: l.levelRange(game.minLevel, game.maxLevel), icon: Icons.bar_chart)),
                ],
              ),
              if (game.pricePerPlayer != null) ...[
                const SizedBox(height: 8),
                Text(
                  l.perPlayer(money(l, game.pricePerPlayer!, currency)),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
