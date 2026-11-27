import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../profile/questionnaire_sheet.dart';
import 'formatters.dart';
import 'widgets.dart';

// How a rating (padel, tennis; design 2026-11-27-actra-m7-competitive §5.3)
// reads anywhere in the app: two decimals for a player's rating, one for a
// range.

/// A player's rating with two decimals: 3.47.
String formatRating(double rating) => rating.toStringAsFixed(2);

/// One end of a rating range with one decimal, truncated, not rounded: a range
/// converted from levels (2.00–4.99) ends at 4.9, never 5.0, which would
/// suggest a 5.0 player fits. The tiny epsilon keeps 4.5 (or 0.3 × 10) from
/// falling to the tenth below through floating-point error.
String formatRatingBound(double value) => ((value * 10 + 1e-9).floor() / 10).toStringAsFixed(1);

/// "3.0–4.5": every place that shows a rating range uses this.
String formatRatingRange(double min, double max) => '${formatRatingBound(min)}–${formatRatingBound(max)}';

/// What a game or Game Request asks for: its rating range in a rated sport,
/// otherwise "Level 2–4".
String gameRangeText(
  AppLocalizations l, {
  required int minLevel,
  required int maxLevel,
  double? minRating,
  double? maxRating,
}) =>
    minRating != null && maxRating != null ? formatRatingRange(minRating, maxRating) : l.levelRange(minLevel, maxLevel);

/// The level of a player in [sport] as text: the rating in a rated sport
/// ("3.47 · provisional" while provisional, "No rating yet" without one),
/// otherwise "Level 3".
String levelOrRating(BuildContext context, Sport sport, {int? level, SportRating? rating}) {
  final l = context.l;
  if (!sport.competitiveRating) return l.level(level ?? 1);
  if (rating == null) return l.noRatingYet;
  final value = formatRating(rating.rating);
  return rating.provisional ? l.ratingWithProvisional(value) : value;
}

/// A player in a game or Game Request: their rating when it is in a rated
/// sport (the server sends one there), otherwise "Level 3".
String memberLevel(BuildContext context, GameMember member) {
  final l = context.l;
  final rating = member.rating;
  if (rating == null) return l.level(member.level);
  final value = formatRating(rating);
  return member.provisional ? l.ratingWithProvisional(value) : value;
}

/// "3.47" and, while the player has fewer than 10 rated games, a
/// "Provisional" tag; with [showGames] also the rated-games count.
class RatingPill extends StatelessWidget {
  const RatingPill(this.rating, {super.key, this.showGames = false});

  final SportRating rating;
  final bool showGames;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Pill(
          text: formatRating(rating.rating),
          icon: Icons.bar_chart_rounded,
          color: AppColors.primarySoft,
          onColor: AppColors.primaryDark,
        ),
        if (rating.provisional) Pill(text: l.ratingProvisional, color: AppColors.amberSoft),
        if (showGames) Text(l.ratedGames(rating.ratedGames), style: AppText.caption),
      ],
    );
  }
}

/// Before creating or joining a game in a rated [sport]: a player with no
/// rating there answers the questionnaire first. Returns false if they close
/// it without a rating. Anything else (a simple sport, a rating already, the
/// player's sports not loading) returns true: the server has the last word.
Future<bool> ensureRated(BuildContext context, WidgetRef ref, Sport sport) async {
  if (!sport.competitiveRating) return true;
  final List<MySport> mine;
  try {
    mine = await ref.read(mySportsProvider.future);
  } catch (_) {
    return true;
  }
  if (mine.any((s) => s.sportId == sport.id && s.rating != null)) return true;
  if (!context.mounted) return false;
  return showQuestionnaire(context, sport);
}
