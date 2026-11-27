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
import '../common/rating_pill.dart';
import '../common/reliability_badge.dart';
import '../common/widgets.dart';
import 'finished_section.dart';
import 'game_card.dart' show accessPills;
import 'host_tools.dart';

/// Game details: who is in, and what the signed-in player can do about it
/// (join, ask to join, answer an invite, leave) or, for the host, the requests
/// and the tools to edit, remove players and cancel.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key, required this.gameId});

  final String gameId;

  Future<void> _join(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).join(gameId));

  /// Joins with one tap inside the range, else asks the host. In padel or
  /// tennis a player with no rating answers the questionnaire first; the range
  /// is then checked again with the new rating. Only a hint: the server
  /// decides, and its refusal is shown as usual.
  Future<void> _joinOrAsk(BuildContext context, WidgetRef ref, Game game, Sport? sport, {bool invited = false}) async {
    if (sport != null && !await ensureRated(context, ref, sport)) return;
    if (!context.mounted) return;
    Player? me;
    try {
      me = await ref.read(playerProvider(kMeId).future);
    } catch (_) {
      // Not loaded: try the one-tap join and let the server decide.
      me = null;
    }
    if (!context.mounted) return;
    if (invited || me == null || fitsRange(game, me)) {
      await _join(context, ref);
    } else {
      await _ask(context, ref);
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).leave(gameId));

  Future<void> _ask(BuildContext context, WidgetRef ref) =>
      runGameAction(context, ref, () => ref.read(gameRepositoryProvider).requestToJoin(gameId));

  Future<void> _withdraw(BuildContext context, WidgetRef ref, Game game) async {
    final requestId = game.myRequestId;
    if (requestId == null) return;
    final done = await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).withdrawRequest(requestId));
    // Without the request an invite-only game is no longer the player's to see (a team game still is: they
    // could ask only while it was open to them).
    if (done && context.mounted && game.visibility == GameVisibility.inviteOnly && game.team == null) {
      context.go('/games');
    }
  }

  Future<void> _declineInvite(BuildContext context, WidgetRef ref) async {
    final done = await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).declineInvite(gameId));
    if (done && context.mounted) context.go('/games');
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, GameMember member) async {
    final name = playerName(context.l, member.name, deleted: member.deleted);
    if (!await confirmRemovePlayer(context, name) || !context.mounted) return;
    await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).removeParticipant(gameId, member.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    return Scaffold(
      body: AsyncBody(
        value: ref.watch(gameProvider(gameId)),
        onRetry: () => ref.invalidate(gameProvider(gameId)),
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
          final host = ref.watch(playerProvider(game.hostId)).valueOrNull;
          final hostName = host == null ? '' : playerName(l, host.name, deleted: host.deleted);
          final me = ref.watch(playerProvider(kMeId)).valueOrNull;
          final inRange = me == null || fitsRange(game, me);
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
                          onPressed: game.isFull ? null : () => _joinOrAsk(context, ref, game, sport, invited: true),
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
                    key: const ValueKey('game-join'),
                    onPressed: game.isFull ? null : () => _joinOrAsk(context, ref, game, sport),
                    child: Text(game.isFull ? l.errGameFull : (inRange ? l.joinGame : l.askToJoin)),
                  ),
                };

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  // Pull to see what other players changed meanwhile.
                  onRefresh: () => pullToReload(context, ref.refresh(gameProvider(gameId).future)),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                    // A game that has ended has no spots to offer.
                                    if (!game.endedAt(gameNow))
                                      Pill(
                                        text: l.spotsLeft(game.spotsLeft),
                                        color: game.isFull ? AppColors.errorSoft : AppColors.amber,
                                        onColor: game.isFull ? AppColors.error : AppColors.ink,
                                      ),
                                    Pill(
                                      text: gameRangeText(
                                        l,
                                        minLevel: game.minLevel,
                                        maxLevel: game.maxLevel,
                                        minRating: game.minRating,
                                        maxRating: game.maxRating,
                                      ),
                                      icon: Icons.bar_chart_rounded,
                                      color: AppColors.primarySoft,
                                      onColor: AppColors.primaryDark,
                                    ),
                                    ...accessPills(context, game, gameNow),
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
                      FinishedSection(game: game),
                      if (isHost && canAct) JoinRequestsSection(game: game),
                      SectionCard(
                        title: '${l.players} · ${game.participantIds.length}/${game.spots}',
                        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(
                          children: [
                            for (final member in members)
                              _PlayerTile(
                                key: ValueKey('game-player-${member.id}'),
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
  const _PlayerTile({super.key, required this.member, required this.isHost, this.onRemove});

  final GameMember member;
  final bool isHost;

  /// Set for the host, on every player but the host.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    // A game that came without names: look the player up. A deleted
    // player's name is gone for good.
    final looked = member.deleted || member.name.isNotEmpty ? null : ref.watch(playerProvider(member.id)).valueOrNull;
    final deleted = member.id != kMeId && (member.deleted || (looked?.deleted ?? false));
    final known = deleted ? l.deletedPlayer : (member.name.isNotEmpty ? member.name : looked?.name ?? '');
    final name = member.id == kMeId ? l.you : known;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          InitialAvatar(name: name, size: 42, deleted: deleted),
          const SizedBox(width: 12),
          Expanded(
            // The labels sit at the end of the name's line when both fit
            // whole; otherwise they wrap onto the next line, never cut short.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(name, style: manrope(15.5, 700)),
                if (isHost || member.name.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (isHost) Pill(text: l.host, color: AppColors.primarySoft, onColor: AppColors.primaryDark),
                      if (member.name.isNotEmpty) ReliabilityPill(reliability: member.reliability),
                    ],
                  ),
              ],
            ),
          ),
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
