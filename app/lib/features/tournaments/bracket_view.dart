import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../l10n/gen/app_localizations.dart';
import '../common/formatters.dart';
import 'group_table.dart';

/// What players see of a published draw (M8a design §10): the bracket with
/// its rounds side by side, the group tables, and the winner once the
/// category is done.

/// The players of [registrationId] in [draw], "Aziz / Bekzod" for a pair;
/// "To be decided" while the side is not known yet.
String entryName(AppLocalizations l, CategoryDraw draw, String? registrationId) {
  if (registrationId == null) return l.matchTbd;
  final entry = draw.entries.where((e) => e.registrationId == registrationId).firstOrNull;
  if (entry == null || entry.players.isEmpty) return l.matchTbd;
  return entry.players.map((p) => playerName(l, p.name, deleted: p.deleted)).join(' / ');
}

/// "6–2 6–3", from side a's point of view; empty without sets.
String matchScore(TournamentMatch m) =>
    [for (final set in m.sets ?? const <List<int>>[]) '${set[0]}–${set[1]}'].join(' ');

/// The outcome when it is more than a plain score.
String? outcomeLabel(AppLocalizations l, TournamentMatch m) => switch (m.outcome) {
  MatchOutcome.walkover => l.outcomeWalkover,
  MatchOutcome.retired => l.outcomeRetired,
  MatchOutcome.decider => l.outcomeDecider,
  MatchOutcome.none => l.outcomeNone,
  _ => null,
};

/// "Sat, 5 Dec, 10:00 · Court 1", the place note without a venue, or null
/// when the match has no time yet.
String? matchWhen(AppLocalizations l, String lang, TournamentMatch m, DateTime now) {
  final start = m.startsAt;
  final where = m.courtName?.resolve(lang) ?? m.placeNote;
  final parts = [
    if (start != null) '${dayLabel(l, lang, start, now)}, ${hm(start)}',
    if (where != null && where.isNotEmpty) where,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "Final", "Semi-finals", "Quarter-finals", else "Round 1".
String roundLabel(AppLocalizations l, int round, int rounds) => switch (rounds - round) {
  0 => l.roundFinal,
  1 => l.roundSemiFinals,
  2 => l.roundQuarterFinals,
  _ => l.roundNumber(round),
};

/// A category's "Draw" section: the winner and runner-up once it is done,
/// the group tables, then the knockout bracket.
class CategoryDrawSection extends StatelessWidget {
  const CategoryDrawSection({super.key, required this.draw, required this.now});

  final CategoryDraw draw;

  /// Venue wall-clock, for "Today" and "Tomorrow".
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final winner = draw.finished ? draw.winner : null;
    final runnerUp = draw.finished ? draw.runnerUp : null;
    final knockout = draw.matches.any((m) => m.stage == MatchStage.knockout);

    Widget podium(Key key, IconData icon, Color color, String label, String registrationId) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text('$label: ', style: AppText.caption),
          Expanded(child: Text(entryName(l, draw, registrationId), style: AppText.bodyStrong)),
        ],
      ),
    );

    return Column(
      key: ValueKey('draw-${draw.categoryId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.drawTitle.toUpperCase(), style: AppText.sectionTitle),
        const SizedBox(height: 10),
        if (winner != null)
          podium(const ValueKey('draw-winner'), Icons.emoji_events_rounded, AppColors.amber, l.drawWinner, winner),
        if (runnerUp != null)
          podium(
            const ValueKey('draw-runner-up'),
            Icons.workspace_premium_outlined,
            AppColors.muted,
            l.drawRunnerUp,
            runnerUp,
          ),
        for (final group in draw.groups) ...[GroupTable(group: group, draw: draw), const SizedBox(height: 12)],
        if (knockout) BracketView(draw: draw, now: now),
      ],
    );
  }
}

/// The knockout rounds side by side, scrolling sideways. Byes are not drawn.
class BracketView extends StatelessWidget {
  const BracketView({super.key, required this.draw, required this.now});

  final CategoryDraw draw;
  final DateTime now;

  static const cardWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final knockout = draw.matches.where((m) => m.stage == MatchStage.knockout).toList();
    if (knockout.isEmpty) return const SizedBox.shrink();
    final rounds = knockout.map((m) => m.round).reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      key: ValueKey('bracket-${draw.categoryId}'),
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var round = 1; round <= rounds; round++)
            Padding(
              padding: EdgeInsets.only(right: round == rounds ? 0 : 12),
              child: SizedBox(
                width: cardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roundLabel(l, round, rounds),
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    for (final m
                        in knockout.where((m) => m.round == round && m.outcome != MatchOutcome.bye).toList()
                          ..sort((a, b) => a.position.compareTo(b.position)))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: MatchCard(match: m, draw: draw, now: now),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One match: both entries (the winner in bold), the score or outcome, and
/// the court and time. [header] goes above, e.g. the tournament's title in
/// My matches.
class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, required this.draw, required this.now, this.header});

  final TournamentMatch match;
  final CategoryDraw draw;
  final DateTime now;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final m = match;
    final score = matchScore(m);
    final outcome = outcomeLabel(l, m);
    final when = matchWhen(l, context.lang, m, now);

    Widget side(String? id, bool empty, Side mine) {
      final won = m.winner == mine;
      return Row(
        children: [
          Expanded(
            child: Text(
              empty ? l.matchTbd : entryName(l, draw, id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: manrope(13.5, won ? 800 : 600, color: id == null ? AppColors.muted : AppColors.ink),
            ),
          ),
          if (won) const Icon(Icons.check_rounded, size: 16, color: AppColors.primaryDark),
        ],
      );
    }

    return Container(
      key: ValueKey('match-${m.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            Text(header!, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
          ],
          side(m.sideA, m.aEmpty, Side.a),
          const SizedBox(height: 4),
          side(m.sideB, m.bEmpty, Side.b),
          if (score.isNotEmpty || outcome != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                if (score.isNotEmpty) Text(score, style: manrope(13, 800, color: AppColors.primaryDark)),
                if (outcome != null) Text(outcome, style: AppText.caption),
              ],
            ),
          ],
          if (when != null) ...[
            const SizedBox(height: 6),
            Text(when, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
