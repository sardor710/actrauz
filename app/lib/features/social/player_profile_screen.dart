import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/community.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/reliability_badge.dart';
import '../common/widgets.dart';
import '../games/host_tools.dart';
import '../games/report_sheet.dart';

/// A player's public profile: name, level per sport, reliability, games
/// played and sportsmanship. The host can invite them to one of their own
/// open games, and anyone can report them from the menu. Opens for players
/// who hid themselves from search too.
class PlayerProfileScreen extends ConsumerWidget {
  const PlayerProfileScreen({super.key, required this.playerId});

  final String playerId;

  void _back(BuildContext context) => context.canPop() ? context.pop() : context.go('/social');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    String sportName(String id) => sports.where((s) => s.id == id).firstOrNull?.name.resolve(context.lang) ?? id;
    final loaded = ref.watch(playerProfileProvider(playerId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _back(context)),
        title: Text(l.playerProfileTitle),
        actions: [
          // Not oneself, and not a deleted account.
          if (loaded != null && loaded.id != kMeId && !loaded.deleted)
            PopupMenuButton<String>(
              key: const ValueKey('profile-menu'),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (_) => showReportSheet(
                context,
                targetId: loaded.id,
                name: playerName(l, loaded.name, deleted: loaded.deleted),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(key: const ValueKey('profile-report'), value: 'report', child: Text(l.reportAction)),
              ],
            ),
        ],
      ),
      body: AsyncBody(
        value: ref.watch(playerProfileProvider(playerId)),
        builder: (player) {
          final isMe = player.id == kMeId;
          final name = playerName(l, player.name, deleted: player.deleted);
          final hint = reliabilityHint(l, player.reliability.badge);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              InitialAvatar(name: name, size: 72, deleted: player.deleted),
                              const SizedBox(height: 12),
                              Text(name, style: manrope(22, 800), textAlign: TextAlign.center),
                              const SizedBox(height: 10),
                              ReliabilityPill(reliability: player.reliability, large: true),
                              const SizedBox(height: 8),
                              Text(l.reliabilityScore(player.reliability.score), style: AppText.muted),
                              if (hint != null && isMe) ...[
                                const SizedBox(height: 8),
                                Text(hint, style: AppText.muted, textAlign: TextAlign.center),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  Pill(text: l.gamesPlayed(player.gamesPlayed), icon: Icons.sports_score_outlined),
                                  if (player.sportsmanship.percent != null) SportsmanshipPill(player.sportsmanship),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SectionCard(
                      title: l.profileLevels,
                      child: player.levels.isEmpty
                          ? Text(l.noLevelsYet, style: AppText.muted.copyWith(fontSize: 15))
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry in player.levels.entries)
                                  if (player.ratings[entry.key] case final rating?)
                                    // A rated sport: the rating, its provisional tag and rated games.
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(sportName(entry.key), style: AppText.bodyStrong),
                                        const SizedBox(width: 8),
                                        Flexible(child: RatingPill(rating, showGames: true)),
                                      ],
                                    )
                                  else
                                    Pill(
                                      text: '${sportName(entry.key)} · ${l.level(entry.value)}',
                                      color: AppColors.primarySoft,
                                      onColor: AppColors.primaryDark,
                                    ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              // A deleted player cannot be invited.
              if (!isMe && !player.deleted)
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
                        child: FilledButton.icon(
                          onPressed: () => showInviteSheet(context, player),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(l.inviteToGame),
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

/// The share of thumbs up and the number of votes (an icon, not an emoji),
/// once there are enough votes to show (design §6.1); nothing before.
class SportsmanshipPill extends StatelessWidget {
  const SportsmanshipPill(this.sportsmanship, {super.key});

  final Sportsmanship sportsmanship;

  @override
  Widget build(BuildContext context) {
    final percent = sportsmanship.percent;
    if (percent == null) return const SizedBox.shrink();
    return Pill(
      key: const ValueKey('sportsmanship'),
      text: context.l.sportsmanshipSummary(percent, sportsmanship.votes),
      icon: Icons.thumb_up_alt_outlined,
    );
  }
}

/// The signed-in player's upcoming hosted games that are open, have not
/// started, are not full and do not have [player] in them.
List<Game> invitableGames(List<Game> games, PlayerProfile player, DateTime now) => [
  for (final g in games)
    if (g.myStatus == MyGameStatus.host &&
        !g.cancelled &&
        g.start.isAfter(now) &&
        !g.isFull &&
        !g.participantIds.contains(player.id))
      g,
];

Future<void> showInviteSheet(BuildContext context, PlayerProfile player) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _InviteSheet(player: player),
);

class _InviteSheet extends ConsumerWidget {
  const _InviteSheet({required this.player});

  final PlayerProfile player;

  Future<void> _invite(BuildContext context, WidgetRef ref, Game game) async {
    final l = context.l;
    // The sheet closes with the invite; keep the screen's messenger for the answer.
    final messenger = ScaffoldMessenger.of(context);
    final done = await runGameAction(context, ref, () => ref.read(gameRepositoryProvider).invite(game.id, player.id));
    if (!done) return;
    if (context.mounted) Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.inviteSent(player.name)), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final now = ref.watch(cityNowProvider)();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.chooseGameToInvite, style: AppText.title),
              const SizedBox(height: 8),
              AsyncBody(
                value: ref.watch(gamesProvider),
                builder: (games) {
                  final open = invitableGames(games, player, now);
                  if (open.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(l.noGamesToInvite, style: AppText.muted.copyWith(fontSize: 15)),
                    );
                  }
                  return Column(
                    children: [
                      for (final game in open)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: SportBadge(sportId: game.sportId, size: 36),
                          title: Text(
                            l.gameTitle(
                              l.you,
                              sports.where((s) => s.id == game.sportId).firstOrNull?.name.resolve(context.lang) ?? '',
                            ),
                            style: manrope(15.5, 700),
                          ),
                          subtitle: Text(
                            '${dayLabel(l, context.lang, game.start, now)} · ${timeRange(game.start, game.end)}',
                            style: AppText.muted,
                          ),
                          trailing: Text(l.going(game.participantIds.length, game.spots), style: AppText.muted),
                          onTap: () => _invite(context, ref, game),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
