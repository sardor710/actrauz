import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../data/sample/sample_media.dart';
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

    return Scaffold(
      body: AsyncBody(
        value: ref.watch(gameProvider(gameId)),
        builder: (game) {
          final venue = ref.watch(venueProvider(game.venueId)).valueOrNull;
          final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
          final sport = sports.where((s) => s.id == game.sportId).firstOrNull;
          final currency = cityById(game.cityId).currency;
          final now = ref.watch(cityNowProvider)();
          final amIn = game.participantIds.contains(kMeId);
          final hostName = ref.watch(playerProvider(game.hostId)).valueOrNull?.name ?? '';

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    PhotoBox(
                      asset: venuePhoto(game.venueId),
                      height: 250,
                      radius: 0,
                      darken: 0.55,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OverlayIconButton(icon: Icons.arrow_back_rounded, onTap: () => context.pop()),
                              const Spacer(),
                              Pill(
                                text: '${dayLabel(l, context.lang, game.start, now)} · ${timeRange(game.start, game.end)}',
                                color: AppColors.blue,
                                onColor: Colors.white,
                                large: true,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l.gameTitle(hostName, sport?.name.resolve(context.lang) ?? ''),
                                style: manrope(23, 800, color: Colors.white, height: 1.2),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (venue != null)
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, color: AppColors.muted),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(venue.name.resolve(context.lang), style: manrope(16, 700)),
                                          Text(venue.address.resolve(context.lang), style: AppText.muted),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Pill(
                                    text: l.spotsLeft(game.spotsLeft),
                                    color: game.isFull ? AppColors.errorSoft : AppColors.amber,
                                    onColor: game.isFull ? AppColors.error : AppColors.ink,
                                  ),
                                  Pill(
                                    text: l.levelRange(game.minLevel, game.maxLevel),
                                    icon: Icons.bar_chart_rounded,
                                    color: AppColors.primarySoft,
                                    onColor: AppColors.primaryDark,
                                  ),
                                  if (game.pricePerPlayer != null)
                                    Pill(text: l.perPlayer(money(l, game.pricePerPlayer!, currency))),
                                  Pill(text: l.payAtVenue, icon: Icons.payments_outlined),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SectionCard(
                      title: '${l.players} · ${game.participantIds.length}/${game.spots}',
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        children: [
                          for (final id in game.participantIds) _PlayerTile(playerId: id, isHost: id == game.hostId),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
    final name = playerId == kMeId ? l.you : (player?.name ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          InitialAvatar(name: name, size: 42),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: manrope(15.5, 700))),
          if (isHost) Pill(text: l.host, color: AppColors.primarySoft, onColor: AppColors.primaryDark),
        ],
      ),
    );
  }
}
