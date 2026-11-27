import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/competitive.dart';
import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/rating_pill.dart';
import '../common/widgets.dart';
import 'questionnaire_sheet.dart';

/// "My sports" (design §5.1): every active sport with a switch. A simple sport
/// takes a level 1–5, a rated one (padel, tennis) the questionnaire.
class MySportsScreen extends ConsumerStatefulWidget {
  const MySportsScreen({super.key});

  @override
  ConsumerState<MySportsScreen> createState() => _MySportsScreenState();
}

class _MySportsScreenState extends ConsumerState<MySportsScreen> {
  /// The sport being written, so its switch cannot be tapped twice.
  String? _busy;

  /// Runs a write to the player's sports and refreshes what shows them.
  Future<void> _write(String sportId, Future<void> Function() action) async {
    final l = context.l;
    setState(() => _busy = sportId);
    try {
      await action();
      refreshSports(ref);
    } on JoinException catch (e) {
      if (mounted) showMessage(context, joinErrorText(l, e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _pickLevel(Sport sport, int? current) async {
    final l = context.l;
    final picked = await showOptionSheet(
      context,
      title: l.pickLevelTitle(sport.name.resolve(context.lang)),
      options: {for (var n = 1; n <= 5; n++) '$n': l.level(n)},
      current: current == null ? null : '$current',
    );
    if (picked == null || !mounted) return;
    await _write(sport.id, () => ref.read(socialRepositoryProvider).setSport(sport.id, level: int.parse(picked)));
  }

  Future<void> _toggle(Sport sport, MySport? mine, bool on) async {
    if (!on) {
      await _write(sport.id, () => ref.read(socialRepositoryProvider).removeSport(sport.id));
    } else if (sport.competitiveRating) {
      // The questionnaire saves the sport itself.
      await showQuestionnaire(context, sport);
    } else {
      await _pickLevel(sport, mine?.level);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final sports = ref.watch(sportsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/profile')),
        title: Text(l.mySports),
      ),
      body: AsyncBody(
        value: sports,
        builder: (sports) => AsyncBody(
          value: ref.watch(mySportsProvider),
          builder: (mine) => ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(l.mySportsHint, style: AppText.muted),
              ),
              SectionCard(
                title: l.mySports,
                contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    for (final (i, sport) in sports.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _SportRow(
                        sport: sport,
                        mine: mine.where((s) => s.sportId == sport.id).firstOrNull,
                        busy: _busy == sport.id,
                        onToggle: (mySport, on) => _toggle(sport, mySport, on),
                        onLevel: (current) => _pickLevel(sport, current),
                        onRetake: () => showQuestionnaire(context, sport),
                      ),
                    ],
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

class _SportRow extends StatelessWidget {
  const _SportRow({
    required this.sport,
    required this.mine,
    required this.busy,
    required this.onToggle,
    required this.onLevel,
    required this.onRetake,
  });

  final Sport sport;

  /// Null while the sport is off.
  final MySport? mine;
  final bool busy;
  final void Function(MySport? mine, bool on) onToggle;
  final ValueChanged<int?> onLevel;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final mine = this.mine;
    final rating = mine?.rating;
    // A simple sport's level changes from its row.
    final changeLevel = mine != null && !sport.competitiveRating && !busy ? () => onLevel(mine.level) : null;

    return InkWell(
      onTap: changeLevel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SportBadge(sportId: sport.id, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sport.name.resolve(context.lang), style: manrope(15.5, 700)),
                  if (mine != null) ...[
                    const SizedBox(height: 4),
                    if (rating != null)
                      RatingPill(rating, showGames: true)
                    else
                      Text(levelOrRating(context, sport, level: mine.level), style: AppText.muted),
                  ],
                  if (mine != null && mine.canRetake)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('sport-retake-${sport.id}'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: busy ? null : onRetake,
                        child: Text(l.retakeQuestionnaire),
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              key: ValueKey('sport-switch-${sport.id}'),
              value: mine != null,
              onChanged: busy ? null : (on) => onToggle(mine, on),
            ),
          ],
        ),
      ),
    );
  }
}
