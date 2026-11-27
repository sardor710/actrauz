import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/markets.dart';
import '../../core/theme.dart';
import '../../data/sample/sample_data.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';
import 'host_tools.dart';
import 'report_sheet.dart';
import 'score_sheet.dart';

/// "Game finished" on the game page (design §5.8): for the players of a game
/// that has ended, was not cancelled and had someone else in it. The score
/// block in a rated sport, then the other players with thumbs up or down,
/// "Didn't show up" and "Report" (design §6.1-§6.3).
class FinishedSection extends ConsumerWidget {
  const FinishedSection({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = game.myStatus;
    if (game.cancelled ||
        game.participantIds.length < 2 ||
        (status != MyGameStatus.host && status != MyGameStatus.participant)) {
      return const SizedBox.shrink();
    }
    // Venue wall-clock time, as the game's start and end.
    final now = venueNow(cityById(game.cityId), utcNow: ref.watch(clockProvider)());
    if (!game.endedAt(now)) return const SizedBox.shrink();
    final sports = ref.watch(sportsProvider).valueOrNull ?? const <Sport>[];
    final rated = sports.where((s) => s.id == game.sportId).firstOrNull?.competitiveRating ?? false;
    final others = _othersOf(game);
    if (!rated && others.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      key: const ValueKey('finished-section'),
      title: context.l.gameFinished,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rated) _ScoreBlock(game: game, now: now),
          if (rated && others.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],
          if (others.isNotEmpty) _OtherPlayers(game: game, others: others, now: now),
        ],
      ),
    );
  }
}

/// The other players of [game], leaving out deleted accounts: they can no
/// longer be rated or reported.
List<GameMember> _othersOf(Game game) => [
  for (final m in game.participants)
    if (m.id != kMeId && !m.deleted) m,
];

/// Every other live player of the game with the player's thumbs for them
/// (until 7 days after the end) and a menu with "Didn't show up" (until 48
/// hours after) and "Report". The server holds the windows too.
class _OtherPlayers extends ConsumerWidget {
  const _OtherPlayers({required this.game, required this.others, required this.now});

  final Game game;
  final List<GameMember> others;

  /// Venue wall-clock time.
  final DateTime now;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    // A vote moves the player's sportsmanship on their profile.
    if (await runGameAction(context, ref, action) && context.mounted) ref.invalidate(playerProfileProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final mine = game.afterGame ?? const AfterGame();
    final votesOpen = canVote(game, now);
    final noShowOpen = canReportNoShow(game, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.afterGameRate, style: AppText.muted),
        for (final m in others)
          _OtherPlayerRow(
            key: ValueKey('after-game-${m.id}'),
            id: m.id,
            name: memberName(l, game, m.id),
            vote: mine.myVotes[m.id],
            markedNoShow: mine.myNoShows.contains(m.id),
            onVote: votesOpen
                ? (up) => _run(
                    context,
                    ref,
                    () => ref.read(gameRepositoryProvider).vote(game.id, m.id, mine.myVotes[m.id] == up ? null : up),
                  )
                : null,
            onNoShow: noShowOpen
                ? () => _run(
                    context,
                    ref,
                    () => ref
                        .read(gameRepositoryProvider)
                        .reportNoShow(game.id, m.id, reported: !mine.myNoShows.contains(m.id)),
                  )
                : null,
            onReport: () => showReportSheet(context, targetId: m.id, name: memberName(l, game, m.id), gameId: game.id),
          ),
      ],
    );
  }
}

class _OtherPlayerRow extends StatelessWidget {
  const _OtherPlayerRow({
    super.key,
    required this.id,
    required this.name,
    required this.vote,
    required this.markedNoShow,
    required this.onVote,
    required this.onNoShow,
    required this.onReport,
  });

  final String id;
  final String name;

  /// The player's thumbs for them: true up, false down, null none.
  final bool? vote;
  final bool markedNoShow;

  /// Tapping the thumb already given takes it back. Null once votes closed.
  final void Function(bool up)? onVote;

