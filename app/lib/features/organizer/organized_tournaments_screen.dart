import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/tournaments.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/widgets.dart';
import '../tournaments/tournament_tools.dart';

/// "Tournaments I run" (M8a design §5): the active tournaments the player is
/// a named organiser of, earliest first; each opens its manager. Reloads on
/// opening and by pulling down; a failed reload keeps the list, and another
/// account never sees the previous one's.
class OrganizedTournamentsScreen extends ConsumerStatefulWidget {
  const OrganizedTournamentsScreen({super.key});

  @override
  ConsumerState<OrganizedTournamentsScreen> createState() => _OrganizedTournamentsScreenState();
}

class _OrganizedTournamentsScreenState extends ConsumerState<OrganizedTournamentsScreen> {
  @override
  void initState() {
    super.initState();
    if (!ref.exists(organizedTournamentsProvider)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(organizedTournamentsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/profile')),
        title: Text(l.tournamentsIRun),
      ),
      body: AsyncBody(
        value: ref.watch(organizedTournamentsProvider),
        onRetry: () => ref.invalidate(organizedTournamentsProvider),
        errorText: (error) => tournamentErrorText(l, error),
        builder: (tournaments) => RefreshIndicator(
          onRefresh: () => pullToReload(context, ref.refresh(organizedTournamentsProvider.future)),
          child: tournaments.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [EmptyState(icon: Icons.emoji_events_outlined, text: l.organizingEmpty)],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [for (final t in tournaments) _Row(tournament: t)],
                ),
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.tournament});

  final TournamentSummary tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final t = tournament;
    final now = tournamentNow(ref, t.cityId);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: ValueKey('organized-${t.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/tournaments/${t.id}/manage'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TournamentCover(
                id: t.id,
                sportId: t.sportId,
                coverUrl: t.coverUrl,
                colorSeed: t.colorSeed,
                width: 64,
                height: 64,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title.resolve(context.lang),
                      style: AppText.cardTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(datesText(l, context.lang, t.start, t.end, now), style: AppText.muted),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }
}
