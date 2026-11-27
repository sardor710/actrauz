import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/sample/sample_data.dart' show kMeId;
import '../../domain/brackets.dart';
import '../common/formatters.dart';
import 'bracket_view.dart';

/// The signed-in player's entry among [match]'s sides in [draw], if any.
Side? mySide(CategoryDraw draw, TournamentMatch match) {
  bool mine(String? id) =>
      id != null && draw.entries.any((e) => e.registrationId == id && e.players.any((p) => p.id == kMeId));
  if (mine(match.sideA)) return Side.a;
  if (mine(match.sideB)) return Side.b;
  return null;
}

/// "Your next match": the opponent, the court and time (or the place note
/// without a venue). [subtitle] names the tournament and category where the
/// page does not (My tournaments).
class NextMatchCard extends StatelessWidget {
  const NextMatchCard({
    super.key,
    required this.match,
    required this.draw,
    required this.now,
    this.subtitle,
    this.onTap,
  });

  final TournamentMatch match;
  final CategoryDraw draw;

  /// Venue wall-clock.
  final DateTime now;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final m = match;
    final opponent = switch (mySide(draw, m)) {
      Side.a => entryName(l, draw, m.sideB),
      Side.b => entryName(l, draw, m.sideA),
      _ => '${entryName(l, draw, m.sideA)} – ${entryName(l, draw, m.sideB)}',
    };
    final when = matchWhen(l, context.lang, m, now) ?? l.matchTimeTbd;

    return Card(
      key: const ValueKey('next-match'),
      color: AppColors.primarySoft,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.sports_tennis_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.nextMatchTitle, style: manrope(12, 800, color: AppColors.primaryDark)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 4),
                    Text(l.versusNames(opponent), style: AppText.cardTitle),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 16, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(when, style: AppText.bodyStrong)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
