import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/brackets.dart';
import '../../domain/tournaments.dart';
import '../../l10n/gen/app_localizations.dart';
import '../common/formatters.dart';
import '../tournaments/bracket_view.dart';

/// What the manager's Schedule and Scores tabs share: the published matches
/// of a tournament with their category, and how one is named.

/// A match of a published draw, with the draw and the category it is in.
class ManagedMatch {
  const ManagedMatch({required this.match, required this.draw, required this.category, required this.categoryOrder});

  final TournamentMatch match;
  final CategoryDraw draw;
  final TournamentCategory category;

  /// The category's place in the tournament, for ordering.
  final int categoryOrder;

  String get id => match.id;

  /// Both sides known and not a bye or a match nobody won: it can be scored.
  bool get scorable =>
      match.sideA != null &&
      match.sideB != null &&
      match.outcome != MatchOutcome.bye &&
      match.outcome != MatchOutcome.none;

  /// Not done yet: it can get a court and a time.
  bool get schedulable => match.status != MatchStatus.done;
}

/// Every match of the tournament's published draws that is or will be
/// played: byes and slots nobody fills are left out.
List<ManagedMatch> managedMatches(Tournament tournament, TournamentBracket bracket) => [
  for (final (i, category) in tournament.categories.indexed)
    if (bracket.draw(category.id) case final draw? when draw.published)
      for (final m in draw.matches)
        if (m.outcome != MatchOutcome.bye && !(m.status != MatchStatus.done && (m.aEmpty || m.bEmpty)))
          ManagedMatch(match: m, draw: draw, category: category, categoryOrder: i),
];

/// Play order: scheduled time (none last), then group matches before the
/// knockout, then round, category and position.
int playOrder(ManagedMatch x, ManagedMatch y) {
  final a = x.match, b = y.match;
  if (a.startsAt != b.startsAt) {
    if (a.startsAt == null) return 1;
    if (b.startsAt == null) return -1;
    final c = a.startsAt!.compareTo(b.startsAt!);
    if (c != 0) return c;
  }
  for (final c in [
    a.stage.index.compareTo(b.stage.index),
    a.round.compareTo(b.round),
    x.categoryOrder.compareTo(y.categoryOrder),
    a.position.compareTo(b.position),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}

/// "Men's pairs · Semi-finals" or "Men's pairs · Group A".
String matchStageText(AppLocalizations l, String lang, ManagedMatch m) {
  final match = m.match;
  final String stage;
  if (match.stage == MatchStage.group) {
    final group = m.draw.groups.where((g) => g.id == match.groupId).firstOrNull;
    stage = group == null ? l.roundNumber(match.round) : l.groupLabel(group.label);
  } else {
    final rounds = m.draw.matches
        .where((x) => x.stage == MatchStage.knockout)
        .fold<int>(0, (max, x) => x.round > max ? x.round : max);
    stage = roundLabel(l, match.round, rounds);
  }
  return '${m.category.name.resolve(lang)} · $stage';
}

/// "Aziz – Bekzod" (pairs: "A / B – C / D").
String matchSidesText(AppLocalizations l, ManagedMatch m) =>
    '${entryName(l, m.draw, m.match.sideA)} – ${entryName(l, m.draw, m.match.sideB)}';

/// A player of the match is in another match at an overlapping time.
class ClashNote extends StatelessWidget {
  const ClashNote({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(context.l.matchClash, style: manrope(12, 700, color: AppColors.error)),
        ),
      ],
    ),
  );
}

/// The `yyyy-mm-dd` of a wall-clock date, for keys.
String dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