  /// Null once "Didn't show up" is closed.
  final VoidCallback? onNoShow;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final onVote = this.onVote;
    final onNoShow = this.onNoShow;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          InitialAvatar(name: name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            key: ValueKey('vote-up-$id'),
            tooltip: l.voteUp,
            isSelected: vote == true,
            icon: const Icon(Icons.thumb_up_alt_outlined),
            selectedIcon: const Icon(Icons.thumb_up_alt, color: AppColors.primaryDark),
            onPressed: onVote == null ? null : () => onVote(true),
          ),
          IconButton(
            key: ValueKey('vote-down-$id'),
            tooltip: l.voteDown,
            isSelected: vote == false,
            icon: const Icon(Icons.thumb_down_alt_outlined),
            selectedIcon: const Icon(Icons.thumb_down_alt, color: AppColors.error),
            onPressed: onVote == null ? null : () => onVote(false),
          ),
          PopupMenuButton<String>(
            key: ValueKey('player-menu-$id'),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => action == _noShow ? onNoShow?.call() : onReport(),
            itemBuilder: (context) => [
              if (onNoShow != null)
                CheckedPopupMenuItem(
                  key: const ValueKey('menu-no-show'),
                  value: _noShow,
                  checked: markedNoShow,
                  child: Text(l.noShowAction),
                ),
              PopupMenuItem(key: const ValueKey('menu-report'), value: _report, child: Text(l.reportAction)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The menu entries of a player row.
const _noShow = 'no_show';
const _report = 'report';

/// Enter the score, or the score with what the player can do about it.
class _ScoreBlock extends ConsumerWidget {
  const _ScoreBlock({required this.game, required this.now});

  final Game game;

  /// Venue wall-clock time.
  final DateTime now;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    // My rating moves once a score is confirmed.
    if (await runGameAction(context, ref, action) && context.mounted) refreshSports(ref);
  }

  Future<void> _dispute(BuildContext context, WidgetRef ref, MatchResult result) async {
    final reason = await _askDisputeReason(context);
    if (reason == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(gameRepositoryProvider).disputeScore(result.id, reason: reason));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final result = game.result;
    final open = now.isBefore(game.end.add(kScoreOpenFor));

    if (result == null) {
      if (!open) return _StatusLine(text: l.scoreEntryClosed, icon: Icons.lock_outline_rounded);
      final mayEnter = game.myStatus == MyGameStatus.host || !now.isBefore(game.end.add(kScoreHostOnlyFor));
      if (!mayEnter) return _StatusLine(text: l.scoreHostEnters, icon: Icons.schedule_rounded);
      return FilledButton.icon(
        key: const ValueKey('score-enter'),
        onPressed: () => showScoreSheet(context, game),
        icon: const Icon(Icons.scoreboard_outlined),
        label: Text(l.scoreEnter),
      );
    }

    final inResult = result.sideA.contains(kMeId) || result.sideB.contains(kMeId);
    final children = <Widget>[ScoreBoard(game: game, result: result), const SizedBox(height: 12)];
    switch (result.status) {
      case ResultStatus.pending:
        final enteredByMe = result.enteredBy == kMeId;
        final waiting = enteredByMe || result.confirmedBy.contains(kMeId);
        children.add(
          _StatusLine(
            text: inResult && waiting ? l.scoreWaitingOtherSide : l.scoreAwaiting,
            icon: Icons.hourglass_empty_rounded,
          ),
        );
        if (enteredByMe && open) {
          children.addAll([
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('score-edit'),
              onPressed: () => showScoreSheet(context, game),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.scoreEdit),
            ),
          ]);
        } else if (inResult && !waiting) {
          children.addAll([
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('score-dispute'),
                    onPressed: () => _dispute(context, ref, result),
                    child: Text(l.scoreDispute, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('score-confirm'),
                    onPressed: () =>
                        _run(context, ref, () => ref.read(gameRepositoryProvider).confirmScore(result.id)),
                    child: Text(l.scoreConfirm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ]);
        }
      case ResultStatus.confirmed:
        children.add(_StatusLine(text: l.scoreConfirmedLabel, icon: Icons.check_circle_outline_rounded));
        for (final id in [...result.sideA, ...result.sideB]) {
          if (result.changes[id] case final change?) {
            children.add(_ChangeTile(game: game, playerId: id, change: change));
          }
        }
      case ResultStatus.disputed:
        children.add(_StatusLine(text: l.scoreDisputedLabel, icon: Icons.gavel_rounded, error: true));
      case ResultStatus.voided:
        children.add(_StatusLine(text: l.scoreVoidedLabel, icon: Icons.block_rounded, error: true));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// The two sides with their games per set; the winning side in bold.
class ScoreBoard extends StatelessWidget {
  const ScoreBoard({super.key, required Game this.game, required this.result}) : names = null;

  /// For a screen that has no [Game] of the result: the names by player id.
  const ScoreBoard.named({super.key, required Map<String, String> this.names, required this.result}) : game = null;

  final Game? game;
  final Map<String, String>? names;
  final MatchResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // From [names]: a missing or empty name is a deleted account's.
    String nameOf(String id) {
      final names = this.names;
      if (names == null) return memberName(l, game!, id);
      final name = names[id];
      return name == null || name.isEmpty ? l.deletedPlayer : name;
    }

    Widget side(List<String> ids, bool a) {
      final won = result.winner == (a ? MatchWinner.a : MatchWinner.b);
      final style = won ? AppText.bodyStrong : AppText.body;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [for (final id in ids) nameOf(id)].join(', '),
                style: style,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final (x, y) in result.sets)
              SizedBox(
                width: 30,
                child: Text('${a ? x : y}', textAlign: TextAlign.center, style: style),
              ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('score-board'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [side(result.sideA, true), const Divider(height: 1), side(result.sideB, false)],
      ),
    );
  }
}

/// A player's name as the game knows it: "You", "Deleted player", or the name.
String memberName(AppLocalizations l, Game game, String id) {
  if (id == kMeId) return l.you;
  final member = game.participants.where((m) => m.id == id).firstOrNull;
  if (member == null) return '';
  return playerName(l, member.name, deleted: member.deleted);
}

/// One player's rating before and after a confirmed result.
class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.game, required this.playerId, required this.change});

  final Game game;
  final String playerId;
  final RatingChange change;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final name = memberName(l, game, playerId);
    final delta = change.delta;
    final deleted = playerId != kMeId && (game.participants.where((m) => m.id == playerId).firstOrNull?.deleted ?? false);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          InitialAvatar(name: name, size: 34, deleted: deleted),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(
            '${formatRating(change.oldRating)} → ${formatRating(change.newRating)}',
            key: ValueKey('rating-change-$playerId'),
            style: AppText.body,
          ),
          const SizedBox(width: 8),
          Pill(
            text: '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
            color: delta < 0 ? AppColors.errorSoft : AppColors.primarySoft,
            onColor: delta < 0 ? AppColors.error : AppColors.primaryDark,
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.icon, this.error = false});

  final String text;
  final IconData icon;
  final bool error;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: error ? AppColors.error : AppColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: error ? AppText.bodyStrong.copyWith(color: AppColors.error) : AppText.muted)),
    ],
  );
}

/// The optional reason for a dispute; null when the player backs out.
Future<String?> _askDisputeReason(BuildContext context) =>
    showDialog<String>(context: context, builder: (context) => const _DisputeDialog());

class _DisputeDialog extends StatefulWidget {
  const _DisputeDialog();

  @override
  State<_DisputeDialog> createState() => _DisputeDialogState();
}

class _DisputeDialogState extends State<_DisputeDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return AlertDialog(
      title: Text(l.scoreDisputeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.scoreDisputeMsg),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('score-dispute-reason'),
            controller: _reason,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(labelText: l.scoreDisputeReason),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.cancel)),
        FilledButton(
          key: const ValueKey('score-dispute-send'),
          onPressed: () => Navigator.of(context).pop(_reason.text),
          child: Text(l.scoreDispute),
        ),
      ],
    );
  }
}
