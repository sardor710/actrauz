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
import '../common/reliability_badge.dart';
import '../common/widgets.dart';
import 'host_tools.dart';

/// Game details: who is in, and what the signed-in player can do about it
/// (join, ask to join, answer an invite, leave) or, for the host, the requests
/// and the tools to edit, remove players and cancel.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key, required this.gameId});

  final String gameId;

  Future<void> _join(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).join(gameId));

  Future<void> _leave(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).leave(gameId));

  Future<void> _ask(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).requestToJoin(gameId));

  Future<void> _withdraw(BuildContext context, WidgetRef ref, Game game) async {
    final requestId = game.myRequestId;
    if (requestId == null) return;
    final done = await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).withdrawRequest(requestId));
    // Without the request an invite-only game is no longer the player's to see.
    if (done && context.mounted && game.visibility == GameVisibility.inviteOnly) context.go('/games');
  }

  Future<void> _declineInvite(BuildContext context, WidgetRef ref) async {
    final done = await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).declineInvite(gameId));
    if (done && context.mounted) context.go('/games');
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, GameMember member) async {
    if (!await confirmRemovePlayer(context, member.name) || !context.mounted) return;
    await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).removeParticipant(gameId, member.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    return Scaffold(
      body: AsyncBody(
        value: ref.watch(gameProvider(gameId)),
        builder: (game) {
          final venueId = game.venueId;
          final venue = venueId == null ? null : ref.watch(venueProvider(venueId)).valueOrNull;
          final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
          final sport = sports.where((s) => s.id == game.sportId).firstOrNull;
          final currency = cityById(game.cityId).currency;
          final now = ref.watch(cityNowProvider)();
          final gameNow = venueNow(cityById(game.cityId), utcNow: ref.watch(clockProvider)());
          final status = game.myStatus;
          final isHost = status == MyGameStatus.host;
          final hostName = ref.watch(playerProvider(game.hostId)).valueOrNull?.name ?? '';
          final myLevel = ref.watch(playerProvider(kMeId)).valueOrNull?.levelFor(game.sportId);
          final inRange = myLevel == null || (myLevel >= game.minLevel && myLevel <= game.maxLevel);
          // A cancelled or started game takes no more joining or hosting changes.
          final canAct = !game.cancelled && game.start.isAfter(gameNow);
          final members = game.participants.isNotEmpty
              ? game.participants
              : [for (final id in game.participantIds) GameMember(id: id, name: '')];
          final distance = game.distanceKm;

          final bar = !canAct
              ? null
              : switch (status) {
                  MyGameStatus.host => null,
                  MyGameStatus.participant => OutlinedButton(
                    onPressed: () => _leave(context, ref),
                    child: Text(l.leaveGame),
                  ),
                  MyGameStatus.invited => Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _declineInvite(context, ref),
                          child: Text(l.declineLabel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: game.isFull ? null : () => _join(context, ref),
                          child: Text(game.isFull ? l.errGameFull : l.acceptInvite),
                        ),
                      ),
                    ],
                  ),
                  MyGameStatus.requested => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(onPressed: null, child: Text(l.requested)),
                      ),
                      TextButton(onPressed: () => _withdraw(context, ref, game), child: Text(l.withdrawRequest)),
                    ],
                  ),
                  null => FilledButton(
                    onPressed: game.isFull ? null : () => inRange ? _join(context, ref) : _ask(context, ref),
                    child: Text(game.isFull ? l.errGameFull : (inRange ? l.joinGame : l.askToJoin)),
                  ),
                };

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    PhotoBox(
                      asset: venueId == null ? kGamesPromoPhoto : venuePhoto(venueId),
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
                                text:
                                    '${dayLabel(l, context.lang, game.start, now)} · ${timeRange(game.start, game.end)}',
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
                    if (game.cancelled)
                      _Banner(icon: Icons.event_busy_outlined, text: l.gameCancelledBanner, error: true)
                    else if (status == MyGameStatus.invited)
                      _Banner(icon: Icons.mail_outline_rounded, text: l.invitedToGame),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (venue != null || game.meetingPoint != null) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.place_outlined, color: AppColors.muted),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: venue != null
                                          ? Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(venue.name.resolve(context.lang), style: manrope(16, 700)),
                                                Text(venue.address.resolve(context.lang), style: AppText.muted),
                                              ],
                                            )
                                          : Text(game.meetingPoint!, style: manrope(16, 700)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
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
                                  if (game.visibility == GameVisibility.inviteOnly)
                                    Pill(text: l.visibilityInviteOnly, icon: Icons.lock_outline_rounded),
                                  if (distance != null)
                                    Pill(
                                      text: l.distanceValue(
                                        distance == distance.roundToDouble() ? '${distance.round()}' : '$distance',
                                      ),
                                      icon: Icons.route_outlined,
                                    ),
                                  if (game.pace != null)
                                    Pill(text: l.paceValue(game.pace!), icon: Icons.speed_outlined),
                                  if (game.pricePerPlayer != null) ...[
                                    Pill(text: l.perPlayer(money(l, game.pricePerPlayer!, currency))),
                                    Pill(text: l.payAtVenue, icon: Icons.payments_outlined),
                                  ],
                                ],
                              ),
                              if (game.note != null) ...[
                                const SizedBox(height: 14),
                                Text(game.note!, style: AppText.body),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isHost && canAct) JoinRequestsSection(game: game),
                    SectionCard(
                      title: '${l.players} · ${game.participantIds.length}/${game.spots}',
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Column(
                        children: [
                          for (final member in members)
                            _PlayerTile(
                              member: member,
                              isHost: member.id == game.hostId,
                              onRemove: isHost && canAct && member.id != game.hostId
                                  ? () => _remove(context, ref, member)
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    if (isHost && canAct) HostToolsSection(game: game, onCancelled: () => context.go('/games')),
                  ],
                ),
              ),
              if (bar != null)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    border: Border(top: BorderSide(color: AppColors.line)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: SizedBox(width: double.infinity, child: bar),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? AppColors.errorSoft : AppColors.primarySoft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, color: error ? AppColors.error : AppColors.primaryDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: manrope(14.5, 700, color: error ? AppColors.error : AppColors.primaryDark)),
        ),
      ],
    ),
  );
}

class _PlayerTile extends ConsumerWidget {
  const _PlayerTile({required this.member, required this.isHost, this.onRemove});

  final GameMember member;
  final bool isHost;

  /// Set for the host, on every player but the host.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    // A game that came without names: look the player up.
    final known = member.name.isNotEmpty ? member.name : ref.watch(playerProvider(member.id)).valueOrNull?.name ?? '';
    final name = member.id == kMeId ? l.you : known;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          InitialAvatar(name: name, size: 42),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: manrope(15.5, 700))),
          if (isHost) Pill(text: l.host, color: AppColors.primarySoft, onColor: AppColors.primaryDark),
          if (member.name.isNotEmpty) ...[const SizedBox(width: 6), ReliabilityPill(reliability: member.reliability)],
          if (onRemove != null)
            IconButton(
              tooltip: l.removePlayer,
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove_outlined, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}
