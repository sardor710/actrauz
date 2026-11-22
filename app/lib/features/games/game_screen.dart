import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';

/// Game details with the participant list and one-tap join or leave.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key, required this.gameId});

  final String gameId;

  Future<void> _act(BuildContext context, WidgetRef ref, {required bool join}) async {
    final l = context.l;
    final repo = ref.read(gameRepositoryProvider);
    try {
      await (join ? repo.join(gameId) : repo.leave(gameId));
      ref.invalidate(gameProvider(gameId));
      // No success message: the player list and the button already show the
      // result, and a snackbar would cover the button.
      ref.invalidate(gamesProvider);
    } on JoinException catch (e) {
      if (context.mounted) showMessage(context, joinErrorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: AsyncBody(
        value: ref.watch(gameProvider(gameId)),
        builder: (game) {
          final venue = ref.watch(venueProvider(game.venueId)).valueOrNull;
          final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
          final sport = sports.where((s) => s.id == game.sportId).firstOrNull;
          final currency = cityById(game.cityId).currency;
          final now = ref.watch(cityNowProvider)();
          final amIn = game.participantIds.contains(kMeId);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SeedArt(
                        seed: venue?.colorSeed ?? 0,
                        icon: sportIcon(sport?.iconKey ?? ''),
                        height: 140,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                sport?.name.resolve(context.lang) ?? '',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${dayLabel(l, context.lang, game.start, now)}, ${timeRange(game.start, game.end)}',
                                style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (venue != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(venue.name.resolve(context.lang)),
                        subtitle: Text(venue.address.resolve(context.lang)),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill(
                          text: l.spotsLeft(game.spotsLeft),
                          color: game.isFull ? scheme.errorContainer : scheme.tertiaryContainer,
                          onColor: game.isFull ? scheme.onErrorContainer : scheme.onTertiaryContainer,
                        ),
                        Pill(text: l.levelRange(game.minLevel, game.maxLevel), icon: Icons.bar_chart),
                        if (game.pricePerPlayer != null)
                          Pill(text: l.perPlayer(money(l, game.pricePerPlayer!, currency))),
                        Pill(text: l.payAtVenue, icon: Icons.payments_outlined),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${l.players} · ${game.participantIds.length}/${game.spots}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    for (final id in game.participantIds) _PlayerTile(playerId: id, isHost: id == game.hostId),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: amIn
                        ? OutlinedButton(
                            onPressed: () => _act(context, ref, join: false),
                            child: Text(l.leaveGame),
                          )
                        : FilledButton(
                            onPressed: game.isFull ? null : () => _act(context, ref, join: true),
                            child: Text(game.isFull ? l.errGameFull : l.joinGame),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerTile extends ConsumerWidget {
  const _PlayerTile({required this.playerId, required this.isHost});

  final String playerId;
  final bool isHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final player = ref.watch(playerProvider(playerId)).valueOrNull;
    final isMe = playerId == kMeId;
    final name = isMe ? l.you : (player?.name ?? '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase())),
      title: Text(name),
      trailing: isHost ? Pill(text: l.host) : null,
    );
  }
}
