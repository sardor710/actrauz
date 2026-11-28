import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';
import '../tournaments/bracket_view.dart';
import '../tournaments/tournament_tools.dart';
import 'match_tools.dart';
import 'score_sheet.dart';

/// The manager's Scores tab (M8a design §7.3–§7.5, §11): every match of the
/// published draws in play order. Tapping one enters its score, or corrects
/// it; an entry's menu withdraws it from the draw.
class ScoresTab extends ConsumerStatefulWidget {
  const ScoresTab({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<ScoresTab> createState() => _ScoresTabState();
}

class _ScoresTabState extends ConsumerState<ScoresTab> with AutomaticKeepAliveClientMixin {
  String get tournamentId => widget.tournamentId;

  @override
  bool get wantKeepAlive => true;

  bool _busy = false;

  Future<void> _withdraw(ManagedMatch m, String registrationId) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => ClosesOnAccountChange(
        child: AlertDialog(
          title: Text(l.withdrawConfirmTitle),
          content: Text('${entryName(l, m.draw, registrationId)}\n\n${l.withdrawConfirmText}'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
            FilledButton(
              key: const ValueKey('confirm-dialog-ok'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.withdrawAction),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    await runTournamentAction(
      context,
      ref,
      () => ref.read(organizerRepositoryProvider).withdraw(registrationId),
      organizer: true,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l;
    final bracketValue = ref.watch(bracketProvider(tournamentId));

    return KeyedSubtree(
      key: const ValueKey('manage-scores'),
      child: AsyncBody(
        value: ref.watch(tournamentProvider(tournamentId)),
        onRetry: () => ref.invalidate(tournamentProvider(tournamentId)),
        errorText: (error) => organizerErrorText(l, error),
        canRetry: (error) => !(error is TournamentException && error.error == TournamentError.notFound),
        builder: (tournament) {
          // Kept through a failed refresh; never another account's.
          final bracket = currentData(bracketValue);
          if (bracket == null) {
            return bracketLoadState(context, bracketValue, () => ref.invalidate(bracketProvider(tournamentId)));
          }
          if (!bracket.organizer) return EmptyState(icon: Icons.lock_outline_rounded, text: l.notOrganizer);
          return _body(context, tournament, bracket);
        },
      ),
    );
  }

  Widget _body(BuildContext context, Tournament tournament, TournamentBracket bracket) {
    final l = context.l;
    final matches = managedMatches(tournament, bracket)..sort(playOrder);
    // Sets or one score per side: not known until the sports have loaded.
    final sports = ref.watch(sportsProvider).valueOrNull;
    final rated = sports != null && isRatedSport(sports, tournament.sportId);
    final now = tournamentNow(ref, tournament.cityId);
    final empty = !bracket.draws.any((d) => d.published)
        ? l.scheduleNoDraws
        : matches.isEmpty
        ? l.scoresEmpty
        : null;

    return RefreshIndicator(
      onRefresh: () => pullToReload(context, ref.refresh(bracketProvider(tournamentId).future)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (empty != null)
            EmptyState(icon: Icons.scoreboard_outlined, text: empty)
          else
            for (final m in matches) ...[
              _ScoreRow(
                match: m,
                now: now,
                onTap: m.scorable && !_busy && sports != null
                    ? () => showMatchScoreSheet(context, m, rated: rated)
                    : null,
                onWithdraw: _busy ? null : (registrationId) => _withdraw(m, registrationId),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

/// The bracket while it has no data the tab may show: a spinner, or its
/// error with Try again.
Widget bracketLoadState(BuildContext context, AsyncValue<TournamentBracket> value, VoidCallback retry) {
  if (value.isLoading || !value.hasError) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      EmptyState(icon: Icons.error_outline, text: organizerErrorText(context.l, value.error!)),
      OutlinedButton(key: const ValueKey('async-retry'), onPressed: retry, child: Text(context.l.tryAgain)),
    ],
  );
}

/// One match: where it stands in the draw, the match card, a clash warning,
/// and a menu to withdraw either entry.
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.match, required this.now, required this.onTap, required this.onWithdraw});

  final ManagedMatch match;
  final DateTime now;
  final VoidCallback? onTap;
  final ValueChanged<String>? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final m = match.match;
    final finished = match.draw.finished;
    // Entries that can still leave: known, not withdrawn, the category not over.
    final withdrawable = [
      for (final id in [m.sideA, m.sideB])
        if (id != null &&
            !finished &&
            !(match.draw.entries.where((e) => e.registrationId == id).firstOrNull?.withdrawn ?? true))
          id,
    ];

    return InkWell(
      key: ValueKey('score-match-${m.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  matchStageText(l, context.lang, match),
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (withdrawable.isNotEmpty)
                SizedBox(
                  height: 32,
                  child: PopupMenuButton<String>(
                    key: ValueKey('match-menu-${m.id}'),
                    tooltip: l.matchActions,
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                    enabled: onWithdraw != null,
                    onSelected: (id) => onWithdraw?.call(id),
                    itemBuilder: (context) => [
                      for (final id in withdrawable)
                        PopupMenuItem(
                          key: ValueKey('withdraw-$id'),
                          value: id,
                          child: Text(
                            l.withdrawEntry(entryName(l, match.draw, id)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          MatchCard(match: m, draw: match.draw, now: now),
          if (m.clash) ClashNote(key: ValueKey('scores-clash-${m.id}')),
        ],
      ),
    );
  }
}
